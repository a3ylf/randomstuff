#!/usr/bin/env bash
# convert_for_tv.sh
#
# Purpose:
# Convert these MKV episode files into TV-friendly MP4 files.
#
# Intended use:
# This script is for anime-style releases that often fail on TVs because they use
# combinations like 10-bit H.264 video, FLAC audio, and ASS subtitles. It re-encodes
# them to more compatible settings:
# - H.264 High, 8-bit, yuv420p video
# - AAC stereo audio
# - Burned-in subtitles for maximum playback compatibility
#
# Output:
# Converted files are written to ./tv_ready using the same base filename with .mp4.
#
# How to run:
# - Convert every .mkv in this folder:
#     ./convert_for_tv.sh
# - Convert specific files only:
#     ./convert_for_tv.sh "Episode 01.mkv" "Episode 02.mkv"
# - Show this help text:
#     ./convert_for_tv.sh --help
#
# Notes:
# - The script skips files that already exist in ./tv_ready.
# - It expects the local ffmpeg environment at ./.venv-ffmpeg.
# - Optional extra ffmpeg args can be passed through FFMPEG_ARGS_EXTRA.
#   Example:
#     FFMPEG_ARGS_EXTRA='-t 30' ./convert_for_tv.sh "Episode 01.mkv"

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"

usage() {
  awk '
    NR == 1 { next }
    /^set -euo pipefail$/ { exit }
    { sub(/^# ?/, ""); print }
  ' "$0"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

ffmpeg_py="$script_dir/.venv-ffmpeg/bin/python"
if [[ ! -x "$ffmpeg_py" ]]; then
  echo "Missing local ffmpeg environment at .venv-ffmpeg" >&2
  exit 1
fi

ffmpeg_bin="$("$ffmpeg_py" -c 'import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())')"
out_dir="$script_dir/tv_ready"
mkdir -p "$out_dir"

# Build a subtitle filter that can safely reference paths with spaces and quotes.
build_subtitle_filter() {
  "$ffmpeg_py" - "$1" <<'PY'
import os
import sys

path = os.path.abspath(sys.argv[1])
escaped = path.replace("\\", "\\\\").replace("'", r"\'")
print(f"subtitles=filename='{escaped}':si=0,format=yuv420p")
PY
}

# Convert one MKV into a TV-friendly MP4 in ./tv_ready.
convert_one() {
  local input="$1"
  local base output subtitle_filter

  base="$(basename "${input%.*}")"
  output="$out_dir/$base.mp4"

  if [[ -f "$output" ]]; then
    echo "Skipping existing output: $output"
    return
  fi

  subtitle_filter="$(build_subtitle_filter "$input")"

  echo "Converting: $input"
  "$ffmpeg_bin" -y -hide_banner -i "$input" \
    -map 0:v:0 -map 0:a:0 \
    -vf "$subtitle_filter" \
    -c:v libx264 -preset veryfast -crf 20 -profile:v high -level 4.1 -pix_fmt yuv420p \
    -c:a aac -b:a 192k \
    -movflags +faststart \
    ${FFMPEG_ARGS_EXTRA:-} \
    "$output"
}

if [[ $# -gt 0 ]]; then
  for input in "$@"; do
    convert_one "$input"
  done
  exit 0
fi

shopt -s nullglob
inputs=( *.mkv )
if [[ ${#inputs[@]} -eq 0 ]]; then
  echo "No MKV files found in $script_dir" >&2
  exit 1
fi

for input in "${inputs[@]}"; do
  convert_one "$input"
done
