extends SceneTree
## Test mirati del Pagamento: fase Pagamenti (automatica / scelta di cosa resta impegnato),
## azione Pagamento da edificio e da token, doppio pagamento della Tesoreria, divieti.
var fails := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok  ", msg)
	else:
		print("  ERR ", msg)
		fails += 1

func base() -> Dictionary:
	var s := Rules.new_game([{"name": "A", "ai": false}, {"name": "B", "ai": true}], 1, {"exploits": false})
	return s

func to_phase(s: Dictionary, phase: String) -> void:
	var ai := AIPlayer.new(1)
	var guard := 0
	while s.phase != phase and guard < 500:
		Rules.apply(s, ai.choose(s, Rules.current_decision(s)))
		guard += 1

func _init() -> void:
	GameData.ensure_loaded()
	print("1) Fase Pagamenti, pagamenti sufficienti → liberazione automatica")
	var s := base()
	var pl: Dictionary = s.players[0]
	pl.buildings = [{"id": "colonial_house", "occ": "disc"}, {"id": "shipyard", "occ": "disc"}]
	pl.supply -= 1
	s.players[1].buildings = [{"id": "colonial_house", "occ": ""}]
	s.players[1].supply += 1
	pl.tokens = [{"icons": {"finance": 1}}, {"icons": {"finance": 1}}]   # Ricchezza 2 → 2 pagamenti
	s.phase = "salary"; s.idx = 0; s.salary_left = -1; s.first = 0
	var h0: int = pl.harbor
	var d := Rules.current_decision(s)
	check(pl.buildings[0].occ == "" and pl.buildings[1].occ == "", "entrambi gli edifici liberati")
	check(pl.harbor == h0 + 2, "porto +2 (era %d, ora %d)" % [h0, pl.harbor])
	check(d.type != "salary", "nessuna domanda al giocatore")

	print("2) Pagamenti insufficienti → si sceglie cosa resta impegnato")
	s = base()
	pl = s.players[0]
	pl.buildings = [{"id": "colonial_house", "occ": "disc"}, {"id": "shipyard", "occ": "disc"}, {"id": "workshop", "occ": "disc"}]
	pl.supply -= 2
	s.players[1].supply += 1
	s.players[1].buildings[0].occ = ""
	pl.tokens = [{"icons": {"finance": 1}}, {"icons": {"finance": 1}}]   # 2 pagamenti per 3 edifici
	s.phase = "salary"; s.idx = 0; s.salary_left = -1; s.first = 0
	h0 = pl.harbor
	d = Rules.current_decision(s)
	check(d.type == "salary" and d.p == 0, "decisione di Pagamento per A")
	check(d.moves.size() == 3 and d.moves.all(func(m): return m["t"] == "keep"), "3 scelte 'tieni impegnato'")
	Rules.apply(s, {"t": "keep", "bi": 1})
	d = Rules.current_decision(s)
	check(pl.buildings[1].occ == "disc" and pl.buildings[0].occ == "" and pl.buildings[2].occ == "", "resta impegnato solo il Cantiere")
	check(pl.harbor == h0 + 2, "porto +2")

	print("3) Azione Pagamento da edificio (Museo)")
	s = base()
	pl = s.players[0]
	pl.buildings = [{"id": "colonial_house", "occ": "disc"}, {"id": "museum", "occ": ""}, {"id": "treasury", "occ": "disc"}, {"id": "shipyard", "occ": "disc"}]
	pl.supply -= 2
	pl.harbor = 3; pl.supply -= 3
	s.phase = "action"; s.turn_i = 0; s.first = 0; s.passed = [false, false]
	d = Rules.current_decision(s)
	var mus: Array = d.moves.filter(func(m): return m["t"] == "activate" and m.bi == 1)
	var tgts: Array = mus.map(func(m): return int(m.o.bi))
	tgts.sort()
	check(tgts == [0, 3], "Museo può liberare Casa coloniale e Cantiere, non la Tesoreria (ha Pagamento) né sé stesso: %s" % [tgts])
	h0 = pl.harbor
	Rules.apply(s, mus.filter(func(m): return m.o.bi == 3)[0])
	check(pl.buildings[1].occ == "disc", "Museo occupato dal colono")
	check(pl.buildings[3].occ == "", "Cantiere liberato")
	check(pl.harbor == h0, "porto invariato (−1 per il Museo, +1 dal Cantiere): %d" % pl.harbor)

	print("4) Tesoreria: due pagamenti in sequenza")
	s = base()
	pl = s.players[0]
	pl.buildings = [{"id": "colonial_house", "occ": "disc"}, {"id": "treasury", "occ": ""}, {"id": "shipyard", "occ": "disc"}, {"id": "workshop", "occ": ""}]
	pl.supply -= 2
	pl.harbor = 2; pl.supply -= 2
	s.phase = "action"; s.turn_i = 0; s.first = 0; s.passed = [false, false]
	d = Rules.current_decision(s)
	var tre: Array = d.moves.filter(func(m): return m["t"] == "activate" and m.bi == 1)
	check(tre.size() == 2, "primo pagamento: 2 bersagli")
	Rules.apply(s, tre.filter(func(m): return m.o.bi == 0)[0])
	d = Rules.current_decision(s)
	check(d.type == "frame", "secondo pagamento chiesto subito (frame)")
	var opts: Array = d.moves.filter(func(m): return m["t"] == "opt")
	check(opts.size() == 1 and int(opts[0].o.bi) == 2, "secondo bersaglio: solo il Cantiere")
	Rules.apply(s, opts[0])
	check(pl.buildings[0].occ == "" and pl.buildings[2].occ == "" and pl.buildings[1].occ == "disc", "due edifici liberati, Tesoreria occupata")
	check(Rules.current_decision(s).p == 1, "turno passato a B")

	print("5) Token azione Pagamento")
	s = base()
	pl = s.players[0]
	pl.buildings = [{"id": "colonial_house", "occ": "disc"}, {"id": "shipyard", "occ": "disc"}]
	pl.supply -= 1
	pl.tokens = [{"action": "payment"}]
	pl.harbor = 0
	s.phase = "action"; s.turn_i = 0; s.first = 0; s.passed = [false, false]
	d = Rules.current_decision(s)
	var tk: Array = d.moves.filter(func(m): return m["t"] == "token")
	check(tk.size() == 2, "token Pagamento utilizzabile anche con porto vuoto: %d bersagli" % tk.size())
	Rules.apply(s, tk[0])
	check(pl.tokens.is_empty() and pl.harbor == 1, "token speso, un colono torna nel porto")

	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


var main: Node
var frames := 0

func _process(_d: float) -> bool:
	frames += 1
	if frames == 2:
		main._start_game([{"name": "A", "ai": false}, {"name": "B", "ai": true}], 1, {"exploits": false})
	if frames == 4:
		ui_tests(main._current)
		print("ERRORI: %d" % fails)
		quit(1 if fails > 0 else 0)
	return false


func ui_tests(gs) -> void:
	print("6) Flusso a clic nell'interfaccia (Museo → clic sull'edificio da liberare)")
	var s: Dictionary
	var pl: Dictionary
	var keys: Array
	gs.pause_btn.button_pressed = true
	s = gs.state
	pl = s.players[0]
	pl.buildings = [{"id": "colonial_house", "occ": "disc"}, {"id": "museum", "occ": ""}, {"id": "shipyard", "occ": "disc"}, {"id": "workshop", "occ": "disc"}]
	pl.supply -= 2
	pl.harbor = 3; pl.supply -= 3
	s.phase = "action"; s.turn_i = 0; s.first = 0; s.passed = [false, false]
	gs._step()
	gs._on_click("bld:1")
	check(gs.sel.get("bi", -1) == 1, "Museo selezionato (colono sopra)")
	keys = gs.board.highlights.keys()
	keys.sort()
	check(keys == ["bld:0", "bld:2", "bld:3"], "evidenziati gli edifici liberabili: %s" % [keys])
	gs._on_click("bld:2")
	check(pl.buildings[2].occ == "" and pl.buildings[1].occ == "disc", "clic sul Cantiere: liberato, Museo occupato")
	check(gs.sel.is_empty(), "selezione chiusa")

	print("7) Fase Pagamenti a clic: 1 pagamento per 4 edifici → si clicca quello da liberare")
	pl.buildings = [{"id": "colonial_house", "occ": "disc"}, {"id": "museum", "occ": "disc"}, {"id": "shipyard", "occ": "disc"}, {"id": "workshop", "occ": "disc"}]
	pl.tokens = []
	s.players[1].buildings = [{"id": "colonial_house", "occ": ""}]
	s.phase = "salary"; s.idx = 0; s.salary_left = -1; s.first = 0
	var before: int = pl.harbor
	gs._step()
	check(gs.decision.type == "salary" and gs.decision.mode == "salary", "si sceglie cosa liberare (1 clic invece di 3)")
	keys = gs.board.highlights.keys()
	check(keys.size() == 4, "4 edifici cliccabili")
	gs._on_click("bld:3")
	check(pl.buildings[3].occ == "" and pl.buildings[0].occ == "disc" and pl.harbor == before + 1, "liberato solo il Laboratorio, porto +1")
	check(s.phase != "salary" or s.idx > 0, "pagamenti di A finiti (ora: %s di %d)" % [gs.decision.type, gs.decision.p])

	print("8) 3 pagamenti per 4 edifici → si clicca quello che resta (con segno RESTA IMPEGNATO)")
	pl.buildings = [{"id": "colonial_house", "occ": "disc"}, {"id": "museum", "occ": "disc"}, {"id": "shipyard", "occ": "disc"}, {"id": "workshop", "occ": "disc"}]
	pl.harbor -= 1
	pl.tokens = [{"icons": {"finance": 1}}, {"icons": {"finance": 1}}, {"icons": {"finance": 1}}, {"icons": {"finance": 1}}]
	s.phase = "salary"; s.idx = 0; s.salary_left = -1; s.first = 0
	before = pl.harbor
	gs._step()
	check(gs.decision.type == "salary" and gs.decision.mode == "keep", "si sceglie cosa resta impegnato")
	gs._on_click("bld:1")
	check(pl.buildings[1].occ == "disc" and pl.buildings[0].occ == "" and pl.buildings[2].occ == "" and pl.buildings[3].occ == "", "resta solo il Museo")
	check(pl.harbor == before + 3, "porto +3")

	print("9) 2 pagamenti per 4 edifici → due clic, il primo resta marcato")
	pl.buildings = [{"id": "colonial_house", "occ": "disc"}, {"id": "museum", "occ": "disc"}, {"id": "shipyard", "occ": "disc"}, {"id": "workshop", "occ": "disc"}]
	pl.harbor -= 3
	pl.tokens = [{"icons": {"finance": 1}}, {"icons": {"finance": 1}}]
	s.phase = "salary"; s.idx = 0; s.salary_left = -1; s.first = 0
	gs._step()
	check(gs.decision.type == "salary", "decisione")
	gs._on_click("bld:0")
	var mid_ok: bool = gs.decision.type == "salary" and (s.get("salary_keep", []).has(0) or pl.buildings[0].occ == "")
	check(mid_ok, "il primo clic si vede subito (marcato o liberato)")
	gs._on_click("bld:1")
	var occ := 0
	for b in pl.buildings:
		if b.occ == "disc":
			occ += 1
	check(occ == 2, "alla fine restano impegnati 2 edifici")
