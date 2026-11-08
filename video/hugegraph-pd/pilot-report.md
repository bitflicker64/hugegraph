# Pilot report: intro video for hugegraph-pd

One module done end to end to learn what each step costs before doing about 20 more. The result
is a 59.8 s, 1920x1080 video with narration, captions, line-art animation and a quiet pad. It
plays at the top of `hugegraph-pd/README.md` on the
[fork branch](https://github.com/bitflicker64/hugegraph/blob/video/hugegraph-pd/hugegraph-pd/README.md).

Date: 2026-11-08. Draft PR: bitflicker64/hugegraph#28, base `video/base-pd`. That base is a
temporary branch at the apache/master commit this branch starts from (0abd931). It exists only
so the PR shows this branch's own commits, because the fork's master is 237 commits behind
apache/master. Delete both `video/base-pd` and `video/hugegraph-pd` after the pilot.

## Wall time per step

One session did all the thinking. The clock runs from 12:22 to 12:54, so the whole pilot took
about 32 minutes.

| Step | Wall time | Notes |
|---|---|---|
| 1. Read README, AGENTS.md, docs and code; check every claim | about 6 min | Re-checked against apache/master later because PD's AGENTS.md had been rewritten there |
| 2. Script and narration text | about 3 min | `narration.json` holds a spoken and a caption version of each scene |
| 3. TTS install on Pune101 | 21 s | uv, Python 3.12, CPU torch, kokoro 0.9.4 |
| 3. TTS runs on Pune101 (3 runs to fit 60 s) | about 3 min | One run: 25 s wall, of which 2 s model load and 18 s synthesis for 55.9 s of audio (0.32x real time) |
| 4. Animation page, three still-frame review passes, mix | about 10 min | Most of the session's effort went here |
| 5. Playwright setup and renders on three machines | about 12 min | Includes a failed first render (see below) |
| 6. Check frames, sync, loudness | about 2 min | |
| 7. Branch, PR, upload, README, playback check | about 5 min | Upload of the 6.9 MB MP4: 3 s |

Tokens: this session's context reached about 270k tokens at the end (messages about 186k). The
app shows no dollar cost. The weekly plan meter stayed at 6%.

## Sound

- Model: [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M), Apache-2.0 for both the
  weights and the `kokoro` code. Its G2P library `misaki` is Apache-2.0 too. Voice `af_heart`,
  speed 1.12. Runs on CPU, no GPU needed.
- Pulled in at install: torch (BSD-style), spaCy and `en_core_web_sm` (MIT), and
  `espeakng-loader`, which bundles espeak-ng (GPL-3.0) as a fallback for unknown words. All of
  these are build tools only. Nothing from them is committed, and the generated audio is not a
  copy of them.
- Timing check: the model returns a start and an end time for every word. No word was shorter
  than 60 ms, and there were no gaps inside sentences. Peaks per scene were 0.42 to 0.62, so
  nothing clipped.
- Music: a pad of four sine chords (Am, F, C, G) synthesized by ffmpeg in `mix.sh`, so there is no
  third-party audio. It is ducked under the voice with a sidechain compressor and sits about 15 dB
  under the voice in the pauses.
- Final mix: -16.0 LUFS integrated, true peak -1.5 dBTP before AAC and -1.3 dBFS after.

## Render per machine

Same `index.html` and `mix.wav` on every machine (md5 checked). Frames are JPEG q95 piped to
x264 (slow, CRF 22) in parallel slices, then joined without re-encoding.

| Machine | CPU | Setup | Render | Size | Problems |
|---|---|---|---|---|---|
| Pune101 | i7-7700, 8 threads, 4 workers | 43 s (Playwright and Chromium, 937 MB) | 69.0 s | 7.41 MB | SSH dropped during the first, slower run |
| library | 12 threads, 6 workers | 10 s (headless shell only, 341 MB) | 57.0 s | 6.90 MB | Disk is 96% full (12 GB free) |
| Mac | Apple M4, 10 cores, 6 workers | 13 s | 30.9 s | 7.45 MB | None |

The three outputs look the same. Between machines the PSNR is about 35.8 dB, which comes from
different x264 builds, not from the picture. The uploaded file is the library render, the
smallest of the three.

## Which machine for what

- TTS: Pune101. It has the venv and the model, plenty of disk, and the job takes 25 s.
- Render: the Mac when it is free (twice as fast). Otherwise library, then Pune101. All three give
  the same picture, so the choice is only about speed.
- Still-frame review while building the page: the Mac, locally, a few seconds per batch.
- Uploads and pushes: the Mac (gh logged in as bitflicker64).
- Compute is not the bottleneck. Writing the page is.

## What broke and the fix

1. **The first render ran at 2.6 frames per second.** Chromium's PNG screenshot at 1080p was the
   cost. JPEG q95 frames are five times faster (60 frames: 24.2 s as PNG, 4.7 s as JPEG). Frames
   are pure functions of time, so `render.cjs` also splits them across workers, each with its
   own browser and encoder.
2. **The SSH session dropped during that render.** The process survived with a dead stdout. Long
   remote runs now start with `nohup ... > log` inside `flock`, and the session reads the log.
3. **The voice drifted late, about 8 s by the end.** The ffmpeg concat `duration` directive does
   not trim a file, so each 2 s silence file played in full. `outpoint` still drifted about 30 ms
   per gap because WAV packets are cut at packet boundaries. Now each scene WAV is placed at its
   exact sample with `adelay`.
4. **The first narration was 61.8 s.** I cut seven words and raised the speed to 1.12, which gave
   55.9 s of voice and 59.8 s in total.
5. **Captions did not wrap, and small labels were too small** for GitHub's player, which is about
   920 px wide. The caption words now have normal spaces between them, and text under 26 px is
   scaled up 1.2x.
6. **PD's AGENTS.md was rewritten on apache/master**, so the sources in `script.md` now cite the
   current files. The facts themselves did not change.
7. **`pkill -f` killed its own SSH shell** because the pattern matched the command line. Kill by
   PID instead.
8. **The fork's master is 237 commits behind**, so the PR uses a temporary base branch (see top).
9. The final MP4 has 1793 of 1795 frames because `-shortest` trims to the audio. The two missing
   frames are the last 66 ms of the end card. Harmless.

## Still unknown

Whether the video plays when the same README is shown on apache/hugegraph. The asset link answers
a request with no GitHub login (302 to S3), and GitHub renders `user-attachments` links in any
repository's Markdown, so it should play there too. That was not tested, because this pilot does
not touch apache/hugegraph.

## Reviewer checklist for each video

- **Facts:** every caption sentence has a row in the sources table of `script.md`, and that row
  still matches apache/master. No counts, defaults or features that are not in the code or docs.
  Example values on screen (here: four partitions, key "marko") are marked as examples.
- **Sync:** captions light up with the voice. Spot-check the first word of each scene against the
  speech onset in the MP4 (`silencedetect`); here the difference was under 0.1 s.
- **Audio:** -16 LUFS, true peak at or under -1 dBTP, no clipped words, music audible only in the
  pauses, no non-commercial models or tracks.
- **Readability:** look at six evenly spaced frames scaled to 900 px wide. No text cut off or
  overlapping, and captions fit in two lines.
- **Size and format:** H.264 High, yuv420p, AAC, under 10 MB, duration 45 to 60 s.
- **README:** the bare `https://github.com/user-attachments/assets/...` link is on its own line
  and plays with sound on the branch page.

## Estimate for about 20 modules with three machines

Per module, once the shared parts are pulled out (see below):

| Work | Time | Where |
|---|---|---|
| Read the module and check facts | 5 to 8 min | Session |
| Script and narration | 3 to 5 min | Session |
| TTS, one or two runs | 1 min | Pune101 |
| Scenes for the page and two still-frame review passes | 10 to 15 min | Session, Mac |
| Mix and render | 1 to 2 min | Mac or library |
| Final check, upload, README, PR | 5 min | Session, Mac |

That is about 25 to 35 minutes per module, almost all of it session time. For 20 modules that
comes to about 8 to 12 hours if one session does them in a row. The machines are busy for under
40 minutes in total: about 10 min of TTS and 20 to 25 min of rendering. Three machines do not
shorten the run much. Running three or four module sessions at once does: about 3 to 4 hours of
wall time, with TTS kept on Pune101 under the lock and renders spread over the Mac and library.
Token use should be about 250k to 300k context tokens per module session, judging by this pilot.

Before the full run:

- Move `tts.py`, `build.py`, `mix.sh` and `render.cjs` to a shared `video/tools/`. They have
  nothing PD-specific.
- Split the page into a shared runtime (helpers, captions, HUD, scene switching, end card) and a
  per-module scenes file, so each module writes only its scenes.
- Decide whether videos go into apache/hugegraph READMEs as fork uploads, or are uploaded from a
  PR on apache/hugegraph itself.

## What is kept on the hosts

Kept for the full run, everything else removed (scratch dirs, audio, recordings, the uv and pip
caches, npm logs):

| Host | Path | Size | What |
|---|---|---|---|
| Pune101 | `~/tools/video/tts-venv`, `python`, `bin` | 1.5 GB | Python 3.12 venv with CPU torch and kokoro, uv |
| Pune101 | `~/tools/video/hf` | 313 MB | Kokoro-82M weights and voices |
| Pune101 | `~/tools/video/pw`, `pw-browsers` | 937 MB | Playwright 1.56.1, Chromium and headless shell |
| library | `~/tools/video/pw`, `pw-browsers` | 341 MB | Playwright 1.56.1, headless shell only |

Removing `~/tools/video` on both hosts undoes all of it. On the Mac, Playwright's headless shell
was added to `~/Library/Caches/ms-playwright/chromium_headless_shell-1194`.
