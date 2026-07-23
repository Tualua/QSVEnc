# Codebase Structure

**Analysis Date:** 2026-07-23

## Directory Layout

```
QSVEnc/
├── QSVPipeline/         # Core encode pipeline (flat dir, ~700 files, Windows+Linux)
│                        #   qsv_*      QSVEnc-specific (libvpl/MFX) implementation
│                        #   rgy_*      shared with NVEnc/VCEEnc/rkmppenc
│                        #   *.cl       OpenCL kernels for rgy_filter_*.cpp filters
│                        #   convert_*, cpu_info*, gpu_info*, logo*, afs*  shared non-rgy files
├── QSVEncC/             # CLI executable (`QSVEncC.exe`/`QSVEncC`) — entry point + argv wiring
├── QSVEnc/              # AviUtl/AviUtl2 output plugin (.auo / .auo2) — spawns QSVEncC
├── GPUFeatures/          # `--check-features` result dumps per GPU/OS, referenced from Readme.md
├── data/                 # Images/assets used by documentation (install guides, etc.)
├── docker/               # Base Dockerfiles for Linux package builds (per-distro subfolders)
├── build_pkg/            # Linux package build scripting output/config (populated at build time)
├── resource/             # Build-time data assets (e.g. `nnedi3_weight`)
├── PerfMonitor/          # Python-based external perf monitor tool (separate .pyproj)
├── meson_embed/          # Meson build helper/embed scripts (Linux build)
├── clRNG/, cl_perf/      # OpenCL RNG + perf helper libraries (own .vcxproj)
├── .github/workflows/    # CI: build_base_images.yml, build_packages.yml, build_releases.yml
├── ffmpeg_lgpl/          # (submodule/dep, Windows-only) bundled LGPL ffmpeg build — do not modify
├── libvpl/               # (submodule/dep) Intel oneVPL SDK — do not modify
├── cppcodec/ dtl/ json/ tinyxml2/ ttmath/  # (submodules/deps) vendored libraries — do not modify
├── QSVEnc.sln            # Visual Studio solution (Windows build)
├── meson.build, meson_options.txt, makefile  # Linux build (meson-based)
├── build_*.sh            # Linux build helper scripts (deb/rpm/vpl/libdovi/libhdr10plus)
├── QSVEncC_Options.{md,ja.md,cn.md}  # CLI option reference (keep in sync with rgy_cmd.cpp help)
├── Readme.{md,ja.md,cn.md}, Build.{en,ja}.md, Install.{en,ja}.md  # top-level docs
└── CLAUDE.md, AGENTS.md  # contributor/agent guidance (directory map, param-addition rules)
```

## Directory Purposes

**`QSVPipeline/`:**
- Purpose: all encode/decode/filter/device logic; the only place with real architectural layering (two-tier shared/specific split described in `CLAUDE.md`).
- Contains: no subdirectories — every `.h`/`.cpp`/`.cl` file lives at the top level (~700 files total: 363 `rgy_*`, 44 `qsv_*`, 82 `.cl` kernels, plus a handful of other shared prefixes).
- Key files: `qsv_pipeline.h/.cpp` (`CQSVPipeline`, the pipeline orchestrator), `qsv_pipeline_ctrl.h` (`PipelineTask` graph), `qsv_prm.h/.cpp` (`sInputParams`), `qsv_cmd.h/.cpp` (QSV CLI parsing), `rgy_prm.h/.cpp` (shared param structs), `rgy_cmd.h/.cpp` (shared CLI parsing), `rgy_filter.h` (filter base class), `rgy_input.h`/`rgy_output.h` (I/O base classes).

**`QSVEncC/`:**
- Purpose: standalone CLI binary; thin — almost all logic lives in `QSVPipeline`.
- Contains: `QSVEncC.cpp` (main + `run_encode`/`run_benchmark`), version resource files, Windows manifests, `.vcxproj`.
- Key files: `QSVEncC.cpp`.

**`QSVEnc/` (AviUtl plugin):**
- Purpose: GUI-configured output plugin for AviUtl (Win32, `.auo`) and AviUtl2 (x64, `.auo2`); translates GUI settings into a `QSVEncC` command line and manages the child process.
- Contains: `QSVEnc.cpp` (plugin entry, `GetOutputPluginTable`, `func_output`/`func_output2`), `.ini`/`.lng` localization files (en/ja/zh), installer scripts (`7zInstallerConfig.txt`, `7zSD.noadmin.sfx`, `QSVEnc_uninstall.bat`), `auo.h`/`auo_version.h` (AviUtl SDK glue), `output.h`/`output2.h`/`logger2.h`.
- Key files: `QSVEnc.cpp`.

**`GPUFeatures/`:**
- Purpose: reference output of `QSVEncC --check-features` for various GPUs/OSes; linked from `Readme.md` so users can check HW support without running the tool themselves.
- Contains: plain-text dumps, one file per GPU+OS combination (e.g. `QSVEnc_ADL_i9_12900K_Win.txt`).
- Generated: manually captured and committed (not build-generated). Committed: Yes.

**`docker/`:**
- Purpose: base Dockerfiles for reproducible Linux package builds, one subfolder per distro (`docker_fedora41`, `docker_ubuntu2004`, `docker_ubuntu2204`, `docker_ubuntu2404`), plus `build_ffmpeg_dll.sh`.
- Committed: Yes.

**`build_pkg/`:**
- Purpose: Linux package (`.deb`/`.rpm`) creation working area, driven by `build_deb.sh`/`build_rpm.sh`/`build_pkg_local.sh` at the repo root.
- Generated: Yes (populated during package builds; empty in a fresh checkout).

**Vendored dependency directories (`libvpl/`, `ffmpeg_lgpl/`, `cppcodec/`, `dtl/`, `json/`, `tinyxml2/`, `ttmath/`, `PerfMonitor/`, `clRNG/`, `cl_perf/`):**
- Purpose: third-party or auxiliary code. Per `CLAUDE.md`: "基本触らない" (do not modify).
- Committed: Yes, generally as git submodules (see `.gitmodules`) or vendored source trees.

## Key File Locations

**Entry Points:**
- `QSVEncC/QSVEncC.cpp`: CLI `_tmain` → `run()` → `run_encode()`/`run_benchmark()`.
- `QSVEnc/QSVEnc.cpp`: AviUtl plugin `GetOutputPluginTable()` export → `func_output()`/`func_output2()`.

**Configuration:**
- `QSVPipeline/qsv_prm.h` / `.cpp`: `sInputParams` definition, defaults, QSV-only parameter validation.
- `QSVPipeline/rgy_prm.h` / `.cpp`: shared parameter structs (`RGYParamVpp`, `RGYParamCommon`, `RGYParamControl`, `RGYParamInput`, `RGYParamParallelEnc`, ...).
- `meson_options.txt`, `meson.build`: Linux build feature toggles (`enable_vapoursynth`, `enable_avisynth`, `enable_libplacebo`, `enable_vulkan`, `enable_openvino`, `opencl_headers`).
- `QSVEnc.sln`, `*.vcxproj`/`*.vcxproj.filters`: Windows/Visual Studio build configuration.

**Core Logic:**
- `QSVPipeline/qsv_pipeline.cpp`: pipeline `Init`/`CreatePipeline`/`RunEncode2` (the encode orchestration — see ARCHITECTURE.md for data flow).
- `QSVPipeline/qsv_pipeline_ctrl.h`: `PipelineTask` graph node definitions.
- `QSVPipeline/rgy_filter_*.[h/cpp]` (+ matching `.cl`): individual VPP filter implementations.
- `QSVPipeline/rgy_input_*.[h/cpp]`, `rgy_output*.[h/cpp]`: demux/mux backends.

**Testing:**
- No dedicated automated test suite/directory was found in this repository (see TESTING.md / CONVENTIONS.md if generated; verification here is primarily manual via `GPUFeatures/` captures and CI build matrices in `.github/workflows/`).

## Naming Conventions

**Files:**
- `qsv_<topic>.h` / `qsv_<topic>.cpp`: QSVEnc-specific implementation (libvpl/MFX-only concerns). Example: `qsv_allocator_d3d11.cpp`.
- `rgy_<topic>.h` / `rgy_<topic>.cpp`: shared across QSVEnc/NVEnc/VCEEnc/rkmppenc. Example: `rgy_bitstream.cpp`.
- `rgy_filter_<name>.h/.cpp`: one VPP filter's host-side (C++) implementation; paired `rgy_filter_<name>.cl` holds the OpenCL kernel source for the same filter. Multi-stage filters split further, e.g. `rgy_filter_afs_analyze.cpp` / `rgy_filter_afs_filter.cpp` / `rgy_filter_afs_merge.cpp` / `rgy_filter_afs_synthesize.cpp` for one logical filter (`afs`).
- `rgy_input_<backend>.h/.cpp` / no equivalent single `rgy_output_<backend>` pattern beyond `rgy_output_avcodec.*` — most output logic lives directly in `rgy_output.cpp` plus the avcodec-specific muxer file.
- SIMD-specialized translation units use an `_<isa>` suffix compiled with per-file ISA flags: `convert_csp_avx2.cpp`, `convert_csp_sse41.cpp`, `rgy_bitstream_avx512bw.cpp`, `rgy_memmem_avx2.cpp`, `rgy_faw_avx2.cpp`.
- `*_version.h` / `*_version.rc`: per-target version metadata (`rgy_version.h` shared macros incl. `ENCODER_QSV`/`ENCODER_NVENC`/`ENCODER_VCEENC`/`ENCODER_MPP`; `QSVEncC_version.h`, `auo_version.h` per-binary).

**Directories:**
- Top-level directories map 1:1 to build targets/binaries (`QSVPipeline`, `QSVEncC`, `QSVEnc`) or to a single concern (`docker`, `data`, `resource`, `GPUFeatures`, `build_pkg`).
- `QSVPipeline` itself is intentionally flat (no subfolders) — file *prefix* (`qsv_`/`rgy_`) is the organizing convention, not directory nesting; Visual Studio's `.vcxproj.filters` file provides virtual grouping in the IDE without an underlying real directory split.

## Where to Add New Code

**New CLI/shared parameter:**
- Decide QSV-only vs shared-across-encoders first (see `CLAUDE.md` "パラメータ追加" table).
- QSV-only: add field to `sInputParams` in `QSVPipeline/qsv_prm.h`/`.cpp`; add parsing/gen-cmd/help in `QSVPipeline/qsv_cmd.h`/`.cpp`.
- Shared: add field to the relevant `RGYParam*` struct in `QSVPipeline/rgy_prm.h`/`.cpp`; add parsing/gen-cmd/help in `QSVPipeline/rgy_cmd.h`/`.cpp`.
- Document in `QSVEncC_Options.md` and `QSVEncC_Options.ja.md` (keep both in sync with the new `rgy_cmd.cpp`/`qsv_cmd.cpp` help text).

**New VPP filter:**
- Implementation: `QSVPipeline/rgy_filter_<name>.h` + `.cpp`, subclassing `RGYFilterBase`/`RGYFilter` (`rgy_filter.h`) and defining an `RGYFilterParam<Name>` subclass.
- OpenCL kernel (if GPU-accelerated): `QSVPipeline/rgy_filter_<name>.cl`, loaded/built by the host-side `.cpp`.
- Wiring: add to the VPP filter-list construction in `CQSVPipeline::InitFiltersCreateVppList`/`AddFilterOpenCL` (`qsv_pipeline.cpp`) and to CLI parsing (`parse_one_vpp_option` in `rgy_cmd.cpp`, `RGYParamVpp` in `rgy_prm.h`).

**New input/output backend:**
- Implementation: `QSVPipeline/rgy_input_<backend>.h/.cpp` subclassing `RGYInput` (`rgy_input.h`), or extend `rgy_output.h`/`rgy_output_avcodec.*` for a new muxer path.
- Wiring: hook selection logic into `CQSVPipeline::InitInput`/`InitOutput` (`qsv_pipeline.cpp`).

**New pipeline stage (task):**
- Implementation: add a `PipelineTask` subclass in `QSVPipeline/qsv_pipeline_ctrl.h`, implement `sendFrame`/`getOutput`/`requiredSurfIn`/`requiredSurfOut`.
- Wiring: insert into the task vector in `CQSVPipeline::CreatePipeline` (`qsv_pipeline.cpp:5445`) at the correct point in the chain; update `isMFXTask()`/allocation priority if it touches MFX surfaces directly.

**Utilities:**
- Shared low-level helpers (string/bitstream/thread/file helpers usable by any of the four encoder products) go in an appropriately named `rgy_*` file at the top of `QSVPipeline/` (e.g. `rgy_util.h`, `rgy_filesystem.cpp`, `rgy_thread.h`) — never introduce a new subdirectory, per the existing flat-layout convention.
- QSV-only helpers (device/session/allocator glue) go in a `qsv_*` file instead.

## Special Directories

**`build_pkg/`:**
- Purpose: scratch area for Linux `.deb`/`.rpm` packaging scripts.
- Generated: Yes.
- Committed: Directory structure only (contents produced at build time, largely gitignored).

**`GPUFeatures/`:**
- Purpose: static reference data (feature-check dumps), not code.
- Generated: No (manually captured from real hardware runs).
- Committed: Yes.

**`data/`:**
- Purpose: images/screenshots embedded in Markdown docs (Readme/Install guides).
- Generated: No.
- Committed: Yes.

**`libvpl/`, `ffmpeg_lgpl/`, and other vendored dep directories:**
- Purpose: third-party dependency source, generally consumed via git submodule.
- Generated: No (external upstream code).
- Committed: Submodule reference committed; contents tracked upstream, not modified locally (see `CLAUDE.md`: "基本触らない").

---

*Structure analysis: 2026-07-23*
