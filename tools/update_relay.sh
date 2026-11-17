#!/usr/bin/env bash
# relay/ is a copy of four scripts from https://github.com/drewburr-labs/game-relay,
# taken at the tag named in relay/VERSION. This refreshes it.
#
#   tools/update_relay.sh            fetch the copy again at the pinned tag
#   tools/update_relay.sh v1.2.0     move the pin to that tag and fetch it
#   tools/update_relay.sh --check    fail if relay/ differs from the pinned tag
#
# Then run the tests and commit relay/. Change these scripts in game-relay,
# never here: the next update would overwrite it.
set -euo pipefail

REPO="drewburr-labs/game-relay"
FILES=(relay_protocol.gd relay_client.gd relay_server.gd relay_metrics.gd)

cd "$(dirname "$0")/../relay"
check=0
tag="$(cat VERSION)"
case "${1:-}" in
	--check) check=1 ;;
	"") ;;
	*) tag="$1" ;;
esac

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
for f in "${FILES[@]}"; do
	curl -fsSL -o "$tmp/$f" "https://raw.githubusercontent.com/$REPO/$tag/$f" \
		|| { echo "can't fetch $f from $REPO at $tag" >&2; exit 1; }
done

if [ "$check" = 1 ]; then
	bad=0
	for f in "${FILES[@]}"; do
		cmp -s "$tmp/$f" "$f" || { echo "relay/$f differs from $REPO $tag" >&2; bad=1; }
	done
	[ "$bad" = 0 ] && echo "relay/ matches $REPO $tag"
	exit "$bad"
fi

for f in "${FILES[@]}"; do
	cp "$tmp/$f" "$f"
done
echo "$tag" > VERSION
echo "relay/ is now $REPO $tag"
