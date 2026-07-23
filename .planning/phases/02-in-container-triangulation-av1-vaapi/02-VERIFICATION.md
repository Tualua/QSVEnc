---
phase: 02-in-container-triangulation-av1-vaapi
verified: 2026-07-23T12:09:52Z
status: passed
score: 2/2 must-haves verified (roadmap SC), 15/15 plan-level truths verified
has_blocking_gaps: false
overrides_applied: 0
---

# Phase 2: In-Container Triangulation — av1_vaapi Verification Report

**Phase Goal:** Determine whether the pure VA-API `av1_vaapi` path (bypassing oneVPL) is immune or corrupt under the same concurrency — the cheapest, fully unblocked differentiator, sequenced before any host-side ask.
**Verified:** 2026-07-23T12:09:52Z
**Status:** passed
**Re-verification:** No — initial verification

## Metadata Anomaly (non-blocking, human-informational)

`gsd-sdk query roadmap.get-phase 2` reports `"mode": "mvp"` for this phase, but the phase goal text ("Determine whether the pure VA-API `av1_vaapi` path...") is not a valid `As a ..., I want to ..., so that ....` User Story (`gsd-sdk query user-story.validate` returns `valid: false` for it). This phase is an investigation/measurement phase, not a user-facing feature — the `mode: mvp` tag on ROADMAP.md's Phase 2 entry appears to be a stale/incorrect label rather than an intentional MVP-narrowing instruction, and the orchestrator's own verification brief for this run explicitly frames the phase as investigation/measurement with the two literal roadmap Success Criteria as the ground truth. Standard goal-backward verification (not MVP User Story Flow Coverage) was applied against those two Success Criteria, matching the phase's actual nature. Recommend correcting the ROADMAP.md `mode` field for Phase 2 (and checking sibling investigation phases 1/3/4/5 for the same stale tag) so future automated verification runs don't need to make this same judgment call.

## Goal Achievement

### Observable Truths (Roadmap Success Criteria — non-negotiable contract)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | An `av1_vaapi` 3-way concurrent run executes through the Phase 1 harness, with its own paired ffmpeg `av1_qsv` immune control in the same run. | VERIFIED | `scratch/repro/harness.sh:660` `cmd_run_iter_vaapi()` launches 3 backgrounded `vaapi_encode()` calls (923/928/1129) which invoke Phase-1's unmodified `run_encode()` (`lib.sh:68`, timeout+exit gate reused verbatim); a paired `ctrl_encode` (ffmpeg av1_qsv) control runs in the same iteration (D-11). `report_vaapi.csv` (embedded in `02-EVIDENCE.md` and confirmed byte-identical on disk) has 60 rows (20 iter × 3 scenes) with `control_clean=1` on every row — the control ran and passed every time. |
| 2 | The result (clean vs corrupt, with frequency and signature if corrupt) is recorded, WITH its interpretation stated explicitly. | VERIFIED | `02-EVIDENCE.md` "Interpretation (roadmap SC#2)" section states the literal branch reasoning: 0/20 corrupt on all 3 scenes but only a PARTIAL trigger triad (`reorder: UNSUPPORTED`, `p010: ACTIVE`, `hw_decode: ACTIVE` — `vaapi_probe.txt`), therefore explicitly **"immunity NOT proven (D-03)"** — not the clean-strengthens-migration branch, not the corrupt-broadens-fault branch. `summary_vaapi.txt`'s own "Interpretation (roadmap SC#2)" block states the same conclusion verbatim on-disk. |

**Score:** 2/2 roadmap Success Criteria verified.

### Plan-Level Must-Haves (02-01 .. 02-05 PLAN frontmatter)

| # | Truth (paraphrased) | Status | Evidence |
|---|---|---|---|
| 3 | Harness builds/invokes full-HW av1_vaapi encode through run_encode gate, extra_hw_frames fix applied, exit 0 (D-01) | VERIFIED | `vaapi_encode()` at `harness.sh:286` uses `scale_vaapi=format=p010:extra_hw_frames=64`, calls `run_encode`. `report_vaapi.csv` shows `status=OK` on all 60 rows — no `EXEC_FAILURE`. |
| 4 | `probe-vaapi` records which triad legs av1_vaapi reproduces (reorder/P010/HW-decode) | VERIFIED | `cmd_probe_vaapi()` at `harness.sh:341`; `vaapi_probe.txt` on disk (verbatim match to `02-EVIDENCE.md`) shows `reorder: UNSUPPORTED`, `p010: ACTIVE`, `hw_decode: ACTIVE`. |
| 5 | Determinism-confirmed av1_vaapi self-reference for scene 923/299 exists, separate from qsvencc reference | VERIFIED | `ensure_vaapi_reference()`/`cmd_reference_vaapi()` at `harness.sh:539/621`; `scratch/repro/reference/` directory present on disk; `vaapi_ref_obu`/`vaapi_ref_png` lookups distinct from qsvencc's (per 02-01-SUMMARY, and `psnr_of` calls in `cmd_run_iter_vaapi` reference the vaapi-specific ref). |
| 6 | 3-way concurrent av1_vaapi run executes through timeout/exit gate under real concurrency (no spurious EXEC_FAILURE) | VERIFIED | `report_vaapi.csv`: 60/60 rows `status=OK`, `EXEC_FAILURE: 0` per `summary_vaapi.txt`. |
| 7 | Each av1_vaapi frame classified corrupt/clean via Phase-1 PSNR classifier verbatim (D-06) | VERIFIED | `cmd_run_iter_vaapi` calls `psnr_of()`/`classify_corrupt()` (`harness.sh:494/506`), the same functions used by the qsvencc path — confirmed via direct grep at `harness.sh:739` (`raw="$(psnr_of ...)"`, `corrupt[$scene]="$(classify_corrupt "$raw")"`). |
| 8 | Every batch runs its own paired av1_qsv immune control; non-clean control invalidates the iteration (D-11) | VERIFIED | `control_clean` column present in `report_vaapi.csv` schema, all 1 in the recorded run; `CONTROL_INVALID: 0` in `summary_vaapi.txt`. |
| 9 | Detection-N=20 batch result (clean vs corrupt, freq + signature) recorded with paired control 0/N (D-07) | VERIFIED | `report_vaapi.csv` 60 rows, `summary_vaapi.txt` states "0/20 (0.0%)" per hotspot and "control non-clean/invalidated iterations: 0/20". |
| 10 | Summary states D-02 triad caveat and gates escalation correctly (D-08) | VERIFIED | `summary_vaapi.txt` "Gated escalation (D-07/D-08)" block: "0/20 with PARTIAL/UNKNOWN triad -> do NOT escalate; 60 runs on a broken triad prove nothing" — matches the actual PARTIAL-TRIAD probe result, gate correctly not triggered. |
| 11 | Summary states roadmap SC#2 interpretation contract explicitly, including "immunity NOT proven" for partial-triad clean (D-03) | VERIFIED | Literal string "immunity NOT proven (D-03)" present in both `summary_vaapi.txt` and `02-EVIDENCE.md`. |
| 12 | Corrupt frames cross-matched against other two concurrent scenes' same-iteration frames (D-09) | VERIFIED (qsvencc leg); N/A (av1_vaapi leg, 0 corrupt frames) | `content_cross_match()` at `harness.sh:1141`; `cmd_cross_match_qsvencc()` at `harness.sh:1300` scanned all 17 Phase-1 corrupt frames — `crossmatch_qsvencc.txt` on disk matches `02-EVIDENCE.md` verbatim. av1_vaapi leg correctly reports "no av1_vaapi corrupt frame observed -> nothing to cross-match" since the batch was 0/20 clean. |
| 13 | Cross-match verdict uses explicit auditable threshold bands distinct from 30 dB corrupt threshold (>=35/20-35/<20 dB) | VERIFIED | `crossmatch_qsvencc.txt` verdicts use exactly those bands: "confirmed cross-session content swap (>=35 dB)", "ambiguous origin (20-35 dB...)", "generic garbage...(<20 dB)". |
| 14 | Cross-match applied to existing Phase-1 qsvencc corrupt frames, closing (or explicitly leaving open) the mechanism-vs-symptom note (D-10) | VERIFIED | `crossmatch_qsvencc.txt` AGGREGATE VERDICT: "17 corrupt frame(s) cross-matched... Phase 1's deferred Mechanism-vs-symptom NOTE is NOT closed by this scan" — explicitly stated open, not silently dropped. **See CR-01 caveat below** — this leg's per-frame candidate completeness is degraded for at least frame `it04-923` (15 candidates scanned vs 111-362 elsewhere), a known, already-surfaced code-review finding; does not flip the "stays OPEN" aggregate conclusion (0/17 ≥35dB either way). |
| 15 | Git-tracked `02-EVIDENCE.md` embeds verbatim on-disk outputs, states SC#2 interpretation + D-03 caveat, maps DIAG-02 to artifacts, triangulates vs Phase-1 baseline | VERIFIED | `02-EVIDENCE.md` (240 lines) present, committed (`7546e112`), contains all required sections; `report_vaapi.csv`/`crossmatch_qsvencc.txt`/`vaapi_probe.txt`/`summary_vaapi.txt` embedded content diffed byte-for-byte against the git-ignored on-disk originals — identical (only a stray closing code-fence line difference from the diff windowing, not a content mismatch). |

**Score:** 15/15 plan-level must-haves verified (14 fully VERIFIED, 1 VERIFIED-with-caveat noted, not failed).

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `scratch/repro/harness.sh` | `vaapi_encode`, `cmd_probe_vaapi`, `ensure_vaapi_reference`, `cmd_run_iter_vaapi`, `cmd_run_batch_vaapi`, `print_batch_summary_vaapi`, `content_cross_match`, `cmd_cross_match_qsvencc` functions + dispatcher wiring | VERIFIED | All 9 functions found by name at the expected line ranges (286–1909); `bash -n` syntax check passes; dispatcher `Usage:` string lists `probe-vaapi\|reference-vaapi\|run-iter-vaapi\|run-batch-vaapi\|cross-match-qsvencc`. Git-tracked (not gitignored), committed across 02-01..02-04 (`e073d9da`, `e4e59cc3`, `e372a3d7`, etc). |
| `scratch/repro/vaapi_probe.txt` | D-02 per-leg triad result | VERIFIED | On disk, content matches `02-EVIDENCE.md` embedded snapshot exactly. |
| `scratch/repro/reference/frame299_vaapi_ref.png` (or equivalent vaapi reference dir) | determinism-confirmed self-reference | VERIFIED (existence) | `scratch/repro/reference/` directory present, populated 2026-07-23 09:37, consistent with the timeline in 02-EVIDENCE.md. |
| `scratch/repro/report_vaapi.csv` | 61 lines, 60 measurement rows | VERIFIED | On disk, byte-identical (except a fenced-code artifact) to `02-EVIDENCE.md`'s embedded copy; header + 60 rows, all `status=OK`, `corrupt=0`, `control_clean=1`. |
| `scratch/repro/summary_vaapi.txt` | interpretive report incl. "immunity NOT proven" | VERIFIED | On disk, matches `02-EVIDENCE.md` embedded copy exactly, contains the literal phrase. |
| `scratch/repro/crossmatch_qsvencc.txt` | per-corrupt-frame cross-match + aggregate verdict | VERIFIED | On disk, matches `02-EVIDENCE.md` embedded copy exactly (diff clean). |
| `.planning/phases/02-in-container-triangulation-av1-vaapi/02-EVIDENCE.md` | durable git-tracked DIAG-02 record | VERIFIED | 240 lines, committed `7546e112`, `min_lines: 60` requirement exceeded 4x over, contains "DIAG-02" and "immunity NOT proven". |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `vaapi_encode()` | `run_encode` (lib.sh) | timeout-bounded encode invocation | WIRED | `harness.sh:290` `run_encode "$logfile" ffmpeg ...`. |
| `vaapi_encode()` filter | `scale_vaapi` P010 conversion | mandatory `extra_hw_frames` fix | WIRED | `harness.sh:291,346` both use `scale_vaapi=format=p010:extra_hw_frames=64`. |
| `cmd_probe_vaapi` | ffprobe pts/dts | reorder detection | WIRED | `harness.sh:377` reads `frame=pts,dts` (CR-06 caveat re: ffprobe column-drop behavior noted in 02-REVIEW.md, non-blocking). |
| `cmd_run_iter_vaapi` | `vaapi_encode` + `run_encode` | 3 backgrounded concurrent encodes, per-PID exit capture | WIRED | `harness.sh:675-679` (3× `vaapi_encode ... &`). |
| `cmd_run_iter_vaapi` | `classify_corrupt`/`psnr_of` | PSNR vs vaapi_ref_png | WIRED | `harness.sh:739` confirmed by grep. |
| `cmd_run_iter_vaapi` | `ctrl_encode` (av1_qsv control) | paired immune control (D-11) | WIRED | present in the same function body; `control_clean` column populated in every output row. |
| `print_batch_summary_vaapi` | `vaapi_probe.txt` | triad-caveat line reads D-02 verdict | WIRED | `summary_vaapi.txt`'s triad block reproduces the exact `vaapi_probe.txt` values. |
| `print_batch_summary_vaapi` | gated escalation (D-08) | 0/20 + PARTIAL → do NOT escalate | WIRED | `summary_vaapi.txt` "Gated escalation" block present and consistent with the actual PARTIAL-TRIAD result. |
| `cmd_run_batch_vaapi` | `print_batch_summary_vaapi` | batch invokes vaapi summary, replacing 02-02 placeholder | WIRED | `summary_vaapi.txt` output content matches `print_batch_summary_vaapi`'s structure (Wilson CI + triad + escalation + interpretation sections all present). |
| `content_cross_match` | `psnr_of` (reused) | loop over other two scenes' candidates, track max PSNR | WIRED | grep confirms `psnr_of` invocation inside the cross-match candidate loop. |
| `cmd_cross_match_qsvencc` | `scratch/repro/runs/itNN/*.obu` | reads Phase-1 on-disk corrupt iterations read-only | WIRED | `crossmatch_qsvencc.txt` output cites frame counts (111/362/340 candidates) consistent with reading the actual `runs/` tree. |
| `content_cross_match` | `cmd_run_iter_vaapi` corrupt branch | invoked when an av1_vaapi frame classifies corrupt (D-10) | WIRED (N/A this batch) | `summary_vaapi.txt` explicitly states "no av1_vaapi corrupt frame observed -> nothing to cross-match" — correct behavior given 0/20 corrupt, not a wiring failure. |
| `02-EVIDENCE.md` | `summary_vaapi.txt`/`vaapi_probe.txt`/`report_vaapi.csv`/`crossmatch_qsvencc.txt` | verbatim embedded snapshots | WIRED | Byte-diff clean against on-disk (git-ignored) originals. |
| `02-EVIDENCE.md` | `01-EVIDENCE.md` qsvencc baseline | triangulation comparison | WIRED | "Triangulation vs Phase-1 baseline" table cross-references 01-EVIDENCE.md's certified 923/928/1129/control figures. |

### Data-Flow Trace (Level 4)

Not applicable in the conventional sense (no UI/component rendering dynamic state) — this is a measurement harness. The equivalent trace is: does the *recorded* summary/evidence data actually originate from a real GPU-encoded/decoded measurement rather than a stub or hardcoded value?

- `psnr_of()` calls real `ffmpeg ... -lavfi psnr` (not a stub); `classify_corrupt()` branches on the real numeric result (`harness.sh:494-519`).
- `report_vaapi.csv`'s `psnr_db=inf` values were cross-checked against Phase 1's already-certified `report.csv`, which shows the identical `inf` pattern for its own clean rows (e.g. all 928/96 qsvencc rows) — confirming `inf` is the harness's genuine "byte-identical to reference" signal, not a broken/empty-PSNR default being misreported as clean. `classify_corrupt()` explicitly treats an *empty* PSNR as `NA`/`MEASURE_FAILURE`, never as clean — ruling out the "empty defaults to clean" failure mode.
- **Status: FLOWING** — the reported 0/20 result is a real GPU-measured outcome, not a placeholder.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| harness.sh has no syntax errors | `bash -n scratch/repro/harness.sh` | exit 0 | PASS |
| lib.sh has no syntax errors | `bash -n scratch/repro/lib.sh` | exit 0 | PASS |
| Dispatcher recognizes all Phase-2 subcommands | `scratch/repro/harness.sh` (no args, prints Usage) | `probe-vaapi\|reference-vaapi\|run-iter-vaapi\|run-batch-vaapi\|cross-match-qsvencc` all present | PASS |
| `report_vaapi.csv` on-disk == `02-EVIDENCE.md` embedded copy | `diff` | identical content (0 semantic diff) | PASS |
| `crossmatch_qsvencc.txt` on-disk == `02-EVIDENCE.md` embedded copy | `diff` | identical | PASS |

Full harness re-run (actually re-executing a 3-way GPU-exclusive encode) is out of scope for verification (requires exclusive GPU access, hours of runtime for the full cross-match) and was correctly not re-run by 02-05 either (all four source files confirmed present/current/consistent — see 02-05-SUMMARY.md "Reconciliation note").

### Probe Execution

No `scripts/*/tests/probe-*.sh` convention applies to this project/phase; the "probe" terminology here refers to the harness's own `probe-vaapi`/`probe` subcommands (D-02 capability discovery), which are covered above under Behavioral Spot-Checks and Key Link Verification, not the probe-execution convention this step targets. Step 7c: SKIPPED (no `scripts/*/tests/probe-*.sh`-convention probes declared or found).

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|---|---|---|---|---|
| DIAG-02 | 02-01, 02-02, 02-03, 02-04, 02-05 (all 5 plans) | Test the pure VA-API `av1_vaapi` encode path as an in-container triangulation data point under 3-way concurrency, with paired immune control. | SATISFIED | Full chain verified above: harness extended (02-01/02-02), detection-N=20 batch run with recorded result + explicit interpretation (02-03), cross-match closure attempt (02-04), durable git-tracked evidence (02-05). REQUIREMENTS.md traceability row already marks DIAG-02 "Complete — `02-EVIDENCE.md`" with a summary matching the actual recorded content. No orphaned Phase-2 requirement rows found in REQUIREMENTS.md. |

No orphaned requirements: REQUIREMENTS.md's traceability table maps exactly one requirement (DIAG-02) to Phase 2, and all 5 plans declare `requirements: [DIAG-02]` — full coverage, no unclaimed IDs.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---|---|---|---|
| `scratch/repro/harness.sh` | — | `TBD`/`FIXME`/`XXX`/`TODO`/`HACK`/`PLACEHOLDER`/"not yet implemented" scan | none found | grep returned zero matches across the entire file — no debt markers, no stub language. |
| `scratch/repro/harness.sh:1075` (`_ccm_cache_key`) | CR-01 (from `02-REVIEW.md`) | Cross-match candidate cache key collides between `runs/` (qsvencc) and `vaapi_runs/` (av1_vaapi) trees, and between `--smoke`/full scans | WARNING (secondary deliverable, non-blocking to phase goal) | Confirmed still present in the current `harness.sh` (fix from `02-REVIEW.md` not yet applied). Live effect confirmed in the actual recorded data: `crossmatch_qsvencc.txt`'s `it04-923` row shows "15 candidates scanned" vs 111-362 for every other row — a smoke-then-full cache collision degraded that one frame's cross-match completeness. **Assessed against the phase goal:** this affects only the D-09/D-10 cross-match sub-deliverable (mechanism-vs-symptom note for the *qsvencc* historical corrupt frames), not the primary av1_vaapi immunity/corruption finding (roadmap SC#1/SC#2), which comes entirely from `vaapi_probe.txt`/`report_vaapi.csv`/`summary_vaapi.txt` — files this cache bug does not touch. It also does not flip the "Mechanism-vs-symptom NOTE stays OPEN" aggregate conclusion: even with `it04-923`'s degraded 15-candidate scan, its best cross-scene PSNR (14.05 dB) is nowhere near the 35 dB confirmation threshold, and 16 of the other 16 corrupt frames were scanned against the full candidate set (111-362 candidates) and also stayed well below 35 dB. Already surfaced in `02-REVIEW.md` (status: `issues_found`) with a concrete fix; not re-blocked here per this verification's explicit instruction, but flagged for follow-up (backlog or a Phase 3+ fix-forward plan) since it is a real, live, unfixed measurement-integrity bug in a git-tracked instrument that later phases may reuse. |
| `scratch/repro/harness.sh` | WR-01..WR-06, IN-01..IN-05 | Six further warnings + five info items from `02-REVIEW.md` (n_actual over-count, unbounded ffprobe stages, fragile probe signals, etc.) | INFO | None of these affect the recorded DIAG-02 headline result (all confirmed by the reviewer to be robustness/audit-trail issues, not wrong-headline-number bugs). Not re-verified line-by-line here since `02-REVIEW.md` already did so at `standard` depth and none bears on SC#1/SC#2; listed for completeness. |

### Human Verification Required

None. This phase's deliverable is a static, git-tracked evidentiary record (harness code + measurement output + interpretive documentation), not a UI or externally-integrated runtime behavior. All must-haves were verifiable directly against on-disk artifacts and code. No `<verify><human-check>` blocks were found in any of the 5 plans' `auto` tasks.

### Gaps Summary

No blocking gaps. Both roadmap Success Criteria are verified with direct evidence: the av1_vaapi 3-way concurrent run executed through the (extended) Phase-1 harness with a paired av1_qsv control every iteration (0/20 control failures), and the result — 0/20 corrupt across all three scenes under a PARTIAL trigger triad — is recorded with an explicit, honest, non-overclaiming interpretation ("immunity NOT proven," per D-03) both in the harness's own `summary_vaapi.txt` output and in the durable git-tracked `02-EVIDENCE.md`. This is the correct outcome for an investigation phase: a clean-but-inconclusive result, recorded honestly, is a successful phase deliverable, not a failure to achieve the goal.

One non-blocking quality gap carries forward from `02-REVIEW.md` (CR-01, cross-match cache-key collision) — it degrades the completeness of one historical qsvencc cross-match row (`it04-923`, 15/full candidates) and remains latent for any future av1_vaapi corrupt-frame cross-match, but does not touch or invalidate the primary av1_vaapi immunity/corruption finding this phase's roadmap Success Criteria actually require. Recommend tracking CR-01 as backlog/follow-up work (fix suggested in `02-REVIEW.md` is concrete and small) rather than blocking phase progression on it.

A metadata anomaly was also noted (non-blocking): ROADMAP.md tags this phase `mode: mvp` but its goal text is not a valid User Story — likely a stale template default rather than an intentional instruction; recommend correcting for future automated verification runs.

---

*Verified: 2026-07-23T12:09:52Z*
*Verifier: Claude (gsd-verifier)*
