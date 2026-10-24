# Phase 3 Durable Evidence Snapshot — host-side capability (DIAG-01)

**Run date:** 2026-10-03 (container probe, i915 encode-path baseline); 2026-10-24 (host probe, operator answers)
**Recorded by:** 03-01-PLAN.md, executed on the main working tree at `/workspaces/QSVEnc` — no worktree isolation.

## Why this file exists

`scratch/` is git-ignored (`/scratch/*`), so the runtime outputs of this phase — `scratch/host-levers/container_probe.txt` now, `host_probe.txt` and `operator_answers.txt` from the host run — vanish with any cleanup of the workdir. This git-tracked file holds the verbatim probe outputs and the capability matrix derived from them, so the DIAG-01 record survives regardless of what happens to `scratch/`.

The probe (`tools/capability_probe.sh`) is strictly read-only (D-02). Nothing on the host or in the container was changed to produce this record (D-07): the container run was followed by a `find -newer` write check (last section), no lever command was run, nothing was installed and nothing was restarted.

## Requirement -> Artifact mapping

| Requirement / criterion | Satisfied by |
|---|---|
| DIAG-01 (determine and record host-side change capability honestly) | `## Capability matrix (DIAG-01)`, `## Firmware & driver versions (D-03 baseline)` and the verbatim probe outputs in this file |
| ROADMAP Phase 3 SC1 (capability determined and recorded, each available or blocked) | `## Capability matrix (DIAG-01)`: container column from `## Container-side probe`; host column from the operator run of the same committed script at the Task 2 checkpoint |
| ROADMAP Phase 3 SC2 (deferred levers listed, what they test, what they need from the host owner) | `03-RUNBOOK.md` (Task 4 of the same plan) |
| Lever gate input (i915 encode-path reference, D-05) | `## Encode-path baseline under i915` and `tools/encode_path_baseline_i915.txt` |

## Hardware change between the two probes

The container probe and the i915 encode-path baseline (2026-10-03) were recorded on an Intel Arc A380 (PCI `8086:56a5`, DG2) at PCI slot `0000:19:00.0`, bound to i915. The host probe (2026-10-24) finds no such device: `gpu_driver: NONE (no 8086:56a5 device under /sys/bus/pci/devices)`, `pci_drivers_present: i915=no xe=yes`, and the same slot now holds `8086:e212` (`drm_cards: card1 driver=xe 0x8086:0xe212`). Operator, verbatim: "A380 сменен на B50" — an Intel Arc Pro B50 (Battlemage / BMG, Xe2), natively driven by `xe`. The operator then chose to continue Phase 3 on the current facts and to record the replacement as a deviation (verbatim: "ОК").

Supporting observations:

- The host was restarted between the two probes: `BOOT_IMAGE=(hd6,gpt2)/vmlinuz-6.19.14-200.fc43.x86_64` in the container probe (2026-10-03) versus `BOOT_IMAGE=(hd5,gpt2)/vmlinuz-6.19.14-200.fc43.x86_64` in the host probe; the kernel version is unchanged. The kernel-log timestamps put the last boot roughly 4.5 days before the host probe.
- The dev container now sees the same device (read-only check on 2026-10-24: `card1 0x8086 0xe212 driver xe`; only `xe` is present under `/sys/bus/pci/drivers`). The container column of the matrix below is kept as recorded on 2026-10-03 (a real, dated probe output); it describes the A380 / i915 state, not the current one. The container probe was not re-run.
- Firmware actually loaded now is `xe/bmg_guc_70.bin`, `xe/bmg_huc.bin` and `i915/bmg_dmc.bin` (BMG files). The installed `dg2_*` files are present but unused.

Consequences recorded for the rest of this file and for the runbook: the deferred levers L1 (DG2 GuC/HuC firmware update) and L2 (i915 -> Xe via `force_probe`) are NOT APPLICABLE to the current hardware (the B50 is natively driven by xe and uses `bmg_*` firmware; there is no `8086:56a5` to force-probe). They stay in the runbook only for the case the A380 is reinstalled. `tools/encode_path_baseline_i915.txt` (A380, i915, `VAEntrypointEncSliceLP`, iHD 26.2.2 in the container, stock 8.31) no longer matches the running system and is valid only with the A380 on i915.

## Capability matrix (DIAG-01)

Status vocabulary (D-04), exactly one term per status cell: `available` | `blocked from container — requires host-owner action` | `blocked on host` | `unknown` | `operator-declared (not tested)` | `n/a`.

Rules (D-04: never infer a capability without evidence; D-07: nothing is changed to test it):

- Observable and changeable are kept apart. An `-OBS` cell (and a visibility row such as CAP-GUCHUC, CAP-XE, CAP-ENCODE) may be `available` when a probe line shows the value was actually read.
- A `-CHG` cell is never `available` from probe evidence: a read-only probe shows readability or existence, not the ability to change anything. It is `blocked ...` when a probe line shows the missing privilege (for example `cap_sys_admin: NO`, `cap_sys_module: NO`, `BLOCKED` in `module_params`), `operator-declared (not tested)` with a quoted operator answer, or `unknown`.
- A row that joins two facts is only as strong as its weaker part: when one part is not observable the row takes the weaker term and the evidence names both parts.
- Evidence cells name the probe key and quote the decisive value from the verbatim section below. The container sees the host kernel (cmdline, sysfs, module parameters, kernel log) but its own image filesystem: the `firmware`, `boot`, `packages` and `modprobe.d` lines of the container probe describe the image, not the host (`fs_scope`).
- The host columns are filled from the host probe (`## Host-side probe`) and the operator answers (`## Operator answers`) collected at the Task 2 checkpoint on 2026-10-24. The host GPU is not the one the container column was recorded on, see `## Hardware change between the two probes`.

| id | capability | container status | container evidence | host status | host evidence |
|---|---|---|---|---|---|
| CAP-PRIV | privilege level of the probing process | blocked from container — requires host-owner action | `run_as: uid=0 euid=0 userns=mapped sudo_invoked=no`; `uid_map: 0 1010 1` (container root is host uid 1010, not host root); `cap_sys_admin: NO`, `cap_sys_module: NO`, `cap_sys_boot: NO`, `cap_syslog: NO`; `sudo_noninteractive: n/a (running as root; uid 0 is mapped into a user namespace)` | available | `run_as: uid=0 euid=0 userns=identity sudo_invoked=yes SUDO_UID=0`; `uid_map: 0 0 4294967295`; `cap_sys_admin: YES`, `cap_sys_module: YES`, `cap_sys_boot: YES`, `cap_syslog: YES`; `sudo_noninteractive: n/a (running as root)`. The probe was started from a root shell. Operator answer (c): "У пользователя REDACTED-USER нет sudo и не будет" — the regular host user has no sudo; this cell records the privilege the probing process had, not a permission to change anything |
| CAP-CMDLINE-OBS | running kernel cmdline and persisted default boot entry readable | blocked from container — requires host-owner action | running cmdline IS readable: `cmdline: BOOT_IMAGE=(hd6,gpt2)/vmlinuz-6.19.14-200.fc43.x86_64 root=/dev/mapper/fedora_nas-root ro rd.lvm.lv=fedora_nas/root console=ttyS1,115200`, `cmdline_gpu_params: NONE`; persisted default entry is NOT: `grubby_default: UNAVAILABLE (grubby not installed)`, `boot_dir_entries: 0` | available | `cmdline: BOOT_IMAGE=(hd5,gpt2)/vmlinuz-6.19.14-200.fc43.x86_64 root=/dev/mapper/fedora_nas-root ro rd.lvm.lv=fedora_nas/root console=ttyS1,115200`, `cmdline_gpu_params: NONE`; persisted default entry read: `grubby_default: index=0`, `grubby_default: args="ro rd.lvm.lv=fedora_nas/root console=ttyS1,115200"`, `boot_mode: UEFI (/sys/firmware/efi present)`, `boot_dir_entries: 23` |
| CAP-CMDLINE-CHG | bootloader / kernel arguments can be changed | blocked from container — requires host-owner action | `cap_sys_admin: NO`, `cap_sys_boot: NO`, `userns=mapped`; the host bootloader entries are not visible (`boot_dir_entries: 0`, `grubby_default: UNAVAILABLE (grubby not installed)`) | operator-declared (not tested) | operator answer (d): "Могу и вправе" (default boot entry kernel arguments via grubby are among the items asked); supporting context only, not proof: CAP-PRIV root evidence and a readable `grubby_default` entry. Nothing was changed to test it. In practice unusable for a restart-dependent change because of answer (a), see CAP-REBOOT |
| CAP-MODPROBE-OBS | module parameters, modprobe.d and modinfo readable | blocked from container — requires host-owner action | `module_params: i915.force_probe=BLOCKED (cat: /sys/module/i915/parameters/force_probe: Permission denied)` and the same for `i915.enable_guc`, `i915.guc_firmware_path`, `i915.huc_firmware_path`, `i915.dmc_firmware_path`, `xe.force_probe`; `modinfo_force_probe: UNAVAILABLE (modinfo not installed)`; `modprobe_d_gpu: NONE` describes the container image only | available | `module_params: xe.force_probe=(empty)` (value actually read); `module_params: i915.force_probe=UNAVAILABLE (module i915 not loaded)` and the same for the other four i915 parameters (not a permission failure: the module is not loaded); `modinfo_force_probe: i915: force_probe:Force probe options for specified supported devices...` and `xe: force_probe:Force probe options for specified devices...`; `modprobe_d_gpu: NONE` (no i915/xe options, blacklist, install or softdep lines) |
| CAP-MODPROBE-CHG | module options or module load / unload can be changed | blocked from container — requires host-owner action | `cap_sys_module: NO`, `cap_sys_admin: NO`, `module_params: ... BLOCKED`, `sysfs_unbind_writable: NO (i915: NO, xe: NO)` | operator-declared (not tested) | operator answer (d): "Могу и вправе" (kernel-module options under /etc/modprobe.d are among the items asked); supporting context only: `cap_sys_module: YES`, `cap_sys_admin: YES` in the root probe shell, `modprobe_d_gpu: NONE`. No module was loaded or unloaded and no file was written to test it |
| CAP-FW-OBS | firmware files, owning package and loaded versions readable | blocked from container — requires host-owner action | `firmware_files_dg2: NONE` and `firmware_file_owner: UNAVAILABLE (rpm not installed)` (container image, not the host); loaded versions: `guc_huc: BLOCKED (dmesg: read kernel buffer failed: Operation not permitted)`, `guc_huc_debugfs: BLOCKED (/sys/kernel/debug/dri is not present: ...)`, `guc_huc_journal: NONE` | available | `firmware_files_dg2: -rw-r--r--. 1 root root 165828 2026-04-11 08:00 /lib/firmware/i915/dg2_guc_70.bin.xz` (7 dg2 files listed), `firmware_file_owner: ... owner=intel-gpu-firmware-20260410-1.fc43.noarch`; loaded versions read: `guc_huc_debugfs: 0000:19:00.0/gt0/uc/guc_info: found release version 70.60.0` and the HuC / DMC lines (see the D-03 table) |
| CAP-FW-CHG | firmware can be updated | blocked from container — requires host-owner action | `firmware_pkgs: UNAVAILABLE (rpm not installed)`, `firmware_upgrades: UNAVAILABLE (dnf not installed)`, `cap_sys_admin: NO`; the host kernel loads firmware from the host filesystem, not from the container image | operator-declared (not tested) | operator answer (d): "Могу и вправе" (the firmware package via dnf upgrade/downgrade is among the items asked); supporting context only: CAP-PRIV root evidence and `firmware_upgrades: intel-gpu-firmware.noarch 20261019-1.fc43 updates` (a newer package is offered; offering it does not prove the install would succeed). Nothing was installed. A package change takes effect on the GPU only after a restart, see CAP-REBOOT |
| CAP-REBOOT | host can be restarted | blocked from container — requires host-owner action | `reboot_capability: BLOCKED (no CAP_SYS_BOOT; a container cannot restart its host)`, `cap_sys_boot: NO` | blocked on host | operator answer (a): "Нет." — an operator-declared policy, NOT a probe result: `reboot_capability: not tested (operator-declared at checkpoint, D-02)`; `cap_sys_boot: YES` in the root probe shell shows the privilege exists but the operator does not allow a restart for the deferred experiments |
| CAP-CONSOLE | out-of-band console for rollback | unknown | not observable from the container; hints only, not proof: `cmdline` carries `console=ttyS1,115200`, `drm_cards: card1 driver=ast 0x1a03:0x2000` (a BMC-class VGA device is present) | operator-declared (not tested) | operator answer (b): "Есть, но лучше избегать проблем, которые его потребуют" (out-of-band console exists, to be avoided); hints only, not proof: `cmdline` carries `console=ttyS1,115200`, `drm_cards: card0 driver=ast 0x1a03:0x2000` (BMC-class VGA). Never exercised |
| CAP-GUCHUC | GuC / HuC / DMC firmware versions visible | blocked from container — requires host-owner action | `guc_huc: BLOCKED (dmesg: read kernel buffer failed: Operation not permitted)`, `guc_huc_debugfs: BLOCKED (/sys/kernel/debug/dri is not present: debugfs not mounted or not visible from this context)`, `guc_huc_journal: NONE` (no kernel messages visible) | available | `guc_huc_debugfs: 0000:19:00.0/gt1/uc/huc_info: found release version 8.2.10`, `... status: RUNNING`, `... HuC status: 0x00500001`; `guc_huc_debugfs: 0000:19:00.0/gt0/uc/guc_info: status: RUNNING`, `found release version 70.60.0`; `guc_huc_debugfs: 0000:19:00.0/i915_dmc_info: version: 2.6`; the kernel log (`guc_huc`, `guc_huc_journal`) agrees. Hardware is the Arc Pro B50 on xe (bmg_* firmware), not the A380 |
| CAP-XE | xe driver present in the running kernel (A380 currently bound to i915) | available | `pci_drivers_present: i915=yes xe=yes`; `gpu_driver: /sys/bus/pci/drivers/i915 (0000:19:00.0)`; `render_node_driver: renderD128 driver=i915`. Presence only: whether xe can drive the A380 is the L2 lever (force_probe) and was not tested(as recorded on 2026-10-03; on 2026-10-24 the container sees the Arc Pro B50 on xe instead, see Hardware change) | available | `pci_drivers_present: i915=no xe=yes`; `drm_cards: card1 driver=xe 0x8086:0xe212`; `render_node_driver: renderD128 driver=xe`. This is xe natively driving the Arc Pro B50 (see Hardware change). The row's original subject, xe driving the A380 via force_probe, was never observable on the host and no longer applies: `gpu_driver: NONE (no 8086:56a5 device under /sys/bus/pci/devices)` |
| CAP-BIND | driver bind / unbind through sysfs | blocked from container — requires host-owner action | `sysfs_unbind_writable: NO (i915: NO, xe: NO)`, `cap_sys_admin: NO` | available | `sysfs_unbind_writable: YES (i915: ABSENT, xe: YES)`: the xe unbind file is writable (`test -w`, visibility only; it was never written and an actual unbind was not tested); the i915 unbind file is absent because i915 is not loaded |
| CAP-ENCODE | AV1 low-power encode path visible (VAEntrypointEncSliceLP, ICQ in the FF block) | available | `vainfo_av1: VAProfileAV1Profile0 : VAEntrypointEncSliceLP`; `qsvencc_av1_ff: RC mode o o x x o x x o x x` with ICQ (8th column) `o`; reference lines in `tools/encode_path_baseline_i915.txt` | available | `vainfo: Intel iHD driver for Intel(R) Gen Graphics - 26.1.5 ()`; `vainfo_av1: VAProfileAV1Profile0 : VAEntrypointVLD` and `VAProfileAV1Profile0 : VAEntrypointEncSlice` (NOT `VAEntrypointEncSliceLP` as on the A380); `qsvencc_av1_ff: RC mode o o x x o x x o x x` with ICQ (8th column) `o`, from a host-installed `QSVEncC (x64) 8.18 (r4205)` (sha256 `c5f791d964c4e3a84aabe15e25fba8388396c2c2357e637cf7914a5bac2d12b3`), not the archived stock 8.31. Different GPU, different entrypoint, different binary: this does NOT match `tools/encode_path_baseline_i915.txt` |

## Firmware & driver versions (D-03 baseline)

Each value is a value or `unknown — reason` (D-03, D-04). The container cannot read the kernel log, the firmware packages or the module metadata, so the GuC / HuC / DMC and package rows are `unknown` on the container side (as of 2026-10-03, A380 / i915); the host column (2026-10-24, Arc Pro B50 / xe) carries the baseline. The two columns describe different GPUs, see `## Hardware change between the two probes`.

| item | container (2026-10-03) | host (2026-10-24) |
|---|---|---|
| GPU and driver in the machine | Arc A380 `0x8086:0x56a5`, driver i915 (`pci_id`, `gpu_driver`) | Arc Pro B50 `0x8086:0xe212` (operator: "A380 сменен на B50"), driver xe (`drm_cards`, `render_node_driver`) |
| kernel (kernel-wide, the same kernel on both sides) | `6.19.14-200.fc43.x86_64` (`kernel`; `kernel_matches_affected_host: YES`) | `6.19.14-200.fc43.x86_64` (`kernel`) |
| GuC firmware version (source order: `guc_huc_debugfs`, `guc_huc_journal`, `guc_huc`) | unknown — `guc_huc: BLOCKED` (dmesg), `guc_huc_debugfs: BLOCKED` (no debugfs), `guc_huc_journal: NONE` | `xe/bmg_guc_70.bin` release 70.60.0, compatibility 1.31.0, wanted 70.49.4, status RUNNING on GT0 and GT1; source `guc_huc_debugfs` (`guc_info`), confirmed by `guc_huc_journal`: `Using GuC firmware from xe/bmg_guc_70.bin version 70.60.0` |
| HuC firmware version and authentication status | unknown — same three sources, none readable | `xe/bmg_huc.bin` release 8.2.10, status RUNNING on GT1, `HuC status: 0x00500001`; GT0 reports `HuC firmware: (null)`, `status: N/A` (expected: the BMG media engines live on GT1). Source `guc_huc_debugfs` (`huc_info`), version also in `guc_huc_journal`. There is no explicit "HuC authenticated" line in the kernel log: authentication status is recorded as RUNNING per debugfs, no explicit authentication line in the kernel log |
| DMC firmware version | unknown — same three sources, none readable | `i915/bmg_dmc.bin` v2.6, `fw loaded: yes` (source `guc_huc_debugfs`, `i915_dmc_info: version: 2.6`; log: `Finished loading DMC firmware i915/bmg_dmc.bin (v2.6)`) |
| firmware package NEVRA(s) and owner of the dg2 files | unknown — `firmware_pkgs: UNAVAILABLE (rpm not installed)`, `firmware_file_owner: UNAVAILABLE (rpm not installed)`; the container image would not describe the host anyway | `linux-firmware-20260410-1.fc43.noarch`, `intel-gpu-firmware-20260410-1.fc43.noarch`, `linux-firmware-whence-20260410-1.fc43.noarch` (`firmware_pkgs`); all seven installed `dg2_*` files are owned by `intel-gpu-firmware-20260410-1.fc43.noarch` (`firmware_file_owner`) and are not loaded by the current hardware |
| newer firmware package available | unknown — `firmware_upgrades: UNAVAILABLE (dnf not installed)` | yes: `intel-gpu-firmware.noarch 20261019-1.fc43 updates`, `linux-firmware.noarch 20261019-1.fc43 updates`, `linux-firmware-whence.noarch 20261019-1.fc43 updates` (`firmware_upgrades`; 13 unrelated dnf key-import lines removed from the verbatim copy at operator request) |
| xe DG2 firmware declarations (does xe request a DG2 HuC file) | unknown — `modinfo_fw_dg2_xe: UNAVAILABLE (modinfo not installed)` | `modinfo_fw_dg2_xe` lists `i915/dg2_guc_70.bin` and `i915/dg2_dmc_ver2_08.bin` only — NO dg2 HuC file; `modinfo_fw_dg2_i915` additionally lists `i915/dg2_huc_gsc.bin` |
| iHD media driver | `Intel iHD driver for Intel(R) Gen Graphics - 26.2.2 ()` (`vainfo`) | `Intel iHD driver for Intel(R) Gen Graphics - 26.1.5 ()` (`vainfo`) |
| libva | VA-API 1.23, libva 2.23.0 (header line of a separate read-only `LIBVA_DRIVER_NAME=iHD vainfo` run, not part of the probe output) | `libva-2.22.0-6.fc43.x86_64` (`media_pkgs`) |
| host media packages (`media_pkgs`) | unknown — `media_pkgs: UNAVAILABLE (rpm not installed)` | `intel-media-driver-26.1.5-1.fc43`, `intel-vpl-gpu-rt-26.1.6-1.fc43`, `libvpl-2.16.0-1.fc43`, `libva-2.22.0-6.fc43`, `libva-utils-2.22.0-5.fc43`, `intel-mediasdk-23.2.2-8.fc43`, `mesa-va-drivers-25.3.6-3.fc43`, `igt-gpu-tools-2.4-1.fc43` |
| qsvencc used for the measurements (D-06) | `QSVEncC (x64) 8.31 (r4604) by rigaya, Oct  1 2026 07:28:26 (gcc 13.3.0/Linux)`; sha256 `f4282c494a1fe0565e568b7c35285d416a64b36265ffa93d5ffa362ec3c3cbdb` (`qsvencc_version`, `qsvencc_bin_sha256`) | n/a (encode runs in the container). A host-installed `QSVEncC (x64) 8.18 (r4205) by rigaya, Jun 27 2026 13:44:06 (gcc 14.3.1/Linux)` was found in PATH (sha256 `c5f791d964c4e3a84aabe15e25fba8388396c2c2357e637cf7914a5bac2d12b3`); it is not the stock binary and is not used for measurements |

## Encode-path baseline under i915 (reference for the lever gate)

This is the reference the runbook's encode-path gate diffs against after every restart and before any measurement (D-05): under i915 the A380 offers the AV1 low-power encode entrypoint, and ICQ (8th column of the `RC mode` row) is supported in the FF block. It was produced by the container probe below with the archived stock binary (D-06), and equals `tools/encode_path_baseline_i915.txt` byte for byte:

```
[user] vainfo: vainfo: Driver version: Intel iHD driver for Intel(R) Gen Graphics - 26.2.2 ()
[user] vainfo_av1: VAProfileAV1Profile0 : VAEntrypointVLD
[user] vainfo_av1: VAProfileAV1Profile0 : VAEntrypointEncSliceLP
[user] qsvencc_bin_sha256: f4282c494a1fe0565e568b7c35285d416a64b36265ffa93d5ffa362ec3c3cbdb
[user] qsvencc_version: QSVEncC (x64) 8.31 (r4604) by rigaya, Oct  1 2026 07:28:26 (gcc 13.3.0/Linux)
[user] qsvencc_av1_ff: Codec: AV1 FF
[user] qsvencc_av1_ff: CBR VBR AVBR QVBR CQP LA LAHRD ICQ LAICQ VCM
[user] qsvencc_av1_ff: RC mode o o x x o x x o x x
[user] qsvencc_av1_ff: 10bit depth o o x x o x x o x x
[user] qsvencc_av1_ff: Hyper Mode x x x x x x x x x x
[user] qsvencc_av1_ff: Interlace x x x x x x x x x x
[user] qsvencc_av1_ff: VUI info o o x x o x x o x x
[user] qsvencc_av1_ff: Trellis x x x x x x x x x x
[user] qsvencc_av1_ff: BFrame/GopRef o o x x o x x o x x
[user] qsvencc_av1_ff: Adaptive_I o o x x o x x o x x
[user] qsvencc_av1_ff: Adaptive_B o o x x o x x o x x
[user] qsvencc_av1_ff: WeightP x x x x x x x x x x
[user] qsvencc_av1_ff: WeightB x x x x x x x x x x
[user] qsvencc_av1_ff: FadeDetect x x x x x x x x x x
[user] qsvencc_av1_ff: B_Pyramid o o x x o x x o x x
[user] qsvencc_av1_ff: +ManyBframes o o x x o x x o x x
[user] qsvencc_av1_ff: PyramQPOffset x x x x o x x x x x
[user] qsvencc_av1_ff: TuneQuality o o x x o x x o x x
[user] qsvencc_av1_ff: ScenarioInfo o o x x o x x o x x
[user] qsvencc_av1_ff: MBBRC o o x x x x x o x x
[user] qsvencc_av1_ff: ExtBRC o o x x x x x o x x
[user] qsvencc_av1_ff: AdaptiveRef x x x x x x x x x x
[user] qsvencc_av1_ff: AdaptiveLTR o o x x o x x o x x
[user] qsvencc_av1_ff: AdaptiveCQM o o x x o x x o x x
[user] qsvencc_av1_ff: LA Quality x x x x x x x x x x
[user] qsvencc_av1_ff: QP Min/Max o o x x x x x o x x
[user] qsvencc_av1_ff: IntraRefresh x x x x x x x x x x
[user] qsvencc_av1_ff: No Deblock x x x x x x x x x x
[user] qsvencc_av1_ff: No GPB x x x x x x x x x x
[user] qsvencc_av1_ff: Windowed BRC x x x x x x x x x x
[user] qsvencc_av1_ff: PerMBQP(CQP) x x x x x x x x x x
[user] qsvencc_av1_ff: DirectBiasAdj x x x x x x x x x x
[user] qsvencc_av1_ff: MVCostScaling x x x x x x x x x x
[user] qsvencc_av1_ff: SAO x x x x x x x x x x
[user] qsvencc_av1_ff: Max CTU Size x x x x x x x x x x
[user] qsvencc_av1_ff: TSkip x x x x x x x x x x
[user] qsvencc_av1_ff: AI Enc Ctrl x x x x x x x x x x
[user] qsvencc_av1_ff: RepartCheck x x x x x x x x x x
[user] qsvencc_av1_ff: COP o o x x o x x o x x
[user] qsvencc_av1_ff: COP2 o o x x o x x o x x
[user] qsvencc_av1_ff: COP3 o o x x o x x o x x
[user] qsvencc_av1_ff: HEVC_PRM x x x x x x x x x x
[user] qsvencc_av1_ff: COP_VP8 x x x x x x x x x x
[user] qsvencc_av1_ff: VP9_PRM x x x x x x x x x x
[user] qsvencc_av1_ff: AV1BITSTREAM o o x x o x x o x x
[user] qsvencc_av1_ff: AV1RESOLUTION o o x x o x x o x x
[user] qsvencc_av1_ff: AV1TILE o o x x o x x o x x
[user] qsvencc_av1_ff: VIDEO_SIGNAL o o x x o x x o x x
[user] qsvencc_av1_ff: CHROMALOC x x x x x x x x x x
[user] qsvencc_av1_ff: TUNE_ENC_QUAL o o x x o x x o x x
[user] qsvencc_av1_ff: HYPER_MODE x x x x x x x x x x
[user] qsvencc_av1_ff: AI_ENC_CTRL x x x x x x x x x x
```

Trigger-path lines of an archived stock run (`scratch/cand-T0b-stock/runs/it01/log923.txt`, ANSI codes stripped with `sed 's/\x1b\[[0-9;]*m//g'`) — a measurement batch must show these four lines in every iteration log, otherwise it did not exercise the trigger path:

```
Media SDK      QuickSyncVideo API v2.16, FF, 1st(d) GPU
Output         AV1(yuv420 10bit) main @ Level 4
Encode Mode    ICQ (Intelligent Const. Quality)
GopRefDist     6, B-pyramid: on
```

Validity of this baseline (recorded 2026-10-24): it is valid ONLY with the Intel Arc A380 (`8086:56a5`) installed and bound to i915. The host probe of 2026-10-24 shows a different GPU (Arc Pro B50, `8086:e212`, xe): its `vainfo_av1` shows `VAEntrypointEncSlice` instead of `VAEntrypointEncSliceLP`, iHD is 26.1.5 on the host, and the host-installed qsvencc is 8.18 (r4205), not the stock 8.31. On the B50 a new baseline would have to be captured first (same probe, stock binary through `QSVENCC_BIN`, in a container that sees the B50) before any gate could use it. The file `tools/encode_path_baseline_i915.txt` is kept unchanged as the historical A380 reference.

Stock binary under test: `scratch/bins/stock-8.31/qsvencc`, sha256 `f4282c494a1fe0565e568b7c35285d416a64b36265ffa93d5ffa362ec3c3cbdb`.

## Container-side probe (verbatim, scratch/host-levers/container_probe.txt)

Produced by `QSVENCC_BIN=scratch/bins/stock-8.31/qsvencc bash .planning/phases/03-host-side-levers-firmware-xe-migration/tools/capability_probe.sh` in the dev container (GPU idle: `gpu_clients` printed nothing). `script_sha256` below is the hash of the committed script as executed.

```
probe_version: 1
script_sha256: 1dd503769f5af4a0af53e35eb4a22a6ddd9d6258aa4b748347144801a6d95d1c (evidence: sha256sum of the script file as executed, hash only)
context: container (evidence: /run/.containerenv present; uid_map is not the identity map)
run_as: uid=0 euid=0 userns=mapped sudo_invoked=no
== identity ==
[user] kernel: 6.19.14-200.fc43.x86_64
[user] kernel_matches_affected_host: YES (affected host: 6.19.14-200.fc43.x86_64)
[user] cmdline: BOOT_IMAGE=(hd6,gpt2)/vmlinuz-6.19.14-200.fc43.x86_64 root=/dev/mapper/fedora_nas-root ro rd.lvm.lv=fedora_nas/root console=ttyS1,115200
[user] cmdline_gpu_params: NONE
== privilege ==
[user] uid_map: 0 1010 1
[user] uid_map: 1 66191360 65536
[user] cap_effective: 0x00000000800405fb (capsh: cap_chown,cap_dac_override,cap_fowner,cap_fsetid,cap_kill,cap_setgid,cap_setuid,cap_setpcap,cap_net_bind_service,cap_sys_chroot,cap_setfcap)
[user] cap_sys_admin: NO
[user] cap_sys_module: NO
[user] cap_sys_boot: NO
[user] cap_syslog: NO
[user] privileged_groups: NONE
[user] sudo_noninteractive: n/a (running as root; uid 0 is mapped into a user namespace)
== gpu ==
[user] drm_cards: card1 driver=ast 0x1a03:0x2000
[user] drm_cards: card2 driver=i915 0x8086:0x56a5
[user] gpu_driver: /sys/bus/pci/drivers/i915 (0000:19:00.0)
[user] pci_id: 0x8086:0x56a5
[user] render_node_driver: renderD128 driver=i915
[user] pci_drivers_present: i915=yes xe=yes
[user] lspci: UNAVAILABLE (lspci not installed)
[user] sysfs_unbind_writable: NO (i915: NO, xe: NO)
[user] reboot_capability: BLOCKED (no CAP_SYS_BOOT; a container cannot restart its host)
== firmware ==
[user] fs_scope: the firmware, package, boot and modprobe.d sections describe the container image filesystem, not the filesystem the host kernel boots and loads firmware from; only kernel-wide state (cmdline, sysfs, kernel log) reflects the host
[user] dmesg_restrict: 1
[root] guc_huc: BLOCKED (dmesg: read kernel buffer failed: Operation not permitted)
[user] guc_huc_journal: NONE
[root] guc_huc_debugfs: BLOCKED (/sys/kernel/debug/dri is not present: debugfs not mounted or not visible from this context)
[root] module_params: i915.force_probe=BLOCKED (cat: /sys/module/i915/parameters/force_probe: Permission denied)
[root] module_params: i915.enable_guc=BLOCKED (cat: /sys/module/i915/parameters/enable_guc: Permission denied)
[root] module_params: i915.guc_firmware_path=BLOCKED (cat: /sys/module/i915/parameters/guc_firmware_path: Permission denied)
[root] module_params: i915.huc_firmware_path=BLOCKED (cat: /sys/module/i915/parameters/huc_firmware_path: Permission denied)
[root] module_params: i915.dmc_firmware_path=BLOCKED (cat: /sys/module/i915/parameters/dmc_firmware_path: Permission denied)
[root] module_params: xe.force_probe=BLOCKED (cat: /sys/module/xe/parameters/force_probe: Permission denied)
[user] modinfo_force_probe: UNAVAILABLE (modinfo not installed)
[user] modinfo_fw_dg2_i915: UNAVAILABLE (modinfo not installed)
[user] modinfo_fw_dg2_xe: UNAVAILABLE (modinfo not installed)
[user] modprobe_d_gpu: NONE
[user] firmware_files_dg2: NONE
[user] firmware_file_owner: UNAVAILABLE (rpm not installed)
== boot ==
[user] boot_mode: UNAVAILABLE (/sys/firmware is empty or hidden)
[user] boot_dir_entries: 0
[root] grubby_default: UNAVAILABLE (grubby not installed)
[root] grubby_default_kernel: UNAVAILABLE (grubby not installed)
[user] installed_kernels: UNAVAILABLE (rpm not installed)
== packages ==
[user] firmware_pkgs: UNAVAILABLE (rpm not installed)
[user] firmware_upgrades: UNAVAILABLE (dnf not installed)
[user] media_pkgs: UNAVAILABLE (rpm not installed)
== encode-path ==
[user] vainfo: vainfo: Driver version: Intel iHD driver for Intel(R) Gen Graphics - 26.2.2 ()
[user] vainfo_av1: VAProfileAV1Profile0 : VAEntrypointVLD
[user] vainfo_av1: VAProfileAV1Profile0 : VAEntrypointEncSliceLP
[user] qsvencc_bin_sha256: f4282c494a1fe0565e568b7c35285d416a64b36265ffa93d5ffa362ec3c3cbdb
[user] qsvencc_version: QSVEncC (x64) 8.31 (r4604) by rigaya, Oct  1 2026 07:28:26 (gcc 13.3.0/Linux)
[user] qsvencc_av1_ff: Codec: AV1 FF
[user] qsvencc_av1_ff: CBR VBR AVBR QVBR CQP LA LAHRD ICQ LAICQ VCM
[user] qsvencc_av1_ff: RC mode o o x x o x x o x x
[user] qsvencc_av1_ff: 10bit depth o o x x o x x o x x
[user] qsvencc_av1_ff: Hyper Mode x x x x x x x x x x
[user] qsvencc_av1_ff: Interlace x x x x x x x x x x
[user] qsvencc_av1_ff: VUI info o o x x o x x o x x
[user] qsvencc_av1_ff: Trellis x x x x x x x x x x
[user] qsvencc_av1_ff: BFrame/GopRef o o x x o x x o x x
[user] qsvencc_av1_ff: Adaptive_I o o x x o x x o x x
[user] qsvencc_av1_ff: Adaptive_B o o x x o x x o x x
[user] qsvencc_av1_ff: WeightP x x x x x x x x x x
[user] qsvencc_av1_ff: WeightB x x x x x x x x x x
[user] qsvencc_av1_ff: FadeDetect x x x x x x x x x x
[user] qsvencc_av1_ff: B_Pyramid o o x x o x x o x x
[user] qsvencc_av1_ff: +ManyBframes o o x x o x x o x x
[user] qsvencc_av1_ff: PyramQPOffset x x x x o x x x x x
[user] qsvencc_av1_ff: TuneQuality o o x x o x x o x x
[user] qsvencc_av1_ff: ScenarioInfo o o x x o x x o x x
[user] qsvencc_av1_ff: MBBRC o o x x x x x o x x
[user] qsvencc_av1_ff: ExtBRC o o x x x x x o x x
[user] qsvencc_av1_ff: AdaptiveRef x x x x x x x x x x
[user] qsvencc_av1_ff: AdaptiveLTR o o x x o x x o x x
[user] qsvencc_av1_ff: AdaptiveCQM o o x x o x x o x x
[user] qsvencc_av1_ff: LA Quality x x x x x x x x x x
[user] qsvencc_av1_ff: QP Min/Max o o x x x x x o x x
[user] qsvencc_av1_ff: IntraRefresh x x x x x x x x x x
[user] qsvencc_av1_ff: No Deblock x x x x x x x x x x
[user] qsvencc_av1_ff: No GPB x x x x x x x x x x
[user] qsvencc_av1_ff: Windowed BRC x x x x x x x x x x
[user] qsvencc_av1_ff: PerMBQP(CQP) x x x x x x x x x x
[user] qsvencc_av1_ff: DirectBiasAdj x x x x x x x x x x
[user] qsvencc_av1_ff: MVCostScaling x x x x x x x x x x
[user] qsvencc_av1_ff: SAO x x x x x x x x x x
[user] qsvencc_av1_ff: Max CTU Size x x x x x x x x x x
[user] qsvencc_av1_ff: TSkip x x x x x x x x x x
[user] qsvencc_av1_ff: AI Enc Ctrl x x x x x x x x x x
[user] qsvencc_av1_ff: RepartCheck x x x x x x x x x x
[user] qsvencc_av1_ff: COP o o x x o x x o x x
[user] qsvencc_av1_ff: COP2 o o x x o x x o x x
[user] qsvencc_av1_ff: COP3 o o x x o x x o x x
[user] qsvencc_av1_ff: HEVC_PRM x x x x x x x x x x
[user] qsvencc_av1_ff: COP_VP8 x x x x x x x x x x
[user] qsvencc_av1_ff: VP9_PRM x x x x x x x x x x
[user] qsvencc_av1_ff: AV1BITSTREAM o o x x o x x o x x
[user] qsvencc_av1_ff: AV1RESOLUTION o o x x o x x o x x
[user] qsvencc_av1_ff: AV1TILE o o x x o x x o x x
[user] qsvencc_av1_ff: VIDEO_SIGNAL o o x x o x x o x x
[user] qsvencc_av1_ff: CHROMALOC x x x x x x x x x x
[user] qsvencc_av1_ff: TUNE_ENC_QUAL o o x x o x x o x x
[user] qsvencc_av1_ff: HYPER_MODE x x x x x x x x x x
[user] qsvencc_av1_ff: AI_ENC_CTRL x x x x x x x x x x
redaction: uuid,mac,id32,home,hostname applied
END capability_probe
```

write-check: no files created or modified outside scratch/host-levers/

## Host-side probe (verbatim, scratch/host-levers/host_probe.txt)

Produced on 2026-10-24 by the operator on the NAS with the committed `tools/capability_probe.sh`, started from a root shell (`run_as: uid=0 euid=0 userns=identity sudo_invoked=yes SUDO_UID=0`) and redirected into `scratch/host-levers/host_probe.txt` (no CRLF conversion was needed).

Integrity (T-03-05):

- END marker: present, `END capability_probe` is the last line; `context: host` (evidence: no container marker file and identity uid_map).
- Script hash: `script_sha256` in the output equals the sha256 of the committed `tools/capability_probe.sh` (`1dd503769f5af4a0af53e35eb4a22a6ddd9d6258aa4b748347144801a6d95d1c`): match.
- Script-side redaction: one UUID in the `mei_lb ... bound 0000:19:00.0` kernel-log lines was replaced by `REDACTED-UUID` by the probe's own filter.
- executor redactions: 2 (1 operator-requested block of 13 dnf key-import lines; 1 user-name scan hit in operator answer (c)). The block is the `firmware_upgrades` text of `host_probe.txt` lines 194-206 (dnf OpenPGP key-import prompts for third-party repositories: URLs, key fingerprints, a vendor support e-mail address, "Is this ok [y/N]" prompts), replaced in the copy below by one marked line at operator request ("Вырежи"); lines 207-209 (the available upgrade versions) are kept. The scan hit is in the operator answers section. `host_probe.txt` itself is unedited.
- Privacy scan of `host_probe.txt`: no `/home/` path, UUID, MAC address or IPv4 address remained; the scan terms from the git-ignored scan-terms file found no hit in it.
- The `guc_huc_debugfs` block appears three times (`0000:19:00.0/`, `1/`, `128/`): they are the same device seen through its PCI-address, card-index and render-node debugfs directories. The text is kept as produced.
- Two kernel-log lines `Engine reset: engine_class=bcs, logical_mask: 0x1, guc_id=26` at uptime 363799 s and 363801 s are a blitter-engine GPU reset about 7.8 hours before the probe (about 09:04 UTC on 2026-10-24, derived from the uptime and the probe time). The operator does not know what was running (verbatim: "Не знаю"). Recorded as an unexplained observation on the B50; it is not tied to the A380 corruption investigation.

```
probe_version: 1
script_sha256: 1dd503769f5af4a0af53e35eb4a22a6ddd9d6258aa4b748347144801a6d95d1c (evidence: sha256sum of the script file as executed, hash only)
context: host (evidence: no container marker file and identity uid_map (userns=identity))
run_as: uid=0 euid=0 userns=identity sudo_invoked=yes SUDO_UID=0
== identity ==
[user] kernel: 6.19.14-200.fc43.x86_64
[user] kernel_matches_affected_host: YES (affected host: 6.19.14-200.fc43.x86_64)
[user] cmdline: BOOT_IMAGE=(hd5,gpt2)/vmlinuz-6.19.14-200.fc43.x86_64 root=/dev/mapper/fedora_nas-root ro rd.lvm.lv=fedora_nas/root console=ttyS1,115200
[user] cmdline_gpu_params: NONE
== privilege ==
[user] uid_map: 0 0 4294967295
[user] cap_effective: 0x000001ffffffffff (capsh: cap_chown,cap_dac_override,cap_dac_read_search,cap_fowner,cap_fsetid,cap_kill,cap_setgid,cap_setuid,cap_setpcap,cap_linux_immutable,cap_net_bind_service,cap_net_broadcast,cap_net_admin,cap_net_raw,cap_ipc_lock,cap_ipc_owner,cap_sys_module,cap_sys_rawio,cap_sys_chroot,cap_sys_ptrace,cap_sys_pacct,cap_sys_admin,cap_sys_boot,cap_sys_nice,cap_sys_resource,cap_sys_time,cap_sys_tty_config,cap_mknod,cap_lease,cap_audit_write,cap_audit_control,cap_setfcap,cap_mac_override,cap_mac_admin,cap_syslog,cap_wake_alarm,cap_block_suspend,cap_audit_read,cap_perfmon,cap_bpf,cap_checkpoint_restore)
[user] cap_sys_admin: YES
[user] cap_sys_module: YES
[user] cap_sys_boot: YES
[user] cap_syslog: YES
[user] privileged_groups: NONE
[user] sudo_noninteractive: n/a (running as root)
== gpu ==
[user] drm_cards: card0 driver=ast 0x1a03:0x2000
[user] drm_cards: card1 driver=xe 0x8086:0xe212
[user] gpu_driver: NONE (no 8086:56a5 device under /sys/bus/pci/devices)
[user] pci_id: NONE (no 8086:56a5 device under /sys/bus/pci/devices)
[user] render_node_driver: renderD128 driver=xe
[user] pci_drivers_present: i915=no xe=yes
[user] lspci: NONE
[user] sysfs_unbind_writable: YES (i915: ABSENT, xe: YES)
[user] reboot_capability: not tested (operator-declared at checkpoint, D-02)
== firmware ==
[user] dmesg_restrict: 1
[root] guc_huc: [   17.730654] xe 0000:19:00.0: [drm] Finished loading DMC firmware i915/bmg_dmc.bin (v2.6)
[root] guc_huc: [   17.740082] xe 0000:19:00.0: [drm] Tile0: GT0: Using GuC firmware from xe/bmg_guc_70.bin version 70.60.0
[root] guc_huc: [   17.952026] xe 0000:19:00.0: [drm] Tile0: GT1: Using GuC firmware from xe/bmg_guc_70.bin version 70.60.0
[root] guc_huc: [   17.971306] xe 0000:19:00.0: [drm] Tile0: GT1: Using HuC firmware from xe/bmg_huc.bin version 8.2.10
[root] guc_huc: [   18.073293] 0x000000001000-0x00000054e000 : "xe.nvm.6400.GSC"
[root] guc_huc: [   18.151172] mei_lb xe.mei-gscfi.6400-REDACTED-UUID: bound 0000:19:00.0 (ops xe_late_bind_component_ops [xe])
[root] guc_huc: [363799.646576] xe 0000:19:00.0: [drm] Tile0: GT0: Engine reset: engine_class=bcs, logical_mask: 0x1, guc_id=26
[root] guc_huc: [363801.182292] xe 0000:19:00.0: [drm] Tile0: GT0: Engine reset: engine_class=bcs, logical_mask: 0x1, guc_id=26
[user] guc_huc_journal: xe 0000:19:00.0: [drm] Finished loading DMC firmware i915/bmg_dmc.bin (v2.6)
[user] guc_huc_journal: xe 0000:19:00.0: [drm] Tile0: GT0: Using GuC firmware from xe/bmg_guc_70.bin version 70.60.0
[user] guc_huc_journal: xe 0000:19:00.0: [drm] Tile0: GT1: Using GuC firmware from xe/bmg_guc_70.bin version 70.60.0
[user] guc_huc_journal: xe 0000:19:00.0: [drm] Tile0: GT1: Using HuC firmware from xe/bmg_huc.bin version 8.2.10
[user] guc_huc_journal: 0x000000001000-0x00000054e000 : "xe.nvm.6400.GSC"
[user] guc_huc_journal: mei_lb xe.mei-gscfi.6400-REDACTED-UUID: bound 0000:19:00.0 (ops xe_late_bind_component_ops [xe])
[user] guc_huc_journal: xe 0000:19:00.0: [drm] Tile0: GT0: Engine reset: engine_class=bcs, logical_mask: 0x1, guc_id=26
[user] guc_huc_journal: xe 0000:19:00.0: [drm] Tile0: GT0: Engine reset: engine_class=bcs, logical_mask: 0x1, guc_id=26
[root] guc_huc_debugfs: 0000:19:00.0/gt0/uc/guc_info: GuC firmware: xe/bmg_guc_70.bin
[root] guc_huc_debugfs: 0000:19:00.0/gt0/uc/guc_info: status: RUNNING
[root] guc_huc_debugfs: 0000:19:00.0/gt0/uc/guc_info: wanted release version 70.49.4
[root] guc_huc_debugfs: 0000:19:00.0/gt0/uc/guc_info: found release version 70.60.0
[root] guc_huc_debugfs: 0000:19:00.0/gt0/uc/guc_info: found compatibility version 1.31.0
[root] guc_huc_debugfs: 0000:19:00.0/gt0/uc/guc_info: GuC status 0x8003f0ec:
[root] guc_huc_debugfs: 0000:19:00.0/gt0/uc/guc_info: Bootrom status = 0x76
[root] guc_huc_debugfs: 0000:19:00.0/gt0/uc/guc_info: uKernel status = 0xf0
[root] guc_huc_debugfs: 0000:19:00.0/gt0/uc/guc_info: MIA Core status = 0x3
[root] guc_huc_debugfs: 0000:19:00.0/gt0/uc/guc_info: status (memory): 0x0
[root] guc_huc_debugfs: 0000:19:00.0/gt0/uc/guc_info: status (memory): 0x0
[root] guc_huc_debugfs: 0000:19:00.0/gt1/uc/guc_info: GuC firmware: xe/bmg_guc_70.bin
[root] guc_huc_debugfs: 0000:19:00.0/gt1/uc/guc_info: status: RUNNING
[root] guc_huc_debugfs: 0000:19:00.0/gt1/uc/guc_info: wanted release version 70.49.4
[root] guc_huc_debugfs: 0000:19:00.0/gt1/uc/guc_info: found release version 70.60.0
[root] guc_huc_debugfs: 0000:19:00.0/gt1/uc/guc_info: found compatibility version 1.31.0
[root] guc_huc_debugfs: 0000:19:00.0/gt1/uc/guc_info: GuC status 0x8003f0ec:
[root] guc_huc_debugfs: 0000:19:00.0/gt1/uc/guc_info: Bootrom status = 0x76
[root] guc_huc_debugfs: 0000:19:00.0/gt1/uc/guc_info: uKernel status = 0xf0
[root] guc_huc_debugfs: 0000:19:00.0/gt1/uc/guc_info: MIA Core status = 0x3
[root] guc_huc_debugfs: 0000:19:00.0/gt1/uc/guc_info: status (memory): 0x0
[root] guc_huc_debugfs: 0000:19:00.0/gt1/uc/guc_info: status (memory): 0x0
[root] guc_huc_debugfs: 1/gt0/uc/guc_info: GuC firmware: xe/bmg_guc_70.bin
[root] guc_huc_debugfs: 1/gt0/uc/guc_info: status: RUNNING
[root] guc_huc_debugfs: 1/gt0/uc/guc_info: wanted release version 70.49.4
[root] guc_huc_debugfs: 1/gt0/uc/guc_info: found release version 70.60.0
[root] guc_huc_debugfs: 1/gt0/uc/guc_info: found compatibility version 1.31.0
[root] guc_huc_debugfs: 1/gt0/uc/guc_info: GuC status 0x8003f0ec:
[root] guc_huc_debugfs: 1/gt0/uc/guc_info: Bootrom status = 0x76
[root] guc_huc_debugfs: 1/gt0/uc/guc_info: uKernel status = 0xf0
[root] guc_huc_debugfs: 1/gt0/uc/guc_info: MIA Core status = 0x3
[root] guc_huc_debugfs: 1/gt0/uc/guc_info: status (memory): 0x0
[root] guc_huc_debugfs: 1/gt0/uc/guc_info: status (memory): 0x0
[root] guc_huc_debugfs: 1/gt1/uc/guc_info: GuC firmware: xe/bmg_guc_70.bin
[root] guc_huc_debugfs: 1/gt1/uc/guc_info: status: RUNNING
[root] guc_huc_debugfs: 1/gt1/uc/guc_info: wanted release version 70.49.4
[root] guc_huc_debugfs: 1/gt1/uc/guc_info: found release version 70.60.0
[root] guc_huc_debugfs: 1/gt1/uc/guc_info: found compatibility version 1.31.0
[root] guc_huc_debugfs: 1/gt1/uc/guc_info: GuC status 0x8003f0ec:
[root] guc_huc_debugfs: 1/gt1/uc/guc_info: Bootrom status = 0x76
[root] guc_huc_debugfs: 1/gt1/uc/guc_info: uKernel status = 0xf0
[root] guc_huc_debugfs: 1/gt1/uc/guc_info: MIA Core status = 0x3
[root] guc_huc_debugfs: 1/gt1/uc/guc_info: status (memory): 0x0
[root] guc_huc_debugfs: 1/gt1/uc/guc_info: status (memory): 0x0
[root] guc_huc_debugfs: 128/gt0/uc/guc_info: GuC firmware: xe/bmg_guc_70.bin
[root] guc_huc_debugfs: 128/gt0/uc/guc_info: status: RUNNING
[root] guc_huc_debugfs: 128/gt0/uc/guc_info: wanted release version 70.49.4
[root] guc_huc_debugfs: 128/gt0/uc/guc_info: found release version 70.60.0
[root] guc_huc_debugfs: 128/gt0/uc/guc_info: found compatibility version 1.31.0
[root] guc_huc_debugfs: 128/gt0/uc/guc_info: GuC status 0x8003f0ec:
[root] guc_huc_debugfs: 128/gt0/uc/guc_info: Bootrom status = 0x76
[root] guc_huc_debugfs: 128/gt0/uc/guc_info: uKernel status = 0xf0
[root] guc_huc_debugfs: 128/gt0/uc/guc_info: MIA Core status = 0x3
[root] guc_huc_debugfs: 128/gt0/uc/guc_info: status (memory): 0x0
[root] guc_huc_debugfs: 128/gt0/uc/guc_info: status (memory): 0x0
[root] guc_huc_debugfs: 128/gt1/uc/guc_info: GuC firmware: xe/bmg_guc_70.bin
[root] guc_huc_debugfs: 128/gt1/uc/guc_info: status: RUNNING
[root] guc_huc_debugfs: 128/gt1/uc/guc_info: wanted release version 70.49.4
[root] guc_huc_debugfs: 128/gt1/uc/guc_info: found release version 70.60.0
[root] guc_huc_debugfs: 128/gt1/uc/guc_info: found compatibility version 1.31.0
[root] guc_huc_debugfs: 128/gt1/uc/guc_info: GuC status 0x8003f0ec:
[root] guc_huc_debugfs: 128/gt1/uc/guc_info: Bootrom status = 0x76
[root] guc_huc_debugfs: 128/gt1/uc/guc_info: uKernel status = 0xf0
[root] guc_huc_debugfs: 128/gt1/uc/guc_info: MIA Core status = 0x3
[root] guc_huc_debugfs: 128/gt1/uc/guc_info: status (memory): 0x0
[root] guc_huc_debugfs: 128/gt1/uc/guc_info: status (memory): 0x0
[root] guc_huc_debugfs: 0000:19:00.0/gt0/uc/huc_info: HuC firmware: (null)
[root] guc_huc_debugfs: 0000:19:00.0/gt0/uc/huc_info: status: N/A
[root] guc_huc_debugfs: 0000:19:00.0/gt0/uc/huc_info: wanted release version 0.0.0
[root] guc_huc_debugfs: 0000:19:00.0/gt1/uc/huc_info: HuC firmware: xe/bmg_huc.bin
[root] guc_huc_debugfs: 0000:19:00.0/gt1/uc/huc_info: status: RUNNING
[root] guc_huc_debugfs: 0000:19:00.0/gt1/uc/huc_info: wanted release version 0.0.0
[root] guc_huc_debugfs: 0000:19:00.0/gt1/uc/huc_info: found release version 8.2.10
[root] guc_huc_debugfs: 0000:19:00.0/gt1/uc/huc_info: HuC status: 0x00500001
[root] guc_huc_debugfs: 1/gt0/uc/huc_info: HuC firmware: (null)
[root] guc_huc_debugfs: 1/gt0/uc/huc_info: status: N/A
[root] guc_huc_debugfs: 1/gt0/uc/huc_info: wanted release version 0.0.0
[root] guc_huc_debugfs: 1/gt1/uc/huc_info: HuC firmware: xe/bmg_huc.bin
[root] guc_huc_debugfs: 1/gt1/uc/huc_info: status: RUNNING
[root] guc_huc_debugfs: 1/gt1/uc/huc_info: wanted release version 0.0.0
[root] guc_huc_debugfs: 1/gt1/uc/huc_info: found release version 8.2.10
[root] guc_huc_debugfs: 1/gt1/uc/huc_info: HuC status: 0x00500001
[root] guc_huc_debugfs: 128/gt0/uc/huc_info: HuC firmware: (null)
[root] guc_huc_debugfs: 128/gt0/uc/huc_info: status: N/A
[root] guc_huc_debugfs: 128/gt0/uc/huc_info: wanted release version 0.0.0
[root] guc_huc_debugfs: 128/gt1/uc/huc_info: HuC firmware: xe/bmg_huc.bin
[root] guc_huc_debugfs: 128/gt1/uc/huc_info: status: RUNNING
[root] guc_huc_debugfs: 128/gt1/uc/huc_info: wanted release version 0.0.0
[root] guc_huc_debugfs: 128/gt1/uc/huc_info: found release version 8.2.10
[root] guc_huc_debugfs: 128/gt1/uc/huc_info: HuC status: 0x00500001
[root] guc_huc_debugfs: 0000:19:00.0/i915_dmc_info: fw loaded: yes
[root] guc_huc_debugfs: 0000:19:00.0/i915_dmc_info: Pipe A fw loaded: yes
[root] guc_huc_debugfs: 0000:19:00.0/i915_dmc_info: Pipe B fw loaded: yes
[root] guc_huc_debugfs: 0000:19:00.0/i915_dmc_info: version: 2.6
[root] guc_huc_debugfs: 1/i915_dmc_info: fw loaded: yes
[root] guc_huc_debugfs: 1/i915_dmc_info: Pipe A fw loaded: yes
[root] guc_huc_debugfs: 1/i915_dmc_info: Pipe B fw loaded: yes
[root] guc_huc_debugfs: 1/i915_dmc_info: version: 2.6
[root] guc_huc_debugfs: 128/i915_dmc_info: fw loaded: yes
[root] guc_huc_debugfs: 128/i915_dmc_info: Pipe A fw loaded: yes
[root] guc_huc_debugfs: 128/i915_dmc_info: Pipe B fw loaded: yes
[root] guc_huc_debugfs: 128/i915_dmc_info: version: 2.6
[root] module_params: i915.force_probe=UNAVAILABLE (module i915 not loaded)
[root] module_params: i915.enable_guc=UNAVAILABLE (module i915 not loaded)
[root] module_params: i915.guc_firmware_path=UNAVAILABLE (module i915 not loaded)
[root] module_params: i915.huc_firmware_path=UNAVAILABLE (module i915 not loaded)
[root] module_params: i915.dmc_firmware_path=UNAVAILABLE (module i915 not loaded)
[root] module_params: xe.force_probe=(empty)
[user] modinfo_force_probe: i915: force_probe:Force probe options for specified supported devices. See CONFIG_DRM_I915_FORCE_PROBE for details. (charp)
[user] modinfo_force_probe: xe: force_probe:Force probe options for specified devices. See CONFIG_DRM_XE_FORCE_PROBE for details [default=]) (charp)
[user] modinfo_fw_dg2_i915: i915/dg2_huc_gsc.bin
[user] modinfo_fw_dg2_i915: i915/dg2_guc_70.bin
[user] modinfo_fw_dg2_i915: i915/dg2_dmc_ver2_08.bin
[user] modinfo_fw_dg2_xe: i915/dg2_guc_70.bin
[user] modinfo_fw_dg2_xe: i915/dg2_dmc_ver2_08.bin
[user] modprobe_d_gpu: NONE
[user] firmware_files_dg2: -rw-r--r--. 1 root root 4360 2026-04-11 08:00 /lib/firmware/i915/dg2_dmc_ver2_06.bin.xz
[user] firmware_files_dg2: -rw-r--r--. 1 root root 4388 2026-04-11 08:00 /lib/firmware/i915/dg2_dmc_ver2_07.bin.xz
[user] firmware_files_dg2: -rw-r--r--. 1 root root 4368 2026-04-11 08:00 /lib/firmware/i915/dg2_dmc_ver2_08.bin.xz
[user] firmware_files_dg2: -rw-r--r--. 1 root root 139760 2026-04-11 08:00 /lib/firmware/i915/dg2_guc_70.1.2.bin.xz
[user] firmware_files_dg2: -rw-r--r--. 1 root root 144824 2026-04-11 08:00 /lib/firmware/i915/dg2_guc_70.4.1.bin.xz
[user] firmware_files_dg2: -rw-r--r--. 1 root root 165828 2026-04-11 08:00 /lib/firmware/i915/dg2_guc_70.bin.xz
[user] firmware_files_dg2: -rw-r--r--. 1 root root 170212 2026-04-11 08:00 /lib/firmware/i915/dg2_huc_gsc.bin.xz
[user] firmware_file_owner: /lib/firmware/i915/dg2_dmc_ver2_06.bin.xz owner=intel-gpu-firmware-20260410-1.fc43.noarch
[user] firmware_file_owner: /lib/firmware/i915/dg2_dmc_ver2_07.bin.xz owner=intel-gpu-firmware-20260410-1.fc43.noarch
[user] firmware_file_owner: /lib/firmware/i915/dg2_dmc_ver2_08.bin.xz owner=intel-gpu-firmware-20260410-1.fc43.noarch
[user] firmware_file_owner: /lib/firmware/i915/dg2_guc_70.1.2.bin.xz owner=intel-gpu-firmware-20260410-1.fc43.noarch
[user] firmware_file_owner: /lib/firmware/i915/dg2_guc_70.4.1.bin.xz owner=intel-gpu-firmware-20260410-1.fc43.noarch
[user] firmware_file_owner: /lib/firmware/i915/dg2_guc_70.bin.xz owner=intel-gpu-firmware-20260410-1.fc43.noarch
[user] firmware_file_owner: /lib/firmware/i915/dg2_huc_gsc.bin.xz owner=intel-gpu-firmware-20260410-1.fc43.noarch
== boot ==
[user] boot_mode: UEFI (/sys/firmware/efi present)
[user] boot_dir_entries: 23
[root] grubby_default: index=0
[root] grubby_default: kernel="/boot/vmlinuz-6.19.14-200.fc43.x86_64"
[root] grubby_default: args="ro rd.lvm.lv=fedora_nas/root console=ttyS1,115200"
[root] grubby_default: root="/dev/mapper/fedora_nas-root"
[root] grubby_default: initrd="/boot/initramfs-6.19.14-200.fc43.x86_64.img"
[root] grubby_default: title="Fedora Linux (6.19.14-200.fc43.x86_64) 43 (Server Edition)"
[root] grubby_default_kernel: /boot/vmlinuz-6.19.14-200.fc43.x86_64
[user] installed_kernels: kernel-core-6.14.9-300.fc42.x86_64
[user] installed_kernels: kernel-core-6.19.14-100.fc42.x86_64
[user] installed_kernels: kernel-core-6.19.14-200.fc43.x86_64
== packages ==
[user] firmware_pkgs: linux-firmware-20260410-1.fc43.noarch
[user] firmware_pkgs: intel-gpu-firmware-20260410-1.fc43.noarch
[user] firmware_pkgs: linux-firmware-whence-20260410-1.fc43.noarch
[user] firmware_upgrades: [13 lines removed at operator request — dnf OpenPGP key-import prompts for third-party repositories, not GPU-related]
[user] firmware_upgrades: intel-gpu-firmware.noarch 20261019-1.fc43 updates
[user] firmware_upgrades: linux-firmware.noarch 20261019-1.fc43 updates
[user] firmware_upgrades: linux-firmware-whence.noarch 20261019-1.fc43 updates
[user] media_pkgs: igt-gpu-tools-2.4-1.fc43.x86_64
[user] media_pkgs: intel-media-driver-26.1.5-1.fc43.x86_64
[user] media_pkgs: intel-mediasdk-23.2.2-8.fc43.x86_64
[user] media_pkgs: intel-vpl-gpu-rt-26.1.6-1.fc43.x86_64
[user] media_pkgs: libva-2.22.0-6.fc43.x86_64
[user] media_pkgs: libva-utils-2.22.0-5.fc43.x86_64
[user] media_pkgs: libvpl-2.16.0-1.fc43.x86_64
[user] media_pkgs: mesa-va-drivers-25.3.6-3.fc43.x86_64
== encode-path ==
[user] vainfo: vainfo: Driver version: Intel iHD driver for Intel(R) Gen Graphics - 26.1.5 ()
[user] vainfo_av1: VAProfileAV1Profile0 : VAEntrypointVLD
[user] vainfo_av1: VAProfileAV1Profile0 : VAEntrypointEncSlice
[user] qsvencc_bin_sha256: c5f791d964c4e3a84aabe15e25fba8388396c2c2357e637cf7914a5bac2d12b3
[user] qsvencc_version: QSVEncC (x64) 8.18 (r4205) by rigaya, Jun 27 2026 13:44:06 (gcc 14.3.1/Linux)
[user] qsvencc_av1_ff: Codec: AV1 FF
[user] qsvencc_av1_ff: CBR VBR AVBR QVBR CQP LA LAHRD ICQ LAICQ VCM
[user] qsvencc_av1_ff: RC mode o o x x o x x o x x
[user] qsvencc_av1_ff: 10bit depth o o x x o x x o x x
[user] qsvencc_av1_ff: Hyper Mode x x x x x x x x x x
[user] qsvencc_av1_ff: Interlace x x x x x x x x x x
[user] qsvencc_av1_ff: VUI info o o x x o x x o x x
[user] qsvencc_av1_ff: Trellis x x x x x x x x x x
[user] qsvencc_av1_ff: BFrame/GopRef o o x x o x x o x x
[user] qsvencc_av1_ff: Adaptive_I o o x x o x x o x x
[user] qsvencc_av1_ff: Adaptive_B o o x x o x x o x x
[user] qsvencc_av1_ff: WeightP x x x x x x x x x x
[user] qsvencc_av1_ff: WeightB x x x x x x x x x x
[user] qsvencc_av1_ff: FadeDetect x x x x x x x x x x
[user] qsvencc_av1_ff: B_Pyramid o o x x o x x o x x
[user] qsvencc_av1_ff: +ManyBframes o o x x o x x o x x
[user] qsvencc_av1_ff: PyramQPOffset x x x x o x x x x x
[user] qsvencc_av1_ff: TuneQuality o o x x o x x o x x
[user] qsvencc_av1_ff: ScenarioInfo o o x x o x x o x x
[user] qsvencc_av1_ff: MBBRC o o x x x x x o x x
[user] qsvencc_av1_ff: ExtBRC o o x x x x x o x x
[user] qsvencc_av1_ff: AdaptiveRef x x x x x x x x x x
[user] qsvencc_av1_ff: AdaptiveLTR o o x x o x x o x x
[user] qsvencc_av1_ff: AdaptiveCQM o o x x o x x o x x
[user] qsvencc_av1_ff: LA Quality x x x x x x x x x x
[user] qsvencc_av1_ff: QP Min/Max o o x x x x x o x x
[user] qsvencc_av1_ff: IntraRefresh x x x x x x x x x x
[user] qsvencc_av1_ff: No Deblock x x x x x x x x x x
[user] qsvencc_av1_ff: No GPB x x x x x x x x x x
[user] qsvencc_av1_ff: Windowed BRC x x x x x x x x x x
[user] qsvencc_av1_ff: PerMBQP(CQP) x x x x x x x x x x
[user] qsvencc_av1_ff: DirectBiasAdj x x x x x x x x x x
[user] qsvencc_av1_ff: MVCostScaling x x x x x x x x x x
[user] qsvencc_av1_ff: SAO x x x x x x x x x x
[user] qsvencc_av1_ff: Max CTU Size x x x x x x x x x x
[user] qsvencc_av1_ff: TSkip x x x x x x x x x x
[user] qsvencc_av1_ff: AI Enc Ctrl x x x x x x x x x x
[user] qsvencc_av1_ff: RepartCheck x x x x x x x x x x
[user] qsvencc_av1_ff: COP o o x x o x x o x x
[user] qsvencc_av1_ff: COP2 o o x x o x x o x x
[user] qsvencc_av1_ff: COP3 o o x x o x x o x x
[user] qsvencc_av1_ff: HEVC_PRM x x x x x x x x x x
[user] qsvencc_av1_ff: COP_VP8 x x x x x x x x x x
[user] qsvencc_av1_ff: VP9_PRM x x x x x x x x x x
[user] qsvencc_av1_ff: AV1BITSTREAM o o x x o x x o x x
[user] qsvencc_av1_ff: AV1RESOLUTION o o x x o x x o x x
[user] qsvencc_av1_ff: AV1TILE o o x x o x x o x x
[user] qsvencc_av1_ff: VIDEO_SIGNAL o o x x o x x o x x
[user] qsvencc_av1_ff: CHROMALOC x x x x x x x x x x
[user] qsvencc_av1_ff: TUNE_ENC_QUAL o o x x o x x o x x
[user] qsvencc_av1_ff: HYPER_MODE x x x x x x x x x x
[user] qsvencc_av1_ff: AI_ENC_CTRL x x x x x x x x x x
redaction: uuid,mac,id32,home,hostname applied
END capability_probe
```

## Operator answers (checkpoint, verbatim)

Date: 2026-10-24. Source: `scratch/host-levers/operator_answers.txt`. Russian kept as given; the only edit is the redaction of the host user name in (c).

- Hardware change, after the probe showed `8086:e212` on xe: "A380 сменен на B50". Decision on how to proceed (continue on the current facts, record the replacement as a deviation, mark L1/L2 not applicable to the current hardware): "ОК".
- (a) Can the NAS be restarted for the deferred experiments, and under what constraints: "Нет."
- (b) Out-of-band console access to repair a broken boot: "Есть, но лучше избегать проблем, которые его потребуют"
- (c) sudo on the host / was the probe run with sudo: "У пользователя REDACTED-USER нет sudo и не будет". Executor note: the probe header reads `run_as: uid=0 euid=0 userns=identity sudo_invoked=yes SUDO_UID=0`, i.e. it was started from a root shell, not through the regular user's sudo.
- (d) Able and permitted to change the default boot entry's kernel arguments (grubby), kernel-module options (/etc/modprobe.d) and the firmware package (dnf upgrade/downgrade): "Могу и вправе"
- Host user name confirmation (checkpoint step 6; the name itself is kept out of git): "Под этим пользователем запущен контейнер в котором мы работаетм"
- dnf key-import lines in the EVIDENCE copy: "Вырежи"
- What was running on the GPU during the two `Engine reset` events: "Не знаю"

## Interpretation

What the operator can change and with which privilege. The probe ran as real root (`uid_map: 0 0 4294967295`, `cap_sys_admin/cap_sys_module/cap_sys_boot/cap_syslog: YES`), so every read-only check, including the root-only ones (kernel ring buffer, debugfs, module parameters, grubby), produced real values. The regular host user has no sudo and will not get it (answer (c)). The operator declares the right and ability to change boot arguments, module options and the firmware package (answer (d)); these three CAP-*-CHG cells are `operator-declared (not tested)`, because a read-only probe shows readability, not that a change would succeed. Nothing was changed to test it (D-07).

The no-reboot answer decides in practice. Answer (a) ("Нет.") blocks a restart of the NAS for the deferred experiments. Every deferred lever needs a restart (a new boot argument or a new firmware file is read only at boot), so the answer blocks BOTH levers regardless of the change rights in answer (d). Answer (b) says an out-of-band console exists but should not be needed; it is operator-declared and was never exercised. Note that (a) is a policy statement, not a probe result.

Both levers are moot on the current hardware. The GPU is now an Arc Pro B50 (Battlemage) natively driven by xe with `bmg_*` firmware, so L1 (update of the DG2 GuC/HuC firmware) and L2 (switch i915 -> xe with `force_probe` for `8086:56a5`) are NOT APPLICABLE: there is no DG2 device to flash or to force-probe, and `dg2_*` firmware is installed but not used. They remain in the runbook only for the case the A380 is put back. The firmware route that does exist on this machine is the Fedora package update `20260410-1.fc43` -> `20261019-1.fc43`, which the host can see, but it would act on the BMG firmware, needs a restart, and is outside what the original hypothesis (the A380 `dg2` GuC/HuC) tests.

What stays unknown. Whether the A380 corruption reproduces on the B50 (not tested: different GPU, different media entrypoint, `VAEntrypointEncSlice` instead of `VAEntrypointEncSliceLP`, host media stack iHD 26.1.5 versus 26.2.2 in the container). Whether a restart would be tolerated in an emergency (only the policy "Нет." is known). Whether the console works (never exercised). What triggered the two blitter-engine resets.

What the host data means for the levers. A newer firmware package exists (`20261019-1.fc43` for `linux-firmware`, `intel-gpu-firmware`, `linux-firmware-whence`), but for DG2 it would only replace unused files on this hardware. The STATE concern about Xe and HuC on DG2 is answered only as far as the static evidence on the running kernel goes: `modinfo_fw_dg2_xe` declares `i915/dg2_guc_70.bin` and `i915/dg2_dmc_ver2_08.bin` and NO dg2 HuC file, while `modinfo_fw_dg2_i915` also declares `i915/dg2_huc_gsc.bin`. If the A380 were put back and L2 attempted, xe would therefore not be expected to load a HuC for it, and the AV1 low-power ICQ path (which depends on HuC) is expected to disappear; the gate would then fail and the result would be "not measurable as a single variable on DG2". A live xe HuC load on DG2 can be observed only after such a switch, through the runbook gate. On the B50, xe loads HuC 8.2.10 (RUNNING per debugfs on GT1) and GuC 70.60.0 (RUNNING).

Encode-path consequence. The i915 encode-path baseline is valid only with the A380 installed on i915. With the B50 the encode path is a different one (`VAEntrypointEncSlice`), so a new baseline would have to be captured on the B50 before any lever gate could rely on it.

No state was changed. No host or container state was changed in Phase 3 (D-07): the probe only read, no lever command ran, nothing was installed or restarted, and nothing was written under `/sys`. The GPU swap and the host restart between 2026-10-03 and 2026-10-24 happened outside any action of this phase.
