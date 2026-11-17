extends RefCounted
## The relay: lets players behind home routers play without port forwarding.
## A host opens a room for its game and gets a short code; friends join with
## the code; the relay then passes each room's packets between its host and
## clients, on the same channel and with the same reliability. It never reads
## the games' messages, so any game can use it and it doesn't change when they
## do, as long as relay_protocol.gd's VERSION stays the same.
##
## run_relay.gd runs it (see Dockerfile); tests drive poll() themselves.
## It counts what happens in `metrics` (relay_metrics.gd); metrics_text() is
## those numbers for Prometheus.
## It uses a raw ENetConnection rather than ENetMultiplayerPeer, so it sees
## every connection as a plain peer and can route between them.

const P = preload("relay_protocol.gd")
const Metrics = preload("relay_metrics.gd")

const MAX_PEERS := 1024
const MAX_ROOMS := 400
const MAX_PACKET := 256 * 1024
const MAX_BAD_JOINS := 20 # wrong codes per address per minute, against code guessing
const SAMPLE_MSEC := 10000 # how often metrics look at every peer's round trip and loss

var quiet := false # tests: don't log
var conn: ENetConnection
var metrics := Metrics.new()

var _next_id := 2 # 1 means "the host" inside a room
var _ids := {} # ENetPacketPeer -> id
var _peers := {} # id -> ENetPacketPeer
var _room_of := {} # id -> room code
var _rooms := {} # code -> {"game": game id, "host": id, "size": max clients, "clients": {id: true},
#   and for metrics: "stats": the game's Metrics.Game, "opened": msec, "peak": most machines at once}
var _bad_joins := {} # remote address -> [wrong codes, minute they're counted in]
var _rng := RandomNumberGenerator.new()
var _sampled := 0 # msec, when metrics last sampled the peers


func start(port: int, bind: String = "*") -> Error:
	conn = ENetConnection.new()
	var err := conn.create_host_bound(bind, port, MAX_PEERS, P.MAX_CHANNELS)
	if err != OK:
		conn = null
		return err
	_rng.randomize()
	_log("listening on udp %s:%d" % [bind, port])
	return OK


func stop() -> void:
	if conn != null:
		for peer: ENetPacketPeer in _ids:
			peer.peer_disconnect_now()
		conn.flush()
		conn.destroy()
	conn = null
	_ids.clear()
	_peers.clear()
	_rooms.clear()
	_room_of.clear()


## Handle everything that has arrived. Returns how many events there were.
## (Don't pass service() a timeout to wait for packets: Godot's ENet spins
## the CPU while it waits. run_relay.gd sleeps between empty polls instead.)
func poll() -> int:
	if conn == null:
		return 0
	var n := 0
	var began := Time.get_ticks_usec()
	var ev: Array = conn.service(0)
	while ev[0] != ENetConnection.EVENT_NONE and ev[0] != ENetConnection.EVENT_ERROR:
		n += 1
		var peer: ENetPacketPeer = ev[1]
		match ev[0]:
			ENetConnection.EVENT_CONNECT:
				_ids[peer] = _next_id
				_peers[_next_id] = peer
				_next_id += 1
				metrics.connections_opened += 1
			ENetConnection.EVENT_DISCONNECT:
				if _ids.has(peer):
					var id: int = _ids[peer]
					_leave(id)
					_ids.erase(peer)
					_peers.erase(id)
					metrics.connections_closed += 1
			ENetConnection.EVENT_RECEIVE:
				var flags := peer.get_packet_flags()
				var packet := peer.get_packet()
				if _ids.has(peer) and packet.size() >= 1 and packet.size() <= MAX_PACKET:
					_receive(_ids[peer], packet, ev[3], flags)
				else:
					metrics.ignored_packets += 1
		ev = conn.service(0)
	conn.flush()
	if _bad_joins.size() > 1000:
		_bad_joins.clear()
	var now := Time.get_ticks_usec()
	if n > 0:
		metrics.poll_time.observe((now - began) / 1000000.0)
	if now / 1000 - _sampled >= SAMPLE_MSEC:
		_sampled = now / 1000
		_sample()
	return n


func room_count() -> int:
	return _rooms.size()


func peer_count() -> int:
	return _peers.size()


## Everything the relay counts, as Prometheus text (README.md lists it).
func metrics_text() -> String:
	if conn != null:
		metrics.add_traffic(conn)
	var open := {} # game label -> [rooms, seats, peers]
	for code: String in _rooms:
		var room: Dictionary = _rooms[code]
		var sums: Array = open.get_or_add(room["stats"].name, [0, 0, 0])
		sums[0] += 1
		sums[1] += room["size"] + 1
		sums[2] += room["clients"].size() + 1
	return metrics.render(open, _peers.size(), MAX_ROOMS, MAX_PEERS)


## Note how well every machine in a room is connected, for the round trip and
## packet loss histograms.
func _sample() -> void:
	metrics.add_traffic(conn)
	for code: String in _rooms:
		var room: Dictionary = _rooms[code]
		var stats: Metrics.Game = room["stats"]
		for id: int in [room["host"]] + room["clients"].keys():
			var peer: ENetPacketPeer = _peers.get(id)
			if peer != null:
				stats.rtt.observe(peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME) / 1000.0)
				stats.loss.observe(peer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS) / float(ENetPacketPeer.PACKET_LOSS_SCALE))


func _receive(id: int, p: PackedByteArray, channel: int, flags: int) -> void:
	match p[0]:
		P.HOST:
			if _room_of.has(id) or not _version_ok(id, p):
				return
			var game := _game_id(p, 4)
			if game == "":
				_refuse(id, P.Refusal.BAD_REQUEST, "The relay couldn't read that request to open a room.")
				return
			if _rooms.size() >= MAX_ROOMS:
				_refuse(id, P.Refusal.RELAY_FULL, "The relay is full right now. Try again in a bit.")
				return
			var code := _new_code()
			var size := clampi(p[3], 1, P.MAX_ROOM_CLIENTS)
			var stats := metrics.game(game)
			stats.rooms_opened += 1
			_rooms[code] = {"game": game, "host": id, "size": size, "clients": {}, "stats": stats, "opened": Time.get_ticks_msec(), "peak": 1}
			_room_of[id] = code
			var out := PackedByteArray([P.ROOM, size])
			out.append_array(code.to_ascii_buffer())
			_send(id, out)
			_log("%s room %s opened for %d (%d rooms, %d peers)" % [game, code, size + 1, _rooms.size(), _peers.size()])
		P.JOIN:
			if _room_of.has(id) or not _version_ok(id, p):
				return
			var game := _game_id(p, 3 + P.CODE_LEN)
			if game == "":
				_refuse(id, P.Refusal.BAD_REQUEST, "The relay couldn't read that request to join a room.")
				return
			var addr: String = (_peers[id] as ENetPacketPeer).get_remote_address()
			var minute := Time.get_ticks_msec() / 60000
			var bad: Array = _bad_joins.get(addr, [0, minute])
			if bad[1] != minute:
				bad = [0, minute]
			if bad[0] >= MAX_BAD_JOINS:
				_refuse(id, P.Refusal.TOO_MANY_TRIES, "Too many wrong codes. Wait a minute and try again.")
				return
			var code := P.normalize_code(p.slice(3, 3 + P.CODE_LEN).get_string_from_ascii())
			if not _rooms.has(code) or _rooms[code]["game"] != game:
				_bad_joins[addr] = [bad[0] + 1, minute]
				_refuse(id, P.Refusal.NO_SUCH_ROOM, "No game with the code %s. Check it with the host." % code if code != "" else "That isn't a room code.")
				return
			var room: Dictionary = _rooms[code]
			if room["clients"].size() >= room["size"]:
				_refuse(id, P.Refusal.ROOM_FULL, "That game is full.")
				return
			room["clients"][id] = true
			_room_of[id] = code
			room["stats"].joins += 1
			room["peak"] = maxi(room["peak"], room["clients"].size() + 1)
			_send(id, P.with_id(P.JOINED, id))
			_send(room["host"], P.with_id(P.PEER_IN, id))
		P.DATA:
			if not _room_of.has(id) or p.size() < 5:
				metrics.ignored_packets += 1
				return
			var room: Dictionary = _rooms[_room_of[id]]
			var payload := p.slice(5)
			room["stats"].packets += 1
			room["stats"].bytes += payload.size()
			flags &= ENetPacketPeer.FLAG_RELIABLE | ENetPacketPeer.FLAG_UNSEQUENCED | ENetPacketPeer.FLAG_UNRELIABLE_FRAGMENT
			if room["host"] == id:
				var out := P.with_id(P.DATA, P.HOST_ID)
				out.append_array(payload)
				var to := p.decode_u32(1)
				if to == 0:
					for c: int in room["clients"]:
						_send(c, out, channel, flags)
				elif room["clients"].has(to):
					_send(to, out, channel, flags)
			else:
				var out := P.with_id(P.DATA, id)
				out.append_array(payload)
				_send(room["host"], out, channel, flags)
		_:
			metrics.ignored_packets += 1


## The game id at the end of a HOST or JOIN packet, or "" if there isn't a
## valid one.
func _game_id(p: PackedByteArray, from: int) -> String:
	if p.size() <= from or p.size() > from + P.MAX_GAME_ID:
		return ""
	var game := p.slice(from).get_string_from_ascii()
	return game if P.valid_game_id(game) and game.length() == p.size() - from else ""


func _leave(id: int) -> void:
	if not _room_of.has(id):
		return
	var code: String = _room_of[id]
	_room_of.erase(id)
	var room: Dictionary = _rooms[code]
	if room["host"] == id:
		# No host, no game: send everyone home.
		for c: int in room["clients"]:
			_room_of.erase(c)
			_peers[c].peer_disconnect_later()
		_rooms.erase(code)
		var stats: Metrics.Game = room["stats"]
		stats.rooms_closed += 1
		stats.duration.observe((Time.get_ticks_msec() - room["opened"]) / 1000.0)
		stats.peak.observe(room["peak"])
		_log("%s room %s closed (%d rooms, %d peers)" % [room["game"], code, _rooms.size(), _peers.size() - 1])
	else:
		room["clients"].erase(id)
		_send(room["host"], P.with_id(P.PEER_OUT, id))


func _version_ok(id: int, p: PackedByteArray) -> bool:
	if p.size() < 3:
		return false
	if p.decode_u16(1) != P.VERSION:
		_refuse(id, P.Refusal.OUTDATED, "This game and the relay speak different versions (game %d, relay %d). Update the game." % [p.decode_u16(1), P.VERSION])
		return false
	return true


func _refuse(id: int, why: P.Refusal, reason: String) -> void:
	metrics.refusals[why] += 1
	var out := PackedByteArray([P.ERROR, why])
	out.append_array(reason.to_utf8_buffer())
	_send(id, out)
	_peers[id].peer_disconnect_later()


func _send(id: int, bytes: PackedByteArray, channel: int = 0, flags: int = ENetPacketPeer.FLAG_RELIABLE) -> void:
	var peer: ENetPacketPeer = _peers.get(id)
	if peer != null:
		peer.send(mini(channel, peer.get_channels() - 1), bytes, flags)


func _new_code() -> String:
	while true:
		var c := ""
		for i in P.CODE_LEN:
			c += P.CODE_CHARS[_rng.randi_range(0, P.CODE_CHARS.length() - 1)]
		if not _rooms.has(c):
			return c
	return ""


func _log(text: String) -> void:
	if not quiet:
		print("[%s] %s" % [Time.get_datetime_string_from_system(true), text])
