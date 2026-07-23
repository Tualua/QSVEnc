# Requirements: QSV Concurrent-Encode Frame-Corruption Resolution

**Defined:** 2026-07-23
**Core Value:** Correctness is non-negotiable — no encoded frame may ever silently contain content from another concurrent session.

## v1 Requirements

Requirements for this investigation milestone. Each maps to a roadmap phase.

### Reproduction & Control

- [x] **REPRO-01**: Fingerprint the environment — record `uname -r`, the bound GPU driver (i915 vs Xe), iHD/VA-API version, and GuC/HuC firmware — and state whether it matches the affected host kernel `6.19.14-200.fc43`.
- [x] **REPRO-02**: A deterministic reproduction harness runs 3 concurrent `qsvencc` sessions on scenes 923/928/1129 with the exact seek/trim from the handoff, writing all outputs to an isolated writable workdir (never to `/data` sources).
- [x] **REPRO-03**: The harness produces a bit-clean single-session reference frame (scene 923, offset 299) and classifies a test frame as corrupt via external-ffmpeg PSNR vs that reference (`<30 dB` = corrupt; known signature ≈15.74 dB).
- [x] **REPRO-04**: A paired ffmpeg `av1_qsv` immune-control run (HW h264_qsv decode + P010 + GopRefDist6 pyramid) executes alongside every qsvencc measurement and is confirmed clean (0/N), validating the harness itself.
- [x] **REPRO-05**: Baseline corruption frequency and PSNR signature are reported over a detection-sized sample (~15–20 iterations), explicitly separating detection-N from the larger validation-N used for fix claims.

### Host-Side Diagnosis

- [ ] **DIAG-01**: Empirically determine and record what host-side changes are possible from this environment (kernel cmdline/modprobe, firmware, reboot, privilege level) — so blocked levers are reported honestly rather than silently skipped.
- [ ] **DIAG-02**: Test the pure VA-API `av1_vaapi` encode path (bypassing oneVPL) as an in-container triangulation data point under the same 3-way concurrency, with the paired immune control.
- [ ] **DIAG-03**: Test the effect of a GuC/HuC firmware update on corruption rate (host-side, reversible), with a before/after paired control and single-variable isolation.
- [ ] **DIAG-04**: Test the `i915`→`Xe` driver switch (`force_probe` on PCI `56a5`) — gated on first confirming the same low-power AV1 encode path is still active (dmesg GuC/HuC lines + iHD logging) before any "clean" result is trusted, so a silently disabled HW-encode path is not mistaken for a fix.
- [ ] **DIAG-05**: Every lever changes exactly one variable per reboot cycle with its own before/after control pair; results are attributed only under single-variable isolation.

### Workaround Recommendation

- [ ] **WORK-01**: Measure workaround A (`--avsw`, SW-decode + HW-encode) for cleanliness and throughput in this environment under concurrency, to a validation-grade sample (~60 zero-failure runs, rule-of-three) before any "clean" claim.
- [ ] **WORK-02**: Measure workaround B (`--jobs 1` serialization) throughput as the simplest correctness-guaranteed baseline for comparison.
- [ ] **WORK-03**: Characterize (not implement) the DV/HDR passthrough risk of workaround C (migration to ffmpeg `av1_qsv`), timeboxed as risk-assessment only.
- [ ] **WORK-04**: Deliver a correctness-first workaround recommendation for `enpipe` with measured throughput numbers and an explicit residual-corruption-rate threshold for "production ready".

### Defense-in-Depth Guard

- [ ] **GUARD-01**: Design a per-frame content-verification gate (VMAF/PSNR of the final joined `movie.obu` vs source) that physically catches a silent single-frame swap — independent of whichever root-cause fix is chosen.
- [ ] **GUARD-02**: Specify the gate's integration contract for `enpipe` (where it runs, pass/fail threshold, VMAF ru-locale CSV parsing gotchas: TAB + decimal comma, field 16) as a design deliverable, since the `enpipe` repo is not in this checkout.

### Final Report

- [ ] **DONE-01**: Produce the Definition-of-Done report (handoff §10): reproduction result in this environment, host-side conclusion (reproduces? which levers tried, with results), the enpipe recommendation, and an updated debug-history status entry (keep `root_cause_found` or raise to `fixed` if a host-side fix is confirmed).

## v2 Requirements

Deferred — depends on a confirmed fix and an explicit user decision.

### Technical Debt

- **DEBT-01**: Correct re-encode of the corrupted shipped Cold Eyes output (frames 39121/61365/73734/110079/110992/136249) after a fix is chosen — at the user's discretion.

## Out of Scope

Explicitly excluded, with reasoning.

| Feature | Reason |
|---------|--------|
| Source-patching qsvencc surface-attributes / allocator | Analytically exhausted (handoff §5): pools are already process-local, `rt_format`/usage-hints inert, `--async-depth 1` no effect, `--disable-va` segfaults. Root cause is kernel-side. |
| Implementing the enpipe workaround in code | The `enpipe` repo (`src/enpipe/encoding/*.py`) is not in this checkout — this milestone delivers a recommendation + gate design, not the applied patch. |
| Migrating enpipe to ffmpeg `av1_qsv` (Option C build) | Large rewrite risking DV-RPU/HDR10+ passthrough — characterize risk only, do not prototype. |
| Full-file re-encode of the source | Only the point scenes (923/928/1129) are needed for the harness. |
| Writing to `/data` source media | Data integrity — reproduction outputs go to an isolated workdir. |
| "Just update the iHD driver" | Deep-research (17 sources) found no concurrent/cross-session fix in iHD ≤26.1.5; userspace-stack swap already proven inert. |

## Traceability

Populated during roadmap creation — each requirement maps to exactly one phase.

| Requirement | Phase | Status |
|-------------|-------|--------|
| REPRO-01 | Phase 1 | Complete — re-run evidence: `01-EVIDENCE.md` (fingerprint.txt snapshot, `kernel_matches_affected_host: YES`) |
| REPRO-02 | Phase 1 | Complete — re-run evidence: `01-EVIDENCE.md` (report.csv snapshot, 20 iterations x 3 scenes = 60 rows) |
| REPRO-03 | Phase 1 | Complete — re-run evidence: `01-EVIDENCE.md` (report.csv `psnr_db`/`corrupt` columns; observed primary-hotspot signature ~12.96 dB mean in this environment, not the handoff's ~15.74 dB — see 01-EVIDENCE.md reconciliation note) |
| REPRO-04 | Phase 1 | Complete — re-run evidence: `01-EVIDENCE.md` (report.csv `control_clean` column, all 1; summary.txt "0/20" control line) |
| REPRO-05 | Phase 1 | Complete — re-run evidence: `01-EVIDENCE.md` (summary.txt: 923/299 9/20 45.0% CI [0.258,0.658], 1129/299 8/20 40.0%, 928/96 0/20, N_requested=20/N_actual=20, detection-N vs validation-N statement) |
| DIAG-01 | Phase 3 | Pending |
| DIAG-02 | Phase 2 | Pending |
| DIAG-03 | Phase 3 | Pending |
| DIAG-04 | Phase 3 | Pending |
| DIAG-05 | Phase 3 | Pending |
| WORK-01 | Phase 4 | Pending |
| WORK-02 | Phase 4 | Pending |
| WORK-03 | Phase 4 | Pending |
| WORK-04 | Phase 4 | Pending |
| GUARD-01 | Phase 4 | Pending |
| GUARD-02 | Phase 4 | Pending |
| DONE-01 | Phase 5 | Pending |

**Coverage:**
- v1 requirements: 17 total
- Mapped to phases: 17 (roadmap created)
- Unmapped: 0 ✓

---
*Requirements defined: 2026-07-23*
*Last updated: 2026-07-23 after roadmap creation (traceability mapped)*
