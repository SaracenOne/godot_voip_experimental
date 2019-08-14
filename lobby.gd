extends Control

const voice_manager_const = preload("voice_manager_constants.gd")

var is_connected = false

var audio_mutex = Mutex.new()
var input_audio_sent_id = 0
var input_audio_buffer_array = []

func set_buffer(p_buffer):
	audio_mutex.lock()
	input_audio_buffer_array.push_back(p_buffer)
	audio_mutex.unlock()

func _audio_packet_processed(p_buffer):
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

func _ready():
	if network_layer.connect("connection_failed", self, "_on_connection_failed") != OK:
		printerr("connection_failed could not be connected!")
	if network_layer.connect("connection_succeeded", self, "_on_connection_success") != OK:
		printerr("connection_succeeded could not be connected!")
	if network_layer.connect("player_list_changed", self, "refresh_lobby") != OK:
		printerr("player_list_changed could not be connected!")
	if network_layer.connect("game_ended", self, "_on_game_ended") != OK:
		printerr("game_ended could not be connected!")
	if network_layer.connect("game_error", self, "_on_game_error") != OK:
		printerr("game_error could not be connected!")
	if network_layer.connect("received_audio_packet", self, "_on_received_audio_packet") != OK:
		printerr("received_audio_packet could not be connected!")
		
	if $GodotVoice.connect("audio_packet_processed", self, "_audio_packet_processed") != OK:
		printerr("audio_packet_processed could not be connected!")
	
func confirm_connection():
	is_connected = true
	input_audio_sent_id = 0

func _process(delta):
	if delta > 0.0:
		if is_connected:
			var buffers = copy_and_clear_buffers()
			for buffer in buffers:
				network_layer.send_audio_packet(input_audio_sent_id, buffer)
				input_audio_sent_id += 1

func _on_host_pressed():
	if get_node("connect/name").text == "":
		get_node("connect/error_label").text = "Invalid name!"
		return

	get_node("connect").hide()
	get_node("players").show()
	get_node("connect/error_label").text = ""

	var player_name = get_node("connect/name").text
	if network_layer.host_game(player_name):
		refresh_lobby()
		confirm_connection()

func _on_join_pressed():
	if get_node("connect/name").text == "":
		get_node("connect/error_label").text = "Invalid name!"
		return

	var ip = get_node("connect/ip").text
	if not ip.is_valid_ip_address():
		get_node("connect/error_label").text = "Invalid IPv4 address!"
		return

	get_node("connect/error_label").text=""
	get_node("connect/host").disabled = true
	get_node("connect/join").disabled = true

	var player_name = get_node("connect/name").text
	network_layer.join_game(ip, player_name)

func _on_connection_success():
	get_node("connect").hide()
	get_node("players").show()
	
	confirm_connection()

func _on_connection_failed():
	get_node("connect/host").disabled = false
	get_node("connect/join").disabled = false
	get_node("connect/error_label").set_text("Connection failed.")

func _on_game_ended():
	show()
	get_node("connect").show()
	get_node("players").hide()
	get_node("connect/host").disabled = false

func _on_game_error(errtxt):
	get_node("error").dialog_text = errtxt
	get_node("error").popup_centered_minsize()

func _on_received_audio_packet(p_id, p_index, p_packet):
	$VoiceController.on_received_audio_packet(p_id, p_index, p_packet)

func refresh_lobby():
	$VoiceController.update_player_audio()
	
	var players = network_layer.get_player_list()
	players.sort()
	
	get_node("players/list").clear()
	get_node("players/list").add_item(network_layer.get_player_name() + " (You)")
	
	for p in players:
		get_node("players/list").add_item(p)
