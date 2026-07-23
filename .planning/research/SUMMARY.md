# Project Research Summary

**Project:** QSV Concurrent-Encode Frame-Corruption Resolution
**Domain:** Diagnose-and-resolve investigation — host-kernel/driver-level root-cause diagnosis of silent, concurrency-triggered AV1 frame corruption in Intel QSV/oneVPL encoding (Arc A380/DG2, Linux), plus a correctness-first workaround recommendation for the downstream `enpipe` pipeline
**Researched:** 2026-07-23
**Confidence:** MEDIUM-HIGH

## Executive Summary

This is not a greenfield build — it is a forensic investigation that inherits a large, already-validated body of prior findings (trigger triad, deterministic ~15.74 dB corruption signature, 33–65% baseline frequency, ffmpeg `av1_qsv` immunity, kernel-not-userspace root cause, and an exhausted qsvencc source-patch line) and must extend it with the untried levers: switching the Arc DG2 host driver from `i915` to `xe`, refreshing GuC/HuC firmware, and trying the pure-VAAPI `av1_vaapi` path as a cheaper triangulation point. All four research passes converge on the same shape: build a rock-solid, reusable reproduction/verification harness first (in-container, fully unblocked), validate it with a mandatory paired ffmpeg `av1_qsv` control on every single measurement, then work outward from cheap in-container levers (`av1_vaapi`) to expensive host-side levers (`i915`→`xe`, firmware) that require reboot access and may simply be unavailable in this environment — and finally land on a measured, throughput-backed workaround recommendation for `enpipe` (`--avsw`, `--jobs 1`, or migrate-to-ffmpeg) plus a root-cause-independent defense-in-depth content gate.

The recommended approach is disciplined and conservative rather than exploratory: every host-side change must be a single isolated variable with a full before/after re-measurement (including the control), because host reconfiguration is slow/expensive (reboot-gated) and because this project's own history shows that skipping this discipline (or skipping the control) produces false conclusions. The single most important structural risk the research surfaces is statistical: this investigation's own prior sample sizes (15–20 runs) are well-calibrated to *detect* the ~33–65% baseline, but are an order of magnitude too small to *certify* a fix or workaround as clean — a rule-of-three analysis shows ~60 zero-failure runs are needed to bound residual risk under ~5% with 95% confidence, and this must be baked into every validation phase's "done" criteria, not left to run-time judgment.

The key risk to actively manage is the Xe/HuC trap: Arc DG2/Alchemist has no HuC firmware support under the `xe` driver, and HuC is required for the low-power AV1 encode/BRC path this project's repro command exercises (`--icq`). A "0% corruption under Xe" result could just mean hardware encode silently fell back to a different code path rather than that BO/context isolation improved — any Xe result must be gated on confirming the same encode mode (low-power BRC) is active via dmesg GuC/HuC lines and `--check-features`/iHD logging before it is trusted. Equally important is the honest reporting distinction between what this investigation can execute unassisted (harness, control, fingerprinting, `av1_vaapi`, all in-container) versus what is host-owner-gated and may be blocked entirely (`i915`→`xe` switch, GuC/HuC firmware update, both requiring reboot + root outside the container) — these must be reported as "recommended but blocked/unattempted" rather than silently skipped or silently attempted without disclosure.

## Key Findings

### Recommended Stack

See `STACK.md` for full detail. The stack splits cleanly into in-container/unblocked tooling (already available, no host cooperation needed) and host-side levers (require reboot + root, may be blocked). The harness itself needs no new dependencies beyond what's already validated in this environment plus a standalone system ffmpeg for control/verification.

**Core technologies:**
- Existing `qsvencc` build (r4386+, this repo) — the system under test; do not re-patch its allocator/surface-attribute code (analytically exhausted).
- System ffmpeg 8.x with `--enable-vaapi --enable-libdrm` (and ideally `--enable-libvmaf`) — provides both the mandatory `av1_qsv` immune control AND the untried `av1_vaapi` cheap differentiator, plus all PSNR/VMAF verification (external, no OpenCL dependency).
- `xe` DRM driver (in-tree, `force_probe` gated) — the single most promising untried lever, but host-side only, requires persistent modprobe.d config + reboot; carries the HuC-loss risk documented below.
- `i915` DRM driver (current) — kept only as the control/baseline condition.
- GuC/HuC firmware (`linux-firmware`, `dg2_guc_70.bin`/`dg2_huc_gsc.bin` family) — cheap, reversible, host-side lever independent of the i915/xe choice.
- `igt-gpu-tools`/`intel_gpu_top`, `/proc/<pid>/fdinfo`, `strace -f -yy`, `LIBVA_TRACE` — diagnostic instrumentation; fdinfo is the one tool confirmed to survive the i915↔xe swap unchanged in *availability* (format differs).

### Expected Features

See `FEATURES.md` for full detail. Framed as investigation deliverables, not product features — "table stakes" here means "the investigation cannot be trusted as complete without these."

**Must have (table stakes):**
- Deterministic reproduction harness (923/928/1129 scenes, 3-way concurrent qsvencc), reused unmodified across every subsequent experiment.
- PSNR-vs-reference detection at ~15.74 dB signature match (not just a raw threshold) — the only way corruption is detected, since frame count alone passes silently.
- ffmpeg `av1_qsv` immune control run as a **paired sibling** of every single measurement, in every environment/lever state — not a one-time fact established once and reused.
- Environment/kernel fingerprinting (`uname -r`, i915-vs-xe, iHD version, GuC/HuC firmware version) — gates whether host-side levers are even meaningfully test-able and resolves the "does this host reproduce the bug at all" fork.
- Per-frame content-verification gate design (spec-level, `enpipe` code absent) — ships independent of root-cause outcome, as defense-in-depth.

**Should have (differentiators — the actual resolution paths):**
- `av1_vaapi` pure-VAAPI path — cheapest, in-container, no host cooperation needed; sequence this *first* among differentiators even though the prior handoff lists it last, since it needs no host access and directly informs whether a quieter API surface alone resolves the bug.
- `i915`→`xe` driver migration test — highest theoretical value but host-side (reboot + root), may be blocked; report as recommended-but-blocked if unavailable, do not silently skip.
- GuC/HuC firmware update test — secondary host-side lever, lower priority than Xe per the handoff's own prioritization.
- §7 workaround recommendation for `enpipe` with throughput numbers measured *in this environment* (not carried over from the prior host): Option A `--avsw` (correctness-preserving, keeps 10-bit/B-pyramid/DV/HDR, throughput cost), Option B `--jobs 1` (0% by construction, full throughput cost), Option C ffmpeg migration (clean and fast but high DV/HDR rewrite risk — characterize, do not prototype to completion).

**Defer (v2+ / explicitly out of scope):**
- Re-patching qsvencc allocator/surface-attribute code — analytically exhausted, do not repeat.
- Full-file re-encode of the source for testing — use only the three point scenes.
- Actual implementation of the chosen `enpipe` workaround, and the corrected re-encode of the already-shipped corrupted Cold Eyes file — both explicitly deferred to user discretion / a separate repo.

### Architecture Approach

See `ARCHITECTURE.md` for full detail. Two layers matter: (1) the isolation stack where correctness plausibly breaks — qsvencc's `CQSVPipeline::AllocFrames` OR-combines `FROM_DECODE|FROM_VPPIN|FROM_ENCODE` into one shared VA surface pool per adjacent pipeline-task pair (`qsv_pipeline.cpp:1708-1822`), in contrast to ffmpeg's `AVHWFramesContext` giving each pipeline role its own separately-allocated pool — both terminate in the same libva→iHD→drm/i915 kernel stack, so the suspected fault is either qsvencc's pool topology or something below it in kernel-side BO retire-tracking/GuC scheduling that isn't process-partitioned; and (2) the investigation harness itself, a component pipeline (Environment Probe → Corpus/Fixture Provider → Reference/Concurrent Runners → Frame Extraction → PSNR/VMAF Metric Engine → Corruption Classifier → Corruption-Rate Report), with a deliberately decoupled Defense-in-Depth Content Gate that reuses only the Metric Engine and never depends on root-cause conclusions.

**Major components:**
1. Environment Probe — tags every downstream measurement with {kernel, i915|xe, GuC/HuC fw, iHD version}; must run before any lever test and gates whether i915→xe/firmware levers can even be interpreted.
2. Reproduction harness (Reference-Encode Runner + Concurrent-Encode Runner, parameterized by encoder-path and iteration count) — the shared substrate reused unmodified across every experiment; built once against the default i915 environment before any lever is tested.
3. PSNR/VMAF Metric Engine + Corruption Classifier — encoder-path-agnostic scoring plus deterministic-signature matching (not raw threshold), reused independently by the Content Gate.
4. Defense-in-Depth Content Gate — production-pipeline design deliverable, explicitly root-cause-independent, ships regardless of which lever/workaround wins.

### Critical Pitfalls

See `PITFALLS.md` for full detail (10 pitfalls identified). Top ones directly shaping the roadmap:

1. **Declaring "fixed" on too few iterations** — the rule-of-three means ~15-20 runs only *detects* the 33-65% baseline; certifying a lever/workaround as clean needs ~60 zero-failure runs (95% CI bound ≈5% residual), ~300 to rule out even a ~1% residual. Bake a minimum-N into every validation phase's done-criteria up front, not as a post-hoc judgment call.
2. **Forgetting the ffmpeg `av1_qsv` immune control** — must be a mandatory paired sibling run for every qsvencc measurement in every environment/lever state, never a one-time fact. A clean-looking qsvencc result without a re-validated control in that same state is not trustworthy (harness could be silently broken, or the lever could have broken the control too).
3. **The Xe/HuC trap** — DG2/Alchemist has no HuC support under `xe`; HuC drives the low-power AV1 BRC path this project's `--icq` repro exercises. A "0% corruption under Xe" result must be gated on confirming the same encode mode is active (dmesg GuC/HuC lines, `--check-features`/iHD logging) before being trusted as a real fix rather than a silent pipeline-mode change.
4. **False isolation from bundling host-side changes** — i915→xe switch and GuC/HuC firmware update must never be applied in the same reboot cycle; one variable per reboot, full stop, with the control and baseline re-run at each single-variable state.
5. **Frame-count silent-pass trap** — this is the entire premise of the bug; every validation step (including the eventual defense-in-depth gate) must use per-frame/percentile PSNR/VMAF at known hotspot offsets, never aggregate/mean scores or frame-count/exit-code checks, which can hide a single swapped frame in hundreds of thousands.

## Implications for Roadmap

Based on combined research, the build order should mirror the Architecture research's "Investigation Build Order" almost exactly, with the sequencing emphasis on cheap-and-unblocked before expensive-and-possibly-blocked.

### Phase 1: Harness, Control, and Fingerprinting
**Rationale:** Nothing downstream is interpretable without a working, calibrated measurement instrument and an environment baseline. This phase is fully in-container and unblocked — no host access needed.
**Delivers:** Environment Probe (kernel/driver/firmware/iHD fingerprint), reproduction harness (923/928/1129 scenes, 3-way concurrent runner reused unmodified downstream), PSNR-vs-reference detection with deterministic-signature matching (not raw threshold), the ffmpeg `av1_qsv` immune-control wired as a mandatory paired run, and a confirmed baseline reproduction (frequency + signature) in this environment.
**Addresses:** All 5 table-stakes features from FEATURES.md.
**Avoids:** Pitfall 4 (missing control), Pitfall 5 (frame-count silent-pass), Pitfall 6 (OpenCL/VMAF locale gotchas), Pitfall 1 (measurement contamination — establish GPU-exclusivity discipline here as a standing rule).

### Phase 2: Cheap In-Container Triangulation (`av1_vaapi`)
**Rationale:** This is the cheapest differentiator — no host cooperation, same iHD driver already installed — and should be sequenced before any host-side ask, both for cost reasons and because its result (clean vs corrupt) reshapes how the eventual host-side and workaround findings should be interpreted (isolates defect to qsvencc's own pool code vs. a broader VA-surface-pool class).
**Delivers:** `av1_vaapi` concurrent run through the same harness (with paired control), interpreted per the STACK.md decision tree (clean → strengthens Option C case; corrupt too → reopens investigation into what oneVPL's runtime does differently).
**Uses:** ffmpeg `av1_vaapi` encoder, harness from Phase 1 unmodified.
**Implements:** Pattern 2 (per-component pool separation) as an additional empirical data point alongside the existing ffmpeg `av1_qsv` control.

### Phase 3: Host-Side Levers (if available) — Xe Migration and GuC/HuC Firmware
**Rationale:** Highest theoretical value (Xe's different BO/context isolation model is the most-promising untried lever) but expensive (reboot, root) and may simply be blocked in this environment. Must be attempted one variable at a time, each with a full harness+control re-run.
**Delivers:** For each of {i915→xe switch, GuC/HuC firmware update} attempted in isolation: fingerprint re-confirmation, HW-encode-mode confirmation (low-power BRC active, not silently degraded — critical Xe/HuC gate), harness+control re-run, corruption-rate comparison against Phase 1 baseline. If host access is unavailable, this phase's output is an honest "recommended but blocked — requires host-owner action" report, not a silently-skipped section.
**Research flag:** This phase needs deeper research/verification at execution time — confirm current Xe/HuC support status live (documented state is ~Sept 2025, re-verify via dmesg) and confirm exact PCI device ID before any `force_probe` config.

### Phase 4: Workaround Throughput Measurement and §7 Recommendation
**Rationale:** Whether or not a host-side fix is found, `enpipe` needs an actionable, measured recommendation. Sequenced after Phases 1-3 so throughput is only measured for configurations already known to be correctness-clean at adequate sample size.
**Delivers:** Fresh in-this-environment throughput numbers for Option A (`--avsw`) and Option B (`--jobs 1`), each validated to the ~60 zero-failure-run bar before being called "clean"; Option C (ffmpeg migration) characterized (not prototyped) for DV/HDR risk with its existing 35/35-clean number re-confirmed at a fresh, smaller top-up sample. A prioritized recommendation favoring the correctness-preserving, feature-preserving option (`--avsw`) unless throughput cost is prohibitive.
**Addresses:** FEATURES.md's §7 workaround differentiators.
**Avoids:** Pitfall 2 (insufficient sample size), Pitfall 10 (over-investing in Option C prototyping beyond what a recommendation needs).

### Phase 5 (parallel with 4): Defense-in-Depth Content Gate Design
**Rationale:** Deliberately root-cause-independent — must not be blocked on Phases 3/4 outcomes. Only depends on the Metric Engine component existing (Phase 1).
**Delivers:** Design/prototype spec for a per-frame or worst-percentile PSNR/VMAF gate on the final joined `movie.obu` vs source, replacing `count_frames` as the sole invariant. Recommendation-only since the `enpipe` repo is absent from this checkout.
**Avoids:** Pitfall 5 (must itself avoid the aggregate/mean-score trap it's designed to close).

### Phase 6: Synthesis — Host-Side Conclusion, Enpipe Recommendation, Upstream Report
**Rationale:** Final deliverable; depends on all diagnostic and content-gate branches converging.
**Delivers:** The Definition-of-Done report per root PROJECT.md §10 — reproduction findings, host-side lever outcomes (including honestly-reported blocked/unattempted levers), the enpipe workaround recommendation with measured numbers, the content-gate spec, and (if warranted) an upstream drm/i915 bug report.

### Phase Ordering Rationale

- Harness-before-levers is non-negotiable: no lever (Xe, firmware, `av1_vaapi`, `--avsw`, `--jobs 1`) is interpretable without a calibrated, control-validated measurement instrument (Architecture research, Build Order step 1-2; Pitfall 4).
- Cheap/unblocked before expensive/possibly-blocked: `av1_vaapi` (in-container) is sequenced ahead of Xe/firmware (host-side, reboot-gated) purely on cost and availability grounds — this also means Phase 2's results are already in hand if Phase 3 turns out to be entirely blocked.
- Host-side levers must never run simultaneously with each other (Pitfall 3, false isolation) — the roadmap should budget one reboot per lever, not one reboot for "try everything."
- The content gate is deliberately parallel/independent (Architecture research explicitly flags this) so it isn't accidentally gated on root-cause resolution, which could otherwise idle a large deliverable for no dependency-driven reason.
- Throughput measurement is sequenced after correctness validation (Phase 4 after 1-3) because sampling throughput for a not-yet-validated-clean configuration wastes GPU-hours on a candidate that may get discarded.

### Research Flags

Phases likely needing deeper research/verification during planning execution:
- **Phase 3 (Host-side levers):** Xe/HuC support status for DG2/Alchemist is dated ~Sept 2025 in current sources — must be re-verified live via dmesg before this phase's plan is finalized; also confirm exact PCI device ID and whether host/root access is actually available in this environment before committing to this phase at all.
- **Phase 4 (Workaround recommendation, Option C sub-track):** DV/HDR passthrough risk for ffmpeg `av1_qsv` migration is unverified/qualitative only — if execution reveals `enpipe`'s actual DV/HDR handling code is reachable for inspection, this sub-track may need a short targeted research pass.

Phases with standard/well-documented patterns (skip research-phase):
- **Phase 1 (Harness/control/fingerprinting):** Fully specified by prior-session PROJECT.md §4 reproducer recipe and this research's harness architecture — no new research needed, just execution.
- **Phase 2 (`av1_vaapi`):** ffmpeg VAAPI AV1 encode option surface is documented and source-confirmed (STACK.md); execution-ready.
- **Phase 5 (Content gate design):** Standard VMAF/PSNR per-frame gating pattern, well-precedented; design-only deliverable.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | MEDIUM-HIGH | Kernel/driver mechanics HIGH (kernel.org docs); DG2-specific Xe/HuC status MEDIUM — last independently confirmed ~Sept 2025, must re-verify live via dmesg before relying on it in Phase 3. |
| Features | MEDIUM | Prior-art findings (trigger triad, signature, control immunity) are HIGH — validated across multiple build cycles by two independent agents. Net-new host-side levers are MEDIUM/LOW — untried in this environment. |
| Architecture | MEDIUM | qsvencc/libva/iHD userspace chain is HIGH (read directly from source in this repo). i915 GEM/GuC/Xe kernel-boundary mechanism is MEDIUM (grounded in kernel docs, not confirmed line-by-line against i915 source). "Why Xe helps" causal claim is LOW-to-MEDIUM — architecturally plausible, empirically untested on this hardware. |
| Pitfalls | MEDIUM-HIGH | Grounded in this project's own exhausted-negatives log (HIGH, primary source), cross-checked against public i915/Xe driver-support facts (MEDIUM) and standard statistical practice for zero-event confidence intervals (MEDIUM-HIGH, well-established convention applied here). |

**Overall confidence:** MEDIUM-HIGH

### Gaps to Address

- **Xe/HuC support status currency:** documented state (~Sept 2025) should be re-verified live via dmesg/driver logs at the point Phase 3 is actually attempted, since driver support matrices change across kernel/firmware releases — do not plan Phase 3 purely off this document's snapshot.
- **Host/root access availability in this environment:** not yet confirmed whether the container has any path to host-level `force_probe`/firmware changes at all; Phase 3 planning should include an explicit early check-and-report step ("is host access available: yes/no") before committing further effort, and must be prepared to report "recommended but blocked" honestly rather than silently omitting the phase.
- **`enpipe` DV/HDR passthrough risk for Option C:** currently only a qualitative risk characterization (repo absent from this checkout) — if execution surfaces any way to inspect `chunk.py`/enpipe internals, a short targeted look would sharpen the Option C risk statement, but this should not block or expand the recommendation-only scope of this project.
- **igt-gpu-tools Xe coverage completeness:** `intel_gpu_top` Xe support may still be partial depending on installed version; verify empirically with `intel_gpu_top -L` immediately after any driver switch attempt, falling back to `/proc/<pid>/fdinfo` if needed — do not assume it "just works."
- **Sample-size discipline for prior §7 numbers:** existing workaround validation numbers (e.g. `--avsw` 0/60, `--gop-ref-dist 1` at only 0/15) carry different confidence levels; Phase 4 should explicitly top up under-sampled claims to the ~60 zero-failure bar before finalizing the recommendation, per Pitfall 2.

## Sources

### Primary (HIGH confidence)
- `QSVPipeline/qsv_pipeline.cpp:1708-1822`, `QSVPipeline/qsv_allocator_va.cpp` — read directly from this repo; qsvencc allocator/pool topology.
- Root `PROJECT.md` handoff (§0-§10) and `.planning/PROJECT.md` — this project's own prior-session validated findings, requirements, and constraints; primary source of record for what has already been established and what must not be repeated.
- Kernel.org Xe "Merge Acceptance Plan" RFC (`gpu/rfc/xe.html`) — confirms `force_probe` protection is permanent for DG2, not a "graduates to default" situation.
- `docs.kernel.org/gpu/i915.html`, `i915_scheduler.html` — full-PPGTT isolation and GuC scheduling mechanism.
- `github.com/FFmpeg/FFmpeg` `libavcodec/vaapi_encode_av1.c` (read via fetch) — confirms AV1 VAAPI encoder option surface and B-picture support.

### Secondary (MEDIUM confidence)
- Phoronix coverage of Xe vs i915 on Alchemist and the Xe-lacks-HuC-for-DG2 finding — corroborated across multiple community sources but not independently re-confirmed for 2026 in this research pass.
- Arch Linux `linux-firmware-intel` package listings — GuC/HuC firmware filename/version lineage for DG2.
- `intel/media-driver` GitHub/DeepWiki — AV1 encode support on DG2 via VAAPI confirmed as viable/supported.
- Rule-of-three statistical convention for zero-event confidence intervals — standard practice, applied here to derive the ~60-run minimum-N guidance.

### Tertiary (LOW confidence)
- Known i915 GEM handle/refcount race class, cited only as precedent that a *class* of cross-boundary BO/handle races exists in this driver, not as confirmation of this specific bug's mechanism.
- `intel/media-driver#1626` — only public corroborating report of a related (but loud, not silent) failure on an older stack.

---
*Research completed: 2026-07-23*
*Ready for roadmap: yes*
