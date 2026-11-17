# Online play through Drew's relay server (relay/, from drewburr-labs/game-relay).
#
# Godot's multiplayer (all of net_game.gd's @rpc functions) normally runs over
# ENetMultiplayerPeer, which needs the host's address and a forwarded port. This
# is a drop-in MultiplayerPeer that sends the same packets through the relay
# instead: the host opens a room and gets a five-letter code, friends join with
# it, and nobody forwards ports or sees anybody's IP address.
#
# The relay only passes bytes along; it never reads them. The host is still the
# referee, and everything net_game.gd keeps from angels still never leaves the host.
#
# Every payload we send through the relay starts with one byte saying what it is:
#   GAME [GAME, transfer mode, Godot's packet...]
#   PING [PING, msec u32]   PONG [PONG, msec u32]   (our own ping: the relay can't see the other players)
#   BYE  [BYE]              host -> client: you've been kicked, please leave
extends MultiplayerPeerExtension

const RP = preload("res://relay/relay_protocol.gd")
const RelayClient = preload("res://relay/relay_client.gd")

const GAME_ID := "halos-and-horns"   # rooms are per game: a Saucer Showdown code won't work here
const PING_EVERY_MS := 1000
const CHANNELS := 3                  # 0 reliable, 1 unreliable in order, 2 unreliable any order
const MAX_PACKET := 250 * 1024       # the relay drops anything over 256 KB

enum { GAME = 1, PING = 2, PONG = 3, BYE = 4 }

signal room_opened(code: String)

var room_code := ""
var refusal := ""                    # why the relay turned us away, for the menu

var _relay := RelayClient.new()
var _status := CONNECTION_DISCONNECTED
var _server := false
var _clients := {}                   # host: client id -> true
var _kicked := {}                    # host: ids we dropped; their packets are ignored
var _inbox: Array = []               # [from, bytes, mode, channel]
var _target := 0
var _mode := TRANSFER_MODE_RELIABLE
var _channel := 0
var _refusing := false
var _rtt := {}                       # peer id -> msec
var _last_ping := 0


func host(address: String, port: int, clients: int) -> Error:
	_server = true
	var err := _relay.host(address, port, GAME_ID, clients, CHANNELS)
	if err == OK:
		_status = CONNECTION_CONNECTING
	return err


func join(address: String, port: int, code: String) -> Error:
	var err := _relay.join(address, port, GAME_ID, code, CHANNELS)
	if err == OK:
		_status = CONNECTION_CONNECTING
	return err


# Round trip to another player in msec (through the relay), or -1 if not known yet.
func ping_to(id: int) -> int:
	return _rtt.get(id, -1)


# ---------- MultiplayerPeer ----------

func _poll() -> void:
	if _status == CONNECTION_DISCONNECTED:
		return
	for ev: Array in _relay.poll():
		match ev[0]:
			"room":
				room_code = ev[1]
				room_opened.emit(room_code)
			"joined":
				_status = CONNECTION_CONNECTED
				if not _server:
					peer_connected.emit(1)
			"peer_in":
				if _clients.has(ev[1]):
					pass   # (never announce a player twice: Godot would forget what it knew about them)
				elif _refusing:
					_send_raw(ev[1], PackedByteArray([BYE]), 0)
					_kicked[ev[1]] = true
				else:
					_clients[ev[1]] = true
					peer_connected.emit(ev[1])
			"peer_out":
				_kicked.erase(ev[1])
				_rtt.erase(ev[1])
				if _clients.erase(ev[1]):
					peer_disconnected.emit(ev[1])
			"data":
				_receive(ev[1], ev[2], ev[3])
			"refused":
				refusal = _refusal_text(ev[1], ev[2])
				_shut_down()
			"failed", "closed":
				_shut_down()
	if _status == CONNECTION_CONNECTED and Time.get_ticks_msec() - _last_ping >= PING_EVERY_MS:
		_last_ping = Time.get_ticks_msec()
		var p := PackedByteArray([PING, 0, 0, 0, 0])
		p.encode_u32(1, _last_ping)
		for id in (_clients.keys() if _server else [1]):
			_send_raw(id, p, 1, 0)
	_relay.flush()


func _receive(from: int, bytes: PackedByteArray, channel: int) -> void:
	if bytes.is_empty() or _kicked.has(from):
		return
	if _server and not _clients.has(from):
		return
	match bytes[0]:
		GAME:
			if bytes.size() >= 2 and _status == CONNECTION_CONNECTED:
				_inbox.append([from, bytes.slice(2), bytes[1], channel])
		PING:
			if bytes.size() == 5:
				bytes[0] = PONG
				_send_raw(from, bytes, 1, 0)
		PONG:
			if bytes.size() == 5:
				_rtt[from] = (Time.get_ticks_msec() & 0xFFFFFFFF) - bytes.decode_u32(1)
		BYE:
			if not _server:
				refusal = "The host removed you from the game."
				_shut_down()


func _get_available_packet_count() -> int:
	return _inbox.size()


# Godot asks who sent the NEXT packet (and how) before it reads it, so these
# look at the front of the queue, and only _get_packet_script takes it off.
func _get_packet_script() -> PackedByteArray:
	return _inbox.pop_front()[1]


func _get_packet_peer() -> int:
	return _inbox[0][0] if not _inbox.is_empty() else 0


func _get_packet_mode() -> TransferMode:
	return _inbox[0][2] if not _inbox.is_empty() else TRANSFER_MODE_RELIABLE


func _get_packet_channel() -> int:
	return 0   # we don't use Godot's custom channels


func _put_packet_script(buffer: PackedByteArray) -> Error:
	if _status != CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	if buffer.size() > MAX_PACKET:
		push_error("relay: a %d-byte packet is too big for the relay (limit %d)" % [buffer.size(), MAX_PACKET])
		return ERR_OUT_OF_MEMORY
	var p := PackedByteArray([GAME, _mode])
	p.append_array(buffer)
	var ch := 0
	var flags := ENetPacketPeer.FLAG_RELIABLE
	if _mode == TRANSFER_MODE_UNRELIABLE_ORDERED:
		ch = 1
		flags = 0
	elif _mode == TRANSFER_MODE_UNRELIABLE:
		ch = 2
		flags = ENetPacketPeer.FLAG_UNSEQUENCED
	if not _server:
		_send_raw(1, p, ch, flags)
	elif _target == 0:
		for id in _clients:
			_send_raw(id, p, ch, flags)
	elif _target > 0:
		if _clients.has(_target):
			_send_raw(_target, p, ch, flags)
	else:
		for id in _clients:
			if id != -_target:
				_send_raw(id, p, ch, flags)
	return OK


# The host always names one player. (The relay's own "to everyone" would also
# reach kicked players and anyone the relay let in before we heard about them.)
func _send_raw(to: int, p: PackedByteArray, channel: int, flags: int = ENetPacketPeer.FLAG_RELIABLE) -> void:
	_relay.send(to, p, channel, flags)


func _get_max_packet_size() -> int:
	return MAX_PACKET


func _set_transfer_mode(mode: TransferMode) -> void:
	_mode = mode


func _get_transfer_mode() -> TransferMode:
	return _mode


func _set_transfer_channel(channel: int) -> void:
	_channel = channel


func _get_transfer_channel() -> int:
	return _channel


func _set_target_peer(peer: int) -> void:
	_target = peer


func _is_server() -> bool:
	return _server


func _get_unique_id() -> int:
	return 1 if _server else maxi(_relay.my_id, 0)


func _get_connection_status() -> ConnectionStatus:
	return _status


func _is_server_relay_supported() -> bool:
	return true   # clients only ever talk to the host, which passes things on


func _set_refuse_new_connections(enable: bool) -> void:
	_refusing = enable


func _is_refusing_new_connections() -> bool:
	return _refusing


# The relay can't throw someone out of a room, so the host forgets them, ignores
# anything else they send, and asks their game to leave (an honest game does).
func _disconnect_peer(peer: int, _force: bool) -> void:
	if not _server or not _clients.has(peer):
		return
	_send_raw(peer, PackedByteArray([BYE]), 0)
	_clients.erase(peer)
	_kicked[peer] = true
	_rtt.erase(peer)
	peer_disconnected.emit(peer)


func _close() -> void:
	_relay.close()
	_shut_down()


func _shut_down() -> void:
	if _status == CONNECTION_DISCONNECTED:
		return
	_relay.close()
	_status = CONNECTION_DISCONNECTED
	_inbox.clear()
	for id in _clients:
		peer_disconnected.emit(id)
	_clients.clear()


func _refusal_text(why: int, text: String) -> String:
	match why:
		RP.Refusal.OUTDATED:
			return "This version of the game can't use the relay server. Update the game."
		RP.Refusal.NO_SUCH_ROOM:
			return "No game with that room code. Check the code with the host."
		RP.Refusal.ROOM_FULL:
			return "That game is full."
		RP.Refusal.RELAY_FULL:
			return "The relay server is full right now. Try again in a bit."
		RP.Refusal.TOO_MANY_TRIES:
			return "Too many wrong room codes. Wait a minute and try again."
	return text if text != "" else "The relay server turned us away."
