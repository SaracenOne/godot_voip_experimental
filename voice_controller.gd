extends Node

const voice_manager_const = preload("voice_manager_constants.gd")
var blank_packet : PoolVector2Array = PoolVector2Array()
var player_audio : Dictionary = {}

const BUFFER_DELAY_THRESHOLD = 0.1

onready var godot_voice = get_node("../GodotVoice")

func get_required_packet_count(p_playback : AudioStreamPlayback, p_frame_size : int) -> int:
	var to_fill : int = p_playback.get_frames_available()
	var required_packets : int = 0
	while to_fill >= p_frame_size:
		to_fill -= p_frame_size
		required_packets += 1
		
	return required_packets

func add_player_audio(p_player_id : int) -> void:
	if !player_audio.has(p_player_id):
		
		var new_generator : AudioStreamGenerator = AudioStreamGenerator.new()
		new_generator.set_mix_rate(48000)
		new_generator.set_buffer_length(BUFFER_DELAY_THRESHOLD)
		
		var audio_stream_player : AudioStreamPlayer = AudioStreamPlayer.new()
		audio_stream_player.set_name(str(p_player_id))
		audio_stream_player.set_stream(new_generator)
		
		$PlayerStreamPlayers.add_child(audio_stream_player)
		audio_stream_player.play()
		
		player_audio[p_player_id] = {"audio_stream_player":audio_stream_player, "buffers":[], "index":-1, "delta":0.0}
	
func remove_player_audio(p_player_id : int) -> void:
	if player_audio.has(p_player_id):
		var audio_stream_player : AudioStreamPlayer = player_audio[p_player_id].audio_stream_player
		audio_stream_player.queue_free()
		audio_stream_player.get_parent().remove_child(audio_stream_player)
		player_audio.erase(p_player_id)

func on_received_audio_packet(p_id : int, p_index : int, p_packet : PoolByteArray) -> void:
	if player_audio.has(p_id):
		# Detects if no audio packets have been received from this player yet.
		if player_audio[p_id].index == -1:
			player_audio[p_id].index = p_index - 1
		
		var current_index : int = player_audio[p_id].index
		var buffers : Array = player_audio[p_id].buffers
		
		var index_offset : int = p_index - current_index
		if index_offset > 0:
			# For skipped buffers, add empty packets
			for i in range(0, index_offset-1):
				buffers.push_front(null)
			# Add the new valid buffer
			buffers.push_front(p_packet)
				
			player_audio[p_id].index += index_offset
		else:
			var index : int = buffers.size() + index_offset
			if index >= 0:
				# Update existing buffer
				buffers[index] = p_packet
		
		player_audio[p_id].buffers = buffers

func update_player_audio() -> void:
	var player_ids : Array = network_layer.get_player_ids()
	# Create stream players and buffer for any new players
	for player_id in player_ids:
		if !player_audio.has(player_id):
			add_player_audio(player_id)
			
	# Remove stream players and buffer for any absent players
	for player_id in player_audio.keys():
		if !player_ids.has(player_id):
			remove_player_audio(player_id)
			
func attempt_to_feed_stream(p_audio_stream_player : AudioStreamPlayer, p_buffers : Array) -> void:
	# Process voice only for client
	if !get_tree().is_network_server():
		return
	
	var playback : AudioStreamPlayback = p_audio_stream_player.get_stream_playback()
	var required_packets : int = get_required_packet_count(playback, voice_manager_const.BUFFER_FRAME_COUNT)
	
	while p_buffers.size() < required_packets:
		p_buffers.push_front(null)
	
	for i in range(0, required_packets):
		var buffer = p_buffers.pop_back()
		if buffer != null:
			var uncompressed_audio : PoolVector2Array = godot_voice.decompress_buffer(buffer)
			if uncompressed_audio.size() == voice_manager_const.BUFFER_FRAME_COUNT:
				playback.push_buffer(uncompressed_audio)
			else:
				playback.push_buffer(blank_packet)
		else:
			playback.push_buffer(blank_packet)

func _process(p_delta : float) -> void:
	if p_delta > 0.0:
		for key in player_audio.keys():
			player_audio[key].delta += p_delta # Increase internal timer for each player
			attempt_to_feed_stream(player_audio[key].audio_stream_player, player_audio[key].buffers)

func _init() -> void:
	for i in range(0, voice_manager_const.BUFFER_FRAME_COUNT):
		blank_packet.push_back(Vector2(0.0, 0.0))
