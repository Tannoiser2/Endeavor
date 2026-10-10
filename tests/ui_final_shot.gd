extends SceneTree
## Menu iniziale e schermata finale. Uso: -- <cartella>
var main: Node
var frames := 0
func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	frames += 1
	if frames == 4:
		_shot("shot_menu.png")
	if frames == 8:
		main._start_game([{"name": "Stefano", "ai": false, "color": "#2f6fd0"}, {"name": "Rosso", "ai": true, "ai_level": 2, "color": "#d23c3c"},
			{"name": "Bianco", "ai": true, "ai_level": 2, "color": "#e8e8e8"}], 11, {})
		main._current.pause_btn.button_pressed = true
	if frames == 10:
		var gs = main._current
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		var guard := 0
		while guard < 20000:
			var d := Rules.current_decision(gs.state)
			if d.type == "game_over":
				break
			Rules.apply(gs.state, d.moves[rng.randi_range(0, d.moves.size() - 1)])
			guard += 1
		gs._step()
	if frames == 14:
		_shot("shot_final.png")
	if frames == 16:
		var gs = main._current
		var b: Button = gs._final_layer.find_child("btn_Guarda_il_tabellone", true, false)
		b.emit_signal("pressed")
	if frames == 19:
		_shot("shot_final_board.png")
	if frames == 21:
		main._current.rematch_requested.emit()
	if frames == 24:
		print("dopo rivincita: ", main._current.state.round, " giocatori ", main._current.state.n)
		quit()
	return false
func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0].path_join(name))
	print("shot ", name)
