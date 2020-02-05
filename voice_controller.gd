extends Node

const voice_manager_const = preload("voice_manager_constants.gd")
var blank_packet : PoolVector2Array = PoolVector2Array()
var player_audio : Dictionary = {}

export(bool) var use_sample_stretching = false

const VOICE_PACKET_SAMPLERATE = 48000
const BUFFER_DELAY_THRESHOLD = 0.1
const MAX_JITTER_BUFFER_SIZE = 10

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
		new_generator.set_mix_rate(VOICE_PACKET_SAMPLERATE)
		new_generator.set_buffer_length(BUFFER_DELAY_THRESHOLD)
		
		var audio_stream_player : AudioStreamPlayer = AudioStreamPlayer.new()
		audio_stream_player.set_name(str(p_player_id))
		audio_stream_player.set_stream(new_generator)
		
		$PlayerStreamPlayers.add_child(audio_stream_player)
		audio_stream_player.play()
		
		player_audio[p_player_id] = {"audio_stream_player":audio_stream_player, "jitter_buffer":[], "index":-1}
	
func remove_player_audio(p_player_id : int) -> void:
	if player_audio.has(p_player_id):
		var audio_stream_player : AudioStreamPlayer = player_audio[p_player_id].audio_stream_player
		audio_stream_player.queue_free()
		audio_stream_player.get_parent().remove_child(audio_stream_player)
		player_audio.erase(p_player_id)

func on_received_audio_packet(p_id : int, p_index : int, p_packet : PoolByteArray) -> void:
	#print("received_audio_packet: " + "id: " + str(p_id) + " index: " + str(p_index))
	if player_audio.has(p_id):
		# Detects if no audio packets have been received from this player yet.
		if player_audio[p_id].index == -1:
			player_audio[p_id].index = p_index - 1
		
		var current_index : int = player_audio[p_id].index
		var jitter_buffer : Array = player_audio[p_id].jitter_buffer
		
		var index_offset : int = p_index - current_index
		if index_offset > 0:
			# For skipped buffers, add empty packets
			var skipped_packets = index_offset-1
			if skipped_packets:
				var fill_packets = null
				
				# If using stretching, fill with last received packet
				if use_sample_stretching and !jitter_buffer.empty():
					fill_packets = jitter_buffer.back()[0]
					
				for i in range(0, skipped_packets):
					jitter_buffer.push_back([fill_packets, false])
			# Add the new valid buffer
			jitter_buffer.push_back([p_packet, true])
				
			var excess_packet_count : int = jitter_buffer.size() - MAX_JITTER_BUFFER_SIZE
			#if excess_packet_count > 0:
			#	print("Excess packet count: " + str(excess_packet_count))
			for i in range(0, excess_packet_count):
				jitter_buffer.pop_front()
				
			player_audio[p_id].index += index_offset
		else:
			var index : int = jitter_buffer.size()-1 + index_offset
			print("Updating existing index: " + str(index))
			if index >= 0:
				# Update existing buffer
				if use_sample_stretching:
					var jitter_buffer_size = jitter_buffer.size()
					for i in range(index, jitter_buffer_size-1):
						if jitter_buffer[i][1] == true:
							break
							
						jitter_buffer[i] = [p_packet, false]
				
				jitter_buffer[index] = [p_packet, true]
			else:
				printerr("invalid repair index!")
		
		player_audio[p_id].jitter_buffer = jitter_buffer

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
			
func attempt_to_feed_stream(p_audio_stream_player : AudioStreamPlayer, p_jitter_buffer : Array) -> void:
	var playback : AudioStreamPlayback = p_audio_stream_player.get_stream_playback()
	var required_packets : int = get_required_packet_count(playback, voice_manager_const.BUFFER_FRAME_COUNT)
	
	var last_packet = null
	if !p_jitter_buffer.empty():
		last_packet = p_jitter_buffer.back()[0]
	while p_jitter_buffer.size() < required_packets:
		var fill_packets = null
		# If using stretching, fill with last received packet
		if use_sample_stretching and !p_jitter_buffer.empty():
			fill_packets = last_packet
			
		p_jitter_buffer.push_back([fill_packets, false])
	
	for i in range(0, required_packets):
		var buffer = p_jitter_buffer.pop_front()[0]
		if buffer != null:
			var uncompressed_audio : PoolVector2Array = godot_voice.decompress_buffer(buffer)
			if uncompressed_audio:
				if uncompressed_audio.size() == voice_manager_const.BUFFER_FRAME_COUNT:
					playback.push_buffer(uncompressed_audio)
				else:
					playback.push_buffer(blank_packet)
			else:
				playback.push_buffer(blank_packet)
		else:
			playback.push_buffer(blank_packet)
	
	if use_sample_stretching and p_jitter_buffer.empty():
		p_jitter_buffer.push_back([last_packet, false])

func _process(p_delta : float) -> void:
	if p_delta > 0.0:
		for key in player_audio.keys():
			attempt_to_feed_stream(player_audio[key].audio_stream_player, player_audio[key].jitter_buffer)

func _init() -> void:
	for i in range(0, voice_manager_const.BUFFER_FRAME_COUNT):
		blank_packet.push_back(Vector2(0.0, 0.0))
