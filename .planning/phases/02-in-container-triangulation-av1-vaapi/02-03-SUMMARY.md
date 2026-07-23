---
phase: 02-in-container-triangulation-av1-vaapi
plan: 03
subsystem: testing
tags: [ffmpeg, vaapi, av1_vaapi, harness, bash, psnr, concurrency, qsv, wilson-ci]

# Dependency graph
requires:
  - phase: 02-in-container-triangulation-av1-vaapi
    plan: 02
    provides: cmd_run_iter_vaapi(), cmd_run_batch_vaapi() (with a placeholder summary step), report_vaapi.csv schema
provides:
  - print_batch_summary_vaapi() -- the interpretive av1_vaapi batch report (Wilson-CI hotspot stats, D-02 triad caveat with UNAVAILABLE guard, D-07/D-08 gated escalation, minimum-valid-iteration DEGRADED-BATCH floor, roadmap SC#2 interpretation including the literal "immunity NOT proven" phrase)
  - the recorded detection-N=20 av1_vaapi result -- report_vaapi.csv (60 scene rows) + summary_vaapi.txt (0/20 corrupt on all three scenes, paired av1_qsv control 0/20, PARTIAL-TRIAD, do-NOT-escalate verdict, "immunity NOT proven" interpretation)
affects: [02-04, 02-05]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "print_batch_summary_vaapi extends print_batch_summary's env-var-passed-CSV-into-python3-heredoc shape rather than replacing it -- wilson_ci()/scene_stats() copied verbatim, new blocks (triad caveat, gated escalation, DEGRADED-BATCH floor, SC#2 interpretation) appended in the same Python body"
    - "Missing/empty vaapi_probe.txt degrades to an explicit 'triad caveat: UNAVAILABLE - probe not run or file missing' line rather than erroring or silently blanking (T-02-15 fail-closed lineage)"
    - "Minimum-valid-iteration floor computed as ceil(0.85 * n_requested) (17 of 20) -- a DEGRADED BATCH warning is additive to, never a replacement for, the existing OK-only denominator accounting"

key-files:
  created: []
  modified:
    - scratch/repro/harness.sh

key-decisions:
  - "Read the D-02 triad legs directly out of vaapi_probe.txt's own line format (reorder:/p010:/hw_decode:/triad: prefixes) rather than re-deriving full_triad from a separately-passed boolean -- keeps print_batch_summary_vaapi as the single place that interprets the probe file, and the UNAVAILABLE guard only has one code path to get right."
  - "full_triad requires the probe file to be non-empty AND all three legs literally 'ACTIVE' -- an UNKNOWN leg (probe ran but a specific check failed) is treated identically to UNSUPPORTED for the escalation gate, never silently promoted to a pass."

patterns-established:
  - "Same worker-function-returns / top-level-cmd-exits discipline carried from 02-01/02-02 -- print_batch_summary_vaapi is a Python-heredoc-wrapping bash function, not a top-level cmd_*, and performs no exit."

requirements-completed: []

# Metrics
duration: ~20min
completed: 2026-07-23
---

# Phase 2 Plan 3: av1_vaapi Detection-N=20 Triangulation Result (print_batch_summary_vaapi + live batch)

**Added `print_batch_summary_vaapi` (Wilson-CI hotspot stats + D-02 triad caveat + D-07/D-08 gated escalation + DEGRADED-BATCH floor + explicit SC#2 interpretation), wired it into `cmd_run_batch_vaapi` replacing the 02-02 placeholder, then ran the real detection-N=20 av1_vaapi 3-way concurrent batch live on the Arc A380: 0/20 corrupt on all three scenes (923/928/1129), paired ffmpeg av1_qsv control clean 0/20, zero EXEC_FAILURE/TIMEOUT/CONTROL_INVALID across all 20 iterations, PARTIAL-TRIAD (B-frame reorder UNSUPPORTED, P010 and HW-decode ACTIVE) confirmed by the 02-02 probe, correctly gating to "do NOT escalate" and recording the honest "immunity NOT proven" interpretation.**

## Performance

- **Duration:** ~20 min (Task 1 implementation + verification ~10 min; Task 2 live N=20 batch ~7 min wall-clock, well under the plan's 1-3 hour estimate since every iteration completed cleanly with no retries)
- **Completed:** 2026-07-23T10:19:00Z
- **Tasks:** 2 completed
- **Files modified:** 1 (`scratch/repro/harness.sh`)

## Accomplishments

- `print_batch_summary_vaapi(report, n_requested, n_actual)` added to `harness.sh`, reusing `wilson_ci()`/`scene_stats()` verbatim from `print_batch_summary` (same <30 dB threshold, same OK-only denominator, same PSNR-signature stability block) for scenes 923/928/1129.
- Reads `$W/vaapi_probe.txt` for the D-02 triad caveat (reorder/p010/hw_decode verdicts); a missing/empty file degrades to the explicit line `triad caveat: UNAVAILABLE - probe not run or file missing` and `full_triad=False` -- never an error, never a silent blank (T-02-15).
- Implements all three D-08 gated-escalation branches: positive (>=1 corrupt) -> stop, detection-grade; 0/N + full triad -> escalate to validation-N~60; 0/N + partial/unknown triad -> do NOT escalate, detection-grade PARTIAL-TRIAD only.
- Adds a minimum-valid-iteration floor at `ceil(0.85 * n_requested)` (17 of 20); below it, emits a distinct `DEGRADED BATCH - detection power reduced` warning additive to the existing OK-only denominator accounting.
- Emits the explicit roadmap SC#2 interpretation contract for all three outcomes (corrupt / clean-with-full-triad / clean-with-partial-triad), with the literal phrase "immunity NOT proven" required and present in the partial-triad branch (D-03).
- Replaced the 02-02 `# PLACEHOLDER: replace in 02-03 Task 1` marker inside `cmd_run_batch_vaapi` with a call to `print_batch_summary_vaapi "$report" "$n_requested" "$n_actual"`; the placeholder no longer exists anywhere in the file.
- Bench-tested the new function against the existing 2-iteration smoke-run CSV before the live run, confirming both the DEGRADED-BATCH branch (2/20 < floor 17) and the UNAVAILABLE-probe-file branch fire correctly.
- **Ran the real detection-N=20 av1_vaapi 3-way concurrent batch live on the Arc A380** (`bash scratch/repro/harness.sh run-batch-vaapi 20`), GPU-exclusive throughout, no other GPU consumers. Result, transcribed verbatim from the on-disk `summary_vaapi.txt`:
  - **N_actual: 20/20** (0 contaminated-skipped, 0 EXEC_FAILURE, 0 TIMEOUT, 0 MEASURE_FAILURE, 0 CONTROL_INVALID) -- the DEGRADED-BATCH floor (17/20) was met with margin.
  - **Scene 923 / offset 299 (primary hotspot):** 0/20 corrupt (0.0%), 95% Wilson CI [0.000, 0.161], PSNR=inf on every OK iteration (no corrupt frames to report a signature for).
  - **Scene 928 / offset 96:** 0/20 corrupt (0.0%).
  - **Scene 1129 / offset 299:** 0/20 corrupt (0.0%).
  - **Paired ffmpeg av1_qsv immune control:** 0/20 non-clean/invalidated (clean throughout, as required by D-11).
  - **D-02 triad caveat (read from `vaapi_probe.txt`, generated in 02-02):** reorder=UNSUPPORTED, p010=ACTIVE, hw_decode=ACTIVE -> `triad: PARTIAL-TRIAD`; `full_triad = False`.
  - **D-07/D-08 gated-escalation verdict:** "0/20 with PARTIAL/UNKNOWN triad -> do NOT escalate; 60 runs on a broken triad prove nothing; report detection-grade PARTIAL-TRIAD only." No N~60 validation run was performed (correctly not demanded by the gate).
  - **SC#2 interpretation (recorded verbatim):** "av1_vaapi CLEAN but PARTIAL triad: immunity NOT proven (D-03) -- a clean result here does not confirm av1_vaapi is immune to the trigger triad, only that the legs that WERE reproducible did not corrupt under this concurrency."

## Task Commits

1. **Task 1: print_batch_summary_vaapi — triad caveat + gated escalation + SC#2 interpretation + replace the 02-02 placeholder** - `e073d9da` (feat)
2. **Task 2: run the detection-N=20 av1_vaapi triangulation batch + capture the result** - no code changes (measurement-only task); the resulting `report_vaapi.csv`/`summary_vaapi.txt` are git-ignored runtime artifacts under `scratch/repro/`, per the existing convention that only `harness.sh`/`lib.sh` are tracked.

**Plan metadata:** (this commit, docs)

## Files Created/Modified

- `scratch/repro/harness.sh` - added `print_batch_summary_vaapi()`, replaced the 02-02 placeholder call site inside `cmd_run_batch_vaapi`
- `scratch/repro/report_vaapi.csv` (git-ignored runtime artifact) - now holds the detection-N=20 result: 61 lines (1 header + 60 scene rows), 20 iterations x 3 scenes, all `status=OK`, `control_clean=1`
- `scratch/repro/summary_vaapi.txt` (git-ignored runtime artifact) - the recorded interpretive report described above

## Decisions Made

- Read the D-02 triad legs directly out of `vaapi_probe.txt`'s own `reorder:`/`p010:`/`hw_decode:`/`triad:` line format inside the Python summary body, rather than pre-computing `full_triad` in bash and passing it as an extra env var -- keeps `print_batch_summary_vaapi` the single place that interprets the probe file's contents, so the UNAVAILABLE-guard logic only has one code path.
- `full_triad` requires the probe file to be non-empty AND all three legs literally `ACTIVE`; an `UNKNOWN` leg (a probe step whose specific check itself failed) is treated identically to `UNSUPPORTED` for the escalation gate -- it is never silently promoted to a pass, consistent with the CR-01/T-02-03 fail-closed lineage already established in `cmd_probe_vaapi`.

## Deviations from Plan

None - plan executed exactly as written. The measurement outcome matched 02-RESEARCH.md's own prediction (PARTIAL-TRIAD, B-frame leg unreproducible, expected outcome not a low-probability edge case) and the plan's own success criteria anticipated and required recording this honestly rather than the (not-taken) full-triad escalation branch.

## Issues Encountered

None. The live N=20 batch completed in ~7 minutes wall-clock with zero retries, zero EXEC_FAILURE, and zero TIMEOUT -- substantially faster than the plan's 1-3 hour estimate, likely because the Assumption A2 fix (`extra_hw_frames=64`) fully eliminated the exit-244 gotcha under 3-way concurrent contention (already confirmed in the 02-02 smoke run) and every iteration ran clean on the first attempt with no GPU-idle-recheck retries needed.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- The detection-N=20 av1_vaapi result is now recorded on disk (`report_vaapi.csv`, `summary_vaapi.txt`) and transcribed above for the durable EVIDENCE artifact 02-05 will produce.
- **DIAG-02 is intentionally NOT marked complete by this plan** (per the plan's own explicit instruction) -- the finding as recorded is a clean, PARTIAL-TRIAD, detection-grade data point with "immunity NOT proven"; the phase's remaining plans (02-04 content-origin cross-match / D-09-D-10, 02-05 durable evidence write-up) still need to run before DIAG-02 as a whole can be closed.
- Because the av1_vaapi batch was 0/20 corrupt, 02-04's content-origin cross-match (D-09/D-10) has no new av1_vaapi corrupt frame to cross-match against this batch -- per D-10 it still applies to the historical qsvencc baseline (closing Phase 1's deferred "Mechanism-vs-symptom NOTE"), which remains fully available on disk (`scratch/repro/runs/itNN/`).
- All `scratch/repro/` runtime artifacts from this run (the full `vaapi_runs/it01`..`it20/` tree, `report_vaapi.csv`, `summary_vaapi.txt`) remain on disk, preserved per this plan's execution constraint (no worktree, main working tree only).

---
*Phase: 02-in-container-triangulation-av1-vaapi*
*Completed: 2026-07-23*
