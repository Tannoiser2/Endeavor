extends SceneTree
## Scheda Edifici con una Compagnia prendibile: presenza mostrata, clic che la prende.
## Uso: -- <cartella>
var main: Node
var frames := 0
func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	frames += 1
	if frames == 3:
		main._start_game([{"name": "Stefano", "ai": false, "color": "#2f6fd0"}, {"name": "Rosso", "ai": true, "ai_level": 2, "color": "#d23c3c"},
			{"name": "Giallo", "ai": true, "ai_level": 2, "color": "#e0b52a"}], 8, {})
		main._current.pause_btn.button_pressed = true
	if frames == 5:
		var gs = main._current
		var s: Dictionary = gs.state
		s.regions["north_america"].sea[0] += 6
		s.players[0].supply -= 6
		gs._step()
	if frames == 9:
		_shot()
	return false
func _shot() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var gs = main._current
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0].path_join("shot_charter.png"))
	print("prompt: ", gs.prompt.text)
	print("figli: ", gs.supply_flow.get_child_count())
	for c in gs.supply_flow.get_children():
		var b = c if c is TextureButton else c.get_child(0)
		print("  ", b.tooltip_text.get_slice("\n", 0).substr(0, 14), " mod=", b.modulate, " vis=", b.is_visible_in_tree(), " pos=", c.position)
	var ok := false
	for c in gs.supply_flow.get_children():
		if c is VBoxContainer and String(c.get_child(0).tooltip_text).contains("Nord America"):
			print("etichetta: ", c.get_child(1).text)
			c.get_child(0).emit_signal("pressed")
			ok = true
	await process_frame
	print("Compagnia di Stefano: ", gs.state.players[0].get("charter", ""), " cliccata=", ok)
	quit()
