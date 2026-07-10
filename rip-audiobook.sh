#!/usr/bin/env bash
#
# rip-audiobook.sh
#
# Rips a multi-disc audiobook to MP3 using cdparanoia (fast raw-read mode,
# no paranoia error correction) + lame (mono, low bitrate, tuned for
# spoken word). Output is organized as:
#
#   <output-dir>/<Author>-<Title>/disc<N>/track<NN>.mp3
#
# Author, title, genre, and year are set once at the top and reused for
# every disc and track (with per-disc/track numbering in the ID3 tags).
#
# Requirements: cdparanoia, lame, id3v2, eject (all in most distro repos:
#   sudo apt install cdparanoia lame id3v2 eject
#
# Usage:
#   ./rip-audiobook.sh [-a author] [-t title] [-y year] [-g genre] [-o output-dir] [start-disc-number]
#
#   -a  Author (default: env AUTHOR or built-in default)
#   -t  Title  (default: env TITLE or built-in default)
#   -y  Year   (default: env YEAR or built-in default)
#   -g  Genre  (default: env GENRE or built-in default)
#   -o  Output root directory (default: env OUTPUT_ROOT or ~/Audiobooks)
#
#   A trailing positional argument resumes ripping at that disc number,
#   e.g. `./rip-audiobook.sh -a "Author" -t "Title" 4` starts at disc 4.
#
set -euo pipefail

# ------------------------- CONFIG (edit me) --------------------------------

AUTHOR="${AUTHOR:-Van der Kolk, Bessel}"
TITLE="${TITLE:-The Body Keeps the Score}"
GENRE="${GENRE:-Audiobook}"
YEAR="${YEAR:-2014}"
DEVICE="${DEVICE:-/dev/cdrom}"   # optical drive device
OUTPUT_ROOT="${OUTPUT_ROOT:-$HOME/Audiobooks}"
START_DISC="${START_DISC:-1}"   # override to resume, e.g. START_DISC=4, or pass as first arg

# Encoding settings tuned for spoken word: mono, 22.05kHz, ~48kbps VBR.
# This keeps file sizes small while remaining perfectly intelligible for
# voice. Bump LAME_BITRATE up (e.g. 64) if you want a bit more headroom.
LAME_MODE="m"          # mono (spoken word doesn't need stereo)
LAME_RESAMPLE="22.05"  # kHz — plenty for voice, halves file size vs 44.1
LAME_VBR_QUALITY="7"   # lame -V setting: 0=best/biggest .. 9=worst/smallest
                        # V7 ~= 48kbps avg mono, good tradeoff for speech

# Speed optimization: -Z tells cdparanoia to skip the paranoia error-
# correction/verification passes and just read the disc as fast as
# possible. Audiobooks are spoken word, not archival audio, so a dropped
# sample here and there is not worth the multi-pass re-read overhead.
# Remove -Z (or set to "") if you hit a scratched/troublesome disc and
# want full paranoia error correction instead.
CDPARANOIA_SPEED_FLAG="${CDPARANOIA_SPEED_FLAG:--Z}"

# After a disc swap, the drive may need a few seconds to spin up and mount
# before it can report its table of contents. Retry TOC reads for up to
# this many seconds before giving up on the disc.
TOC_RETRY_SECONDS="${TOC_RETRY_SECONDS:-15}"
TOC_RETRY_INTERVAL="${TOC_RETRY_INTERVAL:-2}"

# -----------------------------------------------------------------------

sanitize() {
  # Make a string filesystem-safe: strip slashes/colons, collapse spaces.
  echo "$1" | tr '/:' '--' | tr -s ' ' '_'
}

check_deps() {
  local missing=()
  for cmd in cdparanoia lame id3v2 eject; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if (( ${#missing[@]} > 0 )); then
    echo "Missing required tool(s): ${missing[*]}" >&2
    echo "Install with: sudo apt install cdparanoia lame id3v2 eject" >&2
    exit 1
  fi
}

track_count() {
  # Ask cdparanoia how many audio tracks are on the disc currently loaded.
  local out
  out="$(cdparanoia -d "$DEVICE" -Q 2>&1 || true)"
  # cdparanoia -Q prints a table; last numbered track line has the count.
  echo "$out" | awk '/^ *[0-9]+\./ {n=$1} END {gsub(/\./,"",n); print n}'
}

rip_disc() {
  local disc_num="$1"
  local disc_dir="$2"
  local tmp_dir
  tmp_dir="$(mktemp -d)"

  echo
  echo "=== Disc ${disc_num}: ${AUTHOR} - ${TITLE} ==="
  local answer
  read -r -p "Insert disc ${disc_num}, close the tray, then press Enter to rip (or Q to quit)... " answer
  if [[ "$answer" =~ ^[Qq]$ ]]; then
    rm -rf "$tmp_dir"
    return 2
  fi

  echo "Reading table of contents..."
  local n_tracks="" elapsed=0
  while (( elapsed < TOC_RETRY_SECONDS )); do
    n_tracks="$(track_count)"
    if [[ -n "$n_tracks" && "$n_tracks" -gt 0 ]]; then
      break
    fi
    echo "Drive not ready yet, retrying..."
    sleep "$TOC_RETRY_INTERVAL"
    elapsed=$((elapsed + TOC_RETRY_INTERVAL))
  done
  if [[ -z "$n_tracks" || "$n_tracks" -eq 0 ]]; then
    echo "Could not detect any audio tracks on disc ${disc_num} after ${TOC_RETRY_SECONDS}s. Skipping." >&2
    rm -rf "$tmp_dir"
    return 1
  fi
  echo "Found ${n_tracks} track(s). Ripping (fast mode)..."

  mkdir -p "$disc_dir"

  # Batch-rip all tracks in one pass — much faster than invoking
  # cdparanoia once per track, since it only needs to spin up once.
  (
    cd "$tmp_dir"
    # shellcheck disable=SC2086
    cdparanoia -d "$DEVICE" $CDPARANOIA_SPEED_FLAG -B "1-${n_tracks}"
  )

  local track
  for track in $(seq 1 "$n_tracks"); do
    local track_padded
    track_padded="$(printf '%02d' "$track")"
    # cdparanoia's batch mode always zero-pads to (at least) 2 digits,
    # regardless of the total track count.
    local wav="${tmp_dir}/track${track_padded}.cdda.wav"
    if [[ ! -f "$wav" ]]; then
      echo "Warning: expected wav for track ${track_padded} not found, skipping." >&2
      continue
    fi

    local mp3="${disc_dir}/track${track_padded}.mp3"
    echo "Encoding disc ${disc_num} track ${track_padded} -> ${mp3}"

    lame --quiet \
      -m "$LAME_MODE" \
      --resample "$LAME_RESAMPLE" \
      -V "$LAME_VBR_QUALITY" \
      "$wav" "$mp3"

    id3v2 \
      --artist "$AUTHOR" \
      --album "$TITLE" \
      --song "Disc ${disc_num} - Track ${track_padded}" \
      --genre "$GENRE" \
      --year "$YEAR" \
      --track "$((10#$track))" \
      "$mp3" >/dev/null
  done

  rm -rf "$tmp_dir"
  eject "$DEVICE" 2>/dev/null || true
  echo "Disc ${disc_num} complete: ${disc_dir}"
}

main() {
  local opt
  while getopts ":a:t:y:g:o:h" opt; do
    case "$opt" in
      a) AUTHOR="$OPTARG" ;;
      t) TITLE="$OPTARG" ;;
      y) YEAR="$OPTARG" ;;
      g) GENRE="$OPTARG" ;;
      o) OUTPUT_ROOT="$OPTARG" ;;
      h)
        sed -n '17,27p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
      \?)
        echo "Unknown option: -$OPTARG" >&2
        exit 1
        ;;
      :)
        echo "Option -$OPTARG requires an argument" >&2
        exit 1
        ;;
    esac
  done
  shift $((OPTIND - 1))

  if [[ $# -gt 0 ]]; then
    if [[ ! "$1" =~ ^[0-9]+$ || "$1" -lt 1 ]]; then
      echo "Invalid start disc number: $1" >&2
      exit 1
    fi
    START_DISC="$1"
  fi

  check_deps

  local safe_author safe_title book_dir
  safe_author="$(sanitize "$AUTHOR")"
  safe_title="$(sanitize "$TITLE")"
  book_dir="${OUTPUT_ROOT}/${safe_author}-${safe_title}"

  echo "Ripping audiobook:"
  echo "  Author: ${AUTHOR}"
  echo "  Title:  ${TITLE}"
  echo "  Genre:  ${GENRE}"
  echo "  Year:   ${YEAR}"
  echo "  Output: ${book_dir}"
  if [[ "$START_DISC" -gt 1 ]]; then
    echo "  Resuming at disc: ${START_DISC}"
  fi

  mkdir -p "$book_dir"

  local d="$START_DISC"
  local disc_dir rc
  while true; do
    disc_dir="${book_dir}/disc${d}"
    if rip_disc "$d" "$disc_dir"; then
      rc=0
    else
      rc=$?
    fi

    if [[ "$rc" -eq 2 ]]; then
      break
    elif [[ "$rc" -ne 0 ]]; then
      echo "Disc ${d} failed or was skipped." >&2
    fi
    d=$((d+1))
  done

  echo
  echo "All done. Audiobook saved under: ${book_dir}"
}

main "$@"
