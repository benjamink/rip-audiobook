# rip-audiobook

Two bash scripts for producing audiobooks from CDs. See README.md for usage.

- `rip-audiobook.sh` — rips multi-disc audiobook CDs to tagged MP3s using
  `cdparanoia` + `lame` + `id3v2`.
- `make-m4b.sh` — packages a ripped `<Author>-<Title>/disc<N>/track<NN>.mp3`
  directory into a single chaptered `.m4b` using only `ffmpeg`/`ffprobe`.

## Structure

### rip-audiobook.sh

Everything lives in `rip-audiobook.sh`:

- `sanitize` — filesystem-safe string helper for author/title dir names
- `check_deps` — verifies cdparanoia/lame/id3v2/eject are installed
- `track_count` — parses `cdparanoia -Q` output to get track count for the
  loaded disc
- `rip_disc` — prompts for a disc, batch-rips all tracks with cdparanoia,
  encodes each to mp3 with lame, tags with id3v2, ejects
- `main` — arg parsing, then loops `rip_disc` over increasing disc numbers
  until the user quits (`Q` at the prompt)

### make-m4b.sh

Everything lives in `make-m4b.sh`:

- gathers audio files under the target dir with `find ... -print0 | sort -z -V`
  (natural order, so `disc2` < `disc10`, `track01` < `track02`)
- reads per-file duration + `title` tag via `ffprobe` to build an ffmetadata
  file with one `[CHAPTER]` block per track (`TIMEBASE=1/1000`)
- builds a concat-demuxer list and runs a single `ffmpeg` invocation:
  `-f concat` input + ffmetadata input, `-map_metadata`/`-map_chapters` from
  the metadata input, re-encode to `aac`, optional cover as `attached_pic`,
  `-movflags +faststart`, `-f mp4`
- book-level tags (title/album/artist/genre/date) come from the first file;
  `media_type=2` marks it as an audiobook

## Conventions

- `set -euo pipefail`; config values default via `${VAR:-default}` so every
  setting is overridable by env var, with CLI flags overriding those for the
  common ones (author/title/year/genre/output dir).
- Disc/track loop uses return codes as control flow: `rip_disc` returns `2`
  for user-requested quit, `1` for a skipped/failed disc, `0` for success.
  `main`'s loop only breaks on `2`.
- No test suite — this is a hands-on hardware script (drives an optical
  drive interactively). Validate changes with `bash -n rip-audiobook.sh` and
  `shellcheck rip-audiobook.sh` at minimum; the `# shellcheck disable`
  comment on the cdparanoia call is intentional (word-splitting the speed
  flag is desired there).
