# Coding Conventions

**Analysis Date:** 2026-07-23

## Naming Patterns

**Files:**
- Shared (cross-encoder) implementation files use the `rgy_` prefix and live in `QSVPipeline/`: `rgy_prm.h`, `rgy_cmd.cpp`, `rgy_log.h`, `rgy_filter.h`, `rgy_bitstream.cpp`. These files must stay portable across QSVEnc / NVEnc / VCEEnc / rkmppenc — do not add QSV-only code here without an `ENCODER_QSV` guard.
- QSVEnc-specific (libvpl/MFX-only) files use the `qsv_` prefix: `qsv_prm.h`, `qsv_cmd.cpp`, `qsv_pipeline.h`, `qsv_device.cpp`, `qsv_allocator_d3d11.cpp`.
- Platform-specific variants are suffixed rather than branched internally where practical: `qsv_hw_d3d9.cpp` / `qsv_hw_d3d11.cpp` / `qsv_hw_va.cpp` (Windows D3D9/D3D11 vs. Linux VA-API), `qsv_allocator_sys.cpp` vs `qsv_allocator_d3d11.cpp` / `qsv_allocator_va.cpp`.
- SIMD-specialized translation units are suffixed with the instruction set: `convert_csp_sse2.cpp`, `convert_csp_ssse3.cpp`, `convert_csp_sse41.cpp`, `convert_csp_avx.cpp`, `convert_csp_avx2.cpp`, `rgy_bitstream_avx2.cpp`, `rgy_bitstream_avx512bw.cpp`. Each is compiled with a matching `-m<isa>` flag only (see `makefile` pattern rules and `meson.build`).
- Header guards use the pattern `#pragma once` + `#ifndef __FILE_NAME_H__` / `#define __FILE_NAME_H__` (double underscore prefix/suffix, all-caps), e.g. `__RGY_ERR_H__`, `__PIPELINE_ENCODE_H__`, `__RGY_PRM_H__`. Always add both `#pragma once` and the include-guard macro for MSVC/gcc/clang parity.

**Types (structs/classes/enums):**
- Legacy Win32/MFX-influenced classes use a `C` prefix: `CQSVPipeline`, `CPerfMonitor`.
- Shared abstractions use an `RGY` prefix: `RGYLog`, `RGYFilterBase`, `RGYInput`, `RGYOutput`, `RGYBitstream`, `RGYTimecode`, `RGYParamCommon`.
- QSV-specific parameter/data structs use a `QSV` prefix (`QSVVideoParam`, `QSVEncFeatures`, `QSVDevice`, `QSVRCParam`) or legacy Hungarian `s`-prefixed structs (`sInputParams`, `sVppParams`, `sArgsData`, `sTrimParam`) for structs that predate the `RGY`/`QSV` split.
- Enums are a mix of legacy plain `enum` (`MemType`, `VppStabBorder`) and modern `enum class` (`VppType : int`, `RGYHEVCBsf`, `QSVDeviceNum`). Prefer `enum class` for new enums unless implicit int conversion or C-API interop is required.
- VPP filter parameter structs are named `Vpp<FilterName>` (`VppDenoise`, `VppMCTF`, `VppResizeNis`, `VppLibplaceboDeband`).

**Functions:**
- Public API / interface methods use PascalCase: `Init()`, `Run()`, `Close()`, `CheckParam()`, `GetEncodeStatusData()`.
- Newer/internal helper methods use camelCase: `getLogLevel()`, `setLogFile()`, `writeHtmlHeader()`, `addStreamPacket()`.
- Free functions in shared command-line code follow `parse_one_<group>_option(...)` / `gen_cmd(...)` / `gen_cmd_help_<group>()` naming, e.g. `parse_one_common_option`, `parse_one_vpp_option`, `parse_one_vppmfx_option` (QSV-only in `qsv_cmd.cpp`), `gen_cmd_help_ctrl`. When adding a new CLI option group, follow this exact triad of function names (see `QSVPipeline/rgy_cmd.cpp` and `QSVPipeline/qsv_cmd.cpp`).
- `RGY_ERR`-returning functions are verbs: `InitLog`, `InitFilters`, `AddFilterMFX`, `ResetDevice`.

**Variables (legacy Hungarian notation, still actively used):**
- `m_` prefix for all class member variables: `m_pQSVLog`, `m_encWidth`, `m_nAsyncDepth`, `m_bTimerPeriodTuning`.
- Hungarian type-tag prefixes remain common on both members and locals: `p`/`pp` (pointer/pointer-to-pointer: `pParams`, `ppAudioSelectList`), `n` (integer count: `m_nAsyncDepth`, `nArgNum`), `b` (bool: `m_bTimerPeriodTuning`, `bOutOverwrite`), `sts`/`err` (`RGY_ERR` result variables: `RGY_ERR sts = RGY_ERR_NONE;`).
- New code is not required to add Hungarian prefixes, but must not remove them from existing variables it touches (mixed style across eras is expected and accepted).

**Macros:**
- Encoder/platform switches are all-caps with `ENCODER_` prefix: `ENCODER_QSV`, `ENCODER_NVENC`, `ENCODER_VCEENC`, `ENCODER_MPP`. Always guard QSV/libvpl-only code paths in shared `rgy_*` files with `#if ENCODER_QSV ... #endif`.
- Feature toggles use `ENABLE_` prefix: `ENABLE_VULKAN`, `ENABLE_AVSW_READER`, `ENABLE_PERF_COUNTER`, `ENABLE_NVVFX`.
- Error codes are the `RGY_ERR` enum (see `QSVPipeline/rgy_err.h`), all-caps `RGY_ERR_<NAME>` with explicit negative values (`RGY_ERR_NONE = 0`, `RGY_ERR_UNKNOWN = -1`, ... down through OpenCL-specific codes starting at `-50`). When adding a new error, append with the next unused negative value in the relevant block; never renumber existing values (they are used across encoder variants and logs).

## Code Style

**Formatting:**
- No `.clang-format` / `.clang-tidy` config is present. Style is enforced by convention/review, not tooling.
- `.editorconfig` (repo root) is authoritative for whitespace/encoding:
  - Default `charset = utf-8`, `end_of_line = crlf`, `insert_final_newline = true`, `trim_trailing_whitespace = false`.
  - C/C++ source (`*.{c,cc,cpp,cxx,h,hh,hpp,hxx,cu,cuh,cl}`) must be `utf-8-bom` (UTF-8 with BOM) — confirmed by the `﻿` BOM marker visible at the top of every `.h`/`.cpp` file read (e.g. `QSVPipeline/rgy_err.h`, `QSVPipeline/qsv_pipeline.h`).
  - Shell/Python/Makefile files (`*.{sh,bash,py,mk}`) and build files (`Makefile`, `configure`, `meson.build`, `meson_options.txt`) use `end_of_line = lf`.
- Indentation is 4 spaces, no tabs (verified: zero tab characters in `qsv_pipeline.cpp`).
- Braces: opening brace on the same line as the statement (`if (...) {`, `class Foo {`), K&R/Stroustrup style throughout.
- Every source file opens with the standard MIT license header block (see boilerplate at top of `QSVPipeline/rgy_err.h`, `QSVPipeline/qsv_pipeline.h`) — copy this exact block (author line adjusted to the relevant project name, e.g. "QSVEnc/NVEnc by rigaya" for shared files, "QSVEnc by rigaya" for QSV-only files) into any new source file.

**Linting:**
- No ESLint/clang-tidy equivalent. The closest automated check is `check_options.py`, run in CI (`.github/workflows/build_packages.yml`) to diff `--option-list` output of the built binary against the options documented in `QSVEncC_Options.en.md` / `QSVEncC_Options.ja.md`. Any option missing from either side fails visibility (non-blocking check, printed as a diff report) — always update both docs when adding/removing a CLI option.

## Import Organization

**Order (as seen in `qsv_pipeline.h`, `rgy_err.h`):**
1. `rgy_version.h` first (defines `ENCODER_*`/`ENABLE_*` macros used by subsequent conditional includes).
2. Encoder/OS-specific SDK headers wrapped in `#if ENCODER_QSV` / `#if ENCODER_NVENC || CUFILTERS` / `#if ENCODER_VCEENC` / `#if ENCODER_MPP` blocks, each usually wrapped in `#pragma warning (push/pop)` to suppress SDK header warnings (see `QSVPipeline/rgy_err.h`).
3. Shared `rgy_*.h` headers (`rgy_osdep.h`, `rgy_thread.h`, `rgy_event.h`, `rgy_log.h`, `rgy_filter.h`).
4. Encoder-specific `qsv_*.h` headers (`qsv_util.h`, `qsv_prm.h`, `qsv_hw_device.h`, `qsv_allocator.h`).
5. Standard library headers last (`<vector>`, `<memory>`, `<string>`, `<iostream>`).
6. Forward declarations (`struct AVChapter;`, `class RGYTimecode;`) placed after all includes, immediately before the first type/enum definition.

**Path Aliases:** None — all includes are flat relative filenames (no `#include "../foo/bar.h"` layering observed); every source file lives directly in `QSVPipeline/`, `QSVEncC/`, or `QSVEnc/` and includes by bare filename, relying on the compiler's include-path search (`.vcxproj` / `meson.build` include dirs).

## Error Handling

**Pattern:** All fallible internal APIs return `RGY_ERR` (defined in `QSVPipeline/rgy_err.h`), an `enum` with `RGY_ERR_NONE = 0` for success and distinct negative values per failure (general codes `-1..-41`, OpenCL codes from `-50`). Never use exceptions for expected/recoverable error flow in `RGY_ERR`-based APIs.

**Standard flow:**
```cpp
RGY_ERR CQSVPipeline::Init(sInputParams *pParams) {
    if (pParams == nullptr) {
        return RGY_ERR_NULL_PTR;
    }
    RGY_ERR sts = RGY_ERR_NONE;
    sts = m_pFileReader->GetHeader(&m_DecInputBitstream);
    if (sts != RGY_ERR_NONE) {
        return sts;
    }
    ...
}
```
(see `QSVPipeline/qsv_pipeline.cpp:4913` and surrounding code).

**Error-check macros** (local to `qsv_pipeline.cpp`, mirror the pattern used across encoder variants):
```cpp
#define RGY_ERR_MES(ret, MES)  {if (RGY_ERR_NONE > (ret)) { PrintMes(RGY_LOG_ERROR, _T("%s : %s\n"), MES, get_err_mes(ret)); return err_to_mfx(ret);}}
#define RGY_ERR(ret, MES)      {if (RGY_ERR_NONE > (ret)) { PrintMes(RGY_LOG_ERROR, _T("%s : %s\n"), MES, get_err_mes(ret)); return ret;}}
#define QSV_ERR_MES(sts, MES)  {if (MFX_ERR_NONE > (sts)) { PrintMes(RGY_LOG_ERROR, _T("%s : %s\n"), MES, get_err_mes((int)sts)); return sts;}}
```
Use these (or the equivalent inline `if (err != RGY_ERR_NONE) { PrintMes(...); return err; }` block) rather than inventing new error-propagation idioms.

**Conversion helpers:** `err_to_rgy(...)` and `err_to_mfx(...)` convert between MFX SDK status codes (`mfxStatus`) and the shared `RGY_ERR` enum at the QSV/shared boundary (e.g. `QSVPipeline/qsv_pipeline.cpp:1615`). Any new QSV-only code that calls into libvpl/MFX APIs must convert the `mfxStatus` result through `err_to_rgy` before returning/propagating it through shared (`rgy_*`) code paths.

**Null checks:** Defensive `nullptr`/`NULL` parameter checks at the top of public entry points, returning `RGY_ERR_NULL_PTR` immediately (see `Init()` above).

**Runtime assertions:** `assert()` / `<cassert>` is used sparingly for internal invariants (e.g. `QSVPipeline/rgy_util.h`, `QSVPipeline/rgy_stream.h`, `QSVPipeline/qsv_pipeline.cpp`) — these are debug-only sanity checks, not user-facing error handling. `static_assert` is used more heavily for compile-time template constraints, e.g.:
```cpp
static_assert(std::is_integral<T>::value, "rgy_is_pow2 is defined only for integer.");
```
(see `QSVPipeline/rgy_util.h`). Use `static_assert` for template parameter constraints; use `RGY_ERR` returns (never exceptions, rarely runtime `assert`) for anything that can fail based on user input, hardware state, or I/O.

## Logging

**Framework:** Custom `RGYLog` class (`QSVPipeline/rgy_log.h` / `rgy_log.cpp`), not a third-party logging library.

**Levels:** `RGYLogLevel` enum, e.g. `RGY_LOG_DEBUG`, `RGY_LOG_INFO` (default), `RGY_LOG_WARN`, `RGY_LOG_ERROR`, filtered per log-category (`RGYLogType`, e.g. `RGY_LOGT_VPP`) via `RGYParamLogLevel`.

**Two call sites, same idiom:**
- Pipeline-level: `virtual void PrintMes(RGYLogLevel log_level, const TCHAR *format, ...);` on `CQSVPipeline`, e.g.:
  ```cpp
  PrintMes(RGY_LOG_ERROR, _T("%s=%d, is not valid param.\n"), param_name, value);
  ```
  (see `QSVPipeline/qsv_pipeline.cpp:441` and dozens of similar call sites).
- Filter-level: `AddMessage(RGYLogLevel log_level, const TCHAR *format, ...)` on `RGYFilterBase` (`QSVPipeline/rgy_filter.h`), which prefixes every line with the filter's own `m_name` and splits multi-line messages before writing.

**Conventions:**
- All log/format strings use the `_T("...")` macro for TCHAR (wide on Windows, narrow on Linux) portability — never a bare string literal in log/format calls.
- Messages end with `\n` explicitly (log calls do not auto-append newlines).
- Error messages are user-facing English (e.g. "Interlaced encoding is not supported on current rate control mode.\n"), while internal design/rationale comments are frequently Japanese (see Comments section).

## Comments

**Language:** Comments are bilingual — mostly Japanese for internal rationale/history/warnings, English for license headers and some user-facing strings. Both are common in the same file; there is no single-language mandate. Example from `QSVPipeline/qsv_pipeline.cpp`:
```cpp
//最初のフレームそのものをヘッダーとして使用する。
//ここで読み込みんだ第1フレームのデータを読み込み側から消してしまうと、
//メインループでは第2フレームのデータがmfxBitstreamに追加されてしまい、
//第1・第2フレームの両方のデータが存在することになってしまう。
```
New code comments explaining "why" (design rationale, workarounds, gotchas) may be written in Japanese, consistent with the existing codebase; keep user-facing strings (log/error/help text) in English by default with a Japanese counterpart maintained in `QSVEncC_Options.ja.md`.

**When to comment:** Primarily used to explain non-obvious workarounds, ordering dependencies, and hardware/driver quirks — not to restate what the code does. TODO/FIXME/HACK markers are rare (only 2 files in `QSVPipeline/*.cpp` contain them) — this codebase prefers fixing or documenting-in-place over leaving TODO markers.

**Doc comments:** No JSDoc/Doxygen-style block convention observed; comments are plain `//` line comments, often multi-line paragraphs directly above the relevant statement/block.

## Function Design

**Size:** Large, multi-hundred-line functions are common and accepted for pipeline setup/option-parsing code (e.g. `CQSVPipeline::Init` spans thousands of lines with many sequential `if` blocks; `parse_one_common_option` in `rgy_cmd.cpp` is one giant `if (IS_OPTION(...))` chain). Do not feel obligated to refactor these into smaller functions unless the phase explicitly calls for refactoring — match existing structure when adding new options/branches.

**Parameters:** Struct-based parameter passing is the norm for anything with more than ~3 fields — pass a pointer to a params struct (`sInputParams *pParams`, `sVppParams *vppmfx`, `sArgsData *argData`) rather than long parameter lists. Output/in-out parameters are passed by pointer or reference (`int &i` for the CLI arg-index cursor in every `parse_one_*_option` function).

**Return values:** `RGY_ERR` for anything that can fail. `int` return codes of `0`/`1`/`-1` are used specifically in the `parse_one_*_option` family (`0` = not handled or success continue, `1` = error, `-1` = "handled by caller in rgy_cmd.cpp", per inline comments such as `ret = -1; // rgy_cmd.cppで処理する`). `tstring` is returned by value from `gen_cmd`/`gen_cmd_help_*` functions that build CLI strings/help text.

## Module Design

**Exports:** No explicit export/visibility macros for internal linkage; classes and free functions are declared in the matching `.h` and defined in the matching `.cpp`, one class/subsystem per file pair (`qsv_pipeline.h/.cpp`, `rgy_filter.h` + many `rgy_filter_<name>.cpp` implementation files).

**Barrel files:** None — no aggregating "index" header re-exports everything; each header is included individually and explicitly by consumers.

**Two-layer parameter/command pattern:** For any new feature, decide whether it is QSV/libvpl-specific or shared across QSVEnc/NVEnc/VCEEnc/rkmppenc, then edit the matching pair:

| Concern | QSV/libvpl-only file | Shared (all encoders) file |
|---|---|---|
| Parameter struct definition/initialization | `qsv_prm.h` / `qsv_prm.cpp` | `rgy_prm.h` / `rgy_prm.cpp` |
| CLI parsing / generation / help text | `qsv_cmd.h` / `qsv_cmd.cpp` | `rgy_cmd.h` / `rgy_cmd.cpp` |
| Docs | `QSVEncC_Options.ja.md` (write first) then `QSVEncC_Options.en.md` (translate) | same two files |

This mirrors the project's own `.cursor/commands/add-new-common-option.md` and `add-new-qsv-option.md` task definitions, which specify exactly these edit points (`parse_one_xxx_option`, `gen_cmd`, `gen_cmd_help_xxx`) for adding a new command-line option.

---

*Convention analysis: 2026-07-23*
