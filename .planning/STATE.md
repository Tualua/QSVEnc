---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
current_phase: 3
current_phase_name: Host-Side Levers — Firmware & Xe Migration
status: ready_to_plan
stopped_at: Phase 3 complete (1/1) — ready to discuss Phase 4
last_updated: 2026-10-24T17:11:16.818Z
last_activity: 2026-10-24 — 03-01 completed
progress:
  total_phases: 5
  completed_phases: 4
  total_plans: 12
  completed_plans: 12
  percent: 80
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-07-23)

**Core value:** Correctness is non-negotiable — no encoded frame may ever silently contain content from another concurrent session.
**Current focus:** Phase 4 — synthesis — definition of done report

## Current Position

Phase: 4
Plan: Not started
Status: Ready to plan
Last activity: 2026-10-24

Progress: [██████████] 100%

## Performance Metrics

**Velocity:**

- Total plans completed: 12
- Average duration: - min
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01 | 2 | - | - |
| 02 | 5 | - | - |
| 02.1 | 4 | - | - |
| 3 | 1 | - | - |

**Recent Trend:**

- Last 5 plans: none yet
- Trend: N/A

*Updated after each plan completion*
| Phase 01 P02 | 20min | 3 tasks | 3 files |
| Phase 02 P01 | 20min | 2 tasks | 1 files |
| Phase 02 P02 | 15min | 2 tasks | 1 files |
| Phase 02 P03 | 20min | 2 tasks | 1 files |
| Phase 02 P04 | 92min | 3 tasks | 1 files |
| Phase 02 P05 | 15min | 2 tasks | 1 files |
**Per-Plan Metrics:**

| Plan | Duration | Tasks | Files |
|------|----------|-------|-------|
| Phase 02.1 P01 | 52 min | 3 tasks | 3 files |
| Phase 02.1 P02 | 26 min | 3 tasks | 5 files |
| Phase 02.1 P03 | multi-session | 4 tasks | 1 files |
| Phase 02.1 P04 | continuation ~1.5h | 4 tasks | 6 files |
| Phase 03 P01 | checkpoint-split | 4 tasks | 5 files |

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Roadmap: Investigation framed as 5 coarse phases (harness/control → av1_vaapi triangulation → host-side levers → workaround+gate → synthesis), not a code build.
- Roadmap: Defense-in-depth gate design folded into Phase 4 (Workaround Recommendation) rather than a standalone phase, per coarse granularity.
- Roadmap: GPU-exclusivity and single-variable-per-reboot discipline apply as standing operating rules across all phases (Pitfalls 1 and 3), not as one-time setup steps.
- [Phase 01]: Ran plan 01-02 entirely on the main working tree (no worktree isolation) per its hard execution_constraint, regenerating the git-ignored scratch/repro/ baseline the first execution's git worktree remove had destroyed — Prevents repeating the original evidence-loss failure mode; observed re-run baseline (923/299 9/20 45.0%, 1129/299 8/20 40.0%, 928/96 0/20, control 0/20) is now persisted both on disk and in a git-tracked 01-EVIDENCE.md snapshot
- [Phase 02]: D-02 probe result on Arc A380: reorder UNSUPPORTED, P010 ACTIVE, HW-decode ACTIVE -> PARTIAL-TRIAD
- [Phase 02]: Fixed broken ffprobe 'dts' field name in D-02 reorder probe (real field is pkt_dts); documented recipe would have produced a false ACTIVE reorder verdict on every frame
- [Phase 02]: Extended run-batch-vaapi reference preflight to require both av1_vaapi self-references and av1_qsv control references before starting
- [Phase 02]: Live 2-iteration smoke run confirmed Assumption A2 -- extra_hw_frames=64 holds under real 3-way concurrent contention, zero EXEC_FAILURE
- [Phase 02]: Live detection-N=20 av1_vaapi batch (03): 0/20 corrupt all three scenes, control 0/20 clean, PARTIAL-TRIAD (reorder unsupported), gated verdict do-NOT-escalate, immunity NOT proven (D-08/D-03)
- [Phase 02]: Full historical qsvencc content-origin cross-match (D-09/D-10) completed: 0/17 corrupt frames confirmed as cross-session content swaps (>=35 dB); best cross-scene PSNR 10.49-18.57 dB -- Phase 1's Mechanism-vs-symptom NOTE stays OPEN, not closed
- [Phase 02]: av1_vaapi corrupt-path cross-match wired and verified N/A (0/20 corrupt this batch, PARTIAL-TRIAD, as expected)
- [Phase 02]: 02-EVIDENCE.md confirmed all four av1_vaapi source files present/current before writing -- no harness re-run needed
- [2026-10-01]: Upstream QSVEnc 8.23–8.31 do not fix the bug — 8.31 (r4604) reproduces 923 7/20, 1129 6/20, 928 0/20, control 0/20, corrupt PSNR 12.83 dB. Evidence: .planning/research/UPSTREAM-8.31-RECHECK.md. Corroboration: rigaya/QSVEnc #308.
- [2026-10-01]: Direction chosen — new attempt to FIX via qsvencc source (Phase 02.1: surface sync & lifetime vs ffmpeg), executed before Phase 3. Rationale: ffmpeg is clean on the same kernel, so the "kernel-only" root-cause verdict is contradicted; prior "source line exhausted" covered only surface attributes/async-depth.
- [2026-10-01]: Operator communication language is Russian (config response_language: Russian).
- [Phase 02]: Interpretation branch matched the REAL PARTIAL-TRIAD/0-20-clean data: immunity NOT proven (not the full-triad-clean or corrupt branch)
- [Phase 02.1]: 02.1-01: instrument validated via T0b-stock fallback; md5 oracle (d01_md5) mandatory on every candidate because cand_screen is fail-open for a mid-stream drift mode
- [Phase 02.1]: 02.1-01: X2 refutes M6 (tune/scenario inert); X3 --max-procfps 60 gives 0/20 tail corruption = timing-sensitive; pools DEC->VPP 23, VPP->ENC 20
- [Phase 02.1]: 02.1-02: D-03 gate FAIL with tracing on (6/40 < 7, control 0/20) - traces not trusted; 02.1-03 uses D-05 coarse toggles of diag-T2 with tracing OFF after a fresh toggles-off positive control
- [Phase 02.1]: 02.1-02: diag-T2 shows mid-stream drift mode 6/60 md5-D cells; md5 oracle mandatory on every batch
- [Phase 02.1]: X9s_sham_sync_0of20_supports_timing_final_path_fix-path_X5_timing-workaround
- [Phase 02.1]: Upstream PR on 15cd6879 prepared as draft for discussion (pr/vpp-enc-sync 362bde63); upstream output identical to 8.31 references; single-session cost re-measured ~0 to -3 percent (earlier -9..-19 superseded); not pushed
- [Phase 03]: 03-01: GPU replaced (A380 on i915 -> Arc Pro B50 on xe) between probes; levers L1/L2 marked not applicable to current hardware, kept in runbook for an A380 reinstall
- [Phase 03]: 03-01: Operator policy: no restart of the NAS; CAP-REBOOT blocked on host (operator-declared); change abilities operator-declared (not tested)

### Pending Todos

None yet.

### Blockers/Concerns

- Phase 3 (host-side levers) may be entirely blocked in this environment — container may lack host reboot/root/firmware access. Must be reported as "recommended but blocked," not treated as a failure.
- Xe/HuC support status for DG2/Alchemist is dated (~Sept 2025 in research); must be re-verified live via dmesg before Phase 3 is finalized.
- Every "clean/fixed" claim (Phases 3-4) requires ~60 zero-failure runs (rule-of-three); detection-only samples (~15-20) are insufficient for those claims.

### Roadmap Evolution

- Phase 4 removed: former Phase 4 (enpipe workaround + content gate) removed: enpipe not in this repo, bug fixed in qsvencc (2.1); Phase 5 renumbered to 4 with an 'until fixed upstream' section
- Phase 3 edited: reduced to DIAG-01; DIAG-03..05 (GuC/HuC, Xe) deferred to v2

## Deferred Items

Items acknowledged and carried forward from previous milestone close:

| Category | Item | Status | Deferred At |
|----------|------|--------|-------------|
| Tech debt | DEBT-01: correct re-encode of the corrupted shipped Cold Eyes output, at user's discretion after a fix is chosen | Deferred to v2 | Project init |

## Session Continuity

Last session: 2026-10-24T17:07:01.540Z
Stopped at: Completed 03-01-PLAN.md (Phase 3 complete, ready for verification)
Resume file: .planning/phases/03-host-side-levers-firmware-xe-migration/03-01-PLAN.md
