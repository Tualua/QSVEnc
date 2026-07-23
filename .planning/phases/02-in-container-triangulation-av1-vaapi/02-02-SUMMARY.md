---
phase: 02-in-container-triangulation-av1-vaapi
plan: 02
subsystem: testing
tags: [ffmpeg, vaapi, av1_vaapi, harness, bash, psnr, concurrency, qsv]

# Dependency graph
requires:
  - phase: 02-in-container-triangulation-av1-vaapi
    plan: 01
    provides: vaapi_encode(), vaapi_ref_png()/vaapi_ref_obu(), the determinism-confirmed av1_vaapi self-reference for 923/928/1129, and the extra_hw_frames=64 exit-244 fix
provides:
  - cmd_run_iter_vaapi() -- one full 3-way concurrent av1_vaapi measurement iteration (measure -> classify vs av1_vaapi self-reference -> paired av1_qsv immune control), Phase-1-schema report rows
  - cmd_run_batch_vaapi() -- the N-iteration batch loop (WR-08 guard, disk preflight, extended reference preflight, GPU-idle recheck), writing scratch/repro/report_vaapi.csv
  - run-iter-vaapi / run-batch-vaapi dispatcher subcommands
  - live confirmation of research Assumption A2 (extra_hw_frames=64 holds under real 3-way concurrent contention, not just single-session)
affects: [02-03, 02-04, 02-05]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "vp1/vp2/vp3 PID naming for the av1_vaapi measurement block, distinct from the qsvencc analog's p1/p2/p3, to avoid trap-handler variable collision with the shared control block"
    - "Distinct report file per encoder path (report_vaapi.csv vs report.csv), never merged"
    - "Explicit MANDATORY-HANDOFF placeholder pattern for an intentionally incomplete cross-plan dependency (interpretive summary deferred to 02-03)"

key-files:
  created: []
  modified:
    - scratch/repro/harness.sh

key-decisions:
  - "Extended the reference-artifact preflight (WR-05 lineage) to require BOTH the av1_vaapi self-references and the av1_qsv control references before a vaapi batch can start, rather than only the av1_vaapi side -- a missing control reference would otherwise silently produce all-CONTROL_INVALID rows with no diagnostic message pointing at the real cause."
  - "Left the batch summary as an explicit placeholder (raw report.csv dump) rather than writing a partial print_batch_summary_vaapi now -- the plan's own MANDATORY HANDOFF directive requires 02-03 Task 1 to own the full triad-caveat/gated-escalation interpretation; a half-built summary here would risk drifting from that contract."

patterns-established:
  - "Every new av1_vaapi controller function continues the worker-function-returns/never-die() contract for helpers, exit()-only-at-cmd_* boundary for top-level entries -- unchanged from 02-01."

requirements-completed: []

# Metrics
duration: ~15min
completed: 2026-07-23
---

# Phase 2 Plan 2: av1_vaapi 3-Way Concurrency Measurement (cmd_run_iter_vaapi + cmd_run_batch_vaapi)

**Added the core av1_vaapi concurrency measurement machinery to `harness.sh` -- `cmd_run_iter_vaapi` (3-way concurrent measure, classify against the av1_vaapi self-reference, paired immune control) and `cmd_run_batch_vaapi` (the batch loop) -- then proved the path end-to-end with a live 2-iteration smoke run: 6/6 rows OK, PSNR=inf on every scene, control_clean=1, zero EXEC_FAILURE, confirming Assumption A2 (the `extra_hw_frames=64` fix holds under real 3-way concurrent contention, not just single-session).**

## Performance

- **Duration:** ~15 min
- **Completed:** 2026-07-23T09:59:00Z
- **Tasks:** 2 completed
- **Files modified:** 1 (`scratch/repro/harness.sh`)

## Accomplishments

- `cmd_run_iter_vaapi()` runs a full 3-way concurrent `av1_vaapi` iteration (923/928/1129) via `vaapi_encode()`, classifies each scene's extracted frame against its own `vaapi_ref_png` self-reference using `psnr_of()`/`classify_corrupt()` verbatim, then pairs an unchanged `ctrl_encode()` (ffmpeg `av1_qsv`) 3-way immune control sequential-after -- emitting the exact Phase-1 report schema (`iteration,scene,offset,status,psnr_db,corrupt,control_clean`).
- The three concurrent measurement PIDs are named `vp1/vp2/vp3` (not `p1/p2/p3`) so the INT/TERM cleanup trap can safely list both the vaapi PIDs and the control block's `cp1/cp2/cp3` PIDs without any variable-name collision.
- `cmd_run_batch_vaapi()` loops `cmd_run_iter_vaapi` with the WR-08 numeric-N guard, disk preflight, an EXTENDED reference-artifact preflight (requires both the av1_vaapi self-references AND the av1_qsv control references before starting), and the inter-iteration GPU-idle recheck with `cleanup_gpu_procs` retries -- writing to `scratch/repro/report_vaapi.csv` (distinct from the qsvencc `report.csv`).
- `run-iter-vaapi <N>` / `run-batch-vaapi [N=20]` subcommands routed in `main()`.
- **Live 2-iteration smoke run executed and confirmed clean:** `bash scratch/repro/harness.sh run-batch-vaapi 2` produced 6/6 `OK` rows, `psnr_db=inf` on every scene of every iteration (byte-identical to the self-reference), `control_clean=1` throughout, and **zero `EXEC_FAILURE`** -- directly re-verifying 02-RESEARCH.md's open Assumption A2 (that `extra_hw_frames=64` is sufficient headroom under real 3-way concurrent contention, not just the single-session testing that research pass used).
- The batch summary is a deliberate placeholder (raw `report_vaapi.csv` dump), carrying the explicit `# PLACEHOLDER: replace in 02-03 Task 1` marker the plan mandates -- it does NOT call the qsvencc `print_batch_summary` (whose text would misdescribe an av1_vaapi batch) and does not invent a partial `print_batch_summary_vaapi`.

## Task Commits

1. **Task 1: cmd_run_iter_vaapi — 3-way concurrent av1_vaapi measure + classify + paired control** - `15b0e523` (feat)
2. **Task 2: cmd_run_batch_vaapi + dispatchers + smoke run (Assumption A2)** - `6d676f74` (feat)

**Plan metadata:** (this commit, docs)

## Files Created/Modified

- `scratch/repro/harness.sh` - added `cmd_run_iter_vaapi()`, `cmd_run_batch_vaapi()`, and the `run-iter-vaapi`/`run-batch-vaapi` dispatcher cases

## Decisions Made

- Extended the reference-artifact preflight to require both the av1_vaapi self-references and the av1_qsv control references before `run-batch-vaapi` starts (not just the av1_vaapi side) -- prevents a batch from silently producing all-`CONTROL_INVALID` rows with no clear diagnostic pointing at a missing control reference.
- Deliberately left the batch summary as a raw-dump placeholder rather than attempting a partial interpretive summary now, per the plan's MANDATORY HANDOFF directive -- the full triad-caveat/gated-escalation/SC#2 interpretation belongs entirely to 02-03 Task 1's `print_batch_summary_vaapi`.

## Deviations from Plan

None - plan executed exactly as written. The smoke run behaved as the plan anticipated (Assumption A2 held; no EXEC_FAILURE observed).

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `cmd_run_iter_vaapi`/`cmd_run_batch_vaapi` are proven end-to-end (live smoke run, 6/6 clean rows) and ready for the detection-N=20 batch in the next plan.
- The summary placeholder is explicitly marked and MUST be replaced by `print_batch_summary_vaapi` in 02-03 Task 1 before any batch result is treated as an interpreted finding -- a batch run with the placeholder still active produces measurement rows but no triad caveat, no gated escalation, and no SC#2 interpretation.
- `scratch/repro/report_vaapi.csv` and `scratch/repro/vaapi_runs/` are git-ignored runtime artifacts (consistent with the Phase-1 convention) and remain on disk from this plan's smoke run for the next plan to build on; only `harness.sh` itself is git-tracked.
- Per the plan's explicit instruction, DIAG-02 is NOT marked complete by this plan -- the concurrency measurement result is not final until the detection-N=20 batch (with the real interpretive summary) runs in a later plan.

---
*Phase: 02-in-container-triangulation-av1-vaapi*
*Completed: 2026-07-23*
