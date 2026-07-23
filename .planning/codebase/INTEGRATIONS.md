# External Integrations

**Analysis Date:** 2026-07-23

## Hardware / Vendor SDKs

**Intel Quick Sync Video (QSV) via oneVPL/libvpl:**
- Submodule: `libvpl/` (https://github.com/intel/libvpl.git), built from source (CMake) and statically linked (`libvpl.a`)
- Session/device management: `QSVPipeline/qsv_session.cpp`, `QSVPipeline/qsv_device.cpp`, `QSVPipeline/qsv_hw_device.cpp`
- D3D9/D3D11 hardware surface allocators (Windows): `QSVPipeline/qsv_hw_d3d9.cpp`, `QSVPipeline/qsv_hw_d3d11.cpp`, `QSVPipeline/qsv_allocator_d3d9.cpp`, `QSVPipeline/qsv_allocator_d3d11.cpp`
- System-memory allocator: `QSVPipeline/qsv_allocator_sys.cpp`
- Decode: `QSVPipeline/qsv_mfx_dec.cpp`; VPP (video post-processing) native MFX path: `QSVPipeline/qsv_vpp_mfx.cpp`
- Capability/feature querying (`--check-features`): `QSVPipeline/qsv_query.cpp`, results catalogued under `GPUFeatures/`
- Device identification (Intel GPU PCI IDs, generation detection): `QSVPipeline/DeviceId.cpp`, `QSVPipeline/gpu_info.cpp`, `QSVPipeline/gpuz_info.cpp`
- Experimental oneVPL API surface enabled (`USE_ONEVPL=1`, `ONEVPL_EXPERIMENTAL=1`, `QSVPipeline/rgy_version.h:70-71`)

**VA-API (Linux only):**
- `libva`, `libva-drm`, `libva-x11`, `libdrm` — Meson deps (`meson.build:36-41`), gate `LIBVA_SUPPORT`/`LIBVA_DRM_SUPPORT`/`LIBVA_X11_SUPPORT` compile flags
- Runtime driver: `intel-media-va-driver-non-free` (`iHD` VA-API driver), selected via `LIBVA_DRIVER_NAME` env var

**OpenCL (Khronos):**
- Used for the custom GPU-side video filter pipeline (denoise, deband, resize, deinterlace/afs, curves, decimate, chromashift, colorfix, convolution3d, deblock, degrain, bwdif, cas, anime4k, etc.)
- Kernel sources: `QSVPipeline/rgy_filter_*.cl`, `QSVPipeline/rgy_dummy_load.cl`
- Host glue: `QSVPipeline/cl_func.cpp`/`.h` (per CLAUDE.md, shared across QSVEnc/NVEnc/VCEEnc/rkmppenc)
- Headers required at build time (`opencl-headers` package on Linux, `$(INTELOCLSDKROOT)`/`OPENCL_HEADERS` env var on Windows)

**clRNG (GPU random number generation):**
- Submodule `clRNG/` (https://github.com/clMathLibraries/clRNG.git), own `clRNG.vcxproj` on Windows
- Used by dithering/deband filter for pseudo-random noise generation: `QSVPipeline/rgy_filter_deband.cpp`, `QSVPipeline/rgy_filter_deband_gen_rand.cl`, `QSVPipeline/rgy_resource.cpp`

**Vulkan / libplacebo (optional, off by default):**
- `enable_vulkan`/`enable_libplacebo` Meson options (default `false`); requires libplacebo API >= 338
- Device/context: `QSVPipeline/rgy_device_vulkan.cpp`, `QSVPipeline/rgy_vulkan.cpp`
- Filter: `QSVPipeline/rgy_filter_libplacebo.cpp` (advanced GPU scaling/tone-mapping/debanding)

**OpenVINO (optional ONNX inference, `--vpp-onnx` filter):**
- C API headers only at compile time (`enable_openvino`, default `true`); runtime `.dll`/`.so` is dynamically loaded (not link-time linked) — `QSVPipeline/rgy_filter_onnx.cpp`
- Headers auto-fetched from `https://github.com/openvinotoolkit/openvino` (tag `2026.2.0`) if not found via pkg-config, extracted into build-tree `external_headers/`
- Model metadata registry uses nlohmann::json: `QSVPipeline/rgy_model_registry.cpp` + `json/json.hpp`
- Windows: requires `OPENVINO_PATH` env var pointing at extracted OpenVINO Runtime archive; user must run OpenVINO's `setupvars.bat` or place its DLL dir on `PATH` at runtime

## Multimedia / Container-Format Integrations

**FFmpeg (libavutil/libavcodec/libavformat/libavfilter/libavdevice/libswresample):**
- Required system dependency on Linux (`meson.build:88-103`), or prebuilt DLL bundle on Windows (`ffmpeg_dlls_for_hwenc`, fetched per `Build.en.md`)
- Reader/writer/muxer/demuxer: `QSVPipeline/rgy_input_avcodec.cpp` (and sibling `rgy_avutil.cpp`, `rgy_avlog.cpp`, `rgy_bitstream_aac.cpp`)
- API-availability probing at build time for cross-FFmpeg-version compatibility (`AV_CHANNEL_LAYOUT_STRUCT_AVAIL`, `AV_FRAME_DURATION_AVAIL`, `AVCODEC_PAR_CODED_SIDE_DATA_AVAIL`, `ENABLE_AVCODEC_ITERATE`) — probed live in `meson.build:433-455`, results written to generated `QSVPipeline/rgy_config.h`
- Supported FFmpeg versions: 4.x–7.x (`Build.en.md`)

**VapourSynth (optional scripted frame server):**
- `enable_vapoursynth` Meson option (default `true`); requires both V3 (`VapourSynth.h`/`VSScript.h`) and V4 (`VSScript4.h`) headers
- Headers auto-fetched from `https://github.com/vapoursynth/vapoursynth` tag `R72` if system package absent
- Windows: `VAPOURSYNTH_SDK` env var for include path

**AviSynth+ (optional scripted frame server):**
- `enable_avisynth` Meson option (default `true`); requires `avisynth_c.h`
- Headers auto-fetched from `https://github.com/AviSynth/AviSynthPlus` tag `v3.7.5` if absent
- Windows: `AVISYNTH_SDK` env var for include path
- Interface version pinned via `AVS_INTERF_VER` (12 on Linux when enabled, 11 in the Windows-oriented `rgy_version.h`)

**libass (optional subtitle burn-in):**
- `enable_libass` Meson option (default `true`), `ENABLE_LIBASS_SUBBURN` flag
- Windows: `libass/include` under solution dir

**Dolby Vision (libdovi) and HDR10+ (libhdr10plus-rs):**
- Rust crates, built via `cargo` + `cargo-c` (`cargo cinstall`) when not present as system packages
- Build scripts: `build_libdovi.sh`, `build_libhdr10plus.sh`; invoked automatically from `meson.build` (`ENABLE_LIBDOVI`, `ENABLE_LIBHDR10PLUS`)
- Metadata parsing: RPU parser (`libdovi/rpu_parser.h`), HDR10+ JSON parser (`libhdr10plus-rs/hdr10plus.h`)

**libvmaf (optional quality metric):**
- Never link-time linked; loaded dynamically at runtime via `dlopen` (Linux, `libvmaf.so`) or `LoadLibrary` (Windows, `libvmaf.dll`) — `QSVPipeline/rgy_libvmaf.cpp:37-50`
- Currently disabled in the shipped feature-flag header (`ENABLE_VMAF 0`, `QSVPipeline/rgy_version.h:116`)

## Data Storage

**Databases:**
- None — this is a native CLI/plugin video encoder, not a networked service

**File Storage:**
- Local filesystem only: input media files, output bitstreams/containers, chapter files (XML via `tinyxml2`, `QSVPipeline/rgy_chapter.cpp`), logo/watermark overlay files (`QSVPipeline/logo.cpp`), device/feature cache (`QSVPipeline/rgy_device_info_cache.cpp`)

**Caching:**
- Local on-disk device/capability cache only (`QSVPipeline/rgy_device_info_cache.cpp`) — no remote cache service

## Authentication & Identity

- Not applicable — no auth flows, no user accounts, no network-facing API surface

## Monitoring & Observability

**Error Tracking:**
- None (no external crash/error reporting service). Internal error codes defined in `QSVPipeline/rgy_err.cpp`

**Logs:**
- Local logging only, `QSVPipeline/rgy_avlog.cpp` (bridges FFmpeg's av_log to the project's own logger) and the project's own log framework (referenced throughout `rgy_*` files); AviUtl plugin has its own logger (`QSVEnc/logger2.h`)

**Performance Monitoring:**
- `PerfMonitor/` — separate companion Python tool (own `.pyproj`, listed in `QSVEnc.sln`), not linked into the encoder binary; used for external performance measurement during development, not a runtime dependency

## CI/CD & Deployment

**Hosting:**
- No hosted/cloud deployment — distributed as downloadable binaries/packages (GitHub Releases implied by `Build.en.md` download links)

**CI Pipeline:**
- GitHub Actions: `.github/workflows/build_base_images.yml` (builds/pushes Docker base images used for Linux builds), `.github/workflows/build_packages.yml` (builds `.deb`/`.rpm` packages via `build_deb.sh`/`build_rpm.sh`/`build_pkg/`), `.github/workflows/build_releases.yml` (builds release binaries for Windows/Linux)
- Docker images: `docker/docker_ubuntu2004`, `docker_ubuntu2204`, `docker_ubuntu2404`, `docker_fedora41` — each installs Intel driver packages, FFmpeg build deps, Rust/cargo-c, and clones `rigaya/build_scripts` to build the FFmpeg DLL package (`docker/build_ffmpeg_dll.sh`)

## External Package Repositories

**Intel GPU driver repository (Linux):**
- `https://repositories.intel.com/gpu/ubuntu` (or legacy `https://repositories.intel.com/graphics/`) — apt repo for `intel-media-va-driver-non-free`, `intel-opencl-icd` (documented in `Build.en.md`, mirrored in `docker/docker_ubuntu2404`)

**GitHub release/source fetches performed by the build itself:**
- `https://github.com/rigaya/ffmpeg_dlls_for_hwenc` — prebuilt FFmpeg DLL bundle for Windows builds (manual download step, `Build.en.md`)
- `https://github.com/rigaya/build_scripts` — FFmpeg DLL build scripts used inside Docker images (`docker/docker_ubuntu2404:4-5`)
- `https://github.com/vapoursynth/vapoursynth` (tag R72) — VapourSynth headers, auto-fetched by `meson.build` when missing
- `https://github.com/AviSynth/AviSynthPlus` (tag v3.7.5) — AviSynth+ headers, auto-fetched by `meson.build` when missing
- `https://github.com/openvinotoolkit/openvino` (tag 2026.2.0) — OpenVINO C API headers, auto-fetched by `meson.build` when missing
- crates.io via `cargo install cargo-c` — Rust build tooling for `libdovi`/`libhdr10plus-rs`

## Webhooks & Callbacks

**Incoming:**
- None

**Outgoing:**
- None (fully offline/local encoding tool; no telemetry or network calls detected in source)

---

*Integration audit: 2026-07-23*
