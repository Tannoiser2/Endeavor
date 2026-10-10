extends SceneTree
## Tessere Exploit sotto il tabellone con pezzi sopra + clic su una tessera per giocare l'Exploit.
## Uso: godot --path . -s res://tests/ui_xtiles_shot.gd -- <cartella>
var main: Node
var frames := 0
func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	frames += 1
	if frames == 3:
		main._start_game([{"name": "Stefano", "ai": false, "color": "#2f6fd0"}, {"name": "Rosso", "ai": true, "ai_level": 2, "color": "#d23c3c"},
			{"name": "Giallo", "ai": true, "ai_level": 2, "color": "#e0b52a"}], 8,
			{"exploit_ids": ["transit_of_venus", "south_sea_company", "underground_railroad"]})
		main._current.pause_btn.button_pressed = true
	if frames == 5:
		var gs = main._current
		var s: Dictionary = gs.state
		for rid in s.regions:
			Rules.open_region(s, rid)
		var tv: Dictionary = s.xs["transit_of_venus"]
		tv.spots = [1, 2, 1, 0, -1, -1, -1, -1]
		tv.rewards = [2, -1, -1, -1, -1]
		s.xs["south_sea_company"].spots = [2, 0, 1, -1, -1, -1, -1, -1]
		s.xs["underground_railroad"].spots = [1, 2, -1, -1, -1]
		for p in 3:
			s.players[p].supply -= 3
		# presenza ovunque per Stefano, Cantiere libero per provare il clic sulla tessera
		s.players[0].buildings = [{"id": "colonial_house", "occ": ""}, {"id": "shipyard", "occ": ""}]
		for rid in ["south_america", "caribbean", "far_east", "africa", "north_america"]:
			s.regions[rid].sea[0] += 1
			s.players[0].supply -= 1
		s.players[0].harbor = 5
		s.players[0].supply -= 5
		s.phase = "action"; s.turn_i = 0; s.first = 0; s.passed = [false, false, false]
		gs._step()
		gs._on_click("bld:1")
	if frames == 9:
		_shot()
	return false
func _shot() -> void:
	await RenderingServer.frame_post_draw
	var gs = main._current
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0].path_join("shot_xtiles.png"))
	var hl: Array = gs.map.highlights.keys().filter(func(k): return k.begins_with("x:"))
	print("tessere evidenziate: ", hl)
	var before: int = gs.state.xs["south_sea_company"].spots.count(0)
	gs._on_click("x:south_sea_company")
	if gs.popup.visible:
		print("popup: ", gs._popup_moves.size())
		gs._apply_human(gs._popup_moves[0])
	print("dischi di Stefano sulla Compagnia: %d → %d" % [before, gs.state.xs["south_sea_company"].spots.count(0)])
	print("ok")
	quit()
