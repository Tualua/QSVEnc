<!-- refreshed: 2026-07-23 -->
# Architecture

**Analysis Date:** 2026-07-23

## System Overview

```text
┌───────────────────────────────────────────────────────────────────────────┐
│  Frontends (entry points)                                                  │
├───────────────────────────────┬───────────────────────────────────────────┤
│  QSVEncC (CLI)                │  QSVEnc (AviUtl / AviUtl2 output plugin)   │
│  `QSVEncC/QSVEncC.cpp`        │  `QSVEnc/QSVEnc.cpp` (spawns QSVEncC.exe)  │
└───────────────┬───────────────┴───────────────────┬───────────────────────┘
                │                                     │ (pipe/process, not linked)
                ▼                                     ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  QSVEnc-specific implementation layer                                      │
│  `QSVPipeline/qsv_cmd.[h/cpp]`  (CLI parsing, QSV-only options)            │
│  `QSVPipeline/qsv_prm.[h/cpp]`  (`sInputParams`, QSV-only parameter fields) │
│  `QSVPipeline/qsv_pipeline.[h/cpp]` (`CQSVPipeline` — pipeline builder)     │
│  `QSVPipeline/qsv_hw_*`, `qsv_allocator_*`, `qsv_session`, `qsv_device`     │
│  `QSVPipeline/qsv_mfx_dec.*`, `qsv_vpp_mfx.*` (libvpl/MFX dec & VPP wraps)  │
└───────────────┬─────────────────────────────────────────────────────────┬─┘
                │ includes / extends                                      │
                ▼                                                         ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  Shared encoder core (`rgy_*`) — common to QSVEnc/NVEnc/VCEEnc/rkmppenc     │
│  `rgy_cmd.[h/cpp]`   shared CLI option parsing/help/gen-cmd                 │
│  `rgy_prm.[h/cpp]`   shared parameter structs (RGYParamVpp/Common/Control…) │
│  `rgy_pipeline_ctrl` concept: `PipelineTask` graph (see qsv_pipeline_ctrl.h)│
│  `rgy_input*.[h/cpp]` / `rgy_output*.[h/cpp]`  demux/mux & raw I/O          │
│  `rgy_filter*.[h/cpp]` + `*.cl`  OpenCL/CPU video filters (VPP)             │
│  `rgy_opencl*`, `rgy_vulkan`, `rgy_device_*`  GPU device/runtime plumbing   │
└───────────────┬─────────────────────────────────────────────────────────┬─┘
                │                                                         │
                ▼                                                         ▼
┌───────────────────────────────────────────────────────────────────────────┐
│  External libs / OS & HW APIs                                              │
│  `libvpl` (Intel oneVPL / MFX), OpenCL runtime, libavcodec/format/filter    │
│  (ffmpeg_lgpl on Windows), VA-API / D3D9 / D3D11, VapourSynth/AviSynth SDKs │
└───────────────────────────────────────────────────────────────────────────┘
```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| `QSVEncC` CLI frontend | Parse argv, build `sInputParams`, own process lifetime, run/benchmark modes | `QSVEncC/QSVEncC.cpp` |
| AviUtl/AviUtl2 plugin | Translate AviUtl GUI config into a `QSVEncC` command line and spawn/monitor the child process | `QSVEnc/QSVEnc.cpp`, `QSVEnc/output.h`, `QSVEnc/output2.h` |
| `CQSVPipeline` | Core pipeline object: init devices/session, build filter graph, own `PipelineTask` chain, run the encode loop | `QSVPipeline/qsv_pipeline.h`, `QSVPipeline/qsv_pipeline.cpp` |
| `PipelineTask` hierarchy | Node in the frame-processing graph (input, decode, vpp, filter, encode, output); defines `sendFrame`/`getOutput` contract | `QSVPipeline/qsv_pipeline_ctrl.h` |
| `RGYFilterBase`/`RGYFilter` | Base class for all VPP/OpenCL filters (denoise, resize, deinterlace, etc.) | `QSVPipeline/rgy_filter.h`, `QSVPipeline/rgy_filter_*.[h/cpp]` |
| `RGYInput` hierarchy | Abstracts frame/demux sources: avcodec (ffmpeg), raw, avi, avs, vpy (VapourSynth), shared-memory (`rgy_input_sm`) | `QSVPipeline/rgy_input.h`, `rgy_input_avcodec.*`, `rgy_input_raw.*`, `rgy_input_avi.*`, `rgy_input_avs.*`, `rgy_input_vpy.*`, `rgy_input_sm.*` |
| `RGYOutput` hierarchy | Abstracts muxing/output: raw bitstream writer, avcodec (ffmpeg) muxer | `QSVPipeline/rgy_output.h`, `rgy_output_avcodec.*` |
| `QSVDevice` / `qsv_hw_device` | HW device + session/allocator management (D3D9/D3D11/VA-API) | `QSVPipeline/qsv_device.*`, `qsv_hw_device.*`, `qsv_hw_d3d9.*`, `qsv_hw_d3d11.*`, `qsv_hw_va*.*` |
| `QSVMfxDec` / `QSVVppMfx` | Wrap libvpl MFX decode/VPP session objects as `PipelineTask` producers/consumers | `QSVPipeline/qsv_mfx_dec.*`, `qsv_vpp_mfx.*` |
| `RGYParallelEnc` | Multi-GPU/multi-process parallel encode coordination (splits video into chunks, spawns child encoders, joins bitstreams) | `QSVPipeline/rgy_parallel_enc.*` |
| `RGYOpenCLContext` | OpenCL context/queue/kernel management shared by all OpenCL-based filters | `QSVPipeline/rgy_opencl.*` |

## Pattern Overview

**Overall:** Layered, two-tier "shared core + product-specific shell" architecture, wrapped around a **task-graph pipeline** for frame processing (not a classic MVC/service-layer app). Each supported encoder product (QSVEnc, NVEnc, VCEEnc, rkmppenc) is a separate repo/build that shares the `rgy_*` core files verbatim and layers a small number of product-specific files (`qsv_*` here) on top.

**Key Characteristics:**
- Single-process, single-pipeline-per-encode C++17 codebase (no framework, no DI container); polymorphism via abstract base classes (`RGYInput`, `RGYOutput`, `RGYFilterBase`, `PipelineTask`).
- Encoder-family differentiation is done at compile time via preprocessor macros (`ENCODER_QSV`, `ENCODER_NVENC`, `ENCODER_VCEENC`, `ENCODER_MPP`, defined in `QSVPipeline/rgy_version.h`) inside otherwise-shared `rgy_*` files, rather than runtime polymorphism across encoder types.
- The AviUtl plugin (`QSVEnc/`) is a thin GUI shell: it never links the pipeline directly — it builds a CLI string and launches `QSVEncC` as a child process, capturing progress via log/pipe.
- Video processing (VPP/filters) is modeled as a directed chain of `PipelineTask` nodes threaded through `MFXVideoSession` (libvpl) and/or `RGYOpenCLContext` (OpenCL), with explicit sync points wherever the chain crosses between MFX-space and OpenCL-space (`PipelineTask::requireSync`).

## Layers

**Frontend (product entry points):**
- Purpose: turn user input (argv or AviUtl GUI state) into a filled `sInputParams` struct and invoke the pipeline.
- Location: `QSVEncC/QSVEncC.cpp`, `QSVEnc/QSVEnc.cpp`
- Contains: `main`/`_tmain`, AviUtl `OUTPUT_PLUGIN_TABLE` callback implementations (`func_output`, `func_config`, ...), benchmark-mode driver.
- Depends on: `qsv_cmd`, `qsv_prm`, `qsv_pipeline` (CLI only — the AviUtl plugin depends on nothing from `QSVPipeline` and instead shells out).
- Used by: end users / AviUtl host application.

**QSV-specific layer (`qsv_*`):**
- Purpose: everything that is only meaningful because the encoder is Intel QSV via libvpl/MFX — device/session/allocator management, MFX decode & VPP wrapping, QSV-only parameters (rate control modes, HyperMode, hevc_ctu, etc.).
- Location: `QSVPipeline/qsv_*.[h/cpp]`
- Contains: `CQSVPipeline`, `QSVDevice`, `QSVAllocator*`, `QSVMfxDec`, `QSVVppMfx`, `sInputParams`, MFX-session helpers.
- Depends on: libvpl (`libvpl/`), shared `rgy_*` layer.
- Used by: `QSVEncC` frontend; conceptually mirrored by `NVEncCore`/`VCECore`/`MPPCore` in the sibling repos.

**Shared encoder core (`rgy_*`):**
- Purpose: logic common to all four encoder products — CLI plumbing, parameter structs, input/output demux-mux, the OpenCL-based VPP filter library, device/perf utilities.
- Location: `QSVPipeline/rgy_*.[h/cpp]`, plus common non-`rgy_` files called out in `CLAUDE.md` (`afs*`, `cl_func*`, `convert_*`, `cpu_info*`, `gpu_info*`, `logo*`).
- Contains: `RGYInput`/`RGYOutput` hierarchies, `RGYFilterBase` and ~70 concrete filters (`rgy_filter_*.cpp` + matching `.cl` OpenCL kernels), `rgy_prm.h` (`RGYParamVpp`, `RGYParamCommon`, `RGYParamControl`, ...), `rgy_cmd.cpp` (shared option parsing/help), `rgy_opencl.*`, `rgy_parallel_enc.*`.
- Depends on: libavcodec/format/filter (`ENABLE_AVSW_READER`), OpenCL runtime, optional VapourSynth/AviSynth SDKs, optional libplacebo/libdovi/libhdr10plus/onnxruntime/openvino.
- Used by: `qsv_*` layer (and, in sibling repos, `nvenc_*`/`vce_*`/`mpp_*` layers).

**Pipeline task graph:**
- Purpose: represent the frame-processing pipeline as an ordered vector of `PipelineTask` objects, each pulling from its predecessor's output queue and pushing to its own.
- Location: `QSVPipeline/qsv_pipeline_ctrl.h` (`PipelineTask` base + `PipelineTaskInput`, `PipelineTaskMFXDecode`, `PipelineTaskAudio`, `PipelineTaskTrim`, `PipelineTaskCheckPTS`, `PipelineTaskMFXVpp`, `PipelineTaskOpenCL`, `PipelineTaskVideoQualityMetric`, `PipelineTaskMFXEncode`, `PipelineTaskOutputRaw`, `PipelineTaskParallelEncBitstream`)
- Contains: per-task surface/queue management, MFX session pointer, allocation-priority ordering (encode tasks allocate first), sync-requirement detection between MFX and non-MFX neighbors.
- Depends on: `qsv_allocator`, `qsv_mfx_dec`, `qsv_vpp_mfx`, `rgy_filter`, `rgy_opencl`.
- Used by: `CQSVPipeline::CreatePipeline` / `CQSVPipeline::RunEncode2` (`QSVPipeline/qsv_pipeline.cpp`).

## Data Flow

### Primary Encode Path

1. **Argument parsing / config load** — `QSVEncC/QSVEncC.cpp: run()` calls `parse_cmd()` (`QSVPipeline/qsv_cmd.cpp`) to populate `sInputParams` (QSV fields) plus shared `RGYParamCommon`/`RGYParamVpp`/`RGYParamControl` (`QSVPipeline/rgy_cmd.cpp`).
2. **Pipeline construction** — `run_encode()` (`QSVEncC/QSVEncC.cpp:819`) creates a `CQSVPipeline` and calls `Init()` (`QSVPipeline/qsv_pipeline.cpp:4913`), which in turn calls `InitLog`, `InitSession`/device selection, `InitInput` (`qsv_pipeline.cpp:2051`, builds an `RGYInput` reader — avcodec/raw/avs/vpy/avi/sm), `InitFilters` (`qsv_pipeline.cpp:4090`, builds the VPP filter chain — MFX VPP blocks and/or OpenCL `RGYFilter` blocks), `InitOutput` (`qsv_pipeline.cpp:1982`, builds an `RGYOutput` writer), and `InitMfxEncode`.
3. **Pipeline graph assembly** — `CQSVPipeline::CreatePipeline()` (`qsv_pipeline.cpp:5445`) appends `PipelineTask` nodes in order: `PipelineTaskInput`/`PipelineTaskMFXDecode` → optional `PipelineTaskAudio` → optional `PipelineTaskTrim` → `PipelineTaskCheckPTS` → one task per VPP filter block (`PipelineTaskMFXVpp` for MFX-native VPP, `PipelineTaskOpenCL` for OpenCL filter chains) → optional `PipelineTaskVideoQualityMetric` (SSIM/VMAF) → `PipelineTaskMFXEncode` or `PipelineTaskOutputRaw`.
4. **Encode loop** — `CQSVPipeline::RunEncode2()` (`qsv_pipeline.cpp:5554`) drives the task graph: repeatedly calls `sendFrame()`/`getOutput()` on each task in order, using a `dataqueue` of `PipelineTaskData` to shuttle frames/bitstreams downstream, synchronizing (`requireSync`) whenever a hop crosses the MFX/OpenCL boundary, until abort or EOF (`RGY_ERR_MORE_DATA`).
5. **Frame emission** — the terminal task (`PipelineTaskMFXEncode` or `PipelineTaskOutputRaw`) writes encoded bitstream via the `RGYOutput` writer (`QSVPipeline/rgy_output*.cpp`), which muxes via libavformat (`rgy_output_avcodec.cpp`) or writes raw ES.
6. **Shutdown** — `pPipeline->Close()` releases devices, sessions, OpenCL context, and filters.

### AviUtl Plugin Path (indirect frontend)

1. AviUtl/AviUtl2 calls `func_output(OUTPUT_INFO *oip)` (`QSVEnc/QSVEnc.cpp:222`).
2. Plugin loads/merges GUI config (`CONF_GUIEX`), builds encoder parameters (`init_enc_prm`/`set_enc_prm`), and constructs a `QSVEncC` command line string.
3. Plugin spawns `QSVEncC` as a child process (`video_output`/`audio_output` task functions) and streams frame/audio data to it, monitoring its log/progress output.
4. On completion, plugin muxes outputs (`mux()`) and optionally runs pre/post batch files.
5. The AviUtl plugin process never links against `QSVPipeline` directly — all encode logic and HW access happens inside the spawned `QSVEncC` process.

**State Management:**
- No global application state/singleton store; state lives on the `CQSVPipeline` instance (devices, sessions, task vector, status) and is destroyed with it. `EncodeStatus`/`EncodeStatusData` (`rgy_status.*`) tracks progress and is polled by both the CLI and the AviUtl plugin (via log window) for percent-complete/fps display.
- The AviUtl plugin keeps its own transient state in `PRM_ENC`/`CONF_GUIEX` structs (`QSVEnc/*`) which is serialized to `.stg` config files between runs.

## Key Abstractions

**`sInputParams` / `RGYParam*` two-layer parameter model:**
- Purpose: separate QSV/libvpl-only knobs from knobs shared across QSVEnc/NVEnc/VCEEnc/rkmppenc, so the shared `rgy_*` layer never depends on QSV-specific types.
- Examples: `QSVPipeline/qsv_prm.h` (`struct sInputParams` — embeds `RGYParamInput inprm`, `RGYParamCommon common`, `RGYParamControl ctrl`, `RGYParamVpp vpp`, plus QSV-only fields like `QSVRCParam rcParam`, `mfxHyperMode hyperMode`, `QSVAV1Params av1`), `QSVPipeline/rgy_prm.h` (`RGYParamVpp`, `RGYParamCommon`, `RGYParamControl`, `RGYParamInput`, `RGYParamParallelEnc`, `RGYParamLogOpt`).
- Pattern: composition, not inheritance — `sInputParams` "has-a" each shared param struct as a member. New parameters are added to `qsv_prm.h`/`qsv_cmd.h` if libvpl-specific, or `rgy_prm.h`/`rgy_cmd.h` if usable identically across all four encoder products (see `CLAUDE.md` parameter-addition table).

**`PipelineTask`:**
- Purpose: uniform node interface (`sendFrame`, `getOutput`, `requiredSurfIn`/`requiredSurfOut`, `isPassThrough`) so the encode loop can iterate over a heterogeneous chain of decode/VPP/filter/encode/output stages without special-casing each stage type.
- Examples: `PipelineTaskInput`, `PipelineTaskMFXDecode`, `PipelineTaskAudio`, `PipelineTaskTrim`, `PipelineTaskCheckPTS`, `PipelineTaskMFXVpp`, `PipelineTaskOpenCL`, `PipelineTaskVideoQualityMetric`, `PipelineTaskMFXEncode`, `PipelineTaskOutputRaw`, `PipelineTaskParallelEncBitstream` (all in `QSVPipeline/qsv_pipeline_ctrl.h`).
- Pattern: pipe-and-filter / chain-of-responsibility over a `std::vector<std::unique_ptr<PipelineTask>>`, with an allocation-priority hook (`getPipelineTaskAllocPriority`) so encode-adjacent tasks get first pick of shared work surfaces.

**`RGYFilterBase` / `RGYFilter`:**
- Purpose: uniform interface for ~70 optional VPP filters (denoise, deinterlace, resize, color correction, subtitle burn-in, AI upscale, etc.), each pairing a C++ host-side class with one or more OpenCL kernel files.
- Examples: `QSVPipeline/rgy_filter.h` (base), `rgy_filter_denoise_hqdn3d.[h/cpp]` + `rgy_filter_denoise_hqdn3d.cl`, `rgy_filter_resize.[h/cpp]` + `.cl`, `rgy_filter_nnedi.[h/cpp]` + weights (`rgy_filter_nnedi_weights.cpp`), `rgy_filter_afs*` (field-shift deinterlace, itself composed of analyze/filter/merge/synthesize sub-passes).
- Pattern: template method (`init`, `AllocFrameBuf`, `close` are virtual hooks called by the shared task wrapper `PipelineTaskOpenCL`); each filter owns an `RGYFilterParam` subclass describing its I/O frame shape.

**`RGYInput` / `RGYOutput`:**
- Purpose: decouple the pipeline from concrete demux/mux backends.
- Examples: `RGYInputAvcodec` (ffmpeg demux, `rgy_input_avcodec.*`), `RGYInputRaw` (`rgy_input_raw.*`), `RGYInputAvi`, `RGYInputAvs` (AviSynth), `RGYInputVpy` (VapourSynth, `rgy_input_vpy.*`), `RGYInputSM` (shared-memory, used for AviUtl frame feed and parallel-encode IPC, `rgy_input_sm.*`); `RGYOutputRaw`, `RGYOutput` avcodec muxer (`rgy_output_avcodec.*`).
- Pattern: strategy/plugin — selected at `InitInput`/`InitOutput` time based on file extension/CLI flags; all implementations conform to `RGYInput`/`RGYOutput` (`rgy_input.h`, `rgy_output.h`).

## Entry Points

**CLI (`QSVEncC`):**
- Location: `QSVEncC/QSVEncC.cpp` (`_tmain` → `run()` → `run_encode()`/`run_benchmark()`)
- Triggers: direct user invocation, or spawned as a child process by the AviUtl plugin.
- Responsibilities: parse argv (`parse_cmd`), show help/version/feature-list, drive `CQSVPipeline` for one encode or a benchmark sweep.

**AviUtl/AviUtl2 output plugin (`QSVEnc`):**
- Location: `QSVEnc/QSVEnc.cpp` (`GetOutputPluginTable` exported symbol; Win32 build exports `.auo` table, x64 build exports `.auo2` table via `func_output2`/`func_config2`).
- Triggers: AviUtl/AviUtl2 host application, when user selects this output plugin.
- Responsibilities: read GUI-configured settings, translate to `QSVEncC` command line, spawn/monitor child process, mux resulting streams.

## Architectural Constraints

- **Threading:** Not single-threaded — the pipeline uses dedicated OS threads for perf monitoring (`rgy_perf_monitor.*`), parallel-encode child coordination (`rgy_parallel_enc.*`, `rgy_thread_pool.h`), and OpenCL command queues; the main encode loop in `RunEncode2()` itself is a synchronous pull-based loop over `PipelineTask`s (not multi-threaded per stage).
- **Global state:** `g_signal_abort` (file-scope in `QSVEncC.cpp`) is the process-wide abort flag wired to POSIX/Win32 signal handlers; the AviUtl plugin keeps process-wide `g_sys_dat`/`g_conf` globals (`QSVEnc/QSVEnc.cpp`) since AviUtl plugins are single-instance-per-process by design.
- **Cross-process boundary:** The AviUtl plugin and `QSVEncC` are separate processes/binaries — there is no shared C++ object graph between them; all communication is via CLI string generation, stdout/log piping, and (for raw frame handoff) shared memory (`rgy_input_sm.*`, `rgy_shared_mem.h`).
- **Compile-time encoder switching:** Shared `rgy_*` files branch on `ENCODER_QSV`/`ENCODER_NVENC`/`ENCODER_VCEENC`/`ENCODER_MPP` (`rgy_version.h`) rather than runtime dispatch; a file compiled into QSVEnc never contains NVEnc-only code paths at runtime, only at preprocessor level.
- **MFX/OpenCL sync boundary:** Any point in the `PipelineTask` chain where control passes between an MFX-space task (`MFXDEC`/`MFXVPP`/`MFXENC`/`MFXENCODE`) and a non-MFX task (`OPENCL`, `INPUT`, etc.) requires an explicit sync (`PipelineTask::requireSync`, `qsv_pipeline_ctrl.h:575`) — skipping this is a correctness bug, not just a performance one.

## Anti-Patterns

### Adding QSV-only fields to shared `RGYParam*` structs

**What happens:** A contributor adds a QSV-specific field (e.g. a libvpl `mfxU16` flag) directly to `RGYParamVpp`/`RGYParamCommon`/`RGYParamControl` in `rgy_prm.h` because that's where "parameters" live.
**Why it's wrong:** `rgy_prm.h` is compiled unchanged into NVEnc/VCEEnc/rkmppenc; a QSV-only field either forces those builds to carry dead/meaningless state or requires `#if ENCODER_QSV` guards scattered through otherwise-shared code, defeating the point of the shared layer (see `CLAUDE.md` "パラメータ追加" table).
**Do this instead:** Add QSV/libvpl-specific fields to `sInputParams` in `QSVPipeline/qsv_prm.h`, and shared fields to the appropriate `RGYParam*` struct in `QSVPipeline/rgy_prm.h`; mirror the same split in `qsv_cmd.cpp` vs `rgy_cmd.cpp` for parsing/help/gen-cmd.

### Bypassing `PipelineTask::requireSync` when adding a new task type

**What happens:** A new task is inserted into `m_pipelineTasks` without updating `isMFXTask()`/`requireSync()` classification in `qsv_pipeline_ctrl.h`.
**Why it's wrong:** Frame surfaces owned by the MFX session (libvpl) and frame buffers owned by the OpenCL runtime have independent completion signaling; without an explicit sync point the encode loop can hand a not-yet-ready surface downstream, causing corrupt frames or driver-level races that only reproduce under load.
**Do this instead:** Classify new task types in `isMFXTask()` (`qsv_pipeline_ctrl.h:568`) and rely on the existing `requireSync` computation in `CQSVPipeline::RunEncode2()`'s `requireSync` lambda (`qsv_pipeline.cpp:5585`) rather than hand-rolling per-task synchronization.

## Error Handling

**Strategy:** Single shared error-code enum (`RGY_ERR`, `QSVPipeline/rgy_err.h`) returned by nearly every method (`RGY_ERR_NONE` for success, positive values for benign/expected conditions like `RGY_ERR_MORE_DATA`, negative values for real failures). libvpl `mfxStatus` codes are translated at the boundary via `err_to_rgy()`.

**Patterns:**
- Functions return `RGY_ERR` and log via `PrintMes(RGY_LOG_*, ...)` rather than throwing exceptions for expected/recoverable conditions; C++ exceptions are reserved for truly exceptional allocation/runtime failures.
- The main encode loop treats `RGY_ERR_MORE_DATA`/`RGY_ERR_MORE_SURFACE`/`RGY_ERR_MORE_BITSTREAM` as "keep going" signals (`checkContinue` lambda, `qsv_pipeline.cpp:5621`), not errors — callers must distinguish `err >= RGY_ERR_NONE` (or these specific positive codes) from true negative failures.
- User-facing invalid-CLI-value errors go through dedicated `print_cmd_error_invalid_value()` overloads (`rgy_cmd.cpp`) that render the offending value plus the list of valid choices.

## Cross-Cutting Concerns

**Logging:** `RGYLog` (`rgy_log.h`/`.cpp`) — a shared logger with per-subsystem log types (`RGY_LOGT_CORE`, `RGY_LOGT_VPP`, ...) and levels (`RGY_LOG_DEBUG`...`RGY_LOG_ERROR`); every major object (`CQSVPipeline`, `PipelineTask`, `RGYFilterBase`) holds a `shared_ptr<RGYLog>` and exposes a `PrintMes`/`AddMessage` helper that prefixes messages with the component name.

**Validation:** CLI values are validated during parsing (`parse_one_*_option` functions in `rgy_cmd.cpp`/`qsv_cmd.cpp`) against `CX_DESC`/`FEATURE_DESC` lookup tables, with dedicated error printers; pipeline-level validation happens in `CQSVPipeline::CheckParam`/`CheckParamList`/`clamp_param_int` before any device/session is created.

**Authentication:** Not applicable — this is a local command-line/plugin video encoder with no network-facing auth surface.

---

*Architecture analysis: 2026-07-23*
