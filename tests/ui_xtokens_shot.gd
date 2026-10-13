extends SceneTree
## Token degli Exploit sulle tessere e sulla plancia. Uso: -- <cartella> <set 0|1|2>
var main: Node
var frames := 0
const SETS := [["transit_of_venus", "south_sea_company", "underground_railroad"],
	["saltpeter", "manila_galleons", "jesuit_missionaries"],
	["spanish_main", "dutch_east_india", "south_sea_company"],
	["imperialism", "republic_of_pirates", "sun_never_sets"]]
func _initialize() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
func _process(_d: float) -> bool:
	frames += 1
	var which := int(OS.get_cmdline_user_args()[1])
	if frames == 3:
		main._start_game([{"name": "Stefano", "ai": false, "color": "#2f6fd0"}, {"name": "Rosso", "ai": true, "ai_level": 2, "color": "#d23c3c"},
			{"name": "Giallo", "ai": true, "ai_level": 2, "color": "#e0b52a"}], 8, {"exploit_ids": SETS[which]})
		main._current.pause_btn.button_pressed = true
	if frames == 5:
		var gs = main._current
		var s: Dictionary = gs.state
		for rid in s.regions:
			if not (which == 2 and rid == "north_america"):
				Rules.open_region(s, rid)
			for q in 3:
				if q != 1 or rid != "africa":
					s.regions[rid].sea[q] += 1
					s.players[q].supply -= 1
		var pl: Dictionary = s.players[0]
		pl.buildings = [{"id": "colonial_house", "occ": ""}, {"id": "barracks", "occ": "cannon"}, {"id": "shipyard", "occ": ""}]
		pl.tokens.append({"icons": {"culture": 1}, "kind": "freedom"})
		pl.tokens.append({"icons": {"influence": 1}, "kind": "transit"})
		pl.tokens.append({"icons": {"glory": 1}, "kind": "transit"})
		pl.tokens.append({"action": "attack"})
		pl["cannons"] = 3
		pl["galleons"] = 2
		if s.xs.has("south_sea_company"):
			var ss: Dictionary = s.xs["south_sea_company"]
			ss.held = {"0": [ss.deck.pop_front(), ss.deck.pop_front()]}
			ss.spots = [2, 0, 1, -1, -1, -1, -1, -1]
		if s.xs.has("transit_of_venus"):
			s.xs["transit_of_venus"].tokens.erase("influence")
			s.xs["transit_of_venus"].tokens.erase("glory")
		if s.xs.has("underground_railroad"):
			s.xs["underground_railroad"].free.erase("culture")
		if s.xs.has("jesuit_missionaries"):
			var jm: Dictionary = s.xs["jesuit_missionaries"]
			for nid in s.nodes:
				if Rules.board(s)["node"][nid]["kind"] == "city" and Rules.region_of(s, nid) == "europe" and jm.at.size() < 2:
					jm.at[nid] = true
			jm.tile = 3
		if s.xs.has("saltpeter"):
			s.xs["saltpeter"].left = 3
		s.forts_left = 7
		if s.xs.has("imperialism"):
			var keys: Array = s.xs["imperialism"].block.keys()
			s.xs["imperialism"].block.erase(keys[0])
			s.xs["imperialism"].held = {"1": 1}
		gs._refresh_all() if gs.has_method("_refresh_all") else gs._step()
	if frames == 9:
		_shot(which)
	return false
func _shot(which: int) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0].path_join("shot_xtok%d.png" % which))
	var gs = main._current
	if "left_tabs" in gs:
		gs.left_tabs.current_tab = 0
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0].path_join("shot_xtok%d_map.png" % which))
	print("ok")
	quit()
