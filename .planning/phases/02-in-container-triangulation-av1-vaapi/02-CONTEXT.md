# Phase 2: In-Container Triangulation — av1_vaapi - Context

**Gathered:** 2026-07-23
**Status:** Ready for planning

<domain>
## Phase Boundary

Run the *pure VA-API* `av1_vaapi` encode path (ffmpeg → libva directly, **bypassing oneVPL**) under the same 3-way concurrency through the Phase 1 harness, with its own paired ffmpeg `av1_qsv` immune control in the same run, and record clean-vs-corrupt plus an explicit interpretation. This is the cheapest, fully-unblocked differentiator — one data point (DIAG-02) sequenced before any host-side ask.

The device-under-test is an **ffmpeg VAAPI pipeline** (HW VAAPI decode → VA video-memory surfaces → `av1_vaapi` encode, kept entirely on VA surfaces, no download to system RAM so the shared-VA-pool condition is preserved) — NOT `qsvencc`. The harness (`scratch/repro/harness.sh`) is reused, extended with an `av1_vaapi` measurement path; it is not rewritten.

Out of scope (later phases): host-side levers — GuC/HuC firmware, i915→Xe (Phase 3); workaround throughput measurement and the defense-in-depth content gate (Phase 4); the DoD synthesis report (Phase 5).
</domain>

<decisions>
## Implementation Decisions

### Command construction & triad-fidelity gate (Area A)
- **D-01:** Build the `av1_vaapi` device-under-test as a full-HW ffmpeg VAAPI pipeline: HW VAAPI decode (`-hwaccel vaapi -hwaccel_output_format vaapi`) → VA video-memory surfaces → `-c:v av1_vaapi`, keeping frames on VA surfaces end-to-end (no download to system RAM) so the shared-VA-pool condition that the whole bug hinges on is preserved.
- **D-02:** **Probe → run → caveat.** Before the concurrency test, empirically probe which trigger-triad legs `av1_vaapi` can actually reproduce on this Arc A380 — specifically (a) B-frame reorder (`-bf N` / hierarchical-B, the highest-risk leg), (b) P010 10-bit surfaces, (c) HW-VA video-memory decode. Reproduce **every supported leg at maximum fidelity**, run the 3-way concurrency test regardless, and **record exactly which legs were active**.
- **D-03:** **Never claim immunity off a run that could not reproduce the trigger.** If a leg (especially B-frames) is unsupported, report the result as a **PARTIAL-TRIAD data point** with an explicit "immunity NOT proven" caveat. A "cannot exercise the trigger triad via av1_vaapi LP encode" outcome is itself a valid, reportable finding.
  - *Known constraint (grounding, verified at discussion time):* on this Arc A380, AV1 encode exposes **only `VAEntrypointEncSliceLP`** (low-power) — there is no full-power AV1 entrypoint. Low-power AV1 VAAPI encode on Alchemist commonly does **not** support B-frames, so the B-reorder leg is at real risk of being non-reproducible. This is the central interpretive hazard of the phase and mirrors the Xe-gating logic already planned for Phase 3.

### Corruption classification for a different encoder (Area B)
- **D-04:** Classify corruption via a **new bit-clean single-session `av1_vaapi` self-reference** (scene 923, offset 299), mirroring the Phase-1 self-consistency method. The Phase-1 *qsvencc* reference frame is invalid here (different encoder → different clean pixels) and must not be reused.
- **D-05:** Before trusting the self-reference, **re-confirm its determinism** the way Phase 1 D-05 did: encode the isolated single session twice and verify the extracted frame is bit-identical / very-high PSNR. Only a determinism-confirmed self-reference is trusted.
- **D-06:** Keep the **same `<30 dB` = corrupt PSNR threshold** and OpenCL-free external-ffmpeg metric from Phase 1 (D-04/D-06 there). A clean concurrent frame should score ~bit-identical to the self-reference; a corrupt one drops well below 30 dB.

### Sample size & clean-claim rigor (Area C)
- **D-07:** Run **detection-N=20 first** (mirrors Phase 1). If **≥1 corrupt** → av1_vaapi reproduces corruption; report frequency + PSNR signature at detection-N and **stop** (no 60-run once positive).
- **D-08:** **Gated escalation on a clean result.** If **0/20 AND the D-02 triad gate confirmed all legs active** → escalate to **validation-N ~60 zero-failure** (rule-of-three) *within this phase* to earn a "clean/immune" claim. If **0/20 but the triad was only partial** → do **NOT** escalate (60 runs on a broken triad prove nothing); report detection-grade partial-triad only.

### Content-origin / mechanism confirmation (Area D)
- **D-09:** Add a **lightweight content-origin cross-match** as an *add-on* to the PSNR classifier (not a replacement): when any frame scores `<30 dB`, cross-match its content against the OTHER concurrently-running scenes' frames (928 / 1129) to confirm it is a genuine **cross-session content swap**, not generic garbage.
- **D-10:** Apply the content-origin cross-match to **both** the existing **qsvencc baseline** (closing the loose thread that Phase 1's `summary.txt` explicitly deferred "to Phase 2" — see its "Mechanism-vs-symptom NOTE") **and** any **av1_vaapi** corrupt frame. This upgrades the whole triangulation from "PSNR-drop symptom" to "confirmed cross-session content swap," which is exactly the mechanism interpretation the roadmap SC#2 asks for.

### Immune control (carried, not re-decided)
- **D-11:** Every av1_vaapi measurement batch keeps its **own paired ffmpeg `av1_qsv` immune control in the same run** (roadmap SC#1). A non-zero control invalidates that batch as a finding (Phase 1 D-06 semantics, unchanged).

### Claude's Discretion
- Exact `av1_vaapi` rate-control mapping (icq/qp target vs qsvencc's `--icq 24`), tile/gop flag translation, and how the capability probe is scripted.
- The concrete content-origin cross-match implementation (e.g. per-frame PSNR of the corrupt frame against each concurrent scene's decoded frames, pick best match) and its reporting format.
- How the new av1_vaapi measurement path is wired into `harness.sh` (new subcommand/flag vs parameterized encoder selector).
</decisions>

<specifics>
## Specific Ideas

- The interpretation contract from roadmap SC#2 is the north star: a **clean** av1_vaapi (with triad confirmed) strengthens the ffmpeg-migration case; **corrupt** av1_vaapi broadens the suspected fault beyond qsvencc's own oneVPL pool code toward the shared kernel/driver VA layer. State the interpretation explicitly in the report either way.
- Phase 1's own `summary.txt` "Mechanism-vs-symptom NOTE" is the authority for the D-09/D-10 content-origin work — it names the exact gap being closed.
- Verified at discussion time: `av1_vaapi` and `av1_qsv` encoders are present in all three installed ffmpeg builds; Arc A380 AV1 encode entrypoint is `VAEntrypointEncSliceLP` only (low-power).
</specifics>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Bug reproduction & triad (authoritative)
- `PROJECT.md` (repo root — the handoff) — trigger-triad definition (HW VA-decode into VA video memory + P010 10-bit + B-frame reorder), §4 reproducer recipe (scenes/seek/trim/offsets), §7 workaround space (Option C = ffmpeg migration, which this triangulation informs).

### Phase 1 harness & the deferred mechanism note
- `scratch/repro/harness.sh` — the reused measurement instrument (subcommands `probe`/`reference`/`run-iter`/`run-batch`); extend with the av1_vaapi path, do not rewrite.
- `scratch/repro/lib.sh` — shared harness helpers.
- `.planning/phases/01-harness-control-environment-fingerprinting/01-EVIDENCE.md` — the certified Phase-1 baseline (qsvencc 45%/40%/0%, control 0/20) this phase triangulates against.
- `.planning/phases/01-harness-control-environment-fingerprinting/01-CONTEXT.md` — carried decisions D-01..D-09 (harness form, classifier, threshold, control pairing, detection-vs-validation-N, data safety).
- `scratch/repro/summary.txt` — the "Mechanism-vs-symptom NOTE" that explicitly defers cross-session content-origin confirmation to this phase (drives D-09/D-10).

### Project & requirements
- `.planning/PROJECT.md` — Core Value (no silent frame swap), Validated findings, Constraints (single shared Arc GPU → sequential execution; /data read-only).
- `.planning/REQUIREMENTS.md` — DIAG-02 (this phase's sole requirement) and the detection-N vs ~60 validation-N rigor rule.
- `.planning/ROADMAP.md` §"Phase 2" — the 2 success criteria this phase must satisfy.
- `.planning/research/PITFALLS.md` — statistical rigor (detection-N vs ~60 validation-N, rule-of-three), mandatory paired control, silent-pass/frame-count trap.
- `.planning/research/STACK.md` — OpenCL-free PSNR tooling and ffmpeg VAAPI/QSV command references.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scratch/repro/harness.sh` (+ `lib.sh`) — full Phase-1 instrument: environment probe, reference generation, 3-way concurrent runner, PSNR classifier, paired av1_qsv control, batch summary. The av1_vaapi path is an extension of this, not a new tool.
- Installed ffmpeg builds all expose `av1_vaapi` and `av1_qsv` (system `ffmpeg`, `/usr/local/bin/ffmpeg-8.1`, `/usr/bin/ffmpeg`).
- Phase-1 on-disk artifacts under `scratch/repro/` (references, control_reference, report.csv, summary.txt, fingerprint.txt) — the baseline and control frames the content-origin cross-match (D-09/D-10) can reuse.
- Source media read-only: `/data/downloads/Cold.Eyes.2013.Bluray.Remux.mkv`.

### Established Patterns
- Handoff §4 protocol (reference → 3-way concurrent → extract offset → PSNR vs reference → fraction) is the canonical measurement shape; the av1_vaapi path mirrors it with an av1_vaapi self-reference.
- Determinism re-confirmation before trusting a reference (Phase-1 D-05) — repeated here for the av1_vaapi self-reference (D-05 above).
- Triad-gating before trusting a "clean" result — same discipline the roadmap bakes into Phase 3's Xe switch, applied here to the av1_vaapi LP-encode B-frame question.

### Integration Points
- None in this repo — the harness is self-contained standalone orchestration. The `enpipe` consumer (where an eventual ffmpeg-migration recommendation would land) is a separate repo not present here; this phase produces a finding, not enpipe code.
</code_context>

<deferred>
## Deferred Ideas

- Host-side levers — GuC/HuC firmware update, i915→Xe migration (Phase 3; the av1_vaapi result here informs their interpretation).
- Workaround throughput measurement (`--avsw`, `--jobs 1`, ffmpeg-migration) + defense-in-depth content-verification gate design (Phase 4).
- Definition-of-Done synthesis report (Phase 5).
- Corrupted Cold Eyes re-encode (DEBT-01) — deferred v2, user decision after a fix is chosen.

None of the above were pulled into scope; discussion stayed within the DIAG-02 boundary (with the one deliberate, user-approved add-on: reusing the harness's existing frames to close Phase 1's explicitly-deferred content-origin note — D-09/D-10).
</deferred>

---

*Phase: 02-in-container-triangulation-av1-vaapi*
*Context gathered: 2026-07-23*
