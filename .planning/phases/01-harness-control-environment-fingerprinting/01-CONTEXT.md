# Phase 1: Harness, Control & Environment Fingerprinting - Context

**Gathered:** 2026-07-23 (auto mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Build one calibrated, control-validated measurement instrument for the concurrent-encode corruption bug, and use it to reproduce the known signature in *this* environment. Deliverables: a reproduction harness (3-way concurrent `qsvencc` on scenes 923/928/1129), a paired ffmpeg `av1_qsv` immune control, a bit-clean reference frame + PSNR-based corruption classifier, and an environment fingerprint compared to the affected host. Covers REPRO-01..05. Testing host-side levers, av1_vaapi, workarounds, and the content gate are later phases — out of scope here.
</domain>

<decisions>
## Implementation Decisions

*Auto mode: recommended defaults selected for each gray area (logged below). All are HOW-to-implement choices within the fixed REPRO-01..05 boundary.*

### Harness form & language
- **D-01:** Standalone, self-contained shell script(s) living in an isolated writable workdir (default `scratch/repro/` under the repo, git-ignored), orchestrating `qsvencc` + `ffmpeg` via `&`/`wait`. No dependency on the `enpipe` repo (absent from this checkout).
  - *[auto] Harness form — Q: "bash orchestration script vs Python harness vs reuse enpipe?" → Selected: "self-contained bash script" (recommended: matches the documented ephemeral `scratchpad/repro_frame_corruption.sh`; simplest; no absent-repo dependency).*

### qsvencc-under-test (reproduction target)
- **D-02:** Baseline reproduction uses the **installed stock `qsvencc` r4385** on PATH (`/usr/bin/qsvencc`, rigaya, gcc 9.4.0) — the exact build the corruption was characterized against (handoff §9). The from-source r4386 build exists but is NOT the repro target (source-patching is out of scope, §5).
  - *[auto] Binary choice — Q: "stock r4385 vs from-source r4386?" → Selected: "stock r4385" (recommended: reproduction fidelity to documented baseline).*

### Concurrency, scenes & exact commands
- **D-03:** 3 concurrent `qsvencc` sessions on scenes 923/928/1129 with the exact seek/trim from handoff §4 (923: `--seek 01:16:14.167 --trim 0:339`; 928: `01:17:00.667 0:110`; 1129: `01:34:24.583 0:361`), full AV1 command line from §4 (`--avhw --va -c av1 --icq 24 --output-depth 10 --profile main --gop-len 300 --gop-ref-dist 6 --b-pyramid --tile-col 1 --tile-row 1 --tune perceptual --scenario-info archive`, color flags auto). Corruption is measured on scene 923, frame offset 299.

### Corruption detection method (OpenCL-free)
- **D-04:** Extract the hotspot frame by offset via external ffmpeg decode (`-vf select='eq(n\,299)'`, `-vsync 0`) and compute PSNR vs the reference frame with `ffmpeg -lavfi psnr`. Classify `< 30 dB` = corrupt (known signature ≈ 15.74 dB). Do **not** use `qsvencc --psnr/--ssim` (OpenCL-gated; avoid per project constraint). Metric ffmpeg = any (system `/usr/bin/ffmpeg` 6.1.1 or `ffmpeg-8.1`).

### Reference generation
- **D-05:** Produce the bit-clean reference by encoding scene 923 in a **single isolated session** (no concurrency) and extracting frame off=299; re-confirm determinism (isolated re-encode is bit-identical, per handoff §3) before trusting it as the reference.

### Immune control pairing
- **D-06:** Every qsvencc measurement batch runs a **paired ffmpeg `av1_qsv` immune control** (HW `h264_qsv` decode + `vpp_qsv=format=p010le` + `GopRefDist:6 BRefType:pyramid`) using a QSV-enabled ffmpeg (dlstreamer's system ffmpeg or `ffmpeg-8.1`). Expected 0/N. A non-zero control run **invalidates the harness** for that batch — it is not counted as a qsvencc finding.

### Sample sizes & statistics
- **D-07:** Iteration count is parametrized. Phase-1 **baseline detection** default = **20 iterations** (sufficient to observe the ~33–65% rate). The larger **~60 zero-failure validation-N** (rule-of-three) is defined but reserved for later fix/clean claims — NOT run in Phase 1. Report corruption fraction + per-corrupt-frame PSNR, and state detection-N vs validation-N explicitly.

### Environment fingerprint
- **D-08:** Collect and record to a fingerprint file: `uname -r`; bound GPU driver (i915 vs xe, via `/sys/bus/pci/devices/*/driver` or `lspci -k`); iHD + VA-API version (`vainfo`); GuC/HuC firmware (`dmesg | grep -iE 'guc|huc'` and/or sysfs). Explicitly state whether the kernel matches the affected `6.19.14-200.fc43`. (Known at init: this env reports `6.19.14-200.fc43` — the SAME kernel — so reproduction is expected; the fingerprint confirms and captures driver/firmware detail.)

### Data safety
- **D-09:** All harness outputs (`.obu` chunks, extracted frames, logs, PSNR/CSV results, fingerprint) go to the isolated writable workdir. **Never** write to `/data`. Source is read-only from `/data/downloads/Cold.Eyes.2013.Bluray.Remux.mkv` (confirmed present, 21.4 GB).

### Claude's Discretion
- Exact frame-extraction encoding (PNG vs rawvideo), log/report formatting, the concrete workdir path, and how multi-scene results are aggregated into the corruption-rate report.
</decisions>

<specifics>
## Specific Ideas

- The prior `scratchpad/repro_frame_corruption.sh` (ephemeral, to be recreated) is the reference shape for the harness protocol (handoff §4 steps 1–4).
- Corruption signature is deterministic: same reordered-reference slot, PSNR ≈ 15.74 dB run-to-run — the classifier can sanity-check against this expected value, not just the `<30 dB` threshold.
</specifics>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Bug reproduction (authoritative)
- `PROJECT.md` (repo root — the handoff) — §4 reproducer recipe (scenes 923/928/1129, exact seek/trim, exact qsvencc command, 4-step protocol), §3 root-cause chain, §9 gotchas (OpenCL-free metrics, VMAF locale), §10 Definition of Done.

### Project & requirements
- `.planning/PROJECT.md` — project context, Core Value (no silent frame swap), Validated findings.
- `.planning/REQUIREMENTS.md` — REPRO-01..05 (this phase's requirements).
- `.planning/ROADMAP.md` §"Phase 1" — the 5 success criteria this phase must satisfy.

### Research (this phase's how-to)
- `.planning/research/STACK.md` — per-frame PSNR/VMAF tooling, the exact ffmpeg `av1_qsv` control command, diagnostic tooling; "what NOT to use" (`--psnr/--ssim`, `--disable-va`).
- `.planning/research/PITFALLS.md` — statistical rigor (detection-N vs ~60 validation-N), mandatory paired control, silent-pass/frame-count trap, VMAF CSV field-16 gotcha.
- `.planning/research/ARCHITECTURE.md` — the 10-component harness (Environment Probe → Reference/Concurrent Runners → Frame Extraction → Metric Engine → Classifier → Report + Throughput Sampler + Content Gate) and its build-order dependencies.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Installed `qsvencc` r4385 at `/usr/bin/qsvencc` — the reproduction target (D-02).
- QSV-enabled ffmpeg for the immune control: dlstreamer system `ffmpeg` (`av1_qsv`) and `/usr/local/bin/ffmpeg-8.1`. Ubuntu `ffmpeg` 6.1.1 (also installed) usable for PSNR metrics.
- Source media present and read-only: `/data/downloads/Cold.Eyes.2013.Bluray.Remux.mkv` (21.4 GB); a shipped AV1 encode `Cold.Eyes.2013.Bluray.Remux.AV1.mkv` also exists (relevant to the DEBT-01 tech debt, not this phase).
- Environment already validated: Arc A380 drives AV1 10-bit encode + HW decode (`qsvencc --check-features`), VA-API `iHD` 1.23.0, `LIBVA_DRIVER_NAME=iHD`, `/dev/dri/renderD128` present.

### Established Patterns
- Handoff §4 protocol is the canonical harness shape (reference → 3-way concurrent → extract off=299 → PSNR vs reference → fraction).
- QSVEnc source (mapped in `.planning/codebase/`) is the tool's code; the harness itself is standalone orchestration, not a source change.

### Integration Points
- None in this repo — the harness is self-contained. The `enpipe` consumer (where the eventual workaround lands) is a separate repo not present here; Phase 1 produces no enpipe code.
</code_context>

<deferred>
## Deferred Ideas

- av1_vaapi triangulation — Phase 2.
- Host-side levers (GuC/HuC firmware, i915→Xe) — Phase 3.
- Workaround throughput measurement + defense-in-depth content gate — Phase 4.
- Corrupted Cold Eyes re-encode (DEBT-01) — deferred v2, user decision after a fix.
</deferred>

---

*Phase: 01-harness-control-environment-fingerprinting*
*Context gathered: 2026-07-23*
