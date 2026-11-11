#!/usr/bin/env bash
# Converts the unit voices in art_source/sounds/ ("Category_-_name.wav") into
# assets/sounds/<category>_<name>.ogg: mono, silence trimmed, loudness evened
# out, Ogg Vorbis. Run: tools/prep_sounds.sh   (needs ffmpeg)
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p assets/sounds
for f in art_source/sounds/*.wav; do
	base=$(basename "$f" .wav)
	category=$(echo "${base%%_-_*}" | tr '[:upper:]' '[:lower:]')
	name=$(echo "${base#*_-_}" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' '_')
	out="assets/sounds/${category}_${name}.ogg"
	ffmpeg -loglevel error -y -i "$f" -ac 1 -ar 44100 \
		-af "silenceremove=start_periods=1:start_threshold=-45dB,areverse,silenceremove=start_periods=1:start_threshold=-45dB,areverse,loudnorm=I=-16:TP=-1.5:LRA=11" \
		-c:a libvorbis -q:a 4 "$out"
	echo "$out"
done
