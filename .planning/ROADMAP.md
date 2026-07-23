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
- [ ] **Phase 3: Host-Side Levers — Firmware & Xe Migration** - Exhaust the untried in-place kernel/driver levers, one variable per reboot, honestly reporting blocked levers as recommended-but-blocked.
- [ ] **Phase 4: Workaround Recommendation & Defense-in-Depth Gate** - Deliver a measured, correctness-first `enpipe` workaround recommendation and a root-cause-independent content-verification gate design.
- [ ] **Phase 5: Synthesis — Definition-of-Done Report** - Produce the final handoff report synthesizing reproduction, host-side, and recommendation findings.

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
  5. Baseline corruption frequency and PSNR signature are reported over a detection-sized sample (~15-20 iterations), with detection-N explicitly distinguished from the larger validation-N required later for any "clean/fixed" claim.

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

### Phase 3: Host-Side Levers — Firmware & Xe Migration

**Mode:** mvp
**Goal**: Exhaust the untried in-place host-side kernel/driver levers (GuC/HuC firmware update, `i915`→`Xe` migration), one variable per reboot cycle, with blocked levers honestly reported rather than silently skipped.
**Depends on**: Phase 1 (harness reused unmodified); Phase 2 result informs interpretation
**Requirements**: DIAG-01, DIAG-03, DIAG-04, DIAG-05
**Success Criteria** (what must be TRUE):

  1. Host-side change capability in this environment is empirically determined and recorded (kernel cmdline/modprobe access, firmware update access, reboot access, privilege level) — reported honestly as available or blocked before any lever is attempted.
  2. If available: GuC/HuC firmware update is tested in isolation, with its own before/after paired control-plus-harness re-run, and its corruption-rate change against the Phase 1 baseline is recorded.
  3. If available: the `i915`→`Xe` driver switch is tested in isolation, gated on confirming the same low-power AV1 encode path is still active (dmesg GuC/HuC lines + iHD/`--check-features` logging) before any "clean" result under Xe is trusted; corruption-rate change against baseline is recorded.
  4. Every lever's experiment log shows exactly one changed variable versus the immediately prior measured state — no two host-side changes applied in the same reboot cycle.
  5. Any lever unavailable in this environment is explicitly reported as "recommended but blocked — requires host-owner action," never silently omitted from the findings.

**Plans**: TBD

### Phase 4: Workaround Recommendation & Defense-in-Depth Gate

**Mode:** mvp
**Goal**: Deliver a correctness-first, measured workaround recommendation for `enpipe`, plus a root-cause-independent per-frame content-verification gate design — both ship regardless of whether Phase 3 finds a host-side fix.
**Depends on**: Phase 1 (metric engine reused); informed by, but not blocked on, Phase 2/3 outcomes
**Requirements**: WORK-01, WORK-02, WORK-03, WORK-04, GUARD-01, GUARD-02
**Success Criteria** (what must be TRUE):

  1. Workaround A (`--avsw`, SW-decode + HW-encode) is measured for cleanliness and throughput in this environment to a validation-grade sample (~60 zero-failure runs, rule-of-three) before any "clean" claim is made.
  2. Workaround B (`--jobs 1` serialization) throughput is measured fresh in this environment as the simplest correctness-guaranteed comparison baseline.
  3. Workaround C (migration to ffmpeg `av1_qsv`) DV/HDR passthrough risk is characterized in writing (not prototyped), timeboxed as risk-assessment only.
  4. A written recommendation exists naming the correctness-first workaround for `enpipe`, backed by measured throughput numbers per option and an explicit residual-corruption-rate threshold for "production ready."
  5. A per-frame (worst-percentile, not mean/aggregate) content-verification gate design exists — VMAF/PSNR of the final joined `movie.obu` vs source — with its `enpipe` integration contract specified (where it runs, pass/fail threshold, VMAF locale/CSV field-16-vs-17 parsing gotchas) as a design deliverable.

**Plans**: TBD

### Phase 5: Synthesis — Definition-of-Done Report

**Mode:** mvp
**Goal**: Produce the final Definition-of-Done report synthesizing reproduction, host-side, and recommendation findings into an actionable handoff.
**Depends on**: Phases 1-4
**Requirements**: DONE-01
**Success Criteria** (what must be TRUE):

  1. The Definition-of-Done report (handoff §10 format) is written, covering: reproduction result in this environment, host-side conclusion (which levers were tried or reported blocked, with results), and the `enpipe` workaround recommendation with its content-gate spec reference.
  2. The debug-history status entry is updated — kept at `root_cause_found`, or explicitly raised to `fixed` only if a host-side fix was confirmed at validation-grade sample size (~60+ zero-failure runs) in Phase 3.

**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4 → 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Harness, Control & Environment Fingerprinting | 2/2 | Complete   | 2026-07-23 |
| 2. In-Container Triangulation — av1_vaapi | 5/5 | Complete   | 2026-07-23 |
| 3. Host-Side Levers — Firmware & Xe Migration | 0/TBD | Not started | - |
| 4. Workaround Recommendation & Defense-in-Depth Gate | 0/TBD | Not started | - |
| 5. Synthesis — Definition-of-Done Report | 0/TBD | Not started | - |
