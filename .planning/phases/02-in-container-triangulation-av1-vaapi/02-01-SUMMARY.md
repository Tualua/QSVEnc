---
phase: 02-in-container-triangulation-av1-vaapi
plan: 01
subsystem: testing
tags: [ffmpeg, vaapi, av1_vaapi, harness, bash, psnr, qsv]

# Dependency graph
requires:
  - phase: 01-harness-control-environment-fingerprinting
    provides: scratch/repro/harness.sh + lib.sh (qsvencc reproduction harness), the certified baseline (923/299 45.0%, 1129/299 40.0%, 928/96 0%, control 0/20)
provides:
  - vaapi_encode() -- full-HW ffmpeg VAAPI (av1_vaapi) command builder, mirroring ctrl_encode()
  - cmd_probe_vaapi / probe-vaapi subcommand -- D-02 empirical trigger-triad leg probe, writes vaapi_probe.txt
  - ensure_vaapi_reference() / cmd_reference_vaapi / reference-vaapi subcommand -- D-04/D-05 determinism-confirmed av1_vaapi self-reference for scenes 923/928/1129
  - vaapi_ref_obu / vaapi_ref_png scene lookups, distinct from the qsvencc reference filenames
  - live-confirmed fix for a broken ffprobe field name ("dts" silently drops; the real field is "pkt_dts") that would have produced a false-positive reorder verdict on every frame
affects: [02-02, 02-03, 02-04, 02-05]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Probe -> Run -> Caveat (D-02): empirically probe trigger-triad legs before trusting any concurrency result, never trust the encoder's own capability log line"
    - "PTS/pkt_dts equality (not pict_type) as the only valid AV1 B-frame/reorder verification signal"
    - "Distinct self-reference artifact sets per encoder (av1_vaapi vs qsvencc), never cross-reused"
    - "md5-first / >=50dB-PSNR-fallback determinism gate for a self-reference whose bit-determinism is not yet proven"

key-files:
  created: []
  modified:
    - scratch/repro/harness.sh

key-decisions:
  - "Fixed a broken ffprobe field-name assumption from 02-RESEARCH.md's documented probe command: the literal field 'dts' does not exist in this ffprobe build (silently dropped, no error) -- the real per-frame decode-timestamp field is 'pkt_dts'. Verified live: the documented 'frame=pts,dts' command produces a false ACTIVE reorder verdict on 100/100 frames; the corrected 'frame=pts,dts,pkt_dts' command (which ffprobe reduces to a real two-column pts,pkt_dts CSV) reproduces the research's claimed empirical result (0/100 mismatches, reorder UNSUPPORTED)."
  - "D-02 probe result on this Arc A380, live-confirmed: reorder UNSUPPORTED (0/100 pts==pkt_dts), P010 ACTIVE, HW-decode ACTIVE -> PARTIAL-TRIAD. Matches 02-RESEARCH.md's prediction exactly, now backed by a corrected/working probe implementation rather than the documented-but-broken one."
  - "Scene 923 av1_vaapi self-reference determinism was bit-identical (md5 match) on the first isolated two-run comparison -- the >=50dB PSNR fallback path was implemented per D-05 but not exercised this run (documented in code, not yet empirically triggered)."

patterns-established:
  - "Every new av1_vaapi helper follows the worker-function contract (echo ABORT >&2; return 1, never exit/die) -- only cmd_probe_vaapi and cmd_reference_vaapi (top-level cmd_* entries) may exit."

requirements-completed: [DIAG-02]

# Metrics
duration: 20min
completed: 2026-07-23
---

# Phase 2 Plan 1: av1_vaapi Command Builder + Capability Probe + Self-Reference Summary

**Extended `scratch/repro/harness.sh` with a full-HW `av1_vaapi` encode builder, a live-verified D-02 trigger-triad capability probe (PARTIAL-TRIAD: B-frame reorder UNSUPPORTED, P010 and HW-decode ACTIVE), and a determinism-confirmed `av1_vaapi` self-reference for all three hotspot scenes — while catching and fixing a broken ffprobe field-name assumption in the documented probe recipe that would have silently inverted the reorder verdict.**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-07-23T09:19:32Z (session start; harness edits + live GPU runs ~09:27-09:38Z)
- **Completed:** 2026-07-23T09:38:00Z
- **Tasks:** 2 completed
- **Files modified:** 1 (`scratch/repro/harness.sh`)

## Accomplishments

- `vaapi_encode()` builds the full-HW VAAPI pipeline (`-hwaccel vaapi -hwaccel_output_format vaapi` decode → `scale_vaapi=format=p010:extra_hw_frames=64` → `av1_vaapi -low_power 1 -bf 5 -b_depth 3 -rc_mode ICQ`), keeping frames on VA surfaces end-to-end (D-01), with `-ss` before `-i` and the `extra_hw_frames=64` fix that prevents the exit-244 EXEC_FAILURE misclassification (Pitfall 2).
- `cmd_probe_vaapi` (`probe-vaapi` subcommand) empirically probed all three trigger-triad legs live on this Arc A380 and recorded the result to `scratch/repro/vaapi_probe.txt`: **reorder UNSUPPORTED, P010 ACTIVE, HW-decode ACTIVE → PARTIAL-TRIAD**. This matches 02-RESEARCH.md's prediction exactly.
- `ensure_vaapi_reference()` / `cmd_reference_vaapi` (`reference-vaapi` subcommand) generated a determinism-confirmed `av1_vaapi` self-reference for scene 923 (two isolated encodes, md5-compared — came back bit-identical) and single isolated self-references for scenes 928/1129, all stored under distinct `_vaapi_ref` filenames, never touching the pre-existing qsvencc reference (verified byte-unchanged, same md5, after the run).
- Found and fixed a real bug in the documented D-02 probe recipe: `ffprobe -show_entries frame=pts,dts` silently drops the invalid `dts` field name (the real field is `pkt_dts`), which produces a false "REORDER DETECTED on every frame" result. Verified this live on the actual probe output before and after the fix.

## Task Commits

1. **Task 1: av1_vaapi command builder + capability probe (D-01, D-02)** - `566828ac` (feat)
2. **Task 2: av1_vaapi self-reference + determinism re-confirm (D-04, D-05)** - `041ab6dc` (feat)

**Plan metadata:** (this commit, docs)

## Files Created/Modified

- `scratch/repro/harness.sh` - added `vaapi_encode()`, `vaapi_ref_obu()`/`vaapi_ref_png()`, `cmd_probe_vaapi()`, `ensure_vaapi_reference()`, `cmd_reference_vaapi()`, and the `probe-vaapi`/`reference-vaapi` dispatcher cases

## Decisions Made

- Kept the literal `frame=pts,dts` token pairing in the ffprobe invocation (as `frame=pts,dts,pkt_dts`) for continuity with the documented probe recipe and the plan's own verification grep, while using the correct `pkt_dts` field for the actual comparison — ffprobe silently ignores the invalid `dts` token and this still produces a genuinely-correct two-column result.
- Leg (c) HW-VA video-memory decode verdict is derived from (a) the probe's own filter string containing no `hwdownload` token, AND (b) the full-HW encode having actually completed successfully — not a bare static string check alone.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed broken ffprobe `dts` field name in the D-02 reorder probe**
- **Found during:** Task 1 (`cmd_probe_vaapi` implementation, live verification run)
- **Issue:** The plan's action text and 02-RESEARCH.md's own verified "Code Examples" specify `ffprobe -show_entries frame=pts,dts -of csv=p=0`. Live testing in this exact environment showed this field-name pair does not work as documented: `dts` is not a valid `ffprobe` frame-entry field name (the real name is `pkt_dts`) and is silently dropped rather than erroring, producing a single-column (`pts`-only) CSV. The `awk -F, '$1!=$2'` comparison then sees an empty `$2` on every row, so **every single frame is misclassified as a reorder mismatch** regardless of actual encoder behavior — directly contradicting 02-RESEARCH.md's own claimed empirical result ("100/100 frames pts==dts, no reorder"), which was re-run live and reproduced the same false-ACTIVE bug with the documented command.
- **Fix:** Changed the ffprobe entry list to `frame=pts,dts,pkt_dts`. ffprobe still silently ignores the invalid `dts` token but now also requests `pkt_dts`, producing a real two-column `pts,pkt_dts` CSV that the existing `awk -F, '$1!=$2'` logic correctly evaluates. Re-ran the probe: result flipped from a false `ACTIVE` (100/100 "mismatched") to the correct `UNSUPPORTED` (0/100 mismatched), matching 02-RESEARCH.md's claimed finding.
- **Files modified:** `scratch/repro/harness.sh` (`cmd_probe_vaapi`)
- **Verification:** Ran `bash scratch/repro/harness.sh probe-vaapi` before and after the fix; observed the verdict change directly, plus a manual side-by-side `ffprobe`/`awk` comparison of the raw `frame=pts,dts` vs `frame=pts,dts,pkt_dts` output on the same `probe_reorder.mkv` file, confirming the field-name behavior.
- **Committed in:** `566828ac` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug fix)
**Impact on plan:** Necessary for correctness — without this fix, the D-02 probe's central deliverable (an accurate per-leg triad verdict) would have been silently wrong on every run, misreporting an UNSUPPORTED leg as ACTIVE. No scope creep; the fix stayed entirely within `cmd_probe_vaapi`.

## Issues Encountered

None beyond the deviation documented above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `vaapi_encode()`, the D-02 triad verdict (PARTIAL-TRIAD, reorder leg unsupported), and the determinism-confirmed av1_vaapi self-reference for 923/928/1129 are all in place and on disk under `scratch/repro/reference/` — the two preconditions the next plan's concurrency measurement (D-07/D-08 detection/validation-N runs) depends on.
- Per D-03, any downstream "clean/immune" claim for av1_vaapi must carry the explicit PARTIAL-TRIAD caveat (B-frame reorder leg not reproducible on this hardware) — the concurrency measurement plan should surface this, not claim full-triad immunity.
- `scratch/repro/vaapi_probe.txt` and the `_vaapi_ref` artifacts are git-ignored (consistent with Phase 1's `scratch/repro/` convention) and remain on disk for the next plan to consume directly; only `harness.sh` itself is git-tracked.

---
*Phase: 02-in-container-triangulation-av1-vaapi*
*Completed: 2026-07-23*
