# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements. See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License. You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Generate the narration with Kokoro-82M (Apache-2.0) on CPU.

Usage: python tts.py narration.json OUT_DIR

Writes one WAV per scene (24 kHz mono) and timings.json with the duration
of every scene and the start and end time of every spoken word, taken from
the model's own token timestamps.
"""

import json
import os
import sys
import time

import numpy as np
import soundfile as sf
from kokoro import KPipeline

RATE = 24000


def main():
    spec = json.load(open(sys.argv[1]))
    out = sys.argv[2]
    os.makedirs(out, exist_ok=True)
    t0 = time.time()
    pipe = KPipeline(lang_code="a", repo_id="hexgrad/Kokoro-82M")
    load_s = time.time() - t0
    result = {"voice": spec["voice"], "speed": spec["speed"], "rate": RATE,
              "load_seconds": round(load_s, 2), "scenes": []}
    synth_s = 0.0
    for scene in spec["scenes"]:
        t1 = time.time()
        pieces, words, offset = [], [], 0.0
        for r in pipe(scene["spoken"], voice=spec["voice"], speed=spec["speed"]):
            audio = r.audio.numpy() if hasattr(r.audio, "numpy") else np.asarray(r.audio)
            for tok in r.tokens or []:
                if tok.start_ts is None or tok.end_ts is None:
                    continue
                words.append({"w": tok.text, "start": round(offset + tok.start_ts, 3),
                              "end": round(offset + tok.end_ts, 3),
                              "punct": tok.text in ".,:;!?"})
            pieces.append(audio)
            offset += len(audio) / RATE
        audio = np.concatenate(pieces)
        synth_s += time.time() - t1
        sf.write(os.path.join(out, scene["id"] + ".wav"), audio, RATE)
        peak = float(np.max(np.abs(audio)))
        result["scenes"].append({"id": scene["id"], "duration": round(len(audio) / RATE, 3),
                                 "peak": round(peak, 3), "words": words})
        print(f"{scene['id']}: {len(audio) / RATE:.2f}s audio, peak {peak:.2f}, "
              f"{len(words)} tokens", flush=True)
    total = sum(s["duration"] for s in result["scenes"])
    result["synth_seconds"] = round(synth_s, 2)
    result["audio_seconds"] = round(total, 2)
    print(f"model load {load_s:.1f}s, synth {synth_s:.1f}s for {total:.1f}s audio "
          f"(real-time factor {synth_s / total:.2f})", flush=True)
    json.dump(result, open(os.path.join(out, "timings.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
