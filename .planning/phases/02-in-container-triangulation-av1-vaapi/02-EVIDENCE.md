# Phase 2 Durable Evidence Snapshot — av1_vaapi In-Container Triangulation (DIAG-02)

**Run date:** 2026-07-23
**Recorded by:** 02-05-PLAN.md, executed on the main working tree at `/workspaces/QSVEnc` — no worktree isolation (per this phase's explicit execution constraint, carried forward from Phase 1's worktree-cleanup data loss).

## Why this file exists

`scratch/repro/harness.sh` was extended across plans 02-01..02-04 with a full `av1_vaapi` measurement path (command builder, D-02 capability probe, determinism-confirmed self-reference, 3-way concurrent runner with paired `av1_qsv` control, interpretive batch summary, content-origin cross-match). But — exactly as in Phase 1 — the runtime outputs of that instrument (`vaapi_probe.txt`, `report_vaapi.csv`, `summary_vaapi.txt`, `crossmatch_qsvencc.txt`, and the per-iteration `vaapi_runs/`/`crossmatch_cache/` trees) live under the git-ignored `scratch/repro/` workdir. Phase 1 already lost one full baseline this way when a throwaway git worktree was removed. This phase runs on the main tree specifically to avoid a repeat, but the on-disk outputs are still git-ignored by convention (only `harness.sh`/`lib.sh` are tracked) and remain vulnerable to any future `scratch/` cleanup.

This file is the git-**tracked** durable backstop: it embeds the actual, verbatim, on-disk content of `vaapi_probe.txt`, `report_vaapi.csv`, `summary_vaapi.txt`, and `crossmatch_qsvencc.txt` as they existed at the time this plan ran (confirmed present, current, and internally consistent with the 02-02/02-03/02-04 summaries — file timestamps 09:27, 10:15, 10:41, 11:37 respectively, all on 2026-07-23, in the sequence the plans executed; no re-run was needed). The binary/per-iteration artifacts (`vaapi_runs/it01..it21/`, `crossmatch_cache/`, ~36 GB) remain on disk under `scratch/repro/` (git-ignored) for downstream phases to inspect directly; only the textual probe/report/summary/crossmatch outputs are duplicated here as the record of record for DIAG-02.

## Requirement → Artifact mapping

| Requirement | Satisfied by |
|---|---|
| DIAG-02 (av1_vaapi 3-way concurrent triangulation, paired control, explicit interpretation) | All sections below jointly satisfy this: `## vaapi_probe.txt` (D-02 triad legs — which trigger conditions av1_vaapi could actually reproduce), `## report_vaapi.csv` (the 3-way concurrent av1_vaapi result, 60 rows = 20 iterations × 3 scenes, `control_clean` column = the paired `av1_qsv` immune control), `## summary_vaapi.txt` (the recorded fraction/CI per hotspot + the explicit roadmap SC#2 interpretation + D-03 triad caveat + D-07/D-08 gated-escalation verdict), `## crossmatch_qsvencc.txt` (the closed-vs-open Mechanism-vs-symptom NOTE that Phase 1 explicitly deferred to this phase, D-09/D-10). |

## vaapi_probe.txt

Verbatim contents of `scratch/repro/vaapi_probe.txt` as produced by `scratch/repro/harness.sh probe-vaapi` on the main tree (02-01/02-02):

```
# av1_vaapi trigger-triad leg probe (D-02), scene 923, 100 frames
reorder: UNSUPPORTED
p010: ACTIVE
hw_decode: ACTIVE
triad: PARTIAL-TRIAD (immunity NOT proven for any UNSUPPORTED/UNKNOWN leg -- D-03)
```

## report_vaapi.csv

Verbatim contents of `scratch/repro/report_vaapi.csv` (header + all 60 data rows) as produced by `scratch/repro/harness.sh run-batch-vaapi 20` on the main tree (02-03):

```csv
iteration,scene,offset,status,psnr_db,corrupt,control_clean
01,923,299,OK,inf,0,1
01,928,96,OK,inf,0,1
01,1129,299,OK,inf,0,1
02,923,299,OK,inf,0,1
02,928,96,OK,inf,0,1
02,1129,299,OK,inf,0,1
03,923,299,OK,inf,0,1
03,928,96,OK,inf,0,1
03,1129,299,OK,inf,0,1
04,923,299,OK,inf,0,1
04,928,96,OK,inf,0,1
04,1129,299,OK,inf,0,1
05,923,299,OK,inf,0,1
05,928,96,OK,inf,0,1
05,1129,299,OK,inf,0,1
06,923,299,OK,inf,0,1
06,928,96,OK,inf,0,1
06,1129,299,OK,inf,0,1
07,923,299,OK,inf,0,1
07,928,96,OK,inf,0,1
07,1129,299,OK,inf,0,1
08,923,299,OK,inf,0,1
08,928,96,OK,inf,0,1
08,1129,299,OK,inf,0,1
09,923,299,OK,inf,0,1
09,928,96,OK,inf,0,1
09,1129,299,OK,inf,0,1
10,923,299,OK,inf,0,1
10,928,96,OK,inf,0,1
10,1129,299,OK,inf,0,1
11,923,299,OK,inf,0,1
11,928,96,OK,inf,0,1
11,1129,299,OK,inf,0,1
12,923,299,OK,inf,0,1
12,928,96,OK,inf,0,1
12,1129,299,OK,inf,0,1
13,923,299,OK,inf,0,1
13,928,96,OK,inf,0,1
13,1129,299,OK,inf,0,1
14,923,299,OK,inf,0,1
14,928,96,OK,inf,0,1
14,1129,299,OK,inf,0,1
15,923,299,OK,inf,0,1
15,928,96,OK,inf,0,1
15,1129,299,OK,inf,0,1
16,923,299,OK,inf,0,1
16,928,96,OK,inf,0,1
16,1129,299,OK,inf,0,1
17,923,299,OK,inf,0,1
17,928,96,OK,inf,0,1
17,1129,299,OK,inf,0,1
18,923,299,OK,inf,0,1
18,928,96,OK,inf,0,1
18,1129,299,OK,inf,0,1
19,923,299,OK,inf,0,1
19,928,96,OK,inf,0,1
19,1129,299,OK,inf,0,1
20,923,299,OK,inf,0,1
20,928,96,OK,inf,0,1
20,1129,299,OK,inf,0,1
```

Every row is `status=OK`, `corrupt=0`, `control_clean=1` — all 20 iterations × 3 scenes clean, paired control clean throughout.

## summary_vaapi.txt

Verbatim contents of `scratch/repro/summary_vaapi.txt` (the printed report from `print_batch_summary_vaapi`) as produced by the same `run-batch-vaapi 20` invocation, then regenerated (no batch re-run) in 02-04 to append the content-origin cross-match block:

```
==============================================================================
av1_vaapi concurrent-encode triangulation -- detection batch report (DIAG-02)
==============================================================================

N_requested: 20
N_actual:    20
  OK: 20  EXEC_FAILURE: 0  TIMEOUT: 0  MEASURE_FAILURE: 0  CONTROL_INVALID: 0
  (excluded from corruption-fraction denominator: 0)

-- Primary hotspot: scene 923 / offset 299 (vs av1_vaapi self-reference) --
  corruption fraction: 0/20 (0.0%)
  95% Wilson CI: [0.000, 0.161]
  no corrupt frames observed at this hotspot this batch

-- Confirmatory hotspot: scene 928 / offset 96 --
  corruption fraction: 0/20 (0.0%)

-- Confirmatory hotspot: scene 1129 / offset 299 --
  corruption fraction: 0/20 (0.0%)

-- Paired immune control (D-11) --
  ffmpeg av1_qsv control non-clean/invalidated iterations: 0/20
  (expected 0/20 -- a non-zero count here means the control itself was
   compromised for that iteration and it was excluded from the av1_vaapi finding)

-- av1_vaapi triad caveat (D-02/D-03) --
  reorder (B-frame leg):        UNSUPPORTED
  p010 (10-bit surfaces):       ACTIVE
  hw_decode (VA video-memory):  ACTIVE
  triad verdict: PARTIAL-TRIAD (immunity NOT proven for any UNSUPPORTED/UNKNOWN leg -- D-03)
  (reorder caveat is narrow: no display/decode reordering observed via PTS/DTS;
   this is NOT a claim of zero reference-surface-lifetime effect -- 02-RESEARCH.md Open Question #1)
  full_triad = False

-- Minimum-valid-iteration floor --
  valid iterations: 20/20 (floor: 17 = ceil(0.85 x 20))
  floor met -- detection power at nominal N

-- Gated escalation (D-07/D-08) --
  0/20 with PARTIAL/UNKNOWN triad -> do NOT escalate; 60 runs on a broken triad prove nothing
  report detection-grade PARTIAL-TRIAD only

-- Content-origin cross-match (D-09/D-10) --
  no av1_vaapi corrupt frame observed -> nothing to cross-match (cross-session-swap
  mechanism confirmation for av1_vaapi is N/A this batch)
  qsvencc baseline cross-match: see /workspaces/QSVEnc/scratch/repro/crossmatch_qsvencc.txt (both baselines' mechanism findings visible together, D-10)

-- Interpretation (roadmap SC#2) --
  av1_vaapi CLEAN but PARTIAL triad: immunity NOT proven (D-03) -- a clean result
  here does not confirm av1_vaapi is immune to the trigger triad, only that the
  legs that WERE reproducible did not corrupt under this concurrency.

-- Detection-N vs validation-N (D-07) --
  This batch is the DETECTION sample (N_requested=20), sized to observe
  whether av1_vaapi reproduces the documented corruption under 3-way concurrency.
  A larger ~60 zero-failure VALIDATION-N (rule-of-three) is defined but only run
  if the gated-escalation verdict above calls for it (D-08).
==============================================================================
```

## crossmatch_qsvencc.txt

Verbatim contents of `scratch/repro/crossmatch_qsvencc.txt` (the full historical qsvencc content-origin cross-match, all 17 Phase-1 corrupt frames scanned) as produced by `scratch/repro/harness.sh cross-match-qsvencc` on the main tree (02-04):

```
it04-923: vs_928=12.70 (scene 928 frame 0000 (15 candidates scanned)) vs_1129=14.05 (scene 1129 frame 0014 (15 candidates scanned)) failed_candidates=0 best_psnr=14.05 verdict=AMBIGUOUS ORIGIN (matches both concurrent scenes within 2 dB)
it07-923: vs_928=11.98 (scene 928 frame 0000 (111 candidates scanned)) vs_1129=14.99 (scene 1129 frame 0089 (362 candidates scanned)) failed_candidates=0 best_psnr=14.99 verdict=GENERIC GARBAGE (no cross-scene origin)
it08-923: vs_928=12.70 (scene 928 frame 0000 (111 candidates scanned)) vs_1129=15.08 (scene 1129 frame 0090 (362 candidates scanned)) failed_candidates=0 best_psnr=15.08 verdict=GENERIC GARBAGE (no cross-scene origin)
it10-923: vs_928=12.70 (scene 928 frame 0000 (111 candidates scanned)) vs_1129=15.08 (scene 1129 frame 0090 (362 candidates scanned)) failed_candidates=0 best_psnr=15.08 verdict=GENERIC GARBAGE (no cross-scene origin)
it11-923: vs_928=11.98 (scene 928 frame 0000 (111 candidates scanned)) vs_1129=14.99 (scene 1129 frame 0089 (362 candidates scanned)) failed_candidates=0 best_psnr=14.99 verdict=GENERIC GARBAGE (no cross-scene origin)
it12-923: vs_928=10.49 (scene 928 frame 0004 (111 candidates scanned)) vs_1129=11.96 (scene 1129 frame 0087 (362 candidates scanned)) failed_candidates=0 best_psnr=11.96 verdict=AMBIGUOUS ORIGIN (matches both concurrent scenes within 2 dB)
it14-923: vs_928=12.70 (scene 928 frame 0000 (111 candidates scanned)) vs_1129=15.08 (scene 1129 frame 0090 (362 candidates scanned)) failed_candidates=0 best_psnr=15.08 verdict=GENERIC GARBAGE (no cross-scene origin)
it15-923: vs_928=11.98 (scene 928 frame 0000 (111 candidates scanned)) vs_1129=14.99 (scene 1129 frame 0089 (362 candidates scanned)) failed_candidates=0 best_psnr=14.99 verdict=GENERIC GARBAGE (no cross-scene origin)
it17-923: vs_928=12.70 (scene 928 frame 0000 (111 candidates scanned)) vs_1129=15.08 (scene 1129 frame 0090 (362 candidates scanned)) failed_candidates=0 best_psnr=15.08 verdict=GENERIC GARBAGE (no cross-scene origin)
it05-1129: vs_923=18.57 (scene 923 frame 0187 (340 candidates scanned)) vs_928=12.92 (scene 928 frame 0091 (111 candidates scanned)) failed_candidates=0 best_psnr=18.57 verdict=GENERIC GARBAGE (no cross-scene origin)
it06-1129: vs_923=18.57 (scene 923 frame 0187 (340 candidates scanned)) vs_928=12.92 (scene 928 frame 0091 (111 candidates scanned)) failed_candidates=0 best_psnr=18.57 verdict=GENERIC GARBAGE (no cross-scene origin)
it09-1129: vs_923=18.57 (scene 923 frame 0187 (340 candidates scanned)) vs_928=12.92 (scene 928 frame 0091 (111 candidates scanned)) failed_candidates=0 best_psnr=18.57 verdict=GENERIC GARBAGE (no cross-scene origin)
it10-1129: vs_923=18.57 (scene 923 frame 0187 (340 candidates scanned)) vs_928=12.92 (scene 928 frame 0091 (111 candidates scanned)) failed_candidates=0 best_psnr=18.57 verdict=GENERIC GARBAGE (no cross-scene origin)
it12-1129: vs_923=18.57 (scene 923 frame 0187 (340 candidates scanned)) vs_928=12.92 (scene 928 frame 0091 (111 candidates scanned)) failed_candidates=0 best_psnr=18.57 verdict=GENERIC GARBAGE (no cross-scene origin)
it13-1129: vs_923=18.57 (scene 923 frame 0187 (340 candidates scanned)) vs_928=12.92 (scene 928 frame 0091 (111 candidates scanned)) failed_candidates=0 best_psnr=18.57 verdict=GENERIC GARBAGE (no cross-scene origin)
it14-1129: vs_923=18.57 (scene 923 frame 0187 (340 candidates scanned)) vs_928=12.92 (scene 928 frame 0091 (111 candidates scanned)) failed_candidates=0 best_psnr=18.57 verdict=GENERIC GARBAGE (no cross-scene origin)
it18-1129: vs_923=18.57 (scene 923 frame 0187 (340 candidates scanned)) vs_928=12.92 (scene 928 frame 0091 (111 candidates scanned)) failed_candidates=0 best_psnr=18.57 verdict=GENERIC GARBAGE (no cross-scene origin)

==============================================================================
AGGREGATE VERDICT (FULL): 17 corrupt frame(s) cross-matched
  confirmed cross-session content swap (>=35 dB): 0
  ambiguous origin (20-35 dB or within-2dB tie):  2
  generic garbage / no cross-scene origin (<20 dB): 15
  no valid candidates (fail-closed):               0
  -> Phase 1's deferred Mechanism-vs-symptom NOTE is NOT closed by this scan:
     no corrupt frame scored >=35 dB against a concurrent scene.
==============================================================================
```

Note: `report.csv` shows 9 corrupt iterations for scene 923 (it04,07,08,10,11,12,14,15,17), one more than the informal 8-item fallback list documented in earlier plan text — the fallback list is a stale/never-used contingency, not the actual driver of this scan; `report.csv` was read live and is the source of truth here (see 02-04-SUMMARY.md Task-2 note).

## Interpretation (roadmap SC#2)

Roadmap Phase 2 Success Criterion #2 requires the av1_vaapi clean-vs-corrupt result to be recorded "with its interpretation stated explicitly (e.g. clean strengthens the ffmpeg-migration case; corrupt too broadens the suspected fault beyond qsvencc's own pool code)." The actual recorded data drives which branch applies:

- **Which triad legs av1_vaapi reproduced** (`vaapi_probe.txt`): `p010: ACTIVE`, `hw_decode: ACTIVE`, `reorder: UNSUPPORTED` → **PARTIAL-TRIAD**. The Arc A380's AV1 low-power-only VAAPI entrypoint (`VAEntrypointEncSliceLP`, D-03's known constraint) does not reproduce B-frame reorder as PTS/DTS-observable behavior; the two other legs (10-bit P010 surfaces, HW-VA video-memory decode) were reproduced at full fidelity.
- **The clean-vs-corrupt av1_vaapi result at detection-N=20** (`report_vaapi.csv` / `summary_vaapi.txt`): 0/20 corrupt on all three scenes (923 primary hotspot, 928 and 1129 confirmatory hotspots), with the paired `av1_qsv` immune control clean 0/20 throughout (D-11 satisfied — the control itself was never compromised, so the 0/20 av1_vaapi result is not an artifact of a broken measurement).
- **The applicable interpretation branch, matching the REAL recorded data (not the hoped-for outcome):** because the result is 0/20 corrupt with only a **PARTIAL** triad (not the full triad), this is **NOT** the "clean-with-full-triad → strengthens the ffmpeg-migration case" branch. It is also not the "corrupt → broadens the suspected fault beyond qsvencc's oneVPL pool code" branch (0/20 is clean, not corrupt). The applicable branch is the third, partial-triad one: **a clean av1_vaapi result under only a PARTIAL triad means immunity NOT proven** — the result neither confirms nor strengthens the ffmpeg-migration case, because the highest-risk trigger leg (B-frame reorder) was never exercised. Per D-08, this is exactly the gate condition under which no N~60 validation escalation is warranted ("0/20 with PARTIAL/UNKNOWN triad → do NOT escalate; 60 runs on a broken triad prove nothing"), which is what actually happened (`summary_vaapi.txt`'s "Gated escalation (D-07/D-08)" block, verbatim above).
- Per D-03, "cannot exercise the trigger triad via av1_vaapi LP encode" is itself a valid, reportable DIAG-02 finding, not a failed measurement — it narrows the interpretive scope of every downstream conclusion drawn from this batch, and that narrowing is itself the deliverable.

## Triad-fidelity caveat (D-03)

**Immunity NOT proven.** The av1_vaapi 3-way concurrent detection-N=20 batch recorded 0/20 corrupt frames across all three scenes with a clean paired control, but the D-02 capability probe (`vaapi_probe.txt`) found only a **PARTIAL-TRIAD**: `p010: ACTIVE`, `hw_decode: ACTIVE`, `reorder: UNSUPPORTED`. Because the B-frame reorder leg — the highest-risk leg per D-02's own ordering and the central interpretive hazard flagged in 02-CONTEXT.md — could not be exercised at all, this clean result does **not** establish that av1_vaapi is immune to the documented trigger triad. It establishes only that the two legs which WERE reproducible (P010 10-bit surfaces + HW-VA video-memory decode) did not corrupt under this concurrency, at this N.

The reorder caveat is deliberately phrased **narrowly**: the probe observed no display/decode reordering via PTS/DTS inspection on this hardware's low-power-only AV1 VAAPI entrypoint. This is **not** a claim that reference-surface lifetime extension (the actual mechanism suspected to matter for the shared-VA-pool aliasing bug) has zero effect in the absence of PTS/DTS-visible reordering — that distinction is recorded as 02-RESEARCH.md's Open Question #1 and remains open. A future av1_vaapi test on hardware/driver combination that does expose a full-power (non-LP) AV1 VAAPI entrypoint with true B-frame/hierarchical-B reorder would be required to close this gap and earn a genuine "immune" claim under D-08's full-triad escalation branch.

## Triangulation vs Phase-1 baseline

Comparing this phase's av1_vaapi detection-N=20 result against the qsvencc baseline certified in `01-EVIDENCE.md`:

| Measurement | Scene 923 (primary) | Scene 928 (confirmatory) | Scene 1129 (confirmatory) | Paired control |
|---|---|---|---|---|
| **qsvencc baseline** (01-EVIDENCE.md, `01-02-PLAN.md` re-run) | 9/20 (45.0%), 95% CI [0.258, 0.658], mean 12.96 dB / stddev 0.18 dB | 0/20 (0.0%) | 8/20 (40.0%) | 0/20 |
| **av1_vaapi** (this phase, `report_vaapi.csv`/`summary_vaapi.txt`) | 0/20 (0.0%), 95% CI [0.000, 0.161] | 0/20 (0.0%) | 0/20 (0.0%) | 0/20 |

The qsvencc baseline (oneVPL-mediated, full triad reproduced — B-frame reorder, P010, HW-VA decode all active in Phase 1's harness) shows a strong, deterministic, stable-signature corruption rate on scenes 923 and 1129 (~40-45%), with 928 always clean. The av1_vaapi path (bypassing oneVPL, VA-API direct) shows 0% across all three scenes, but under a triad missing its highest-risk leg. **This combination does not by itself distinguish two competing explanations:** (a) av1_vaapi genuinely does not trigger the shared-VA-pool aliasing bug because it bypasses the oneVPL memory-pool code path implicated in the qsvencc corruption, or (b) av1_vaapi would also corrupt if it could reproduce true B-frame reorder, but this LP-only hardware/entrypoint combination never lets that leg fire. Both remain live hypotheses after this phase.

**Implication for Phases 3/4:** because immunity is NOT proven, Phase 3's host-side lever work (GuC/HuC firmware, i915→Xe) and Phase 4's workaround recommendation (Option C, ffmpeg migration) cannot yet cite this phase's result as confirmation that migrating off oneVPL/qsvencc to ffmpeg's `av1_vaapi` path would resolve the bug. The result is a genuinely informative negative-but-inconclusive data point: it rules out "av1_vaapi trivially and unconditionally reproduces the same ~40-45% corruption rate qsvencc does" (it does not, at 0/20 under a partial triad), but it does not rule in "av1_vaapi is a safe migration target" either, because the specific highest-risk trigger condition was never exercised. Phase 4 should treat this as "unresolved, requires either full-triad hardware/entrypoint access or acceptance of residual risk," not as a green light.

## Mechanism confirmation

- **qsvencc cross-session-swap verdict (Phase-1 deferred note, this phase's D-09/D-10 closure attempt):** all 17 of Phase 1's documented qsvencc corrupt frames were cross-matched against the two other concurrently-running scenes' same-iteration decoded frames (`crossmatch_qsvencc.txt`, full scan). Result: **0/17 confirmed cross-session content swaps** (≥35 dB), 2/17 low-confidence ties in the 20-35 dB ambiguous band (both under 15 dB on each side, tied within ~2 dB — not genuine partial matches), 15/17 generic garbage (<20 dB, best cross-scene PSNR 10.49-18.57 dB across all 17 frames). **Phase 1's Mechanism-vs-symptom NOTE therefore stays OPEN, not closed.** This scan rules out the simplest hypothesis — a clean whole-frame content swap from a concurrent same-iteration scene's own encoded output — without providing a positive alternative mechanism. Plausible untested alternatives (per 02-04-SUMMARY.md): sub-frame/reference-surface/tile-granularity aliasing rather than whole-frame swap; content from a different point in time within the same-iteration streams; or aliasing from stale VA surface contents not represented in any of the three scenes' own encoded output at all (e.g. an earlier iteration or process). This remains an explicit open item for any future mechanism-focused work.
- **av1_vaapi cross-match status:** N/A this batch. The av1_vaapi detection-N=20 run produced 0 corrupt frames, so there was nothing to cross-match — `summary_vaapi.txt`'s "Content-origin cross-match (D-09/D-10)" block explicitly states this and points to `crossmatch_qsvencc.txt` so both baselines' mechanism findings are visible together, per D-10's intent that the cross-match apply to both baselines even when one side has no corrupt frames of its own to test.

## Reconciliation note

No re-run was required for this plan: all four on-disk source files (`vaapi_probe.txt`, `report_vaapi.csv`, `summary_vaapi.txt`, `crossmatch_qsvencc.txt`) were confirmed present and current at plan-05 execution time, with timestamps (09:27, 10:15, 10:41, 11:37 on 2026-07-23) consistent with the sequence in which plans 02-01 through 02-04 actually ran, and with content matching the figures already transcribed in `02-01-SUMMARY.md`/`02-03-SUMMARY.md`/`02-04-SUMMARY.md`. This file's role is purely to give those git-ignored, already-correct on-disk outputs a durable git-tracked home, mirroring `01-EVIDENCE.md`'s role for the Phase-1 qsvencc baseline. The `scratch/repro/crossmatch_cache/` (~36 GB) and `scratch/repro/vaapi_runs/it01..it21/` trees remain on disk (git-ignored, preserved, not cleaned up) as the durable inputs backing the figures embedded here.

---
*Phase: 02-in-container-triangulation-av1-vaapi*
*Completed: 2026-07-23*
