extends RefCounted
## What the relay counts, and how it's written out for Prometheus (the text
## format, https://prometheus.io/docs/instrumenting/exposition_formats/).
## relay_server.gd adds to these as things happen; relay_metrics_http.gd
## serves render()'s text. README.md lists every metric.
##
## Nothing here names a room code or a player's address: it's totals, by game
## id at the finest.

const P = preload("relay_protocol.gd")

## Game ids come from clients, so only the first MAX_GAMES get a label of
## their own; the rest are counted together as OTHER. Otherwise anyone could
## grow the metrics without limit by opening rooms under made-up ids.
const MAX_GAMES := 32
const OTHER := "other"

const DURATION_BUCKETS: Array[float] = [10, 30, 60, 120, 300, 600, 1200, 1800, 3600, 7200, 14400]
const PEERS_BUCKETS: Array[float] = [1, 2, 3, 4, 5, 6, 8, 12, 16, 24, 32]
const RTT_BUCKETS: Array[float] = [0.01, 0.02, 0.035, 0.05, 0.075, 0.1, 0.15, 0.2, 0.3, 0.5, 1]
const LOSS_BUCKETS: Array[float] = [0.001, 0.005, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5]
const POLL_BUCKETS: Array[float] = [0.0001, 0.00025, 0.0005, 0.001, 0.0025, 0.005, 0.01, 0.025, 0.05, 0.1]


class Histogram:
	var bounds: PackedFloat64Array
	var counts: PackedInt64Array # per bucket (not running totals); the last is everything above
	var sum := 0.0
	var count := 0

	func _init(p_bounds: Array[float]) -> void:
		bounds = PackedFloat64Array(p_bounds)
		counts.resize(bounds.size() + 1)

	func observe(v: float) -> void:
		counts[bounds.bsearch(v)] += 1
		sum += v
		count += 1


## One game id's numbers.
class Game:
	var name := ""
	var rooms_opened := 0
	var rooms_closed := 0
	var joins := 0
	var packets := 0 # game packets passed on
	var bytes := 0 # and their payload
	var duration := Histogram.new(DURATION_BUCKETS) # how long rooms stayed open
	var peak := Histogram.new(PEERS_BUCKETS) # the most machines each room had at once
	var rtt := Histogram.new(RTT_BUCKETS) # round trips to the relay, sampled
	var loss := Histogram.new(LOSS_BUCKETS) # packet loss, sampled


var started := Time.get_unix_time_from_system()
var connections_opened := 0
var connections_closed := 0
var refusals := PackedInt64Array() # by P.Refusal
var ignored_packets := 0
var sent_bytes := 0 # on the wire, ENet's own overhead included
var sent_packets := 0
var received_bytes := 0
var received_packets := 0
var poll_time := Histogram.new(POLL_BUCKETS) # polls that had something to do

var _games := {} # game id -> Game


func _init() -> void:
	refusals.resize(P.Refusal.size() + 1)


## The numbers for this game id (or for OTHER, once there are MAX_GAMES).
func game(id: String) -> Game:
	var g: Game = _games.get(id)
	if g == null:
		if _games.size() >= MAX_GAMES:
			id = OTHER
			g = _games.get(id)
		if g == null:
			g = Game.new()
			g.name = id
			_games[id] = g
	return g


## ENet's traffic totals since the last call.
func add_traffic(conn: ENetConnection) -> void:
	sent_bytes += int(conn.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA))
	sent_packets += int(conn.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS))
	received_bytes += int(conn.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA))
	received_packets += int(conn.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_PACKETS))


## The Prometheus text. `open` is what's open right now, which only the
## server knows: game label -> [rooms, seats, peers]. Hosts count in both.
func render(open: Dictionary, connections: int, max_rooms: int, max_connections: int) -> String:
	var o := PackedStringArray()
	var games: Array = _games.values()
	games.sort_custom(func(a: Game, b: Game) -> bool: return a.name < b.name)
	var labels := {} # Game -> game="..."
	for g: Game in games:
		labels[g] = "game=\"%s\"" % g.name.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")

	_head(o, "relay_info", "gauge", "Always 1; protocol is the relay protocol version it speaks.")
	o.append("relay_info{protocol=\"%d\"} 1" % P.VERSION)

	var gauges := [
		["relay_rooms", "Rooms open now."],
		["relay_room_seats", "Machines the open rooms have room for, hosts included."],
		["relay_room_peers", "Machines in the open rooms now, hosts included."],
	]
	for i in gauges.size():
		_head(o, gauges[i][0], "gauge", gauges[i][1])
		for g: Game in games:
			o.append("%s{%s} %d" % [gauges[i][0], labels[g], open.get(g.name, [0, 0, 0])[i]])
	_one(o, "relay_rooms_limit", "gauge", "Most rooms the relay opens at once, across every game.", max_rooms)
	_one(o, "relay_connections", "gauge", "Connections open now, in a room or not.", connections)
	_one(o, "relay_connections_limit", "gauge", "Most connections the relay takes at once.", max_connections)

	var counters := [
		["relay_rooms_opened_total", "Rooms opened.", func(g: Game) -> int: return g.rooms_opened],
		["relay_rooms_closed_total", "Rooms closed (their host left).", func(g: Game) -> int: return g.rooms_closed],
		["relay_room_joins_total", "Times a client got into a room.", func(g: Game) -> int: return g.joins],
		["relay_game_packets_total", "Game packets the relay took in to pass on.", func(g: Game) -> int: return g.packets],
		["relay_game_bytes_total", "Bytes of game payload in those packets.", func(g: Game) -> int: return g.bytes],
	]
	for c: Array in counters:
		_head(o, c[0], "counter", c[1])
		for g: Game in games:
			o.append("%s{%s} %d" % [c[0], labels[g], c[2].call(g)])

	var histograms := [
		["relay_room_duration_seconds", "How long each closed room was open.", func(g: Game) -> Histogram: return g.duration],
		["relay_room_peak_peers", "The most machines each closed room had at once, host included.", func(g: Game) -> Histogram: return g.peak],
		["relay_peer_round_trip_seconds", "Round trip between the relay and each machine in a room, sampled every 10 s.", func(g: Game) -> Histogram: return g.rtt],
		["relay_peer_packet_loss_ratio", "Packet loss (0 to 1) to each machine in a room, sampled every 10 s.", func(g: Game) -> Histogram: return g.loss],
	]
	for h: Array in histograms:
		_head(o, h[0], "histogram", h[1])
		for g: Game in games:
			_histogram(o, h[0], labels[g], h[2].call(g))

	_one(o, "relay_connections_opened_total", "counter", "Connections accepted.", connections_opened)
	_one(o, "relay_connections_closed_total", "counter", "Connections that ended.", connections_closed)
	_head(o, "relay_refusals_total", "counter", "Requests to host or join that the relay turned away.")
	for why: String in P.Refusal:
		o.append("relay_refusals_total{reason=\"%s\"} %d" % [why.to_lower(), refusals[P.Refusal[why]]])
	_one(o, "relay_ignored_packets_total", "counter", "Packets dropped: empty, too big, an unknown type, or data from outside a room.", ignored_packets)
	_one(o, "relay_network_sent_bytes_total", "counter", "Bytes sent, ENet's overhead included.", sent_bytes)
	_one(o, "relay_network_sent_packets_total", "counter", "UDP packets sent.", sent_packets)
	_one(o, "relay_network_received_bytes_total", "counter", "Bytes received, ENet's overhead included.", received_bytes)
	_one(o, "relay_network_received_packets_total", "counter", "UDP packets received.", received_packets)
	_head(o, "relay_poll_duration_seconds", "histogram", "Time each poll with something to do took; packets wait while one runs. Its sum is the time spent working.")
	_histogram(o, "relay_poll_duration_seconds", "", poll_time)

	_one(o, "process_start_time_seconds", "gauge", "When the relay started, in Unix time.", "%.3f" % started)
	var proc := _process()
	if proc.has("cpu"):
		_one(o, "process_cpu_seconds_total", "counter", "CPU time the relay has used.", "%.2f" % proc["cpu"])
	if proc.has("rss"):
		_one(o, "process_resident_memory_bytes", "gauge", "Memory the relay holds.", proc["rss"])
	o.append("")
	return "\n".join(o)


static func _head(o: PackedStringArray, name: String, type: String, help: String) -> void:
	o.append("# HELP %s %s" % [name, help])
	o.append("# TYPE %s %s" % [name, type])


static func _one(o: PackedStringArray, name: String, type: String, help: String, value: Variant) -> void:
	_head(o, name, type, help)
	o.append("%s %s" % [name, value])


static func _histogram(o: PackedStringArray, name: String, labels: String, h: Histogram) -> void:
	var sep := "," if labels != "" else ""
	var n := 0
	for i in h.bounds.size():
		n += h.counts[i]
		o.append("%s_bucket{%s%sle=\"%s\"} %d" % [name, labels, sep, String.num(h.bounds[i]).trim_suffix(".0"), n])
	o.append("%s_bucket{%s%sle=\"+Inf\"} %d" % [name, labels, sep, h.count])
	var braces := "{%s}" % labels if labels != "" else ""
	o.append("%s_sum%s %s" % [name, braces, String.num(h.sum, 6)])
	o.append("%s_count%s %d" % [name, braces, h.count])


## CPU seconds used and memory held, from /proc; empty where there isn't one
## (anything but Linux).
static func _process() -> Dictionary:
	var out := {}
	var stat := FileAccess.open("/proc/self/stat", FileAccess.READ)
	if stat != null:
		# "pid (name) state ...": after the name, user and system time are
		# the 12th and 13th numbers, in ticks of 1/100 s.
		var line := stat.get_line()
		var f := line.substr(line.rfind(")") + 2).split(" ")
		if f.size() > 12:
			out["cpu"] = (int(f[11]) + int(f[12])) / 100.0
	var status := FileAccess.open("/proc/self/status", FileAccess.READ)
	while status != null:
		var line := status.get_line()
		if line.begins_with("VmRSS:"):
			out["rss"] = int(line.trim_prefix("VmRSS:").strip_edges().get_slice(" ", 0)) * 1024
			break
		if line == "":
			break
	return out
