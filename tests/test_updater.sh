#!/usr/bin/env bash
# Automated test of the built-in updater (scripts/updater.gd), Linux only.
# Exports two real builds of the game, stamped as versions 1.0.0 and 99.0.0
# the way the release workflow stamps them, serves the newer one from a stand-in for GitHub on this
# computer, and checks that the current build:
#   1. refuses a download that doesn't match the listed checksum, and
#   2. otherwise replaces itself with the newer build and restarts into it.
# Needs Godot with its Linux export template installed, and python3.
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

# Export a copy of the project as the given version.
build() {   # build <name> <version>
	mkdir -p "$OUT/src-$1" "$OUT/$1"
	(cd "$ROOT" && git ls-files -co --exclude-standard -z | xargs -0 cp --parents -t "$OUT/src-$1")
	sed -i "s|^config/version=.*|config/version=\"$2\"|" "$OUT/src-$1/project.godot"
	"$GODOT" --headless --path "$OUT/src-$1" --export-debug Linux "$OUT/$1/$FILE" > "$OUT/$1.export.log" 2>&1
	chmod +x "$OUT/$1/$FILE" 2>/dev/null
	test -s "$OUT/$1/$FILE"
}

# What GitHub's "latest release" answer looks like, as far as the updater reads it.
release() {   # release <sha256 to list>
	cat > "$OUT/serve/latest.json" <<-EOF
	{"tag_name": "v99.0.0", "assets": [{"name": "$FILE",
	  "browser_download_url": "http://127.0.0.1:$PORT/$FILE",
	  "size": $(stat -c %s "$OUT/serve/$FILE"), "digest": "sha256:$1"}]}
	EOF
}

sha() { sha256sum "$1" | cut -d' ' -f1; }

echo "Exporting two builds (this takes a minute)..."
check "the current version exports" build install "1.0.0"
check "a newer version exports" build serve "99.0.0"
OLD="$(sha "$GAME")"
NEW="$(sha "$OUT/serve/$FILE")"
check "the two builds differ" test "$OLD" != "$NEW"

(cd "$OUT/serve" && exec python3 -m http.server "$PORT" --bind 127.0.0.1) > "$OUT/server.log" 2>&1 &
SERVER=$!
sleep 1
ARGS=(--headless -- "--update-api=http://127.0.0.1:$PORT/latest.json" --update-auto)

# 1. A download that doesn't match its checksum is thrown away.
release "$(printf '0%.0s' {1..64})"
timeout 20 "$GAME" "${ARGS[@]}" > "$OUT/bad.log" 2>&1
check "a damaged download is refused" grep -q "updater\] failed: The downloaded file was damaged" "$OUT/bad.log"
check "...and the game file is untouched" test "$(sha "$GAME")" = "$OLD"
check "...with nothing left behind" test ! -e "$GAME.new" -a ! -e "$GAME.old"

# 2. A good download replaces the game, which restarts as the new version.
release "$NEW"
timeout 60 "$GAME" "${ARGS[@]}" > "$OUT/good.log" 2>&1
check "the old game quits by itself after updating" test $? -eq 0
check "the game file is now the new version" test "$(sha "$GAME")" = "$NEW"
check "...and can still be run" test -x "$GAME"
sleep 3
check "the new version is running" pgrep -f "$OUT/install/"
check "...and has removed the old file" test ! -e "$GAME.old"
check "...and doesn't offer the update again" test "$(grep -c 'is available' "$OUT/good.log")" -eq 1

echo
if [ "$failures" -eq 0 ]; then
	echo "ALL PASSED: 0 failure(s)"
else
	echo "$failures FAILURE(S)"
	tail -n 20 "$OUT"/*.log
fi
exit "$failures"
