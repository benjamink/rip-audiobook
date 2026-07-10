# rip-audiobook

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
