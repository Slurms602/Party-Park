extends Node
## Lobby and connection (autoload "Net").
## The host owns all physics. Clients only send input and draw the snapshots they receive.

signal players_changed
signal match_started(seconds: float)
signal match_ended
signal status(text: String)

const PORT := 7777
const MAX_PLAYERS := 8
const COLORS := [Color("ff4d6d"), Color("4dabff"), Color("ffd23f"), Color("3ddc97"),
	Color("b980ff"), Color("ff8c42"), Color("ff7eb6"), Color("5ef2f2")]
const BOT_NAMES := ["Gutterball", "Split", "Turkey", "Lefty", "Big Lebowski", "Pinhead", "Sparetire", "Strikeout"]

var players := {}  # peer id (bots < 0) -> {name, color, bot}
var my_name := "Bowler"
var in_match := false
var match_seconds := 180.0
var _next_bot := -1


func _ready() -> void:
	multiplayer.peer_connected.connect(func(_id): pass)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func(): _register.rpc_id(1, my_name))
	multiplayer.connection_failed.connect(func(): leave(); status.emit("Could not connect."))
	multiplayer.server_disconnected.connect(func(): leave(); status.emit("The host left."))


func host(player_name: String) -> String:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		return "Could not host on port %d (%s)." % [PORT, error_string(err)]
	multiplayer.multiplayer_peer = peer
	my_name = _clean(player_name)
	players = {1: _entry(my_name, false)}
	players_changed.emit()
	return ""


func join(player_name: String, ip: String) -> String:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip.strip_edges(), PORT)
	if err != OK:
		return "Could not connect to %s (%s)." % [ip, error_string(err)]
	multiplayer.multiplayer_peer = peer
	my_name = _clean(player_name)
	return ""


func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()
	if in_match:
		in_match = false
		match_ended.emit()
	players_changed.emit()


func is_online() -> bool:
	return multiplayer.multiplayer_peer != null and \
		multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func is_host() -> bool:
	return is_online() and multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1


func add_bot() -> void:
	if not is_host() or players.size() >= MAX_PLAYERS:
		return
	players[_next_bot] = _entry(BOT_NAMES[(-_next_bot - 1) % BOT_NAMES.size()], true)
	_next_bot -= 1
	_sync_players.rpc(players)


func remove_bot() -> void:
	var bots := players.keys().filter(func(id): return players[id].bot)
	if is_host() and not bots.is_empty():
		players.erase(bots.min())
		_sync_players.rpc(players)


func start_match(seconds: float) -> void:
	if is_host():
		_start.rpc(seconds)


func end_match() -> void:
	if is_host():
		_end.rpc()


func _entry(n: String, bot: bool) -> Dictionary:
	var used := players.values().map(func(p): return p.color)
	var color: Color = COLORS[0]
	for c in COLORS:
		if not used.has(c):
			color = c
			break
	return {name = n, color = color, bot = bot}


func _clean(n: String) -> String:
	n = n.strip_edges().left(16)
	return n if n != "" else "Bowler"


@rpc("any_peer", "reliable")
func _register(player_name: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if players.size() >= MAX_PLAYERS:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	players[id] = _entry(_clean(player_name), false)
	_sync_players.rpc(players)
	if in_match:  # drop-in: late joiners spawn straight into the running match
		_start.rpc_id(id, match_seconds)


func _on_peer_disconnected(id: int) -> void:
	if is_host() and players.has(id):
		players.erase(id)
		_sync_players.rpc(players)


@rpc("authority", "call_local", "reliable")
func _sync_players(p: Dictionary) -> void:
	players = p
	players_changed.emit()


@rpc("authority", "call_local", "reliable")
func _start(seconds: float) -> void:
	match_seconds = seconds
	in_match = true
	match_started.emit(seconds)


@rpc("authority", "call_local", "reliable")
func _end() -> void:
	in_match = false
	match_ended.emit()
