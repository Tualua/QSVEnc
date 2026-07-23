---
phase: 01-harness-control-environment-fingerprinting
verified: 2026-07-23T05:11:18Z
status: gaps_found
score: 2/5 must-haves verified
has_blocking_gaps: true
overrides_applied: 0
gaps:
  - truth: "Environment fingerprint is recorded (uname -r, bound GPU driver, iHD/VA-API version, GuC/HuC firmware) with an explicit kernel-match statement"
    status: failed
    severity: blocking
    reason: "scratch/repro/fingerprint.txt does not exist anywhere in the working tree. The harness's own `probe` subcommand is functional (spot-check run during verification reproduced kernel_matches_affected_host: YES, iHD 26.2.2, guc_huc UNAVAILABLE, matching SUMMARY.md's narrative), but no recorded fingerprint artifact was left in the environment for downstream phases to reuse, as the phase goal literally requires (\"a recorded ... environment fingerprint ... exists in this environment\")."
    artifacts:
      - path: "scratch/repro/fingerprint.txt"
        issue: "Missing — required must-have artifact from PLAN frontmatter, not present on disk"
    missing:
      - "Run `scratch/repro/harness.sh probe` in this environment and leave fingerprint.txt in place (or otherwise persist it) so the recorded fingerprint actually exists for Phase 2-5 reuse."
  - truth: "A bit-clean single-session reference frame (scene 923, offset 299) exists"
    status: failed
    severity: blocking
    reason: "scratch/repro/reference/ does not exist at all (no directory, no frame299_ref.png, no chunk923_ref.obu). The `reference` subcommand was never left having run to completion in this environment (or its output was lost with a since-removed worktree). The plan's own must_haves.artifacts explicitly requires this path."
    artifacts:
      - path: "scratch/repro/reference/frame299_ref.png"
        issue: "Missing — directory scratch/repro/reference/ does not exist"
    missing:
      - "Run `scratch/repro/harness.sh reference` and confirm frame299_ref.png (and the md5-determinism/frame-count gate) actually persists in this environment."
  - truth: "Every qsvencc measurement in this phase has a paired ffmpeg av1_qsv immune-control run reported alongside it, confirmed clean (0/N)"
    status: failed
    severity: blocking
    reason: "scratch/repro/control_reference/ does not exist (no c923_ffref.obu), and no control_runs/ directory exists. There is zero artifact evidence in the codebase that any paired control was ever run and confirmed clean; the claim is sourced only from SUMMARY.md narrative."
    artifacts:
      - path: "scratch/repro/control_reference/c923_ffref.obu"
        issue: "Missing — directory scratch/repro/control_reference/ does not exist"
    missing:
      - "Regenerate the control reference and re-run the batch so control_clean results are backed by an on-disk report.csv."
  - truth: "Baseline corruption frequency and PSNR signature are reported over a detection-sized sample (N=20), with detection-N distinguished from validation-N"
    status: failed
    severity: blocking
    reason: "scratch/repro/report.csv and scratch/repro/summary.txt do not exist anywhere in the working tree — there is no persisted evidence of the N=20 baseline. This is corroborated by git history: the Task 3 commit (35f760fb, timestamped 04:48:40, the commit that actually implements run-batch) documents in its own message only 'Dry-run verified with N=2: pipeline runs end-to-end, correctly detects a corrupt frame at 12.82 dB ... report.csv/summary.txt both produced correctly' — it does NOT claim an N=20 run. The specific N=20 numbers (923/299 6/20 30.0% CI [0.145,0.519] stddev 0.03dB; 1129/299 9/20 45.0%; 928/96 clean; control 0/20) first appear only in the SUMMARY.md commit (7456aaf0, 10 minutes later) which contains no code/data, only the summary document itself. Per verification policy, SUMMARY.md claims are not evidence; absent any report.csv/summary.txt/runs/ artifacts, the detailed N=20 baseline cannot be confirmed to have actually been produced, and the one piece of hard evidence available (the Task 3 commit message) documents a different, smaller run (N=2)."
    artifacts:
      - path: "scratch/repro/report.csv"
        issue: "Missing — file does not exist; no runs/ or control_runs/ directories exist either"
      - path: "scratch/repro/summary.txt"
        issue: "Missing — file does not exist"
    missing:
      - "Actually run `scratch/repro/harness.sh run-batch 20` in this environment and leave report.csv + summary.txt on disk as the recorded baseline deliverable, OR persist the prior run's outputs (e.g. commit an evidence snapshot or copy them out of the worktree before it is discarded) so the claimed N=20/6-corrupt baseline is independently checkable."
deferred: []
human_verification: []
---

# Phase 1: Harness, Control & Environment Fingerprinting Verification Report

**Phase Goal:** A calibrated, control-validated reproduction harness exists in this environment, with a recorded baseline corruption signature and environment fingerprint — nothing downstream is interpretable without this.
**Verified:** 2026-07-23T05:11:18Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Environment fingerprint recorded with explicit kernel-match statement | ✗ FAILED | `scratch/repro/fingerprint.txt` absent from disk. `harness.sh probe` (source code) is correct and was confirmed functional by a live spot-check during this verification (reproduces kernel_matches_affected_host: YES, iHD 26.2.2, guc_huc UNAVAILABLE), but no recorded artifact exists in the repo as delivered. |
| 2 | 3-way concurrent qsvencc harness runs scenes 923/928/1129 with exact handoff seek/trim, writing only to isolated workdir | ✓ VERIFIED | Source-level: `cmd_run_iter` in `scratch/repro/harness.sh:299-421` launches 3 backgrounded `qsvencc --avhw --va` calls with the exact seek/trim table from `lib.sh:29-31` (matches PROJECT.md §4), captures each PID's exit code individually, and every output path is built from `$W` (hardcoded under `scratch/repro/`, `lib.sh:16`) — no path touches `/data` except the read-only `-i "$SRC"` input. `bash -n` syntax check passes. |
| 3 | Bit-clean single-session reference frame (923/299) exists; test frame classified corrupt via external-ffmpeg PSNR (<30dB) | ✗ FAILED | `scratch/repro/reference/frame299_ref.png` does not exist (directory itself absent). Classifier logic (`psnr_of`/`classify_corrupt`, harness.sh:255-278) exists and threshold-only (no hardcoded 15.74 equality), but see CR-01 below — it fails open to "clean" on an empty/missing PSNR value. |
| 4 | Every qsvencc measurement has a paired ffmpeg av1_qsv immune control, confirmed clean (0/N) | ✗ FAILED | `scratch/repro/control_reference/c923_ffref.obu` and any `control_runs/` output are absent. Sequential-after, separate-3-way control design is correctly implemented in source (`ctrl_encode`, `-profile:v main`, harness.sh:174-189, 372-406), but there is no on-disk evidence any control run actually completed and was recorded as clean. |
| 5 | Baseline corruption frequency + PSNR signature reported over detection-N=20, distinguished from validation-N | ✗ FAILED | `scratch/repro/report.csv` and `summary.txt` are absent. The only hard (git-committed, non-SUMMARY) evidence of an actual test run is the Task 3 commit message, which documents an **N=2 dry run**, not N=20. The specific N=20 statistics in SUMMARY.md (6/20, 9/20, stddev 0.03dB, CI [0.145,0.519]) have no corroborating artifact anywhere in the codebase. |

**Score:** 2/5 truths verified (1 fully verified at source level; environment-fingerprint truth given partial credit only for demonstrated code functionality, but still counted FAILED because the required artifact does not exist)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.gitignore` | scratch workdir ignored, harness source tracked | ✓ VERIFIED | `/scratch/*` + `!/scratch/repro/` + `/scratch/repro/*` + `!/scratch/repro/*.sh` — correctly scoped; `git ls-files scratch/` shows only `harness.sh`/`lib.sh` tracked. |
| `scratch/repro/harness.sh` | Standalone harness, self-documenting header, ≥140 lines | ✓ VERIFIED | 647 lines. Header documents purpose, PROJECT.md §4, D-01..D-09, subcommands, outputs, per-subcommand `set -e` policy. `bash -n` passes. No TBD/FIXME/XXX/TODO/HACK/PLACEHOLDER markers found. |
| `scratch/repro/lib.sh` | Shared config + helpers | ✓ VERIFIED | 91 lines. `gpu_clients`, `require_gpu_exclusive`, `run_encode`, `cleanup_gpu_procs` all present and match the plan's spec. |
| `scratch/repro/fingerprint.txt` | Fingerprint with kernel-match line, graceful degradation | ✗ MISSING | Not present on disk at verification time. |
| `scratch/repro/reference/frame299_ref.png` | Bit-clean reference frame | ✗ MISSING | `scratch/repro/reference/` directory does not exist. |
| `scratch/repro/control_reference/c923_ffref.obu` | Isolated ffmpeg control reference | ✗ MISSING | `scratch/repro/control_reference/` directory does not exist. |
| `scratch/repro/report.csv` | Per-iteration/per-scene corruption report | ✗ MISSING | Not present; `runs/` and `control_runs/` also absent. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `harness.sh` | `/usr/bin/qsvencc` | 3-way concurrent invocation, exact seek/trim | ✓ WIRED (source) | `harness.sh:120-126, 247-248, 308-316` — pattern `qsvencc --avhw --va .*--seek` present and matches PROJECT.md §4 seek/trim table verbatim. |
| `harness.sh` | `ffmpeg -lavfi psnr` | extract offset frame, parse `psnr_avg` | ✓ WIRED (source) | `harness.sh:259-264` — `psnr_of()` correctly extracts `psnr_avg:` field via awk. |
| `harness.sh` | `ffmpeg av1_qsv` immune control | paired, sequential-after, `-profile:v main` | ✓ WIRED (source) | `harness.sh:180-189, 372-406` — `ctrl_encode()` uses `-profile:v main` exactly, runs sequentially after the qsvencc measurement as a separate 3-way run per the design rationale documented in-code. |
| `report.csv` | `fingerprint.txt` | report tagged with fingerprint | ✓ WIRED (source) | `print_batch_summary()` (`harness.sh:432-556`) reads and prints the `kernel_matches_affected_host` line from `fingerprint.txt` into the summary header. |

All key-link wiring is sound **at the source level**. None of it can be confirmed to have actually executed end-to-end in this environment, because none of the runtime outputs it would produce exist on disk (see Required Artifacts / Gaps).

### Critical Measurement-Soundness Issue (from 01-REVIEW.md, unresolved)

**CR-01 — Failed/empty PSNR measurement is silently classified as CLEAN.** Confirmed still present in the current code:

```bash
# scratch/repro/harness.sh:271-278
classify_corrupt() {
  local p="$1"
  if [[ "$p" == "inf" || -z "$p" ]]; then
    echo 0            # <-- empty (measurement failure) => "clean"
  else
    awk -v p="$p" 'BEGIN { print (p+0 < 30) ? 1 : 0 }'
  fi
}
```

The frame-extraction ffmpeg call that feeds `psnr_of` (`harness.sh:366`) has no error/existence check on `$test_png`, so if a corrupted `.obu` (the single strongest possible corruption signal) causes frame extraction to fail outright, the row is still recorded `status=OK, corrupt=0` — the harness scores its own worst-case failure mode as "clean." This directly biases the corruption fraction **downward** and undermines the "calibrated, control-validated" claim in the phase goal — REPRO-03's classifier and REPRO-05's reported baseline are both affected. This is a genuine measurement-soundness defect, not merely a hardening nice-to-have, because it can silently mask the exact bug this instrument exists to detect. Given the review already scoped a concrete fix (guard `test_png` existence/non-empty, treat empty PSNR as `NA`/`MEASURE_FAILURE` rather than `0`), and given the phase goal explicitly promises a "control-validated" instrument, this is treated as a **blocking** follow-up item, not a cosmetic one. It does not, on its own, invalidate Truth #2 (the 3-way runner itself, which is correctly wired), but it does further weaken confidence in any already-claimed N=20 corruption-fraction numbers, compounding the missing-artifact gap above.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|---|---|---|---|---|
| REPRO-01 | 01-01-PLAN.md | Fingerprint environment, state kernel match | ✗ BLOCKED | Probe logic correct and spot-check-functional, but no `fingerprint.txt` artifact currently exists in the environment. |
| REPRO-02 | 01-01-PLAN.md | 3-way concurrent qsvencc harness, exact seek/trim, isolated workdir only | ✓ SATISFIED | Verified at source level — correctly implemented, no `/data` writes. |
| REPRO-03 | 01-01-PLAN.md | Bit-clean reference + PSNR corruption classifier (<30dB) | ✗ BLOCKED | Reference frame artifact missing; classifier has an unresolved fail-open bug (CR-01). |
| REPRO-04 | 01-01-PLAN.md | Paired ffmpeg av1_qsv immune control, confirmed clean 0/N | ✗ BLOCKED | Control-reference artifact missing; no report.csv to show 0/N. |
| REPRO-05 | 01-01-PLAN.md | Baseline corruption frequency + signature over detection-N, vs reserved validation-N | ✗ BLOCKED | report.csv/summary.txt missing; the only git-committed evidence of an actual run (Task 3 commit message) documents N=2, not the claimed N=20. |

**Note:** REQUIREMENTS.md currently marks all five of REPRO-01..05 as `[x]` Complete — this verification contradicts that status for REPRO-01, 03, 04, 05 based on the current, on-disk state of the environment.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---|---|---|---|
| `scratch/repro/harness.sh` | 271-278 | Fail-open error handling (CR-01, from 01-REVIEW.md) | 🛑 Blocker | Corruption-detection instrument silently scores extraction/measurement failures as "clean," biasing the very metric it exists to measure. |

No TBD/FIXME/XXX/TODO/HACK/PLACEHOLDER debt markers found in the two harness files.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| `harness.sh probe` produces a fingerprint with the required fields | `bash -n harness.sh && harness.sh probe` | Produced correct `fingerprint.txt` content live (kernel_matches_affected_host: YES, iHD 26.2.2, guc_huc UNAVAILABLE): matches SUMMARY.md's narrative for this field. File was removed again after the check to leave the tree in its pre-verification state. | ✓ PASS (code is functional) — but does not substitute for the missing deliverable artifact |
| `bash -n` syntax check on both files | `bash -n scratch/repro/harness.sh && bash -n scratch/repro/lib.sh` | No syntax errors | ✓ PASS |
| Full `run-batch 20` / `reference` / `run-iter` re-execution | not run | Skipped — real GPU 3-way concurrent encoding across 3 scenes with sequential paired controls takes multiple minutes and has real side effects (GPU-bound encode jobs); outside spot-check bounds (must be <10s, no side effects) | ? SKIP (see gaps above; this is exactly the missing evidence the gaps document) |

### Probe Execution

No `scripts/*/tests/probe-*.sh` convention or PLAN-declared probes found for this phase (bash-harness deliverable, not the probe-pattern migration/tooling type). Step 7c: SKIPPED (no applicable probes; this phase's own `harness.sh probe` subcommand is a different concept — a fingerprinting probe, not a verification probe — and was covered under Behavioral Spot-Checks above).

### Human Verification Required

None. All open items are resolvable by re-running the harness and persisting its output, or by fixing CR-01 in the classifier — neither requires subjective human judgment.

### Gaps Summary

The harness **source code** (`harness.sh` + `lib.sh`) is well-structured, matches the plan's design intent closely, and every key link (qsvencc invocation, PSNR classification, paired control, /data-safety) is correctly wired at the source level — Truth #2 (the 3-way concurrent runner) is genuinely verified.

However, the phase's actual deliverable — "a recorded baseline corruption signature and environment fingerprint" that **exists in this environment** so that "nothing downstream is interpretable without" it — is **not present**. None of `fingerprint.txt`, `reference/`, `control_reference/`, `runs/`, `control_runs/`, `report.csv`, or `summary.txt` exist anywhere in the current working tree; only the two git-tracked `.sh` source files are present. SUMMARY.md's detailed N=20 baseline narrative (923/299 6/20 30.0% CI [0.145,0.519], stable ~12.84dB; 1129/299 9/20 45.0%; 928/96 clean; control 0/20) has no corroborating artifact, and is directly contradicted by the Task 3 implementation commit's own message, which documents only an N=2 dry run as actually performed and verified at commit time.

Separately, 01-REVIEW.md's CR-01 finding (fail-open PSNR/frame-extraction-failure classification) remains unresolved in the current code and represents a genuine measurement-soundness defect that would bias any future corruption-fraction measurement downward — directly undermining the "control-validated" half of the phase goal.

Recommended path: re-run `scratch/repro/harness.sh probe`, `reference`, and `run-batch 20` in this environment and ensure the resulting `fingerprint.txt`/`reference/`/`control_reference/`/`report.csv`/`summary.txt` persist (not lost to worktree cleanup) as the actual phase-1 deliverable; and apply the CR-01 fix (treat missing/empty PSNR as `NA`/`MEASURE_FAILURE`, never `0`/clean) before certifying any baseline number derived from this instrument.

---

*Verified: 2026-07-23T05:11:18Z*
*Verifier: Claude (gsd-verifier)*
