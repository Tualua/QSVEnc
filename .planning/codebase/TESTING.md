# Testing Patterns

**Analysis Date:** 2026-07-23

## Test Framework

**Runner:** None. There is no unit test framework in this repository (no GoogleTest, Catch2, doctest, CTest test targets, or similar). A repo-wide search for `*test*`/`*spec*` files (excluding vendored dependencies `ttmath`, `libvpl`, `cppcodec`, `json`, `dtl`, `tinyxml2`) returns no matches, and neither `meson.build` nor the top-level `makefile` define a `test` target.

**Assertion Library:** None for automated tests. `static_assert` (from `<type_traits>`-style template constraints) is used throughout for compile-time invariants, e.g.:
```cpp
static_assert(std::is_integral<T>::value, "rgy_is_pow2 is defined only for integer.");
```
(`QSVPipeline/rgy_util.h`). Runtime `assert()`/`<cassert>` appears sparingly (`QSVPipeline/rgy_util.h`, `rgy_stream.h`, `rgy_input_avcodec.h`, `qsv_pipeline.cpp`, `qsv_allocator*.cpp`) as debug-only internal invariant checks, not as part of any structured test suite.

**Run Commands:** There is no `test` command. Correctness is validated by:
1. Building the project (Windows via `msbuild QSVEnc.sln`, Linux via `meson`/`make`) and confirming it compiles cleanly.
2. Running the built binary against real Intel GPU hardware and comparing `--check-features` output.
3. Running `check_options.py` (repo root) to catch documentation/CLI drift.

## Validation Strategy (in place of unit tests)

This is a hardware-dependent C++ video encoder with no automated unit/integration test suite. Correctness is instead validated through three mechanisms:

### 1. Hardware feature-capability snapshots (`GPUFeatures/`)

`GPUFeatures/*.txt` (29 files as of this analysis) are captured outputs of `QSVEncC --check-features` run on real hardware/OS/driver combinations, named `QSVEnc_<CPUCodename>_<CPUModel>_<OS>.txt`, e.g.:
- `GPUFeatures/QSVEnc_ADL_i9_12900K_Ubuntu2004.txt`
- `GPUFeatures/QSVEnc_DG2_Arc_A380_Win.txt`
- `GPUFeatures/QSVEnc_ARL_u5_245K_Win.txt`

Each file records encoder version, environment info (OS, CPU, driver), and a full feature-support matrix per codec/rate-control-mode (`CBR`, `VBR`, `AVBR`, `QVBR`, `CQP`, `LA`, `LAHRD`, `ICQ`, `LAICQ`, `VCM`) across dozens of feature rows (10bit depth, Hyper Mode, Interlace, WeightP/B, MBBRC, ExtBRC, AdaptiveRef, etc.).

These are **reference/regression documents, not automated tests** — there is no script in this repo that re-runs `--check-features` and diffs against a stored snapshot. When adding hardware/codec support, add or update the relevant `GPUFeatures/*.txt` file manually after running `--check-features` on real hardware; `Readme.md` links to this directory as the authoritative feature-support matrix for users.

### 2. Documentation/CLI consistency check (`check_options.py`)

`check_options.py` (repo root, Python 3) is executed in CI (`.github/workflows/build_packages.yml`, "Build Exec" step: `./check_options.py -exe ./build/qsvencc`). It:
- Parses `QSVEncC_Options.en.md` and `QSVEncC_Options.ja.md` for every documented `--option` (matching `### --option`, `### -x, --option`, `### --(no-)option` heading patterns).
- Runs the built `qsvencc` binary with `--option-list` to get the actual implemented option set.
- Reports (does not fail the build on) any option present in one side but not the other, printed as "Not listed in <file>: N" diffs.

This is the closest thing to an automated regression check in the repo — it guards against CLI/documentation drift, not runtime encoder correctness. When adding a new CLI option (per `qsv_cmd.cpp`/`rgy_cmd.cpp`), always add matching entries to `QSVEncC_Options.en.md` and `QSVEncC_Options.ja.md` or this check will flag the mismatch.

### 3. CI build + smoke checks

No dedicated test workflow exists; validation is folded into the release/build workflows under `.github/workflows/`:
- **`build_packages.yml`** (Linux, push to `master`/`linux` or tag): builds via `meson`/`ninja` inside Docker, then runs smoke checks before packaging:
  ```bash
  docker exec build_pkg ldd ./build/qsvencc
  docker exec build_pkg ./build/qsvencc --version
  docker exec build_pkg ./check_options.py -exe ./build/qsvencc
  ```
  It also verifies the git tag matches `VER_STR_FILEVERSION` in `QSVPipeline/rgy_version.h` before tagged releases.
- **`build_releases.yml`** (Windows, push to `master`/`actions` or tag): builds via `msbuild` for `Win32`/`x64`, then runs a DLL-availability smoke check:
  ```cmd
  QSVEncC_Release\QSVEncC64.exe --check-avcodec-dll
  ```
  and (for tagged releases) verifies the built `.exe` `FileVersion` matches the expected release version name via PowerShell.
- **`build_base_images.yml`**: rebuilds the Docker base images used by the Linux build workflow; not a test workflow itself.

None of these workflows run the encoder against a video file to validate actual encode/decode/filter correctness — there is no golden-output frame comparison, no CRC/PSNR check, and no hardware runner in CI (GitHub-hosted runners have no Intel QSV-capable GPU). Hardware-dependent correctness is validated manually by the maintainer/contributors on real Intel hardware before release, then recorded into `GPUFeatures/`.

## Test File Organization

Not applicable — no test files exist in this repository outside of vendored third-party dependencies (which are out of scope and should not be modified).

## Mocking

Not applicable — no mocking framework or dependency-injection test seams are used, since there is no unit test suite. `RGYLog`/`PrintMes` output can be redirected to a log file (`--log <file>`) for manual inspection but this is a CLI feature, not a test harness.

## Fixtures and Factories

Not applicable — no fixture/factory infrastructure exists. Sample media files, if needed for manual testing, are not checked into the repository.

## Coverage

No coverage tooling (gcov/lcov, OpenCppCoverage, etc.) is configured in `meson.build`, the `makefile`, or any `.vcxproj`/CI workflow.

## Test Types

**Unit Tests:** None.

**Integration Tests:** None automated. Manual integration validation is performed by running the built `QSVEncC`/`qsvencc` binary against real media and real Intel QSV hardware, informed by `--check-features` and the accumulated matrices in `GPUFeatures/`.

**E2E Tests:** None. `--check-avcodec-dll` (Windows) and `--version`/`ldd` (Linux, in CI) are the closest thing to an end-to-end smoke test, confirming the binary starts and loads its shared library dependencies correctly — they do not exercise the encode pipeline itself.

## Guidance for Contributors Adding Functionality

Because there is no test suite to extend, when adding a feature or option in this codebase:
1. Verify manually on real Intel hardware (`--check-features`, and an actual encode run) rather than relying on CI to catch regressions.
2. Update the relevant `GPUFeatures/*.txt` file(s) if the change affects reported feature/codec support on hardware you have access to.
3. Run `check_options.py -exe <path-to-built-binary>` locally before committing CLI option changes, and keep `QSVEncC_Options.en.md` / `QSVEncC_Options.ja.md` in sync with `qsv_cmd.cpp`/`rgy_cmd.cpp` (see `CONVENTIONS.md` two-layer parameter/command table).
4. Rely on `static_assert` for any new template-based utility to catch misuse at compile time, since there is no runtime test harness to catch it later.

---

*Testing analysis: 2026-07-23*
