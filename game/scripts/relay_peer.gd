class_name RelayPeer
extends MultiplayerPeerExtension
## A MultiplayerPeer that tunnels through the room-code relay (server/relay.js) over one WebSocket, so nobody
## has to port forward. Everything rides one TCP stream, so delivery is always reliable and in order. When the
## link backs up, unreliable packets (position snapshots) are dropped instead of queued, which keeps latency down.

signal hosted(code: String)
signal failed(message: String)

const PROTOCOL := "4"  # bump when the network format changes; the relay refuses mismatched versions
const MAX_BACKLOG := 48 * 1024

var code := ""
var _ws := WebSocketPeer.new()
var _hosting := false
var _id := 0
var _status := MultiplayerPeer.CONNECTION_DISCONNECTED
var _hello := {}
var _queue: Array = []  # [[from_peer, bytes], ...]
var _target := 0
var _mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _channel := 0
var _refuse := false
var _peers := {}
var _error := ""


func host(url: String) -> Error:
	_hosting = true
	_id = 1
	return _open(url, {op = "host", v = PROTOCOL})


func join(url: String, room: String) -> Error:
	_hosting = false
	_id = randi_range(2, 0x7FFFFFFF)
	code = room.to_upper().strip_edges()
	return _open(url, {op = "join", v = PROTOCOL, code = code, id = _id})


func _open(url: String, hello: Dictionary) -> Error:
	_ws.inbound_buffer_size = 1 << 20
	_ws.outbound_buffer_size = 1 << 20
	_ws.max_queued_packets = 8192
	_hello = hello
	var err := _ws.connect_to_url(url)
	if err == OK:
		_status = MultiplayerPeer.CONNECTION_CONNECTING
	return err


func _poll() -> void:
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN and not _hello.is_empty():
		_ws.send_text(JSON.stringify(_hello))
		_hello = {}
	while _ws.get_available_packet_count() > 0:
		var pkt := _ws.get_packet()
		if _ws.was_string_packet():
			var msg = JSON.parse_string(pkt.get_string_from_utf8())
			if msg is Dictionary:
				_control(msg)
		elif pkt.size() >= 4 and _status == MultiplayerPeer.CONNECTION_CONNECTED:
			_queue.append([pkt.decode_s32(0), pkt.slice(4)])
	if state == WebSocketPeer.STATE_CLOSED and _status != MultiplayerPeer.CONNECTION_DISCONNECTED:
		var reason := _error
		if reason == "" and _ws.get_close_code() == 4001 and _ws.get_close_reason() != "":
			reason = _ws.get_close_reason()  # the relay refused us and said why
		if reason == "":
			if _ws.get_close_code() == 4000:
				reason = "The host left the game."
			elif _status == MultiplayerPeer.CONNECTION_CONNECTING:
				reason = "Couldn't reach the online server. Check your internet connection."
			else:
				reason = "Lost connection to the online server."
		_drop_all()
		failed.emit(reason)


func _control(msg: Dictionary) -> void:
	match msg.get("op"):
		"hosted":
			code = str(msg.code)
			_status = MultiplayerPeer.CONNECTION_CONNECTED
			hosted.emit(code)
		"joined":
			_id = int(msg.id)
			_status = MultiplayerPeer.CONNECTION_CONNECTED
			_peers[1] = true
			peer_connected.emit(1)
		"peer_joined":
			_peers[int(msg.id)] = true
			peer_connected.emit(int(msg.id))
		"peer_left":
			if _peers.erase(int(msg.id)):
				peer_disconnected.emit(int(msg.id))
		"error":
			_error = str(msg.get("msg", "The online server refused the connection."))


func _drop_all() -> void:
	for id in _peers.keys():
		peer_disconnected.emit(id)
	_peers.clear()
	_queue.clear()
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED


func _get_available_packet_count() -> int:
	return _queue.size()


func _get_packet_script() -> PackedByteArray:
	return _queue.pop_front()[1] if not _queue.is_empty() else PackedByteArray()


func _get_packet_peer() -> int:
	return _queue[0][0] if not _queue.is_empty() else 0


func _put_packet_script(buffer: PackedByteArray) -> Error:
	if _status != MultiplayerPeer.CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	if _mode != MultiplayerPeer.TRANSFER_MODE_RELIABLE and _ws.get_current_outbound_buffered_amount() > MAX_BACKLOG:
		return OK  # a stale snapshot is worse than none
	var out := PackedByteArray()
	out.resize(4)
	out.encode_s32(0, _target if _hosting else 1)
	out.append_array(buffer)
	return _ws.send(out)


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return MultiplayerPeer.TRANSFER_MODE_RELIABLE


func _get_packet_channel() -> int:
	return 0


func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
	_mode = mode


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _mode


func _set_transfer_channel(channel: int) -> void:
	_channel = channel


func _get_transfer_channel() -> int:
	return _channel


func _set_target_peer(peer: int) -> void:
	_target = peer


func _get_unique_id() -> int:
	return _id


func _is_server() -> bool:
	return _hosting


func _is_server_relay_supported() -> bool:
	return false


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _status


func _get_max_packet_size() -> int:
	return 1 << 18


func _set_refuse_new_connections(enable: bool) -> void:
	_refuse = enable


func _is_refusing_new_connections() -> bool:
	return _refuse


func _disconnect_peer(_peer: int, _force: bool) -> void:
	pass  # the relay enforces room size; kicking isn't supported yet


func _close() -> void:
	_ws.close()
	_drop_all()
