# rip-audiobook

Bash scripts for ripping multi-disc audiobook CDs to MP3 and packaging them
into a single `.m4b` audiobook file:

- `rip-audiobook.sh` — rip the CDs to a tagged, per-disc MP3 collection.
- `make-m4b.sh` — join that collection into one chaptered `.m4b`.

## rip-audiobook.sh

A bash script for ripping multi-disc audiobook CDs to MP3.

It combines `cdparanoia` (fast raw-read mode, no error-correction passes) and
`lame` (mono, low bitrate, tuned for spoken word) to quickly turn a stack of
audiobook CDs into a tagged MP3 collection, prompting you to swap discs as it
goes.

Output is organized as:

```
<output-dir>/<Author>-<Title>/disc<N>/track<NN>.mp3
```

Each track is tagged with author, title, genre, year, disc/track number via
`id3v2`.

## Requirements

- Linux with an optical drive
- `cdparanoia`, `lame`, `id3v2`, `eject`

```sh
sudo apt install cdparanoia lame id3v2 eject
```

## Usage

```sh
./rip-audiobook.sh [-a author] [-t title] [-y year] [-g genre] [-o output-dir] [start-disc-number]
```

| Flag | Meaning | Default |
|------|---------|---------|
| `-a` | Author | env `AUTHOR` or built-in default |
| `-t` | Title | env `TITLE` or built-in default |
| `-y` | Year | env `YEAR` or built-in default |
| `-g` | Genre | env `GENRE` or built-in default |
| `-o` | Output root directory | env `OUTPUT_ROOT` or `~/Audiobooks` |

A trailing positional argument resumes ripping at that disc number, e.g.:

```sh
./rip-audiobook.sh -a "Author" -t "Title" 4
```

The script loops disc by disc, prompting you to insert each one:

```
=== Disc 1: Author - Title ===
Insert disc 1, close the tray, then press Enter to rip (or Q to quit)...
```

Press `Q` at any prompt to stop; the audiobook directory it built so far is
left intact.

### Environment variables

All config at the top of the script can also be set via environment
variables instead of flags, e.g.:

```sh
DEVICE=/dev/sr0 AUTHOR="Author" TITLE="Title" ./rip-audiobook.sh
```

Notable ones not exposed as flags:

- `DEVICE` — optical drive device (default `/dev/cdrom`)
- `CDPARANOIA_SPEED_FLAG` — defaults to `-Z` (skip paranoia error
  correction for speed). Set to empty string for full error correction on
  scratched discs.
- `TOC_RETRY_SECONDS` / `TOC_RETRY_INTERVAL` — how long/often to retry
  reading a disc's table of contents after a swap (default 15s / 2s).

## Encoding settings

Tuned for spoken word rather than music: mono, resampled to 22.05kHz, LAME
`-V 7` (~48kbps VBR). This keeps files small while staying intelligible for
voice. Edit the `LAME_*` variables at the top of the script to change this.

# make-m4b.sh

Packages an audiobook directory into a single self-contained `.m4b` file,
named after the directory. It's the natural second step after
`rip-audiobook.sh`: point it at a `<Author>-<Title>/` directory and it joins
every track into one chaptered audiobook.

It joins all the audio files it finds under the directory, in natural order
(so `disc2` sorts before `disc10` and `track01` before `track02`),
re-encodes them to AAC, and writes a `.m4b` with:

- **one chapter per source track**, titled from each file's embedded `title`
  tag (falling back to a path-derived label), with boundaries computed from
  each file's real duration;
- **book-level metadata** (title, author, genre, year) copied from the first
  file's tags, tagged as an audiobook (`media_type=2`) so players shelve it
  correctly;
- **cover art** embedded if a `cover`/`folder`/`front`/`albumart` image is
  found under the directory;
- `+faststart` so the file streams without a full download.

Only `ffmpeg`/`ffprobe` are required — no `mp4v2`/`AtomicParsley` tools.

## Requirements

- `ffmpeg`, `ffprobe`

```sh
sudo apt install ffmpeg
```

## Usage

```sh
./make-m4b.sh [DIR] [-b BITRATE] [-o OUTPUT.m4b] [-f]
```

| Flag | Meaning | Default |
|------|---------|---------|
| `DIR` | Audiobook directory to package | current directory |
| `-b` | AAC bitrate for the output | `64k` |
| `-o` | Output file path | `<DIR-basename>.m4b` beside `DIR` |
| `-f` | Overwrite the output file if it exists | off |

For example, to package a book ripped by `rip-audiobook.sh`:

```sh
./make-m4b.sh ~/Audiobooks/Turton,Stuart-The_7_1-2_Deaths_of_Evelyn_Hardcastle
```

This writes
`~/Audiobooks/Turton,Stuart-The_7_1-2_Deaths_of_Evelyn_Hardcastle.m4b`.

## Encoding settings

The output is AAC at `-b 64k` by default, which is generous for mono
spoken-word source. Lower it (e.g. `-b 48k`) for smaller files, or raise it
for stereo/music-heavy content.
