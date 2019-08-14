extends Control

signal host_requested(p_player_name, p_server_only)

func _on_host_pressed():
	if get_node("connect/name").text == "":
		get_node("connect/error_label").text = "Invalid name!"
		return

	get_node("connect").hide()
	get_node("players").show()
	get_node("connect/error_label").text = ""
	
	var server_only = get_node("connect/server_only").pressed
	var player_name = get_node("connect/name").text
	
	emit_signal("host_requested", player_name, server_only)

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

func on_connection_success():
	get_node("connect").hide()
	get_node("players").show()

func on_connection_failed():
	get_node("connect/host").disabled = false
	get_node("connect/join").disabled = false
	get_node("connect/error_label").set_text("Connection failed.")

func on_game_ended():
	show()
	get_node("connect").show()
	get_node("players").hide()
	get_node("connect/host").disabled = false

func on_game_error(errtxt):
	get_node("error").dialog_text = errtxt
	get_node("error").popup_centered_minsize()

func refresh_lobby(p_player_names : Array) -> void:
	get_node("players/list").clear()
	
	for p in p_player_names:
		get_node("players/list").add_item(p)
