# rip-audiobook

Single-file bash script (`rip-audiobook.sh`) that rips multi-disc audiobook
CDs to tagged MP3s using `cdparanoia` + `lame` + `id3v2`. See README.md for
usage.

## Structure

Everything lives in `rip-audiobook.sh`:

- `sanitize` — filesystem-safe string helper for author/title dir names
- `check_deps` — verifies cdparanoia/lame/id3v2/eject are installed
- `track_count` — parses `cdparanoia -Q` output to get track count for the
  loaded disc
- `rip_disc` — prompts for a disc, batch-rips all tracks with cdparanoia,
  encodes each to mp3 with lame, tags with id3v2, ejects
- `main` — arg parsing, then loops `rip_disc` over increasing disc numbers
  until the user quits (`Q` at the prompt)

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
