extends Node

const voice_manager_const = preload("voice_manager_constants.gd")
const lobby_scene_const = preload("lobby.tscn")
var lobby_scene : Node = null

var is_connected : bool = false

var audio_mutex : Mutex = Mutex.new()
var input_audio_sent_id : int = 0
var input_audio_buffer_array : Array = []

func host(p_player_name : String, p_port : int, p_server_only : bool) -> void: 
	if network_layer.host_game(p_player_name, p_port, p_server_only):
		if lobby_scene:
			if network_layer.is_active_player():
				$GodotVoice.start()
				$VoiceController.update_player_audio()
			lobby_scene.refresh_lobby(network_layer.get_full_player_list())
		
		confirm_connection()

func confirm_connection() -> void:
	is_connected = true
	input_audio_sent_id = 0

func set_buffer(p_buffer : PoolByteArray) -> void:
	audio_mutex.lock()
	input_audio_buffer_array.push_back(p_buffer)
	audio_mutex.unlock()

func _audio_packet_processed(p_buffer : PoolByteArray) -> void:
	if network_layer.is_active_player():
		if p_buffer.size() == voice_manager_const.BUFFER_FRAME_COUNT * voice_manager_const.BUFFER_BYTE_COUNT:
			var compressed_buffer : PoolByteArray = $GodotVoice.compress_buffer(p_buffer)
			if compressed_buffer:
				set_buffer(compressed_buffer)

func copy_and_clear_buffers() -> Array:
	var out_buffers : Array = []
	
	audio_mutex.lock()
	out_buffers = input_audio_buffer_array.duplicate()
	input_audio_buffer_array = []
	audio_mutex.unlock()
	
	return out_buffers

func _on_connection_success() -> void:
	if network_layer.is_active_player():
		$GodotVoice.start()
	
	if lobby_scene:
		lobby_scene.on_connection_success()
		lobby_scene.refresh_lobby(network_layer.get_full_player_list())
		
	confirm_connection()

func _on_connection_failed() -> void:
	if lobby_scene:
		lobby_scene.on_connection_failed()
	
func _player_list_changed() -> void:
	if network_layer.is_active_player():
		$VoiceController.update_player_audio()
	
	if lobby_scene:
		lobby_scene.refresh_lobby(network_layer.get_full_player_list())

func _on_game_ended() -> void:
	if network_layer.is_active_player():
		$GodotVoice.stop()
	
	if lobby_scene:
		lobby_scene.on_game_ended()

func _on_game_error(p_errtxt : String) -> void:
	if lobby_scene:
		lobby_scene.on_game_error(p_errtxt)

func _on_received_audio_packet(p_id : int, p_index : int, p_packet : PoolByteArray) -> void:
	if network_layer.is_active_player():
		$VoiceController.on_received_audio_packet(p_id, p_index, p_packet)

func setup_connections() -> void:
	if network_layer.connect("connection_failed", self, "_on_connection_failed") != OK:
		printerr("connection_failed could not be connected!")
	if network_layer.connect("connection_succeeded", self, "_on_connection_success") != OK:
		printerr("connection_succeeded could not be connected!")
	if network_layer.connect("player_list_changed", self, "_player_list_changed") != OK:
		printerr("player_list_changed could not be connected!")
	if network_layer.connect("game_ended", self, "_on_game_ended") != OK:
		printerr("game_ended could not be connected!")
	if network_layer.connect("game_error", self, "_on_game_error") != OK:
		printerr("game_error could not be connected!")
	if network_layer.connect("received_audio_packet", self, "_on_received_audio_packet") != OK:
		printerr("received_audio_packet could not be connected!")
		
	if $GodotVoice.connect("audio_packet_processed", self, "_audio_packet_processed") != OK:
		printerr("audio_packet_processed could not be connected!")
		
	if lobby_scene:
		if lobby_scene.connect("host_requested", self, "host") != OK:
			printerr("audio_packet_processed could not be connected!")

var buffer_queue = []

export(float) var min_latency = 0.0
export(float) var max_latency = 0.0
export(float) var drop_rate = 0.0
export(float) var dup_rate = 0.0

static func sort_buffer_by_time(a, b):
	return a[1] <= b[1]

func _process(p_delta : float) -> void:
	if p_delta > 0.0:
		if is_connected and network_layer.is_active_player():
			var time = OS.get_ticks_msec() * 1000
			
			var buffers = copy_and_clear_buffers()
			for buffer_data in buffers:
				if randf() < drop_rate:
					continue
					
				var first_packet_time = time + min_latency + randf() * (max_latency-min_latency)
				buffer_queue.append([buffer_data, first_packet_time, input_audio_sent_id])
				while(randf() < dup_rate):
					var dup_packet_time = time + min_latency + randf() * (max_latency-min_latency)
					buffer_queue.append([buffer_data, dup_packet_time, input_audio_sent_id])
			
				input_audio_sent_id += 1
			
			if min_latency != max_latency:
				buffer_queue.sort_custom(self, "sort_buffer_by_time")
				
			var current_buffer_queue = buffer_queue.duplicate()
			for buffer in current_buffer_queue:
				
				var buffer_data = buffer[0]
				var buffer_time = buffer[1]
				var buffer_id = buffer[2]
				
				if time >= buffer_time:
					var id = buffer_queue.find(buffer)
					if id == -1:
						printerr("INVALID ID")
					buffer_queue.remove(id)
					network_layer.send_audio_packet(buffer_id, buffer_data)

func _ready() -> void:
	randomize()
	
	lobby_scene = lobby_scene_const.instance()
	add_child(lobby_scene)
	
	setup_connections()
