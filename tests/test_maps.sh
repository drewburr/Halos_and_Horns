#!/bin/bash
# A host on a custom map: the joiner must get the map and play a round on it.
GODOT=${GODOT:-godot}
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
"$GODOT" --headless -- --host --name=Theo --autobot --autostart=2 --hide=5 --hunt=25 --quit-after-round \
	--map=res://tests/test_map.json --roles=Theo:angel,Wife:demon > "$OUT/host.log" 2>&1 &
sleep 3
timeout 90 "$GODOT" --headless -- --join=127.0.0.1 --name=Wife --autobot --quit-after-round > "$OUT/Wife.log" 2>&1
wait
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=$((fails+1)); fi; }
check "the joiner got the host's map" "grep -q 'map: Test Arena' '$OUT/Wife.log'"
check "a round was played on it" "grep -q 'round over' '$OUT/Wife.log'"
check "no script errors" "! grep -q 'SCRIPT ERROR' '$OUT'/*.log"
if [ $fails -eq 0 ]; then echo "ALL PASSED"; else echo "FAILED (logs in $OUT)"; fi
