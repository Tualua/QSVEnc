# Phase 3 Durable Evidence Snapshot — host-side capability (DIAG-01)

**Run date:** 2026-10-03
**Recorded by:** 03-01-PLAN.md, executed on the main working tree at `/workspaces/QSVEnc` — no worktree isolation.

## Why this file exists

`scratch/` is git-ignored (`/scratch/*`), so the runtime outputs of this phase — `scratch/host-levers/container_probe.txt` now, `host_probe.txt` and `operator_answers.txt` after the host run — vanish with any cleanup of the workdir. This git-tracked file holds the verbatim probe outputs and the capability matrix derived from them, so the DIAG-01 record survives regardless of what happens to `scratch/`.

The probe (`tools/capability_probe.sh`) is strictly read-only (D-02). Nothing on the host or in the container was changed to produce this record (D-07): the container run was followed by a `find -newer` write check (last section), no lever command was run, nothing was installed and nothing was restarted.

## Requirement -> Artifact mapping

| Requirement / criterion | Satisfied by |
|---|---|
| DIAG-01 (determine and record host-side change capability honestly) | `## Capability matrix (DIAG-01)`, `## Firmware & driver versions (D-03 baseline)` and the verbatim probe outputs in this file |
| ROADMAP Phase 3 SC1 (capability determined and recorded, each available or blocked) | `## Capability matrix (DIAG-01)`: container column from `## Container-side probe`; host column from the operator run of the same committed script at the Task 2 checkpoint |
| ROADMAP Phase 3 SC2 (deferred levers listed, what they test, what they need from the host owner) | `03-RUNBOOK.md` (Task 4 of the same plan) |
| Lever gate input (i915 encode-path reference, D-05) | `## Encode-path baseline under i915` and `tools/encode_path_baseline_i915.txt` |

## Capability matrix (DIAG-01)

Status vocabulary (D-04), exactly one term per status cell: `available` | `blocked from container — requires host-owner action` | `blocked on host` | `unknown` | `operator-declared (not tested)` | `n/a`.

Rules (D-04: never infer a capability without evidence; D-07: nothing is changed to test it):

- Observable and changeable are kept apart. An `-OBS` cell (and a visibility row such as CAP-GUCHUC, CAP-XE, CAP-ENCODE) may be `available` when a probe line shows the value was actually read.
- A `-CHG` cell is never `available` from probe evidence: a read-only probe shows readability or existence, not the ability to change anything. It is `blocked ...` when a probe line shows the missing privilege (for example `cap_sys_admin: NO`, `cap_sys_module: NO`, `BLOCKED` in `module_params`), `operator-declared (not tested)` with a quoted operator answer, or `unknown`.
- A row that joins two facts is only as strong as its weaker part: when one part is not observable the row takes the weaker term and the evidence names both parts.
- Evidence cells name the probe key and quote the decisive value from the verbatim section below. The container sees the host kernel (cmdline, sysfs, module parameters, kernel log) but its own image filesystem: the `firmware`, `boot`, `packages` and `modprobe.d` lines of the container probe describe the image, not the host (`fs_scope`).
- The host columns are filled from the host probe and the operator answers after the Task 2 checkpoint.

| id | capability | container status | container evidence | host status | host evidence |
|---|---|---|---|---|---|
| CAP-PRIV | privilege level of the probing process | blocked from container — requires host-owner action | `run_as: uid=0 euid=0 userns=mapped sudo_invoked=no`; `uid_map: 0 1010 1` (container root is host uid 1010, not host root); `cap_sys_admin: NO`, `cap_sys_module: NO`, `cap_sys_boot: NO`, `cap_syslog: NO`; `sudo_noninteractive: n/a (running as root; uid 0 is mapped into a user namespace)` | awaiting host probe (Task 2 checkpoint) | awaiting host probe (Task 2 checkpoint) |
| CAP-CMDLINE-OBS | running kernel cmdline and persisted default boot entry readable | blocked from container — requires host-owner action | running cmdline IS readable: `cmdline: BOOT_IMAGE=(hd6,gpt2)/vmlinuz-6.19.14-200.fc43.x86_64 root=/dev/mapper/fedora_nas-root ro rd.lvm.lv=fedora_nas/root console=ttyS1,115200`, `cmdline_gpu_params: NONE`; persisted default entry is NOT: `grubby_default: UNAVAILABLE (grubby not installed)`, `boot_dir_entries: 0` | awaiting host probe (Task 2 checkpoint) | awaiting host probe (Task 2 checkpoint) |
| CAP-CMDLINE-CHG | bootloader / kernel arguments can be changed | blocked from container — requires host-owner action | `cap_sys_admin: NO`, `cap_sys_boot: NO`, `userns=mapped`; the host bootloader entries are not visible (`boot_dir_entries: 0`, `grubby_default: UNAVAILABLE (grubby not installed)`) | awaiting host probe (Task 2 checkpoint) | awaiting host probe (Task 2 checkpoint) |
| CAP-MODPROBE-OBS | module parameters, modprobe.d and modinfo readable | blocked from container — requires host-owner action | `module_params: i915.force_probe=BLOCKED (cat: /sys/module/i915/parameters/force_probe: Permission denied)` and the same for `i915.enable_guc`, `i915.guc_firmware_path`, `i915.huc_firmware_path`, `i915.dmc_firmware_path`, `xe.force_probe`; `modinfo_force_probe: UNAVAILABLE (modinfo not installed)`; `modprobe_d_gpu: NONE` describes the container image only | awaiting host probe (Task 2 checkpoint) | awaiting host probe (Task 2 checkpoint) |
| CAP-MODPROBE-CHG | module options or module load / unload can be changed | blocked from container — requires host-owner action | `cap_sys_module: NO`, `cap_sys_admin: NO`, `module_params: ... BLOCKED`, `sysfs_unbind_writable: NO (i915: NO, xe: NO)` | awaiting host probe (Task 2 checkpoint) | awaiting host probe (Task 2 checkpoint) |
| CAP-FW-OBS | firmware files, owning package and loaded versions readable | blocked from container — requires host-owner action | `firmware_files_dg2: NONE` and `firmware_file_owner: UNAVAILABLE (rpm not installed)` (container image, not the host); loaded versions: `guc_huc: BLOCKED (dmesg: read kernel buffer failed: Operation not permitted)`, `guc_huc_debugfs: BLOCKED (/sys/kernel/debug/dri is not present: ...)`, `guc_huc_journal: NONE` | awaiting host probe (Task 2 checkpoint) | awaiting host probe (Task 2 checkpoint) |
| CAP-FW-CHG | firmware can be updated | blocked from container — requires host-owner action | `firmware_pkgs: UNAVAILABLE (rpm not installed)`, `firmware_upgrades: UNAVAILABLE (dnf not installed)`, `cap_sys_admin: NO`; the host kernel loads firmware from the host filesystem, not from the container image | awaiting host probe (Task 2 checkpoint) | awaiting host probe (Task 2 checkpoint) |
| CAP-REBOOT | host can be restarted | blocked from container — requires host-owner action | `reboot_capability: BLOCKED (no CAP_SYS_BOOT; a container cannot restart its host)`, `cap_sys_boot: NO` | awaiting host probe (Task 2 checkpoint) | awaiting host probe (Task 2 checkpoint) |
| CAP-CONSOLE | out-of-band console for rollback | unknown | not observable from the container; hints only, not proof: `cmdline` carries `console=ttyS1,115200`, `drm_cards: card1 driver=ast 0x1a03:0x2000` (a BMC-class VGA device is present) | awaiting host probe (Task 2 checkpoint) | awaiting host probe (Task 2 checkpoint) |
| CAP-GUCHUC | GuC / HuC / DMC firmware versions visible | blocked from container — requires host-owner action | `guc_huc: BLOCKED (dmesg: read kernel buffer failed: Operation not permitted)`, `guc_huc_debugfs: BLOCKED (/sys/kernel/debug/dri is not present: debugfs not mounted or not visible from this context)`, `guc_huc_journal: NONE` (no kernel messages visible) | awaiting host probe (Task 2 checkpoint) | awaiting host probe (Task 2 checkpoint) |
| CAP-XE | xe driver present in the running kernel (A380 currently bound to i915) | available | `pci_drivers_present: i915=yes xe=yes`; `gpu_driver: /sys/bus/pci/drivers/i915 (0000:19:00.0)`; `render_node_driver: renderD128 driver=i915`. Presence only: whether xe can drive the A380 is the L2 lever (force_probe) and was not tested | awaiting host probe (Task 2 checkpoint) | awaiting host probe (Task 2 checkpoint) |
| CAP-BIND | driver bind / unbind through sysfs | blocked from container — requires host-owner action | `sysfs_unbind_writable: NO (i915: NO, xe: NO)`, `cap_sys_admin: NO` | awaiting host probe (Task 2 checkpoint) | awaiting host probe (Task 2 checkpoint) |
| CAP-ENCODE | AV1 low-power encode path visible (VAEntrypointEncSliceLP, ICQ in the FF block) | available | `vainfo_av1: VAProfileAV1Profile0 : VAEntrypointEncSliceLP`; `qsvencc_av1_ff: RC mode o o x x o x x o x x` with ICQ (8th column) `o`; reference lines in `tools/encode_path_baseline_i915.txt` | awaiting host probe (Task 2 checkpoint) | awaiting host probe (Task 2 checkpoint) |

## Firmware & driver versions (D-03 baseline)

Each value is a value or `unknown — reason` (D-03, D-04). The container cannot read the kernel log, the firmware packages or the module metadata, so the GuC / HuC / DMC and package rows are `unknown` on the container side; the host column carries the baseline.

| item | container | host |
|---|---|---|
| kernel (kernel-wide, the same kernel on both sides) | `6.19.14-200.fc43.x86_64` (`kernel`; `kernel_matches_affected_host: YES`) | awaiting host probe (Task 2 checkpoint) |
| GuC firmware version (source order: `guc_huc_debugfs`, `guc_huc_journal`, `guc_huc`) | unknown — `guc_huc: BLOCKED` (dmesg), `guc_huc_debugfs: BLOCKED` (no debugfs), `guc_huc_journal: NONE` | awaiting host probe (Task 2 checkpoint) |
| HuC firmware version and authentication status | unknown — same three sources, none readable | awaiting host probe (Task 2 checkpoint) |
| DMC firmware version | unknown — same three sources, none readable | awaiting host probe (Task 2 checkpoint) |
| firmware package NEVRA(s) and owner of the dg2 files | unknown — `firmware_pkgs: UNAVAILABLE (rpm not installed)`, `firmware_file_owner: UNAVAILABLE (rpm not installed)`; the container image would not describe the host anyway | awaiting host probe (Task 2 checkpoint) |
| newer firmware package available | unknown — `firmware_upgrades: UNAVAILABLE (dnf not installed)` | awaiting host probe (Task 2 checkpoint) |
| xe DG2 firmware declarations (does xe request a DG2 HuC file) | unknown — `modinfo_fw_dg2_xe: UNAVAILABLE (modinfo not installed)` | awaiting host probe (Task 2 checkpoint) |
| iHD media driver | `Intel iHD driver for Intel(R) Gen Graphics - 26.2.2 ()` (`vainfo`) | host media packages (`media_pkgs`): awaiting host probe (Task 2 checkpoint) |
| libva | VA-API 1.23, libva 2.23.0 (header line of a separate read-only `LIBVA_DRIVER_NAME=iHD vainfo` run, not part of the probe output) | awaiting host probe (Task 2 checkpoint) |
| qsvencc used for the measurements (D-06) | `QSVEncC (x64) 8.31 (r4604) by rigaya, Oct  1 2026 07:28:26 (gcc 13.3.0/Linux)`; sha256 `f4282c494a1fe0565e568b7c35285d416a64b36265ffa93d5ffa362ec3c3cbdb` (`qsvencc_version`, `qsvencc_bin_sha256`) | n/a (encode runs in the container) |

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
