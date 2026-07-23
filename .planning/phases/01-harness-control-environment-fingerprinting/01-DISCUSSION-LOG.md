# Phase 1: Harness, Control & Environment Fingerprinting - Discussion Log

> **Audit trail only.** Not consumed by downstream agents. Decisions live in `01-CONTEXT.md`.

**Date:** 2026-07-23
**Phase:** 01-harness-control-environment-fingerprinting
**Mode:** discuss (--auto, single pass)
**Areas analyzed:** Harness form & language, qsvencc-under-test, Concurrency/scenes, Corruption detection, Reference generation, Immune control pairing, Sample sizes, Environment fingerprint, Data safety

## Auto-Selected Decisions (recommended defaults)

| Area | Question | Selected (recommended) |
|------|----------|------------------------|
| Harness form | bash vs Python vs reuse enpipe | Self-contained bash script (matches ephemeral repro_frame_corruption.sh; no absent-repo dep) |
| Binary under test | stock r4385 vs from-source r4386 | Stock installed r4385 (fidelity to documented baseline) |
| Detection method | qsvencc metrics vs external ffmpeg | External ffmpeg frame-extract + `-lavfi psnr`, `<30 dB`=corrupt (OpenCL-free) |
| Immune control | one-time vs paired every batch | Paired av1_qsv control every batch; non-zero control invalidates harness |
| Sample size | fixed vs parametrized | Parametrized; Phase-1 detection default 20 iters; ~60 validation-N reserved for later |
| Fingerprint | minimal vs full | Full: uname/driver/iHD/GuC-HuC + explicit compare to 6.19.14-200.fc43 |
| Data safety | — | Outputs to isolated workdir; never write /data; source read-only |

## Scene Parameters (from handoff §4, locked)

| Scene | seek | trim | measured offset |
|-------|------|------|-----------------|
| 923 | 01:16:14.167 | 0:339 | 299 (hotspot) |
| 928 | 01:17:00.667 | 0:110 | 96 |
| 1129 | 01:34:24.583 | 0:361 | 299 |

## Grounding checks performed

- Source `/data/downloads/Cold.Eyes.2013.Bluray.Remux.mkv` present (21.4 GB) ✓
- Installed `qsvencc` = r4385 (stock rigaya) ✓
- QSV ffmpeg available (dlstreamer system ffmpeg + ffmpeg-8.1) ✓
- No pending todos matched Phase 1.

## Deferred (out of phase scope)

- av1_vaapi (Phase 2), host-side levers (Phase 3), workaround + content gate (Phase 4), Cold Eyes re-encode (DEBT-01, v2).
