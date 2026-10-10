extends SceneTree
## Smoke test dell'interfaccia: il giocatore umano gioca CLICCANDO (edificio → bersaglio,
## token, carte, edifici disponibili, popup), le mosse sono scelte da un'IA di supporto.
## Uso: godot --path . -s res://tests/ui_smoke.gd -- <cartella_screenshot>

var main: Node
var frames := 0
var shots := 0
var helper := AIPlayer.new(7)
var out_dir := "user://"
var clicks := {}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(_d: float) -> bool:
	frames += 1
	if frames == 3:
		main._start_game([
			{"name": "Stefano", "ai": false, "ai_level": 0, "color": "#2f6fd0"},
			{"name": "Rosso", "ai": true, "ai_level": 2, "color": "#d23c3c"},
			{"name": "Giallo", "ai": true, "ai_level": 3, "color": "#e0b52a"}], 11,
			{"exploit_ids": ["republic_of_pirates", "jesuit_missionaries", "spanish_main"]})
		return false
	if frames < 6:
		return false
	var gs = main._current
	gs.speed.value = 0.05
	var d: Dictionary = gs.decision
	if d.type == "game_over":
		_shot("fine")
		print("FINE OK: ", gs.state.log.back())
		print("Clic usati: ", clicks)
		return true
	if gs._human() and frames % 3 == 0:
		if d.type == "action" and gs.state.round == 2 and shots == 0:
			_shot("azione_r2")
			return false
		_play_by_click(gs, helper.choose(gs.state, d))
	if frames > 4000:
		print("Fine smoke test (limite frame)")
		return true
	return false


func _count(k: String) -> void:
	clicks[k] = clicks.get(k, 0) + 1


func _play_by_click(gs, m: Dictionary) -> void:
	var before = gs.state.get("last", {})
	var target := Rules.move_target(m)
	match m["t"]:
		"build":
			_count("supply")
			gs._apply_human(m)   # = clic sul pulsante dell'edificio disponibile
			return
		"activate":
			gs._on_click("bld:%d" % int(m.bi))
			_count("bld")
			if is_same(gs.state.get("last", {}), before):
				if gs.sel.get("w", "") != m.w:
					gs._select({"k": "bld", "bi": m.bi, "w": m.w})
				if gs.state.round == 4 and shots == 1 and not gs.sel.is_empty():
					_shot("selezione_r4")
		"token":
			gs._on_click("tok:%d" % int(m.ti))
			_count("tok")
		"pass":
			_count("passa")
			gs._apply_human(m)
			return
	if not is_same(gs.state.get("last", {}), before):
		return
	if target != "":
		gs._on_click(target)
		_count(target.split(":")[0])
		if gs.popup.visible:
			_count("popup")
			var i: int = gs._popup_moves.find(m)
			gs.popup.hide()
			gs._apply_human(gs._popup_moves[i] if i >= 0 else m)
			return
	if is_same(gs.state.get("last", {}), before):
		_count("chip")
		gs._apply_human(m)


func _shot(name: String) -> void:
	shots += 1
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join("shot_%s.png" % name))
	print("screenshot ", name)
