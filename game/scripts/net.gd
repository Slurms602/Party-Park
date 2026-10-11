extends Node
## Lobby and connection (autoload "Net").
## The host owns all physics. Clients only send input and draw the snapshots they receive.
## Online play goes through the room-code relay (RelayPeer), so nobody has to port forward. Super Battle Golf gets
## the same thing from Steam's relay. "Host on this network" / direct IP use ENet, and LAN beacons make nearby
## games show up in the join screen by themselves.

signal players_changed
signal match_started(seconds: float)
signal match_ended
signal status(text: String)
signal room_ready(code: String)
signal lan_games_changed

const PORT := 7777
const BEACON_PORT := 7778
const DEFAULT_RELAY := "wss://bowling-your-friends-relay.onrender.com"  # see render.yaml; override in Settings
const MAX_PLAYERS := 8
const COLORS := [Color("ff4d6d"), Color("4dabff"), Color("ffd23f"), Color("3ddc97"),
	Color("b980ff"), Color("ff8c42"), Color("ff7eb6"), Color("5ef2f2")]
const BOT_NAMES := ["Gutterball", "Split", "Turkey", "Lefty", "Big Lebowski", "Pinhead", "Sparetire", "Strikeout"]

var players := {}  # peer id (bots < 0) -> {name, color, bot, skin}
var in_match := false
var match_seconds := 180.0
var _next_bot := -1
var room_code := ""  # online room code (host and clients)
var lan_games := {}  # ip -> beacon info {name, n, code, port, seen}
var _beacon := PacketPeerUDP.new()
var _beacon_t := 0.0
var _listen: PacketPeerUDP


func _ready() -> void:
	multiplayer.peer_connected.connect(func(_id): pass)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func(): _register.rpc_id(1, Prefs.player_name, Prefs.skin))
	multiplayer.connection_failed.connect(func(): leave(); status.emit("Could not connect."))
	multiplayer.server_disconnected.connect(func(): leave(); status.emit("The host left."))
	_wake_relay.call_deferred()


func relay_url() -> String:
	return Prefs.relay.strip_edges() if Prefs.relay.strip_edges() != "" else DEFAULT_RELAY


func host_online() -> void:
	## Opens a room on the relay. room_ready(code) fires when it's up; status(msg) fires if it fails.
	leave()
	var peer := RelayPeer.new()
	peer.hosted.connect(func(c):
		room_code = c
		players = {1: _entry(Prefs.player_name, false, Prefs.skin)}
		print("ROOM CODE ", c)
		players_changed.emit()
		room_ready.emit(c))
	peer.failed.connect(_on_relay_failed, CONNECT_DEFERRED)
	var err := peer.host(relay_url())
	if err != OK:
		status.emit("Couldn't start online hosting (%s)." % error_string(err))
		return
	multiplayer.multiplayer_peer = peer


func join_code(code: String) -> void:
	leave()
	var peer := RelayPeer.new()
	peer.failed.connect(_on_relay_failed, CONNECT_DEFERRED)
	var err := peer.join(relay_url(), code)
	if err != OK:
		status.emit("Couldn't connect (%s)." % error_string(err))
		return
	room_code = peer.code
	multiplayer.multiplayer_peer = peer


func _on_relay_failed(message: String) -> void:
	leave()
	status.emit(message)


func _wake_relay() -> void:
	# Free hosting plans put the relay to sleep when idle; poke it as soon as the game opens so it's awake by the
	# time someone presses HOST.
	var http := HTTPRequest.new()
	http.timeout = 90.0
	add_child(http)
	http.request_completed.connect(func(_r, _c, _h, _b): http.queue_free())
	if http.request(relay_url().replace("wss://", "https://").replace("ws://", "http://")) != OK:
		http.queue_free()


func host_lan() -> String:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS)
	if err != OK:
		return "Could not host on port %d (%s)." % [PORT, error_string(err)]
	multiplayer.multiplayer_peer = peer
	players = {1: _entry(Prefs.player_name, false, Prefs.skin)}
	players_changed.emit()
	return ""


func join_ip(ip: String) -> String:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip.strip_edges(), PORT)
	if err != OK:
		return "Could not connect to %s (%s)." % [ip, error_string(err)]
	multiplayer.multiplayer_peer = peer
	return ""


func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()
	room_code = ""
	if in_match:
		in_match = false
		match_ended.emit()
	players_changed.emit()


# ---------------------------------------------------------------- LAN discovery

func start_discovery() -> void:
	if _listen == null:
		_listen = PacketPeerUDP.new()
		if _listen.bind(BEACON_PORT) != OK:  # another copy of the game on this PC already listens
			_listen = null


func stop_discovery() -> void:
	if _listen:
		_listen.close()
		_listen = null
	lan_games.clear()


func _process(dt: float) -> void:
	if is_host():  # tell the local network about this game once a second
		_beacon_t -= dt
		if _beacon_t <= 0.0:
			_beacon_t = 1.0
			var info := {g = "byf", v = RelayPeer.PROTOCOL, name = players[1].name if players.has(1) else "?",
				n = players.size(), code = room_code, port = PORT}
			_beacon.set_broadcast_enabled(true)
			_beacon.set_dest_address("255.255.255.255", BEACON_PORT)
			_beacon.put_packet(JSON.stringify(info).to_utf8_buffer())
	if _listen == null:
		return
	var changed := false
	while _listen.get_available_packet_count() > 0:
		var data = JSON.parse_string(_listen.get_packet().get_string_from_utf8())
		var ip := _listen.get_packet_ip()
		if data is Dictionary and data.get("g") == "byf" and data.get("v") == RelayPeer.PROTOCOL:
			changed = changed or not lan_games.has(ip) or lan_games[ip].n != data.n
			data.seen = Time.get_ticks_msec()
			lan_games[ip] = data
	for ip in lan_games.keys():
		if Time.get_ticks_msec() - lan_games[ip].seen > 3500:
			lan_games.erase(ip)
			changed = true
	if changed:
		lan_games_changed.emit()


func is_online() -> bool:
	var p := multiplayer.multiplayer_peer
	# Godot's default OfflineMultiplayerPeer reports itself as connected, so rule it out explicitly.
	return p != null and not p is OfflineMultiplayerPeer and p.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func is_host() -> bool:
	return is_online() and multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1


func add_bot() -> void:
	if not is_host() or players.size() >= MAX_PLAYERS:
		return
	var i := -_next_bot - 1
	players[_next_bot] = _entry(BOT_NAMES[i % BOT_NAMES.size()], true, Skins.PRESETS.values()[(i + 1) % Skins.PRESETS.size()])
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


func update_me() -> void:
	## Push a changed name or skin from Prefs to everyone.
	if is_host():
		_update(Prefs.player_name, Prefs.skin)
	elif is_online():
		_update.rpc_id(1, Prefs.player_name, Prefs.skin)


func _entry(n: String, bot: bool, skin = {}) -> Dictionary:
	var used := players.values().map(func(p): return p.color)
	var color: Color = COLORS[0]
	for c in COLORS:
		if not used.has(c):
			color = c
			break
	return {name = _clean(n), color = color, bot = bot, skin = Skins.sanitize(skin)}


func _clean(n: String) -> String:
	n = n.strip_edges().left(16)
	return n if n != "" else "Bowler"


@rpc("any_peer", "reliable")
func _update(player_name: String, skin: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	id = 1 if id == 0 else id
	if players.has(id):
		players[id].name = _clean(player_name)
		players[id].skin = Skins.sanitize(skin)
		_sync_players.rpc(players)


@rpc("any_peer", "reliable")
func _register(player_name: String, skin: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if players.size() >= MAX_PLAYERS:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	players[id] = _entry(player_name, false, skin)
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
