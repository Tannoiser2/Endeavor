extends SceneTree
## Screenshot con un edificio selezionato (colono "in mano" e bersagli evidenziati).
## Uso: godot --path . -s res://tests/ui_select_shot.gd -- <cartella> [lato]
var main: Node
var frames := 0
func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	frames += 1
	var args := OS.get_cmdline_user_args()
	if frames == 3:
		main._start_game([{"name": "Stefano", "ai": false, "color": "#2f6fd0"}, {"name": "Rosso", "ai": true, "ai_level": 2, "color": "#d23c3c"},
			{"name": "Giallo", "ai": true, "ai_level": 2, "color": "#e0b52a"}], 4, {"side": args[1] if args.size() > 1 else "A"})
		main._current.pause_btn.button_pressed = true
	if frames == 5:
		var gs = main._current
		var ai := AIPlayer.new(3)
		# avanza fino a un turno d'azione di Stefano al round 3, con un edificio dalle molte opzioni
		var guard := 0
		while guard < 3000:
			guard += 1
			var d := Rules.current_decision(gs.state)
			if d.type == "action" and d.p == 0 and gs.state.round >= 3:
				var best := -1
				var bn := 1
				for m in d.moves:
					if m["t"] == "activate":
						var n: int = d.moves.filter(func(x): return x["t"] == "activate" and x.bi == m.bi).size()
						if n > bn:
							bn = n
							best = m.bi
				if best >= 0:
					gs._step()
					gs._on_click("bld:%d" % best)
					break
			Rules.apply(gs.state, ai.choose(gs.state, d))
	if frames == 10:
		_shot()
	return false
func _shot() -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0].path_join("shot_select.png"))
	print("ok")
	quit()
