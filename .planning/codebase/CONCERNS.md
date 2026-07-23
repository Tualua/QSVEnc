# Codebase Concerns

**Analysis Date:** 2026-07-23

## Tech Debt

**No automated test suite:**
- Issue: There is no `tests/` directory, no unit test framework, no test target in the build, and no test/sanitizer job in CI (`.github/workflows/build_base_images.yml`, `build_packages.yml`, `build_releases.yml` only build and package artifacts).
- Files: entire repo — confirmed absence via `find . -iname "*test*"` returning no test directories or test source files outside bundled third-party libs.
- Impact: All correctness validation is manual/visual (encode a sample, inspect output) or discovered post-release via user bug reports. This directly correlates with the very high rate of latent bug fixes landing recently (see "Known Bugs" below) — many of these are the kind of defects (off-by-one, buffer overrun, use-after-free, inverted boolean) that a basic unit/regression test suite or CI sanitizer run would catch before merge.
- Fix approach: Add at least a minimal unit test target for the platform-independent `rgy_*` utility files (string trimming, bitstream parsing, NAL/OBU parsing, chapter parsing) and wire an ASan/UBSan build into CI for the CLI smoke-encode path.

**Massive shared command/parameter files carrying 4-encoder conditional logic:**
- Issue: `QSVPipeline/rgy_cmd.cpp` (17,315 lines) and `QSVPipeline/rgy_prm.h` (4,349 lines) / `rgy_prm.cpp` (4,533 lines) implement command-line parsing and parameter definitions shared across QSVEnc/NVEnc/VCEEnc/rkmppenc, gated by `ENCODER_QSV`/`ENCODER_NVENC`/`ENCODER_VCEENC`/`ENCODER_MPP` macros (121 occurrences in `rgy_prm.h` alone, 14+ distinct macro combinations).
- Files: `QSVPipeline/rgy_cmd.cpp`, `QSVPipeline/rgy_prm.h`, `QSVPipeline/rgy_prm.cpp`.
- Impact: Any change to a shared option must be reasoned about across four separate encoder projects that are not present in this repo (NVEnc/VCEEnc/rkmppenc live in sibling repos and receive the same file via manual sync, per `CLAUDE.md`). A mistake in a macro-guarded branch can silently miscompile for one encoder while working for another; recent bug-fix history (`ed259e24`, `7f2676f8`, `165f5929` — all `qsv_cmd`/`rgy_cmd` parsing logic bugs with inverted conditionals or misparsed arguments) shows this class of defect already shipped repeatedly.
- Fix approach: When touching shared files, grep for the macro name in all four gating combinations and manually trace each branch; do not assume test coverage will catch it (there is none).

**Disabled VPP filter left compiled-out via feature flag:**
- Issue: `--vpp-stdeint` (ST-DeInt ONNX-based deinterlacer) was disabled in commit `7723b930` ("--vpp-stdeintを一時無効化" / "temporarily disable --vpp-stdeint") by hardcoding the feature macro to `0`, but its implementation and all associated code remain in the tree.
- Files: `QSVPipeline/rgy_prm.h:87` — `#define ENABLE_VPP_FILTER_STDEINT 0 //((ENABLE_OPENVINO && ENCODER_QSV) || (ENABLE_ONNXRUNTIME && (ENCODER_NVENC || ENCODER_VCEENC)))`. Related implementation likely in `rgy_filter_stdeint*` (search for `stdeint` filter sources) and OpenVINO integration paths.
- Impact: The corresponding documentation section was fully removed from `QSVEncC_Options.en.md` / `QSVEncC_Options.ja.md` in the same commit, so there's no visible trace to users that the feature exists or why it's gone; if left disabled long-term the dead code will bit-rot against surrounding refactors (e.g. the zero-copy OpenCL/OpenVINO paths it depends on) without anyone testing it.
- Fix approach: Track re-enablement as a follow-up item; when other OpenVINO/zero-copy filter code changes, verify `ENABLE_VPP_FILTER_STDEINT` code paths still compile (`grep -rn ENABLE_VPP_FILTER_STDEINT` to find all call sites) even though they aren't built by default.

**Pointer-identity-based zero-copy cache validation (fragile-by-design, self-acknowledged in comments):**
- Issue: The degrain/rtgmc zero-copy cache optimizations (`702b4823`, `5868d4e1`, `075e1eef` — all landed 2026-07-18) validate that a cached/attached frame reference is safe to alias (rather than deep-copy) by comparing raw pointer values (`ptr[0]`) between the current frame and a previously attached `RGYFrameData` subclass (`RGYFrameDataRtgmcEdi`, `RGYFrameDataRtgmcSourceTwin`). The code comments explicitly acknowledge this is a correctness-by-convention scheme: "アンカー判定はいずれもptr[0]の一致検証を必須とする...添付情報の存在だけを根拠にすると誤ったバッファに寿命保証が付く" (anchor detection requires ptr[0] match; relying on attachment presence alone would give lifetime guarantees to the wrong buffer).
- Files: `QSVPipeline/rgy_filter_degrain.cpp` (`pushCacheFrame`), `QSVPipeline/rgy_filter_rtgmc.cpp` (`attachEdiReference`, `initFilters`), `QSVPipeline/rgy_filter_rtgmc_common.h` (`RGYFrameDataRtgmcEdi`, `RGYFrameDataRtgmcSourceTwin`), `QSVPipeline/rgy_filter_rtgmc_search_prefilter.cpp`.
- Impact: Pointer-value equality is not a guarantee of object identity when an allocator/pool can reuse a freed address for an unrelated buffer between the time a `dataList` attachment is created and the time it is consulted. If the OpenCL frame pool ever recycles a buffer address in that window, this scheme could silently alias the wrong pixel data. The comments show the author is aware of and defending against a narrower version of this risk (attachment inherited to unrelated frame via `FILTER_PATHTHROUGH_DATA`), but the fundamental "pointer as proof of identity" approach remains a latent risk if pool/allocation strategy changes.
- Fix approach: If a data-corruption/flicker bug ever appears in `--vpp-degrain` or `--vpp-rtgmc` output when combined with `zeroCopyCache`, this pointer-aliasing logic is the first place to check. Consider adding a generation/epoch counter to `RGYCLFrame` pool allocations to make the identity check robust against address reuse rather than relying solely on pointer value.

**Bundled dependencies with very stale last-touch dates:**
- Issue: Several vendored/submodule dependencies have not been updated in years: `ttmath` (last touched 2016-07-09), `clRNG` (2021-04-17), `tinyxml2` (2022-07-02), `cppcodec` (2023-09-15).
- Files: `ttmath/`, `clRNG/`, `tinyxml2/`, `cppcodec/`.
- Impact: These are narrow-purpose libraries (arbitrary precision math for timestamps, OpenCL RNG for `--vpp-deband`, XML parsing, base64/hex codec) so staleness is lower risk than a security-sensitive dependency, but any upstream security fix or bug fix in these projects will not be picked up automatically.
- Fix approach: No immediate action needed; revisit only if a specific CVE or bug in one of these libraries is reported upstream.

## Known Bugs

**High recent rate of memory-safety and logic bug fixes (historical pattern, mostly already fixed):**
- Symptoms: Of the last 300 commits, 58 (~19%) are explicit bug fixes (commit messages containing "バグを修正" / "不具合を修正" / "fix:"), spanning buffer overruns, use-after-free, double-free, uninitialized memory, inverted boolean logic, and resource leaks.
- Files (representative, already fixed but indicative of code areas that need extra scrutiny in future changes):
  - `QSVPipeline/rgy_bitstream.cpp` — AV1 OBU size parsing out-of-range read/write (`6491ac8c`), NAL unnal() buffer under-read (`5e667a74`), NAL start-code header out-of-range read (`b547c655`).
  - `QSVPipeline/rgy_chapter.cpp` — matroska EditionEntry infinite loop from wrong loop variable (`0e07ad51`), null `GetText()` crash (`931fc3c3`), apple chapter null-pointer crash (`18f39475`).
  - `QSVPipeline/qsv_hw_va_utils.cpp` / `qsv_hw_va_utils_drm.cpp` (Linux VA-API) — closing an uninitialized fd (always 0/stdin) in `ReleaseVASurface` (`482875ed`), dangling `%s` format arg in driver-name logging (`382d539b`), missing `break` causing wrong VA status mapping (`5ce143e6`).
  - `QSVPipeline/qsv_allocator_d3d9.cpp` / `qsv_allocator_d3d11.cpp` / `qsv_allocator_va.cpp` (Windows/Linux frame allocators) — double-free of `dxMids` on alloc failure (`fd802879`), leaked texture on alloc failure (`f0d5d65a`), leaked VA surface from raw-fourcc VP8 segmap check (`f30adce5`), invalid surface written back after `vaCreateSurfaces` failure (`8e7a383c`).
  - `QSVPipeline/rgy_util.cpp` — `rgy_is_pow2` inverted logic (`f6c2f9ec`), `find_data` underflow when pattern longer than haystack (`ae036abb`), `lstrip`/`rstrip` off-by-one trimming bugs (`111d136e`, `2bbc45ff`).
  - `QSVPipeline/rgy_shared_mem.cpp` / `rgy_device_usage.cpp` — `shmat` failure sentinel `(void*)-1` not checked (`10201082`), null header dereference on `open()` failure (`974f9fd4`), duplicate stale entries left after compression (`c804983f`).
  - `QSVPipeline/rgy_faw.cpp` — infinite loop on zero-length AAC frame (`e4b206d9`), buffer over-read past AAC header (`0e9f2430`).
  - `QSVEnc/encode/auo_encode.cpp` and related AviUtl plugin files (`auo_settings.cpp`, WAV writer) — half-written silence padding for fp32 audio (`b375f18c`), int32 overflow in non-RF64 WAV size calc (`5aad11d6`), wrong WAV data-size write offset (`8a706a21`).
- Files: see above; full list visible via `git log --oneline` messages matching "バグを修正".
- Trigger: Most require a specific edge-case input (malformed/edge-case bitstream, chapter file, WAV format, allocator failure path, VA-API error path) that ordinary happy-path testing does not exercise.
- Workaround: All commits listed above are already merged fixes as of 2026-07-23; no outstanding workaround needed for these specific instances. The concern is forward-looking: the density of this bug class strongly suggests similar undiscovered defects remain in adjacent, less-recently-audited code (particularly Windows-specific allocator/device paths, which have seen comparatively less recent fix activity than the Linux VA-API paths).

**`--vpp-stdeint` unavailable:**
- Symptoms: Users following historical documentation or third-party guides referencing `--vpp-stdeint` will get an "unknown option" or unsupported-filter error; the option was silently removed from `QSVEncC_Options.en.md`/`.ja.md` in commit `7723b930`.
- Files: `QSVPipeline/rgy_prm.h:87`.
- Trigger: Passing `--vpp-stdeint` on any current build.
- Workaround: None documented; users must fall back to other deinterlacers (`--vpp-yadif`, `--vpp-bwdif`, `--vpp-nnedi`, `--vpp-rtgmc`).

## Security Considerations

**Bundled/vendored third-party parsers process untrusted input:**
- Risk: Chapter file parsing (matroska/apple formats via `QSVPipeline/rgy_chapter.cpp`), bitstream/NAL/OBU parsing (`rgy_bitstream.cpp`), and AAC/WAV audio parsing (`rgy_faw.cpp`, AviUtl WAV writer) all operate on attacker-influenceable input files (a crafted video/chapter/audio file handed to the encoder). Several of the "Known Bugs" above (null derefs, buffer over-reads, infinite loops) are exactly the class of issue that can be weaponized as a denial-of-service or (in the worst case) memory-disclosure vector when processing a malicious input file.
- Files: `QSVPipeline/rgy_chapter.cpp`, `QSVPipeline/rgy_bitstream.cpp`, `QSVPipeline/rgy_faw.cpp`, `QSVPipeline/rgy_input_avcodec.cpp` (3,654 lines, handles demuxed input via libavformat/libavcodec — the largest attack surface for malformed containers).
- Current mitigation: Ad-hoc fixes as individual bugs are reported/found (see above); no fuzzing harness or bounds-checking framework in place.
- Recommendations: Given this is a locally-invoked CLI/plugin tool (not a network service), risk is limited to local file processing, but a lightweight fuzz target (e.g., libFuzzer harness around `rgy_chapter`/`rgy_bitstream` parse entry points) would catch this class of bug proactively rather than reactively, consistent with the pattern of bugs already found.

**No `.env`/secrets handling relevant** — this is a native CLI/plugin encoder with no network services, credentials, or remote APIs; standard web-app security concerns (auth, injection, secrets management) do not apply. The relevant security surface is exclusively "parsing untrusted local media/chapter files and command-line arguments," covered above.

## Performance Bottlenecks

**Deep zero-copy optimization work is ongoing and incremental, implying a history of copy-heavy hot paths:**
- Problem: Multiple recent commits (`075e1eef` "interopバッチacquire/releaseにより高速化" / batched interop acquire/release, `702b4823` and `5868d4e1` degrain/rtgmc zero-copy cache referencing, `b8ac0a60` "動き探索のSAD再検証・flat補正をブロック並列化" / block-parallelized SAD re-verification and flat correction) show the motion-search and denoise/deinterlace (`rtgmc`, `degrain`) VPP filter chains were previously paying redundant frame-copy and per-frame interop acquire/release overhead.
- Files: `QSVPipeline/rgy_filter_degrain.cpp`, `QSVPipeline/rgy_filter_rtgmc.cpp`, `QSVPipeline/rgy_filter_rtgmc_common.h`, `QSVPipeline/rgy_filter_rtgmc_search_prefilter.cpp`.
- Cause: The RTGMC/degrain filter chain passes frames through several internal sub-filters (search-prefilter → EDI → degrain analyze → composite), and until these recent commits each stage independently deep-copied its input into a cache rather than sharing a pooled reference.
- Improvement path: The zero-copy work is actively in progress; remaining copy-heavy call sites in the same filter family (or other multi-stage filters like `rgy_filter_kfm.cpp` at 7,679 lines, `rgy_filter_ivtc.cpp` at 4,628 lines) are candidates for the same treatment if profiling shows they are hot.

**`rgy_filter_kfm.cpp` (7,679 lines) and `rgy_filter_ivtc.cpp` (4,628 lines) are large, complex per-frame filters:**
- Problem: These implement KFM (keyframe/field-matching inverse telecine detection) and IVTC (inverse telecine), both of which do per-frame/per-field analysis; their size suggests substantial branching/parameter-combination complexity that makes performance tuning and correctness review harder than in smaller filters.
- Files: `QSVPipeline/rgy_filter_kfm.cpp`, `QSVPipeline/rgy_filter_ivtc.cpp`.
- Cause: Organic growth as parameters were added (`4c964857` "--vpp-ivtcのパラメータ追加" among others) without extraction of common helpers.
- Improvement path: If touching either file, prefer extracting well-scoped helper functions rather than adding more branches inline, to keep the already-large file navigable.

## Fragile Areas

**Linux VA-API device/driver integration:**
- Files: `QSVPipeline/qsv_hw_va_utils.cpp`, `qsv_hw_va_utils_drm.cpp`, `qsv_hw_va.cpp`, `qsv_device.cpp`.
- Why fragile: This is the platform layer with the highest recent bug-fix density (uninitialized fd close, dangling format-string args, missing `break` in status-code mapping, Wayland null-pointer crash in `WaylandCreate()` per `34742525`, multi-GPU/mixed-vendor initialization behavior per `683e77ad`). Linux GPU driver/display-server diversity (X11/Wayland, multiple Intel GPU generations, Xe driver per `1c9bcef6`) makes this code path harder to exhaustively test than the more mature Windows D3D9/D3D11 path.
- Safe modification: Any change here should be manually tested against both X11 and Wayland display servers if possible, and against systems with multiple GPUs (including non-Intel GPUs present in the same system, per `683e77ad`).
- Test coverage: None (no automated tests anywhere in the repo).

**AviUtl/AviUtl2 plugin audio path (`QSVEnc/encode/auo_encode.cpp`, `QSVEnc/prm/auo_settings.cpp`):**
- Files: `QSVEnc/encode/auo_encode.cpp` (2,142 lines), `QSVEnc/prm/auo_settings.cpp`.
- Why fragile: Several recent fixes involve WAV/PCM audio edge cases (fp32 silence padding written at half size, RF64 vs. non-RF64 size-field overflow and offset mistakes, wrong encoder-index selection between internal/external audio encoders). This suggests the audio muxing/padding logic has accumulated special cases without a shared, well-tested abstraction.
- Safe modification: Any change to WAV header writing or audio delay/padding logic should be checked against both RF64 and legacy (<4GB) WAV paths, and against both fp32 and integer PCM.
- Test coverage: None.

**Shared parameter/command layer (`rgy_prm.h`/`.cpp`, `rgy_cmd.cpp`) macro-gated across 4 encoders:**
- Files: `QSVPipeline/rgy_prm.h`, `rgy_prm.cpp`, `rgy_cmd.cpp`.
- Why fragile: Changes must be correct across `ENCODER_QSV`/`ENCODER_NVENC`/`ENCODER_VCEENC`/`ENCODER_MPP` builds simultaneously, but only the QSV build is present/buildable in this repo; NVEnc/VCEEnc/rkmppenc builds cannot be locally verified. Per `CLAUDE.md`, commonization intent is explicit but enforcement is manual (code review discipline), not automated (no CI matrix building the sibling encoder repos from this shared code).
- Safe modification: Per `CLAUDE.md` guidance, when adding a parameter decide up front whether it is QSV/libvpl-specific (`qsv_prm.h/.cpp`, `qsv_cmd.h/.cpp`) or cross-encoder shared (`rgy_prm.h/.cpp`, `rgy_cmd.h/.cpp`), and update `QSVEncC_Options.*.md` in the same change.
- Test coverage: None; correctness for the other three encoders cannot be verified from this repo at all.

## Scaling Limits

**Not applicable in the traditional sense** — this is a single-machine CLI/plugin video encoder, not a scaled service. The relevant "scaling" concerns are hardware-bound (number of Intel GPU execution units, available VRAM/system RAM for frame pools) rather than software-architectural. `QSVPipeline/rgy_parallel_enc.*` (parallel encode across multiple GPU sessions) is the closest analog; a recent fix (`177c30a4` "RGYParallelEncodeStatusData::getのロック外での二重チェックを削除" — removed a double-check outside the lock) indicates the parallel-encode status synchronization has had at least one subtle locking bug, worth extra scrutiny if extending parallel-encode functionality.

## Dependencies at Risk

**None identified as at-risk in a security/support sense.** `libvpl` (Intel's oneVPL, actively maintained upstream, last synced `2644c316` Jan 2026) and `json` (nlohmann/json-style, last synced Aug 2025) are both reasonably current. Older bundled libs (`ttmath`, `clRNG`, `tinyxml2`, `cppcodec` — see Tech Debt above) are narrow-purpose and low risk but not actively tracked for upstream updates.

## Missing Critical Features

**No fuzzing/sanitizer CI job:** Given the demonstrated bug pattern (memory-safety issues in parsers and allocators), the highest-leverage missing capability is an ASan/UBSan CI build and/or a small fuzzing harness for the input-parsing modules (`rgy_bitstream.cpp`, `rgy_chapter.cpp`, `rgy_faw.cpp`), rather than a new product feature.

**No regression/unit test harness:** There is no way to pin down "this specific bug, once fixed, stays fixed" other than manual re-testing. Any future refactor of `rgy_util.cpp` string-trimming (`lstrip`/`rstrip`), bitstream parsing, or the allocator classes carries meaningful regression risk with no automated safety net.

## Test Coverage Gaps

**Entire codebase (100%):**
- What's not tested: There is no unit test framework, no integration test suite, and no CI job that runs an actual encode and validates output. All validation is manual.
- Files: entire repo.
- Risk: Every change — including the shared `rgy_*` files consumed by three sibling encoder projects — relies entirely on manual review and ad-hoc manual testing to catch regressions. The 58/300-commit recent bug-fix rate is direct evidence of the cost of this gap.
- Priority: High — even a minimal unit test target covering pure-function utilities (`rgy_util.cpp` string helpers, `rgy_bitstream.cpp` parsing functions, `rgy_chapter.cpp` parsers) would have caught several of the bugs listed above (inverted `rgy_is_pow2`, `lstrip`/`rstrip` off-by-ones, NAL/OBU out-of-range reads) without requiring GPU hardware or real video files.

---

*Concerns audit: 2026-07-23*
