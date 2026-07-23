---
phase: 02-in-container-triangulation-av1-vaapi
reviewed: 2026-07-23T12:00:00Z
depth: standard
files_reviewed: 2
files_reviewed_list:
  - scratch/repro/harness.sh
  - scratch/repro/lib.sh
findings:
  critical: 1
  warning: 6
  info: 5
  total: 12
status: issues_found
---

# Phase 2: Code Review Report

**Reviewed:** 2026-07-23T12:00:00Z
**Depth:** standard
**Files Reviewed:** 2 (`harness.sh` under review; `lib.sh` read as its sourced dependency to trace `run_encode`/`ff_bounded`/`gpu_clients`/cache paths)
**Status:** issues_found

## Summary

`harness.sh` is a safety-critical measurement instrument: it classifies encoded frames corrupt/clean via external-ffmpeg PSNR, runs 3-way concurrent GPU encodes with per-PID exit capture, gates every iteration on a paired av1_qsv immune control, and does content cross-matching with explicit threshold bands. The author has clearly invested in fail-closed behavior (empty/`inf` PSNR handling in `classify_corrupt`, MEASURE_FAILURE on failed frame extraction, WR-10 md5 non-empty guards, disk/reference preflights). Those defenses are largely sound and were traced end-to-end.

The review focused, as directed, on PSNR classification, threshold bands, concurrency/PID/exit handling, control-invalidation gating, fail-closed-on-empty behavior, and silent-failure paths that could produce a misleading measurement result.

One BLOCKER was found and confirmed against on-disk state: the content-origin cross-match candidate cache is keyed in a way that collides between the two encoders' data (`runs/` qsvencc vs `vaapi_runs/` av1_vaapi) and between smoke and full scans, so a corrupt frame can be silently compared against the wrong session's candidate frames — directly producing a misleading cross-session-swap verdict. Six warnings concern measurement integrity (n_actual over-counting weakening the degraded-batch guard), further cache under-scan paths, unbounded ffprobe stages, and a couple of fragile probe signals. The core corruption-fraction path (3-way encode -> PSNR -> 30 dB threshold -> control gating -> Wilson CI over `status==OK` rows) is otherwise correct.

## Critical Issues

### CR-01: Cross-match candidate cache key collides across encoders and scan modes -> corrupt frame compared against the wrong session's frames

**File:** `scratch/repro/harness.sh:1075` (`_ccm_cache_key`), `scratch/repro/harness.sh:1086-1108` (`_ccm_extract_candidates`)

**Issue:** The candidate-frame cache is global at `$W/crossmatch_cache/<cache_key>`, and the key is derived as:
```bash
_ccm_cache_key() { echo "$(basename "$(dirname "$obu")")_$(basename "$obu" .obu)"; }
```
This uses only the immediate parent directory name (`itNN`) plus the OBU basename (`cSCENE`). It therefore loses the grandparent that distinguishes the two encoders' trees:

- qsvencc historical scan reads `$W/runs/itNN/cSCENE.obu` -> key `itNN_cSCENE`
- av1_vaapi cross-match (Step 2b) reads `$W/vaapi_runs/itNN/cSCENE.obu` -> **key `itNN_cSCENE`** (identical)

`_ccm_extract_candidates` reuses any existing non-empty cache dir verbatim (lines 1089-1092). So whichever encoder runs its cross-match first populates `crossmatch_cache/itNN_cSCENE` from *its* pixels, and the other encoder then silently compares its corrupt frame against the wrong encoder's decoded frames. av1_vaapi and qsvencc/av1_qsv outputs are different pixels by construction (the harness itself stresses this in the Pitfall-6 comments at lines 296-300), so the reused cache scores low PSNR and yields a false `GENERIC GARBAGE (no cross-scene origin)` verdict — i.e. it can wrongly conclude there was no cross-session content swap, or wrongly confirm one. This is exactly the "silent-failure path that produces a misleading measurement result" this harness must not have, and it feeds the Phase-1 "Mechanism-vs-symptom NOTE closed?" conclusion (lines 1432-1442) and the av1_vaapi interpretation.

The same key weakness makes `--smoke` (which caps extraction to 15 frames, `max_candidates=15`, line 1373) poison the full scan: a smoke run populates `crossmatch_cache/itNN_cSCENE` with 15 frames, then a later full scan (`max_candidates=0`) reuses that 15-frame dir instead of extracting all frames — a silent under-scan that can miss the true matching candidate.

Confirmed against on-disk state: `crossmatch_cache/` currently contains dirs named `it04_c928`, `it05_c923`, ... with no encoder/tree component, so the collision is live, not hypothetical.

**Fix:** Make the cache identity encoder- and mode-unique. Include the grandparent tree and the candidate cap in the key, e.g.:
```bash
_ccm_cache_key() {
  local obu="$1" cap="${2:-full}"
  local tree; tree="$(basename "$(dirname "$(dirname "$obu")")")"   # runs | vaapi_runs
  echo "${tree}_$(basename "$(dirname "$obu")")_$(basename "$obu" .obu)_${cap}"
}
```
and thread the effective `max_candidates` (or a `full`/`smoke` tag) into the key so full and smoke never share a dir. Additionally, treat a cache dir as reusable only when a completeness sentinel is present (see WR-03), not merely non-empty.

## Warnings

### WR-01: `n_actual` counts failed iterations, silently weakening the "minimum-valid-iteration floor" and the control denominator

**File:** `scratch/repro/harness.sh:1660-1666` and `scratch/repro/harness.sh:1972-1976`; consumed at `scratch/repro/harness.sh:1776-1777, 1838` (vaapi degraded-batch floor)

**Issue:** `cmd_run_iter[_vaapi]` creates `result.csv` unconditionally at entry (`: > "$result_file"`, lines 666/870) and writes rows even on TIMEOUT / EXEC_FAILURE / CONTROL_INVALID early-returns. The batch loop then does `cmd_run_iter... || true; if [[ -f .../result.csv ]]; then n_actual++`. Because `result.csv` always exists after the call, **`n_actual` is incremented for every non-contaminated iteration including fully failed ones**. The WR-02 comment (lines 1663-1664) claims `n_actual` reflects "only iterations that actually produced usable measurement rows" — the implementation does not match that intent. The vaapi degraded-batch floor `degraded = n_actual < ceil(0.85*n_requested)` (lines 1776-1777) therefore fails to fire even when most iterations produced no valid measurement, and the printed `control_invalid/n_actual` uses an inflated denominator. The corruption fraction itself is unaffected (it independently uses `status=="OK"` rows via `n_ok`), so this is measurement-integrity/robustness rather than a wrong headline number.

**Fix:** Count `n_actual` from the iteration's actual outcome, not from file existence. e.g. capture `cmd_run_iter`'s return, or grep the produced `result.csv` for an `OK` (or non-failure) status row before incrementing:
```bash
cmd_run_iter "$iter_label" && n_actual=$((n_actual+1)) || true
# or: increment only if result.csv has any status==OK row
```
and reconcile the WR-02 comment with whichever definition is chosen.

### WR-02: `--smoke` 15-frame cache is reused by the full scan (under-scan)

**File:** `scratch/repro/harness.sh:1094-1100` with reuse gate at `scratch/repro/harness.sh:1089-1092`; `max_candidates` set at `scratch/repro/harness.sh:1373,1376`

**Issue:** A subset of CR-01 with a distinct root cause worth its own fix: `max_candidates` is not part of the cache identity, and the reuse gate only checks "dir exists and is non-empty." Running `--smoke` (cap 15) before the real full scan leaves a 15-frame cache that the full scan silently accepts as complete, so the full historical scan may compare against only the first 15 candidates and emit a false `GENERIC GARBAGE`/`NO VALID CANDIDATES` verdict for those iteration+scene pairs.

**Fix:** Fold the cap into the cache key (see CR-01 fix) so smoke and full never collide, or refuse to reuse a capped cache for a full scan.

### WR-03: Partial/interrupted candidate extraction is treated as a complete cache on the next run

**File:** `scratch/repro/harness.sh:1089-1108`

**Issue:** `_ccm_extract_candidates` returns an existing cache dir whenever it is non-empty (line 1089), and on a fresh extraction only checks `rc != 0 || dir empty` (line 1102). If a full extraction is interrupted (SIGINT, timeout via `ff_bounded`, disk-full) after writing some frames but before finishing, the dir is left non-empty and is accepted as complete on the next invocation, silently under-scanning. Given the documented multi-hour full scan, interruption is a realistic operating condition.

**Fix:** Write a completeness sentinel only after a clean extraction (e.g. `touch "$cache_dir/.complete"` after the `rc==0` check) and require that sentinel in the reuse gate; or extract into a temp dir and atomically `mv` into place on success.

### WR-04: PSNR-generation ffmpeg is timeout-bounded but several ffprobe decode stages are not

**File:** `scratch/repro/harness.sh:143-145` (`-count_frames`), `scratch/repro/harness.sh:377` (reorder CSV), `scratch/repro/harness.sh:393` (pix_fmt); contrast `ff_bounded` in `scratch/repro/lib.sh:83-85`

**Issue:** The harness deliberately wraps inline ffmpeg extraction/PSNR in `ff_bounded` (WR-09) so "a wedged GPU job can never block the whole harness with no time bound." But the ffprobe stages that fully decode media — `ffprobe -count_frames` over the reference OBU (line 143) and the reorder-probe decode of the probe mkv (line 377) — call `ffprobe` directly with no timeout. A wedged/looping decode on a corrupt or GPU-starved input would hang the harness unbounded, defeating the stated WR-09 guarantee at the reference/probe gate that runs before any measurement.

**Fix:** Route these through a bounded wrapper too, e.g. add `ffprobe_bounded() { timeout -k 10 "${ENCODE_TIMEOUT}" ffprobe "$@"; }` in `lib.sh` and use it for the `-count_frames`, reorder, and pix_fmt probes.

### WR-05: `cmd_probe` hardcodes `card2` for the GPU-driver fingerprint while the rest of the harness targets `renderD128`

**File:** `scratch/repro/harness.sh:91`

**Issue:** `gpu_driver="$(readlink -f /sys/class/drm/card2/device/driver ...)"` assumes the GPU is DRM `card2`. Every other GPU touchpoint (exclusivity check, cleanup) keys off `renderD128` (`lib.sh:38-45`). On a host where the render node maps to a different `cardN`, this line reports `gpu_driver: UNAVAILABLE` even though the GPU is present and working — a misleading environment fingerprint. Since `fingerprint.txt` is the attestation that this environment matches the affected host (D-08), a silently-wrong `UNAVAILABLE` degrades the reproduction claim's provenance.

**Fix:** Derive the card from the render node instead of hardcoding, e.g. resolve `/sys/class/drm/renderD128/device/driver` (the render node exposes the same `device/driver` symlink), or iterate `/sys/class/drm/card*/device/driver` and record the one whose `device` matches the renderD128 PCI device.

### WR-06: Reorder verdict depends on ffprobe silently dropping an invalid `dts` field

**File:** `scratch/repro/harness.sh:377,383`

**Issue:** Leg (a) requests `-show_entries frame=pts,dts,pkt_dts` and then compares `$1!=$2` (pts vs the second CSV column). The lengthy comment (lines 366-375) documents that ffprobe silently ignores the invalid `dts` token and emits a two-column `pts,pkt_dts` CSV, so `$2` is `pkt_dts`. This is a version-dependent behavior: on an ffprobe build where the requested field set yields a different column layout (or an empty column for an unresolved field), `$1!=$2` would compare the wrong pair and could flip the reorder verdict (e.g. an empty `$2` makes `pts!=""` always true -> false `ACTIVE`). The verdict feeds the D-02/D-03 triad caveat and the gated-escalation decision (lines 1844-1852), so a wrong verdict misleads the escalation call (though not the corruption fraction).

**Fix:** Request only fields you actually consume with unambiguous names — `-show_entries frame=pts_time,dts_time` (or `pkt_pts,pkt_dts`) — and assert the column count per row in awk (`NF==2`) before comparing, emitting `UNKNOWN` on any row that does not have exactly two numeric fields.

## Info

### IN-01: `scene_seek`/`scene_trim`/`scene_offset`/`scene_ref_*` lack the default-case guard used by their siblings

**File:** `scratch/repro/harness.sh:203-237`

**Issue:** `ctrl_frames`, `ctrl_ref_obu`, `vaapi_ref_obu`, etc. all have a `*) echo "unknown scene" >&2; return 1 ;;` arm, but `scene_seek`/`scene_trim`/`scene_offset`/`scene_ref_obu`/`scene_ref_png` silently `echo` nothing and return 0 for an unknown scene. Deviation from the convention the file establishes for its own lookup helpers. Currently unreachable (only 923/928/1129 are passed), so advisory only.
**Fix:** Add the same `*)` guard to these five lookups for consistency and defense-in-depth.

### IN-02: `control_clean` CSV column can hold `TIMEOUT`, outside its documented `0/1` schema

**File:** `scratch/repro/harness.sh:789-790, 973-974` (written into column 7 at lines 831-835 / 1018-1022)

**Issue:** The schema comment (lines 657/861) describes `control_clean` as a boolean, but on a control timeout the column is written as the string `TIMEOUT`. The Python summaries never parse column 7 (they key off `status`), so this is harmless today, but it is an out-of-schema value that a future consumer could mis-handle.
**Fix:** Normalize the column to `0` on timeout (the `status` column already records `CONTROL_INVALID`), or document `TIMEOUT` as a permitted third value.

### IN-03: No `set -o pipefail` despite many `cmd | awk`/`cmd | grep` pipelines

**File:** `scratch/repro/harness.sh:69` (`set -u` only)

**Issue:** Correctness of pipelines like `md5sum | awk`, `ffprobe | awk`, `df | awk` relies on per-site empty-string guards rather than pipefail. The author handles the load-bearing cases explicitly (WR-10 md5 guards, `|| echo ""` on ffprobe), so this is a defense-in-depth observation, not a live bug.
**Fix:** Consider `set -uo pipefail` at the top and keep the existing explicit guards; verify the `probe` subcommand's `|| echo UNAVAILABLE` sites still behave as intended under pipefail.

### IN-04: PSNR values are generated under `LC_ALL=C` but compared under the ambient locale

**File:** `scratch/repro/harness.sh:496` (generation forces `LC_ALL=C`) vs `scratch/repro/harness.sh:517` and control/determinism awk comparisons (no locale pin)

**Issue:** `psnr_of` pins `LC_ALL=C` so ffmpeg writes `.`-decimal PSNR, but the numeric awk comparisons in `classify_corrupt` and the control/determinism gates run in the ambient locale. In a comma-decimal locale, awk may truncate `15.74` to `15`. This is benign here only because every threshold is an integer (`<30`, `>=35`, `>=20`, `>=50`, `>=30`), so truncation never crosses a boundary — but it is a latent inconsistency.
**Fix:** Prefix the numeric awk invocations with `LC_ALL=C` as well, so generation and comparison share one locale.

### IN-05: `control_runs/itNN` is shared and overwritten between the qsvencc and av1_vaapi batches

**File:** `scratch/repro/harness.sh:663` (vaapi) and `scratch/repro/harness.sh:867` (qsvencc)

**Issue:** Both `cmd_run_iter` and `cmd_run_iter_vaapi` write their paired control into `$W/control_runs/it$n`. Running `run-batch` then `run-batch-vaapi` clobbers the earlier batch's per-iteration control artifacts for the same iteration number. `control_clean` is computed inline before the CSV is written, so the reported result is unaffected; only the retained on-disk control artifacts are overwritten (a debugging/audit-trail loss).
**Fix:** Namespace the control output dir per encoder (e.g. `control_runs/qsv/itNN` vs `control_runs/vaapi/itNN`), mirroring the `runs/` vs `vaapi_runs/` split.

---

_Reviewed: 2026-07-23T12:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
