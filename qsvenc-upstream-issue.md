# [BUG] Silent single-frame corruption when several QSVEncC instances encode concurrently (AV1 10-bit, --avhw, B-pyramid, Arc A380, Linux)

### Description

When 2 or more `qsvencc` processes encode at the same time on one Intel Arc A380, the output occasionally contains **one corrupted frame**. The encode finishes normally, with no error or warning, and the **frame count is correct**, so the corruption is silent.

- A single-session encode of the same chunk is **bit-exact** across runs (identical md5).
- Under 3-way concurrency, the same chunk is corrupted in roughly **30–45 % of runs**.
- When it happens, the corrupted frame is **always at the same position** (same frame index of the same chunk), and its PSNR against the clean single-session encode is **~12.8 dB** with σ 0.03 dB across runs. The value is effectively deterministic.
- The bad frame is not a duplicate of any neighbouring frame (±5 frames). It is also not a clean copy of a frame from the other concurrently encoded chunks: the best PSNR against them is 10.5–18.6 dB.

This looks like the same defect as **#308** ("Encoded video occasionally displays a frame from the previous scene after a scene cut"). That report has the same GPU (Arc A380), Linux in Docker, B-pyramid, intermittent occurrence and a stable frame position when it occurs.

### Trigger conditions

All of the following are needed (from our earlier investigation). Removing any single one gave 0 defects:

1. HW decode into VA memory: `--avhw` (with `--va`)
2. 10-bit output: `--output-depth 10` (P010 surfaces; VPP `nv12 -> p010`)
3. B-frame reordering: `--gop-ref-dist 6 --b-pyramid`
4. ≥ 2 concurrent `qsvencc` processes on the same GPU

### Reproduction

Source: 1920x1080 H.264 8-bit 24 fps Blu-ray remux. We can share exact scene positions, but not the file. We have not yet tested other sources. Three chunks of the same file are encoded at the same time:

```sh
COMMON="-c av1 --icq 24 --qp-max 100 --output-depth 10 --profile main \
  --gop-len 300 --gop-ref-dist 6 --b-pyramid --tile-col 1 --tile-row 1 \
  --tune perceptual --scenario-info archive \
  --colorrange auto --colormatrix auto --colorprim auto --transfer auto --chromaloc auto"

qsvencc --avhw --va -i src.mkv $COMMON --seek 01:16:14.167 --trim 0:339 -o c923.obu  &
qsvencc --avhw --va -i src.mkv $COMMON --seek 01:17:00.667 --trim 0:110 -o c928.obu  &
qsvencc --avhw --va -i src.mkv $COMMON --seek 01:34:24.583 --trim 0:361 -o c1129.obu &
wait
```

Each output frame at the known position is compared, using external ffmpeg PSNR, with the bit-exact single-session reference of the same chunk. PSNR < 30 dB counts as corrupt.

QSVEncC log of one of the sessions (8.22):

```
Input Info     avqsv: H.264/AVC, 1920x1080, 24/1 fps
VPP            ColorFmtConvertion: nv12 -> p010
Buffer Memory  va, 43 work buffer
Output         AV1(yuv420 10bit) main @ Level 4
GopRefDist     6, B-pyramid: on
```

### Results (N = 20 iterations of 3-way concurrency)

| chunk / frame | QSVEncC 8.22 (r4385) | QSVEncC 8.31 (r4604, built from tag) | 8.31 + patch below (N = 60) |
|---|---|---|---|
| 923 / 299 | 9/20 (45 %) | 7/20 (35 %) | 0/60 (0 %) |
| 1129 / 299 | 8/20 (40 %) | 6/20 (30 %) | 0/60 (0 %) |
| 928 / 96 | 0/20 | 0/20 | 0/60 |
| ffmpeg `av1_qsv` control, 3-way concurrent | 0/20 | 0/20 | 0/60 |

Corrupt-frame PSNR: 12.96 dB (8.22) / 12.83 dB (8.31). The defect is unchanged in 8.31. With the patch, the whole-file md5 of all 180 outputs (60 iterations x 3 chunks) is identical to the single-session reference. We state the result only as: residual per-iteration corruption rate <= 5 % (rule of three, 0/60; exact one-sided 95 % bound 4.87 %); this is not a proof that the defect is gone.

### Mechanism (what we found)

The corrupted frame is a **stale input surface from the same encode session**, not data from another session. In 30/30 corrupt outputs (13 on 8.31, 17 on 8.22) the bad output frame is a near-copy (PSNR 47-57 dB) of an earlier frame of the same chunk (frames 289, 290, 291 or 294), and the damage is confined to output frames 295..299, i.e. the final truncated mini-GOP before the forced IDR at frame 300. That is, the encoder reads the wrong (stale) content of a surface it was handed.

The defect behaves like a **timing window** in the decode -> VPP -> encode surface hand-off:

- A consumer-side wait on the VPP output syncpoint before `EncodeFrameAsync` removes it (0/20 in the first screen, 0/60 in the validation run).
- A wait on the decode output before the VPP removes it as well (0/20).
- A plain `sleep` before `EncodeFrameAsync` with **no** syncpoint wait also removes it (4 ms: 0/20; 850 us, equal to the measured mean wait: 0/20, at 5-16 % lower fps), so the cure does not need a real ordering edge.
- Slowing the pipeline (`--max-procfps 60`) or running with `LIBVA_TRACE` (about -26 % fps) also hides it.
- Round-robin surface reuse and larger pools (+16) do not remove it, and the pools are not exhausted.

We therefore describe the patch as a **timing workaround** that serializes the VPP -> encoder hand-off (as ffmpeg's `vpp_qsv` -> encoder path does), not as proof of a missing API-level ordering. We could not observe the underlying ordering failure directly; our reading is that it is below the API (driver/kernel), but we have not shown that.

### Proposed patch

`0001-Wait-for-the-VPP-output-syncpoint-before-encoding-to.patch` (against tag 8.31, one file `QSVPipeline/qsv_pipeline_ctrl.h`, 5 added lines, no new option):

```cpp
// in PipelineTaskMFXEncode::sendFrame(), after the frame-type check
// wait for the producer's syncpoint (VPP) before the encoder reads the surface;
// otherwise the encoder can read a stale input surface when several sessions share the GPU
if (frame) { // frame is nullptr on the flush call
    frame->waitsync();
}
```

Measured cost: with 3-way concurrency the fps is unchanged within noise (60-iteration means 227.0 / 129.9 / 229.0 vs stock 226.6 / 131.2 / 230.1 for chunks 923 / 928 / 1129). A single session without contention shows no significant cost when stock and patched builds are run back to back (8.31: 315.1 / 227.1 / 315.2 fps stock vs 316.5 / 226.0 / 311.3 patched; upstream master 15cd6879, 6 encodes per chunk: 313.2 / 229.0 / 313.2 vs 312.9 / 222.5 / 311.9, i.e. -0.1 / -2.9 / -0.4 %); an earlier measurement that showed -9 to -19 % was not reproducible and is superseded. Single-session output stays bit-exact (6/6 identical md5). The patch has been tested only on this configuration (Arc A380, 3-way, these three chunks), and we have not tried to narrow it to multi-session use.

### What we have ruled out

- **ffmpeg does not show it.** The same combination in ffmpeg (h264_qsv HW decode → `vpp_qsv=format=p010le` → `av1_qsv`, `-bf 5`), run 3-way concurrently on the same machine, is clean: 0/20 in this test and 35/35 earlier. So the driver can handle concurrent sessions correctly in this configuration.
- **Surface lifetime/reuse and pool size are not the cause by themselves.** Round-robin surface reuse (instead of lowest-index-first) still corrupted; adding 16 surfaces to each pool still corrupted; the pool dump shows two per-edge pools (decode->VPP 23 surfaces, VPP->encode 20 surfaces) with no retries, i.e. no exhaustion.
- **`--tune perceptual --scenario-info archive` are not the cause:** removing both still corrupted (1 of 11 iterations).
- **Upgrading the userspace stack does not help.** Replacing the whole userspace media stack (iHD 25.2.3 → 26.2.2, vpl-gpu-rt, libva 2.23) gave the same frequency and the same signature.
- **Option changes that had no effect:** `--async-depth 1`, `VASurfaceAttribUsageHint` variants, and setting `rt_format` explicitly for P010 surfaces in the VA allocator.
- `--disable-va` segfaults in this configuration, so we could not test it.

Workarounds that avoid the corruption (for reference):
- `--avsw` (SW decode): 0/60.
- Running encodes one at a time: 0 %.
- 8-bit output, or no B-frames.

Original observation (before the investigation above): one difference we noticed is how surfaces are allocated. In `AllocFrames()` (`qsv_pipeline.cpp`), QSVEncC allocates one surface pool for each pair of adjacent tasks, and the pool's memtype combines the flags of both ends: `FROM_DECODE|FROM_VPPIN` for decode→VPP, `FROM_VPPOUT|FROM_ENCODE` for VPP→encode, and also the next task when one is bypassed. ffmpeg allocates a separate `AVHWFramesContext` per component. We do not know if this difference matters. We mention it only because the defect needs both `--avhw` and the VPP P010 conversion.

### Environment

- GPU: Intel Arc A380 (DG2, PCI 8086:56a5), kernel driver i915
- OS: Ubuntu 24.04 container on Fedora 43 host, kernel 6.19.14-200.fc43.x86_64
- iHD (intel-media-va-driver-non-free) 26.2.2, libmfx-gen 26.2.2, libvpl 2.16.0, libva 2.23.0
- QSVEncC 8.22 (r4385, Ubuntu package) and 8.31 (r4604, built from source, gcc 13.3)

### Additional notes

We have a scripted harness: it checks GPU exclusivity, builds a bit-exact reference, runs the paired ffmpeg control and computes Wilson confidence intervals. We can run additional experiments or debug builds if that helps. Open questions we have not answered: the below-API cause of the timing window, behaviour on other GPUs/driver stacks and with 2-way/4-way concurrency, and whether the wait should be unconditional or applied only when a VPP stage feeds the encoder.

*(Draft. The patch was published as draft PR rigaya/QSVEnc#316 on 2026-10-01; this issue text itself is not yet published.)*
