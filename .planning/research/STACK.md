# Stack Research

**Domain:** Host-kernel/driver-level diagnosis of concurrent Intel QSV/oneVPL AV1 encode frame corruption on Arc DG2 (Alchemist, A380), Linux
**Researched:** 2026-07-23
**Confidence:** MEDIUM-HIGH overall (kernel/driver mechanics HIGH; DG2-specific Xe HuC status MEDIUM — last independently confirmed ~Sept 2025, re-verify live via dmesg before relying on it)

## Recommended Stack

### Core Technologies (host-side levers)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Linux kernel | 6.8+ minimum for Xe-on-DG2 at all; this environment already runs 6.19.14 (matches affected host) | Host GPU driver substrate | Xe support for DG2/Alchemist has existed since ~6.8 but stays behind `force_probe` forever by design — it is **not** a "wait for a newer kernel and it becomes default" situation for this GPU generation. Confidence: HIGH (kernel.org Xe merge-acceptance-plan RFC). |
| `xe` DRM driver | in-tree, same kernel as above | Alternative host driver to `i915`, different GEM/BO lifecycle, VM/context, and (on DG2 specifically) **GuC-only submission model with no execlist fallback** | This is the single most promising untried lever per the brief — a different BO/context-isolation model could close the cross-process aliasing window that `i915` allows. Confidence: MEDIUM-HIGH the mechanism differs; LOW-MEDIUM that it actually fixes this specific bug (untested). |
| `i915` DRM driver | current default for DG2/Alchemist | Baseline/current host driver | This is what's currently running and reproducing the bug; kept only as the control condition, not the target. |
| GuC/HuC firmware (`linux-firmware`) | `dg2_guc_70.bin` family (70.x, e.g. 70.29/70.45.2/70.53.0 lineage — check `linux-firmware` package changelog for the exact latest at test time), `dg2_huc_gsc.bin` (GSC-layout HuC, distinct from pre-DG2 CSS-layout HuC) | Scheduling (GuC) and low-power media BRC (HuC) firmware blobs loaded by whichever DRM driver binds the card | GuC handles context submission/scheduling across processes — directly relevant to a cross-session aliasing bug. Updating it is cheap and reversible. Confidence: MEDIUM (exact "latest" version drifts; use whatever `linux-firmware` ships current at test time, see Installation). |
| FFmpeg | 8.0/8.1 line (8.0 "Huffman" Aug 2025, 8.1.x current as of mid-2026; 8.0.3 released 2026-06-18, 8.1.2 released 2026-06-17) | Alternative/control encode paths: `av1_qsv` (already proven immune, keep as control) and `av1_vaapi` (untried "quieter" path) | `av1_vaapi` talks to `iHD` directly over `libva`, entirely bypassing the oneVPL/MSDK-compat runtime layer that both `qsvencc` and ffmpeg's `av1_qsv` sit on top of. A third clean/dirty data point here is diagnostically useful: if `av1_vaapi` is also clean, it further isolates the defect to qsvencc's own OR-combined surface-pool code (already suspected) rather than to the oneVPL runtime; if `av1_vaapi` corrupts too, that reopens the oneVPL-runtime-is-innocent conclusion. Confidence: MEDIUM (FFmpeg source confirms AV1 VAAPI encoder supports B-pictures via `FF_HW_FLAG_B_PICTURES` and shares the common `b_depth`/`async_depth`/`rc_mode` HW-encode option set; 10-bit `p010`→AV1 VAAPI is confirmed working via `-vf format=p010,hwupload` in community reports). |
| `igt-gpu-tools` (`intel_gpu_top`, `intel_reg`, etc.) | 2.4+ (Arch `core/intel-gpu-tools` at 2.4-1 as of the `linux-firmware-intel 20260622` snapshot; project renamed package `intel-gpu-tools`→bundled under `igt-gpu-tools` upstream) | GPU engine/BO diagnostics | Needed for concurrency observation (engine occupancy overlap between sessions) and possibly the only way to see per-client GPU load on `i915`. Confidence: MEDIUM — `intel_gpu_top` gained Xe *library* support in igt-gpu-tools 1.29 (Sep 2024) but full first-class Xe support in the `intel_gpu_top` *tool* itself lagged behind and may still be incomplete; verify empirically after switching to Xe (`intel_gpu_top -L` to list PCI devices it can see). |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `libva`/`libva-drm` | 2.23+ (already validated as inert in prior userspace-swap experiment) | VA-API core, used by both `iHD` (qsvencc/oneVPL) and ffmpeg `av1_vaapi` | Already ruled out as the fix surface at the userspace-only level; keep at whatever version currently installed, don't chase newer libva as a lever (see "What NOT to Use"). |
| `iHD` media driver | 25.2.3 or 26.2.2 (both already tested, both reproduce identically) | The VA-API driver both `qsvencc` and ffmpeg ultimately call into | Do not re-test different `iHD` versions; already exhausted (§5 of handoff). Only relevant here as the constant you hold while swapping the *kernel-side* driver (`i915`↔`xe`). |
| `ffmpeg` build with `--enable-vaapi --enable-libdrm` | matches whatever `libavcodec` the repo already links (4.x–7.x per `QSVEnc` build reqs; a *standalone* system `ffmpeg` 8.x binary is fine for the diagnostic harness — it does not need to be the same build QSVEnc links against) | Control/comparison encode paths (`av1_qsv`, `av1_vaapi`) and all frame-extraction/PSNR/VMAF verification | Use a normal distro or self-built ffmpeg ≥6.1 (unified HW-encode option set) for the harness; version drift vs. the QSVEnc-linked libav* doesn't matter because this ffmpeg only produces/consumes bitstreams and does verification, it is not part of the code under test. |
| `libvmaf` | current upstream (loaded via `dlopen` by ffmpeg's `libvmaf` filter, or ffmpeg's built-in `vmaf`/`libvmaf` filter) | Defense-in-depth per-frame content verification (§ Active requirement in PROJECT.md) | Use ffmpeg's `-lavfi libvmaf` (needs ffmpeg built `--enable-libvmaf`) or the simpler `-lavfi psnr` for the fast per-frame gate; do **not** rely on `qsvencc --psnr/--ssim` (requires OpenCL/Intel ICD which this stack should not depend on per PROJECT.md constraint). |

### Development/Diagnostic Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `readlink -f /sys/class/drm/card0/device/driver` (also `/sys/class/drm/renderD128/device/driver`) | Confirm which kernel driver (`i915` vs `xe`) is currently bound to the GPU | Fast, no root needed. Cross-check with `lspci -k -s <bus-id>` ("Kernel driver in use:" line) and `dmesg \| grep -iE '(i915\|xe) .*(guc\|huc)'` for firmware load confirmation. Confidence: HIGH. |
| `dmesg \| egrep -i '(GuC|HuC|firmware)'` (with driver-name filter) | Confirm GuC/HuC firmware version actually loaded, and whether HuC authenticated successfully | Look for lines like `i915 0000:XX:XX.X: [drm] GuC firmware i915/dg2_guc_70.bin version X.Y.Z` and `HuC firmware i915/dg2_huc_gsc.bin version A.B.C`; under `xe` the driver name prefix changes to `xe`. **A missing/failed HuC line under `xe` on DG2 is the expected, not-a-bug, outcome (see Critical Caveat below).** |
| `intel_gpu_top` (igt-gpu-tools) | Live engine-occupancy view (Render/Blitter/Video/VideoEnhance %, per-client if supported) during the 3-way concurrent repro | Only reliably full-featured on `i915`; Xe support was added to the underlying perf library in igt-gpu-tools 1.29 (Sep 2024) but the tool's own Xe coverage lagged — re-verify with the currently-installed igt-gpu-tools version once bound to `xe`; if it can't enumerate the Xe device, fall back to `/proc/<pid>/fdinfo`. |
| `/proc/<pid>/fdinfo/<fd>` (`drm-driver`, `drm-total-local0`, `drm-cycles-*`) | Per-process GPU memory/engine-cycle accounting, generic DRM fdinfo interface | Works on **both** `i915` and `xe` (format differs slightly: i915 reports `drm-total-local0`/time in ns, xe reports `drm-cycles-<engine>`/GPU cycles) — this is the one diagnostic that survives the driver swap unchanged in *availability*, useful for confirming the three concurrent `qsvencc` PIDs really do have distinct GPU memory/BO footprints as expected, or unexpectedly overlapping ones. |
| `/sys/kernel/debug/dri/<N>/` (debugfs, root, `mount -t debugfs debug /sys/kernel/debug` if not mounted) | Deeper per-driver debugfs (client list, GEM object dump, engine reset/hang state) | Path and mount mechanism identical between `i915` and `xe`; the *contents*/file-names differ per driver (i915 exposes e.g. `i915_gem_objects`, `clients`; xe exposes its own `gt#/` and VM/exec-queue debugfs — inspect `ls /sys/kernel/debug/dri/<N>/` after binding to enumerate what's actually present on your kernel build, do not assume filenames without checking). |
| `strace -f -e trace=ioctl -yy -o trace.log qsvencc ...` | Trace raw DRM ioctls (`DRM_IOCTL_I915_GEM_*` vs `DRM_IOCTL_XE_*`) issued by the two concurrent processes | Use `-f` (follow forks/threads) and `-yy` (decode fd paths) since the interesting ioctls happen across the internal MFX/VA thread(s); pair with `-T` for per-call timing to spot contention windows that might correlate with a corrupt frame. High volume — filter by ioctl number/name once you know which family you're chasing, or use `strace -c` first for a summary pass. |
| `LIBVA_TRACE=<path>` , `LIBVA_MESSAGING_LEVEL=2` | libva-level call tracing / verbose diagnostic logging (per-thread trace file of every VA-API call + semi-disassembled params) | Cheap, no rebuild required, works identically regardless of which kernel driver is bound (this is a libva/userspace-level knob, already partially explored per handoff §5 but not with `LIBVA_TRACE` specifically — worth re-running under both `i915` and `xe` to compare the actual VA surface-creation/submission call sequence, not just outcomes). |
| `LD_DEBUG=libs,bindings` (glibc dynamic linker trace) | Confirm which `libmfx`/`libvpl`/`libva`/`iHD` shared objects actually get resolved/loaded per process, catch stale-symlink or LD_LIBRARY_PATH surprises when swapping stacks | Standard glibc facility, extremely verbose — redirect to per-process log files (`LD_DEBUG_OUTPUT=/path/prefix` writes `<prefix>.<pid>` per process, essential for the concurrent 3-session harness so logs don't interleave). |

## Installation

```bash
# 1. Confirm current driver binding (baseline, before any change)
readlink -f /sys/class/drm/card0/device/driver
lspci -k -s "$(basename $(readlink -f /sys/class/drm/card0/device))" | grep -i "kernel driver"
dmesg | grep -iE '\bi915\b.*(guc|huc)|firmware'

# 2. Switch Intel Arc A380 (PCI ID 8086:56a5, DG2-128) from i915 to Xe
#    Persistent config (survives reboot), NOT a live-swap (requires reboot: force_probe
#    is read at driver module init, and i915/xe both need to (re)bind cleanly to the
#    display + render nodes — do this on a host you can reboot, not a live session):
cat <<'EOF' | sudo tee /etc/modprobe.d/xe-a380.conf
options i915 force_probe=!56a5
options xe force_probe=56a5
EOF
sudo dracut -f   # or: sudo update-initramfs -u   (regenerate initramfs so early modprobe.d is honored)
sudo reboot

# 3. Post-reboot verification
readlink -f /sys/class/drm/card0/device/driver     # expect: .../drivers/xe
dmesg | grep -iE '\bxe\b.*(guc|huc|firmware)'       # confirm GuC loaded; WATCH for missing/failed HuC line (expected on DG2+Xe, see caveat)
vainfo 2>&1 | head -20                              # confirm iHD still finds the render node and lists AV1 encode profiles

# 4. GuC/HuC firmware refresh (independent of i915/Xe choice — do this either way)
sudo apt install --only-upgrade linux-firmware        # Debian/Ubuntu
# or: sudo dnf upgrade linux-firmware                  # Fedora (this environment's fc43 base)
# or: sudo pacman -Syu linux-firmware                  # Arch
ls -la /lib/firmware/i915/dg2_guc_70*.bin /lib/firmware/i915/dg2_huc_gsc.bin
sudo reboot
dmesg | grep -iE '(GuC|HuC) firmware'   # confirm version string bumped and "loaded" / "authenticated" status

# 5. ffmpeg for control encode + verification (system package is fine, does not need
#    to match QSVEnc's linked libav* version — this is an external harness tool)
sudo apt install ffmpeg           # or dnf/pacman equivalent; confirm >= 6.1 for unified vaapi b_depth/async_depth options
ffmpeg -hide_banner -encoders | grep -E 'av1_qsv|av1_vaapi'
ffmpeg -hide_banner -h encoder=av1_vaapi   # inspect actual option list on the installed build (do not assume from docs alone)

# 6. igt-gpu-tools for intel_gpu_top / debugfs helpers
sudo apt install intel-gpu-tools   # Debian/Ubuntu package name
# or: sudo dnf install igt-gpu-tools   # Fedora
intel_gpu_top -L        # list detected devices -- verify it still sees the card after switching to xe
```

### Pure VA-API control-path command (av1_vaapi, quieter path)

```bash
# Mirrors the qsvencc repro command's trigger triad as closely as ffmpeg's vaapi
# encoder allows: HW decode -> P010 10-bit surfaces -> GOP-ref-dist-6 B-pyramid.
ffmpeg -hwaccel vaapi -hwaccel_output_format vaapi -vaapi_device /dev/dri/renderD128 \
  -i /data/downloads/Cold.Eyes.2013.Bluray.Remux.mkv \
  -ss 01:16:14.167 -frames:v 340 \
  -vf 'format=p010,hwupload=extra_hw_frames=32' \
  -c:v av1_vaapi -profile:v main -low_power 0 \
  -bf 5 -b_depth 3 -async_depth 4 -rc_mode ICQ -global_quality 24 \
  -tiles 1x1 \
  "$WORKDIR/chunk923_vaapi.obu"
# NOTE: exact GOP-ref-dist analog is -bf (b-frame count) + -b_depth (pyramid depth);
# there is no single "gop-ref-dist" flag in ffmpeg's vaapi encoder -- b_depth 3 with
# bf 5 approximates GopRefDist 6 (5 B-frames between P-frames, pyramid depth 3).
# Verify actual accepted values with `ffmpeg -h encoder=av1_vaapi` on the installed build.
# Run 3 of these concurrently (923/928/1129 scenes) exactly as with qsvencc, and grade
# with the same PSNR-vs-reference protocol from handoff §4.
```

### Per-frame extraction + PSNR/VMAF verification (no OpenCL dependency)

```bash
# Extract a single frame (offset 299, 0-indexed) from an AV1 .obu/.ivf/mkv container to PNG
ffmpeg -i "$WORKDIR/chunk923.obu" -vf "select='eq(n\,299)'" -vsync 0 -frames:v 1 \
  "$WORKDIR/frame299_test.png"

# Reference frame extracted once from an isolated (non-concurrent) known-clean encode
ffmpeg -i "$WORKDIR/chunk923_reference.obu" -vf "select='eq(n\,299)'" -vsync 0 -frames:v 1 \
  "$WORKDIR/frame299_ref.png"

# PSNR between the two PNGs (fast, no OpenCL, no GPU involved -- pure CPU filter)
ffmpeg -i "$WORKDIR/frame299_test.png" -i "$WORKDIR/frame299_ref.png" \
  -lavfi psnr="stats_file=$WORKDIR/psnr299.log" -f null -
tail -1 "$WORKDIR/psnr299.log"   # psnr_avg:<value> ... ; < 30 dB = corrupted per handoff threshold (expect exactly ~15.74 dB if the known bug)

# VMAF (defense-in-depth full-file gate, ffmpeg built --enable-libvmaf) -- run against
# the full joined movie.obu vs. source, not just the hotspot frame, to catch this
# defect CLASS generically (not just the known offsets):
ffmpeg -i "$WORKDIR/movie.obu" -i /data/downloads/Cold.Eyes.2013.Bluray.Remux.mkv \
  -lavfi "[0:v]scale=1920:1080[dist];[dist][1:v]libvmaf=log_fmt=csv:log_path=$WORKDIR/vmaf.csv" \
  -f null -
# CSV field 16 = vmaf score per frame (per handoff §9 gotcha: field 17 duplicates the
# frame number, and on ru-locale systems the CSV separator/decimal marks can differ --
# force `LC_ALL=C` before running ffmpeg to get a stable `.`-decimal, comma-separated CSV).
```

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Switch to `xe` driver via `force_probe` (persistent modprobe.d + reboot) | Live/temporary `rmmod i915; modprobe xe` without reboot | Don't — `i915` on DG2 typically can't be cleanly unbound/reloaded while a display/render node is active without a full session teardown; the modprobe.d + initramfs + reboot path is the only reliable one documented for discrete GPUs. |
| `av1_vaapi` via system ffmpeg 8.x as the "quieter" control path | `gstreamer`+`vaapiav1enc`/`msdkav1enc` | Only if you need a third *independent* implementation (different surface-pool code than both ffmpeg and qsvencc) for triangulation; higher setup cost, lower payoff than the ffmpeg path already validated for `av1_qsv`. |
| `intel_gpu_top`/fdinfo for concurrency observation | Full IGT test-suite (`igt@gem_*`, `igt@xe_*` kernel selftests) | Only if the host-side levers (Xe/firmware) fail to change reproduction and you need to write a minimal kernel-level reproducer of the aliasing itself for an upstream drm/i915 bug report — that is a much larger investment (building IGT, writing a custom GEM/BO test) and should be a later-phase escalation, not the first tool reached for. |
| `ffmpeg -lavfi psnr`/`libvmaf` for verification | `qsvencc --psnr`/`--ssim` | Never in this project — those flags require an Intel OpenCL ICD that this stack should not depend on (PROJECT.md constraint); even though OpenCL happens to be present in this particular build, don't couple the reproducer/verification harness to it. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Re-patching `qsvencc` `qsv_allocator_va.cpp` / `qsv_pipeline.cpp` surface-attribute / `rt_format` / `VASurfaceAttribUsageHint` lines | Analytically exhausted per handoff §5 — three build cycles already spent; `rt_format` argument is provably inert because `vaCreateSurfaces` is called with an explicit `VASurfaceAttribPixelFormat=VA_FOURCC_P010` that iHD honors regardless; usage-hints don't affect the bitstream; pools are already process-local. | Host-side levers in this document (driver/firmware swap) or the enpipe workaround space (§7 of handoff: `--avsw`, `--jobs 1`, migrate to ffmpeg). |
| `qsvencc --disable-va` | Segfaults 100% on this Linux/iHD combination — dead flag, not a workaround. | N/A — do not include in any test matrix. |
| `qsvencc --async-depth 1` as a fix attempt | Already tested, inert (7/15 corrupted, unchanged) — only touches the AsyncDepth pool member, not the DPB P010 reference pool where the aliasing actually happens. | If testing an async-depth-style lever on the *new* `av1_vaapi` path, that's a different code path and genuinely untested — fine to try there, just don't re-try it against qsvencc. |
| Chasing newer `iHD`/`vpl-gpu-rt`/`libva` userspace versions as the fix | Already swapped iHD 25.2.3 → 26.2.2 plus vpl-gpu-rt/libva 2.23 on the same kernel — zero effect, identical frequency/signature. A 17-source deep-research pass (handoff §5) found no concurrent/multi-session/cross-session fix documented in iHD ≤26.1.5 or vpl-gpu-rt changelogs. | Assume root cause is below the userspace driver; focus all new effort on the kernel driver (`i915` vs `xe`) and firmware (GuC/HuC), not on chasing another point-release of iHD. |
| `qsvencc --psnr`/`--ssim` for verification metrics | Requires OpenCL/Intel ICD — a dependency PROJECT.md explicitly says the reproducer should not require, even where technically available in this build. | External `ffmpeg -lavfi psnr`/`libvmaf` as shown above — pure CPU path, zero GPU/OpenCL coupling, works identically regardless of which kernel driver or firmware is under test. |
| Assuming `intel_gpu_top` "just works" identically after switching to `xe` | Xe support in the igt-gpu-tools *tool itself* (not just its perf library) has lagged and may still be incomplete depending on exact igt-gpu-tools version installed; silently trusting a blank/wrong reading would corrupt your concurrency-observation data the same way the bug corrupts frames. | Verify with `intel_gpu_top -L` immediately after the driver switch; fall back to `/proc/<pid>/fdinfo` (works on both drivers, format differs) if `intel_gpu_top` can't see the Xe-bound device. |

## Stack Patterns by Variant

**If the bug reproduces identically under `xe` (same frequency/signature as `i915`):**
- Root cause is either in shared/duplicated logic between the two drivers (e.g. a common GuC firmware/scheduling-protocol issue rather than driver-specific BO code), or in something even lower (GuC firmware itself, or PCIe/memory controller behavior not driver-specific at all).
- Escalate: try the GuC/HuC firmware bump next (independent variable), then consider this genuinely a firmware or hardware-generation issue worth an upstream drm/i915 **and** drm/xe report (both maintainers should see it, since it's driver-agnostic).
- Do not conclude "Xe doesn't help" from a single run given the baseline's own 33–65% stochastic frequency — run the same 15–20 iteration protocol used for `i915` before comparing.

**If the bug does NOT reproduce under `xe` (0% across ≥15 iterations):**
- This is the sought host-side fix. But first rule out a confound: DG2 lacks HuC support under Xe (see Critical Caveat below), which could mean AV1 low-power BRC (used by `--icq`) silently isn't running the same code path at all under Xe — verify the encode is actually using the intended rate-control mode (check `--check-features`/iHD logs for "low power" vs "normal"/"legacy" encode mode) before attributing the clean result to BO-isolation rather than to an accidental change of encode pipeline stage entirely.
- If confirmed genuine (same encode mode, same triad, just clean under Xe): document exact kernel version, `xe.force_probe`/`i915.force_probe` cmdline, GuC/HuC firmware versions loaded, and `iHD`/libva versions as the reproducible fix recipe for the production host.

**If `av1_vaapi` (ffmpeg, pure libva, oneVPL-runtime-bypassed) is also clean under the same concurrency, on the SAME kernel/driver (`i915`) that corrupts qsvencc:**
- This triangulates the defect specifically to qsvencc's own combined-pool allocator code (both ffmpeg paths — `av1_qsv` via oneVPL and `av1_vaapi` via raw libva — stay clean; only qsvencc's OR-combined `FROM_DECODE|FROM_VPPIN|FROM_ENCODE` pool corrupts), independent of any kernel-level fix. This strengthens (but does not replace) the case for workaround **C** (migrate enpipe to ffmpeg) in the existing §7 solution space, since it shows the *userspace call pattern*, not just the encoder choice, is what matters.

**If `av1_vaapi` also corrupts under concurrency (matching qsvencc's rate, not ffmpeg `av1_qsv`'s 0%):**
- This is new information: it would mean the defect is NOT specific to qsvencc's allocator code but to *some* class of VA surface pool construction that both qsvencc and raw-libva `av1_vaapi` share but oneVPL's `av1_qsv` avoids — re-open investigation into what oneVPL's runtime does differently (likely its own internal pool/allocator abstraction) rather than treating "switch to ffmpeg" as a safe fix.

## Version Compatibility

| Component | Compatible With | Notes |
|-----------|-----------------|-------|
| Kernel 6.19.14 (this environment / affected host) | Both `i915` and `xe` DRM drivers built-in, DG2 supported by both (Xe only via `force_probe`) | Confirmed same kernel version as the original affected host per PROJECT.md context — the "different kernel = free fix" escape is closed; in-place lever testing (this document) is the primary path. |
| `xe.force_probe=56a5` / `i915.force_probe=!56a5` | Arc A380 (PCI 8086:56a5, DG2-128) specifically | Get the exact PCI ID for your card via `lspci -nn \| grep -i vga` / `lspci -nn \| grep 8086` before copying this — other DG2 SKUs (A310/A580/A750/A770) use different IDs (56a0/56a1/etc.), and using the wrong ID silently leaves the card on `i915`. |
| `xe` driver + DG2 | **No HuC firmware support, not planned** (confirmed via Phoronix/dri-devel coverage as of ~Sept 2025; not independently re-confirmed for 2026 in this research pass — re-check `dmesg` live) | HuC is required for AVC/HEVC/VP9/AV1 **low-power** encode bitrate control (CBR/VBR/ICQ), which is the default BRC path Arc GPUs use and which the repro's `--icq 24` almost certainly exercises. Switching to Xe on DG2 may silently force the "normal"/legacy (non-low-power) encode path instead of just changing BO isolation — treat any "Xe fixes it" result as suspect until you've confirmed the encode is using the same BRC mode as under `i915`. |
| ffmpeg 8.x `av1_vaapi` | `libva` 2.x + `iHD` with AV1 encode profile support (already present per PROJECT.md hardware check) | No known version-pinning issue; confirm `-vf format=p010,hwupload` + B-frame options (`-bf`, `-b_depth`) are accepted by your exact installed ffmpeg build via `ffmpeg -h encoder=av1_vaapi` rather than assuming from this document, since option surface has changed across ffmpeg 6.x→8.x HW-encode unification. |
| `libvmaf` | ffmpeg built with `--enable-libvmaf` | Standard distro ffmpeg packages frequently omit `libvmaf` (licensing/build-complexity reasons) — check `ffmpeg -filters \| grep vmaf` before assuming it's available; if absent, PSNR-only verification (no extra build needed) is the fallback already used in the existing harness. |

## Critical Caveat (headline finding, read first)

**Switching Arc A380/DG2 from `i915` to `xe` is the single most promising untried lever per the brief, but it carries a real risk of masking the bug by changing the encode pipeline rather than fixing BO isolation:** Intel's `xe` driver has no HuC firmware support for DG2/Alchemist, and Intel engineers have stated they do not plan to add it (this generation is considered `i915`'s domain; Xe's HuC work targets Meteor Lake and later). HuC is specifically required for the **low-power** AV1/HEVC/VP9/AVC encode bitrate-control path that Arc GPUs use by default (including `--icq`, the rate-control mode in this project's repro command). If HuC doesn't load under Xe, `iHD` may either (a) fail to encode at all, (b) silently fall back to a different, non-low-power encode kernel with different pooling/allocator code paths, or (c) something else undocumented — any of which could make the bug "disappear" under Xe for reasons unrelated to BO/context isolation. **Before concluding "Xe fixes it," always check `dmesg` for GuC/HuC firmware load/auth lines and confirm via `--check-features`/iHD verbose logging that the low-power encode path is actually active on both drivers being compared.** Confidence: MEDIUM (well-corroborated as of ~Sept 2025 via Phoronix/dri-devel reporting; re-verify live since this is exactly the kind of detail that could have changed in the ~10 months since).

## Sources

- [Intel Xe vs. i915 Driver Performance On Linux 6.19 For Arc Alchemist GPUs — Phoronix](https://www.phoronix.com/review/intel-xe-i915-linux-619) — confirms 6.19 kernel context, Xe still optional/non-default for Alchemist, performance gains 15–50% in some workloads. MEDIUM (WebSearch summary, page itself blocked by anti-bot).
- Kernel.org Xe "Merge Acceptance Plan" RFC doc (`gpu/rfc/xe.html`) — confirms `force_probe`/`.require_force_probe` protection stays permanently for platforms like DG2 that were only used to prototype the driver; not a "graduates to default later" situation. HIGH.
- [Intel's Experimental Xe Driver For Linux Lacking HuC Media Support For DG2/Alchemist — Phoronix](https://www.phoronix.com/news/Intel-Xe-DG2-No-HuC) — HuC not implemented for DG2 under Xe, not planned; recommends `i915` for HuC-dependent media on DG2. MEDIUM-HIGH (WebSearch summary; direct fetch blocked by anti-bot Anubis).
- GitHub `intel-gpu/intel-gpu-firmware` issue #5, GitLab `kernel-firmware/drm-firmware` MRs #28/#43 — GuC firmware version lineage for DG2 (`dg2_guc_70.bin`, versions 70.12.1 → 70.45.2 → 70.53.0). MEDIUM.
- Arch Linux `linux-firmware-intel` package file listing (20260622 snapshot) — confirms current `dg2_guc_*.bin`/`dg2_huc_gsc.bin` filenames shipped in a 2026 package build. MEDIUM.
- FFmpeg RELEASE_NOTES / endoflife.date / UbuntuHandbook coverage — FFmpeg 8.0 "Huffman" (Aug 2025), 8.0.3 (2026-06-18) and 8.1.2 (2026-06-17) as current stable lines as of this research date. HIGH.
- `github.com/FFmpeg/FFmpeg` `libavcodec/vaapi_encode_av1.c` (read via WebFetch) — confirms `profile`/`tier`/`level` AVOptions plus shared `HW_BASE_ENCODE_COMMON_OPTIONS`/`VAAPI_ENCODE_COMMON_OPTIONS`/`VAAPI_ENCODE_RC_OPTIONS` macros and `FF_HW_FLAG_B_PICTURES` support. MEDIUM-HIGH (source read via fetch-summarization, not raw diff).
- Community reports (Level1Techs forum, GitHub issues) confirming `-vf format=p010,hwupload` → `av1_vaapi` 10-bit path works in practice. MEDIUM (community, not official docs).
- DeepWiki / Arch manpage for `intel_gpu_top`; xorg-announce igt-gpu-tools 1.29 release note — Xe support added to igt's perf library Sep 2024; `intel_gpu_top` tool-level Xe coverage described as lagging/partial by community reports. MEDIUM.
- Chromium VA-API docs, various community troubleshooting threads — `LIBVA_TRACE`, `LIBVA_MESSAGING_LEVEL` environment variables. HIGH (long-standing, stable, well-documented libva behavior).
- Phoronix "Intel Graphics Continues Work Toward Per-Client Memory Reporting" + `proc_pid_fdinfo.5` patch threads — generic DRM fdinfo (`drm-driver`, `drm-total-local0`/`drm-cycles-*`) supported by both `i915` and `xe`, format differs slightly. MEDIUM-HIGH.
- Existing project documents: `PROJECT.md` (root handoff, full bug context/exhausted results/untried levers), `.planning/PROJECT.md`, `.planning/codebase/STACK.md`, `.planning/codebase/CONCERNS.md` — ground truth for what has already been tried and must NOT be repeated.

---
*Stack research for: host-kernel/driver diagnosis of concurrent QSV AV1 frame corruption on Intel Arc DG2*
*Researched: 2026-07-23*
