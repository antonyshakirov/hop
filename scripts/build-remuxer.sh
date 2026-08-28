#!/bin/bash
# Builds the repacking helper Hop downloads for mkv/webm files.
#
# It is ffmpeg, configured down to the one job it does here: read Matroska,
# write MP4, copy the tracks across. No encoders, no filters beyond the two the
# CLI insists on, no network, and — importantly — NO GPL parts: the build is
# plain LGPL, which is what lets us host the binary next to a closed-source app.
# Anyone can rebuild exactly what we ship by running this script.
#
# Usage: scripts/build-remuxer.sh [work-dir]
# Output: <work-dir>/hop-remuxer/ffmpeg  (universal: arm64 + x86_64)
#
# Then: swift scripts/sign-tool.swift <that binary> <download url>
# and put the binary, its .sig and the printed manifest on the site under
# /downloads/hop/remuxer/.
set -euo pipefail

VERSION="8.1"
TARBALL="ffmpeg-${VERSION}.tar.xz"
SOURCE_URL="https://ffmpeg.org/releases/${TARBALL}"

WORK="${1:-$(pwd)/.remuxer-build}"
mkdir -p "$WORK"
cd "$WORK"

if [ ! -f "$TARBALL" ]; then
  echo "downloading ${SOURCE_URL}"
  curl -L --retry 5 --retry-delay 5 -o "$TARBALL" "$SOURCE_URL"
fi

rm -rf "ffmpeg-${VERSION}"
tar xf "$TARBALL"

# Everything off, then back on: only what a repack actually touches. Note the
# absence of --enable-gpl and --enable-nonfree — their presence is what would
# make the result undistributable for us.
configure_common=(
  --disable-everything
  --disable-autodetect
  --disable-doc
  --disable-network
  --disable-debug
  --disable-avdevice
  --disable-postproc
  --disable-x86asm
  --disable-ffplay
  --disable-ffprobe
  --enable-small
  --enable-demuxer=matroska,mov,mpegts
  --enable-muxer=mp4,mov
  --enable-protocol=file
  --enable-parser=h264,hevc,aac,vp9,av1,opus,vorbis,mpegaudio,flac,ac3,vp8
  --enable-bsf=h264_mp4toannexb,hevc_mp4toannexb,extract_extradata,aac_adtstoasc,vp9_superframe,av1_metadata,vp9_metadata,dump_extradata
  --enable-filter=null,anull
)

build_arch() {
  local arch="$1"
  local dir="build-${arch}"
  rm -rf "$dir"
  cp -R "ffmpeg-${VERSION}" "$dir"
  cd "$dir"
  local cross=()
  if [ "$arch" != "$(uname -m)" ]; then
    cross=(--enable-cross-compile --target-os=darwin)
  fi
  ./configure "${configure_common[@]}" \
    --arch="$arch" \
    --cc="clang -arch ${arch}" \
    "${cross[@]}" > "../configure-${arch}.log" 2>&1
  make -j"$(sysctl -n hw.ncpu)" ffmpeg > "../make-${arch}.log" 2>&1
  cd ..
  echo "built ${arch}: $(du -h "${dir}/ffmpeg" | cut -f1)"
}

build_arch arm64
build_arch x86_64

# One binary for both machines, the same way Hop itself ships.
OUT="hop-remuxer"
mkdir -p "$OUT"
lipo -create -output "${OUT}/ffmpeg" build-arm64/ffmpeg build-x86_64/ffmpeg
strip -x "${OUT}/ffmpeg"

echo
echo "universal helper: ${WORK}/${OUT}/ffmpeg ($(du -h "${OUT}/ffmpeg" | cut -f1))"
lipo -archs "${OUT}/ffmpeg"
echo "sha256: $(shasum -a 256 "${OUT}/ffmpeg" | cut -d' ' -f1)"
echo
echo "next: swift scripts/sign-tool.swift ${WORK}/${OUT}/ffmpeg <download-url>"
