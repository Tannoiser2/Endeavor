extends SceneTree
## Quante volte una Compagnia privilegiata è disponibile in Costruzione e quante volte l'IA la prende.
func _init() -> void:
	GameData.ensure_loaded()
	var games := int(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 6
	var offered := 0
	var taken := 0
	var maxpres := []
	var first_round := []
	var why := {}
	var totals := []
	for g in games:
		var specs := []
		for i in 4:
			specs.append({"name": "IA%d" % i, "ai": true, "ai_level": 2})
		var s := Rules.new_game(specs, int(OS.get_cmdline_user_args()[1]) + g if OS.get_cmdline_user_args().size() > 1 else 100 + g, {})
		var ai := AIPlayer.new(g)
		var mp := 0
		while true:
			var d := Rules.current_decision(s)
			if d.type == "game_over":
				break
			for q in s.n:
				for rid in s.regions:
					mp = maxi(mp, Rules.presence(s, q, rid))
			var ch: Array = d.moves.filter(func(m): return m.get("t", "") == "build" and GameData.buildings[m.b].has("charter"))
			var m := ai.choose(s, d)
			if not ch.is_empty():
				offered += 1
				if first_round.size() < 30:
					first_round.append(s.round)
				var cv := []
				for c in ch:
					cv.append("%s=%.2f" % [c.b, ai._value_after(s, d.p, c, false)])
				var chosen := "%s=%.2f" % [m.get("b", m.t), ai._value_after(s, d.p, m, false)]
				if GameData.buildings.has(m.get("b", "")) and GameData.buildings[m.b].has("charter"):
					taken += 1
				elif why.size() < 12:
					why["g%d r%d p%d" % [g, s.round, d.p]] = "scelto %s contro %s" % [chosen, ", ".join(cv)]
			Rules.apply(s, m)
		maxpres.append(mp)
		for q in s.n:
			totals.append(Rules.score(s, q)["total"])
	print("decisioni con Compagnia disponibile: %d, prese: %d" % [offered, taken])
	print("presenza massima raggiunta per partita: ", maxpres)
	print("round in cui è disponibile: ", first_round)
	var sum := 0
	for t in totals:
		sum += t
	print("Gloria media: %.1f" % (float(sum) / max(1, totals.size())))
	for k in why:
		print(k, ": ", why[k])
	quit()
