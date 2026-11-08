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

"""Turn the TTS timings into the video timeline.

Usage: python3 build.py narration.json timings.json index.html [voice_starts.txt]

Scene start times come from the real length of each scene's audio, so the
voice, the captions and the animation share one clock. Every caption word
gets the start and end time of the spoken words it stands for. The result
is written into index.html between the TIMELINE markers. With a fourth
argument, it also writes the start time of each scene WAV for mix.sh.
"""

import json
import re
import sys

LEAD = 0.3      # silence before the first word
OUTRO = 1.6     # end card after the last scene

# Caption spellings whose spoken form is a different word.
ALIASES = {"16bit": "sixteenbit"}


def norm(word):
    return re.sub(r"[^a-z0-9]", "", word.lower())


def align(caption, spoken):
    """Map each caption word to a run of spoken word tokens."""
    words, i = [], 0
    for cw in caption.split():
        target = ALIASES.get(norm(cw), norm(cw))
        start, acc = i, ""
        while i < len(spoken) and len(acc) < len(target):
            acc += norm(spoken[i]["w"])
            i += 1
        if acc != target:
            sys.exit(f"cannot align caption word {cw!r}: spoken gives {acc!r}")
        words.append({"t": cw, "start": spoken[start]["start"], "end": spoken[i - 1]["end"]})
    if i != len(spoken):
        sys.exit(f"spoken words left over: {[w['w'] for w in spoken[i:]]}")
    return words


def sentences(words):
    """Split caption words into sentences for the caption lines."""
    out, cur = [], []
    for w in words:
        cur.append(w)
        if w["t"][-1] in ".?!":
            out.append(cur)
            cur = []
    if cur:
        out.append(cur)
    return out


def main():
    spec = json.load(open(sys.argv[1]))
    tim = {s["id"]: s for s in json.load(open(sys.argv[2]))["scenes"]}
    gap = spec["gap_seconds"]
    t, scenes, starts = LEAD, [], []
    for n, sc in enumerate(spec["scenes"]):
        tm = tim[sc["id"]]
        spoken = [w for w in tm["words"] if norm(w["w"])]
        words = align(sc["caption"], spoken)
        for w in words:
            w["start"] = round(t + w["start"], 3)
            w["end"] = round(t + w["end"], 3)
        last = n == len(spec["scenes"]) - 1
        end = t + tm["duration"] + (0 if last else gap)
        scenes.append({"id": sc["id"], "title": sc["title"], "start": round(t, 3),
                       "voiceEnd": round(t + tm["duration"], 3), "end": round(end, 3),
                       "lines": sentences(words)})
        starts.append(f"{sc['id']}.wav {t:.3f}")
        t = end
    total = round(t + OUTRO, 3)
    timeline = {"total": total, "outro": OUTRO, "scenes": scenes}

    page = open(sys.argv[3]).read()
    block = "/*TIMELINE*/" + json.dumps(timeline, separators=(",", ":")) + "/*END*/"
    page, n = re.subn(r"/\*TIMELINE\*/.*?/\*END\*/", lambda m: block, page, flags=re.S)
    if n != 1:
        sys.exit("TIMELINE marker not found exactly once in the page")
    open(sys.argv[3], "w").write(page)
    if len(sys.argv) > 4:
        open(sys.argv[4], "w").write("\n".join(starts) + "\n")
    for s in scenes:
        print(f"{s['id']:<11} {s['start']:6.2f} -> {s['end']:6.2f}")
    print(f"total {total:.2f}s")


if __name__ == "__main__":
    main()
