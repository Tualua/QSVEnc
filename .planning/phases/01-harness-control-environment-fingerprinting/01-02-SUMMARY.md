---
phase: 01-harness-control-environment-fingerprinting
plan: 02
subsystem: testing
tags: [bash, qsvencc, ffmpeg, av1_qsv, psnr, gpu-concurrency, va-api, oneVPL, evidence-recovery]

# Dependency graph
requires:
  - "scratch/repro/harness.sh + lib.sh -- completed, hardened harness from Phase 1 Plan 1 (CR-01 + WR-01..WR-10 already fixed)"
provides:
  - "scratch/repro/fingerprint.txt -- on-disk environment fingerprint, kernel_matches_affected_host: YES, graceful UNAVAILABLE degradation for blocked GuC/HuC dmesg probe"
  - "scratch/repro/reference/, control_reference/ -- on-disk bit-clean qsvencc references (923/928/1129) + once-only ffmpeg av1_qsv control references (923/928/1129), md5-determinism + frame-count (340) gated"
  - "scratch/repro/report.csv + summary.txt -- on-disk N=20 baseline (60 data rows, N_actual=20): 923/299 9/20 (45.0%) CI [0.258,0.658] mean 12.96dB stddev 0.18dB; 1129/299 8/20 (40.0%); 928/96 0/20; paired av1_qsv control 0/20 non-clean"
  - ".planning/phases/01-harness-control-environment-fingerprinting/01-EVIDENCE.md -- git-tracked durable snapshot of fingerprint.txt + report.csv + summary.txt, survives scratch/ cleanup"
affects: [02-av1-vaapi-triangulation, 03-host-side-levers, 04-workaround-recommendation-content-gate]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Git-tracked durable evidence snapshot pattern: git-ignored runtime outputs are duplicated verbatim into a committed .md file so a future scratch-workdir cleanup (or another worktree-remove) cannot silently re-erase a recorded baseline"

key-files:
  created:
    - .planning/phases/01-harness-control-environment-fingerprinting/01-EVIDENCE.md
  modified:
    - .planning/REQUIREMENTS.md
    - .planning/phases/01-harness-control-environment-fingerprinting/01-01-SUMMARY.md

key-decisions:
  - "Ran entirely on the main working tree (no worktree isolation) per the plan's hard execution_constraint, to avoid repeating the original failure mode where git worktree remove deleted every git-ignored scratch/repro/ output"
  - "Tasks 1 and 2 produce only git-ignored runtime artifacts (scratch/repro/fingerprint.txt, reference/, control_reference/, report.csv, summary.txt, runs/, control_runs/) -- there is nothing to stage/commit to git for those tasks; only Task 3 (01-EVIDENCE.md + REQUIREMENTS.md + 01-01-SUMMARY.md reconciliation) produces a git commit"
  - "Reconciled 01-01-SUMMARY.md and REQUIREMENTS.md to the ACTUAL re-run numbers rather than the original unverified narration, per the plan's explicit 'never leave a figure the re-run contradicts' instruction -- corrected figures differ from the original narration (923/299 went from 6/20 30.0% to 9/20 45.0%; 1129/299 from 9/20 45.0% to 8/20 40.0%; signature mean from ~12.84dB to ~12.96dB) but both runs land within the documented ~33-65% expected range and agree on kernel match, classifier behavior, 928/96 always-clean, and 0/20 clean control"

requirements-completed: [REPRO-01, REPRO-02, REPRO-03, REPRO-04, REPRO-05]

# Metrics
duration: 20min
completed: 2026-07-23
---

# Phase 1 Plan 2: Harness Gap-Closure — Persisted Baseline & Evidence Snapshot Summary

**Re-ran the already-hardened `scratch/repro/harness.sh` (probe, reference, run-batch 20) in place on the main working tree — never inside a worktree — to regenerate the git-ignored fingerprint/reference/report artifacts the first execution lost to `git worktree remove`, and captured a git-tracked `01-EVIDENCE.md` durable snapshot so the Phase 1 baseline (923/299 corrupts 9/20 = 45.0%, 1129/299 8/20 = 40.0%, 928/96 clean, paired av1_qsv control clean 0/20) can never again be silently lost.**

## Performance

- **Duration:** ~20 min (fingerprint probe: seconds; reference generation: ~1 min; run-batch 20: ~13 min GPU-bound; evidence write + reconciliation: ~5 min)
- **Started:** 2026-07-23T06:25:00Z (approx)
- **Completed:** 2026-07-23T06:43:00Z
- **Tasks:** 3/3 completed
- **Files modified (git-tracked):** 3 (`01-EVIDENCE.md` created, `.planning/REQUIREMENTS.md`, `01-01-SUMMARY.md`)
- **Files produced (git-ignored, on disk under `scratch/repro/`):** `fingerprint.txt`, `reference/*.obu` + `*.png` (923/928/1129), `control_reference/*.obu` + `*.png` (923/928/1129), `report.csv`, `summary.txt`, `runs/it01..it20/`, `control_runs/it01..it20/`

## Accomplishments

- Confirmed the environment before executing: `git rev-parse --show-toplevel` = `/workspaces/QSVEnc`, `git worktree list` showed only the main tree, GPU idle (no `renderD128` clients), `scratch/repro/` contained only `harness.sh` + `lib.sh` (the exact gap state described in the plan).
- **Task 1:** Ran `harness.sh probe` → `scratch/repro/fingerprint.txt` (kernel `6.19.14-200.fc43.x86_64` matches the affected host: `kernel_matches_affected_host: YES`; `guc_huc` line correctly degrades to `UNAVAILABLE: dmesg blocked` rather than aborting). Ran `harness.sh reference` (GPU-bound, several minutes) → generated the md5-determinism-verified bit-clean qsvencc references for all three scenes (923/928/1129) with the 340-frame-count gate passing, plus the once-only ffmpeg `av1_qsv` control references for all three scenes, all under `require_gpu_exclusive`.
- **Task 2:** Ran the full `harness.sh run-batch 20` (long-running real-GPU batch, ~13 min observed) to completion with zero timeouts/aborts. Produced `report.csv` (61 lines = header + 60 data rows = 20 iterations × 3 scenes, `N_actual=20`) and `summary.txt`. Confirmed the CR-01/MEASURE_FAILURE fail-open fix end-to-end: an `awk` scan of the produced `report.csv` found zero `status=OK` rows with an empty/`NA` `psnr_db` or `corrupt` value; all 20 iterations landed `OK`/`control_clean=1` with zero `EXEC_FAILURE`/`TIMEOUT`/`MEASURE_FAILURE`/`CONTROL_INVALID` rows to exercise the exclusion path this run (the exclusion-breakdown line in `summary.txt` still correctly reports `0` excluded).
- **Task 3:** Wrote `.planning/phases/01-harness-control-environment-fingerprinting/01-EVIDENCE.md` embedding the verbatim contents of `fingerprint.txt`, `report.csv`, and `summary.txt`, with a REPRO-01..05 → artifact mapping and a reconciliation note. Updated `.planning/REQUIREMENTS.md`'s traceability table to point REPRO-01..05 at the 01-EVIDENCE.md re-run evidence. Corrected `01-01-SUMMARY.md`'s frontmatter `provides` line and body to flag the original figures as unverified narration and point to the real, corroborated numbers.

## Observed baseline (actual, from this re-run — see 01-EVIDENCE.md for verbatim source)

- **923/299 (primary hotspot):** 9/20 corrupt (45.0%), 95% Wilson CI [0.258, 0.658]. Observed corrupt-frame PSNR values: `[12.82, 13.22, 12.82, 12.82, 13.22, 12.91, 12.82, 13.22, 12.82]` dB — mean 12.96 dB, stddev 0.18 dB, `signature_stable_across_iterations=True`.
- **1129/299 (confirmatory hotspot):** 8/20 corrupt (40.0%).
- **928/96 (confirmatory hotspot):** 0/20 corrupt — stayed clean across all 20 iterations.
- **Paired ffmpeg `av1_qsv` immune control:** 0/20 non-clean/invalidated — confirmed clean across every iteration.
- **N_requested=20, N_actual=20, 0 excluded** (0 EXEC_FAILURE, 0 TIMEOUT, 0 MEASURE_FAILURE, 0 CONTROL_INVALID).
- This is the DETECTION sample only (N=20); the larger ~60 validation-N is reserved for later fix/clean claims and was not run here, matching D-07.

These numbers differ from the original 01-01-SUMMARY.md narration (923/299 6/20 30.0%, 1129/299 9/20 45.0%, ~12.84 dB) because that narration was never corroborated on disk — this plan's re-run is the first verified measurement in this environment. Both runs land within the documented ~33-65% expected corruption-rate range and agree on kernel match, classifier behavior (threshold-only, never hardcoded equality), 928/96 staying clean, and the control staying 0/20 clean, so this is read as run-to-run variance within a real, reproducing bug — not a harness defect.

## Task Commits

Tasks 1 and 2 produce ONLY git-ignored runtime artifacts under `scratch/repro/` (`fingerprint.txt`, `reference/`, `control_reference/`, `report.csv`, `summary.txt`, `runs/`, `control_runs/` — all excluded by `.gitignore`'s `/scratch/repro/*` rule save for the two tracked `.sh` files). There is nothing to `git add`/commit for those two tasks; this is expected given the plan's own framing that these are git-ignored runtime deliverables, and `git status --short` was checked after each to confirm no untracked/trackable files were left behind.

1. **Task 1: Persist environment fingerprint + bit-clean/control references** — no git commit (git-ignored artifacts only); verified via `test -f`/`grep` gate, all checks passed.
2. **Task 2: Run the detection-N=20 batch, confirm CR-01/MEASURE_FAILURE semantics** — no git commit (git-ignored artifacts only); verified via the full automated gate (header row, ≥60 data rows, `control_clean` column, `N_requested: 20`, `N_actual >= 20`, `excluded from` line present, zero fail-open `OK` rows), all checks passed.
3. **Task 3: Persist git-tracked evidence snapshot + reconcile REQUIREMENTS.md/01-01-SUMMARY.md** — `c502fcfe` (docs)

## Files Created/Modified

- `.planning/phases/01-harness-control-environment-fingerprinting/01-EVIDENCE.md` (created) — git-tracked verbatim snapshot of `fingerprint.txt`, `report.csv` (header + 60 rows), `summary.txt`, plus a REPRO-01..05 → artifact mapping and a reconciliation note explaining the numeric delta from the original (destroyed) execution.
- `.planning/REQUIREMENTS.md` (modified) — REPRO-01..05 traceability rows now reference `01-EVIDENCE.md` as the re-run evidence source, with the actual observed figures inline.
- `.planning/phases/01-harness-control-environment-fingerprinting/01-01-SUMMARY.md` (modified) — added a correction banner (frontmatter `provides` line + body header note) pointing to `01-EVIDENCE.md` as the source of truth; original unverified figures kept for historical record but explicitly flagged as unverified/superseded.
- `scratch/repro/fingerprint.txt`, `scratch/repro/reference/*`, `scratch/repro/control_reference/*`, `scratch/repro/report.csv`, `scratch/repro/summary.txt`, `scratch/repro/runs/it01..it20/*`, `scratch/repro/control_runs/it01..it20/*` (created, git-ignored) — the actual on-disk deliverables this plan exists to produce and persist.
- `scratch/repro/harness.sh`, `scratch/repro/lib.sh` — **unchanged** (`git diff --stat` confirmed empty before every commit, per the hard constraint that this plan executes but does not modify the harness).

## Decisions Made

- **Main-tree-only execution, no worktree isolation (per plan's hard `execution_constraint`):** confirmed `git rev-parse --show-toplevel` = `/workspaces/QSVEnc` and `git worktree list` showed only the main tree before starting, and never ran `git worktree`/`git stash` at any point. This is the exact mechanism the plan exists to avoid repeating.
- **No per-task commit for Tasks 1 and 2:** since their only outputs are git-ignored runtime artifacts (by design — `scratch/repro/*` outputs stay ignored per `01-01-SUMMARY.md`'s `.gitignore` decision), there was no git-trackable change to stage after either task. This is consistent with the plan's own repeated framing ("the deliverables are git-ignored runtime outputs") and was not treated as a gap — `git status --short` was checked after each task to confirm no untracked files were silently left behind.
- **Never deleted any generated artifact:** `fingerprint.txt`, `reference/`, `control_reference/`, `report.csv`, `summary.txt` all remain on disk under `scratch/repro/` after this plan completes, per the plan's explicit prohibition against repeating the prior verification spot-check's deletion of `fingerprint.txt`.

## Deviations from Plan

None — plan executed exactly as written. All three tasks' automated `<verify>` gates passed on the first real run; no auto-fixes, no architectural changes, no blocking issues encountered. `harness.sh`/`lib.sh` confirmed unchanged (`git diff --stat` empty) before every commit.

## Issues Encountered

None. GPU was idle at dispatch and remained exclusive throughout (no `require_gpu_exclusive` aborts); no competing GPU work was run. The full N=20 batch completed with 0 EXEC_FAILURE/TIMEOUT/MEASURE_FAILURE/CONTROL_INVALID iterations, so the CR-01 fail-open-exclusion path (excluding failed iterations from the corruption-fraction denominator) was confirmed present-and-correct in the summary's exclusion-breakdown line but was not exercised by an actual failure this run (0 excluded, matching a clean run).

## User Setup Required

None — no external service configuration required. All tooling (`qsvencc`, `ffmpeg`, `vainfo`) was already installed and confirmed working; the source media at `/data/downloads/Cold.Eyes.2013.Bluray.Remux.mkv` was read-only and untouched (`git diff --stat` on `harness.sh`/`lib.sh` stayed empty, and no output path construction was modified — all outputs remained hardcoded under `scratch/repro/`).

## Next Phase Readiness

- Phase 1's on-disk, control-validated baseline now genuinely exists in this environment (not just narrated): `scratch/repro/fingerprint.txt`, `reference/`, `control_reference/`, `report.csv`, `summary.txt` are all present, and the numbers are additionally duplicated in the git-tracked `01-EVIDENCE.md` so a future scratch-workdir cleanup cannot silently re-erase them.
- Phases 2-5 can diff their own measurements against this corroborated baseline: primary hotspot 923/299 at 9/20 (45.0%, CI [0.258, 0.658]), confirmatory hotspots 1129/299 (8/20) and 928/96 (0/20), and the paired `av1_qsv` control at 0/20.
- Environment fingerprint confirms this is the SAME kernel as the affected host (`kernel_matches_affected_host: YES`), so Phase 3's host-side levers (i915→Xe, GuC/HuC firmware) remain the primary untried path.
- The Mechanism-vs-symptom NOTE printed in `summary.txt` (and captured verbatim in `01-EVIDENCE.md`) explicitly defers confirming that the corrupt frame's CONTENT originates from a concurrent session's scene to Phase 2 — this batch establishes the PSNR-drop symptom only.
- No blockers. `scratch/repro/` retains all 20 iterations' raw `.obu`/`.png`/log outputs for downstream phases to inspect or diff against directly.

## Known Stubs

None. No hardcoded empty values, placeholder text, or unwired data sources were introduced by this plan — it only executes the existing harness and writes documentation/evidence files.

## Threat Flags

None. This plan introduced no new files, endpoints, auth paths, or schema changes beyond what the already-reviewed `<threat_model>` in `01-02-PLAN.md` covers (T-01-01 output-path safety, T-01-04 scoped-kill safety, T-02-01 evidence-file information disclosure — all already mitigated by the shipped harness or accepted as low-value local-only data).

## Self-Check: PASSED

Verified on disk:
- `scratch/repro/fingerprint.txt` — FOUND
- `scratch/repro/reference/chunk923_ref.obu` — FOUND
- `scratch/repro/reference/frame299_ref.png` — FOUND
- `scratch/repro/control_reference/c923_ffref.obu` — FOUND
- `scratch/repro/report.csv` (61 lines: header + 60 data rows) — FOUND
- `scratch/repro/summary.txt` — FOUND
- `.planning/phases/01-harness-control-environment-fingerprinting/01-EVIDENCE.md` — FOUND, confirmed git-tracked (`git check-ignore` returns non-zero)
- `.planning/REQUIREMENTS.md` — FOUND, updated
- `.planning/phases/01-harness-control-environment-fingerprinting/01-01-SUMMARY.md` — FOUND, updated

Verified in git log: commit `c502fcfe` ("docs(01-02): persist git-tracked evidence snapshot of main-tree GPU re-run") present in `git log --oneline`.

`harness.sh`/`lib.sh` confirmed unchanged throughout (`git diff --stat` empty at every checkpoint).

---
*Phase: 01-harness-control-environment-fingerprinting*
*Completed: 2026-07-23*
