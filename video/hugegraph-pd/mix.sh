#!/usr/bin/env bash
#
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
#
# Build the soundtrack: narration on the timeline from build.py, a quiet
# synthesized pad (plain sine chords made by ffmpeg, so no third-party audio),
# the pad ducked under the voice, then loudness normalized to -16 LUFS.
#
#   ./mix.sh AUDIO_DIR DURATION_SECONDS OUT.wav
#
# AUDIO_DIR holds the scene WAVs and voice_starts.txt from build.py
# ("<file> <start seconds>" per line). Each WAV is placed at its exact sample.

set -euo pipefail
dir=$1 dur=$2 out=$3
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

inputs=() filters="" labels="" n=0
while read -r f start; do
    rate=$(ffprobe -v error -show_entries stream=sample_rate -of csv=p=0 "$dir/$f")
    inputs+=(-i "$dir/$f")
    filters+="[$n:a]adelay=delays=$(python3 -c "print(round($start*$rate))")S:all=1[d$n];"
    labels+="[d$n]"
    n=$((n + 1))
done < "$dir/voice_starts.txt"
ffmpeg -loglevel error -y "${inputs[@]}" -filter_complex \
    "${filters}${labels}amix=inputs=$n:normalize=0,apad,aresample=48000[v]" \
    -map "[v]" -t "$dur" -ac 2 "$tmp/voice.wav"

# Am - F - C - G, one chord every 7.5 s with raised-cosine crossfades.
chord() {  # $1 = index, rest = frequencies
    local i=$1; shift
    local sum="" f
    for f in "$@"; do
        sum+="${sum:+ + }sin(2*PI*$f*t) + 0.6*sin(2*PI*$f*1.004*t)"
    done
    echo "pow(0.5+0.5*cos(2*PI*(t/7.5-$i-0.4)/4),4)*($sum)"
}
expr="0.018*( $(chord 0 110 164.81 220 261.63 329.63) + $(chord 1 87.31 130.81 174.61 220 261.63) \
+ $(chord 2 130.81 196 261.63 329.63 392) + $(chord 3 98 146.83 196 246.94 293.66) )"
ffmpeg -loglevel error -y -f lavfi -i "aevalsrc=exprs='$expr':s=48000:d=$dur" \
    -af "lowpass=f=1400,aecho=0.8:0.6:140|260:0.35|0.25,tremolo=f=0.25:d=0.25,\
afade=t=in:d=2.5,afade=t=out:st=$(echo "$dur - 3" | bc):d=3" -ac 2 "$tmp/pad.wav"

# Duck the pad under the voice and mix.
ffmpeg -loglevel error -y -i "$tmp/pad.wav" -i "$tmp/voice.wav" -filter_complex \
    "[0:a]volume=0.55[pad];[1:a]asplit=2[v1][v2];\
[pad][v1]sidechaincompress=threshold=0.015:ratio=6:attack=30:release=500[duck];\
[duck][v2]amix=inputs=2:duration=first:normalize=0[mix]" \
    -map "[mix]" "$tmp/mix.wav"

# Two-pass loudness normalization to -16 LUFS, true peak -1.5 dBTP.
m=$(ffmpeg -hide_banner -i "$tmp/mix.wav" -af loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json -f null - 2>&1 \
    | sed -n '/^{/,/^}/p')
get() { echo "$m" | python3 -c "import json,sys; print(json.load(sys.stdin)['$1'])"; }
ffmpeg -loglevel error -y -i "$tmp/mix.wav" -af "loudnorm=I=-16:TP=-1.5:LRA=11:\
measured_I=$(get input_i):measured_TP=$(get input_tp):measured_LRA=$(get input_lra):\
measured_thresh=$(get input_thresh):offset=$(get target_offset):linear=true,aresample=48000" \
    -c:a pcm_s16le "$out"
echo "mixed $out"
