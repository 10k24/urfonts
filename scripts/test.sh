#!/usr/bin/env bash
# The local gate. CI runs the same commands.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

swift test
swift run -c release UrFonts --headless focus-check
swift run -c release UrFonts --headless render
swift run -c release UrFonts --headless list-spike
swift run -c release UrFonts --headless settings

# Individual file adds and folder exclusion. Two real system fonts keep this
# independent of the user's library; the temporary databases are discarded.
fonts=()
while IFS= read -r path; do
    fonts+=("$path")
done < <(find /System/Library/Fonts -type f -name '*.ttf' 2>/dev/null | head -2)
if [ "${#fonts[@]}" -eq 2 ]; then
    add_db="$(mktemp -t urfonts-add-files)"
    swift run -c release UrFonts --headless add-files --db "$add_db" --no-rescan "${fonts[@]}"
    rm -f "$add_db"

    ignore_db="$(mktemp -t urfonts-ignore-folder)"
    swift run -c release UrFonts --headless ignore-folder --db "$ignore_db" --no-rescan "${fonts[@]}"
    rm -f "$ignore_db"
fi
