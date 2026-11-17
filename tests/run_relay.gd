extends SceneTree
# Runs a relay server on this computer, for tests:
#   godot --headless -s res://tests/run_relay.gd -- --port=24699 --quit-after=300
# The real one runs from drewburr-labs/game-relay; this is the same relay_server.gd.

const RelayServer = preload("res://relay/relay_server.gd")

var relay := RelayServer.new()
var quit_at := 0


func _initialize() -> void:
	var port := 24680
	var seconds := 600
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--port="):
			port = int(a.trim_prefix("--port="))
		elif a.begins_with("--quit-after="):
			seconds = int(a.trim_prefix("--quit-after="))
	quit_at = Time.get_ticks_msec() + seconds * 1000
	if relay.start(port, "127.0.0.1") != OK:
		print("relay: couldn't listen on port %d" % port)
		quit(1)


func _process(_delta: float) -> bool:
	relay.poll()
	if Time.get_ticks_msec() > quit_at:
		relay.stop()
		return true
	return false
