extends Node

const voice_manager_const = preload("voice_manager_constants.gd")
const lobby_scene_const = preload("lobby.tscn")
var lobby_scene = null

var is_connected = false

var audio_mutex = Mutex.new()
var input_audio_sent_id = 0
var input_audio_buffer_array = []

func host(p_player_name, p_server_only): 
	if network_layer.host_game(p_player_name, p_server_only):
		if lobby_scene:
			if network_layer.is_active_player():
				$GodotVoice.start()
				$VoiceController.update_player_audio()
			lobby_scene.refresh_lobby(network_layer.get_full_player_list())
		
		confirm_connection()

func confirm_connection():
	is_connected = true
	input_audio_sent_id = 0

func set_buffer(p_buffer):
	audio_mutex.lock()
	input_audio_buffer_array.push_back(p_buffer)
	audio_mutex.unlock()

func _audio_packet_processed(p_buffer):
	if network_layer.is_active_player():
		if p_buffer.size() == voice_manager_const.BUFFER_FRAME_COUNT * voice_manager_const.BUFFER_BYTE_COUNT:
			var compressed_buffer = $GodotVoice.compress_buffer(p_buffer)
			set_buffer(compressed_buffer)

func copy_and_clear_buffers():
	var out_buffers = []
	
	if audio_mutex.try_lock() == OK:
		out_buffers = input_audio_buffer_array
		input_audio_buffer_array = []
		audio_mutex.unlock()
	
	return out_buffers

func _on_connection_success():
	if network_layer.is_active_player():
		$GodotVoice.start()
	
	if lobby_scene:
		lobby_scene.on_connection_success()
		lobby_scene.refresh_lobby(network_layer.get_full_player_list())
		
	confirm_connection()

func _on_connection_failed():
	if lobby_scene:
		lobby_scene.on_connection_failed()
	
func _player_list_changed():
	if network_layer.is_active_player():
		$VoiceController.update_player_audio()
	
	if lobby_scene:
		lobby_scene.refresh_lobby(network_layer.get_full_player_list())

func _on_game_ended():
	if network_layer.is_active_player():
		$GodotVoice.stop()
	
	if lobby_scene:
		lobby_scene.on_game_ended()

func _on_game_error(errtxt):
	if lobby_scene:
		lobby_scene.on_game_error()

func _on_received_audio_packet(p_id, p_index, p_packet):
	if network_layer.is_active_player():
		$VoiceController.on_received_audio_packet(p_id, p_index, p_packet)

func setup_connections():
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

func _process(delta):
	if delta > 0.0:
		if is_connected and network_layer.is_active_player():
			var buffers = copy_and_clear_buffers()
			for buffer in buffers:
				network_layer.send_audio_packet(input_audio_sent_id, buffer)
				input_audio_sent_id += 1

func _ready():
	lobby_scene = lobby_scene_const.instance()
	add_child(lobby_scene)
	
	setup_connections()
