extends Node

const voice_manager_const = preload("voice_manager_constants.gd")
var blank_packet = PoolVector2Array()
var player_audio = {}

onready var godot_voice = get_node("../GodotVoice")

func get_required_packet_count(p_playback : AudioStreamPlayback, p_frame_size : int) -> int:
	var to_fill = p_playback.get_frames_available()
	var required_packets = 0
	while to_fill >= p_frame_size:
		to_fill -= p_frame_size
		required_packets += 1
		
	return required_packets

func add_player_audio(p_player_id : int) -> void:
	if !player_audio.has(p_player_id):
		
		var new_generator = AudioStreamGenerator.new()
		new_generator.set_mix_rate(48000)
		new_generator.set_buffer_length(0.1)
		
		var audio_stream_player = AudioStreamPlayer.new()
		audio_stream_player.set_name(str(p_player_id))
		audio_stream_player.set_stream(new_generator)
		
		$PlayerStreamPlayers.add_child(audio_stream_player)
		audio_stream_player.play()
		
		player_audio[p_player_id] = {"audio_stream_player":audio_stream_player, "buffers":[], "index":-1}
	
func remove_player_audio(p_player_id : int) -> void:
	if player_audio.has(p_player_id):
		var audio_stream_player = player_audio[p_player_id].audio_stream_player
		audio_stream_player.queue_free()
		audio_stream_player.get_parent().remove_child(audio_stream_player)
		player_audio.erase(p_player_id)

func on_received_audio_packet(p_id, p_index, p_packet):
	if player_audio.has(p_id):
		var current_index = player_audio[p_id].index
		var buffers = player_audio[p_id].buffers
		
		var index_offset = p_index - current_index
		
		if index_offset > 0:
			# For skipped buffers, add empty packets
			for i in range(0, index_offset-1):
				buffers.push_front(null)
			# Add the new valid buffer
			buffers.push_front(p_packet)
				
			player_audio[p_id].index += index_offset
		else:
			var index = buffers.size() + index_offset
			if index >= 0:
				# Update existing buffer
				buffers[index] = p_packet
		
		player_audio[p_id].buffers = buffers

func update_player_audio():
	var player_ids = network_layer.get_player_ids()
	# Create stream players and buffer for any new players
	for player_id in player_ids:
		if !player_audio.has(player_id):
			add_player_audio(player_id)
			
	# Remove stream players and buffer for any absent players
	for player_id in player_audio.keys():
		if !player_ids.has(player_id):
			remove_player_audio(player_id)
			
func attempt_to_feed_stream(p_audio_stream_player, p_buffers):
	var playback = p_audio_stream_player.get_stream_playback()
	var required_packets = get_required_packet_count(playback, voice_manager_const.BUFFER_FRAME_COUNT)
	
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

func _process(delta):
	if delta > 0.0:
		for key in player_audio.keys():
			attempt_to_feed_stream(player_audio[key].audio_stream_player, player_audio[key].buffers)

func _init():
	for i in range(0, voice_manager_const.BUFFER_FRAME_COUNT):
		blank_packet.push_back(Vector2(0.0, 0.0))
