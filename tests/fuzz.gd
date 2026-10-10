extends SceneTree
## Test "fuzz": partite a mosse casuali con tutte le regioni aperte dall'inizio, così ogni
## Exploit è sbloccato subito e ogni suo ramo viene esercitato. Controlla le invarianti.
## Uso: godot --headless --path . -s res://tests/fuzz.gd -- [partite] [giocatori]

var errors := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 30
	var players := int(args[1]) if args.size() > 1 else 4
	GameData.ensure_loaded()
	var all_x: Array = GameData.exploits.map(func(x): return x["id"])
	var use := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for g in games:
		var specs := []
		for i in players:
			specs.append({"name": "R%d" % i, "ai": true})
		var xs := []
		for k in 3:
			xs.append(all_x[(g * 3 + k + g / 5) % all_x.size()])
		var s := Rules.new_game(specs, 1000 + g, {"exploit_ids": xs, "side": "A" if g % 2 == 0 else "B"})
		# Dischi e token extra per rendere disponibili più opzioni.
		for p in players:
			Rules.gain_discs(s, p, 6)
			for k in GameData.TRACKS:
				s.players[p].tokens.append({"icons": {k: 1}})
		for rid in s.regions:
			Rules.open_region(s, rid)
		var steps := 0
		while steps < 4000:
			var d := Rules.current_decision(s)
			if d.type == "game_over":
				break
			if d.type == "error" or d.moves.is_empty():
				push_error("Partita %d: decisione non valida %s" % [g, d])
				errors += 1
				break
			var moves: Array = d.moves
			var m: Dictionary = moves[rng.randi_range(0, moves.size() - 1)]
			# Preferisci le opzioni Exploit e non passare troppo presto.
			for k in 10:
				var c: Dictionary = moves[rng.randi_range(0, moves.size() - 1)]
				if c.get("o", {}).has("x") or c["t"] == "xm":
					m = c
					break
			if m["t"] == "pass" and moves.size() > 1 and rng.randf() < 0.85:
				m = moves[rng.randi_range(0, moves.size() - 2)]
			Rules.apply(s, m)
			steps += 1
			_check(s, g)
		for k in s.get("xuse", {}):
			use[k] = use.get(k, 0) + s.xuse[k]
		for p in players:
			Rules.score(s, p)
	var ks := use.keys()
	ks.sort()
	print("Rami Exploit esercitati (%d): %s" % [ks.size(), ", ".join(ks.map(func(k): return "%s=%d" % [k, use[k]]))])
	print("Partite: %d, errori: %d" % [games, errors])
	quit(1 if errors > 0 else 0)


func _check(s: Dictionary, g: int) -> void:
	for p in s.n:
		var pl: Dictionary = s.players[p]
		if pl.harbor < 0 or pl.supply < 0:
			push_error("Partita %d: popolazione negativa per %s (porto %d, riserva %d) dopo %s" % [g, pl.name, pl.harbor, pl.supply, s.last])
			errors += 1
		var tot := Rules.disc_total(s, p)
		if tot != int(GameData.rules["discs_per_player"]):
			push_error("Partita %d: dischi di %s = %d dopo %s" % [g, pl.name, tot, s.last])
			errors += 1
	if errors > 15:
		quit(1)
