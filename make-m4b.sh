#!/usr/bin/env bash
#
# make_m4b.sh — turn an audiobook directory into a single self-contained .m4b
#
# Usage:
#   ./make_m4b.sh [DIR|ZIP] [-b BITRATE] [-o OUTPUT.m4b] [-f]
#
#   DIR|ZIP     Audiobook directory (default: current directory), or a .zip
#               archive of one. A zip is unpacked to a temporary directory,
#               used to build the .m4b, then removed; the original zip is
#               kept untouched.
#               All audio files found under it are joined, in natural
#               order (disc2 before disc10, track01 before track02).
#   -b BITRATE  AAC bitrate for the output (default: 64k, good for
#               spoken-word mono/stereo).
#   -o OUTPUT   Output file (default: <DIR-basename>.m4b next to DIR, or
#               <ZIP-basename>.m4b next to the zip).
#   -f          Overwrite the output file if it already exists.
#
# Each source audio file becomes one chapter, titled from its embedded
# "title" tag when present (otherwise a "Disc N - Track M"-style label
# derived from its path). Book-level metadata (title, author, genre,
# year) is taken from the first file's tags. Cover art (cover/folder.*)
# found anywhere under DIR is embedded if present.
#
# Requires: ffmpeg, ffprobe.

set -euo pipefail

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

command -v ffmpeg  >/dev/null 2>&1 || die "ffmpeg not found in PATH"
command -v ffprobe >/dev/null 2>&1 || die "ffprobe not found in PATH"

# ---- parse arguments --------------------------------------------------------
SRC=""
BITRATE="64k"
OUTPUT=""
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    -b) BITRATE="${2:?-b needs a value}"; shift 2 ;;
    -o) OUTPUT="${2:?-o needs a value}"; shift 2 ;;
    -f) FORCE=1; shift ;;
    -h|--help) sed -n '2,34p' "$0"; exit 0 ;;
    -*) die "unknown option: $1" ;;
    *)  if [ -z "$SRC" ]; then SRC="$1"; else die "unexpected argument: $1"; fi; shift ;;
  esac
done

SRC="${SRC:-.}"

# ---- temp working files -----------------------------------------------------
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---- resolve input: directory or .zip archive -------------------------------
# For a zip we unpack into $WORK (cleaned up on exit) and default the output
# next to the original zip, named after it.
if [ -f "$SRC" ] && printf '%s' "$SRC" | grep -qiE '\.zip$'; then
  command -v unzip >/dev/null 2>&1 || die "unzip not found in PATH (needed for .zip input)"
  ZIP="$(cd "$(dirname "$SRC")" && pwd)/$(basename "$SRC")"   # absolute
  BASENAME="$(basename "$SRC")"; BASENAME="${BASENAME%.[zZ][iI][pP]}"
  DIR="$WORK/unzipped"
  mkdir -p "$DIR"
  printf 'Unpacking %s ...\n' "$ZIP"
  unzip -q -o "$ZIP" -d "$DIR" || die "failed to unzip: $ZIP"
  OUTPUT="${OUTPUT:-$(dirname "$ZIP")/$BASENAME.m4b}"
elif [ -d "$SRC" ]; then
  DIR="$(cd "$SRC" && pwd)"                 # absolute path
  BASENAME="$(basename "$DIR")"
  OUTPUT="${OUTPUT:-$DIR/../$BASENAME.m4b}"
else
  die "not a directory or .zip file: $SRC"
fi

if [ -e "$OUTPUT" ] && [ "$FORCE" -ne 1 ]; then
  die "output exists: $OUTPUT (use -f to overwrite)"
fi

# ---- gather audio files in natural order ------------------------------------
mapfile -d '' FILES < <(
  find "$DIR" -type f \
    \( -iname '*.mp3'  -o -iname '*.m4a' -o -iname '*.m4b' -o -iname '*.aac' \
    -o -iname '*.flac' -o -iname '*.ogg' -o -iname '*.opus' -o -iname '*.wav' \) \
    -print0 | sort -z -V
)
[ "${#FILES[@]}" -gt 0 ] || die "no audio files found under: $DIR"
printf 'Found %d audio files.\n' "${#FILES[@]}"

# ---- optional cover art -----------------------------------------------------
COVER=""
for name in cover folder front albumart; do
  for ext in jpg jpeg png; do
    hit="$(find "$DIR" -maxdepth 3 -type f -iname "$name.$ext" -print -quit)"
    [ -n "$hit" ] && { COVER="$hit"; break 2; }
  done
done

# ---- temp working files -----------------------------------------------------
CONCAT="$WORK/concat.txt"
FFMETA="$WORK/meta.txt"

# escape a path for ffmpeg concat ('  ->  '\'') and wrap in single quotes
concat_escape() { printf "file '%s'\n" "${1//\'/\'\\\'\'}"; }

# ---- book-level metadata from the first file --------------------------------
first="${FILES[0]}"
get_tag() { ffprobe -v error -show_entries "format_tags=$1" -of default=nk=1:nw=1 "$2" 2>/dev/null | head -n1; }

ALBUM="$(get_tag album  "$first")"
ARTIST="$(get_tag artist "$first")"
GENRE="$(get_tag genre  "$first")"
DATE="$(get_tag date   "$first")"
[ -n "$ALBUM" ]  || ALBUM="$BASENAME"
[ -n "$GENRE" ]  || GENRE="Audiobook"

# ---- build concat list + chapter metadata -----------------------------------
: > "$CONCAT"
{
  printf ';FFMETADATA1\n'
  printf 'title=%s\n'  "$ALBUM"
  printf 'album=%s\n'  "$ALBUM"
  [ -n "$ARTIST" ] && { printf 'artist=%s\n' "$ARTIST"; printf 'album_artist=%s\n' "$ARTIST"; printf 'composer=%s\n' "$ARTIST"; }
  printf 'genre=%s\n'  "$GENRE"
  [ -n "$DATE" ] && printf 'date=%s\n' "$DATE"
  printf 'media_type=2\n'   # 2 = Audiobook (iTunes stik)
} > "$FFMETA"

start_ms=0
idx=0
for f in "${FILES[@]}"; do
  idx=$((idx + 1))
  concat_escape "$f" >> "$CONCAT"

  dur="$(ffprobe -v error -show_entries format=duration -of default=nk=1:nw=1 "$f" 2>/dev/null)"
  [ -n "$dur" ] || die "could not read duration of: $f"
  # duration -> integer milliseconds (rounded)
  dur_ms="$(awk -v d="$dur" 'BEGIN{printf "%d", (d*1000)+0.5}')"
  end_ms=$((start_ms + dur_ms))

  title="$(get_tag title "$f")"
  if [ -z "$title" ]; then
    rel="${f#"$DIR"/}"
    title="${rel%.*}"
  fi

  {
    printf '[CHAPTER]\n'
    printf 'TIMEBASE=1/1000\n'
    printf 'START=%d\n' "$start_ms"
    printf 'END=%d\n'   "$end_ms"
    printf 'title=%s\n' "$title"
  } >> "$FFMETA"

  start_ms=$end_ms
done

total_s="$(awk -v m="$start_ms" 'BEGIN{printf "%.0f", m/1000}')"
printf 'Total duration: %02d:%02d:%02d\n' $((total_s/3600)) $(((total_s%3600)/60)) $((total_s%60))

# ---- encode -----------------------------------------------------------------
printf 'Encoding -> %s\n' "$OUTPUT"

ff_inputs=( -f concat -safe 0 -i "$CONCAT" -i "$FFMETA" )
map_args=( -map 0:a -map_metadata 1 -map_chapters 1 )
disp_args=()

if [ -n "$COVER" ]; then
  printf 'Embedding cover: %s\n' "$COVER"
  ff_inputs+=( -i "$COVER" )
  map_args+=( -map 2:v )
  disp_args+=( -disposition:v attached_pic -c:v mjpeg )
fi

ffmpeg -hide_banner -loglevel warning -stats -y \
  "${ff_inputs[@]}" \
  "${map_args[@]}" \
  -c:a aac -b:a "$BITRATE" \
  "${disp_args[@]}" \
  -movflags +faststart \
  -f mp4 "$OUTPUT"

printf '\nDone: %s\n' "$OUTPUT"
