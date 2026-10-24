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

- [x] **DIAG-01**: Empirically determine and record what host-side changes are possible from this environment (kernel cmdline/modprobe, firmware, reboot, privilege level) — so blocked levers are reported honestly rather than silently skipped. (Complete — container + host capability matrix and GuC/HuC/DMC + firmware baseline in `03-EVIDENCE.md`; deferred levers in `03-RUNBOOK.md`, not applicable to the current Arc Pro B50 hardware.)
- [x] **DIAG-02**: Test the pure VA-API `av1_vaapi` encode path (bypassing oneVPL) as an in-container triangulation data point under the same 3-way concurrency, with the paired immune control. (Complete — detection-N=20: 0/20 corrupt on all three scenes, paired av1_qsv control clean 0/20, but only a PARTIAL trigger triad (B-frame reorder UNSUPPORTED on this Arc A380's LP-only AV1 entrypoint); recorded as "immunity NOT proven" per D-03. See `02-EVIDENCE.md`.)

### Source-Level Fix

- [x] **FIX-01**: Each examined surface-sync/lifetime/allocator hypothesis is confirmed or refuted by harness measurement; any claimed fix passes ~60 zero-failure 3-way iterations on 923/1129 with control 0/N and preserved single-session bit-exactness. (Complete — fix fix/vpp-enc-sync (consumer-side waitsync before EncodeFrameAsync, label timing-workaround) validated 0/60 on 923 and 1129, control 0/60, md5 180/180 S, bit-exact 6/6; residual per-iteration rate <= 5 % (rule of three). See 02.1-EVIDENCE.md.)

### Final Report

- [ ] **DONE-01**: Produce the Definition-of-Done report: reproduction result in this environment, the source-level fix and its upstream status (rigaya/QSVEnc#316, release `8.31-vppsync1`), host-side capability and deferred levers, open questions, an "until fixed upstream" section for qsvencc users, and an updated debug-history status entry (application-level workaround, upstream pending — not a proven root-cause fix). *(Revised 2026-10-01: enpipe recommendation removed from scope.)*

## v2 Requirements

Deferred — depends on a confirmed fix and an explicit user decision.

### Host-Side Root-Cause Experiments (deferred 2026-10-01)

Useful only to test the "root cause below the API" hypothesis (e.g. for a report to Intel); need host reboots and operator action.

- **DIAG-03**: Test the effect of a GuC/HuC firmware update on corruption rate (host-side, reversible), with a before/after paired control and single-variable isolation.
- **DIAG-04**: Test the `i915`→`Xe` driver switch (`force_probe` on PCI `56a5`) — gated on first confirming the same low-power AV1 encode path is still active (dmesg GuC/HuC lines + iHD logging) before any "clean" result is trusted, so a silently disabled HW-encode path is not mistaken for a fix.
- **DIAG-05**: Every lever changes exactly one variable per reboot cycle with its own before/after control pair; results are attributed only under single-variable isolation.

### Technical Debt

- **DEBT-01**: Correct re-encode of the corrupted shipped Cold Eyes output (frames 39121/61365/73734/110079/110992/136249) after a fix is chosen — at the user's discretion.

## Out of Scope

Explicitly excluded, with reasoning.

| Feature | Reason |
|---------|--------|
| Source-patching qsvencc surface-attributes / allocator | Analytically exhausted (handoff §5): pools are already process-local, `rt_format`/usage-hints inert, `--async-depth 1` no effect, `--disable-va` segfaults. *(Narrowed 2026-10-01: surface synchronization was re-opened as Phase 2.1 and fixed there.)* |
| Implementing the enpipe workaround in code | The `enpipe` repo (`src/enpipe/encoding/*.py`) is not in this checkout — this milestone delivers a recommendation + gate design, not the applied patch. |
| Migrating enpipe to ffmpeg `av1_qsv` (Option C build) | Large rewrite risking DV-RPU/HDR10+ passthrough — characterize risk only, do not prototype. |
| Workaround recommendation and content-verification gate for `enpipe` (former WORK-01..04, GUARD-01..02) | Removed 2026-10-01: `enpipe` is not part of this repository and the bug is now fixed in qsvencc itself (Phase 2.1). A short "until fixed upstream" section in the final report replaces it. |
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
| DIAG-01 | Phase 3 | Complete |
| DIAG-02 | Phase 2 | Complete — `02-EVIDENCE.md` (detection-N=20: 0/20 corrupt all three scenes, paired av1_qsv control clean 0/20, D-02 triad PARTIAL (reorder UNSUPPORTED, P010/hw_decode ACTIVE), explicit SC#2 interpretation "immunity NOT proven", triangulated against 01-EVIDENCE.md qsvencc baseline, qsvencc cross-session-swap mechanism note stays OPEN) |
| FIX-01 | Phase 02.1 | Complete — 02.1-EVIDENCE.md (FIX-v60: 0/60 + md5 180/180 S + bit-exact 6/6; patches/0001-*.patch) |
| DIAG-03 | v2 (deferred) | Deferred |
| DIAG-04 | v2 (deferred) | Deferred |
| DIAG-05 | v2 (deferred) | Deferred |
| WORK-01 | — | Removed (out of scope) |
| WORK-02 | — | Removed (out of scope) |
| WORK-03 | — | Removed (out of scope) |
| WORK-04 | — | Removed (out of scope) |
| GUARD-01 | — | Removed (out of scope) |
| GUARD-02 | — | Removed (out of scope) |
| DONE-01 | Phase 4 | Pending |

**Coverage:**
- v1 requirements: 9 active (18 defined; DIAG-03..05 deferred to v2, WORK-01..04 and GUARD-01..02 removed 2026-10-01)
- Mapped to phases: 9
- Unmapped: 0 ✓

---
*Requirements defined: 2026-07-23*
*Last updated: 2026-10-01 — FIX-01 added for Phase 02.1; scope revised after the fix (DIAG-03..05 deferred, WORK/GUARD removed, DONE-01 revised)*
