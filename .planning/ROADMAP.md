# Roadmap: QSV Concurrent-Encode Frame-Corruption Resolution

## Overview

This is a diagnose-and-resolve investigation, not a feature build. The journey starts by building one calibrated, control-validated measurement instrument (harness + paired ffmpeg `av1_qsv` immune control + environment fingerprint) and reproducing the known corruption signature in this environment. From there it works outward from cheap/unblocked levers (in-container `av1_vaapi` triangulation) to expensive/possibly-blocked levers (host-side firmware and `i915`→`Xe` migration, one variable per reboot), then lands on a measured, correctness-first workaround recommendation for `enpipe` plus a root-cause-independent defense-in-depth content gate, and closes with a synthesis report. Every phase's deliverable is a finding, a measurement, or a written recommendation — not shipped application code.

## Phases

**Phase Numbering:**

- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Harness, Control & Environment Fingerprinting** - Build and calibrate the reproduction harness, mandatory ffmpeg `av1_qsv` immune control, and environment fingerprint; confirm baseline corruption signature in this environment. (completed 2026-07-23)
- [x] **Phase 2: In-Container Triangulation — av1_vaapi** - Test the pure VA-API path as a cheap, unblocked data point that reshapes interpretation of later host-side and workaround findings. (completed 2026-07-23)
- [x] **Phase 2.1: Source-Level Fix — qsvencc Surface Sync & Lifetime** (INSERTED) - Diff qsvencc vs ffmpeg surface sync/lifetime under concurrency and validate source patches with the Phase-1 harness on an 8.31 build. (completed 2026-10-01)
- [ ] **Phase 3: Host-Side Levers — Firmware & Xe Migration** - Record what host-side changes are possible from this environment (DIAG-01); the GuC/HuC and Xe experiments are deferred to v2 (2026-10-01, after the source-level fix in 2.1).
- [ ] **Phase 4: Synthesis — Definition-of-Done Report** - Produce the final report: reproduction, the source-level fix and its upstream status, host-side capability, and what to do until the fix is upstream.

## Phase Details

### Phase 1: Harness, Control & Environment Fingerprinting

**Mode:** mvp
**Goal**: A calibrated, control-validated reproduction harness exists in this environment, with a recorded baseline corruption signature and environment fingerprint — nothing downstream is interpretable without this.
**Depends on**: Nothing (first phase)
**Requirements**: REPRO-01, REPRO-02, REPRO-03, REPRO-04, REPRO-05
**Success Criteria** (what must be TRUE):

  1. Environment fingerprint is recorded (`uname -r`, bound GPU driver i915/Xe, iHD/VA-API version, GuC/HuC firmware) with an explicit statement of whether it matches the affected host's `6.19.14-200.fc43` kernel.
  2. The 3-way concurrent `qsvencc` harness runs on scenes 923/928/1129 with the exact seek/trim from the handoff, writing all outputs only to an isolated writable workdir, never to `/data`.
  3. A bit-clean single-session reference frame (scene 923, offset 299) exists, and the harness classifies a test frame as corrupt via external-ffmpeg PSNR against that reference (`<30 dB` = corrupt; known signature ≈15.74 dB).
  4. Every qsvencc measurement in this phase has a paired ffmpeg `av1_qsv` immune-control run (HW h264_qsv decode + P010 + GopRefDist6 pyramid) reported alongside it, confirmed clean (0/N).
  5. Baseline corruption frequency and PSNR signature are reported over a detection-sized sample (~14-20 iterations), with detection-N explicitly distinguished from the larger validation-N required later for any "clean/fixed" claim.

**Plans**: 2 plans (1 execute + 1 gap-closure)
Plans:

- [x] 01-01-PLAN.md — Reproduction harness: environment probe, bit-clean reference, 3-way concurrent runner, PSNR classifier, paired av1_qsv immune control, detection-N=20 baseline report
- [x] 01-02-PLAN.md — Gap closure: re-run the completed harness on the main tree (no worktree isolation) to persist the missing on-disk fingerprint/reference/control-reference/report.csv/summary.txt evidence, verify the CR-01 fail-open fix end-to-end, and capture a git-tracked 01-EVIDENCE.md snapshot

### Phase 2: In-Container Triangulation — av1_vaapi

**Mode:** mvp
**Goal**: Determine whether the pure VA-API `av1_vaapi` path (bypassing oneVPL) is immune or corrupt under the same concurrency — the cheapest, fully unblocked differentiator, sequenced before any host-side ask.
**Depends on**: Phase 1
**Requirements**: DIAG-02
**Success Criteria** (what must be TRUE):

  1. An `av1_vaapi` 3-way concurrent run executes through the Phase 1 harness unmodified, with its own paired ffmpeg `av1_qsv` immune control in the same run.
  2. The result (clean vs corrupt, with frequency and signature if corrupt) is recorded, with its interpretation stated explicitly (e.g. clean strengthens the ffmpeg-migration case; corrupt too broadens the suspected fault beyond qsvencc's own pool code).

**Plans**: 5 plans
Plans:
**Wave 1**

- [x] 02-01-PLAN.md — av1_vaapi command builder (D-01) + D-02 capability probe (PTS/DTS reorder, P010, HW-VA decode → vaapi_probe.txt) + determinism-confirmed av1_vaapi self-reference (D-04/D-05)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 02-02-PLAN.md — Concurrent av1_vaapi runner: cmd_run_iter_vaapi (3-way measure + PSNR classify + paired av1_qsv control, D-06/D-11) + cmd_run_batch_vaapi + smoke run (extra_hw_frames under concurrency, A2)

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 02-03-PLAN.md — Detection-N=20 batch (D-07): print_batch_summary_vaapi with triad caveat, D-08 gated escalation, and explicit SC#2 interpretation; live run → report_vaapi.csv + summary_vaapi.txt

**Wave 4** *(blocked on Wave 3 completion)*

- [x] 02-04-PLAN.md — Content-origin cross-match (D-09/D-10): content_cross_match + cross-match-qsvencc closing Phase-1's deferred mechanism note; av1_vaapi corrupt-path wiring

**Wave 5** *(blocked on Wave 4 completion)*

- [x] 02-05-PLAN.md — Durable git-tracked 02-EVIDENCE.md: verbatim outputs + DIAG-02 mapping + explicit SC#2 interpretation + D-03 triad caveat + triangulation vs Phase-1 baseline

### Phase 02.1: Source-Level Fix — qsvencc Surface Sync & Lifetime (INSERTED)

**Mode:** mvp
**Goal:** Find and fix, in qsvencc source (8.31 base), why concurrent `--avhw` + P010 + B-pyramid sessions emit a corrupted frame while ffmpeg `av1_qsv` with the same driver/kernel/trigger triad stays clean — by diffing how each manages surface synchronization and surface lifetime, then validating candidate patches with the unmodified Phase-1 harness.
**Requirements**: FIX-01
**Depends on:** Phase 2; upstream 8.31 re-check (`.planning/research/UPSTREAM-8.31-RECHECK.md`)
**Plans:** 4/4 plans complete

**Why now (decided 2026-10-01):** 8.31 still reproduces (923 7/20, 1129 6/20, control 0/20). ffmpeg immunity on the SAME kernel contradicts the "root cause is kernel-only" conclusion — the driver can isolate sessions, so qsvencc's usage pattern differs. The earlier "source-patch line exhausted" verdict covered only surface attributes (`rt_format`, `UsageHint`) and `--async-depth 1`; synchronization and surface lifetime were never examined. Phase 3 stays in the roadmap (needs operator action on the host).

**Hypotheses to examine (not yet ranked):**
1. Sync ordering: when a decode/VPP output surface is handed downstream vs `SyncOperation`/`vaSyncSurface` completion (qsvencc vs ffmpeg).
2. Surface lifetime/reuse: a surface returned to the per-edge pool (`AllocFrames()`, `qsv_pipeline.cpp`) while still referenced — B-pyramid + GopRefDist 6 holds references longer.
3. External allocator (qsvencc `QSVAllocatorVA`) vs ffmpeg's `AVHWFramesContext` per component.

**Success Criteria** (what must be TRUE):
  1. A root-cause hypothesis is confirmed or refuted by measurement for each candidate examined (harness, N=20 detection, paired control).
  2. Any patch claimed as a fix passes ~60 zero-failure 3-way iterations on scenes 923/1129 (rule-of-three), with control 0/N and no regression in single-session bit-exactness.
  3. Working tree: build in worktree `/workspaces/qsvenc-831` (tag 8.31); harness copy in `scratch/repro-831/` (Phase-1 baseline in `scratch/repro/` untouched); run on main tree, worktree isolation OFF for `scratch/` outputs.

Plans:
**Wave 1**
- [x] 02.1-01-PLAN.md — stock positive control through the candidate pipeline (tracer); FIX-01 registration; D-01/D-04 on record; X1 pool dump, X2/X3 shim screens

**Wave 2** *(blocked on Wave 1 completion)*
- [x] 02.1-02-PLAN.md — diag/surf-trace build: in-memory surface trace + default-off coarse toggles; bit-exactness; X4 D-03 reproduce gate + D-vs-S trace analysis

**Wave 3** *(blocked on Wave 2 completion)*
- [x] 02.1-03-PLAN.md — lever screens X5/X6/X7a/X7b (+ conditional D-06 allocator); per-hypothesis verdicts; operator path decision

**Wave 4** *(blocked on Wave 3 completion)*
- [x] 02.1-04-PLAN.md — fix commit + 60-iteration validation + md5 + bit-exactness + fps + format-patch (or negative close); upstream draft update only

### Phase 3: Host-Side Levers — Firmware & Xe Migration

**Mode:** mvp
**Goal**: Empirically record which host-side changes are possible from this environment (kernel cmdline/modprobe, firmware, reboot, privilege level), so the deferred host-side experiments can be scoped honestly.
**Depends on**: Phase 1
**Requirements**: DIAG-01
**Scope change (2026-10-01):** Phase 2.1 delivered an application-level fix (rigaya/QSVEnc#316). The GuC/HuC firmware and `i915`→`Xe` experiments (DIAG-03/04/05) only remain useful to test the "root cause below the API" hypothesis for a report to Intel; they need host reboots and operator action and are deferred to v2.
**Success Criteria** (what must be TRUE):

  1. Host-side change capability in this environment is empirically determined and recorded (kernel cmdline/modprobe access, firmware update access, reboot access, privilege level) — each reported honestly as available or blocked.
  2. The deferred levers (GuC/HuC update, `i915`→`Xe`) are listed with what they would test and what they need from the host owner, so they can be picked up later without re-analysis.

**Plans**: 1 plan
Plans:
**Wave 1**
- [ ] 03-01-PLAN.md — read-only capability probe run in the container (tracer) and on the NAS host (operator checkpoint); DIAG-01 capability matrix, GuC/HuC/DMC + firmware baseline and i915 encode-path baseline in 03-EVIDENCE.md; deferred-lever runbook 03-RUNBOOK.md (L1 GuC/HuC firmware, L2 i915 -> Xe)

### Phase 4: Synthesis — Definition-of-Done Report

**Mode:** mvp
**Goal**: Produce the final Definition-of-Done report: reproduction result, the source-level fix and its upstream status, host-side capability, open questions, and guidance for qsvencc users until the fix is in an official release.
**Depends on**: Phases 1, 2, 2.1, 3
**Requirements**: DONE-01
**Scope change (2026-10-01):** the former Phase 4 (workaround recommendation and content-verification gate for `enpipe`) was removed — `enpipe` is not part of this repository and the fix now lives in qsvencc itself. A short "until fixed upstream" section replaces it.
**Success Criteria** (what must be TRUE):

  1. The report covers: reproduction in this environment; mechanism (stale input surface of the same session at the last mini-GOP anchor before the IDR; behaves as a timing window); the fix (rigaya/QSVEnc#316, release `8.31-vppsync1`) with its validation numbers and limits (statistical bound, root cause below the API not proven); host-side capability (Phase 3) and the deferred levers; open questions (mid-stream drift observations, other configurations such as #308).
  2. An "until fixed upstream" section tells qsvencc users what to do: use the patched build, or fall back to a configuration that avoids the trigger (e.g. `--avsw` or one encode per GPU), with each option marked as measured or not measured in this milestone.
  3. The debug-history status entry is updated to reflect an application-level workaround with upstream PR pending — not a proven root-cause fix.

**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 2.1 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Harness, Control & Environment Fingerprinting | 2/2 | Complete   | 2026-07-23 |
| 2. In-Container Triangulation — av1_vaapi | 5/5 | Complete   | 2026-07-23 |
| 2.1. Source-Level Fix — qsvencc Surface Sync & Lifetime | 4/4 | Complete   | 2026-10-01 |
| 3. Host-Side Levers — Firmware & Xe Migration | 0/TBD | Not started | - |
| 4. Synthesis — Definition-of-Done Report | 0/TBD | Not started | - |
