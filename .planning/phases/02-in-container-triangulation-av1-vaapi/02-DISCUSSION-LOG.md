# Phase 2: In-Container Triangulation — av1_vaapi - Discussion Log

> **Audit trail only.** Not consumed by downstream agents (researcher, planner, executor).
> Decisions captured in `02-CONTEXT.md`; this log preserves the discussion.

**Date:** 2026-07-23
**Phase:** 02-in-container-triangulation-av1-vaapi
**Mode:** discuss (default)
**Areas discussed:** Command + triad-fidelity gate, Corruption classification, Sample size & clean-claim rigor, Content-origin confirmation

## Pre-discussion grounding

Verified live before framing gray areas:
- `av1_vaapi` and `av1_qsv` encoders present in all three installed ffmpeg builds.
- Arc A380 AV1 encode entrypoint is **`VAEntrypointEncSliceLP` only** (low-power) — no full-power AV1 entrypoint. Low-power AV1 encode likely cannot do B-frames → the B-reorder leg of the trigger triad is at real risk of being non-reproducible. This shaped every subsequent question.

## Area 1 — Command + triad-fidelity gate

- **Options presented:** (a) Probe, run, caveat [recommended]; (b) Full-triad-or-declare-blocked; (c) Match knobs, let PSNR speak.
- **Selected:** (a) Probe, run, caveat.
- **Result → D-01/D-02/D-03:** Full-HW ffmpeg VAAPI pipeline kept on VA surfaces; probe which triad legs reproduce; run regardless; record active legs; report a missing B-frame leg as a PARTIAL-TRIAD data point with "immunity NOT proven" caveat.

## Area 2 — Corruption classification

- **Options presented:** (a) New av1_vaapi self-reference [recommended]; (b) Absolute PSNR vs source frame; (c) Content-origin match only.
- **Selected:** (a) New av1_vaapi self-reference.
- **Result → D-04/D-05/D-06:** Generate a determinism-confirmed single-session av1_vaapi self-reference (923/off 299); classify concurrent frames by PSNR vs it at the same `<30 dB` threshold. Phase-1 qsvencc reference is invalid for this encoder.

## Area 3 — Sample size & clean-claim rigor

- **Options presented:** (a) Detection-20, gated escalation [recommended]; (b) Detection-20 only, defer validation; (c) Always full validation-N ~60.
- **Selected:** (a) Detection-20, gated escalation.
- **Result → D-07/D-08:** Detection-N=20 first; ≥1 corrupt → report and stop; 0/20 with full triad → escalate to ~60 zero-failure for a clean claim; 0/20 with partial triad → no escalation, detection-grade partial-triad only.

## Area 4 — Content-origin confirmation

- **Options presented:** (a) Both qsvencc + av1_vaapi, as add-on [recommended]; (b) av1_vaapi corrupt frames only; (c) Skip — PSNR clean/corrupt only.
- **Selected:** (a) Both qsvencc + av1_vaapi, as add-on.
- **Scope note:** Deliberate, user-approved add-on that reuses harness frames already on disk to close the content-origin thread Phase 1's `summary.txt` explicitly deferred "to Phase 2." Kept as an add-on to the PSNR classifier, not a scope expansion of DIAG-02's measurement.
- **Result → D-09/D-10:** On any `<30 dB` frame, cross-match content against the other concurrent scenes (928/1129) to confirm a cross-session swap; apply to both the qsvencc baseline and any av1_vaapi corrupt frame.

## Deferred ideas

- Phase 3 (host-side levers), Phase 4 (workarounds + content gate), Phase 5 (DoD report), DEBT-01 (re-encode) — all left out of scope.

## Claude's discretion (recorded)

- av1_vaapi rate-control mapping, tile/gop flag translation, capability-probe scripting, content-origin cross-match implementation, and how the av1_vaapi path is wired into `harness.sh`.
