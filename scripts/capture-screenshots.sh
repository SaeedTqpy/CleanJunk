#!/usr/bin/env bash
# Capture REAL CleanJunk windows on a Mac. Requires a running CleanJunk.app.
# This deliberately never commits, uploads, or transfers screenshots.
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Real screenshot capture requires a running macOS desktop session." >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$ROOT/docs/screenshots"
mkdir -p "$OUTPUT"

if ! pgrep -x CleanJunk >/dev/null 2>&1; then
  echo "Launch CleanJunk.app before capturing screenshots." >&2
  exit 1
fi

cat <<'NOTICE'
CleanJunk real screenshot capture
--------------------------------
1. For each page, navigate to it in the running CleanJunk.app.
2. Use a disposable test profile: real paths, installed packages and filenames
   may contain private information and should NEVER be committed unreviewed.
3. For each capture, macOS will ask you to click the CleanJunk window.
4. CleanJunk will not upload or commit screenshots.
NOTICE

for page in overview space-explorer packages system-data; do
  printf '\nNavigate to %s in CleanJunk, then press Enter (Ctrl+C to cancel): ' "$page"
  IFS= read -r _
  target="$OUTPUT/$page.png"
  if [[ -e "$target" ]]; then
    printf 'Overwrite existing %s? Type YES: ' "$target"
    IFS= read -r confirm
    if [[ "$confirm" != "YES" ]]; then
      echo "Skipped $target"
      continue
    fi
  fi
  echo "Click only the CleanJunk window to capture it..."
  if screencapture -i -W -x "$target" && [[ -s "$target" ]]; then
    echo "Saved $target"
  else
    echo "Capture cancelled; no screenshot saved." >&2
    rm -f "$target"
  fi
done

cat <<'DONE'

Review all screenshots for private data before committing:
  open docs/screenshots
  git status --short docs/screenshots

To publish approved, real screenshots:
  git add docs/screenshots/*.png
  git commit -m "docs: add verified real macOS app screenshots"
  git push

These commands do NOT run GitHub Actions (workflow_dispatch only).
DONE
