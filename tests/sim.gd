extends SceneTree
## Simulazione headless: N partite IA contro IA, controlla invarianti e stampa statistiche.
## Gli Exploit ruotano in modo che in poche partite escano tutti e 15.
## Uso: godot --headless --path . -s res://tests/sim.gd -- [partite] [giocatori] [lato A/B] [livello IA fisso]

var errors := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 10
	var players := int(args[1]) if args.size() > 1 else 3
	var side: String = args[2] if args.size() > 2 else ""
	var fixed_level := int(args[3]) if args.size() > 3 else 0
	GameData.ensure_loaded()
	var all_x: Array = GameData.exploits.map(func(x): return x["id"])
	var wins := {}
	var totals := []
	var x_used := {}
	var x_unlocked := {}
	var x_actions := {}
	var charters_taken := {}
	var t0 := Time.get_ticks_msec()
	for g in games:
		var specs := []
		for i in players:
			var lvl := fixed_level if fixed_level > 0 else 1 + ((i + g) % 3)
			specs.append({"name": "IA%d" % (i + 1), "ai": true, "ai_level": lvl})
		var xs := []
		for k in 3:
			xs.append(all_x[(g * 3 + k) % all_x.size()])
		var opts := {"exploit_ids": xs}
		if side != "":
			opts["side"] = side
		var s := Rules.new_game(specs, g, opts)
		var ai := AIPlayer.new(g)
		var steps := 0
		while true:
			var d := Rules.current_decision(s)
			if d.type == "game_over" or d.type == "error":
				if d.type == "error":
					errors += 1
				break
			if d.moves.is_empty():
				push_error("Partita %d: decisione senza mosse %s" % [g, d])
				errors += 1
				break
			Rules.apply(s, ai.choose(s, d))
			steps += 1
			_check(s, g)
			if steps > 6000:
				push_error("Partita %d: troppi passi" % g)
				errors += 1
				break
		for pl in s.players:
			if String(pl.get("charter", "")) != "":
				charters_taken[pl.charter] = charters_taken.get(pl.charter, 0) + 1
		for k in s.get("xuse", {}):
			x_actions[k] = x_actions.get(k, 0) + s.xuse[k]
		for x in s.exploits:
			x_used[x] = x_used.get(x, 0) + 1
			if s.unlocked[x]:
				x_unlocked[x] = x_unlocked.get(x, 0) + 1
		var best := -1
		var best_sc := -999
		for p in players:
			var sc: int = Rules.score(s, p)["total"]
			totals.append(sc)
			if sc > best_sc:
				best_sc = sc
				best = p
		var lvl: int = s.players[best].ai_level
		wins[lvl] = wins.get(lvl, 0) + 1
		print("Partita %d (%s, %d passi): %s" % [g, ", ".join(s.exploits), steps,
			", ".join(range(players).map(func(p): return "%s L%d=%d" % [s.players[p].name, s.players[p].ai_level, Rules.score(s, p)["total"]]))])
		if g == 0:
			for line in s.log.slice(maxi(0, s.log.size() - 10)):
				print("   ", line)
			for p in players:
				print("   ", s.players[p].name, " ", Rules.score(s, p))
	totals.sort()
	print("Partite: %d, errori: %d. Vittorie per livello IA: %s" % [games, errors, wins])
	print("Exploit usati/sbloccati: %s / %s" % [x_used, x_unlocked])
	var ks := x_actions.keys()
	ks.sort()
	print("Azioni Exploit eseguite: ", ", ".join(ks.map(func(k): return "%s=%d" % [k, x_actions[k]])))
	print("Compagnie privilegiate prese: ", charters_taken)
	print("Punteggi min/mediana/max: %d / %d / %d" % [totals[0], totals[totals.size() / 2], totals[-1]])
	print("Tempo: %d ms" % (Time.get_ticks_msec() - t0))
	quit(1 if errors > 0 else 0)


func _check(s: Dictionary, g: int) -> void:
	var expected := int(GameData.rules["discs_per_player"])
	for p in s.n:
		var pl: Dictionary = s.players[p]
		if pl.harbor < 0 or pl.supply < 0:
			push_error("Partita %d: popolazione negativa per %s (porto %d, riserva %d) dopo %s" % [g, pl.name, pl.harbor, pl.supply, s.last])
			errors += 1
		var tot := Rules.disc_total(s, p)
		if tot != expected:
			push_error("Partita %d: dischi di %s = %d (attesi %d) dopo %s" % [g, pl.name, tot, expected, s.last])
			errors += 1
	if errors > 20:
		quit(1)
