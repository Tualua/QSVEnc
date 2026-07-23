---
phase: 1
reviewers: [opencode, qwen]
reviewed_at: 2026-07-23
plans_reviewed: [01-01-PLAN.md]
note: claude skipped (self — running inside Claude Code CLI); gemini/codex/cursor/coderabbit not installed
---

# Cross-AI Plan Review — Phase 1

## OpenCode Review (model: glm-5.2)

### 1. Summary

This is a thoroughly-researched, well-grounded plan that benefits from live pre-verification of nearly every command against the real source and tools. The methodology — threshold-based PSNR classification (not hardcoded dB equality), paired immune control, md5-verified reference determinism, graceful degradation for blocked container capabilities — is sound and directly serves the phase goal of a calibrated, control-validated reproduction instrument. The plan's main weaknesses are in **operational resilience of the autonomous 20-iteration batch run** (no timeout, no per-iteration error recovery, no zombie-process cleanup) and **ambiguous concurrency semantics for the paired control**. These are fixable specification gaps, not architectural flaws.

### Concerns

**HIGH**
- **Control concurrency semantics undefined** — Task 2 says run the control "in the SAME iteration" but doesn't say whether the 3 ffmpeg control sessions run *concurrently with* the 3 qsvencc sessions (6-way) or *sequentially after*. Load-bearing: concurrent 6-way no longer matches the documented 3-way trigger and could corrupt the control under heavier load; sequential is the correct differential design (ffmpeg immune to its *own* 3-way). Research ran them separately → sequential intended, but the plan must state it.
- **No timeout / process-recovery for the autonomous 20-iteration batch** — a hung qsvencc (plausible for a driver-level i915 concurrency bug) makes `wait $Pn` block indefinitely. Highest-probability failure mode for an autonomous GPU job.
- **No per-iteration error recovery** — if an iteration fails (non-zero exit, disk full, zombie holding renderD128), behaviour is unspecified; a zombie would trip `require_gpu_exclusive()` on the next iteration and cascade-abort. Needs continue-on-failure + cleanup + `N_actual` vs `N_requested`.

**MEDIUM**
- Frame-offset off-by-one noted but not gated (assert `nb_read_frames == 340` before measuring, else stop).
- Control-reference re-generation not structurally guarded (lives inside `run-iter` → re-encoded 20×); make it a `control-reference` subcommand.
- `matches_known_signature` semantics confusing (vs 15.74 dB → always false here); rename to `matches_documented_signature` or compare to this env's own value / `signature_stable_across_iterations`.
- Error policy (`set -e`) unspecified for `run-iter`/`run-batch`.
- Statistical reporting: with N=20 and 33–65% rate, 95% CI ≈ ±20pp; report raw count + Clopper-Pearson CI, not a bare percentage.

**LOW**
- No disk-space preflight (`df`) / intermediate `.obu` cleanup.
- Launch timing jitter (`&` starts within ms, not simultaneous) — negligible but worth a note.
- **Mechanism-confirmation gap**: Open Question 1 (is the corrupt frame's content from a *different session's* scene?) is the mechanistic heart of the bug definition, but Task 3 makes it optional — flag it as a gap (PSNR-drop is symptom, content-swap is mechanism).
- `report.csv` format (header row? bool encoding? invalid-iteration marker?) unspecified.

**Risk: MEDIUM** — methodology strong; risk concentrated in operational execution of the autonomous batch (the 3 HIGH concerns all converge on: the batch stalls, aborts partway, or produces a contaminated/invalid baseline). Fixable with 5–15 lines of bash each → then LOW.

---

## Qwen Review

### Summary

A well-researched, tightly-scoped plan that correctly treats the investigation as measurement-instrumentation rather than code construction, building on extensive live-session validation. Strong environment awareness (CAP_SYS_ADMIN gaps, absent tools).

### Concerns

**HIGH**
- **No inter-iteration GPU-cooldown / serialization guard** — 20 iterations run back-to-back; if iteration N's VA surfaces/renderD128 handles aren't fully released before N+1 starts, cross-iteration contamination skews the corruption rate. VA surface release may be async to process exit. Add `sleep 2` + re-check `gpu_clients` empty between iterations.
- **Control and target run sequentially within an iteration, not simultaneously** — temporal separation means the control's "clean" result (10s later) may not be a valid control for the target run if corruption depends on a specific contention moment (thermal/queue-depth/freq). Handoff says the control must run "alongside." Run all 6 processes (3 qsvencc + 3 ffmpeg) truly simultaneously with separate output dirs.

**MEDIUM**
- No explicit handling of qsvencc non-zero exit codes (Rn != 0): mark iteration `EXEC_FAILURE`, skip PSNR, don't count toward corruption fraction, optionally retry.
- `control_reference/` generation timing unspecified — generate during the `reference` subcommand (Task 1) under the same `require_gpu_exclusive` gate.
- No timeout on individual encode processes — one hung encode stalls the batch for hours.

**LOW**
- Open Question 3 (check all 3 scene hotspots) left ambiguous — make multi-scene PSNR mandatory (all `.obu` files already exist; near-zero cost).
- `report.csv` format / `matches_known_signature` boolean rule not fully specified.
- Root `PROJECT.md` still points at the ephemeral `scratchpad/repro_frame_corruption.sh`; add a self-documenting header to `harness.sh`.

**Risk: MEDIUM** — technically sound; the core methodology matches the correctness-first mandate. With the concurrency/isolation/timeout fixes applied, risk drops to LOW.

---

## Consensus Summary

Both reviewers independently rate the plan **MEDIUM risk**, agree the methodology and live-verified research foundation are **strong**, and agree every concern is a **specification gap fixable in a few lines of bash — not a design flaw**. Reproduction correctness is not in doubt; the risk is in the operational robustness of the autonomous batch.

### Agreed Strengths (both reviewers)
- Live pre-verification of every command against the real 21 GB source + real binaries.
- Threshold classifier (`<30 dB`) that **reports** the observed dB, not hardcoding 15.74/12.8.
- Paired ffmpeg `av1_qsv` immune control that invalidates a batch if non-clean.
- Graceful per-line degradation of the environment probe (no CAP_SYS_ADMIN).
- Detection-N=20 vs validation-N≈60 (rule-of-three) discipline.
- Data safety: isolated `scratch/repro/` workdir, `/data` read-only.
- Per-PID exit capture (`wait $PID; R=$?`) and correct `-profile:v main`.

### Agreed Concerns (raised by BOTH — highest priority)
1. **Paired-control concurrency semantics must be made explicit** (HIGH/HIGH) — the plan doesn't state whether the control runs concurrently or sequentially with the qsvencc measurement. *See Divergent Views for the direction disagreement.*
2. **Per-encode timeout + process/zombie cleanup** (HIGH opencode / MEDIUM qwen) — a hung qsvencc blocks `wait` indefinitely; needs `timeout` + `kill` cleanup so one GPU hang doesn't stall the whole batch.
3. **Per-iteration exit-code / error recovery** (HIGH opencode / MEDIUM qwen) — non-zero encode exit must mark the iteration `EXEC_FAILURE` (not corrupt/clean), be excluded from the corruption fraction, and report `N_actual` vs `N_requested`.
4. **Control-reference generation** should be a once-only step in Task 1 under the GPU-exclusivity gate, not re-run inside `run-iter` (MEDIUM/MEDIUM).
5. **`matches_known_signature` field + `report.csv` schema** need a precise definition (MEDIUM/LOW) — the field is uninformative as written (env value ≠ 15.74).
6. **Multi-scene hotspots (923/299 + 928/96 + 1129/299)** should be mandatory, not optional — near-zero extra cost (LOW/LOW).

### Divergent Views (worth deciding explicitly)
- **Control execution direction.** Both flag the ambiguity; they recommend **opposite fixes**:
  - **OpenCode → sequential** (control after target): concurrent 6-way changes the qsvencc contention profile away from the documented 3-way trigger and risks corrupting the control itself under heavier load.
  - **Qwen → truly concurrent** (6 processes at once): the handoff says the control runs "alongside," and temporal separation weakens same-environment validity.
  - *Orchestrator note for `--reviews` replan:* the documented trigger triad is **same-tool 3-way** concurrency, and the immune control is ffmpeg's immunity to **its own 3-way** — so OpenCode's sequential design preserves the trigger conditions and is the safer default. Whichever is chosen, the plan must state it and its rationale explicitly.
- **Mechanism vs symptom** (opencode-only, worth noting): confirming the corrupt frame's content comes from a *concurrent session's scene* (the bug's definition) is only a symptom-level PSNR drop in this phase — opencode wants it flagged as a deliverable gap; reasonable to defer the content-swap confirmation to Phase 2 but say so.
