---
phase: 03-host-side-levers-firmware-xe-migration
plan: 01
subsystem: infra
tags: [capability-probe, intel-gpu, guc-huc-firmware, xe, i915, fedora, runbook]

requires:
  - phase: 02.1-source-level-fix-qsvencc-surface-sync-lifetime
    provides: stock 8.31 binary archive, cand/d01 measurement tooling, verified application-level fix
provides:
  - read-only capability probe (container + host) with a strict output contract
  - DIAG-01 capability matrix for container and host, D-03 GuC/HuC/DMC and firmware package baseline
  - i915 encode-path reference lines (A380 only)
  - deferred-lever runbook (L1 GuC/HuC firmware, L2 i915 -> Xe) with gate, rollback, measurement procedure
affects: [v2 DIAG-03/04/05, phase-04 report]

tech-stack:
  added: []
  patterns:
    - "Observable vs changeable capability rows (-OBS / -CHG); a read-only probe never proves a change ability"
    - "Operator-run probe with script-hash check, git-ignored scan-term file and automated privacy gate before each commit"

key-files:
  created:
    - .planning/phases/03-host-side-levers-firmware-xe-migration/tools/capability_probe.sh
    - .planning/phases/03-host-side-levers-firmware-xe-migration/tools/encode_path_baseline_i915.txt
    - .planning/phases/03-host-side-levers-firmware-xe-migration/03-EVIDENCE.md
    - .planning/phases/03-host-side-levers-firmware-xe-migration/03-RUNBOOK.md
  modified:
    - .planning/REQUIREMENTS.md

key-decisions:
  - "The GPU in the machine was replaced between the container probe (Arc A380, i915) and the host probe (Arc Pro B50, xe); Phase 3 continued on the current facts and L1/L2 were marked not applicable to the current hardware."
  - "The operator's no-restart policy (answer (a)) is recorded as CAP-REBOOT = blocked on host (operator-declared policy, not a probe result) and blocks both deferred levers in practice."
  - "Change-ability rows stay operator-declared (not tested); no -CHG cell is ever available."

patterns-established:
  - "Evidence cells name the probe key and quote the decisive line; hardware-dependent baselines carry an explicit validity statement."

requirements-completed: [DIAG-01]

duration: not tracked (checkpoint-split execution 2026-10-03 and 2026-10-24)
completed: 2026-10-24
---

# Phase 3 Plan 01: Host-side capability record and deferred-lever runbook Summary

**A read-only capability probe run in the container and as root on the NAS produced a DIAG-01 matrix (13 capabilities, container and host), the host GuC 70.60.0 / HuC 8.2.10 / DMC v2.6 firmware baseline with a newer package on offer, and a runbook for the GuC/HuC-firmware and i915 -> Xe levers that are not applicable to the current Arc Pro B50 and are blocked by the operator's no-restart policy.**

## Performance

- **Started:** 2026-10-03 (Tasks 1-2, paused at the host-probe checkpoint)
- **Completed:** 2026-10-24 (Tasks 3-4 after the checkpoint was resolved)
- **Tasks:** 4 of 4 (Task 2 was the operator checkpoint)
- **Files:** 4 created, 1 modified (tracked)

## Accomplishments

- `tools/capability_probe.sh`: strictly read-only (static gates plus a `find -newer` write check in the container), identical bytes run in both places; host run confirmed by `script_sha256` match.
- `03-EVIDENCE.md`: capability matrix with exactly one D-04 term per cell, D-03 firmware/driver table, verbatim container and host probe outputs, operator answers, interpretation.
- `03-RUNBOOK.md`: Applicability, Standing rules, shared Measurement procedure (M1-M9), Encode-path gate, L1 and L2 (hypothesis, prerequisites, change, confirmation, measurement, rollback, emergency), command validation table (20 `untested — verify on first use` markers).
- `REQUIREMENTS.md`: DIAG-01 line points to the evidence and runbook.

Host findings (all from `scratch/host-levers/host_probe.txt`, quoted in 03-EVIDENCE.md): real root with all four capabilities; xe 0000:19:00.0 `8086:e212`; GuC `xe/bmg_guc_70.bin` 70.60.0 RUNNING on GT0 and GT1; HuC `xe/bmg_huc.bin` 8.2.10 RUNNING on GT1 (no explicit authentication line in the kernel log); DMC `i915/bmg_dmc.bin` v2.6; firmware packages 20260410-1.fc43 with 20261019-1.fc43 offered; `modinfo_fw_dg2_xe` declares no DG2 HuC file.

## Task Commits

1. **Task 1: probe, container run, container column, i915 baseline** - `667714de` (feat), `b7c94b84` (fix: modprobe.d scan matches blacklist/options lines)
2. **Task 2: operator checkpoint** - no commit; outputs under git-ignored `scratch/host-levers/` (host_probe.txt, operator_answers.txt, .scan_terms)
3. **Task 3: host column, D-03 baseline, interpretation** - `7083d351` (feat)
4. **Task 4: runbook and DIAG-01 pointer** - `3f602857` (feat)

## Deviations from Plan

### Auto-fixed / recorded Issues

**1. [Deviation - hardware changed] A380 on i915 replaced by Arc Pro B50 on xe**
- **Found during:** Task 2 checkpoint review of the host probe
- **Planned:** both probes describe the A380 (`8086:56a5`) on i915; L1/L2 are the deferred levers for it
- **Actual:** the host has `8086:e212` (operator: "A380 сменен на B50") on xe with `bmg_*` firmware; `gpu_driver: NONE`, `pci_drivers_present: i915=no xe=yes`; the host restarted between the probes (BOOT_IMAGE `(hd6,gpt2)` -> `(hd5,gpt2)`). The dev container now sees the same device.
- **Handling:** operator chose to continue on the current facts (verbatim "ОК"). The container column is kept as recorded on 2026-10-03 (dated); the container probe was not re-run. L1 and L2 are marked NOT APPLICABLE to the current hardware and kept in the runbook for an A380 reinstall; the runbook's applicability check requires `0x56a5` to be present. The i915 encode-path baseline file is unchanged and declared valid only with the A380 on i915; the runbook gate states a new baseline must be captured on the B50 first. The plan's CAP-XE truth ("A380 bound to i915 with xe registered") describes the 2026-10-03 container state only.
- **Cost if wrong:** if the A380 is still expected in this machine, the "not applicable" labels are premature and the baseline gate would block measurements until the card is back; low, the runbook content for L1/L2 is complete either way.
- **Files modified:** 03-EVIDENCE.md, 03-RUNBOOK.md
- **Commits:** 7083d351, 3f602857

**2. [Deviation - operator-requested redaction] 13 dnf key-import lines cut from the EVIDENCE copy**
- **Found during:** Task 3 privacy review
- **Issue:** `host_probe.txt` lines 194-206 are dnf OpenPGP key-import prompts for third-party repositories (URLs, fingerprints, a vendor support e-mail); operator: "Вырежи".
- **Fix:** replaced by one marked line in the EVIDENCE copy; lines 207-209 (available upgrades) kept; `host_probe.txt` untouched. Second redaction: the host user name in operator answer (c) -> `REDACTED-USER` (scan-term hit). Recorded as `executor redactions: 2`. The probe's own filter had already replaced one UUID.
- **Cost if wrong:** the verbatim copy is not byte-identical to the host file at those lines; the original stays in `scratch/host-levers/host_probe.txt` while it exists.
- **Files modified:** 03-EVIDENCE.md
- **Commit:** 7083d351

**3. [Deviation - policy] Restart not allowed; CAP-REBOOT and the levers**
- **Found during:** Task 2 answers
- **Issue:** answer (a) "Нет." blocks any restart; the plan expected a restart window to be negotiable.
- **Handling:** CAP-REBOOT = `blocked on host`, stated as an operator-declared policy, not a probe result; the Interpretation states that this blocks both levers regardless of answer (d) "Могу и вправе", and that both are moot on the B50 anyway. CAP-CMDLINE-CHG, CAP-MODPROBE-CHG, CAP-FW-CHG, CAP-CONSOLE are `operator-declared (not tested)`.
- **Cost if wrong:** if the policy changes, the cells are stale; they quote the answer and date.
- **Commit:** 7083d351

**4. [Deviation - plan assumption] CAP-ENCODE host cell**
- **Planned:** `n/a` on the host (encode runs in the container)
- **Actual:** `available`, following the checkpoint review: the host probe printed a real AV1 entrypoint list and FF block (host-installed qsvencc 8.18, `VAEntrypointEncSlice`), explicitly marked as not matching the i915 baseline.
- **Cost if wrong:** low, evidence cell states the limits.

**5. [Verification note] Task 4 acceptance check on the host cmdline**
- The criterion `grep -F "$(cat /proc/cmdline)" container_probe.txt` fails literally because of the host restart (BOOT_IMAGE differs); the current `/proc/cmdline` equals the host probe's cmdline line exactly, and no cmdline change was made by this phase.

**6. [Attribution] commit trailer**
- Task 3 and Task 4 commits carry `Co-Authored-By: Claude Sonnet 5.5`, matching the harness attribution instruction, not the `Fable 5.1` name written in the orchestrator prompt. Task 3 was amended once before any push to correct this.

## Assumption Drift (advisory)

- **Found during:** Task 2/3. **Planned:** the host GPU is the A380 on i915 with xe registered (matrix CAP-XE, baseline gate, L1/L2 applicability). **Actual:** B50 on xe. **Why:** hardware replacement plus restart between 2026-10-03 and 2026-10-24. **Cost if wrong:** see deviation 1.

## Known Stubs

None.

## Issues Encountered

- During Task 3 assembly an anchor matched a substring inside the mapping table and corrupted the working copy of 03-EVIDENCE.md; it was restored from `HEAD` (`git show HEAD:file > file`, the Task 1 content) and re-assembled with line-start anchors before anything was staged.
- Not verified: the commands marked `untested — verify on first use` in the runbook (by design, D-07); the `cp -a` fallback and `d01-tools` comparison of runbook step M2 were not run (only `cand-tools` was compared and was identical); the GPU engine resets seen at ~09:04 UTC on 2026-10-24 are unexplained (operator: "Не знаю").

## Verification Results

- Task 2 automated verify (re-run before Task 3): exit 0.
- Task 3 automated verify: exit 0 (all 13 CAP rows present, no pending marker, no `-CHG` cell `available`, no home path/UUID/MAC, scan-term gate clean).
- Task 4 automated verify: all checks passed (sha256, force_probe args, baseline reference, sections, 20 untested markers, 2 Rollback subsections, DIAG-01 pointer, no home path/UUID, scan-term gate clean on tracked and staged content); the one failing acceptance criterion is deviation 5.
- Privacy gate `git grep -iwFf scratch/host-levers/.scan_terms` found nothing before each commit.
- No host or container state was changed in this plan: nothing installed, restarted or written under `/sys`; no lever command ran (D-07).

## Threat Flags

None.

## Self-Check: PASSED
