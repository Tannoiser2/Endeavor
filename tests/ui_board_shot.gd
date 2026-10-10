extends SceneTree
## Screenshot della plancia giocatore ingrandita a metà partita. Uso: ... -s res://tests/ui_board_shot.gd -- <cartella>
var main: Node
var frames := 0
func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	frames += 1
	if frames == 3:
		main._start_game([{"name": "Blu", "ai": true, "ai_level": 3, "color": "#2f6fd0"}, {"name": "Rosso", "ai": true, "ai_level": 2, "color": "#d23c3c"},
			{"name": "Giallo", "ai": true, "ai_level": 2, "color": "#e0b52a"}], 21, {"side": "B"})
		main._current.pause_btn.button_pressed = true
	if frames == 5:
		var gs = main._current
		var ai := AIPlayer.new(5)
		while gs.state.round < 5:
			var d := Rules.current_decision(gs.state)
			Rules.apply(gs.state, ai.choose(gs.state, d))
		while Rules.current_decision(gs.state).type != "action":
			Rules.apply(gs.state, ai.choose(gs.state, Rules.current_decision(gs.state)))
		for k in 6:
			Rules.apply(gs.state, ai.choose(gs.state, Rules.current_decision(gs.state)))
		gs._step()
	if frames == 9:
		_shot("shot_sideB.png", false)
	if frames == 14:
		_shot("shot_board.png", true)
	return false


func _shot(name: String, last: bool) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0].path_join(name))
	if last:
		print("ok")
		quit()
	else:
		main._current._open_board(0)
