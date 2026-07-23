---
phase: 02-in-container-triangulation-av1-vaapi
plan: 05
subsystem: testing
tags: [evidence, documentation, av1_vaapi, qsvencc, psnr, diag-02]

# Dependency graph
requires:
  - phase: 02-in-container-triangulation-av1-vaapi
    plan: 04
    provides: content_cross_match(), cmd_cross_match_qsvencc, crossmatch_qsvencc.txt (full 17-frame scan), av1_vaapi cross-match wiring
  - phase: 02-in-container-triangulation-av1-vaapi
    plan: 03
    provides: print_batch_summary_vaapi(), report_vaapi.csv + summary_vaapi.txt (detection-N=20, 0/20 corrupt, PARTIAL-TRIAD)
  - phase: 01-harness-control-environment-fingerprinting
    plan: 02
    provides: 01-EVIDENCE.md (certified qsvencc baseline: 923 9/20 45.0%, 1129 8/20 40.0%, 928 0/20, control 0/20)
provides:
  - .planning/phases/02-in-container-triangulation-av1-vaapi/02-EVIDENCE.md -- the git-tracked durable DIAG-02 finding, embedding verbatim vaapi_probe.txt/report_vaapi.csv/summary_vaapi.txt/crossmatch_qsvencc.txt, an explicit roadmap SC#2 interpretation ("immunity NOT proven" for the PARTIAL-TRIAD clean result), the D-03 triad-fidelity caveat (narrowly-phrased B-frame caveat), a triangulation table against the Phase-1 qsvencc baseline with Phase-3/4 implications, and the mechanism-confirmation note (qsvencc cross-session-swap mechanism note stays OPEN, av1_vaapi cross-match N/A)
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "EVIDENCE.md documentation-only plan reuses the on-disk outputs of prior measurement plans verbatim rather than re-running the harness -- confirmed all four source files present/current/consistent with prior SUMMARYs before writing, avoiding an unnecessary GPU-exclusive re-run"

key-files:
  created:
    - .planning/phases/02-in-container-triangulation-av1-vaapi/02-EVIDENCE.md
  modified: []

key-decisions:
  - "Confirmed all four on-disk source files (vaapi_probe.txt, report_vaapi.csv, summary_vaapi.txt, crossmatch_qsvencc.txt) present, current, and consistent with 02-01/02-03/02-04-SUMMARY.md before writing -- no re-run of the harness was needed, avoiding an unnecessary GPU-exclusive measurement pass"
  - "Wrote both plan tasks (verbatim-output assembly + explicit interpretation/caveat/triangulation) into 02-EVIDENCE.md in a single Write, since both operate on the same file and the interpretation content depends on having the embedded data already in place -- both tasks' independent verification greps pass against the single resulting file"
  - "Interpretation branch was written to match the REAL recorded data (PARTIAL-TRIAD, 0/20 clean) rather than a scripted narrative -- explicitly states this is neither the clean-with-full-triad branch nor the corrupt branch, only the partial-triad 'immunity NOT proven' branch"

patterns-established: []

requirements-completed: [DIAG-02]

# Metrics
duration: ~15min
completed: 2026-07-23
---

# Phase 2 Plan 5: Durable DIAG-02 Evidence Artifact (02-EVIDENCE.md)

**Authored `02-EVIDENCE.md`, the git-tracked durable record of the av1_vaapi in-container triangulation finding: embeds verbatim on-disk `vaapi_probe.txt`/`report_vaapi.csv`/`summary_vaapi.txt`/`crossmatch_qsvencc.txt`, states the roadmap SC#2 interpretation explicitly ("PARTIAL-TRIAD clean result -> immunity NOT proven"), carries the D-03 triad-fidelity caveat with a narrowly-phrased B-frame reorder note, triangulates the 0/20 av1_vaapi result against the Phase-1 qsvencc baseline (923 45%/1129 40%/928 0%, control 0/20), and records the qsvencc cross-session-swap mechanism note as staying OPEN.**

## Performance

- **Duration:** ~15 min (confirmed all four source files present/current, read them + prior summaries + Phase-1 baseline, wrote the single 240-line EVIDENCE artifact, verified against both tasks' automated grep checks, committed)
- **Started:** 2026-07-23T11:51:00Z
- **Completed:** 2026-07-23T11:56:00Z
- **Tasks:** 2 completed
- **Files modified:** 1 (created)

## Accomplishments

- Confirmed all four required on-disk outputs (`vaapi_probe.txt` 09:27, `report_vaapi.csv` 10:15, `summary_vaapi.txt` 10:41, `crossmatch_qsvencc.txt` 11:37, all 2026-07-23) were present, current, and internally consistent with 02-01/02-03/02-04-SUMMARY.md's transcribed figures -- no re-run of the harness was needed.
- Created `.planning/phases/02-in-container-triangulation-av1-vaapi/02-EVIDENCE.md` (240 lines, git-tracked), mirroring `01-EVIDENCE.md`'s structure: "Why this file exists" (git-ignored-workdir durability rationale), a "Requirement -> Artifact mapping" table mapping DIAG-02 to all four embedded sections, and verbatim fenced snapshots of `vaapi_probe.txt`, `report_vaapi.csv` (61 lines: header + 60 rows, all `status=OK`/`corrupt=0`/`control_clean=1`), `summary_vaapi.txt`, and `crossmatch_qsvencc.txt` (17-frame scan + aggregate verdict).
- Added an "Interpretation (roadmap SC#2)" section stating explicitly which branch applies to the REAL recorded data: PARTIAL-TRIAD (`p010: ACTIVE`, `hw_decode: ACTIVE`, `reorder: UNSUPPORTED`) + 0/20 clean with clean paired control -> neither the "clean-with-full-triad strengthens ffmpeg-migration case" branch nor the "corrupt broadens the fault" branch, but the third: **immunity NOT proven**.
- Added a "Triad-fidelity caveat (D-03)" section with the literal phrase "immunity NOT proven", and phrased the B-frame reorder caveat narrowly: "no display/decode reordering observed via PTS/DTS... NOT a claim of zero reference-surface-lifetime effect" (per 02-RESEARCH.md Open Question #1), matching the plan's explicit instruction not to overclaim.
- Added a "Triangulation vs Phase-1 baseline" section with a comparison table (qsvencc 923 9/20 45.0% / 1129 8/20 40.0% / 928 0/20 / control 0/20 vs. av1_vaapi 0/20 across all three scenes / control 0/20), explicitly naming the two live competing hypotheses this data does not distinguish, and stating the implication for Phase 3 (host-side levers) and Phase 4 (ffmpeg-migration workaround): the result is inconclusive, not a green light.
- Added a "Mechanism confirmation" section recording Plan 04's full qsvencc cross-session-swap verdict (0/17 confirmed >=35 dB, mechanism note stays OPEN -- closing Phase 1's deferred note by determining it is NOT confirmed, not by confirming it) and the av1_vaapi cross-match status (N/A, 0 corrupt this batch).
- Both tasks' independent automated verification checks pass against the single resulting file (confirmed via direct grep re-execution, see Self-Check below).

## Task Commits

1. **Task 1 + Task 2 (combined -- see Deviations): assemble verbatim outputs + DIAG-02 mapping, and write the explicit SC#2 interpretation + D-03 caveat + Phase-1 triangulation** - `7546e112` (docs)

**Plan metadata:** (this commit, docs)

## Files Created/Modified

- `.planning/phases/02-in-container-triangulation-av1-vaapi/02-EVIDENCE.md` - the durable git-tracked DIAG-02 finding (240 lines): "Why this file exists", "Requirement -> Artifact mapping", four verbatim fenced snapshots, "Interpretation (roadmap SC#2)", "Triad-fidelity caveat (D-03)", "Triangulation vs Phase-1 baseline", "Mechanism confirmation", "Reconciliation note"

## Decisions Made

- Confirmed all four on-disk source files present, current, and consistent with prior plans' SUMMARYs before writing -- no re-run of the harness was needed, avoiding an unnecessary GPU-exclusive measurement pass (the plan's own fallback re-run instruction was conditioned on staleness/absence, neither of which applied).
- Wrote both plan tasks into 02-EVIDENCE.md in a single Write operation rather than two incremental edits, since the interpretation/caveat/triangulation content (Task 2) is written directly alongside the verbatim data it interprets (Task 1) and both draw on the same read context; both tasks' independently-specified automated verification greps were re-run against the single resulting file and both pass.
- Wrote the interpretation branch to match the REAL recorded data (PARTIAL-TRIAD + 0/20 clean) rather than assuming the research-predicted narrative sight-unseen -- explicitly stated in the EVIDENCE file that this is neither the clean-with-full-triad nor the corrupt branch, only the partial-triad "immunity NOT proven" branch, per the plan's own instruction not to force the expected narrative if the real data differed (it did not differ in this case, but the branch logic is stated explicitly rather than assumed).

## Deviations from Plan

**1. [Claude's discretion, non-substantive] Combined Task 1 and Task 2 into a single commit**
- **Found during:** Task 1 (before starting)
- **Issue:** The plan specifies two `type="auto"` tasks both modifying the same single file (`02-EVIDENCE.md`), where Task 2's content (interpretation/caveat/triangulation) is written directly alongside Task 1's content (verbatim snapshots + mapping) it interprets, using the same read context gathered once.
- **Fix:** Wrote the complete file (both tasks' required sections) in a single `Write` operation and committed once, rather than committing an intermediate partial file after Task 1 and amending afterward. This avoids an artificial intermediate commit state and matches how the two tasks' content naturally interleaves in the finished document.
- **Files modified:** `.planning/phases/02-in-container-triangulation-av1-vaapi/02-EVIDENCE.md`
- **Verification:** Both tasks' independent `<verify><automated>` grep checks were re-run against the single resulting file after the commit and both pass (see Self-Check below).
- **Committed in:** `7546e112`

---

**Total deviations:** 1 (task-commit granularity only, no code/content deviation from either task's `<action>` or `<acceptance_criteria>`).
**Impact on plan:** None on substance -- both tasks' acceptance criteria and automated verification are fully satisfied by the single committed file.

## Issues Encountered

None. All four required on-disk source files were present, current, and internally consistent with prior plans' transcribed figures; no harness re-run, no missing data, no GPU contention concerns.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- **DIAG-02 is now complete.** This is the final plan of Phase 2 -- `02-EVIDENCE.md` durably records the full concurrency measurement (probe, detection-N=20 batch, paired control, content-origin cross-match against both baselines) with an explicit, honest interpretation.
- The finding as recorded: av1_vaapi is 0/20 corrupt under 3-way concurrency but only under a PARTIAL trigger triad (B-frame reorder unreproducible on this Arc A380's low-power-only AV1 VAAPI entrypoint) -- **immunity NOT proven**. This is a genuinely inconclusive result for Phase 3 (host-side levers) and Phase 4 (ffmpeg-migration workaround recommendation) to build on, not a green light; both phases should treat the ffmpeg-migration case as unresolved pending either full-triad hardware/entrypoint access or acceptance of residual risk.
- The qsvencc cross-session-swap mechanism note (Phase 1's deferred item) stays OPEN, not closed: the full 17-frame historical scan found 0/17 confirmed whole-frame swaps, ruling out the simplest hypothesis without providing a positive alternative mechanism. Any future mechanism-focused work should start from the open alternatives noted in `02-EVIDENCE.md`'s "Mechanism confirmation" section (sub-frame/tile-granularity aliasing, cross-time content, or stale VA surface content not present in any of the three scenes' own output).
- All `scratch/repro/` runtime artifacts remain on disk (git-ignored, preserved): `vaapi_probe.txt`, `report_vaapi.csv`, `summary_vaapi.txt`, `crossmatch_qsvencc.txt`, `vaapi_runs/it01..it21/`, `crossmatch_cache/` (~36 GB), plus all Phase-1 artifacts (`runs/`, `control_runs/`).

---
*Phase: 02-in-container-triangulation-av1-vaapi*
*Completed: 2026-07-23*
