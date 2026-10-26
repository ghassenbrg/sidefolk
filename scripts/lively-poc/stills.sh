#!/bin/zsh
# Recordings to MP4, then every companion's moments (strips and GIFs), Miso's included.
set -u
cd "${0:A:h}/../.."
for f in build/lively-poc/recordings/*.mov(N); do
  ffmpeg -loglevel error -y -i $f -c:v libx264 -pix_fmt yuv420p -crf 20 ${f:r}.mp4 && rm $f
done
R=.build/release/sidefolk-render
$R --antics build/lively-poc/antics | tail -1
$R --antics build/lively-poc/antics --only companions/miso | tail -1
$R build/lively-poc/custom --only companions/miso | tail -1
$R build/lively-poc/custom --only companions/template | tail -1
.build/release/sidefolk-3d --snap build/lively-poc/3d/mochi-3d.png
ls build/lively-poc/recordings build/lively-poc/antics | head -40
