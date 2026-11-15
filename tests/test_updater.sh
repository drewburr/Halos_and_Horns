#!/usr/bin/env bash
# Automated test of the new-version notice (scripts/updater.gd), Linux only.
# Exports a real build stamped as version 1.0.0 (the way the release workflow
# stamps them), points it at a stand-in for GitHub on this computer that lists a
# newer release, and checks that the game:
#   1. notices the newer version and offers the download page,
#   2. never downloads or touches any file, even when the release lists a download,
#   3. stays quiet when there's nothing newer.
# Needs Godot with its Linux debug export template installed, and python3.
# Usage: GODOT=/path/to/godot tests/test_updater.sh
set -u
GODOT="${GODOT:-godot}"
PORT="${PORT:-8765}"
FILE=HalosAndHorns.x86_64
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"
GAME="$OUT/install/$FILE"
failures=0

check() {   # check "what" command...
	local what="$1"; shift
	if "$@" >/dev/null 2>&1; then echo "PASS  $what"; else echo "FAIL  $what"; failures=$((failures + 1)); fi
}

cleanup() {
	pkill -f "$OUT/install/" 2>/dev/null
	[ -n "${SERVER:-}" ] && kill "$SERVER" 2>/dev/null
	rm -rf "$OUT"
}
trap cleanup EXIT

echo "Exporting a build (this takes a minute)..."
mkdir -p "$OUT/src" "$OUT/install" "$OUT/serve"
(cd "$ROOT" && git ls-files -co --exclude-standard -z | xargs -0 cp --parents -t "$OUT/src")
sed -i 's|^config/version=.*|config/version="1.0.0"|' "$OUT/src/project.godot"
"$GODOT" --headless --path "$OUT/src" --export-debug Linux "$GAME" > "$OUT/export.log" 2>&1
chmod +x "$GAME" 2>/dev/null
check "the game exports" test -s "$GAME"
BEFORE="$(sha256sum "$GAME" | cut -d' ' -f1)"

echo "not a game" > "$OUT/serve/$FILE"
(cd "$OUT/serve" && exec python3 -m http.server "$PORT" --bind 127.0.0.1) > "$OUT/server.log" 2>&1 &
SERVER=$!
sleep 1
release() {   # release <tag>
	cat > "$OUT/serve/latest.json" <<-EOF2
	{"tag_name": "$1", "assets": [{"name": "$FILE", "browser_download_url": "http://127.0.0.1:$PORT/$FILE", "size": 11}]}
	EOF2
}
ARGS=(--headless --quit-after 300 -- "--update-api=http://127.0.0.1:$PORT/latest.json" --update-click)

# 1 + 2. A newer release: offered, the button opens the page, nothing is downloaded.
release "v99.0.0"
timeout 30 "$GAME" "${ARGS[@]}" > "$OUT/newer.log" 2>&1
check "a newer version is noticed" grep -q "updater\] version 99.0.0 is available" "$OUT/newer.log"
check "...and the button opens the download page" grep -q "updater\] opening the download page" "$OUT/newer.log"
check "...without downloading anything" bash -c "! grep -q 'GET /$FILE' '$OUT/server.log'"
check "...or touching the game file" test "$(sha256sum "$GAME" | cut -d' ' -f1)" = "$BEFORE"
check "...or leaving anything next to it" test "$(ls "$OUT/install" | wc -l)" -eq 1

# 3. Nothing newer: nothing offered.
release "v1.0.0"
timeout 30 "$GAME" "${ARGS[@]}" > "$OUT/same.log" 2>&1
check "the same version isn't offered" bash -c "! grep -q 'is available' '$OUT/same.log'"
check "no script errors" bash -c "! grep -q 'SCRIPT ERROR' '$OUT'/*.log"

echo
if [ "$failures" -eq 0 ]; then
	echo "ALL PASSED: 0 failure(s)"
else
	echo "$failures FAILURE(S)"
	tail -n 20 "$OUT"/*.log
fi
exit "$failures"
