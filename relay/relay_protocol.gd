extends RefCounted
## Wire format between games and the relay server. The relay, relay_client.gd
## and any Godot game using the relay all load this file, so it must not
## depend on anything else. Any game can use the relay: rooms belong to a
## game id, and the relay never looks inside a game's packets.
##
## The relay speaks ENet over UDP. Every packet starts with a type byte;
## numbers are little-endian. Send the control messages (HOST, JOIN) reliably
## on channel 0; the relay sends its own on channel 0, reliably.
##
##   game -> relay   HOST   [HOST, version u16, clients u8, game id]          open a room
##                   JOIN   [JOIN, version u16, code (5 ASCII), game id]      join one
##                   DATA   [DATA, to u32, payload]   host: to a client id, 0 = every client
##                                                    client: to the host (to is ignored)
##   relay -> game   ROOM   [ROOM, clients u8, code (5 ASCII)]               your room is open
##                   JOINED [JOINED, your id u32]                            you're in
##                   ERROR  [ERROR, Refusal u8, UTF-8 reason]   then the relay hangs up
##                   PEER_IN / PEER_OUT [type, id u32]          host: a client came or went
##                   DATA   [DATA, from u32, payload]           from is 1 for the host
##
## - clients: how many clients the room takes besides the host, 1 to
##   MAX_ROOM_CLIENTS (anything else is clamped). ROOM says what you got.
## - game id: 1 to MAX_GAME_ID printable ASCII bytes, say "saucer-showdown".
##   A code only works with the game id its room was opened with.
## - DATA goes out on the channel it came in on (up to MAX_CHANNELS, or the
##   receiver's last channel if it has fewer) and with the same reliability:
##   reliable, unreliable, or unsequenced.
## - Client ids are 2 and up, unique on the relay for as long as it runs.
##
## The payloads are the game's own business; the relay passes them through.

const HOST_NAME := "saucer.drewburr.com"
const PORT := 24680
const VERSION := 2
const CODE_CHARS := "ABCDEFGHJKMNPQRSTUVWXYZ23456789" # no I, L, O, 0 or 1
const CODE_LEN := 5
const MAX_ROOM_CLIENTS := 31 # per room, besides the host
const MAX_GAME_ID := 32
const MAX_CHANNELS := 8
const HOST_ID := 1

enum { HOST = 1, JOIN = 2, DATA = 3, ROOM = 10, JOINED = 11, ERROR = 12, PEER_IN = 13, PEER_OUT = 14 }

## Why the relay turned a game away (the byte after ERROR).
enum Refusal { BAD_REQUEST = 1, OUTDATED = 2, RELAY_FULL = 3, NO_SUCH_ROOM = 4, ROOM_FULL = 5, TOO_MANY_TRIES = 6 }


static func with_id(type: int, id: int) -> PackedByteArray:
	var p := PackedByteArray()
	p.resize(5)
	p[0] = type
	p.encode_u32(1, id)
	return p


static func with_version(type: int) -> PackedByteArray:
	var p := PackedByteArray()
	p.resize(3)
	p[0] = type
	p.encode_u16(1, VERSION)
	return p


static func host_request(game_id: String, clients: int) -> PackedByteArray:
	var p := with_version(HOST)
	p.append(clampi(clients, 1, MAX_ROOM_CLIENTS))
	p.append_array(game_id.to_ascii_buffer())
	return p


static func join_request(game_id: String, code: String) -> PackedByteArray:
	var p := with_version(JOIN)
	p.append_array(code.to_ascii_buffer())
	p.append_array(game_id.to_ascii_buffer())
	return p


## True if the relay will take this as a game id.
static func valid_game_id(game_id: String) -> bool:
	if game_id.length() < 1 or game_id.length() > MAX_GAME_ID:
		return false
	for i in game_id.length():
		var c := game_id.unicode_at(i)
		if c < 0x21 or c > 0x7e:
			return false
	return true


## "kx4pz " -> "KX4PZ", or "" if it can't be a room code.
static func normalize_code(text: String) -> String:
	var c := text.strip_edges().to_upper()
	if c.length() != CODE_LEN:
		return ""
	for ch in c:
		if not CODE_CHARS.contains(ch):
			return ""
	return c
