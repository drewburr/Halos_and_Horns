#!/usr/bin/env bash
# Plays a full online match with 5 copies of the game on this computer, no humans:
# a host plus 4 joined players, all driven by the autobot. One player tries to
# teleport out of bounds. Passes if the round ends with every demon caught, every
# angel saw only fellow angels' names (demons see none), and the host blocked the cheat.
#
# Usage: GODOT=/path/to/godot tests/test_multiplayer.sh
set -u
GODOT="${GODOT:-godot}"
OUT="$(mktemp -d)"
cd "$(dirname "$0")/.."

"$GODOT" --headless -- --host --name=Theo --autobot --autostart=5 --hide=14 --hunt=150 --quit-after-round --skills=possess,fear \
	--roles=Theo:demon,Wife:angel,Brother:demon,Squirrel:angel,Oddy:demon > "$OUT/host.log" 2>&1 &
sleep 3
for n in Wife Brother Squirrel Oddy; do
	extra=""
	[ "$n" = "Oddy" ] && extra="--cheat=teleport,fly --skills=teleport,fly"
	[ "$n" = "Wife" ] && extra="--skills=cherub,vacuum --say=hello_everyone --cheat=claim"
	[ "$n" = "Squirrel" ] && extra="--skills=dash,leap"
	[ "$n" = "Brother" ] && extra="--skills=fire,minion --sayteam=demons_only_secret"
	timeout 240 "$GODOT" --headless -- --join=127.0.0.1 --name=$n --autobot --quit-after-round $extra > "$OUT/$n.log" 2>&1 &
	sleep 0.5
done
# Someone joining mid-round (an angel) must see the props as they are by then.
(sleep 24; timeout 200 "$GODOT" --headless -- --join=127.0.0.1 --name=Late --autobot --lazy --quit-after-round > "$OUT/Late.log" 2>&1) &
wait

fail=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fail=1; fi; }

check "round started with 5 players" "grep -q 'round started: 2 angel(s), 3 demon(s)' '$OUT/host.log'"
end_msg=$(grep -m1 -oE "round over: .*" "$OUT/host.log" | sed 's/round over: //')
check "round ended ($end_msg)" "[ -n \"$end_msg\" ]"
check "at least one demon was caught" "grep -q 'was caught' '$OUT/host.log'"
for n in Wife Brother Squirrel Oddy; do
	check "$n saw the same result as the host" "grep -qF \"round over: $end_msg\" '$OUT/$n.log'"
	if grep -q "\\[host\\] $n was caught" "$OUT/host.log"; then
		check "$n was caught and switched to the angel side" "grep -q 'now playing as angel' '$OUT/$n.log'"
	fi
done
check "flying without Hatred was caught" "grep -q 'blocked Oddy: flying without enough Hatred' '$OUT/host.log'"
check "no false alarms (only Oddy was flagged)" "! grep '^\\[host\\] blocked' '$OUT/host.log' | grep -qv 'blocked Oddy'"
check "demons flew" "grep -q 'flying' '$OUT/Brother.log' '$OUT/Theo.log' '$OUT/Oddy.log'"
check "a demon possessed a real prop" "grep -q 'a demon possessed a' '$OUT/host.log'"
check "an angel dropped an Alarm Cherub" "grep -q 'cherub dropped' '$OUT/host.log'"
check "an angel threw a Vacuum Orb" "grep -q 'vacuum orb' '$OUT/host.log'"
check "an angel used the Flying Dash" "grep -q 'used dash' '$OUT/Squirrel.log'"
if grep -q 'used fire' "$OUT/Brother.log"; then
	check "a demon flung Hellfire" "grep -q 'hellfire lit' '$OUT/host.log'"
fi
check "an angel used Holy Leap" "grep -q 'used leap' '$OUT/Squirrel.log'"
# (only if the stomp landed before the round ended)
if sed '/round over/q' "$OUT/Squirrel.log" | grep -q 'used stomp'; then
	check "...and the host handled the Cloud Stomp" "grep -q 'cloud stomp hit' '$OUT/host.log'"
fi
check "the roster shows chosen skills" "grep -q 'Wife(angel,[0-9]*ms,Alarm Cherub+Vacuum Orb)' '$OUT/Brother.log'"
check "out-of-bounds teleport was blocked" "grep -q 'blocked Oddy: out of bounds' '$OUT/host.log'"
x=$(grep -oE 'after cheat, position x = -?[0-9.]+' "$OUT/Oddy.log" | grep -oE -- '-?[0-9.]+$')
check "cheater was snapped back inside the map (x=$x)" "awk -v x=\"$x\" 'BEGIN { exit !(x != \"\" && x < 28.5 && x > -28.5) }'"
# Name leaks: only angels see names, and only their fellow angels'.
leaks=$(grep -h "names I can see" "$OUT"/*.log | awk '{
	me=$4; sub(",", "", me)
	for (i = 1; i <= NF; i++) if ($i ~ /^(angel|demon)=/) {
		split($i, kv, "="); nm = kv[2]; sub(",$", "", nm)
		if (nm != "<hidden>" && (kv[1] != me || me == "demon")) print
	}
}')
check "no player ever saw a name they shouldn't (enemies, or anyone as a demon)" "[ -z \"$leaks\" ]"
check "angels can see their fellow angels' names" "grep -h 'as angel, names I can see' '$OUT'/*.log | grep -qE 'angel=(Theo|Wife|Brother|Squirrel|Oddy)'"
check "name checks actually ran" "[ \$(grep -h 'names I can see' '$OUT'/*.log | wc -l) -ge 5 ]"
for n in Wife Brother Squirrel Oddy; do
	line=$(grep -m1 "roster:" "$OUT/$n.log")
	check "$n's Tab roster lists all 5 players" "[ \$(echo \"$line\" | grep -oE '(Theo|Wife|Brother|Squirrel|Oddy)\\((angel|demon),' | wc -l) -eq 5 ]"
	check "$n's ping is measured" "echo \"$line\" | grep -qE 'my ping [0-9]+'"
done
check "global chat reaches the other team" "grep -q 'Wife: hello_everyone' '$OUT/Oddy.log'"
check "team chat reaches teammates" "grep -q '\[TEAM\] Brother: demons_only_secret' '$OUT/host.log'"
check "team chat never reaches the other team" "! grep -q 'demons_only_secret' '$OUT/Wife.log' '$OUT/Squirrel.log'"
# (Whether a hit is counted by the host's own copy of a throw or by the thrower's
# claim depends on timing, so this only checks that real claims aren't refused for
# being off the throw's path or behind walls.)
check "real hit claims aren't refused as impossible" "! grep -E \"refused (Theo|Brother|Squirrel|Oddy)'s hit claim: (not on that throw's path|through a wall)\" '$OUT/host.log'"
check "a made-up hit claim is refused" "grep -q \"refused Wife's hit claim\" '$OUT/host.log'"
check "everyone hears who redeemed whom" "grep -qE '\\[news\\] [A-Za-z]+ redeemed [A-Za-z]+!' '$OUT/Wife.log'"
if [ $(grep -c 'was caught' "$OUT/host.log") -ge 2 ]; then
	check "everyone hears who the last demon is" "grep -q 'LAST demon standing' '$OUT/Squirrel.log'"
fi
if grep -q 'used minion' "$OUT/Brother.log"; then
	check "a demon sent out a minion and the host showed it to everyone" "grep -q 'Brother sent out a minion' '$OUT/host.log'"
fi
if grep -q 'BOT Theo: used fear' "$OUT/host.log"; then
	check "Fear: the host scattered the angels near the demon" "grep -qE 'fear: [1-9] angel' '$OUT/host.log'"
	check "...and a scared angel was told" "grep -q 'scared!' '$OUT/Wife.log' '$OUT/Squirrel.log' '$OUT/Brother.log' '$OUT/Oddy.log'"
fi
if grep -qE 'picked up vanish' "$OUT/host.log"; then
	check "Invisibility power-up: the host hid the demon from the angels" "grep -q ' vanished' '$OUT/host.log'"
fi
if grep -q 'used teleport' "$OUT/Oddy.log"; then
	check "Teleport: the host moved the demon" "grep -q 'teleport' '$OUT/host.log'"
fi
if grep -q 'was caught' "$OUT/host.log"; then
	check "a redeemed demon drops an angel power-up" "grep -q 'angel power-up dropped' '$OUT/host.log'"
fi
if grep -q 'now playing as angel' "$OUT/Late.log" 2>/dev/null; then
	check "a mid-round joiner catches up on taken and moved props" "grep -q 'caught up on the props' '$OUT/Late.log'"
fi
check "no player script errors" "! grep -q 'SCRIPT ERROR' '$OUT'/*.log"

if [ $fail -eq 0 ]; then echo "ALL PASSED"; else echo "FAILED (logs in $OUT)"; fi
exit $fail
