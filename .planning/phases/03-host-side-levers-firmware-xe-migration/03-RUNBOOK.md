# Phase 3 Runbook — deferred host-side levers (L1 GuC/HuC firmware update, L2 i915 -> Xe)

**Written:** 2026-10-24 by plan 03-01. Nothing in this file was executed in Phase 3.
**Evidence base:** `03-EVIDENCE.md` (capability matrix, D-03 baseline, verbatim probes, operator answers) and `tools/encode_path_baseline_i915.txt`.

Marker convention: every command that changes host state, or that the Phase 3 probe runs did not validate read-only, is followed by the exact marker `untested — verify on first use`.

## Purpose and status

The levers test one hypothesis only: that the root cause of the AV1 small-chroma corruption lies below the API (a timing window in the decode -> VPP -> encode hand-off, see 02.1-EVIDENCE.md, mechanism section) and therefore reacts to a different GuC/HuC firmware build (L1) or to a different kernel driver (L2). The application-level fix already exists (upstream commit 45003f15, verified on the Arc A380 in 02.1-EVIDENCE.md). The levers are useful only to support a report to Intel or the driver maintainers.

Status as of 2026-10-24:

- Nothing here was executed in Phase 3 (D-07). The phase only read system state.
- The machine no longer contains the A380. The GPU in slot 0000:19:00.0 is an Intel Arc Pro B50 (`8086:e212`), natively driven by `xe` with `bmg_*` firmware (03-EVIDENCE.md, "Hardware change between the two probes"). Levers L1 and L2 are **NOT APPLICABLE to the current hardware**; they are kept for the case the A380 (`8086:56a5`) is reinstalled.
- The operator's restart policy (answer (a): "Нет.") blocks both levers in practice even on the A380, because both need a restart.
- Results of an executed lever belong to the v2 requirements DIAG-03 (L1), DIAG-04 (L2) and DIAG-05 (one variable per reboot).

## Applicability on this host (from 03-EVIDENCE.md)

Check before anything else: the levers apply only when `8086:56a5` is present, i.e. the first command below prints a path (read-only, validated by the probe key `pci_id`). If it prints nothing, stop: L1 and L2 do not apply.

```
ls /sys/bus/pci/devices/0000:19:00.0/device && cat /sys/bus/pci/devices/0000:19:00.0/device
```

(the second line must read `0x56a5`).

| item | state at 2026-10-24 | EVIDENCE key |
|---|---|---|
| GPU | Arc Pro B50 `8086:e212` on xe, no A380 | `drm_cards`, `gpu_driver: NONE`, `pci_drivers_present: i915=no xe=yes` |
| newer firmware package | yes: `linux-firmware`, `intel-gpu-firmware`, `linux-firmware-whence` 20260410-1.fc43 -> 20261019-1.fc43 (`updates`); for the A380 this would replace the `dg2_*` files | `firmware_pkgs`, `firmware_upgrades` |
| owning package of the dg2 files | `intel-gpu-firmware-20260410-1.fc43.noarch` | `firmware_file_owner` |
| xe module and `force_probe` parameter | xe present and bound to the B50; `xe.force_probe` is empty; `modinfo_force_probe` lists the parameter for i915 and xe; i915 is not loaded | `module_params`, `modinfo_force_probe` |
| xe declares a DG2 HuC file | NO: `modinfo_fw_dg2_xe` lists only `i915/dg2_guc_70.bin` and `i915/dg2_dmc_ver2_08.bin` (i915 also lists `i915/dg2_huc_gsc.bin`) | `modinfo_fw_dg2_xe`, `modinfo_fw_dg2_i915` |
| privilege | the probe shell was real root with all of cap_sys_admin / cap_sys_module / cap_sys_boot / cap_syslog; the regular host user has no sudo and will not get it (answer (c)) | CAP-PRIV |
| change boot arguments | `operator-declared (not tested)`: "Могу и вправе" | CAP-CMDLINE-CHG |
| change module options | `operator-declared (not tested)`: "Могу и вправе" | CAP-MODPROBE-CHG |
| change firmware package | `operator-declared (not tested)`: "Могу и вправе" | CAP-FW-CHG |
| restart | `blocked on host`: operator policy "Нет." (not a probe result); every lever below needs it | CAP-REBOOT |
| console for rollback | `operator-declared (not tested)`: "Есть, но лучше избегать проблем, которые его потребуют" | CAP-CONSOLE |

The change abilities are shown exactly as recorded in 03-EVIDENCE.md and are never upgraded to "available" here: a lever starts only after the operator explicitly confirms the matching ability and a restart window.

## Standing rules

1. Exactly one changed variable per reboot cycle (DIAG-05, PITFALLS Pitfall 3). No kernel update, no package update outside the lever, no other host change pending.
2. A before batch in the state immediately preceding the change and an after batch after it.
3. The paired ffmpeg `av1_qsv` control inside every harness iteration must stay 0/N (PITFALLS Pitfall 4); anything else voids the batch.
4. Only the archived stock binary `scratch/bins/stock-8.31/qsvencc`, sha256 `f4282c494a1fe0565e568b7c35285d416a64b36265ffa93d5ffa362ec3c3cbdb`. A fixed build hides the bug and would make every lever look clean (D-06).
5. The harness stays unmodified (the pins are enforced by `cand_setup.sh`).
6. The md5 oracle runs on every batch, fail-closed: any `D` or `?` cell is a failure (harness PSNR is blind to the mid-stream drift mode).
7. Detection N=20, validation N=60 (rule of three).
8. The GPU is exclusive during measurements; main working tree, no worktree; never write under `/data`.

## Measurement procedure (shared by all levers)

Run from the repo root in the dev container.

- (M1) Assert the stock binary: `test "$(sha256sum < scratch/bins/stock-8.31/qsvencc | awk '{print $1}')" = f4282c494a1fe0565e568b7c35285d416a64b36265ffa93d5ffa362ec3c3cbdb` (validated in Phase 3, `qsvencc_bin_sha256`).
- (M2) `diff -r scratch/cand-tools .planning/phases/02.1-source-level-fix-qsvencc-surface-sync-lifetime/tools/cand-tools` and the same for `scratch/d01-tools` against `.../tools/d01-tools`; copy with `cp -a` if missing; stop if they differ. untested — verify on first use (the compare was clean on 2026-10-24 for cand-tools; the copy command was not run).
- (M3) On the host the operator stops other GPU users such as media servers (the container's `gpu_clients` cannot see host processes); in the container `source scratch/repro/lib.sh && gpu_clients` prints nothing (validated in 02.1).
- (M4) `scratch/cand-tools/cand_setup.sh ID scratch/bins/stock-8.31/qsvencc` with a fresh ID per batch: `cand-L1-before`, `cand-L1-after`, `cand-L1-after-v60`, `cand-L2-before`, `cand-L2-after`, `cand-L2-after-v60`; add a date suffix on repeats (validated in 02.1).
- (M5) Refresh the state record inside the cand dir with `./harness.sh probe` (replaces the copied 8.31/i915 fingerprint), and run the capability probe with `QSVENCC_BIN` pointing into the cand dir, output to `capability_probe.txt` (the probe is validated read-only in Phase 3).
- (M6) Detection batch inside the cand dir: `PATH="$PWD/bin:$PATH" ./harness.sh run-batch 20` (about 9 minutes; validated in 02.1).
- (M7) `scratch/d01-tools/d01_md5.sh scratch/cand-ID`: any `D` or `?` cell is a failure (validated in 02.1).
- (M8) Every `runs/it*/log*.txt` (ANSI stripped) must show the four trigger-path lines recorded in 03-EVIDENCE.md (`Media SDK ... FF, 1st(d) GPU`, `Output AV1(yuv420 10bit) main @ Level 4`, `Encode Mode ICQ`, `GopRefDist 6, B-pyramid: on`); otherwise the batch did not exercise the trigger and is void.
- (M9) Decision rules. The before batch must reproduce (at least one hot corrupt frame at 923/299 or 1129/299; zero in 20 at the baseline rate has probability about 1e-7); otherwise STOP, the environment no longer reproduces. A paired control other than 0/N voids the batch. An after batch with 0 hot corrupt frames and md5 all `S` goes to validation (fresh `ID-v60`, `run-batch 60`, md5): 0/60, 180/180 `S` and control 0/60 allow "the lever removes the symptom" (residual at most 5 %). Otherwise compare the fractions and Wilson CIs with the before batch and report "no measurable effect at detection-N" when they overlap.

## Encode-path gate (after every reboot, before any measurement)

The gate reference is `.planning/phases/03-host-side-levers-firmware-xe-migration/tools/encode_path_baseline_i915.txt`. **That baseline is valid ONLY with the Arc A380 installed and bound to i915.** On the Arc Pro B50 it does not match (`VAEntrypointEncSlice` instead of `VAEntrypointEncSliceLP`, different iHD, host qsvencc 8.18), so on the B50 no gate can pass until a new baseline has been captured: run the probe with the stock binary in a container that sees the B50 and store the five `[user]` key groups as a new tracked baseline file first. Do not edit or delete the i915 baseline file.

Steps (the diff step was validated in Phase 3 by comparing a fresh container probe with the baseline file; the host-side lines are validated read-only by the Phase 3 host probe):

1. (host, operator) the driver is the expected one: `readlink -f /sys/bus/pci/devices/0000:19:00.0/driver` (PCI address from 03-EVIDENCE.md), and `journalctl -k -b 0 -o cat | grep -iE '(i915|xe).*(guc|huc|dmc|gsc)'` shows GuC loaded and HuC authenticated or running, with the versions recorded. For L1 the versions must differ from the D-03 baseline, otherwise the change did not take effect.
2. (container) restart or reopen the dev container after the host restart, run the capability probe with `QSVENCC_BIN` set, output to `scratch/host-levers/gate-ID.txt`, then `grep -E '^\[user\] (vainfo|vainfo_av1|qsvencc_version|qsvencc_bin_sha256|qsvencc_av1_ff):' scratch/host-levers/gate-ID.txt | diff -u .planning/phases/03-host-side-levers-firmware-xe-migration/tools/encode_path_baseline_i915.txt -` must print nothing, and `render_node_driver` must show `renderD128` on the expected driver (the harness hardcodes `renderD128`).
3. (encode) `scratch/cand-tools/cand_bitexact.sh scratch/bins/stock-8.31/qsvencc scratch/bitexact-ID`: the logs show the four trigger-path lines, and the md5 results against the references (923 `ca77cc72b0cfa2cfd291f278ab62f278`, 928 `0c37720dd1886fceef86b45abe24d389`, 1129 `e0061679b2904499162081e5b0ef96ef`) are recorded; `BITEXACT` supports "same pipeline", `MISMATCH` is recorded and means the pipeline differs (validated in 02.1).

Any failed step: do not measure. Record "lever not measurable as a single variable: FAILED STEP" as a valid negative result (PITFALLS Pitfall 8) and roll back.

## Lever L1 — GuC/HuC firmware update

Applies only with the A380 installed. Not applicable on the current hardware.

### Hypothesis

The window lives in GuC scheduling or firmware below the API, so another GuC/HuC build changes the stock corruption rate.

### Prerequisites

- Root on the host (sudo is not available to the regular host user; the operator would act from a root shell). Restart window and console per the operator answers (a) and (b): the current policy is no restart, so L1 cannot start until the operator changes it.
- A newer package: `firmware_upgrades` showed `20261019-1.fc43`. If `firmware_upgrades` were `NONE`, the package route would not apply and the alternative is a chosen `dg2` GuC/HuC build from upstream linux-firmware placed in `/usr/lib/firmware/updates/i915/`, which takes precedence over `/usr/lib/firmware/i915/`, with the exact file and version recorded. untested — verify on first use
- `cand-L1-before` measured in the current state.

### Change

1. Backup: `sudo mkdir -p /root/fw-rollback-$(date +%F)` and `sudo cp -a /usr/lib/firmware/i915/dg2_* /root/fw-rollback-$(date +%F)/` (Fedora installs the files compressed, `.xz`, under `/lib/firmware/i915/`, which is `/usr/lib/firmware/i915/`). untested — verify on first use
2. `sudo dnf upgrade OWNER_PKG` with OWNER_PKG from `firmware_file_owner` (`intel-gpu-firmware`), that package only, never a kernel. untested — verify on first use
3. Initramfs check: `sudo lsinitrd /boot/initramfs-$(uname -r).img | grep -E 'i915|dg2'`. If i915 or dg2 firmware is inside, first `sudo cp -p /boot/initramfs-$(uname -r).img /boot/initramfs-$(uname -r).img.pre-fw` and then `sudo dracut --force --kver "$(uname -r)"`. untested — verify on first use
4. `sudo systemctl reboot`. untested — verify on first use

### Confirmation

The encode-path gate. For L1 the GuC/HuC versions must differ from the D-03 baseline.

### Measurement

`cand-L1-after`, then `cand-L1-after-v60` when eligible (M9).

### Rollback

`sudo dnf downgrade OWNER_PKG-PREV_EVR` when the previous EVR is still offered (`dnf list --showduplicates OWNER_PKG`), or `sudo dnf history undo ID` with ID from `dnf history list`; otherwise copy the backup into `/usr/lib/firmware/updates/i915/`. Restore the `.pre-fw` initramfs, or rebuild it if it had been rebuilt. Restart. Confirm the GuC/HuC versions are back to the D-03 baseline and that the gate diff is empty. untested — verify on first use

### Emergency

Boot the previous kernel entry, or select the `.pre-fw` initramfs, from the GRUB menu through the console.

## Lever L2 — i915 -> Xe (force_probe)

Applies only with the A380 installed. Not applicable on the current hardware (the B50 already runs on xe without any force_probe).

### Hypothesis

The window is i915-specific (GEM, context, scheduling), while xe uses a different BO/VM/exec-queue model with GuC-only submission.

### Pre-assessment

From `modinfo_fw_dg2_xe` (03-EVIDENCE.md): xe lists **no** dg2 HuC file (only `i915/dg2_guc_70.bin` and `i915/dg2_dmc_ver2_08.bin`). The AV1 low-power bitrate control (ICQ) depends on HuC, so it is expected to disappear under xe, the encode-path gate is expected to fail, and L2 would then yield "not measurable as a single variable on DG2", which is still worth recording. A live xe HuC load on DG2 can only be observed after the switch.

### Prerequisites

- Root on the host; a restart window (policy today: none); console access is required because a bad boot entry is fixed from the GRUB menu (answer (b): exists, to be avoided); `cand-L2-before` measured; no other host change pending; no kernel updates during the experiment.
- Rollback and Emergency below are read and understood before the change.

### Change

1. `sudo grubby --update-kernel=DEFAULT --args='i915.force_probe=!56a5 xe.force_probe=56a5'` — single quotes are required, because inside double quotes an interactive bash expands `!56a5` as history. untested — verify on first use
2. `sudo grubby --info=DEFAULT` shows the args only on the default entry, so older entries stay on i915 as a fallback (`grubby_default` was read by the Phase 3 probe; the update itself was not run).
3. `sudo systemctl reboot`. untested — verify on first use

The kernel command line is used instead of `/etc/modprobe.d` because cmdline parameters also apply inside the initramfs and need no rebuild.

### Confirmation

The encode-path gate with the expected driver `xe`.

### Measurement

`cand-L2-after`, then `cand-L2-after-v60` when eligible (M9).

### Rollback

1. `sudo grubby --update-kernel=DEFAULT --remove-args='i915.force_probe=!56a5 xe.force_probe=56a5'` untested — verify on first use
2. `sudo systemctl reboot` untested — verify on first use
3. Confirm `renderD128` is back on i915 and that the gate diff is empty.

### Emergency

In the GRUB menu through the console: press `e` on the default entry, delete the two parameters from the `linux` line, press Ctrl-X for a one-time boot (or pick an older kernel entry); then run the rollback command.

## Recording results

Each lever goes to the v2 phase EVIDENCE (DIAG-03/04/05) with the lever id, the exact command run, the date, the before/after capability probe outputs, the gate results, the cand dirs with summary, `report.csv` and md5 matrix, and the interpretation. Never "fixed" or "clean" from fewer than 60 clean iterations or with any md5 `D` cell.

## Command validation status

| command | purpose | status |
|---|---|---|
| `ls`/`cat` of `/sys/bus/pci/devices/0000:19:00.0/device` | applicability check (A380 present) | validated read-only by the Phase 3 probe runs (03-EVIDENCE.md, `pci_id`, `gpu_driver`) |
| `sha256sum < scratch/bins/stock-8.31/qsvencc` | assert the stock binary (M1) | validated read-only by the Phase 3 probe runs (03-EVIDENCE.md, `qsvencc_bin_sha256`) |
| `diff -r` of cand-tools and d01-tools against the tracked copies | tooling integrity (M2) | validated in Phase 02.1 (02.1-EVIDENCE.md); the `cp -a` fallback is `untested — verify on first use` |
| `source scratch/repro/lib.sh && gpu_clients` | GPU exclusivity (M3) | validated in Phase 02.1 (02.1-EVIDENCE.md) |
| `cand_setup.sh`, `harness.sh probe`, `harness.sh run-batch N`, `d01_md5.sh`, `cand_bitexact.sh`, `cand_screen.sh` | measurement (M4-M8) | validated in Phase 02.1 (02.1-EVIDENCE.md) |
| `capability_probe.sh` with `QSVENCC_BIN` | state record and gate input | validated read-only by the Phase 3 probe runs (03-EVIDENCE.md) |
| `readlink -f /sys/bus/pci/devices/0000:19:00.0/driver`; `journalctl -k -b 0 -o cat \| grep ...` | gate step 1 | validated read-only by the Phase 3 probe runs (`gpu_driver`, `guc_huc_journal`) |
| `diff -u tools/encode_path_baseline_i915.txt -` against the fresh probe lines | gate step 2 | validated in Phase 3 (identical container output at record time, A380 only) |
| `sudo mkdir -p /root/fw-rollback-$(date +%F)`, `sudo cp -a /usr/lib/firmware/i915/dg2_* ...` | L1 backup | `untested — verify on first use` |
| `sudo dnf upgrade OWNER_PKG` | L1 change | `untested — verify on first use` |
| `sudo lsinitrd ... \| grep`, `sudo cp -p ... .pre-fw`, `sudo dracut --force --kver` | L1 initramfs | `untested — verify on first use` |
| `sudo systemctl reboot` | restart | `untested — verify on first use` |
| `sudo dnf downgrade ...`, `sudo dnf history undo ID`, `dnf list --showduplicates`, `dnf history list` | L1 rollback | `untested — verify on first use` |
| `sudo grubby --update-kernel=DEFAULT --args=...` | L2 change | `untested — verify on first use` |
| `sudo grubby --update-kernel=DEFAULT --remove-args=...` | L2 rollback | `untested — verify on first use` |
| `sudo grubby --info=DEFAULT` | read the default entry | validated read-only by the Phase 3 probe runs (`grubby_default`, run as root; the host user has no sudo) |
