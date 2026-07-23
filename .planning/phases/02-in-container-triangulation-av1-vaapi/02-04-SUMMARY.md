---
phase: 02-in-container-triangulation-av1-vaapi
plan: 04
subsystem: testing
tags: [ffmpeg, psnr, harness, bash, content-cross-match, qsvencc, av1_vaapi]

# Dependency graph
requires:
  - phase: 02-in-container-triangulation-av1-vaapi
    plan: 03
    provides: print_batch_summary_vaapi(), cmd_run_iter_vaapi(), report_vaapi.csv (detection-N=20, 0/20 corrupt, PARTIAL-TRIAD)
provides:
  - content_cross_match() -- best-match PSNR search against the OTHER two concurrently-running scenes' same-iteration frames, with an explicit >=35/20-35/<20 dB threshold band + ~2 dB tie-break rule + fail-closed empty-PSNR handling
  - cmd_cross_match_qsvencc [--smoke] -- report.csv-driven historical qsvencc cross-match with a 01-EVIDENCE.md fallback list, corrupt-frame PNG preflight, cost-warning banner, disk preflight, and a fast --smoke mode
  - the real, completed full historical qsvencc cross-match result (all 17 Phase-1 corrupt frames scanned) -- Phase 1's deferred Mechanism-vs-symptom NOTE is NOT closed by this scan (0/17 confirmed >=35 dB)
  - av1_vaapi corrupt-path wiring (cmd_run_iter_vaapi + print_batch_summary_vaapi), exercised live and confirmed to emit the explicit N/A line on the recorded 0/20-corrupt PARTIAL-TRIAD batch
affects: [02-05]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Single-pass whole-.obu frame extraction cached per (iteration,scene) under crossmatch_cache/, reused across every corrupt frame that needs that same candidate set -- turns an O(N^2) naive per-candidate select-filter re-decode (empirically ~1-1.4s/candidate, which would have put the full scan at several hours) into an O(N) one-time decode (5-15s per scene), cutting the real full scan to ~64 minutes wall-clock"
    - "content_cross_match is a worker function (echo ABORT + return 1, never exit); cmd_cross_match_qsvencc is the sole top-level cmd_* entry allowed to exit -- same worker/top-level discipline as every other harness.sh function"
    - "The report.csv corrupt-set is read at runtime (never hardcoded), with a loud WARN + 01-EVIDENCE.md fallback list if report.csv is missing/empty, and a hard ABORT only if both report.csv and runs/ .obu inputs are absent"

key-files:
  created: []
  modified:
    - scratch/repro/harness.sh

key-decisions:
  - "Batch-extracted every candidate frame of an other-scene .obu in ONE ffmpeg call (no per-frame select filter) instead of the plan's minimum-viable per-.obu-per-iteration caching -- empirically measured naive per-candidate cost (~1-1.4s each) against the real Phase-1 .obu files before implementing, found it would put the full scan at several hours (worse than the plan's own 2-4h estimate), and built the single-pass-decode-then-cache approach to keep the full historical scan runnable within a single operator session (~64 min observed, not just theoretically 'ready to run')"
  - "The ~2 dB tie-break rule is applied BEFORE the threshold band, even when both sides are well below 20 dB -- 2 of the 17 real corrupt frames tied within 2 dB (14.05 vs 12.70 dB, 11.96 vs 10.49 dB) and are correctly reported as low-confidence 'ambiguous origin (tie)', not silently promoted into the 20-35 dB ambiguous band or picked as a single best match"
  - "Ran the full ~1-hour historical scan to completion in this session (nohup + a bounded polling wait, not the plan's minimum-viable 'leave it ready-to-run' fallback) because the batch-extraction optimization made the real cost (~64 min) fit within the session -- the recorded aggregate verdict below is a REAL, on-disk result, not a fabricated or projected one"

patterns-established:
  - "Fail-closed candidate scoring: an empty/failed psnr_of() result during a cross-match scan is logged distinctly via failed_candidates in the report line and excluded from the best-match search -- never silently treated as 'no match' or scored as 0 (CR-01/T-02-10 lineage)"

requirements-completed: []

# Metrics
duration: ~92min
completed: 2026-07-23
---

# Phase 2 Plan 4: Content-Origin Cross-Match -- qsvencc Historical Scan (Mechanism Note Stays OPEN) + av1_vaapi Wiring

**Built `content_cross_match()` + `cmd_cross_match_qsvencc` (threshold band, tie-break, report.csv guard, PNG preflight, cost warning, smoke mode), ran the REAL full historical scan over all 17 Phase-1 qsvencc corrupt frames (not just a ready-to-run stub), and found the corruption is NOT a clean cross-session content swap: best cross-scene PSNR values ranged 10.49-18.57 dB (15/17 GENERIC GARBAGE, 2/17 low-confidence ties, 0/17 confirmed >=35 dB) -- so Phase 1's deferred Mechanism-vs-symptom NOTE stays OPEN, not closed. Wired the same cross-match into the av1_vaapi corrupt path and confirmed live that a clean (0/20 corrupt) batch emits the explicit "nothing to cross-match / N/A this batch" line.**

## Performance

- **Duration:** ~92 min (Task 1 build + smoke ~15 min; Task 2 full scan ~64 min wall-clock, run to completion via `nohup` + a bounded polling wait, not left as a stub; Task 3 wiring + live verification + summary regeneration ~13 min)
- **Started:** 2026-07-23T10:22:43Z (immediately after 02-03)
- **Completed:** 2026-07-23T11:54:00Z
- **Tasks:** 3 completed
- **Files modified:** 1 (`scratch/repro/harness.sh`)

## Accomplishments

- **`content_cross_match()`** added: for a given corrupt frame, decodes each of the two OTHER concurrently-running scenes' same-iteration `.obu` outputs into a per-(iteration,scene) cache (`crossmatch_cache/`), loops `psnr_of()` (reused verbatim, no new metric) against every cached candidate, and emits an auditable verdict using an explicit threshold band DISTINCT from the 30 dB self-reference corrupt threshold: `>=35 dB` = CONFIRMED CROSS-SESSION CONTENT SWAP, `20-35 dB` = AMBIGUOUS ORIGIN, `<20 dB` = GENERIC GARBAGE. A ~2 dB tie-break rule reports "matches both concurrent scenes within 2 dB" rather than silently picking a winner. An empty/failed candidate PSNR is logged distinctly (`failed_candidates=N` in the report line) and excluded from scoring, never folded in as a false "no match" or a 0 (CR-01/T-02-10 fail-closed lineage).
- **Performance-critical optimization (Claude's discretion, correctness unaffected):** benchmarked the naive per-candidate `select=eq(n,f)` extraction against the real Phase-1 `.obu` files BEFORE committing to an approach and found it re-decodes each `.obu` from its start for every single candidate (no keyframe seeking in a raw AV1 stream) -- ~1-1.4s per candidate, which would have put the full 17-corrupt-frame scan at 6-7+ hours, worse than the plan's own 2-4h estimate. Replaced it with a single whole-`.obu` decode per (iteration,scene) into a cache directory (5-15s for a 111-362 frame scene, empirically verified), reused across every corrupt frame that needs that same candidate set (3 iterations have corrupt frames on both hotspots and share a cached leg). This cut the REAL full scan to **~64 minutes wall-clock**, which is what made running it to completion (rather than leaving it as a ready-to-run stub) feasible within this session.
- **`cmd_cross_match_qsvencc [--smoke]`** added: reads the corrupt set from `report.csv` at runtime (never hardcoded), with a loud `WARN` + the documented 01-EVIDENCE.md fallback list if `report.csv` is missing/empty, and a hard `ABORT` only if both `report.csv` and the `runs/*.obu` inputs are absent; preflights every corrupt-frame PNG (all were already present on disk from Phase 1, confirmed, so no extraction was needed this run, but the fallback-extraction code path exists and is exercised by the guard logic); prints a cost-warning banner + a 30 GB disk preflight before the long scan; prints a progress line every 100 candidates scanned.
- **Task 1 smoke run:** `bash scratch/repro/harness.sh cross-match-qsvencc --smoke` completed in **~17s** (verified timed), wrote `crossmatch_qsvencc_smoke.txt` with a real (not synthetic) best-match + band verdict for `it04-923` (best_psnr=14.05 dB, AMBIGUOUS ORIGIN tie) -- proved the code path before committing to the long scan.
- **Task 2 REAL full historical scan, run to completion (not left as a stub):** launched via `nohup bash scratch/repro/harness.sh cross-match-qsvencc` (non-blocking, backgrounded), monitored via a bounded polling loop rather than a short verify timeout, completed cleanly in ~64 minutes. Scanned all **17** Phase-1 corrupt frames (923: it04,07,08,10,11,12,14,15,17 -- note the real on-disk `report.csv` has 9 corrupt 923 iterations, one more than the plan interfaces' fallback-list text of 8; the fallback list is used verbatim from the plan only when `report.csv` is unavailable, and was NOT exercised this run since the real file was present and used). Verbatim final aggregate from `scratch/repro/crossmatch_qsvencc.txt`:
  ```
  AGGREGATE VERDICT (FULL): 17 corrupt frame(s) cross-matched
    confirmed cross-session content swap (>=35 dB): 0
    ambiguous origin (20-35 dB or within-2dB tie):  2
    generic garbage / no cross-scene origin (<20 dB): 15
    no valid candidates (fail-closed):               0
    -> Phase 1's deferred Mechanism-vs-symptom NOTE is NOT closed by this scan:
       no corrupt frame scored >=35 dB against a concurrent scene.
  ```
  Representative per-frame lines (best cross-scene PSNR across ~111-362 candidate frames per leg):
  ```
  it04-923: vs_928=12.70 vs_1129=14.05 best_psnr=14.05 verdict=AMBIGUOUS ORIGIN (matches both concurrent scenes within 2 dB)
  it07-923: vs_928=11.98 vs_1129=14.99 best_psnr=14.99 verdict=GENERIC GARBAGE (no cross-scene origin)
  it12-923: vs_928=10.49 vs_1129=11.96 best_psnr=11.96 verdict=AMBIGUOUS ORIGIN (matches both concurrent scenes within 2 dB)
  it05-1129: vs_923=18.57 vs_928=12.92 best_psnr=18.57 verdict=GENERIC GARBAGE (no cross-scene origin)
  ```
  **Honest interpretation (per explicit instruction, no overclaiming):** the best cross-scene PSNR across all 17 corrupt frames ranged **10.49-18.57 dB** -- well below even the 20 dB floor of the "ambiguous" band, let alone the 35 dB "confirmed" bar. This means the corrupt frame's content does NOT closely resemble any single frame of either concurrently-running scene at the whole-frame level this search measures. The two "ambiguous" verdicts are LOW-CONFIDENCE TIES (both sides under 15 dB, within ~2 dB of each other), not genuine 20-35 dB partial matches. **Phase 1's Mechanism-vs-symptom NOTE therefore stays OPEN, not closed**: this scan does NOT confirm the documented "cross-session content swap" mechanism at the whole-frame-vs-whole-frame granularity searched here. Plausible explanations (not tested by this plan, left for 02-05/future work to note as an open question): the swap may be at a sub-frame/reference-surface/tile granularity rather than a literal full concurrent-scene frame; the corrupted content may originate from a different point in time within the same-iteration `.obu` streams than any extracted candidate frame; or the aliasing may pull from GPU memory content that is not represented in any of the three scenes' own encoded output at all (e.g. stale VA surface contents from an even earlier iteration or process). This scan rules out the simplest hypothesis (a clean whole-frame swap from a concurrent SAME-iteration scene) without providing a positive alternative mechanism.
- **Task 3:** wired `content_cross_match` into `cmd_run_iter_vaapi`'s corrupt-frame branch (invoked only when `classify_corrupt` returns 1 for a scene, so it costs nothing on a clean batch) and added a "Content-origin cross-match (D-09/D-10)" block to `print_batch_summary_vaapi`. Verified live with a targeted `run-iter-vaapi 21` (GPU-idle, no contention with the CPU-only background scan): 0/3 corrupt as expected under the recorded PARTIAL-TRIAD result, no `crossmatch.txt` written (correctly gated -- only created when at least one corrupt frame occurs), and `summary_vaapi.txt` regenerated from the existing `report_vaapi.csv` (no N=20 batch re-run) correctly emits: `"no av1_vaapi corrupt frame observed -> nothing to cross-match (cross-session-swap mechanism confirmation for av1_vaapi is N/A this batch)"` and references `crossmatch_qsvencc.txt` so both baselines' mechanism findings are visible together (D-10).

## Task Commits

1. **Task 1: content_cross_match() + cmd_cross_match_qsvencc (threshold band, guards, preflight, progress, smoke) -- build + smoke-verify** - `e4e59cc3` (feat)
2. **Task 2: run the full historical qsvencc cross-match scan** - no code changes (measurement-only task, run via the harness built in Task 1); the resulting `crossmatch_qsvencc.txt` and `crossmatch_cache/` are git-ignored runtime artifacts under `scratch/repro/`, per the existing convention that only `harness.sh`/`lib.sh` are tracked.
3. **Task 3: wire the cross-match into the av1_vaapi corrupt path + surface in the summary (D-10)** - `e372a3d7` (feat)

**Plan metadata:** (this commit, docs)

## Files Created/Modified

- `scratch/repro/harness.sh` - added `content_cross_match()`, `_ccm_cache_key()`, `_ccm_extract_candidates()`, `_ccm_psnr_num()`, `_ccm_band()`, `_ccm_corrupt_png_path()`, `_ccm_ensure_corrupt_png()`, `cmd_cross_match_qsvencc()`, the `cross-match-qsvencc` dispatcher case; extended `cmd_run_iter_vaapi` with the corrupt-branch cross-match call; extended `print_batch_summary_vaapi` with the Content-origin cross-match block (+ `WORKDIR` env var for the Python heredoc)
- `scratch/repro/crossmatch_qsvencc.txt` (git-ignored runtime artifact) - the real full-scan result: 17 per-frame lines + the aggregate verdict transcribed above
- `scratch/repro/crossmatch_qsvencc_smoke.txt` (git-ignored runtime artifact) - the Task 1 smoke-run proof
- `scratch/repro/crossmatch_cache/` (git-ignored runtime artifact, ~36 GB) - the cached candidate-frame extractions backing the full scan; preserved on disk (not cleaned up) as a durable input for 02-05, per the explicit instruction to preserve `scratch/` artifacts
- `scratch/repro/vaapi_runs/it21/` (git-ignored runtime artifact) - the Task 3 targeted live verification iteration (0/3 corrupt, no crossmatch.txt, as expected)
- `scratch/repro/summary_vaapi.txt` (git-ignored runtime artifact) - regenerated from the existing `report_vaapi.csv` (no batch re-run) to include the new cross-match block

## Decisions Made

- Benchmarked the naive per-candidate extraction approach against the real Phase-1 `.obu` files BEFORE implementing, found it would make the full scan take several hours (worse than the plan's own 2-4h estimate), and built a single-pass-decode-then-cache optimization instead -- this is squarely within the plan's own "OPTIONAL optimization (Claude's discretion, correctness unaffected): cache extracted candidate PNGs per-.obu-per-iteration" allowance, extended from "avoid re-extracting when an iteration is corrupt in both hotspots" (the plan's minimum suggestion) to "extract each `.obu` exactly once regardless of how many corrupt frames need it" (a much larger win: O(N) instead of O(N^2) decode cost per scene).
- Because the optimization made the real full scan feasible within a single operator session (~64 min, not 2-4h), ran it to completion via `nohup` (backgrounded) + a bounded polling wait, rather than leaving it as a documented ready-to-run command per the plan's fallback allowance -- the aggregate verdict recorded above is a REAL, observed, on-disk result.
- Reported the honest "mechanism note stays OPEN" interpretation rather than the hoped-for "confirmed cross-session swap" outcome, per the plan's own explicit fail-closed philosophy and the coordinator's explicit instruction not to overclaim -- the scan's actual finding (all cross-scene PSNRs well below even the 20 dB ambiguous floor) is itself a valid, reportable, non-trivial result: it rules out the simplest "clean whole-frame swap from a concurrent scene" hypothesis.

## Deviations from Plan

### Auto-fixed Issues

None in the Rule 1/2/3 sense (no bugs found, no missing critical functionality, no blocking issues requiring inline fixes).

**1. [Claude's discretion, plan-sanctioned] Batch single-pass candidate extraction instead of per-.obu-per-iteration-only caching**
- **Found during:** Task 1 (before committing to an implementation, benchmarked the naive per-candidate approach against real data)
- **Issue:** The plan's baseline approach (per-candidate `select=eq(n,f)` extraction, with only the *optional* per-.obu-per-iteration re-extraction caching) would have made the full historical scan take an estimated 6-7+ hours on this hardware -- worse than the plan's own already-corrected 2-4h estimate -- because raw AV1 elementary streams have no keyframe seeking, so a per-candidate select filter re-decodes from the start every time.
- **Fix:** Implemented single-pass whole-`.obu` extraction into a `crossmatch_cache/` directory once per (iteration,scene), with every corrupt frame that needs that scene's candidates reusing the cache. Empirically verified: 111-362 frame scenes extract in 5-15s (vs. ~1-1.4s x N candidates naive).
- **Files modified:** `scratch/repro/harness.sh` (`_ccm_extract_candidates`)
- **Verification:** Directly benchmarked both approaches against real `runs/it10/c928.obu` and `c1129.obu` before implementing; the full scan then ran to completion in ~64 min, matching the batch-extraction estimate, not the naive one.
- **Committed in:** `e4e59cc3` (Task 1 commit)

---

**Total deviations:** 1 discretionary optimization (explicitly sanctioned by the plan's own "Claude's discretion" clause), 0 auto-fixed bugs/gaps.
**Impact on plan:** The optimization is what made running the real full scan (rather than leaving it as a stub) feasible within this session -- it directly served the plan's own stated goal of avoiding a "ready-to-run but never actually run" outcome where the real cost allows otherwise.

## Issues Encountered

None. The full scan completed cleanly with 0 measurement failures, 0 missing candidates, and `failed_candidates=0` on every one of the 17 corrupt-frame lines.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- **DIAG-02 is intentionally NOT marked complete by this plan** (per the plan's own explicit instruction, carried from 02-03) -- 02-05's durable evidence write-up still remains before DIAG-02 as a whole can be closed.
- 02-05 has three real, on-disk findings to embed: (1) the av1_vaapi detection-N=20 PARTIAL-TRIAD result from 02-03 (0/20 corrupt, "immunity NOT proven"); (2) this plan's full qsvencc historical cross-match (0/17 confirmed swaps, mechanism note stays OPEN, best cross-scene PSNR 10.49-18.57 dB); (3) the av1_vaapi cross-match wiring, N/A this batch (0 corrupt observed).
- `scratch/repro/crossmatch_cache/` (~36 GB) is preserved on disk as the durable input backing `crossmatch_qsvencc.txt`, per the explicit instruction not to clean it up.
- All `scratch/repro/` runtime artifacts (Phase 1's `runs/`, `control_runs/`, this plan's `crossmatch_cache/`, `crossmatch_qsvencc.txt`, `crossmatch_qsvencc_smoke.txt`, and 02-02/02-03's `vaapi_runs/`, `report_vaapi.csv`, `summary_vaapi.txt`, plus this plan's `vaapi_runs/it21/`) remain on disk, preserved per this plan's execution constraint (no worktree, main working tree only, no `git clean`/`stash`/`reset --hard`).

---
*Phase: 02-in-container-triangulation-av1-vaapi*
*Completed: 2026-07-23*
