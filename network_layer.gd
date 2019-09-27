extends Node

const DEFAULT_PORT = 10567
const MAX_PEERS = 32

var blocking_sending_audio_packets : bool = false

var is_server_only : bool = false
var player_name : String = "Player"
var players : Dictionary = {}

signal player_list_changed()
signal connection_failed()
signal connection_succeeded()
signal game_ended()
signal game_error(what)
signal received_audio_packet(p_id, p_index, p_packet)

static func encode_16_bit_value(p_value : int) -> PoolByteArray:
	return PoolByteArray([(p_value & 0x000000ff), (p_value & 0x0000ff00) >> 8])

static func decode_16_bit_value(p_buffer : PoolByteArray) -> int:
	var integer : int = 0
	integer = p_buffer[0] & 0x000000ff | (p_buffer[1] << 8) & 0x0000ff00
	return integer

static func encode_24_bit_value(p_value : int) -> PoolByteArray:
	return PoolByteArray([(p_value & 0x000000ff), (p_value & 0x0000ff00) >> 8, (p_value & 0x00ff0000) >> 16])

static func decode_24_bit_value(p_buffer : PoolByteArray) -> int:
	var integer : int = 0
	integer = p_buffer[0] & 0x000000ff | (p_buffer[1] << 8) & 0x0000ff00 | (p_buffer[2] << 16) & 0x00ff0000
	return integer

func is_active_player() -> bool:
	if get_tree().is_network_server():
		if !is_server_only:
			return true
		else:
			return false
	else:
		return true

func _player_connected(p_id : int) -> void:
	print(str(p_id) + " connected!")

func _player_disconnected(id : int) -> void:
	if get_tree().is_network_server():
		unregister_player(id)
		for p_id in players:
			# Erase in the server
			rpc_id(p_id, "unregister_player", id)

func _connected_ok() -> void:
	rpc("register_player", get_tree().get_network_unique_id(), player_name)
	emit_signal("connection_succeeded")

# Callback from SceneTree, only for clients (not server)
func _server_disconnected() -> void:
	emit_signal("game_error", "Server disconnected")
	end_game()

# Callback from SceneTree, only for clients (not server)
func _connected_fail() -> void:
	get_tree().set_network_peer(null) # Remove peer
	emit_signal("connection_failed")

func _network_peer_packet(p_id : int, packet : PoolByteArray) -> void:
	var result : Array = decode_voice_packet(packet)
	emit_signal("received_audio_packet", p_id, result[0], result[1])

# Lobby management functions

remote func register_player(id : int, new_player_name : String) -> void:
	if get_tree().is_network_server():
		if is_server_only == false:
			rpc_id(id, "register_player", 1, player_name)
		
		for p_id in players:
			rpc_id(id, "register_player", p_id, players[p_id])
			rpc_id(p_id, "register_player", id, new_player_name)

	players[id] = new_player_name
	emit_signal("player_list_changed")

remote func unregister_player(p_id : int) -> void:
	if players.erase(p_id) == true:
		emit_signal("player_list_changed")
	else:
		printerr("unregister_player: invalid id " + str(p_id))

func is_network_server():
	return get_tree().is_network_server()

func host_game(new_player_name : String, p_is_server_only : bool) -> bool:
	player_name = new_player_name
	is_server_only = p_is_server_only
	var host : NetworkedMultiplayerENet = NetworkedMultiplayerENet.new()
	if host.create_server(DEFAULT_PORT, MAX_PEERS) == OK:
		get_tree().set_network_peer(host)
		return true
	
	return false

func join_game(ip : String, new_player_name : String) -> void:
	player_name = new_player_name
	var host : NetworkedMultiplayerENet = NetworkedMultiplayerENet.new()
	if host.create_client(ip, DEFAULT_PORT) == OK:
		get_tree().set_network_peer(host)

func get_player_list() -> Array:
	return players.values()
	
func get_player_ids() -> Array:
	return players.keys()

func get_player_name() -> String:
	return player_name

func end_game():
	emit_signal("game_ended")
	players.clear()
	get_tree().set_network_peer(null) # End networking
	
func encode_voice_packet(p_index : int, p_voice_buffer : PoolByteArray) -> PoolByteArray:
	var encoded_index : PoolByteArray = encode_24_bit_value(p_index)
	var encoded_size : PoolByteArray = encode_16_bit_value(p_voice_buffer.size())
	
	var new_pool = PoolByteArray()
	new_pool.append_array(encoded_index)
	new_pool.append_array(encoded_size)
	new_pool.append_array(p_voice_buffer)
	
	return new_pool
	
func decode_voice_packet(p_voice_buffer : PoolByteArray) -> Array:
	var new_pool : PoolByteArray = PoolByteArray()
	var encoded_id : int = -1
	
	if p_voice_buffer.size() > 5:
		var index : int = 0
		encoded_id = decode_24_bit_value(PoolByteArray([p_voice_buffer[index + 0], p_voice_buffer[index + 1], p_voice_buffer[index + 2]]))
		index += 3
		
		var encoded_size : int = decode_16_bit_value(PoolByteArray([p_voice_buffer[index + 0], p_voice_buffer[index + 1]]))
		index += 2
		
		new_pool = p_voice_buffer.subarray(index, index + (encoded_size - 1))
		
		
	return [encoded_id, new_pool]

func send_audio_packet(p_index : int, p_data : PoolByteArray) -> void:
	if not blocking_sending_audio_packets:
		var compressed_audio_packet : PoolByteArray = encode_voice_packet(p_index , p_data)
		if get_tree().multiplayer.send_bytes(compressed_audio_packet, NetworkedMultiplayerPeer.TARGET_PEER_BROADCAST, NetworkedMultiplayerPeer.TRANSFER_MODE_UNRELIABLE) != OK:
			printerr("send_audio_packet: send_bytes failed!")

func get_full_player_list() -> Array:
	var players = get_player_list()
	players.sort()
	
	if is_active_player():
		players.push_front(get_player_name() + " (You)")
	
	return players
	
func _input(p_event : InputEvent):
	if p_event is InputEventKey:
		if p_event.scancode == KEY_X:
			if p_event.pressed:
				blocking_sending_audio_packets = true
			else:
				blocking_sending_audio_packets = false

func _ready() -> void:
	var connect_result : int = OK
	
	if get_tree().connect("network_peer_connected", self, "_player_connected") != OK:
		printerr("could not connect network_peer_connected!")
	if get_tree().connect("network_peer_disconnected", self,"_player_disconnected") != OK:
		printerr("could not connect network_peer_disconnected!")
	if get_tree().connect("connected_to_server", self, "_connected_ok") != OK:
		printerr("could not connect connected_to_server!")
	if get_tree().connect("connection_failed", self, "_connected_fail") != OK:
		printerr("could not connect connection_failed!")
	if get_tree().connect("server_disconnected", self, "_server_disconnected") != OK:
		printerr("could not connect server_disconnected!")
	
	connect_result = get_tree().multiplayer.connect("network_peer_packet", self, "_network_peer_packet")
	if connect_result != OK:
		printerr("NetworkManager: network_peer_packet could not be connected!")
