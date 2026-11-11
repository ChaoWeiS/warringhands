#!/usr/bin/env bash
# Makes the game's music (assets/music/*.ogg) from art_source/music/*.mp3:
# brightens the top end (the sources are dull above ~6 kHz), adds a little
# harmonic sparkle, evens out loudness and keeps peaks safe; then Ogg Vorbis
# at high quality. Run: tools/prep_music.sh   (needs ffmpeg)
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p assets/music
enhance() {  # source, output, treble boost (dB), sparkle amount
	ffmpeg -loglevel error -y -i "$1" -map 0:a -ar 48000 -ac 2 -af "\
equalizer=f=3500:t=q:w=1.0:g=1.5,\
highshelf=f=6500:g=$3:t=q:w=0.6,\
aexciter=level_in=1:level_out=1:amount=$4:drive=4:blend=0:freq=6500:ceil=16000,\
loudnorm=I=-16:TP=-1.5:LRA=11" \
		-c:a libvorbis -q:a 6 "$2"
	echo "$2"
}
enhance art_source/music/Majestic_Crescendo.mp3 assets/music/majestic_crescendo.ogg 6 1.2
enhance art_source/music/Antes_de_la_Batalla.mp3 assets/music/antes_de_la_batalla.ogg 2 0.4
