extends SceneTree
## Prova del gioco online: due istanze di Endeavor (chi crea la stanza e un amico) giocano una
## partita intera sul finto Firebase (tests/firebase_mock.py), con un terzo colore IA. Le persone
## sono simulate dall'IA. EN_ROLE=host|guest, EN_CODEFILE=file per il codice della stanza,
## EN_PHASE=drop: l'ospite esce a metà (per provare il rientro con EN_PHASE=back).
## Alla fine ognuno stampa l'impronta della partita: devono coincidere.

var main
var t0 := 0
var ai := AIPlayer.new(7)


func _init() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	t0 = Time.get_ticks_msec()
	_run()


func _wait(s: float) -> void:
	await create_timer(s).timeout


static func fingerprint(s: Dictionary) -> String:
	var c: Dictionary = s.duplicate(true)
	c.erase("log")
	var sc := []
	for p in s.n:
		sc.append(Rules.score(s, p)["total"])
	return "%s · %d" % [str(sc), var_to_str(c).hash()]


func _run() -> void:
	await _wait(0.5)
	var role := OS.get_environment("EN_ROLE")
	var cf := OS.get_environment("EN_CODEFILE")
	var phase := OS.get_environment("EN_PHASE")
	var ss = main._current
	# Blu umano (chi crea), Rosso umano (l'amico), Bianco IA, gli altri non giocano.
	var pick := [1, 1, 3, 0, 0]
	for i in 5:
		ss._rows[i].group.get_buttons()[pick[i]].button_pressed = true
	ss._seed.text = "4242"
	ss._refresh_rows()
	ss._online_panel()
	ss.on_name.text = "Host" if role == "host" else "Ospite"
	if role == "host":
		await ss._online_create()
		var code: String = main.lobby.get("code", "")
		print("ENTEST stanza ", code)
		var f := FileAccess.open(cf, FileAccess.WRITE)
		f.store_string(code)
		f.close()
		while true:
			var room: Dictionary = await main.net.room(code)
			if Net._as_dict(room.get("seats", {})).size() >= 2:
				break
			await _wait(0.5)
		await ss._online_start()
	else:
		var code := ""
		while code == "":
			if FileAccess.file_exists(cf):
				code = FileAccess.get_file_as_string(cf).strip_edges()
			await _wait(0.3)
		ss.on_code.text = code
		await ss._online_join()
	var speed_set := false
	while true:
		await process_frame
		if Time.get_ticks_msec() - t0 > 1500000:
			print("ENTEST tempo scaduto")
			quit(2)
			return
		var gs = main._current
		if gs == null or not (gs is GameScreen) or gs.online == null:
			continue
		if not speed_set:
			speed_set = true
			gs.speed.value = 0.05
		var st: Dictionary = gs.state
		if gs.decision.get("type", "") == "game_over":
			await _wait(0.5)
			print("ENTEST impronta mosse=", gs.online.n, " | ", fingerprint(st))
			quit(0)
			return
		if phase == "drop" and st.round >= 4:
			print("ENTEST esco a metà partita, mossa ", gs.online.n)
			quit(0)
			return
		if gs._human() and gs.decision.moves.size() > 1:
			gs._apply_human(ai.choose(st, gs.decision))
