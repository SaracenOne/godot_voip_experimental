extends Node

const voice_manager_const = preload("bin/godot_speech_constants.gd")
var blank_packet: PoolVector2Array = PoolVector2Array()
var player_audio: Dictionary = {}

export (bool) var use_sample_stretching = true

const VOICE_PACKET_SAMPLERATE = 48000
const BUFFER_DELAY_THRESHOLD = 0.1

const STREAM_STANDARD_PITCH = 1.0
const STREAM_SPEEDUP_PITCH = 1.5

const MAX_JITTER_BUFFER_SIZE = 16
const JITTER_BUFFER_SPEEDUP = 12
const JITTER_BUFFER_SLOWDOWN = 6

const MIC_BUS_NAME = "Mic"
const STREAM_BUS_NAME = "Mic"

const DEBUG = false

var uncompressed_audio: PoolVector2Array = PoolVector2Array()
var decompress_funcref: FuncRef = null

# Debugging info
var packets_received_this_frame: int = 0


func vc_debug_print(p_str):
	if DEBUG:
		print(p_str)


func vc_debug_printerr(p_str):
	if DEBUG:
		printerr(p_str)


func get_required_packet_count(p_playback: AudioStreamPlayback, p_frame_size: int) -> int:
	var to_fill: int = p_playback.get_frames_available()
	var required_packets: int = 0
	while to_fill >= p_frame_size:
		to_fill -= p_frame_size
		required_packets += 1

	return required_packets


func add_player_audio(p_player_id: int, p_audio_stream_player: Node) -> void:
	if (
		p_audio_stream_player is AudioStreamPlayer
		or p_audio_stream_player is AudioStreamPlayer2D
		or p_audio_stream_player is AudioStreamPlayer3D
	):
		if ! player_audio.has(p_player_id):
			var new_generator: AudioStreamGenerator = AudioStreamGenerator.new()
			new_generator.set_mix_rate(VOICE_PACKET_SAMPLERATE)
			new_generator.set_buffer_length(BUFFER_DELAY_THRESHOLD)

			p_audio_stream_player.set_stream(new_generator)
			p_audio_stream_player.bus = "VoiceOutput"
			p_audio_stream_player.autoplay = true
			p_audio_stream_player.play()

			var speech_decoder: Reference = get_node("..").get_speech_decoder()

			player_audio[p_player_id] = {
				"audio_stream_player": p_audio_stream_player,
				"jitter_buffer": [],
				"sequence_id": -1,
				"last_update": OS.get_ticks_msec(),
				"packets_received_this_frame": 0,
				"excess_packets": 0,
				"speech_decoder": speech_decoder
			}
		else:
			printerr("Attempted to duplicate player_audio entry (%s)!" % p_player_id)


func remove_player_audio(p_player_id: int) -> void:
	if player_audio.has(p_player_id):
		if player_audio.erase(p_player_id):
			return
	
	printerr("Attempted to remove non-existant player_audio entry (%s)" % p_player_id)


func clear_all_player_audio() -> void:
	for key in player_audio.keys():
		if player_audio[key].audio_stream_player:
			player_audio[key].audio_stream_player.queue_free()

	player_audio = {}


func on_received_audio_packet(p_peer_id: int, p_sequence_id: int, p_packet: PoolByteArray) -> void:
	vc_debug_print(
		"received_audio_packet: peer_id: {id} sequence_id: {sequence_id}".format(
			{"id": str(p_peer_id), "sequence_id": str(p_sequence_id)}
		)
	)
	
	if player_audio.has(p_peer_id):
		
		# Detects if no audio packets have been received from this player yet.
		if player_audio[p_peer_id]["sequence_id"] == -1:
			player_audio[p_peer_id]["sequence_id"] = p_sequence_id - 1
			
		player_audio[p_peer_id]["packets_received_this_frame"] += 1
		packets_received_this_frame += 1

		var current_sequence_id: int = player_audio[p_peer_id]["sequence_id"]
		var jitter_buffer: Array = player_audio[p_peer_id]["jitter_buffer"]

		var sequence_id_offset: int = p_sequence_id - current_sequence_id
		if sequence_id_offset > 0:
			# For skipped buffers, add empty packets
			var skipped_packets = sequence_id_offset - 1
			if skipped_packets:
				var fill_packets = null

				# If using stretching, fill with last received packet
				if use_sample_stretching and ! jitter_buffer.empty():
					fill_packets = jitter_buffer.back()["packet"]

				for _i in range(0, skipped_packets):
					jitter_buffer.push_back({"packet": fill_packets, "valid": false})
			# Add the new valid buffer
			jitter_buffer.push_back({"packet": p_packet, "valid": true})

			var excess_packet_count: int = jitter_buffer.size() - MAX_JITTER_BUFFER_SIZE
			if excess_packet_count > 0:
				print("Excess packet count: %s" % str(excess_packet_count))
				for _i in range(0, excess_packet_count):
					player_audio[p_peer_id]["excess_packets"] += 1
					jitter_buffer.pop_front()

			player_audio[p_peer_id]["sequence_id"] += sequence_id_offset
		else:
			var sequence_id: int = jitter_buffer.size() - 1 + sequence_id_offset
			vc_debug_print("Updating existing sequence_id: %s" % str(sequence_id))
			if sequence_id >= 0:
				# Update existing buffer
				if use_sample_stretching:
					var jitter_buffer_size = jitter_buffer.size()
					for i in range(sequence_id, jitter_buffer_size - 1):
						if jitter_buffer[i]["valid"]:
							break

						jitter_buffer[i] = {"packet": p_packet, "valid": false}

				jitter_buffer[sequence_id] = {"packet": p_packet, "valid": true}
			else:
				vc_debug_printerr("invalid repair sequence_id!")

		player_audio[p_peer_id]["jitter_buffer"] = jitter_buffer


func attempt_to_feed_stream(
	p_skip_count: int, p_decoder: Reference, p_audio_stream_player: Node, p_jitter_buffer: Array
) -> void:
	if p_audio_stream_player == null:
		return
		
	for _i in range(0, p_skip_count):
		p_jitter_buffer.pop_front()

	var playback: AudioStreamPlayback = p_audio_stream_player.get_stream_playback()
	var required_packets: int = get_required_packet_count(
		playback, voice_manager_const.BUFFER_FRAME_COUNT
	)
	
	var skips: int = playback.get_skips()
	vc_debug_print("packets skips: %s" % skips)

	var last_packet = null
	if ! p_jitter_buffer.empty():
		last_packet = p_jitter_buffer.back()["packet"]
	while p_jitter_buffer.size() < required_packets:
		var fill_packets = null
		# If using stretching, fill with last received packet
		if use_sample_stretching and ! p_jitter_buffer.empty():
			fill_packets = last_packet

		p_jitter_buffer.push_back({"packet": fill_packets, "valid": false})

	for _i in range(0, required_packets):
		var packet = p_jitter_buffer.pop_front()
		var packet_pushed: bool = false
		if packet:
			var buffer = packet["packet"]
			if buffer != null:
				uncompressed_audio = decompress_funcref.call_func(
					p_decoder, buffer, buffer.size(), uncompressed_audio
				)
				if uncompressed_audio:
					if uncompressed_audio.size() == voice_manager_const.BUFFER_FRAME_COUNT:
						playback.push_buffer(uncompressed_audio)
						packet_pushed = true
		if ! packet_pushed:
			playback.push_buffer(blank_packet)

	if use_sample_stretching and p_jitter_buffer.empty():
		p_jitter_buffer.push_back({"packet": last_packet, "valid": false})
		
	# Speed up or slow down the audio stream to mitigate skipping
	if p_jitter_buffer.size() > JITTER_BUFFER_SPEEDUP:
		p_audio_stream_player.pitch_scale = STREAM_SPEEDUP_PITCH
	elif p_jitter_buffer.size() < JITTER_BUFFER_SLOWDOWN:
		p_audio_stream_player.pitch_scale = STREAM_STANDARD_PITCH

func _process(_delta: float) -> void:
	for key in player_audio.keys():
		attempt_to_feed_stream(
			0,
			player_audio[key]["speech_decoder"],
			player_audio[key]["audio_stream_player"],
			player_audio[key]["jitter_buffer"]
		)
		player_audio[key]["packets_received_this_frame"] = 0
	packets_received_this_frame = 0


func _ready() -> void:
	uncompressed_audio.resize(voice_manager_const.BUFFER_FRAME_COUNT)

	decompress_funcref = funcref(get_node(".."), "decompress_buffer")


func _init() -> void:
	blank_packet.resize(voice_manager_const.BUFFER_FRAME_COUNT)
	for i in range(0, voice_manager_const.BUFFER_FRAME_COUNT):
		blank_packet[i] = Vector2(0.0, 0.0)
