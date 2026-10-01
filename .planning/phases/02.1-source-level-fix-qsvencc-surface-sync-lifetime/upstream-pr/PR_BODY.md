> **Draft, for discussion.** This is a small application-level workaround for a silent frame corruption that I could reduce to a timing window. I would like to know how you prefer it handled (see "Open questions") before it is considered for merging.

Refs #308.

## Summary

When several QSVEncC sessions share one GPU, one frame of an encode can come out wrong: the last mini-GOP anchor before a forced IDR is encoded from a stale input surface (an earlier frame of the *same* session). There is no error or warning; the bitstream is valid and the encoder reports success.

The patch adds a `frame->waitsync()` in `PipelineTaskMFXEncode::sendFrame()`, before `EncodeFrameAsync()`. This serializes the VPP -> encoder hand-off, as the ffmpeg QSV path does. The change is 5 lines in `QSVPipeline/qsv_pipeline_ctrl.h`; the flush call (no frame) is unaffected.

## Symptom and trigger conditions

- Silent, single frame: in a 300-frame chunk with a forced IDR at frame 300, the frame at the last B-pyramid anchor (output frames 295..299) is the content of an earlier frame of the same session (best match PSNR 47-57 dB to frames 289..294; 30 of 30 inspected corrupt outputs).
- AV1 (`-c av1`), 10-bit output, `--avhw` with VA video memory, a P010 VPP stage (`nv12 -> p010` conversion), `--gop-len 300 --gop-ref-dist 6 --b-pyramid`.
- Needs two or more concurrent QSVEncC sessions on the same GPU (I used 3). A single session is bit-exact across runs.
- Arc A380, Linux. The ffmpeg `av1_qsv` encoder with the same concurrency and the same media stack does not show it (0 of 60 and 0 of 20 control iterations).

## Reproduction outline

Three chunks of an H.264 1080p source (decoded with `--avhw`, `--seek`/`--trim`) are encoded concurrently, 20 to 60 iterations:

```
qsvencc --avhw --va -i <source> -c av1 --icq 24 --qp-max 100 --output-depth 10 --profile main \
  --gop-len 300 --gop-ref-dist 6 --b-pyramid --tile-col 1 --tile-row 1 \
  --tune perceptual --scenario-info archive \
  --colorrange auto --colormatrix auto --colorprim auto --transfer auto --chromaloc auto \
  --seek <chunk start> --trim 0:<frames> -o <out>.obu
```

Each output is compared with the single-session output of the same chunk (whole-file md5, plus PSNR of the frame at the end of the chunk; PSNR < 30 dB counts as corrupt, the corrupt frame scores about 12.8 dB). Single-session outputs are bit-exact between runs. I can share the scripted harness (bash + ffmpeg, OpenCL-free) and exact chunk positions on request.

## Root-cause analysis

What I measured (8.31 tag, same configuration):

- The corrupt frame is a stale input of the session itself (not another session's data).
- It behaves like a timing window. The corruption disappears with: waiting for the VPP syncpoint before `EncodeFrameAsync` (this patch), waiting after decode, an untargeted CPU sleep before `EncodeFrameAsync` with no sync at all (0.85 ms, the mean real wait, and 4 ms), `--max-procfps 60`, and `LIBVA_TRACE`.
- It is not affected by a larger surface pool (+16) or by round-robin surface reuse. The surface pools are not exhausted.

Honest conclusion: the fact that an untargeted delay also hides it means I cannot show that the encoder reads a surface the VPP has not finished writing, and I cannot show that the application is missing an API-level dependency. The ordering problem probably lies below the API (driver / runtime / kernel cross-context fencing), which I could not observe directly. The patch is therefore a workaround that closes the window by serializing the VPP -> encoder hand-off like ffmpeg's QSV path, which is immune in my tests.

## Results

Counts are corrupt frames at the end of the chunk, per hot chunk (923 and 1129; chunk 928 is a confirmatory chunk and was never corrupt). md5 compares every output with its isolated single-session reference.

| build | iterations | corrupt 923 | corrupt 1129 | md5 vs reference | single-session bit-exact vs stock |
|---|---|---|---|---|---|
| 8.31 stock (baseline) | 20 | 7/20 | 6/20 | - | - |
| 8.31 + patch | 60 | 0/60 | 0/60 | 180/180 identical | 6/6 |
| upstream master 15cd6879 stock | 1 (stopped at first corrupt frame) | 1/1 | 0/1 | 923 differs, others identical | reference identical to 8.31 |
| upstream master 15cd6879 + patch | 20 | 0/20 | 0/20 | 60/60 identical | 6/6 (and identical to the 8.31 reference md5s) |

Residual rate with the patch on 8.31: <= 5 % per iteration (rule of three, 0/60; exact one-sided 95 % bound 4.87 %). This is a statistical bound, not proof that the defect is gone. The upstream-master result is a 20-iteration screen only. Stock upstream master reproduces the bug (corrupt frame at 12.82 dB in the first iteration).

Single-session outputs of upstream master (stock and with the patch) are identical to the 8.31 outputs for all three chunks, and deterministic.

## Performance cost

Mean encoded fps; "stock" 3-way numbers are the 8.31 baseline, since upstream-master stock was stopped at its first corrupt iteration (its single iteration: 226.1 / 130.6 / 229.4).

3 concurrent sessions (chunks 923 / 928 / 1129):

| build | 923 | 928 | 1129 |
|---|---|---|---|
| 8.31 stock | 226.6 | 131.2 | 230.1 |
| 8.31 + patch (60 iterations) | 227.0 | 129.9 | 229.0 |
| upstream master + patch (20 iterations) | 227.1 | 130.3 | 229.2 |

Single session, no contention (6 encodes per scene and build on upstream master, alternating builds; 2 encodes per scene on 8.31):

| build | 923 | 928 | 1129 |
|---|---|---|---|
| upstream master stock | 313.2 | 229.0 | 313.2 |
| upstream master + patch | 312.9 | 222.5 | 311.9 |
| delta | -0.1 % | -2.9 % | -0.4 % |
| 8.31 stock / + patch | 315.1 / 316.5 | 227.1 / 226.0 | 315.2 / 311.3 |

The cost is small in these measurements (0 to about -3 %). An earlier single-session measurement of the patched 8.31 build that showed -9 to -19 % was not reproduced when stock and patched builds were run back to back, and is superseded by the table above. I have only measured this one configuration (Arc A380, these three chunks), so the cost on other content, other GPUs, or sessions where VPP runs much longer than the encode is unknown. That is the reason this is a draft.

## Open questions

1. Would you prefer this unconditional, conditional (for example only for VA/D3D video memory with an MFX VPP stage between decode and encode), or behind an option?
2. Is waiting on the VPP output syncpoint in `sendFrame()` the right place, or would you prefer the wait on the producing side (end of the VPP task)?
3. Has this been seen on other GPUs, drivers or operating systems? I could only test one Arc A380 (below). I have not tried 2-way or 4-way concurrency, or other codecs.
4. If you have a better idea of where the ordering is lost (driver, runtime, or a missing dependency in the way the surface is passed between two sessions' contexts), I am happy to run diagnostic builds.

## Testing environment

- GPU: Intel Arc A380, Linux kernel 6.19.14 (Fedora 43), `i915`
- Media stack: iHD driver 26.2.2, libvpl 2.16, libmfx-gen 26.2.2
- Tested builds: tag 8.31 (r4604) and upstream master 15cd6879 (`QSVEncC 8.31 (r4627)`), Meson release builds
- The patch applies to both without conflicts.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
