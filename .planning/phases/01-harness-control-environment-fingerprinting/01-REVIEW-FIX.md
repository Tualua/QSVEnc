---
phase: 01-harness-control-environment-fingerprinting
fixed_at: 2026-07-23T00:00:00Z
review_path: .planning/phases/01-harness-control-environment-fingerprinting/01-REVIEW.md
iteration: 1
findings_in_scope: 11
fixed: 11
skipped: 0
status: all_fixed
---

# Phase 01: Code Review Fix Report

**Fixed at:** 2026-07-23
**Source review:** .planning/phases/01-harness-control-environment-fingerprinting/01-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 11 (1 Critical + 10 Warning; 3 Info out of scope for `critical_warning`)
- Fixed: 11
- Skipped: 0

## Fixed Issues

### CR-01: Failed/empty PSNR measurement is silently classified as CLEAN

**Files modified:** `scratch/repro/harness.sh`
**Commit:** 6a471523
**Applied fix:** `classify_corrupt` now emits `NA` (not `0`) for an empty PSNR — only `inf` maps to clean. The measurement loop in `cmd_run_iter` guards frame extraction (`if ! ff... || [[ ! -s "$test_png" ]]`) and the PSNR value, recording an explicit `MEASURE_FAILURE` row (excluded from the corruption-fraction denominator) instead of `OK/clean`. The row-emission block honors a new per-scene `meas_fail` map, and the Python summary tallies `MEASURE_FAILURE` in the exclusion breakdown. This closes the fail-open path where the strongest corruption signal (a truncated `.obu` that fails extraction) was scored clean.
**Note:** Logic-bearing change to classification semantics — **requires human verification** that `MEASURE_FAILURE` rows are treated as intended across the full pipeline.

### WR-01: No trap — interrupted iteration orphans background encodes

**Files modified:** `scratch/repro/harness.sh`
**Commit:** 2cd32a4f
**Applied fix:** Installed `trap '... kill tracked PIDs ...; cleanup_gpu_procs' INT TERM` at the top of `cmd_run_iter`, killing `p1/p2/p3` and `cp1/cp2/cp3` (via `${var:-}` for `set -u` safety) and reaping GPU clients on interrupt.

### WR-02: `n_actual` always equals `n_requested`

**Files modified:** `scratch/repro/harness.sh`
**Commit:** 79ee9489
**Applied fix:** `n_actual` now increments only inside the `result.csv` guard (iterations that produced usable rows); contaminated skips are counted separately as `n_contaminated` / `contaminated_skipped`, giving `control_invalid/n_actual` a truthful denominator.
**Note:** Changes a metric's denominator semantics — **requires human verification** that the reported ratios match intent.

### WR-03: Background ffmpeg encodes run without `-nostdin`

**Files modified:** `scratch/repro/harness.sh`
**Commit:** fe41891b
**Applied fix:** Added `-nostdin` to `ctrl_encode` and the inline extraction/PSNR ffmpegs (the step-2 measurement extraction already received it in CR-01).

### WR-04: Control immunity PSNR-validated for scene 923 only

**Files modified:** `scratch/repro/harness.sh`
**Commit:** 5fe00c67
**Applied fix:** Added per-scene control lookups (`ctrl_frames`, `ctrl_ref_obu`, `ctrl_ref_png`) and an `ensure_control_reference` helper; `cmd_reference` now generates control references for all three scenes; `cmd_run_iter` PSNR-validates every control frame against its own reference and sets `control_clean=1` only if all three are >= 30 dB, treating missing/empty control PSNR conservatively as NOT clean.
**Note:** Substantial logic change to the control-validation path — **requires human verification** (especially the per-scene offsets/frame counts: 923@299/339, 928@96/110, 1129@299/361).

### WR-05: `run-batch` does not preflight required reference artifacts

**Files modified:** `scratch/repro/harness.sh`
**Commit:** 2f6d2c5c
**Applied fix:** Added a reference-artifact preflight in `cmd_run_batch` that aborts loudly (exit 1) if any qsvencc or control reference frame for 923/928/1129 is missing, before the (potentially hours-long) loop.

### WR-06: Post-measurement exclusivity race starves 928/1129 reference generation

**Files modified:** `scratch/repro/harness.sh`
**Commit:** b6f0516b
**Applied fix:** `cmd_reference` now generates the 928/1129 qsvencc references up front (while the GPU is known-idle), so `ensure_scene_reference` is a cache hit during the batch and never re-hits the async-release race. Added an idle-wait/retry loop before `require_gpu_exclusive` inside `ensure_scene_reference` as defense in depth.

### WR-07: PID-reuse TOCTOU in `cleanup_gpu_procs`

**Files modified:** `scratch/repro/lib.sh`
**Commit:** 2d99abba
**Applied fix:** Re-verify the live `/proc/$pid/cmdline` at kill time (skip if no longer qsvencc/ffmpeg) and terminate gracefully (SIGTERM, 0.2s wait) before SIGKILL, so a recycled PID is not killed and the target can release GPU/VA state.

### WR-08: `n_requested` not validated numeric

**Files modified:** `scratch/repro/harness.sh`
**Commit:** 5bd490f8
**Applied fix:** `cmd_run_batch` rejects a non-`^[1-9][0-9]*$` argument with a clean usage error and `exit 2`, before `seq`/the Python summary.

### WR-09: `timeout` has no `--kill-after`; inline ffmpegs unbounded

**Files modified:** `scratch/repro/lib.sh`, `scratch/repro/harness.sh`
**Commit:** cc0a6498
**Applied fix:** `run_encode` now uses `timeout -k 10`; added an `ff_bounded` helper (same bounded timeout wrapping `ffmpeg`) and routed all inline extraction/PSNR ffmpegs through it. The `ctrl_encode` ffmpeg was left as-is because it already runs through `run_encode` (avoiding a double timeout wrap).

### WR-10: md5 determinism check treats empty==empty as a pass

**Files modified:** `scratch/repro/harness.sh`
**Commit:** 46c66fe2
**Applied fix:** The D-05 determinism gate now requires both hashes non-empty AND equal (`-z "$md5_a" || -z "$md5_b" || "$md5_a" != "$md5_b"`), fail-closed on an md5sum failure.

## Skipped Issues

None — all in-scope findings were fixed. IN-01, IN-02, and IN-03 are Info-severity (CONVENTION) and outside the `critical_warning` fix scope; they were not attempted.

## Verification

- Every fix passed Tier 2 syntax verification: `bash -n` on the modified shell file(s), plus `python3 ast.parse` on the embedded summary heredoc for changes touching it. shellcheck is not installed in this environment.
- Logic-bearing fixes (CR-01, WR-02, WR-04) are flagged above as **requires human verification**; syntax/structure is confirmed but semantic correctness should be manually reviewed before the phase proceeds.

---

_Fixed: 2026-07-23_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
