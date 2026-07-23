# QSV Concurrent-Encode Frame-Corruption Resolution

## What This Is

A diagnose-and-resolve investigation into a silent, single-frame corruption that appears when multiple `qsvencc` (rigaya/QSVEnc) sessions encode concurrently on one Intel Arc GPU. Under concurrency, QSV/oneVPL/iHD occasionally emits one frame whose pixel content comes from a *different* parallel session's scene — while the frame *count* stays correct, so `count_frames`-style checks pass and the corruption ships silently. The goal is to reproduce it in this GPU+`/data` environment, exhaust the untried host-side (kernel) levers, and deliver a correctness-first recommendation for the downstream `enpipe` pipeline — plus a defense-in-depth content check so this class of defect can never ship silently again.

## Core Value

**Correctness is non-negotiable: no encoded frame may ever silently contain content from another session.** Every other concern (throughput, features, elegance) yields to this. A fix that restores per-frame content integrity under concurrency — even at a throughput cost — beats a faster pipeline that can silently swap a frame.

## Requirements

### Validated

<!-- Established by the prior debugging session (see root PROJECT.md handoff + scene-chunk-frame-mismatch.md). Locked findings. -->

- ✓ **Trigger triad isolated** — corruption requires all of: HW VA-decode into VA video memory (`--avhw --va`) + 10-bit P010 surfaces (`--output-depth 10`, main-10) + B-frame reorder (`--gop-ref-dist 6 --b-pyramid`), plus ≥2 concurrent `qsvencc` sessions on one GPU. Breaking any one leg → 0% defects. — prior session
- ✓ **Deterministic signature** — the corrupted frame is always the same reordered-reference slot; PSNR vs reference ≈ **15.74 dB**, identical run-to-run. — prior session
- ✓ **Frequency ~33–65%** of 3-way concurrent runs produce ≥1 bad frame; single-session encode is bit-identical (0%). — prior session
- ✓ **Not seek/trim arithmetic, not a neighbor-frame dup** — isolated re-encode of the same chunk is bit-exact (41.5 dB); corrupted frame matches no ±5 neighbor. — prior session
- ✓ **ffmpeg `av1_qsv` is immune** — identical combo (HW h264_qsv decode + P010 + GopRefDist6 pyramid) is 35/35 clean under the same concurrency. The driver *can* isolate correctly; difference is qsvencc's single OR-combined `FROM_DECODE|FROM_VPPIN|FROM_ENCODE` VA pool vs ffmpeg's per-component `AVHWFramesContext`. — prior session
- ✓ **Root cause is in the host kernel (drm/i915), not userspace** — replacing the entire userspace media stack (iHD 25.2.3 → 26.2.2, vpl-gpu-rt, libva 2.23) on the same kernel had zero effect; identical frequency/signature. — prior session
- ✓ **qsvencc source-patch line exhausted** — P010 `rt_format` patch, `VASurfaceAttribUsageHint` variants, `--async-depth 1` all inert; `--disable-va` segfaults 100%. Allocator pools are already process-local and separate. — prior session (§5, do not repeat)
- ✓ **Reproducer recipe defined** — source `Cold.Eyes.2013.Bluray.Remux.mkv`, three harness scenes (923/928/1129) with exact seek/trim and known hotspot offsets/corrupt frames. — prior session (§4)
- ✓ **Workaround solution space characterized** — A: `--avsw` (SW-decode, keeps 10-bit+B+DV/HDR, 0/60), B: `--jobs 1` (serialize, 0%), C: migrate to ffmpeg `av1_qsv` (clean but risky for DV), D: 8-bit, E: no-B. — prior session (§7)
- ✓ **QSVEnc builds from source in this environment** — full toolchain validated; `qsvencc` (r4386, gcc 13.3) compiles and drives the Arc A380 (AV1 10-bit encode + HW decode confirmed via `--check-features`). — this environment
- ✓ **Bug reproduced in THIS environment with a control-validated baseline** — calibrated harness (`scratch/repro/`) on the Arc A380 records, on-disk, N=20 3-way concurrency: 923/299 **9/20 (45%)**, 1129/299 **8/20 (40%)**, 928/96 **0/20**; corrupt-frame PSNR mean **12.96 dB** (σ 0.18, threshold <30 dB); paired ffmpeg `av1_qsv` immune control **0/20** clean; environment fingerprint confirms same-kernel `6.19.14-200.fc43`. Observed signature (~12.96 dB) differs from the prior session's 15.74 dB — the harness reports the OBSERVED value. Durable evidence: `.planning/phases/01-harness-control-environment-fingerprinting/01-EVIDENCE.md`. — Validated in Phase 1

- ✓ **Pure VA-API `av1_vaapi` triangulated (bypassing oneVPL) — clean but immunity NOT proven** — N=20 3-way concurrent `av1_vaapi` (923/928/1129) recorded **0/20 corrupt** on all three scenes, paired ffmpeg `av1_qsv` control **0/20** clean, through the Phase-1 harness. The trigger triad was only **PARTIAL** on this Arc A380 (B-frame reorder UNSUPPORTED; P010 + HW-VA-decode ACTIVE), so under D-03 immunity is **NOT proven** and escalation to N~60 is correctly withheld. Secondary finding: content cross-match of all 17 Phase-1 qsvencc corrupt frames found **0 confirmed cross-session swaps (≥35 dB)** — the corruption is not a clean whole-frame swap, so Phase-1's mechanism-vs-symptom note stays **OPEN**. Durable evidence: `.planning/phases/02-in-container-triangulation-av1-vaapi/02-EVIDENCE.md`. — Validated in Phase 2 (DIAG-02)

### Active

<!-- The mission for this GPU+/data environment. Hypotheses until confirmed. -->
- [ ] Resolve the host/kernel fork: confirm whether this host's kernel/GPU-driver differs from the affected `6.19.14-200.fc43` / i915, and whether that changes reproduction.
- [ ] Test untried in-place host-side levers: switch Arc (Alchemist/DG2) from `i915` to the `Xe` driver; update GuC/HuC firmware. (av1_vaapi leg measured in Phase 2 — clean under PARTIAL triad, immunity not proven.)
- [ ] Produce a correctness-first recommendation for `enpipe` (which §7 workaround), backed by measured throughput numbers in this environment.
- [ ] Design a defense-in-depth per-frame content-verification gate (e.g. VMAF/PSNR on the final joined `movie.obu` vs source) so a silent single-frame swap cannot ship — independent of which fix is chosen.
- [ ] Decide/act on the acknowledged tech debt: the corrupted shipped Cold Eyes encode (frames 39121/61365/73734/110079/110992/136249) — correct re-encode after a fix, at user's discretion.

### Out of Scope

- **Source-patching qsvencc along surface-attribute/allocator lines** — analytically exhausted (§5); pools are already process-local, `rt_format`/usage-hints inert. Re-trying wastes build cycles.
- **Implementing `enpipe` code changes here** — the `enpipe` repo (`src/enpipe/encoding/*.py`) is not in this checkout; this project delivers a *recommendation* + reproducer + host-side findings, not the enpipe patch.
- **Full-file re-encode of the source** — only the point scenes (923/928/1129) are needed for the harness.
- **Writing to `/data` source media** — reproduction outputs go to a separate writable workdir; never mutate `/data` sources.
- **Overwriting the existing QSVEnc `CLAUDE.md`** — it is the upstream project's own build/architecture guide; GSD guidance stays in `.planning/`.

## Context

- **Same-kernel signal (important):** this environment reports OS kernel **`6.19.14-200.fc43`** (confirmed via `qsvencc --check-features`), the *same* kernel as the affected host in the handoff. The §6 "different kernel = free fix" escape is therefore likely closed, and the bug is expected to reproduce — making the *in-place* host-side levers (i915→Xe, GuC/HuC firmware) and the enpipe workaround the primary path rather than "it just works on this box."
- **Hardware:** Intel Arc A380 (Alchemist/DG2, 128 CU), driver `iHD` / VA-API 1.23.0, oneVPL Hardware API v2.16. `/dev/dri/renderD128` passed through; `LIBVA_DRIVER_NAME=iHD`.
- **Downstream consumer:** `enpipe` — a chunked AV1 encode pipeline that runs `JOBS` (default 3) concurrent `qsvencc` sessions (`ThreadPoolExecutor`), which is what surfaces the bug. Its correctness invariant today is only `count_frames` (frame count), which the silent swap defeats.
- **Prior art in-repo:** full debugging history in the root `PROJECT.md` handoff, `scene-chunk-frame-mismatch.md` (300 lines, 6+ tested hypotheses, status `root_cause_found`), and upstream draft `qsvenc-upstream-issue.md`. QSVEnc codebase mapped in `.planning/codebase/`.
- **Only public corroboration:** intel/media-driver #1626 (loud failure on an old stack; ours is the *silent* variant).
- **Metrics constraint:** `qsvencc --psnr/--ssim` need OpenCL — measure PSNR/VMAF with external ffmpeg instead. (OpenCL *is* available in this build, but the reproducer should not depend on it.)

## Constraints

- **Correctness**: Any fix must preserve keyframe-alignment and frame-count invariants; silent content swap is the exact risk the whole pipeline exists to prevent. — non-negotiable project invariant
- **Environment**: Single Arc A380 GPU shared by all experiments — concurrent GPU experiments contend and pollute the concurrency-triggered corruption measurements. — sequential plan execution chosen for this reason
- **Repo boundary**: `enpipe` source not present — deliverable for §7 fixes is a recommendation, not an applied patch. — multi-repo reality
- **Host boundary**: kernel/driver/firmware levers (§6) are host-side, outside the container — may require host reconfiguration the user must perform. — host-side dependency
- **Data safety**: `/data` sources are read-only-by-policy even if writable; outputs go to an isolated workdir. — data integrity

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Frame the project as investigation→recommendation, not a code build | Root cause is kernel-side; qsvencc source line exhausted; enpipe code is in another repo | — Pending |
| Sequential plan execution | Concurrent GPU experiments would skew the very corruption metrics being measured | — Pending |
| Preserve existing `CLAUDE.md`; keep GSD docs in `.planning/` | The repo's CLAUDE.md is upstream project documentation, not GSD-generated | ✓ Good |
| Correctness-first: prefer a workaround that keeps 10-bit/DV/HDR (e.g. `--avsw`) over throughput | Core value is no silent frame swap; DV/HDR features are why qsvencc was chosen | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-07-23 after Phase 2 complete — av1_vaapi triangulation recorded (0/20 corrupt, PARTIAL triad, immunity NOT proven; DIAG-02 validated). Next: Phase 3 host-side levers (host-access-gated).*
