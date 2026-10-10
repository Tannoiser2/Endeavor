extends SceneTree
## Test delle Compagnie privilegiate: requisito di presenza, una per giocatore, spazio del porto,
## azioni doppie, divieto di Pagamento, punteggio.
var fails := 0
func check(c: bool, m: String) -> void:
	print(("  ok  " if c else "  ERR ") + m)
	if not c:
		fails += 1

func _init() -> void:
	GameData.ensure_loaded()
	var s := Rules.new_game([{"name": "A"}, {"name": "B", "ai": true}], 3, {"exploits": false})
	check(s.charters.size() == 6, "6 Compagnie sul tavolo")
	var pl: Dictionary = s.players[0]
	s.phase = "build"; s.idx = 0; s.first = 0
	var d := Rules.current_decision(s)
	check(not d.moves.any(func(m): return String(m.b).begins_with("charter_")), "senza presenza nessuna Compagnia")
	# 6 presenza in India: 4 sul tracciato + 2 città aperte
	for i in 4:
		s.regions["india"].track.append(0)
	pl.supply -= 4
	Rules.open_region(s, "india")
	var cities: Array = Rules.board(s)["region_nodes"]["india"].filter(func(n): return Rules.board(s)["node"][n]["kind"] == "city")
	s.nodes[cities[0]].owner = 0
	s.nodes[cities[1]].owner = 0
	pl.supply -= 2
	check(Rules.presence(s, 0, "india") >= 6, "presenza in India: %d" % Rules.presence(s, 0, "india"))
	d = Rules.current_decision(s)
	var cm: Array = d.moves.filter(func(m): return m.b == "charter_india")
	check(cm.size() == 1, "può prendere la Compagnia dell'India")
	check(Rules.move_target(cm[0]) == "charter:india", "bersaglio cliccabile sul tavolo: charter:india")
	var ind0 := Rules.icons(s, 0, "industry")
	Rules.apply(s, cm[0])
	check(pl.buildings.back().id == "charter_india", "la Compagnia occupa uno spazio del porto")
	check(not s.charters.has("india"), "tolta dal tavolo")
	check(Rules.icons(s, 0, "industry") == ind0 + 1, "+1 Industria")
	# seconda Compagnia vietata
	for i in 6:
		s.regions["africa"].sea[0] += 1
	pl.supply -= 6
	Rules.open_region(s, "africa")
	s.phase = "build"; s.idx = 0
	d = Rules.current_decision(s)
	check(not d.moves.any(func(m): return String(m.b).begins_with("charter_")), "una sola Compagnia per giocatore")
	# azioni: Attaccare + Occupare in sequenza; niente Pagamento sul colono della Compagnia
	pl.buildings[-1].occ = "disc"
	pl.supply -= 1
	pl.buildings.append({"id": "museum", "occ": ""})
	pl.buildings[0].occ = "disc"
	pl.supply -= 1
	pl.harbor = 2; pl.supply -= 2
	s.phase = "action"; s.turn_i = 0; s.passed = [false, false]
	d = Rules.current_decision(s)
	var pay: Array = d.moves.filter(func(m): return m["t"] == "activate" and GameData.buildings[pl.buildings[m.bi].id]["id"] == "museum")
	var tg: Array = pay.map(func(m): return int(m.o.bi))
	check(not tg.has(pl.buildings.size() - 2), "il Museo non può liberare la Compagnia (bersagli %s)" % [tg])
	var sc := Rules.score(s, 0)
	check(sc.total > 0, "punteggio calcolato: %s" % sc)
	print("ERRORI: %d" % fails)
	quit(1 if fails > 0 else 0)
