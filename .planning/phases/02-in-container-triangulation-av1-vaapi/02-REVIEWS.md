---
phase: 2
reviewers: [opencode, qwen]
reviewed_at: 2026-07-23T08:47:39Z
plans_reviewed: [02-01-PLAN.md,02-02-PLAN.md,02-03-PLAN.md,02-04-PLAN.md,02-05-PLAN.md]
skipped: [claude (self — running inside Claude Code CLI), gemini/codex/coderabbit/cursor (not installed), lm_studio/llama_cpp (ports open but not usable OpenAI-compatible servers)]
---

# Cross-AI Plan Review — Phase 2

## OpenCode Review
*(model: glm-5.2)*

# Cross-AI Plan Review: Phase 2 — In-Container Triangulation (av1_vaapi)

## 1. Summary

These five plans form a well-sequenced, methodologically honest measurement phase that extends a proven bash harness to triangulate whether the pure VA-API `av1_vaapi` path is immune or corrupt under the same 3-way concurrency that silently corrupts `qsvencc`. The standout quality is the triad-fidelity honesty gate: the plans correctly anticipate that the B-frame reorder leg is non-reproducible on Arc A380's low-power-only AV1 entrypoint, refuse to claim "immunity" off a partial triad, and treat "cannot exercise the trigger" as a valid reportable finding rather than a failure. The exit-244/`extra_hw_frames=64` harness gotcha is correctly identified, fixed at the source, and re-verified under concurrency. The main weaknesses are a significant underestimate of the cross-match scan cost (~8,000–10,000 ffmpeg invocations, not "well under 1,000"), an undefined "confirmed swap" PSNR threshold for the cross-match, and the absence of a minimum-valid-iteration floor for the N=20 batch. None of these are showstoppers; all are addressable before or during execution.

## 2. Strengths

- **Triad-fidelity honesty is exemplary.** Every plan that touches interpretation (02-01 probe, 02-03 summary, 02-05 evidence) consistently uses PTS/DTS (not `pict_type`), records PARTIAL-TRIAD as the expected outcome, requires the literal phrase "immunity NOT proven," gates N~60 escalation on full-triad confirmation, and phrases the B-frame caveat narrowly ("no display/decode reordering observed via PTS/DTS; not a claim of zero reference-surface-lifetime effect"). This is exactly the discipline a measurement phase demands.
- **The exit-244 gotcha is handled at the source, not the symptom.** `extra_hw_frames=64` is mandated inside `vaapi_encode()` (not in a wrapper), the smoke run in 02-02 explicitly asserts zero `EXEC_FAILURE` under 3-way concurrency (closing Assumption A2), and the fail-closed `run_encode` exit-code gate is preserved rather than loosened.
- **Near-verbatim structural reuse of Phase-1 proven machinery.** `cmd_run_iter_vaapi` copies `cmd_run_iter`'s four-step shape; `print_batch_summary_vaapi` reuses `wilson_ci()`/`scene_stats()` verbatim; the paired `av1_qsv` control is unchanged; the INT/TERM trap is extended. This minimizes the surface area for new bugs.
- **D-05 determinism re-confirm has a PSNR fallback.** The plan doesn't assume av1_vaapi is bit-deterministic — it tries md5 first, then falls back to ≥50 dB PSNR, and fails closed if neither holds. This is more robust than blindly trusting md5 on an unverified encoder.
- **D-09/D-10 content-origin cross-match closes a real deferred thread.** Phase-1's `summary.txt` explicitly deferred the mechanism-vs-symptom question. The cross-match reuses `psnr_of` (no new methodology), reads the corrupt set from `report.csv` at runtime (not hardcoded), reads `runs/` strictly read-only, and emits an explicit "N/A this batch" line when av1_vaapi produces 0 corrupt frames — absence is never silent.
- **02-05 EVIDENCE.md mirrors Phase-1's durability fix.** Git-tracked verbatim snapshots of git-ignored runtime outputs, with "do not force the expected narrative" if real data differs from the research prediction.
- **Scope is well-bounded.** The D-09/D-10 add-on is the only scope expansion beyond strict DIAG-02, and it was explicitly user-approved in CONTEXT.md. No host-side levers, no enpipe code, no throughput measurement — all correctly deferred to later phases.
- **Wave dependency ordering respects the single-shared-GPU constraint.** Plans are strictly sequential (1→2→3→4→5), each blocked on the prior. No plan launches a competing GPU process during a measurement batch.

## 3. Concerns

- **[HIGH] Cross-match scan cost is severely underestimated.** RESEARCH.md claims "well under 1000 total ffmpeg invocations across the whole historical qsvencc batch." The actual count: 17 corrupt frames × 2 other-scenes × ~(110+361) candidate frames = **~8,000–10,000+ ffmpeg invocations** (frame extraction + PSNR each). At ~0.3–0.5s per invocation, this is 40–80 minutes of wall-clock time, not the trivial cost the research implies. 02-04 Task 1's verify block runs `cross-match-qsvencc` live with no timeout accommodation. If the executor's default timeout is short, this will fail spuriously. The scan itself is correct; the time budget is wrong.

- **[MEDIUM] No explicit "confirmed swap" PSNR threshold for the cross-match.** 02-04 says "A high best PSNR (near-identical) against a DIFFERENT concurrent scene's frame confirms a cross-session content SWAP" but never defines "high." RESEARCH.md Pattern 2 suggests ">30 dB / near-inf" — but >30 dB is the same threshold used to classify a frame as corrupt vs its own self-reference. A cross-scene match at 31 dB is ambiguous: is it a confirmed swap or just incidental pixel similarity? Without a distinct, higher threshold (e.g., ≥40 dB or ≥50 dB), the aggregate verdict ("confirmed cross-session swap vs generic garbage") is subjective and non-reproducible.

- **[MEDIUM] No minimum valid-iteration floor for the detection-N=20 batch.** 02-03 Task 2's verify accepts `≥45` scene rows out of 60 (75%). If 5 of 20 iterations are `CONTROL_INVALID` or `EXEC_FAILURE`, the batch drops to 15 valid iterations — still ≥45 rows? No: 15 × 3 = 45, which barely passes. But 15 valid iterations significantly reduces the detection power versus 20. There should be an explicit minimum (e.g., "if <17 of 20 iterations produce OK rows, the batch is inconclusive — re-run") rather than silently accepting a degraded denominator.

- **[MEDIUM] `pict_type` grep in 02-01 verify is unscoped.** The verify asserts `! grep -q 'pict_type' scratch/repro/harness.sh` across the ENTIRE file. If any pre-existing Phase-1 code references `pict_type` (e.g., in a comment, or for the qsvencc H.264 path where it IS valid), this verify fails spuriously. The check should be scoped to the new vaapi functions, or at minimum to non-comment lines in the vaapi section.

- **[MEDIUM] 02-04 corrupt-frame extraction for 1129 assumes `frame299_1129.png` is on disk.** The plan says "extract the corrupt frame PNG via the scene offset if not already on disk" but doesn't specify how. For 923, `frame299.png` is the known artifact. For 1129, the plan references `frame299_1129.png` — but Phase-1's `01-EVIDENCE.md` report.csv marks corrupt 1129 iterations (it05,06,09,10,12,13,14,18). Were the 1129 corrupt frames extracted and saved as PNGs during Phase 1, or only the 923 ones? If not, the cross-match needs to extract them from `c1129.obu` first, which is an extra step not fully specified.

- **[LOW] Wall-clock time for the full N=20 batch is not estimated or bounded.** 20 iterations × (3 concurrent av1_vaapi + 3 sequential av1_qsv control) = ~120 encodes + PSNR extractions. On a single shared GPU with GPU-exclusivity gating between iterations, this could take 1–3 hours. No plan mentions this or suggests splitting the batch. Not a correctness issue, but an operational surprise risk.

- **[LOW] 02-02's placeholder summary could persist if 02-03 doesn't fully replace it.** 02-02 explicitly leaves the summary call as "a placeholder/no-op or a bare row dump." If 02-03's wiring step is incomplete or the executor skips it, the batch could run with no summary. The 02-03 verify block checks for `print_batch_summary_vaapi` in the code and `summary_vaapi.txt` on disk, which would catch this — but only if 02-03's verify actually runs.

- **[LOW] The D-05 PSNR fallback threshold of ≥50 dB is unjustified.** For true bit-determinism, PSNR should be infinite. 50 dB is "very high" but not bit-identical. The plan doesn't explain why 50 dB is sufficient to trust the self-reference. In practice this is fine (50 dB means ~1-bit average difference), but the threshold should be documented as a deliberate choice, not an arbitrary number.

- **[LOW] 02-05's re-run safety net could be expensive.** "If any is missing or stale, re-run the sequence on the live GPU sequentially" could trigger a full N=20 re-run if the workdir was cleaned between 02-03 and 02-05. The plan should more strongly emphasize preserving the workdir (or checkpointing outputs to a git-tracked location earlier) rather than relying on re-runs.

## 4. Suggestions

- **Add an explicit cross-match "confirmed swap" threshold.** Define a distinct threshold (e.g., ≥40 dB best-match against a different concurrent scene's frame = "confirmed cross-session content swap"; <40 dB best-match = "generic garbage / no cross-scene origin found"). This should be higher than the 30 dB corrupt-classification threshold to avoid threshold conflation. Document it in 02-04 and surface the threshold value in `crossmatch_qsvencc.txt` so the verdict is auditable.

- **Add a minimum-valid-iteration check to `cmd_run_batch_vaapi`.** After the batch loop, if `n_actual < ceil(0.85 * n_requested)` (i.e., <17 of 20), emit a "DEGRADED BATCH" warning in the summary and note that detection power is reduced. This prevents a silently underpowered batch from being reported at face value.

- **Scope the `pict_type` grep to the vaapi section.** Replace `! grep -q 'pict_type' scratch/repro/harness.sh` with something like `! grep -A50 'vaapi_encode' scratch/repro/harness.sh | grep -q 'pict_type'` or check only the new functions. Alternatively, add a comment in the existing code if `pict_type` is already used legitimately, and scope the ban to the vaapi probe path.

- **Add a time estimate and optional batch-split capability.** In 02-03, note that N=20 may take 1–3 hours. Consider supporting `run-batch-vaapi 10` twice (appending to the same CSV) so the batch can be interrupted and resumed. This is optional but operationally valuable.

- **Pre-extract or verify all corrupt-frame PNGs before the cross-match loop.** In 02-04 Task 1, add an explicit preflight: for each corrupt iteration in `report.csv`, verify that the corrupt frame PNG exists on disk (or extract it from the `.obu` via `scene_offset` before entering the cross-match loop). This prevents the loop from failing mid-way through an 8,000-invocation scan.

- **Consider a candidate-frame caching optimization for the cross-match.** Each `.obu` file's frames are extracted fresh for every corrupt frame in the same iteration. If iteration `it04` has corrupt frames in both 923 and 1129, the 928.obu frames are extracted twice. Caching extracted candidate PNGs per `.obu` per iteration would roughly halve the ffmpeg invocation count. This is purely an optimization; the correctness is unaffected.

- **Add a cross-match tie-breaking rule.** If the corrupt frame matches both other scenes at similar PSNR (within 2 dB), the verdict should state "ambiguous origin" rather than picking an arbitrary best. This is an edge case but matters for mechanism honesty.

- **Document the ≥50 dB determinism threshold.** Add a one-line rationale in 02-01 Task 2: "50 dB corresponds to <1-bit average per-pixel difference, sufficient to rule out a concurrency-induced content swap (which scores ~13 dB) while tolerating non-bit-exact rate-control nondeterminism."

## 5. Risk Assessment

**Overall risk: LOW–MEDIUM**

The plans are well-researched, methodologically sound, and exceptionally honest about the triad-fidelity limitation — the single biggest interpretive hazard of the phase. The exit-244 gotcha is correctly handled. The statistical rigor (detection-N=20, gated escalation, paired control, Wilson CI) is carried forward from Phase 1 without dilution. The fail-closed philosophy is consistently applied.

The MEDIUM risks are all operational, not correctness-affecting:
- The cross-match time underestimate won't produce wrong results, but it could cause a timeout failure during 02-04's live verify. This is easily mitigated by increasing the executor timeout or splitting the scan.
- The missing "confirmed swap" threshold won't cause silent misclassification (the best-match PSNR is always reported), but it could lead to an ambiguous aggregate verdict that's hard to interpret downstream.
- The missing minimum-valid-iteration floor won't cause false positives, but it could allow an underpowered batch to be reported at face value.

None of these risks could cause a silent frame-swap to ship undetected — the core project invariant is preserved. The plans will achieve both Phase-2 success criteria: SC#1 (av1_vaapi concurrent run with paired control) is met by 02-02; SC#2 (recorded result with explicit interpretation) is met by 02-03 + 02-05. The expected PARTIAL-TRIAD "immunity NOT proven" outcome is a valid, honest DIAG-02 finding that correctly informs — without overstating — the downstream Phase 3/4 decisions.

---

## Qwen Review

# Phase 2 Plans Review — In-Container Triangulation (av1_vaapi)

## Summary

These are **strong, disciplined measurement plans** that faithfully mirror the Phase 1 harness's fail-closed philosophy and correctly anticipate the expected PARTIAL-TRIAD outcome. The triad-fidelity honesty gate (D-03), the extra_hw_frames=64 fix, the paired immune control (D-11), and the D-08 gated escalation logic are all correctly specified. The plans succeed at what they set out to do — extend a bash measurement instrument, not build product code. Two specific gaps in the content-origin cross-match (02-04) need addressing before execution: the search cost is significantly underestimated, and the match-success threshold is left undefined.

---

## Strengths

- **Honest about expected outcome.** Every plan treats "PARTIAL-TRIAD, B-frame reorder UNSUPPORTED" as the *expected* result (not an edge case), and D-03's "immunity NOT proven" language is baked into 02-03's summary and 02-05's evidence artifact. This prevents over-claiming.
- **Fail-closed classification preserved end-to-end.** The exit-244 / extra_hw_frames=64 fix is placed at the source (inside `vaapi_encode()`), not worked around by loosening the `run_encode` gate. Unknown probe legs degrade to UNKNOWN, not silently UNSUPPORTED. Missing PSNR → NA, not clean.
- **Pitfall 6 (wrong reference) protected.** Separate `vaapi_ref_png` filenames, distinct from qsvencc references, enforced across all plans. The self-reference determinism gate (D-05) with md5 + ≥50 dB PSNR fallback is sound.
- **Verbatim reuse of Phase 1 primitives.** `psnr_of`, `classify_corrupt`, `ctrl_encode`, `run_encode`, `require_gpu_exclusive`, `wilson_ci` — all reused, not re-implemented. The pattern-map correctly identifies every analog.
- **D-08 gated escalation correctly specified.** All three branches are explicit: positive → stop; 0 + full triad → escalate N~60; 0 + partial triad → do NOT escalate. The literal "immunity NOT proven" phrase is required.
- **Sequential single-GPU constraint respected.** Plans explicitly state "never launch a competing GPU process during the batch." The inter-iteration GPU-idle recheck with `cleanup_gpu_procs` retries is carried from Phase 1.
- **Worker-function contract enforced.** New helpers `return 1`, never `exit`/`die()` — only top-level `cmd_*` entries exit.

---

## Concerns

### HIGH

1. **Cross-match cost massively underestimated (02-04, both tasks).** The Research claims "well under 1000 total ffmpeg invocations," but the actual math is far higher. For the 17 known qsvencc corrupt iterations: 9 corrupt frames from scene 923 each scan ~110 (scene 928) + ~361 (scene 1129) = ~471 candidate frames, each requiring 2 ffmpeg calls (extract PNG + PSNR) → 9 × 471 × 2 ≈ **8,478 calls**. 8 corrupt frames from scene 1129 each scan ~340 (scene 923) + ~110 (scene 928) = ~450 → 8 × 450 × 2 ≈ **7,200 calls**. Total: **~15,700 ffmpeg invocations**. At ~0.5–1s each, this is **2–4 hours of wall-clock time**, not a "trivial amount." The plan should either:
   - Acknowledge this cost and set operator expectations (e.g., "this subcommand will take ~2–3 hours on the live machine"), or
   - Add a progress indicator (e.g., print every 100 candidates scanned), or
   - Consider a coarse pre-filter (e.g., keyframe-only or sampled subset) if wall-clock becomes a blocker.

2. **Cross-match success threshold undefined (02-04).** The plan says "A high best PSNR (near-identical) against a DIFFERENT concurrent scene's frame confirms a cross-session content SWAP" but never defines the threshold. What PSNR value separates "confirmed swap" from "ambiguous"? Given Phase 1 corrupt frames scored 12–22 dB vs their *own* reference, a cross-session match at ≥35 dB would be a strong signal. The plan needs an explicit threshold (e.g., `best_psnr >= 35 dB → confirmed swap; 20–35 dB → ambiguous; <20 dB → likely generic garbage`) so the verdict is measurable, not qualitative.

### MEDIUM

3. **Missing `vaapi_probe.txt` degradation path (02-03, Task 1).** `print_batch_summary_vaapi` reads `vaapi_probe.txt` for the triad caveat, but the plan doesn't specify what happens if the file is missing (e.g., workdir cleaned, probe never run). It should degrade gracefully: `triad caveat: UNAVAILABLE — probe not run or file missing` rather than erroring or emitting an empty block.

4. **Summary placeholder in 02-02 must be replaced in 02-03.** The 02-02 plan leaves `print_batch_summary_vaapi` as "a placeholder/no-op" inside `cmd_run_batch_vaapi`. If the executor forgets to replace it in 02-03 Task 1, the batch produces rows but never a summary — silently defeating the phase's success criteria. The 02-02 plan should explicitly flag this as a "MUST be replaced in 02-03, do not ship with placeholder" note.

5. **Cross-match reads report.csv at runtime (02-04, Task 1) — but what if it's missing?** The plan says "determines the corrupt set at runtime by re-reading scratch/repro/report.csv" but doesn't guard against the file being missing (e.g., workdir cleaned since Phase 1). It should fall back to the known corrupt iteration list from 01-EVIDENCE.md or fail loudly with instructions.

### LOW

6. **PSNR ≥50 dB determinism fallback threshold (02-01, Task 2).** The qsvencc reference got `inf` (bit-identical) across two runs. If `av1_vaapi` has higher encode variance (RC-mode ICQ can vary slightly), 50 dB may be a reasonable cutoff, but it's stated without justification. A brief note like "50 dB chosen as near-identical — ~4× the <30 dB corrupt threshold, well above any plausible encode variance" would strengthen the rationale.

7. **INT/TERM trap PID naming (02-02, Task 1).** The vaapi concurrent PIDs should be named distinctly (e.g., `vp1/vp2/vp3`) from the qsvencc `p1/p2/p3` to avoid variable shadowing in the trap handler. Not a correctness issue — bash scoping handles it — but a hygiene gap.

---

## Suggestions

1. **Add a cross-match threshold table to 02-04:**
   ```
   | best_psnr | Verdict |
   |-----------|---------|
   | ≥ 35 dB   | confirmed cross-session swap |
   | 20–34 dB  | ambiguous — may be partial overlap |
   | < 20 dB   | generic garbage (not a swap) |
   ```
   This makes the verdict auditable.

2. **Add cost expectation to 02-04 Task 1:** "Expected ~15,000–16,000 ffmpeg invocations across all 17 Phase 1 corrupt frames; estimated wall-clock 2–4 hours. A progress counter will be printed every 500 candidates."

3. **Add missing-file guard to 02-03 Task 1:** If `vaapi_probe.txt` is absent, print `triad caveat: UNAVAILABLE — probe was not executed; immunity claims cannot be assessed` rather than failing.

4. **Add explicit replacement directive to 02-02 Task 2:** "The placeholder summary call in cmd_run_batch_vaapi MUST be replaced by print_batch_summary_vaapi in 02-03 Task 1. Do not commit 02-02 with the placeholder active — the batch would produce rows but no interpretive summary."

5. **Add report.csv existence check to 02-04 Task 1:** If `report.csv` is missing, fail loudly: `ABORT: report.csv not found; re-run Phase 1 run-batch first` (or fall back to the known list from 01-EVIDENCE.md as a secondary path).

---

## Risk Assessment: **MEDIUM**

**Justification:** The structural design is excellent — wave dependencies are correct, the fail-closed discipline is maintained throughout, and the plans correctly refuse to over-claim on a partial triad. The two HIGH concerns are both localized to 02-04's cross-match: one is a *cost estimate* issue (won't produce a wrong result, but could waste hours or time out the operator), and the other is a *threshold definition* gap (the cross-match could produce a number without a clear verdict line). Neither invalidates the phase's success criteria, and both are fixable with the additions suggested above. The remaining plans (02-01, 02-02, 02-03, 02-05) are ready to execute as written once the summary placeholder dependency between 02-02→02-03 is explicitly documented.

---

## Consensus Summary

Two independent reviewers (OpenCode/glm-5.2, Qwen) reviewed all 5 plans. Both rate the phase well-designed and methodologically honest, converging on the **same single hotspot: plan 02-04's content-origin cross-match**. Overall risk: **LOW–MEDIUM** (OpenCode) / **MEDIUM** (Qwen) — no concern threatens the core no-silent-frame-swap invariant, and both agree the plans achieve both Phase-2 success criteria.

### Agreed Strengths (raised by both)
- **Triad-fidelity honesty (D-03) is exemplary** — PARTIAL-TRIAD treated as the *expected* outcome, literal "immunity NOT proven" required, N~60 escalation gated on full-triad confirmation, PTS/DTS used instead of `pict_type`. Correctly refuses to over-claim immunity off a broken triad.
- **exit-244 / `extra_hw_frames=64` fixed at the source** (inside `vaapi_encode()`), not by loosening the `run_encode` fail-closed exit gate; re-verified under 3-way concurrency (A2 smoke run).
- **Verbatim reuse of Phase-1 primitives** (`psnr_of`, `classify_corrupt`, `ctrl_encode`, `run_encode`, `require_gpu_exclusive`, `wilson_ci`) — minimal new-bug surface.
- **D-05 determinism re-confirm with md5→≥50 dB PSNR fallback, failing closed** if neither holds.
- **Fail-closed everywhere**: unknown probe legs → UNKNOWN (not UNSUPPORTED); missing PSNR → NA (not clean); Pitfall-6 separate `_vaapi_ref` filenames.
- **Sequential single-shared-GPU constraint respected**; worker-function `(success,error)` contract enforced (helpers `return 1`, only `cmd_*` exit).

### Agreed Concerns (raised by both — priority order)
1. **[HIGH] Cross-match cost is massively underestimated (02-04).** RESEARCH.md's "well under 1000 ffmpeg invocations" is wrong — real count is **~8,000–16,000 invocations, ~2–4 hours wall-clock** (17 corrupt frames × 2 other scenes × ~450–470 candidate frames × 2 calls each). 02-04 Task 1 runs `cross-match-qsvencc` live in its verify block with no timeout accommodation → **spurious timeout failure risk**. Fix: set operator expectations, add a progress counter, and/or a preflight/caching/coarse pre-filter. (Correctness unaffected; time budget wrong.)
2. **[HIGH per Qwen / MEDIUM per OpenCode] Undefined "confirmed swap" PSNR threshold (02-04).** "A high best PSNR confirms a cross-session SWAP" never defines "high." Conflates with the 30 dB corrupt threshold. Fix: a distinct, higher, auditable threshold band (e.g. ≥35–40 dB = confirmed swap; 20–35 dB = ambiguous; <20 dB = generic garbage) surfaced in the crossmatch output.
3. **[MEDIUM] 02-02 placeholder summary must be explicitly replaced in 02-03.** 02-02 leaves `print_batch_summary_vaapi` as a placeholder/no-op; if 02-03 Task 1 is skipped, the batch produces rows but **no interpretive summary** — silently defeating SC#2. Fix: add an explicit "MUST be replaced in 02-03, do not ship placeholder" directive in 02-02.
4. **[MEDIUM] Missing-file guards for runtime inputs (02-03/02-04).** `report.csv` (corrupt set) and `vaapi_probe.txt` (triad caveat) are read at runtime with no guard if the workdir was cleaned. Fix: degrade gracefully (`triad caveat: UNAVAILABLE`) or fail loudly with a re-run instruction / fall back to 01-EVIDENCE.md's known corrupt list.
5. **[LOW] The ≥50 dB determinism fallback threshold is unjustified.** Both accept it as reasonable but want a one-line rationale documented (≈<1-bit avg diff, ~4× the corrupt threshold, above plausible ICQ encode variance).

### Divergent / Single-Reviewer Views (worth a look)
- **OpenCode only:** no minimum-valid-iteration floor for N=20 (a degraded 15/20 batch could be reported at face value — add a "DEGRADED BATCH" warning if <~17/20 valid); the `! grep -q 'pict_type' harness.sh` verify is unscoped and could false-fail on legitimate pre-existing qsvencc references (scope it to the vaapi section); candidate-frame caching could ~halve cross-match cost; add a cross-match tie-break rule for near-equal matches ("ambiguous origin"); 1129 corrupt-frame PNGs may need extraction from `.obu` (not on disk like the 923 ones).
- **Qwen only:** name the vaapi concurrent PIDs distinctly (`vp1/vp2/vp3`) from qsvencc's `p1/p2/p3` to avoid trap-handler shadowing (hygiene, not correctness).

### Bottom line
Plans 02-01, 02-02, 02-03, 02-05 are ready to execute as written. **02-04 is the one plan worth refining before execution** — chiefly the cross-match cost/timeout reality and the "confirmed swap" threshold. All findings are addressable via `/gsd:plan-phase 2 --reviews` (or during execution); none block the phase.
