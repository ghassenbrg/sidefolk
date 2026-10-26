#!/bin/zsh
# Films of the live companion from Core Animation's own frames (no screen capture), as MP4 and GIF.
# Usage: scripts/lively-poc/films.sh
set -u
cd "${0:A:h}/../.."
R=.build/release/sidefolk-render
out=build/lively-poc/films
mkdir -p $out

film() { # name seconds then live args
  local name=$1 secs=$2; shift 2
  $R --live "$@" --film $out/$name > $out/$name.log 2>&1
  ffmpeg -loglevel error -y -i $out/$name/film.mp4 \
    -vf "fps=20,scale=240:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=96[p];[b][p]paletteuse=dither=bayer" $out/$name.gif
  mv $out/$name/film.mp4 $out/$name.mp4
  rm -rf $out/$name
  echo "$name: $(ls -lh $out/$name.mp4 | awk '{print $5}') mp4, $(ls -lh $out/$name.gif | awk '{print $5}') gif"
}

film demo-mochi 47 demo 47 mochi --liveliness balanced
film demo-miso 47 demo 47 companions/miso --liveliness balanced
film demo-robot 47 demo 47 sidefolk --liveliness balanced
film demo-guard 47 demo 47 guard --liveliness balanced
# The scheduler choosing on its own, 10x faster: sits, lies down, moments in between.
film scheduler-mochi-lively-pace10 60 idle 60 mochi --liveliness lively --pace 10
film scheduler-mochi-balanced-pace10 60 idle 60 mochi --liveliness balanced --pace 10
# Reduce Motion: moments show only their faces.
film demo-mochi-reduced-motion 47 demo 47 mochi --liveliness balanced --reduced-motion
