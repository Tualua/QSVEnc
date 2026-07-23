# Architecture Research

**Domain:** Concurrent Intel QSV AV1 hardware-encode correctness investigation (cross-process GPU surface isolation + reproduction/diagnosis harness)
**Researched:** 2026-07-23
**Confidence:** MEDIUM overall — HIGH for the qsvencc/libva/iHD userspace chain (read directly from source in this repo), MEDIUM for the i915 GEM/GuC/Xe kernel-boundary mechanism (grounded in kernel docs + known race classes, not confirmed against i915 source line-by-line), LOW-to-MEDIUM for "why Xe helps" (architecturally plausible, empirically untested on this hardware)

---

# Part 1 — The Isolation Stack (where correctness breaks)

## System Overview

```
┌───────────────────────────────────────────────────────────────────────────────────┐
│ PROCESS A (qsvencc session, scene 923)   │  PROCESS B (qsvencc session, scene 928) │
│                                           │                                         │
│ CQSVPipeline::AllocFrames()              │  CQSVPipeline::AllocFrames()            │
│  qsv_pipeline.cpp:1708-1822              │   (identical logic, separate process)   │
│  ── ONE mfxFrameAllocRequest per         │                                         │
│     adjacent task-pair, Type is          │                                         │
│     OR-COMBINED across roles:            │                                         │
│     FROM_DECODE | FROM_VPPIN | FROM_ENCODE (qsv_pipeline.cpp:1789-1803)            │
│  ── AllocId = 0 unless externalAlloc()   │                                         │
│     (qsv_pipeline.cpp:1805)              │                                         │
│         ↓                                │         ↓                               │
│ QSVAllocatorVA::AllocImpl()              │  QSVAllocatorVA::AllocImpl()            │
│  qsv_allocator_va.cpp:267                │   (own m_dpy, own vaapi_mids[] array)   │
│  ── single vaCreateSurfaces() batch      │                                         │
│     call for the WHOLE combined-role     │                                         │
│     pool (P010 / VA_FOURCC_P010)         │                                         │
│         ↓                                │         ↓                               │
├───────────────────────────────────────────────────────────────────────────────────┤
│                  libva (process-local VADisplay m_dpy, own /dev/dri fd)            │
├───────────────────────────────────────────────────────────────────────────────────┤
│                  iHD (media-driver) — Gen backend, internal buffer manager         │
│                  derives GEM BOs for each VASurfaceID it creates                   │
├───────────────────────────────────────────────────────────────────────────────────┤
│           DRM ioctls: GEM_CREATE / GEM_EXECBUFFER2 / GEM_CONTEXT_CREATE            │
│           on the SAME shared /dev/dri/renderD128 (one physical GPU, one node)      │
├───────────────────────────────────────────────────────────────────────────────────┤
│  drm/i915 kernel driver                                                            │
│  ── per-fd GEM handle IDR (integers are process-local — NOT the bug)              │
│  ── full-PPGTT per-context virtual address space (isolates VA, not BO lifecycle)  │
│  ── GuC firmware owns scheduling once enabled: contexts are registered and        │
│     submitted/retired by GuC, "outside kernel driver control" (kernel.org docs)   │
│  ── shared kernel-global BO retire-tracking / eviction / shrinker infrastructure  │
│     — this layer is NOT partitioned per calling process                          │
│         ↓ ↑ (suspected aliasing surface)                                         │
│  ⚠ SUSPECTED FAULT: a 10-bit P010 reference BO from Process A's reorder window   │
│     (still GPU-referenced because of B-pyramid ref-dist-6 lifetime) is retired/  │
│     recycled by the shared kernel-side bookkeeping and its backing store handed  │
│     to Process B's next same-shape (P010, same WxH) allocation before A's GPU    │
│     read has actually completed — content aliasing, NOT a crash, NOT a frame-    │
│     count error. Confidence: MEDIUM (mechanism inferred from doc facts + known   │
│     i915 handle/refcount race class; not confirmed against i915 source).        │
└───────────────────────────────────────────────────────────────────────────────────┘
```

**Contrast — ffmpeg `av1_qsv` (immune, 35/35 clean under identical trigger triad):**

```
Process: ffmpeg -hwaccel qsv (h264_qsv decode) → vpp_qsv (format=p010le) → av1_qsv encode
  AVHWFramesContext[decode]  ── own AllocId, own vaCreateSurfaces pool, decode-only role
  AVHWFramesContext[vpp]     ── own AllocId, own pool, vpp-only role
  AVHWFramesContext[encode]  ── own AllocId, own pool, encode-only role
        ↓ (three separate, single-role pools instead of one OR-combined pool)
  same libva → iHD → i915/GuC path as qsvencc
```

Both paths terminate in the *same* kernel/driver stack on the *same* GPU. The only architectural difference upstream of the kernel is **pool topology**: qsvencc requests one pool whose `mfxFrameAllocRequest.Type` is the bitwise-OR of every role that touches it (decode target *and* vpp input *and* encode reference all alias the same surface set), while ffmpeg's `AVHWFramesContext` gives each pipeline stage its own separately-allocated, separately-`AllocId`'d pool. This is the load-bearing empirical fact the whole investigation hangs on (prior session, ffmpeg control run).

## Component Responsibilities

| Component | Responsibility | Location / Evidence |
|-----------|----------------|------------------------|
| `CQSVPipeline::AllocFrames` | Decides one shared `mfxFrameAllocRequest` per adjacent task-pair boundary; OR-combines `MFX_MEMTYPE_FROM_DECODE\|FROM_VPPIN\|FROM_ENCODE` bits depending on which `PipelineTask` types sit on each side | `QSVPipeline/qsv_pipeline.cpp:1708-1822` (read directly, HIGH confidence) |
| `QSVAllocatorVA::AllocImpl`/`ReallocImpl` | Translates one `mfxFrameAllocRequest` into one `vaCreateSurfaces()` batch call (P010 → `VA_FOURCC_P010`, no `rt_format` override needed since `VASurfaceAttribPixelFormat` is set explicitly) | `QSVPipeline/qsv_allocator_va.cpp:267,189` (read directly, HIGH confidence) |
| libva (VA-API) | Process-scoped dispatch layer; one `VADisplay` (`m_dpy`) per process, wraps DRM fd | external lib, HIGH confidence (standard VA-API contract) |
| iHD (media-driver) | Gen-specific VA-API backend; derives GEM buffer objects for VA surfaces via its own internal buffer manager; **already ruled out** as the fault site — swapping iHD 25.2.3→26.2.2 on the same kernel had zero effect (prior session, HIGH confidence, negative result) |
| drm/i915 (kernel) | Owns GEM object lifecycle, per-context PPGTT (address-space isolation only), and — when GuC submission is enabled — hands scheduling/retirement to firmware | kernel.org i915 docs (MEDIUM confidence — mechanism-level, not code-line-level) |
| GuC firmware | Batches/retires HW contexts; i915 docs state engine resets and fine-grained submission ordering move "outside kernel driver control" once GuC owns it | kernel.org `i915_scheduler.html` (MEDIUM confidence) |
| `AVHWFramesContext` (ffmpeg, contrast case) | One frame pool per pipeline role, each with its own `AllocId`; empirically immune (35/35 clean) under the identical trigger triad | prior session control experiment (HIGH confidence — empirical, reproduced) |

## Architectural Patterns

### Pattern 1: OR-combined shared surface pool (qsvencc — the fault-adjacent pattern)

**What:** A single `mfxFrameAllocRequest`/VA surface pool is reused across every pipeline role that touches a given frame (decode output doubles as VPP input doubles as encode reference), distinguished only by an OR'd bitmask (`qsv_pipeline.cpp:1789-1803`).
**When it appears:** Any `qsvencc`-family (rgy_*-based) pipeline stage boundary where two adjacent `PipelineTask`s both want a `mfxFrameAllocRequest` (`AllocFrames`, `qsv_pipeline.cpp:1742-1747` picks the higher-priority request and unions the surface count).
**Trade-offs:** Minimizes surface count / VRAM footprint and avoids redundant copies — this is *why* it exists, and it is provably correct single-process (bit-identical single-session encode, 0% defects). Under concurrent multi-process submission on the same GPU it is the empirically-implicated pattern: identical trigger triad through ffmpeg's per-role-pool design is clean.
**Confidence:** HIGH that this is the pattern (source-read); MEDIUM that pool topology (rather than something else correlated with it) is causally responsible — this is the load-bearing untested causal claim of the whole investigation.

### Pattern 2: Per-component pool separation (ffmpeg `AVHWFramesContext` — the immune pattern)

**What:** Each pipeline stage (decode/vpp/encode) gets its own hardware frames pool with its own `AllocId`, even though all three still ultimately call `vaCreateSurfaces` against the same VADisplay/kernel/GPU.
**When to use:** Already the ffmpeg default for `-hwaccel qsv` pipelines; not a qsvencc option today (out of scope per PROJECT.md §5 — allocator-line patching of qsvencc is analytically exhausted).
**Trade-offs:** More surfaces / more VA objects allocated (three pools instead of one merged pool) but empirically immune to the cross-session corruption under the identical trigger triad. Costs some memory, not throughput, per prior findings.
**Confidence:** MEDIUM on mechanism (pool separation *correlates* with immunity; the causal "why" — i.e., exactly what kernel-side bookkeeping a merged pool defeats — is inferred, not proven against i915 source).

### Pattern 3: Full-PPGTT per-context address-space isolation (i915) vs VM_BIND explicit binding (Xe)

**What:** i915 gives every GEM context its own page-table-level GPU virtual address space ("full-ppgtt... ensures complete separation of one client from all others" — kernel.org i915 docs). This isolates *where a context's memory appears in GPU address space*, but does **not** isolate the *lower-level bookkeeping of when a physical BO's backing store is considered idle/retirable/reusable* — that retire-tracking, eviction, and (once GuC is enabled) scheduling/retirement itself is shared kernel/firmware-global infrastructure, not partitioned per calling process. Xe's memory model is described (kernel.org Xe docs) as being based solely on `VM_BIND` — explicit, persistent GPU-virtual-address bind/unbind of BOs — with execution supporting only *explicit* synchronization (no implicit kernel-managed relocation/exec-list construction per submission, which is the legacy i915 execbuffer2 path Xe never carries). Xe is also GuC-only from inception (no legacy ring/execlist fallback path to maintain), reducing the kernel-side code-path surface where an implicit "is this buffer still needed by another context" ambiguity could hide.
**When it matters here:** The corruption is a *silent aliasing* defect, i.e., exactly the failure mode that lives in ambiguous/implicit buffer-lifetime bookkeeping rather than in address-space collision (address-space collision would typically produce a hard fault, not a plausible-looking wrong frame). Because Xe requires userspace to explicitly manage bind lifetime and explicit sync per submission, the class of implicit "kernel silently decides this BO is free to reuse" bugs that plausibly explain this symptom has structurally less surface to exist in.
**Trade-offs / caveats:** This is an architectural *hypothesis for why Xe is the most promising untried lever* (§6 of the handoff), **not a confirmed fix** — it has not been empirically tested on this Arc A380/DG2 hardware in this investigation yet, and DG2 (Alchemist) support in the Xe driver has historically lagged newer generations (Meteor Lake+/Battlemage/Ponte Vecchio were the initial Xe targets); confirming Xe actually enumerates and drives this specific GPU on the available kernel is a prerequisite, not a given.
**Confidence:** LOW-MEDIUM — grounded in real architectural differences documented by the kernel project itself, but the causal link to *this specific bug* is inference, and hardware-driver-version support is unverified for this environment.

## Anti-Patterns (for the investigation, not just the code)

### Anti-Pattern 1: Re-attributing the bug to iHD/userspace after a version bump shows no change

**What people do:** See "same frequency/signature after iHD 25.2.3→26.2.2" and conclude "must be something else in userspace, keep patching qsvencc."
**Why it's wrong:** This negative result is exactly the evidence that already located the fault *below* userspace (prior session, §3/§5 — already exhausted, do not repeat). Re-litigating userspace patches wastes GPU-exclusive experiment cycles that are a scarce, sequential resource in this single-GPU environment.
**Do this instead:** Treat "iHD swap = zero effect" as closing the userspace hypothesis space permanently; all new experiment cycles go to kernel/driver-model levers (i915 config, GuC/HuC firmware, Xe) or to the ffmpeg/av1_vaapi comparison, not to further qsvencc source patches.

### Anti-Pattern 2: Testing a lever without an immune-control run in the same batch

**What people do:** Flip a host-side lever (e.g. switch to Xe) and run only the qsvencc concurrent case; observe 0 corrupt frames; declare victory.
**Why it's wrong:** A clean qsvencc run under a new environment is ambiguous — it could mean the lever fixed the kernel-side bug, or it could mean the harness itself silently broke (wrong hotspot offset after a decoder version changed reordering, wrong PSNR reference frame, extraction pointing at the wrong file, etc.), producing a false "fixed" signal. The prior session's own methodology already treats the ffmpeg immune-control as mandatory validation, not optional.
**Do this instead:** Every lever test batch must include the ffmpeg `av1_qsv` immune-control run against the *same* harness invocation. If the control ever stops being clean (or the qsvencc run ever goes clean but the control run also silently degrades), the environment change is confounded and the result is not a conclusion — see the Investigation Build Order below.

---

# Part 2 — The Investigation System (reproduction + verification harness)

## System Overview

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│ ENVIRONMENT PROBE  (uname -r; /sys/kernel/debug/dri/*/name; vainfo; qsvencc          │
│ --check-features)                                                                    │
│  → tags every downstream measurement with {kernel, i915|xe, GuC/HuC fw, iHD version} │
└───────────────────────────────┬───────────────────────────────────────────────────────┘
                                 │ (independent variable, attached to every report row)
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│ CORPUS / FIXTURE PROVIDER                                                            │
│  /data/downloads/Cold.Eyes.2013.Bluray.Remux.mkv (read-only)                        │
│  fixed scene table: {923, 928, 1129} with exact seek/trim + known hotspot offset    │
└───────┬───────────────────────────────────────────┬───────────────────────────────────┘
        │                                            │
        ▼                                            ▼
┌───────────────────────────┐        ┌───────────────────────────────────────────────┐
│ REFERENCE-ENCODE RUNNER    │        │ CONCURRENT-ENCODE RUNNER                       │
│ single isolated qsvencc    │        │ N-way simultaneous invocations (bash & + wait, │
│ session per scene → bit-   │        │ mirrors enpipe's ThreadPoolExecutor(jobs=3))   │
│ exact "golden" chunk .obu  │        │ parameterized by:                              │
│ (0% defect baseline)       │        │  - encoder-path: qsvencc | ffmpeg av1_qsv (ctrl)│
└──────────┬──────────────────┘        │  - environment (tagged by Environment Probe)  │
           │                          │  - iteration count (15-20+ per batch)          │
           │                          └──────────────────┬──────────────────────────────┘
           ▼                                             ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│ FRAME EXTRACTION  (ffmpeg, encoder-path-agnostic: consumes any .obu/.mp4 + known     │
│ frame offset; decodes to PNG/raw via -vf select=eq(n,OFFSET) or per-frame -vsync 0)  │
└───────────────────────────────┬───────────────────────────────────────────────────────┘
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│ PSNR/VMAF METRIC ENGINE  (ffmpeg lavfi psnr / libvmaf, reference frame vs test frame;│
│ NOTE: NOT qsvencc --psnr/--ssim — those require OpenCL and must not be a dependency) │
└───────────────────────────────┬───────────────────────────────────────────────────────┘
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│ CORRUPTION CLASSIFIER  (threshold: PSNR < 30 dB ⇒ corrupt; expect deterministic      │
│ ~15.74 dB signature match, not merely "below threshold" — a novel low-PSNR value     │
│ under a new environment is a DIFFERENT finding, not confirmation of the known bug)   │
└───────────────────────────────┬───────────────────────────────────────────────────────┘
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│ THROUGHPUT / PERF SAMPLER  (fps, wall-clock per config — required to back the        │
│ enpipe recommendation with measured numbers, not just correctness)                   │
└───────────────────────────────┬───────────────────────────────────────────────────────┘
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────────────┐
│ CORRUPTION-RATE REPORT  (scene × iteration × environment-variant × encoder-path      │
│ → aggregate frequency %, signature-match confirmation, throughput deltas)            │
└───────────────────────────────┬───────────────────────────────────────────────────────┘
                                 ▼
                    enpipe recommendation + host-side conclusion + upstream report

  (separate, root-cause-independent branch — reuses the Metric Engine only)
┌─────────────────────────────────────────────────────────────────────────────────────┐
│ DEFENSE-IN-DEPTH CONTENT GATE (design/prototype)                                     │
│  final joined movie.obu vs source → VMAF/PSNR gate, replaces count_frames-only check │
│  consumes: Metric Engine component only — does NOT depend on which lever/workaround  │
│  is chosen, and does NOT depend on root-cause conclusion                             │
└─────────────────────────────────────────────────────────────────────────────────────┘
```

## Component Responsibilities

| Component | Responsibility | Talks to |
|-----------|----------------|----------|
| Environment Probe | Captures `{kernel version, i915 vs xe, GuC/HuC firmware version, iHD version, oneVPL API version}` once per environment/lever configuration; every other component's output must be tagged with this | Nothing upstream; tags all downstream reports |
| Corpus/Fixture Provider | Owns the fixed, already-validated scene table (923/928/1129: frame ranges, seek/trim strings, hotspot offsets, expected corrupt-frame indices) and read-only access to the source `.mkv`; never writes to `/data` | Reference-Encode Runner, Concurrent-Encode Runner |
| Reference-Encode Runner | Runs one isolated `qsvencc` session per scene (no concurrency) to produce the bit-exact "golden" chunk + extracted reference frame at the hotspot offset | Corpus/Fixture Provider → Frame Extraction |
| Concurrent-Encode Runner | Launches N simultaneous sessions (3-way baseline; parameterizable encoder-path: `qsvencc` vs ffmpeg `av1_qsv` control) mirroring enpipe's `ThreadPoolExecutor(max_workers=JOBS)`; repeats for M iterations per batch | Corpus/Fixture Provider → Frame Extraction |
| Frame Extraction | Encoder-path-agnostic: given any bitstream file + known frame offset, produces a comparable decoded frame (PNG/raw) — must not special-case qsvencc vs ffmpeg outputs | Reference/Concurrent runners → Metric Engine |
| PSNR/VMAF Metric Engine | Computes reference-vs-test frame similarity via external ffmpeg (`-lavfi psnr` or `libvmaf`) — explicitly not via `qsvencc --psnr/--ssim` (OpenCL dependency to avoid per PROJECT.md metrics constraint) | Frame Extraction → Corruption Classifier; also reused standalone by the Content Gate |
| Corruption Classifier | Applies the deterministic-signature check (not just a raw threshold) so that a "clean" result under a new lever is trustworthy and a "corrupt" result under a new environment is recognizably the *same* bug (or flagged as a new one) | Metric Engine → Corruption-Rate Report |
| Throughput/Perf Sampler | Measures fps/wall-clock per candidate configuration (needed to satisfy the Active requirement "recommendation backed by measured throughput numbers") | Concurrent-Encode Runner → Corruption-Rate Report |
| Corruption-Rate Report | Aggregates frequency %, signature match, and throughput across the {scene × iteration × environment × encoder-path} matrix; this is the artifact the roadmap's "resolve host/kernel fork" and "test untried levers" requirements consume directly | All upstream components → recommendation/upstream-report authors |
| Immune-Control (ffmpeg `av1_qsv`) | Not a separate pipeline stage — a *parameterization* of the Concurrent-Encode Runner/Frame Extraction/Metric Engine/Classifier chain that must be run in the same batch as every qsvencc/lever measurement, to validate the harness itself | Runs through every component above, in parallel with the qsvencc path |
| Defense-in-Depth Content Gate | Production-pipeline component (belongs conceptually to `enpipe`, not the diagnostic harness) that reuses the Metric Engine as a library to gate final joined output vs source; explicitly root-cause-independent | Consumes Metric Engine only; does not consume Classifier/Report |

## Data Flow

**Primary diagnostic flow:** Environment Probe tags a run → Corpus/Fixture Provider supplies scene parameters → Reference-Encode Runner and Concurrent-Encode Runner both produce bitstreams → Frame Extraction decodes the known hotspot offset from each → Metric Engine scores test-vs-reference → Corruption Classifier labels each iteration clean/corrupt (with signature check) → Corruption-Rate Report aggregates across the {scene, iteration, environment, encoder-path} matrix → feeds both the host-side conclusion and the enpipe recommendation.

**Control flow (parallel, mandatory):** The identical pipeline is parameterized with `encoder-path = ffmpeg av1_qsv` and run in the same batch as every qsvencc/lever measurement; its output is not a separate report but a validity gate on the qsvencc measurement in the same row.

**Content-gate flow (independent branch):** Final joined `movie.obu` (from the *production* enpipe pipeline, any chosen workaround) → Metric Engine (reused, not the full harness) → gate decision. This branch never touches the Corruption Classifier or Report — it is deliberately decoupled from which root cause/lever/workaround was chosen, per PROJECT.md's defense-in-depth requirement.

## Investigation Build Order

| Order | Step | Depends on | Why this order |
|-------|------|-------------|-----------------|
| 0 | Environment Probe run | — | Must tag the environment before any measurement is meaningful (the whole investigation hinges on the same-kernel/different-kernel fork, PROJECT.md §6) |
| 1 | Build harness components (Corpus, Reference Runner, Concurrent Runner, Frame Extraction, Metric Engine, Classifier, Report) targeting the default i915 environment | Step 0 | **Harness before levers** — no lever (Xe, firmware, `--avsw`, `--jobs 1`) can be evaluated without a working, calibrated measurement instrument; building the harness is the critical path for everything else |
| 2 | Run the ffmpeg `av1_qsv` immune-control through the harness; confirm 0/N clean | Step 1 | **Immune-control before conclusions** — validates that Frame Extraction/Metric Engine/Classifier are correctly wired (right offset, right reference frame, right PSNR interpretation) using a path *known* to be clean. A clean result here is necessary before any qsvencc result (clean or corrupt) can be trusted. If the control is not clean, the harness itself is broken — do not proceed to interpret qsvencc results. |
| 3 | Run qsvencc concurrent baseline on the default/current environment; confirm reproduction, frequency, and signature match the handoff's prior numbers (~33-65%, ~15.74 dB) | Step 2 | Establishes the pre-lever baseline that every subsequent lever result is diffed against; also resolves the "does this host reproduce the bug at all" fork from PROJECT.md Context |
| 4 | Test levers, one at a time (GPU is a single shared resource — sequential, per PROJECT.md Constraints), each re-running steps 2+3 under the new configuration and re-running Environment Probe to confirm what actually changed: (a) i915 config/firmware update, (b) switch to Xe driver, (c) `av1_vaapi` quiet path | Step 3 | Each lever test is only interpretable relative to the validated baseline and re-validated control; testing levers before the harness/control are solid would produce ambiguous or false results (Anti-Pattern 2 above) |
| 5 (parallel with 4) | Design/prototype the Defense-in-Depth Content Gate, reusing the Metric Engine component only | Step 1 (Metric Engine must exist) — explicitly NOT steps 3/4 | **Content-gate independent of root-cause** — this deliverable must ship regardless of which lever wins or whether host-side levers succeed at all; blocking it on root-cause conclusions would idle a large chunk of the investigation for no dependency-driven reason |
| 6 | Throughput/Perf Sampler measurements on every surviving candidate configuration (host-fix, or each enpipe workaround A/B/C) | Steps 3-4 results known | Recommendation must be "backed by measured throughput numbers in this environment" (PROJECT.md Active requirement) — cannot sample throughput for configurations not yet identified as correctness-clean |
| 7 | Synthesize enpipe recommendation + host-side conclusion + (if warranted) upstream drm/i915 report | Steps 4, 5, 6 | Final deliverable; depends on all diagnostic and content-gate branches converging |

## Anti-Patterns (harness-specific)

### Anti-Pattern 1: Trusting a raw PSNR threshold instead of the deterministic signature

**What people do:** Classify any frame below 30 dB as "the bug," without checking whether the corrupted content matches the known deterministic cross-scene signature.
**Why it's wrong:** Under a new environment/lever, a different low-PSNR artifact (e.g., a genuine encoder bug, a decode error, an unrelated driver regression) could be misattributed to this specific corruption class, corrupting the conclusion about whether the *lever* worked.
**Do this instead:** The Classifier should report both "below threshold" and "matches known signature" as separate booleans; a lever that eliminates the known signature but introduces a different low-PSNR artifact is a different, new finding, not "still broken."

### Anti-Pattern 2: Running qsvencc metrics through `--psnr`/`--ssim`

**What people do:** Reach for qsvencc's built-in quality metrics for convenience.
**Why it's wrong:** They require OpenCL, which is not guaranteed present in every environment this harness runs in (PROJECT.md metrics constraint); making the harness depend on it makes reproduction environment-fragile for a reason unrelated to the bug being investigated.
**Do this instead:** Always compute PSNR/VMAF via an external, encoder-path-agnostic ffmpeg invocation on extracted frames/files.

### Anti-Pattern 3: Writing harness intermediates or extracted frames into `/data`

**What people do:** Use the source directory as scratch space because it's convenient and (in this environment) writable.
**Why it's wrong:** Violates the project's explicit data-safety constraint (`/data` sources are read-only-by-policy even if writable); risks contaminating the very source the reference/control comparisons depend on.
**Do this instead:** All harness outputs (chunks, extracted frames, reports) go to an isolated writable workdir, never `/data`.

## Integration Points

### External Services / Tools

| Tool | Integration Pattern | Notes |
|------|---------------------|-------|
| `qsvencc` (built from source in this repo, r4386+) | Subprocess invocation via CLI flags matching `chunk.py::chunk_command`'s exact recipe | Do not re-patch its allocator source (out of scope, analytically exhausted) |
| ffmpeg (`av1_qsv`, decode/extraction, PSNR/VMAF) | Subprocess invocation; used both as the immune-control encoder-path and as the encoder-agnostic metric/extraction engine | Must be pinned/version-recorded alongside Environment Probe output since ffmpeg's own QSV/VA-API glue could in principle shift with driver updates |
| `vainfo` / `/sys/kernel/debug/dri/*/name` / `uname -r` | Shell invocation, parsed for environment tagging | Cheap, must run before every batch, not just once at session start (host-side lever tests change this mid-investigation) |
| Xe kernel driver (untested lever) | Requires host-side driver switch outside any container (PROJECT.md host boundary) | Prerequisite check: confirm Xe actually enumerates/drives this Arc A380 (DG2/Alchemist) on the available kernel before spending an experiment cycle on it |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Concurrent-Encode Runner ↔ Frame Extraction | File handoff (bitstream path + known offset) | Must be encoder-path-agnostic — the same extraction code serves qsvencc and ffmpeg outputs, or the harness cannot validate itself via the immune-control |
| Metric Engine ↔ Corruption Classifier | Numeric PSNR/VMAF score + reference metadata (expected signature value) | Classifier owns the "is this the known bug" judgment; Metric Engine stays a dumb, reusable scorer so the Content Gate can consume it independently |
| Corruption-Rate Report ↔ Content Gate | None (deliberately no shared dependency) | Enforces "content-gate independent of root-cause" — if this boundary were coupled, the content-gate deliverable would be blocked on root-cause conclusions it doesn't need |
| Environment Probe ↔ everything else | One-way tagging, no feedback | Probe never consumes other components' output; every report row carries its tag |

## Sources

- `QSVPipeline/qsv_pipeline.cpp:1708-1822` (`CQSVPipeline::AllocFrames`) — read directly from this repo, HIGH confidence
- `QSVPipeline/qsv_allocator_va.cpp` (`QSVAllocatorVA::AllocImpl`/`ReallocImpl`/`ReleaseResponse`) — read directly from this repo, HIGH confidence
- `/workspaces/QSVEnc/PROJECT.md` (prior-session handoff: root-cause chain §3, reproducer protocol §4, negative results §5, untested levers §6, solution space §7, enpipe touchpoints §8) — HIGH confidence for what was empirically established, explicitly flagged as hypothesis for what remains untested
- `.planning/PROJECT.md` (this milestone's requirements/constraints/context) — project framing
- `.planning/codebase/ARCHITECTURE.md` (QSVEnc pipeline/task-graph/allocator structure) — HIGH confidence, prior codebase analysis
- Linux kernel documentation, "I915 GuC Submission/DRM Scheduler" (https://docs.kernel.org/gpu/rfc/i915_scheduler.html) — MEDIUM confidence, official docs, WebSearch-surfaced and cross-checked against multiple mirrors (kernel.org, docs.kernel.org)
- Linux kernel documentation, "Xe – Merge Acceptance Plan" (https://www.kernel.org/doc/html/v6.8/gpu/rfc/xe.html) — MEDIUM confidence, official docs; describes VM_BIND-only memory model and explicit-sync execution
- `drm/i915 Intel GFX Driver` kernel docs (https://docs.kernel.org/gpu/i915.html) — MEDIUM confidence, official docs; full-PPGTT per-context isolation statement
- Known i915 GEM handle/refcount race class (concurrent `gem_close` + PRIME handle swap leaving a dangling IDR entry) surfaced via WebSearch — LOW-MEDIUM confidence, cited as evidence that *a class* of cross-boundary BO/handle races has precedent in this driver, not as the specific bug
- `intel/media-driver#1626` (only public corroborating report — loud failure on an older stack; this investigation's variant is silent) — per prior-session handoff, not independently re-verified in this research pass

---
*Architecture research for: QSV concurrent-encode frame-corruption investigation (isolation stack + diagnostic harness)*
*Researched: 2026-07-23*
