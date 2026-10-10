extends SceneTree
## Azioni della Compagnia dei Mari del Sud: bonus immediati e continui.
func _init() -> void:
	var err := 0
	var specs := [{"name": "A", "ai": false, "color": "#2f6fd0"}, {"name": "B", "ai": false, "color": "#d23c3c"}, {"name": "C", "ai": false, "color": "#e0b52a"}]
	for sid in ["pay_industry", "disc_glory", "disc_industry", "pay_glory", "disc2_industry"]:
		for choice in ["now", "keep"]:
			var s: Dictionary = Rules.new_game(specs, 5, {"exploit_ids": ["south_sea_company", "saltpeter", "spanish_main"]})
			var ss: Dictionary = s.xs["south_sea_company"]
			ss.deck.erase(sid)
			ss.deck.push_front(sid)
			ss.spots = [1, 0, -1, -1, -1, -1, -1, -1]
			var x = Rules.exploit("south_sea_company")
			var sup0: int = s.players[0].supply
			var h0: int = s.players[0].harbor
			var ind0 := Rules.attr(s, 0, "industry")
			s.players[2].harbor += 1
			s.players[2].supply -= 1
			x.execute(s, 2, {}, {})
			var d := Rules.current_decision(s)
			if d.p != 0:
				print("ERR decisione a ", d.p); err += 1; continue
			var mv = d.moves.filter(func(m): return m.get("k", "") == choice and m.get("sid", "") == sid)[0]
			Rules.apply(s, mv)
			var dd := Rules.current_decision(s)
			var info := "%s/%s: harbor %d→%d, ind %d→%d, held %s, next %s" % [sid, choice, h0, s.players[0].harbor, ind0, Rules.attr(s, 0, "industry"), str(x.held(s, 0)), dd.get("type", "")]
			print(info)
			if choice == "keep" and sid.ends_with("industry") and Rules.attr(s, 0, "industry") != ind0 + 1:
				print("ERR industria"); err += 1
			if choice == "keep" and sid.ends_with("glory") and x.end_glory(s, 0) != 2 + 1:
				print("ERR gloria"); err += 1
			if choice == "now" and sid.begins_with("disc2") and s.players[0].harbor != h0 + 2:
				print("ERR +2"); err += 1
			if choice == "now" and sid.begins_with("disc_") and s.players[0].harbor != h0 + 1:
				print("ERR +1"); err += 1
			if choice == "now" and sid.begins_with("pay") and dd.get("p", -1) != 0:
				print("ERR pagamento non chiesto"); err += 1
	print("ERRORI: ", err)
	quit()
