extends Node

const gdnlib_const = preload("bin/godot_speech.gdnlib")
var godot_speech_nativescript: NativeScript = preload("bin/godot_speech.gdns")

var voice_controller: Node = null
const voice_controller_const = preload("voice_controller.gd")

var godot_speech = null


func get_skipped_audio_packets() -> int:
	if godot_speech:
		return godot_speech.get_skipped_audio_packets()
	else:
		return -1
		
func clear_skipped_audio_packets() -> void:
	if godot_speech:
		godot_speech.clear_skipped_audio_packets()

func start_recording() -> bool:
	if godot_speech:
		return godot_speech.start_recording()

	return false


func end_recording() -> bool:
	if godot_speech:
		return godot_speech.end_recording()

	return false


func decompress_buffer(
	p_decoder: Reference,
	p_byte_array: PoolByteArray,
	p_buffer_size: int,
	p_uncompressed_audio: PoolVector2Array
):
	return godot_speech.decompress_buffer(
		p_decoder, p_byte_array, p_buffer_size, p_uncompressed_audio
	)


func copy_and_clear_buffers() -> Array:
	if godot_speech:
		var buffer: Array = godot_speech.copy_and_clear_buffers()
		return buffer
	else:
		return []


func on_received_external_audio_packet(p_peer_id: int, p_sequence_id: int, p_buffer: PoolByteArray) -> void:
	voice_controller.on_received_audio_packet(p_peer_id, p_sequence_id, p_buffer)


func set_streaming_bus(p_name: String) -> void:
	if godot_speech:
		godot_speech.set_streaming_bus(p_name)
	else:
		printerr("Could not set streaming bus")
	

func set_audio_input_stream_player(p_audio_stream_player: AudioStreamPlayer) -> void:
	if godot_speech:
		godot_speech.set_audio_input_stream_player(p_audio_stream_player)
	else:
		printerr("Could not set audio input stream player")


func get_speech_decoder() -> Reference:
	if godot_speech:
		return godot_speech.get_speech_decoder()
	else:
		return null


func _ready() -> void:
	if ! Engine.is_editor_hint():
		voice_controller = voice_controller_const.new()
		voice_controller.set_name("VoiceController")
		add_child(voice_controller)

		if gdnlib_const and gdnlib_const.get_current_library_path() != "":
			if godot_speech_nativescript and godot_speech_nativescript.can_instance():
				godot_speech = godot_speech_nativescript.new()
				godot_speech.set_name("GodotSpeech")
				add_child(godot_speech)
				godot_speech.assign_voice_controller(voice_controller)
			else:
				printerr("GodotSpeech: could not instance godot_speech!")
