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
signal direct_info_changed  # public IP / router port status found while hosting by IP
signal party_changed

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
var map := "classic"  # Arena.MAPS id the host picked (in a party: the minigame being played)
var party := {}  # party mode state, host-authoritative (see Party); empty when playing single matches
var party_mine := {}  # this player's totals across a party's minigames, banked as one match at the end
var _next_bot := -1
var room_code := ""  # online room code (host and clients)
var lan_games := {}  # ip -> beacon info {name, n, code, port, seen}
var _beacon := PacketPeerUDP.new()
var _beacon_t := 0.0
var _listen: PacketPeerUDP
var public_ip := ""  # what friends type when hosting by IP
var shared_ip := false  # the router's outside address isn't the real internet IP (ISP CGNAT / double NAT)
var _router_ip := ""
var _web_ip := ""
var port_open := 0  # 1 = the router opened the port for us (UPnP), -1 = it didn't, 0 = still checking
var _upnp: UPNP
var _upnp_thread: Thread


func _ready() -> void:
	multiplayer.peer_connected.connect(func(_id): pass)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func(): _register.rpc_id(1, Prefs.player_name, Prefs.skin))
	multiplayer.connection_failed.connect(func():
		if multiplayer.multiplayer_peer is RelayPeer:
			return  # RelayPeer reports its own, more specific error
		leave()
		status.emit("Couldn't connect to that IP. Double-check it with your host (they may need to forward port %d)." % PORT))
	multiplayer.server_disconnected.connect(func():
		if multiplayer.multiplayer_peer is RelayPeer:
			return
		leave()
		status.emit("The host left."))
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
	peer.failed.connect(_on_relay_failed.bind(peer), CONNECT_DEFERRED)
	var err := peer.host(relay_url())
	if err != OK:
		status.emit("Couldn't start online hosting (%s)." % error_string(err))
		return
	multiplayer.multiplayer_peer = peer


func join_code(code: String) -> void:
	leave()
	var peer := RelayPeer.new()
	peer.failed.connect(_on_relay_failed.bind(peer), CONNECT_DEFERRED)
	var err := peer.join(relay_url(), code)
	if err != OK:
		status.emit("Couldn't connect (%s)." % error_string(err))
		return
	room_code = peer.code
	multiplayer.multiplayer_peer = peer


func _on_relay_failed(message: String, peer: RelayPeer) -> void:
	if multiplayer.multiplayer_peer != peer:
		return  # we've already moved on (e.g. hosting by IP instead)
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
	_open_port()
	return ""


func join_ip(address: String) -> String:
	address = address.strip_edges()
	var host := address
	var port := PORT
	if address.count(":") == 1:  # "1.2.3.4:7777"
		host = address.get_slice(":", 0)
		port = int(address.get_slice(":", 1))
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(host, port)
	if err != OK:
		return "Couldn't connect to %s (%s)." % [address, error_string(err)]
	multiplayer.multiplayer_peer = peer
	return ""


# ---------------------------------------------------------------- hosting by IP: open the router port, find the public IP

func _open_port() -> void:
	public_ip = ""
	port_open = 0
	shared_ip = false
	_router_ip = ""
	_web_ip = ""
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_work)  # router discovery blocks for ~2 s, so keep it off the main thread
	var http := HTTPRequest.new()  # fallback in case the router doesn't speak UPnP
	http.timeout = 10.0
	add_child(http)
	http.request_completed.connect(func(_r, code, _h, body):
		var ip: String = body.get_string_from_utf8().strip_edges()
		if code == 200 and ip.is_valid_ip_address():
			_web_ip = ip
			public_ip = ip
			_check_shared()
			direct_info_changed.emit()
		http.queue_free())
	if http.request("https://api.ipify.org") != OK:
		http.queue_free()


func _upnp_work() -> void:
	var u := UPNP.new()
	var ok := false
	var ip := ""
	if u.discover(2000, 2, "InternetGatewayDevice") == UPNP.UPNP_RESULT_SUCCESS and u.get_gateway() and u.get_gateway().is_valid_gateway():
		ok = u.add_port_mapping(PORT, PORT, "Bowling your Friends", "UDP", 0) == UPNP.UPNP_RESULT_SUCCESS
		ip = u.query_external_address()
	_upnp_done.call_deferred(u if ok else null, ip)


func _upnp_done(u: UPNP, ip: String) -> void:
	_upnp_thread.wait_to_finish()
	_upnp_thread = null
	if not is_host() or room_code != "":  # left (or went online) while the router was answering
		if u:
			u.delete_port_mapping(PORT, "UDP")
		return
	_upnp = u
	port_open = 1 if u else -1
	_router_ip = ip
	if ip.is_valid_ip_address() and not _is_private(ip) and public_ip == "":
		public_ip = ip
	_check_shared()
	direct_info_changed.emit()


func _check_shared() -> void:
	# If the router's own outside address differs from what the internet sees, there's another NAT in front of
	# it (common with mobile/fibre ISPs): the opened port never reaches this PC from outside.
	shared_ip = _router_ip.is_valid_ip_address() and _web_ip != "" and _router_ip != _web_ip


func _close_port() -> void:
	if _upnp:
		_upnp.delete_port_mapping(PORT, "UDP")
		_upnp = null


static func _is_private(ip: String) -> bool:
	var p := ip.split(".")
	if p.size() != 4:
		return false
	var a := int(p[0])
	var b := int(p[1])
	return a == 10 or a == 127 or (a == 192 and b == 168) or (a == 172 and b >= 16 and b < 32) or (a == 100 and b >= 64 and b < 128)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		_close_port()


func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()
	room_code = ""
	public_ip = ""
	port_open = 0
	_close_port()
	if in_match:
		in_match = false
		match_ended.emit()
	if in_party():
		party = {}
		party_changed.emit()
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
		_start.rpc(seconds, map)


func end_match() -> void:
	if is_host():
		_end.rpc()


# ---------------------------------------------------------------- party mode

func in_party() -> bool:
	return not party.is_empty()


func start_party(rounds: int) -> void:
	if is_host():
		_party.rpc(Party.new_state(players.keys(), rounds))


func push_party() -> void:
	## Host: everyone gets the new board state.
	if is_host():
		_party.rpc(party)


func end_party() -> void:
	if is_host():
		_party.rpc({})


func party_roll() -> void:
	## This player taps Roll.
	if is_host():
		party_roll_for(my_id())
	elif is_online():
		_roll_request.rpc_id(1)


func party_roll_for(pid: int) -> void:
	if is_host() and Party.roll(party, pid) > 0:
		push_party()


func party_minigame_done(points: Dictionary) -> void:
	if is_host():
		Party.award(party, points)
		push_party()


func add_party_stats(row: Dictionary, feats: Dictionary) -> void:
	## Sum this player's minigame results so the whole party banks as one match (Progress).
	var m := party_mine
	for k in ["total", "kos", "strikes", "spares"]:
		m[k] = m.get(k, 0) + row.get(k, 0)
	m.rolls = m.get("rolls", []) + row.get("rolls", [])
	var f: Dictionary = m.get("feats", {pins = 0})
	for k in feats:
		f[k] = f.get(k, 0) + feats[k] if k == "pins" else (f.get(k, false) or feats[k])
	m.feats = f


@rpc("any_peer", "reliable")
func _roll_request() -> void:
	party_roll_for(multiplayer.get_remote_sender_id())


@rpc("authority", "call_local", "reliable")
func _party(state: Dictionary) -> void:
	if not state.is_empty() and party.is_empty():
		party_mine = {}  # a new party
	party = state
	party_changed.emit()


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
	if in_party():  # drop-in: late joiners start on the start space
		Party.add_player(party, id)
		push_party()
	if in_match:  # drop-in: late joiners spawn straight into the running match
		_start.rpc_id(id, match_seconds, map)


func _on_peer_disconnected(id: int) -> void:
	if is_host() and players.has(id):
		players.erase(id)
		_sync_players.rpc(players)


@rpc("authority", "call_local", "reliable")
func _sync_players(p: Dictionary) -> void:
	players = p
	players_changed.emit()


@rpc("authority", "call_local", "reliable")
func _start(seconds: float, map_id: String) -> void:
	match_seconds = seconds
	map = map_id if Arena.MAPS.has(map_id) else "classic"
	in_match = true
	match_started.emit(seconds)


@rpc("authority", "call_local", "reliable")
func _end() -> void:
	in_match = false
	match_ended.emit()
