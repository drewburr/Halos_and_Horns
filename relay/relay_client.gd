extends RefCounted
## A Godot game's side of the relay. Copy this file and relay_protocol.gd into
## your game (keep them side by side) and you can host and join rooms by code.
##
##   var relay := RelayClient.new()
##   relay.host(P.HOST_NAME, P.PORT, "my-game", 3)     # or join(..., "my-game", code)
##   # every frame:
##   for ev in relay.poll():
##       match ev[0]:
##           "room": print("tell your friends: ", ev[1])   # host only
##           "joined": print("in, my id is ", ev[1])       # host gets 1
##           "peer_in", "peer_out": pass                   # host: ev[1] is the client id
##           "data": handle(ev[1], ev[2], ev[3])            # from id, bytes, channel
##           "refused": print(ev[2])                        # ev[1] is a P.Refusal
##           "failed", "closed": pass                      # couldn't connect / connection lost
##   relay.send(P.HOST_ID, bytes)    # client -> host; host: a client id, or 0 for every client
##
## Events arrive in order. After "refused", "failed" or "closed" the client is
## closed and poll() returns nothing more. It doesn't use Godot's high-level
## multiplayer (RPCs, MultiplayerSynchronizer); you send bytes yourself.

const P = preload("relay_protocol.gd")
const CONNECT_TIMEOUT_MS := 8000

var is_host := false
var my_id := 0 # 1 for the host, once "joined" has arrived
var room_code := ""
var room_clients := 0 # how many clients the room takes (host)
var channels := 1

var _conn: ENetConnection
var _server: ENetPacketPeer
var _hello := PackedByteArray()
var _linked := false
var _closed := false
var _started_ms := 0
var _events: Array = []


## Open a room for up to `clients` players besides you. "room" brings its code.
func host(address: String, port: int, game_id: String, clients: int, channel_count: int = 1) -> Error:
	if not P.valid_game_id(game_id):
		return ERR_INVALID_PARAMETER
	is_host = true
	_hello = P.host_request(game_id, clients)
	return _connect(address, port, channel_count)


## Join the room with this code (any case, stray spaces are fine).
func join(address: String, port: int, game_id: String, code: String, channel_count: int = 1) -> Error:
	if not P.valid_game_id(game_id):
		return ERR_INVALID_PARAMETER
	var c := P.normalize_code(code)
	if c == "":
		return ERR_INVALID_PARAMETER
	room_code = c
	_hello = P.join_request(game_id, c)
	return _connect(address, port, channel_count)


func _connect(address: String, port: int, channel_count: int) -> Error:
	channels = clampi(channel_count, 1, P.MAX_CHANNELS)
	_conn = ENetConnection.new()
	var err := _conn.create_host(1, channels)
	if err != OK:
		_conn = null
		return err
	_server = _conn.connect_to_host(address, port, channels)
	if _server == null:
		_conn.destroy()
		_conn = null
		return ERR_CANT_CONNECT
	_started_ms = Time.get_ticks_msec()
	return OK


## True once the relay has put us in a room.
func is_linked() -> bool:
	return _linked and not _closed


## Everything that has happened since the last poll (see the top of the file).
func poll() -> Array:
	if _conn == null or _closed:
		return []
	var ev: Array = _conn.service(0)
	while ev[0] != ENetConnection.EVENT_NONE and not _closed:
		match ev[0]:
			ENetConnection.EVENT_CONNECT:
				_server.send(0, _hello, ENetPacketPeer.FLAG_RELIABLE)
			ENetConnection.EVENT_RECEIVE:
				_receive(_server.get_packet(), ev[3])
			ENetConnection.EVENT_DISCONNECT, ENetConnection.EVENT_ERROR:
				_end("closed" if _linked else "failed")
		if not _closed:
			ev = _conn.service(0)
	if not _closed and not _linked and Time.get_ticks_msec() - _started_ms > CONNECT_TIMEOUT_MS:
		_end("failed")
	var out := _events
	_events = []
	return out


func _receive(p: PackedByteArray, channel: int) -> void:
	if p.is_empty():
		return
	match p[0]:
		P.ROOM:
			if is_host and p.size() == 2 + P.CODE_LEN:
				room_clients = p[1]
				room_code = p.slice(2).get_string_from_ascii()
				my_id = P.HOST_ID
				_linked = true
				_events.append(["room", room_code])
				_events.append(["joined", my_id])
		P.JOINED:
			if not is_host and p.size() == 5:
				my_id = p.decode_u32(1)
				_linked = true
				_events.append(["joined", my_id])
		P.ERROR:
			var why: int = p[1] if p.size() > 1 else P.Refusal.BAD_REQUEST
			_events.append(["refused", why, p.slice(2).get_string_from_utf8()])
			close()
		P.PEER_IN, P.PEER_OUT:
			if is_host and p.size() == 5:
				_events.append(["peer_in" if p[0] == P.PEER_IN else "peer_out", p.decode_u32(1)])
		P.DATA:
			if p.size() >= 5:
				_events.append(["data", p.decode_u32(1), p.slice(5), channel])


func _end(event: String) -> void:
	_events.append([event])
	close()


## Send bytes through the relay. Host: `to` is a client id, or 0 for every
## client. Client: it always goes to the host. `flags` are ENetPacketPeer's:
## FLAG_RELIABLE, 0 (unreliable, in order) or FLAG_UNSEQUENCED.
func send(to: int, payload: PackedByteArray, channel: int = 0, flags: int = ENetPacketPeer.FLAG_RELIABLE) -> void:
	if not is_linked():
		return
	var p := P.with_id(P.DATA, to)
	p.append_array(payload)
	_server.send(clampi(channel, 0, channels - 1), p, flags)


## Push queued packets out now rather than at the next poll().
func flush() -> void:
	if _conn != null and not _closed:
		_conn.flush()


## Round trip to the relay in msec (not to the other players: the relay
## doesn't see your game's packets, so measure that yourself), or -1.
func relay_ping() -> int:
	if _server == null or _closed:
		return -1
	return int(_server.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))


## Leave. A host leaving closes its room and sends everyone in it home.
func close() -> void:
	if _conn != null:
		if _server != null and _server.is_active():
			_server.peer_disconnect_now() # tell the relay at once, so the room closes
		_conn.flush()
		_conn.destroy()
	_conn = null
	_server = null
	_closed = true
