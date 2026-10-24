---
phase: 03-host-side-levers-firmware-xe-migration
verified: 2026-10-24T18:00:00Z
status: passed
score: 10/10 must-haves verified
has_blocking_gaps: false
overrides_applied: 0
re_verification: false
gaps: []
minor_observations:
  - id: OBS-1
    severity: minor
    text: "CAP-XE row capability label still reads '(A380 currently bound to i915)'; the host cell and the Hardware change section state the B50/xe reality, so no silent assumption, only a stale row label."
  - id: OBS-2
    severity: minor
    text: "Plan acceptance criterion 'grep -F /proc/cmdline container_probe.txt' fails literally (BOOT_IMAGE hd6 -> hd5 after the host restart). Not a gap: current /proc/cmdline equals the host probe cmdline line; SUMMARY deviation 5 documents it."
human_verification: []
---

# Phase 3: Host-Side Levers — Firmware & Xe Migration Verification Report

**Phase Goal:** Empirically record which host-side changes are possible from this environment (kernel cmdline/modprobe, firmware, reboot, privilege level), so the deferred host-side experiments can be scoped honestly.
**Verified:** 2026-10-24
**Status:** passed
**Re-verification:** No, initial verification
**Requirement:** DIAG-01 (accounted for, see Requirements Coverage)

## Goal Achievement

### Observable Truths (ROADMAP success criteria + PLAN must_haves)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| SC1 | Host-side change capability empirically determined and recorded for cmdline/modprobe, firmware, reboot and privilege level, each reported honestly as available or blocked | VERIFIED | `03-EVIDENCE.md` `## Capability matrix (DIAG-01)` has all 13 CAP-* rows for container and host. CAP-PRIV, CAP-CMDLINE-OBS/-CHG, CAP-MODPROBE-OBS/-CHG, CAP-FW-OBS/-CHG and CAP-REBOOT each carry a D-04 term plus a quoted probe key or operator answer. Host -OBS cells quote values actually read (cmdline, `grubby_default`, `module_params`, `firmware_file_owner`, `guc_huc_debugfs`). Reboot is `blocked on host` and explicitly labelled an operator-declared policy, not a probe result. |
| SC2 | Deferred levers (GuC/HuC update, i915 -> Xe) listed with what they test and what they need from the host owner | VERIFIED | `03-RUNBOOK.md`: L1 and L2 each have Hypothesis, Prerequisites (root, restart window, console), Change, Confirmation, Measurement, Rollback and Emergency, with L2 also having Pre-assessment. There is a shared M1-M9 measurement procedure, an Encode-path gate and a 20-row command validation table. Commands that change state carry `untested — verify on first use`. |
| T1 | One tracked, strictly read-only probe, identical in container and host, with [user]/[root] labels and NEEDS_SUDO | VERIFIED | `tools/capability_probe.sh` is git-tracked, `bash -n` OK, ends with `END capability_probe`. Static gate: no forbidden commands (modprobe/reboot/systemctl/tee/...) and no mutating dnf/rpm/grubby verbs outside comments. dnf runs with a throw-away cache dir. `script_sha256` in the host output (`1dd50376...5d1c`) equals the sha256 of the committed script. |
| T2 | Container record is a real probe run, embedded verbatim | VERIFIED | The EVIDENCE container block (lines 162-278) is byte-identical to `scratch/host-levers/container_probe.txt` (diff empty). It shows `cap_sys_admin: NO`, uid_map mapped, `gpu_driver` i915 and `pci_drivers_present: i915=yes xe=yes`. The A380 wording describes the dated 2026-10-03 state, which the file states clearly. |
| T3 | Host record embedded verbatim except listed redactions, with operator answers quoted | VERIFIED | The EVIDENCE host block diffs against `host_probe.txt` only at lines 194-206 (13 dnf key-import lines replaced by one marked line), exactly the redaction recorded. The operator answers (a)-(d) are quoted in Russian. The user name is replaced by REDACTED-USER (operator-approved). |
| T4 | D-03 versions recorded (GuC, HuC with authentication status, DMC, packages, newer available) | VERIFIED | The D-03 table has GuC 70.60.0 RUNNING, HuC 8.2.10 RUNNING (the missing explicit "authenticated" log line is stated honestly), DMC v2.6, NEVRA 20260410-1.fc43, newer 20261019-1.fc43 offered, and the xe DG2 HuC declaration (none). Container values are `unknown` with reasons. |
| T5 | Matrix keeps observable vs changeable apart; no -CHG cell is `available` | VERIFIED | Task 3 verify (exact `grep -E '^\| *CAP-[A-Z]+-CHG'` check) passes. Host -CHG cells are `operator-declared (not tested)` quoting "Могу и вправе"; container -CHG cells are `blocked from container`. |
| T6 | Host user name / repo path never reaches git | VERIFIED | `git grep -qiwFf scratch/host-levers/.scan_terms -- .` gave rc=1 (no match, gate clean). The EVIDENCE file has no `/home/x`, UUID or MAC (Task 3/4 verify regexes pass). |
| T7 | RUNBOOK lets a later session run each lever without re-analysis, with encode-path gate against the baseline, stock-binary sha pin, one variable per reboot, paired control | VERIFIED | The sha `f4282c49...c3cbdb`, `i915.force_probe=!56a5 xe.force_probe=56a5`, the baseline file reference, 2 Rollback subsections and 20 untested markers are all present. The Standing rules list the paired control and the md5 oracle. |
| T8 | No host or container state changed; no lever command run | VERIFIED | Commits 667714de, b7c94b84, 7083d351, 3f602857 and ebccf5d7 touch only `.planning/**` (the probe, baseline, EVIDENCE, RUNBOOK, REQUIREMENTS, STATE, ROADMAP and SUMMARY). The probe passes the static no-mutation gate. The current `/proc/cmdline` equals the host probe's cmdline line. I ran no lever command. |
| H1 | Approved hardware change (A380/i915 -> B50/xe) is handled honestly, with no silent A380 assumption | VERIFIED | EVIDENCE has a dedicated section, `## Hardware change between the two probes`, and the Interpretation marks L1/L2 NOT APPLICABLE. The RUNBOOK has an applicability check requiring `0x56a5` and says the i915 baseline is valid only with the A380. Encode-path gate text says a new baseline must be captured on the B50 first. The remaining A380 mentions are conditional ("if reinstalled") or dated. |

**Score:** 10/10 truths verified (SC1, SC2, T1-T8, H1; T1-T8 are the plan truths and prohibitions).

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `tools/capability_probe.sh` | read-only probe, contains `END capability_probe` | VERIFIED | tracked, syntax OK, statically clean, hash matches the host run |
| `tools/encode_path_baseline_i915.txt` | i915 reference lines, `qsvencc_av1_ff: RC mode` | VERIFIED | tracked; the content is reproduced byte for byte in the EVIDENCE baseline section; declared A380-only |
| `03-EVIDENCE.md` | matrix, D-03, verbatim probes, answers, interpretation | VERIFIED | all required headings present, no pending marker (Task 3 verify exit 0) |
| `03-RUNBOOK.md` | levers, gate, measurement procedure | VERIFIED | all required sections present (Task 4 verify exit 0) |
| `.planning/REQUIREMENTS.md` | DIAG-01 pointer | VERIFIED | line 20 points to `03-EVIDENCE.md` and `03-RUNBOOK.md`; the traceability row says Complete |

### Key Link Verification

| From | To | Status | Details |
|------|----|--------|---------|
| probe stdout | EVIDENCE verbatim sections | WIRED | container block identical; host block identical except the recorded redaction |
| RUNBOOK gate | `tools/encode_path_baseline_i915.txt` | WIRED | referenced by full path in the gate `diff -u` step |
| RUNBOOK measurement | stock binary + cand tooling + md5 oracle | WIRED | sha pin, M1-M9 reference the 02.1 tools |
| EVIDENCE host column | host_probe keys / operator answers | WIRED | each cell cites a key or quotes an answer |

### Behavioral Spot-Checks / Automated Plan Verify

| Check | Result | Status |
|-------|--------|--------|
| Task 3 `<automated>` verify, run verbatim | exit 0 | PASS |
| Task 4 `<automated>` verify, run verbatim | exit 0 | PASS |
| Privacy gate `git grep -qiwFf scratch/host-levers/.scan_terms -- .` | rc=1, no match | PASS |
| `grep -F "$(cat /proc/cmdline)" container_probe.txt` (Task 4 acceptance) | rc=1 | Expected literal fail, NOT a gap (BOOT_IMAGE hd6 -> hd5 after the host restart; matches the host probe, rc=0; SUMMARY deviation 5) |
| Static no-mutation gate on the probe | pass | PASS |

Step 7b/7c: no application code or probe-declared PASS markers; the probe was not re-run (it would read host state, and the plan's checks were run instead).

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| DIAG-01 | 03-01 | Empirically determine and record host-side change capability (cmdline/modprobe, firmware, reboot, privilege) | SATISFIED | See SC1/SC2; REQUIREMENTS.md checkbox `[x]` and traceability Complete are backed by the artifacts |

No orphaned requirements: REQUIREMENTS.md maps only DIAG-01 to Phase 3 (DIAG-03/04/05 are v2 deferred).

### Anti-Patterns Found

No TBD/FIXME/XXX debt markers needed attention in the phase deliverables; they are Markdown and a shell probe. The `untested — verify on first use` markers are the intentional D-07 convention, not stubs.

### Observations (minor, non-blocking)

1. OBS-1: the CAP-XE capability label still names the A380 as the current binding. It is stale but explained in the host cell and the Hardware change section.
2. OBS-2: the Task 4 cmdline acceptance criterion is literally false. It is explained by the host restart and does not indicate a state change.
3. The operator-declared cells (-CHG, CAP-CONSOLE, CAP-REBOOT) are by design not machine-verifiable. They are labelled as such and never `available`. This is the honest outcome of D-04, not an open item.
4. The B50 swap makes L1/L2 moot for now. This is a scoping fact of the phase result, not a failure; the deliverable (honest record plus runbook) is complete.

### Human Verification Required

None. The operator already approved the hardware deviation, the redactions and the declared policies at the checkpoint.

### Gaps Summary

No gaps. Both ROADMAP success criteria are met on the real, dated facts (2026-10-03 container, 2026-10-24 host with the Arc Pro B50). The record is honest about what is blocked, operator-declared or unknown, and the privacy gate is clean.

---

_Verified: 2026-10-24_
_Verifier: Claude (bm-verifier)_
