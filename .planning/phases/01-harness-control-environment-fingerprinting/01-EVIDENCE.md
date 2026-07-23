# Phase 1 Durable Evidence Snapshot

**Run date:** 2026-07-23
**Recorded by:** 01-02-PLAN.md (gap-closure re-run), executed on the main working tree at `/workspaces/QSVEnc` — no worktree isolation.

## Why this file exists

`scratch/repro/harness.sh` + `lib.sh` are complete and hardened (CR-01 fail-open fix + all WR-01..WR-10 findings already committed). But their runtime outputs — `fingerprint.txt`, `reference/`, `control_reference/`, `report.csv`, `summary.txt` — live under the git-ignored `scratch/repro/` workdir (D-01/D-09). The first execution of this phase ran inside a throwaway git worktree; `git worktree remove` permanently deleted every one of those git-ignored outputs, leaving the N=20 baseline narrated in `01-01-SUMMARY.md` with no on-disk corroboration.

This file is the git-**tracked** durable backstop: it embeds the actual, verbatim, on-disk content of `fingerprint.txt`, `report.csv`, and `summary.txt` produced by the 01-02 re-run on the main tree, so the Phase 1 baseline survives regardless of how the git-ignored `scratch/repro/` workdir is later cleaned. The binary `.png`/`.obu` reference and per-iteration artifacts remain on disk under `scratch/repro/` (git-ignored) for downstream phases to inspect directly; only the textual fingerprint/report/summary are duplicated here as the record of record.

## Requirement → Artifact mapping

| Requirement | Satisfied by |
|---|---|
| REPRO-01 (environment fingerprint) | `## fingerprint.txt` section below — `kernel_matches_affected_host: YES`, graceful `UNAVAILABLE` degradation for the blocked GuC/HuC dmesg probe. |
| REPRO-02 (3-way concurrent qsvencc harness, isolated workdir) | `## report.csv` section below — 20 iterations × 3 scenes = 60 rows, all produced by `scratch/repro/runs/it01..it20/` + `control_runs/it01..it20/` on disk under `scratch/repro/` (never `/data`). |
| REPRO-03 (bit-clean reference + external-ffmpeg PSNR classification) | `scratch/repro/reference/frame299_ref.png` (on disk, git-ignored) generated the classification reference; `report.csv`'s `psnr_db`/`corrupt` columns below are the classification output. |
| REPRO-04 (paired av1_qsv immune control, confirmed clean 0/N) | `report.csv`'s `control_clean` column (all `1`) below + `summary.txt`'s "Paired immune control: 0/20" line below. |
| REPRO-05 (baseline corruption frequency + PSNR signature over detection-N, detection-N vs validation-N) | `## summary.txt` section below — raw `X/N_actual` + 95% Wilson CI per hotspot, `N_requested: 20` / `N_actual: 20`, detection-N vs validation-N statement. |

## fingerprint.txt

Verbatim contents of `scratch/repro/fingerprint.txt` as produced by `scratch/repro/harness.sh probe` on the main tree:

```
kernel: 6.19.14-200.fc43.x86_64
kernel_matches_affected_host: YES (affected host: 6.19.14-200.fc43.x86_64)
gpu_driver: /sys/bus/pci/drivers/i915
pci_id: 0x8086:0x56a5
vainfo: vainfo: Driver version: Intel iHD driver for Intel(R) Gen Graphics - 26.2.2 ()
guc_huc: UNAVAILABLE: dmesg blocked (no CAP_SYS_ADMIN in this container)
```

## report.csv

Verbatim contents of `scratch/repro/report.csv` (header + all 60 data rows) as produced by `scratch/repro/harness.sh run-batch 20` on the main tree:

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
04,923,299,OK,12.82,1,1
04,928,96,OK,inf,0,1
04,1129,299,OK,inf,0,1
05,923,299,OK,inf,0,1
05,928,96,OK,inf,0,1
05,1129,299,OK,22.29,1,1
06,923,299,OK,inf,0,1
06,928,96,OK,inf,0,1
06,1129,299,OK,22.29,1,1
07,923,299,OK,13.22,1,1
07,928,96,OK,inf,0,1
07,1129,299,OK,inf,0,1
08,923,299,OK,12.82,1,1
08,928,96,OK,inf,0,1
08,1129,299,OK,inf,0,1
09,923,299,OK,inf,0,1
09,928,96,OK,inf,0,1
09,1129,299,OK,22.29,1,1
10,923,299,OK,12.82,1,1
10,928,96,OK,inf,0,1
10,1129,299,OK,22.29,1,1
11,923,299,OK,13.22,1,1
11,928,96,OK,inf,0,1
11,1129,299,OK,inf,0,1
12,923,299,OK,12.91,1,1
12,928,96,OK,inf,0,1
12,1129,299,OK,22.29,1,1
13,923,299,OK,inf,0,1
13,928,96,OK,inf,0,1
13,1129,299,OK,22.29,1,1
14,923,299,OK,12.82,1,1
14,928,96,OK,inf,0,1
14,1129,299,OK,22.29,1,1
15,923,299,OK,13.22,1,1
15,928,96,OK,inf,0,1
15,1129,299,OK,inf,0,1
16,923,299,OK,inf,0,1
16,928,96,OK,inf,0,1
16,1129,299,OK,inf,0,1
17,923,299,OK,12.82,1,1
17,928,96,OK,inf,0,1
17,1129,299,OK,inf,0,1
18,923,299,OK,inf,0,1
18,928,96,OK,inf,0,1
18,1129,299,OK,22.29,1,1
19,923,299,OK,inf,0,1
19,928,96,OK,inf,0,1
19,1129,299,OK,inf,0,1
20,923,299,OK,inf,0,1
20,928,96,OK,inf,0,1
20,1129,299,OK,inf,0,1
```

## summary.txt

Verbatim contents of `scratch/repro/summary.txt` (the printed baseline from `print_batch_summary`) as produced by the same `run-batch 20` invocation:

```
==============================================================================
QSV concurrent-encode corruption -- baseline report
==============================================================================
fingerprint: /workspaces/QSVEnc/scratch/repro/fingerprint.txt (kernel_matches_affected_host: YES (affected host: 6.19.14-200.fc43.x86_64))

N_requested: 20
N_actual:    20
  OK: 20  EXEC_FAILURE: 0  TIMEOUT: 0  MEASURE_FAILURE: 0  CONTROL_INVALID: 0
  (excluded from corruption-fraction denominator: 0)

-- Primary hotspot: scene 923 / offset 299 --
  corruption fraction: 9/20 (45.0%)
  95% Wilson CI: [0.258, 0.658]
  observed corrupt-frame PSNR values (dB): [12.82, 13.22, 12.82, 12.82, 13.22, 12.91, 12.82, 13.22, 12.82]
  mean=12.96 dB, stddev=0.18 dB, signature_stable_across_iterations=True
  (informational only: the previously-documented handoff signature was ~15.74 dB;
   this environment's own deterministic value may differ -- see 01-RESEARCH.md)

-- Confirmatory hotspot: scene 928 / offset 96 --
  corruption fraction: 0/20 (0.0%)

-- Confirmatory hotspot: scene 1129 / offset 299 --
  corruption fraction: 8/20 (40.0%)

-- Paired immune control --
  ffmpeg av1_qsv control non-clean/invalidated iterations: 0/20
  (expected 0/20 -- a non-zero count here means the control itself was
   compromised for that iteration and it was excluded from the qsvencc finding)

-- Detection-N vs validation-N (D-07) --
  This batch is the DETECTION sample (N_requested=20), sized to observe
  whether the documented ~33-65% baseline recurs in this environment.
  A larger ~60 zero-failure VALIDATION-N (rule-of-three) is defined but RESERVED
  for later fix/clean claims -- it is NOT run in this phase.

-- Mechanism-vs-symptom NOTE --
  This baseline confirms reproduction by the PSNR-drop SYMPTOM (a hotspot frame
  scoring well below the 30 dB threshold, deterministically, under 3-way
  concurrency). Confirming that the corrupt frame's CONTENT actually originates
  from a concurrently-running session's scene (the documented cross-session
  aliasing mechanism) is DEFERRED to Phase 2 -- not established by this batch.
==============================================================================
```

## Reconciliation note

This re-run's numbers (923/299 **9/20, 45.0%**, 95% CI [0.258, 0.658], mean 12.96 dB / stddev 0.18 dB; 1129/299 **8/20, 40.0%**; 928/96 **0/20**; control **0/20**) supersede the unverified figures narrated in `01-01-SUMMARY.md` (923/299 6/20 30.0%, 1129/299 9/20 45.0%, ~12.84 dB) from the first (destroyed) execution. Both runs agree on: same kernel match, same threshold-only classifier behavior, same stable low-teens-dB corrupt-frame signature, same 928/96 always-clean, same 0/20 clean control. The specific per-iteration corruption counts differ run-to-run within the documented ~33-65% expected range — consistent with the harness's own detection-N (not validation-N) framing, not a harness defect. `01-01-SUMMARY.md` has been corrected in this same plan (01-02) to point here as the corroborated on-disk source of truth.
