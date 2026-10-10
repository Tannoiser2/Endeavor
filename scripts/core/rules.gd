class_name Rules
extends RefCounted
## Motore delle regole di Endeavor: Age of Sail (con Exploit).
## Funzioni statiche e pure sullo stato, un Dictionary serializzabile: lo stesso codice
## gira nella partita, nell'IA (che clona lo stato) e nei test headless.
##
## Flusso: current_decision(s) avanza le fasi automatiche e restituisce la prossima
## decisione {p, type, moves}; apply(s, move) applica una mossa scelta fra quelle legali.
## Le decisioni annidate (passi successivi di un edificio, scelte degli Exploit) vivono
## in una pila s.stack di "frame".

const LOG_MAX := 500
const PHASES := ["build", "growth", "salary", "action", "discard"]

static var _xinst: Dictionary = {}


# ═════════════════════════════ SETUP ═════════════════════════════

## opts: {"side": "A"/"B", "start_building": "colonial_house"/"merchant_dock", "exploits": true}
static func new_game(player_specs: Array, seed_value: int = -1, opts: Dictionary = {}) -> Dictionary:
	GameData.ensure_loaded()
	var rng := RandomNumberGenerator.new()
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	var n := player_specs.size()
	var R := GameData.rules
	var side: String = opts.get("side", "B" if n >= 5 else "A")
	var s := {
		"n": n, "side": side, "round": 1, "phase": "build", "first": 0, "idx": 0, "turn_i": 0,
		"salary_left": -1, "passed": [], "stack": [], "players": [],
		"nodes": {}, "links": [], "regions": {}, "discard": [], "bsupply": {},
		"abolished": false, "exploits": [], "unlocked": {}, "xs": {},
		"log": [], "seed": rng.seed, "rng_state": 0, "last": {},
		"opts": opts.duplicate(),
	}
	var start_b: String = opts.get("start_building", "colonial_house")
	for i in n:
		var spec: Dictionary = player_specs[i]
		var pl := {
			"name": spec.get("name", "Giocatore %d" % (i + 1)),
			"ai": spec.get("ai", false), "ai_level": spec.get("ai_level", 2),
			"color": spec.get("color", "#ffffff"),
			"supply": int(R["discs_per_player"]), "harbor": int(R["start_harbor"]),
			"buildings": [{"id": start_b, "occ": ""}], "cards": [], "gov": "", "tokens": [],
			"slavery_aside": 0, "bonus_glory": 0, "disc_cards": {},
		}
		if R.get("start_building_disc", true):
			pl.supply -= 1
			pl.buildings[0].occ = "disc"
		s.players.append(pl)
		s.passed.append(false)

	var B := board(s)
	var pool: Array = GameData.tokens.duplicate(true)
	_shuffle(pool, rng)
	for r in B["regions"]:
		var rid: String = r["id"]
		var decks := {"main": [], "slavery": []}
		var gov := ""
		var by_deck := {"main": [], "slavery": []}
		for cid in GameData.cards:
			var c: Dictionary = GameData.cards[cid]
			if c["region"] != rid:
				continue
			if c.get("governor", false):
				gov = cid
			else:
				by_deck[c.get("deck", "main")].append(cid)
		for d in by_deck:
			var arr: Array = by_deck[d]
			arr.sort_custom(func(a, b): return GameData.cards[a]["value"] > GameData.cards[b]["value"])
			decks[d] = arr  # ultimo elemento = cima del mazzo (valore più basso)
		var tr: Array = B["tracks"].get(rid, [])
		var ttok := []
		for k in tr.size():
			ttok.append(pool.pop_back())
		var sea := []
		for p in n:
			sea.append(0)
		s.regions[rid] = {"open": r["start_open"], "track": [], "track_tokens": ttok, "sea": sea,
			"decks": decks, "governor": gov}
	for nid in B["node"]:
		s.nodes[nid] = {"owner": -1, "token": pool.pop_back()}
	for l in B["link"]:
		s.links.append({"token": pool.pop_back() if l["token"] else null, "claimed": false})
	if not pool.is_empty():
		push_warning("Token avanzati: %d" % pool.size())

	# Edifici: livelli 1-4 tutti, livello 5 solo alcuni a caso.
	var lvl5 := []
	for bid in GameData.building_order:
		var b: Dictionary = GameData.buildings[bid]
		var lv := int(b["level"])
		if lv == 0:
			continue
		if lv == 5:
			lvl5.append(bid)
		else:
			s.bsupply[bid] = int(b["count"])
	_shuffle(lvl5, rng)
	for i in mini(int(R["lvl5_available"]), lvl5.size()):
		s.bsupply[lvl5[i]] = 1

	# Compagnie privilegiate (mini-espansione): una per regione, disponibili sul tavolo.
	s["charters"] = {}
	if opts.get("charters", true):
		for bid in GameData.building_order:
			var b: Dictionary = GameData.buildings[bid]
			if b.has("charter"):
				s.charters[b["charter"]] = bid

	# Exploit.
	if opts.get("exploits", true):
		var xs: Array = GameData.exploits.map(func(x): return x["id"])
		if opts.has("exploit_ids"):
			xs = opts["exploit_ids"].duplicate()
		else:
			_shuffle(xs, rng)
		for i in mini(int(R["exploits_per_game"]), xs.size()):
			var xid: String = xs[i]
			s.exploits.append(xid)
			s.unlocked[xid] = false
			s.xs[xid] = {"closed": false}
		for xid in s.exploits:
			_exploit(xid).setup(s)
	log_line(s, "Nuova partita: %d giocatori, tabellone lato %s. Exploit: %s" % [n, side,
		", ".join(s.exploits.map(func(x): return GameData.exploit_by_id[x]["name"]))])
	return s


static func board(s: Dictionary) -> Dictionary:
	return GameData.boards[s.side]


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


# ═════════════════════════════ VALORI DERIVATI ═════════════════════════════

## Totale grezzo di icone di un tipo (le icone oltre 15 non spostano il segnalino).
static func icons(s: Dictionary, p: int, key: String) -> int:
	var pl: Dictionary = s.players[p]
	var total := 0
	for b in pl.buildings:
		total += int(GameData.buildings[b.id]["icons"].get(key, 0))
	for cid in pl.cards:
		total += int(GameData.cards[cid]["icons"].get(key, 0))
	if pl.gov != "":
		total += int(GameData.cards[pl.gov]["icons"].get(key, 0))
	for t in pl.tokens:
		if t.has("icons"):
			total += int(t["icons"].get(key, 0))
	for x in s.exploits:
		total += _exploit(x).attr_bonus(s, p, key)
	return total


static func attr(s: Dictionary, p: int, key: String) -> int:
	return clampi(icons(s, p, key), 0, int(GameData.rules["track_max"]))


static func industry_level(s, p) -> int: return GameData.table("industry_level", attr(s, p, "industry"))
static func growth(s, p) -> int: return GameData.table("growth", attr(s, p, "culture"))
static func salary(s, p) -> int: return GameData.table("salary", attr(s, p, "finance"))


static func card_limit(s: Dictionary, p: int) -> int:
	var lim := GameData.table("card_limit", attr(s, p, "influence"))
	var mx := int(GameData.rules["card_limit_max"])
	var has_slavery := false
	for cid in s.players[p].cards:
		if GameData.cards[cid].get("slavery", false):
			has_slavery = true
	# Lo spazio "catena" della plancia: una carta Schiavitù in più, senza superare 5.
	if has_slavery and lim < mx:
		lim += 1
	return lim


static func presence(s: Dictionary, p: int, rid: String, for_draw: bool = false) -> int:
	var r: Dictionary = s.regions[rid]
	var n: int = r.track.count(p) + int(r.sea[p])
	for nid in board(s)["region_nodes"][rid]:
		if s.nodes[nid].owner == p:
			n += 1
	if for_draw:
		for x in s.exploits:
			if x_available(s, p, x):
				n += _exploit(x).draw_presence_bonus(s, p)
	return n


static func x_available(s: Dictionary, p: int, x: String) -> bool:
	if not s.unlocked.get(x, false) or s.xs[x].get("closed", false):
		return false
	for rid in GameData.exploit_by_id[x]["regions"]:
		if presence(s, p, rid) == 0:
			return false
	return true


## Idoneità per il punteggio finale (anche se l'Exploit è stato "chiuso").
static func x_eligible(s: Dictionary, p: int, x: String) -> bool:
	if not s.unlocked.get(x, false):
		return false
	for rid in GameData.exploit_by_id[x]["regions"]:
		if presence(s, p, rid) == 0:
			return false
	return true


static func order(s: Dictionary, i: int) -> int:
	return (s.first + i) % s.n


static func building_has(bid: String, a: String) -> bool:
	for st in GameData.buildings[bid]["actions"]:
		if a in String(st).split("|"):
			return true
	return false


static func symbol_count(bid: String, a: String) -> int:
	var n := 0
	for st in GameData.buildings[bid]["actions"]:
		if a in String(st).split("|"):
			n += 1
	return n


static func link_blocked(s: Dictionary, li: int) -> bool:
	for x in s.exploits:
		if _exploit(x).link_blocked(s, li):
			return true
	return false


static func link_owner(s: Dictionary, li: int) -> int:
	var l: Dictionary = board(s)["link"][li]
	var oa: int = s.nodes[l["a"]].owner
	if oa < 0 or s.nodes[l["b"]].owner != oa or link_blocked(s, li):
		return -1
	return oa


static func node_protected(s: Dictionary, nid: String) -> bool:
	if s.nodes[nid].get("fort", false):
		return true
	for x in s.exploits:
		if _exploit(x).node_protected(s, nid):
			return true
	return false


static func node_blocked(s: Dictionary, nid: String) -> bool:
	for x in s.exploits:
		if _exploit(x).node_blocked(s, nid):
			return true
	return false


# ═════════════════════════════ DECISIONI ═════════════════════════════

static func current_decision(s: Dictionary) -> Dictionary:
	var guard := 0
	while guard < 2000:
		guard += 1
		if not s.stack.is_empty():
			var fr: Dictionary = s.stack.back()
			var moves := frame_moves(s, fr)
			if moves.is_empty() or (moves.size() == 1 and moves[0]["t"] == "skip"):
				pop_frame(s)
				continue
			return {"p": fr.p, "type": "frame", "frame": fr.get("f", ""), "moves": moves}
		match s.phase:
			"build":
				if s.idx >= s.n:
					s.phase = "growth"
					s.idx = 0
					continue
				var p := order(s, s.idx)
				var moves := build_moves(s, p)
				if moves.is_empty():
					log_line(s, "%s non può costruire." % s.players[p].name)
					s.idx += 1
					continue
				if moves.size() == 1:
					apply_build(s, p, moves[0].b)
					continue
				return {"p": p, "type": "build", "moves": moves}
			"growth":
				if s.idx >= s.n:
					s.phase = "salary"
					s.idx = 0
					s.salary_left = -1
					continue
				var p := order(s, s.idx)
				var gm := growth_moves(s, p)
				if not gm.is_empty():
					return {"p": p, "type": "growth", "moves": gm}
				_do_growth(s, p, 0)
				s.idx += 1
				continue
			"salary":
				if s.idx >= s.n:
					s.phase = "action"
					s.turn_i = 0
					for i in s.n:
						s.passed[i] = false
					continue
				var p := order(s, s.idx)
				if s.salary_left < 0:
					for x in s.exploits:
						_exploit(x).on_salary(s, p)
					s.salary_left = salary(s, p) + int(s.players[p].get("galleon_salary", 0))
				var kept: Array = s.get("salary_keep", [])
				var cand := []
				var bs: Array = s.players[p].buildings
				for i in bs.size():
					if bs[i].occ == "disc" and not kept.has(i):
						cand.append(i)
				# Se i pagamenti bastano si libera tutto da solo; altrimenti si sceglie cosa resta impegnato.
				if cand.size() <= s.salary_left or s.salary_left <= 0:
					if s.salary_left <= 0:
						cand = []
					for bi in cand:
						free_building(s, p, bi)
					if not cand.is_empty():
						log_line(s, "%s paga: libera %d edifici%s." % [s.players[p].name, cand.size(),
							"" if kept.is_empty() else ", %d restano impegnati" % kept.size()])
					s.idx += 1
					s.salary_left = -1
					s["salary_keep"] = []
					continue
				# Si chiede la scelta più breve: quali tenere impegnati oppure quali liberare.
				var need_keep: int = cand.size() - s.salary_left
				var mode := "keep" if need_keep <= s.salary_left else "salary"
				var moves := []
				for bi in cand:
					moves.append({"t": mode, "bi": bi})
				return {"p": p, "type": "salary", "mode": mode, "moves": moves}
			"action":
				if not s.passed.has(false):
					s.phase = "discard"
					s.idx = 0
					continue
				var p := order(s, s.turn_i)
				if s.passed[p]:
					s.turn_i = (s.turn_i + 1) % s.n
					continue
				return {"p": p, "type": "action", "moves": action_moves(s, p)}
			"discard":
				if s.idx >= s.n:
					_end_round(s)
					continue
				var p := order(s, s.idx)
				if s.players[p].cards.size() > card_limit(s, p):
					var moves := []
					for cid in s.players[p].cards:
						moves.append({"t": "discard", "c": cid})
					return {"p": p, "type": "discard", "moves": moves}
				s.idx += 1
				continue
			"game_over":
				return {"p": -1, "type": "game_over", "moves": []}
	push_error("current_decision: ciclo infinito")
	return {"p": -1, "type": "error", "moves": []}


static func build_moves(s: Dictionary, p: int) -> Array:
	if s.players[p].buildings.size() >= int(GameData.rules["building_slots"]):
		return []
	var lvl := industry_level(s, p)
	var out := []
	for bid in GameData.building_order:
		if not s.bsupply.has(bid) or s.bsupply[bid] <= 0:
			continue
		if int(GameData.buildings[bid]["level"]) > lvl:
			continue
		out.append({"t": "build", "b": bid})
	# Compagnia privilegiata al posto di un edificio: 6+ presenza nella regione, una a testa.
	if String(s.players[p].get("charter", "")) == "":
		for rid in s.get("charters", {}):
			var cb: String = s.charters[rid]
			if presence(s, p, rid) >= int(GameData.buildings[cb].get("presence", 6)):
				out.append({"t": "build", "b": cb})
	return out


static func growth_moves(s: Dictionary, p: int) -> Array:
	var g := int(s.players[p].get("galleons", 0))
	if g <= 0:
		return []
	var occupied := 0
	for b in s.players[p].buildings:
		if b.occ == "disc":
			occupied += 1
	if salary(s, p) >= occupied:
		return []  # i pagamenti bastano già: i Galeoni diventano popolazione
	var out := []
	for k in g + 1:
		out.append({"t": "galleon", "k": k})
	return out


## Lavoratori disponibili per attivare un edificio: dischi dal porto o cannoni (Salnitro).
static func workers_for(s: Dictionary, p: int, bi: int) -> Array:
	var pl: Dictionary = s.players[p]
	var out := []
	if pl.harbor >= 1:
		out.append("disc")
	var bid: String = pl.buildings[bi].id
	if building_has(bid, "attack") and free_cannons(s, p) > 0 and s.xs.has("saltpeter") and x_available(s, p, "saltpeter"):
		out.append("cannon")
	return out


static func free_cannons(s: Dictionary, p: int) -> int:
	var pl: Dictionary = s.players[p]
	var used := 0
	for b in pl.buildings:
		if b.occ == "cannon":
			used += 1
	return int(pl.get("cannons", 0)) - used


static func action_moves(s: Dictionary, p: int) -> Array:
	var pl: Dictionary = s.players[p]
	var out := []
	for bi in pl.buildings.size():
		var b: Dictionary = pl.buildings[bi]
		if b.occ != "":
			continue
		var steps: Array = GameData.buildings[b.id]["actions"]
		if steps.is_empty():
			continue
		for w in workers_for(s, p, bi):
			var h_after: int = pl.harbor - (1 if w == "disc" else 0)
			var ctx := {"bi": bi, "harbor": h_after}
			var seen := {}
			for o in options(s, p, String(steps[0]).split("|"), ctx):
				var k := str(o)
				if seen.has(k):
					continue
				seen[k] = true
				out.append({"t": "activate", "bi": bi, "w": w, "o": o})
			if seen.is_empty() and steps.size() > 1:
				# Primo passo impossibile ma il secondo sì: si può attivare saltando il primo.
				out.append({"t": "activate", "bi": bi, "w": w, "o": {"a": "skip"}})
	var tok_seen := {}
	for ti in pl.tokens.size():
		var tok: Dictionary = pl.tokens[ti]
		if not tok.has("action"):
			continue
		if tok_seen.has(tok["action"]):
			continue
		tok_seen[tok["action"]] = true
		for o in options(s, p, String(tok["action"]).split("|"), {"bi": -1, "harbor": pl.harbor}):
			out.append({"t": "token", "ti": ti, "o": o})
	out.append({"t": "pass"})
	return out


## Opzioni elementari per uno o più tipi d'azione (normali + alternative Exploit).
static func options(s: Dictionary, p: int, types: Array, ctx: Dictionary) -> Array:
	var out := []
	for a in types:
		out.append_array(std_options(s, p, a, ctx))
		if not ctx.get("standard", false):
			for x in s.exploits:
				if x_available(s, p, x):
					out.append_array(_exploit(x).options(s, p, a, ctx))
	return out


static func _harbor(s: Dictionary, p: int, ctx: Dictionary) -> int:
	return int(ctx.get("harbor", s.players[p].harbor))


static func std_options(s: Dictionary, p: int, a: String, ctx: Dictionary) -> Array:
	var B := board(s)
	var out := []
	var h := _harbor(s, p, ctx)
	var only: String = ctx.get("region", "")
	match a:
		"ship":
			if h < 1:
				return out
			for rid in s.regions:
				if only != "" and rid != only:
					continue
				var r: Dictionary = s.regions[rid]
				if not r.open and r.track.size() < r.track_tokens.size():
					out.append({"a": "ship", "k": "track", "r": rid})
				if r.open and B["region"][rid]["sea"] != null and not ctx.get("no_sea", false):
					out.append({"a": "ship", "k": "sea", "r": rid})
			for nid in B["node"]:
				var nd: Dictionary = B["node"][nid]
				if nd["kind"] != "fleet" or s.nodes[nid].owner != -1:
					continue
				if only != "" and nd["region"] != only:
					continue
				if s.regions[nd["region"]].open and not node_blocked(s, nid):
					out.append({"a": "ship", "k": "fleet", "n": nid})
		"occupy":
			if h < 1:
				return out
			for nid in B["node"]:
				var nd: Dictionary = B["node"][nid]
				if nd["kind"] != "city" or s.nodes[nid].owner != -1 or node_blocked(s, nid):
					continue
				var rid: String = nd["region"]
				if only != "" and rid != only:
					continue
				if not s.regions[rid].open:
					continue
				if rid != "europe" and presence(s, p, rid) == 0 and not ctx.get("any_open", false):
					continue
				out.append({"a": "occupy", "n": nid})
		"attack":
			if h < 1:
				return out
			for nid in attack_targets(s, p, only):
				if h >= 1 + casualties(s, p, nid):
					out.append({"a": "attack", "n": nid})
		"draw":
			for rid in s.regions:
				if only != "" and rid != only:
					continue
				var pres := presence(s, p, rid, true)
				var r: Dictionary = s.regions[rid]
				for d in r.decks:
					var deck: Array = r.decks[d]
					if not deck.is_empty() and int(GameData.cards[deck.back()]["value"]) <= pres:
						out.append({"a": "draw", "r": rid, "d": d})
			if only == "" or only == "europe":
				var pe := presence(s, p, "europe", true)
				var seen := {}
				for cid in s.discard:
					if int(GameData.cards[cid]["value"]) <= pe and not seen.has(cid):
						seen[cid] = true
						out.append({"a": "draw", "k": "discard", "c": cid})
		"payment":
			var bs: Array = s.players[p].buildings
			for bi in bs.size():
				if bi == int(ctx.get("bi", -1)) or bs[bi].occ != "disc":
					continue
				if building_has(bs[bi].id, "payment") or GameData.buildings[bs[bi].id].get("no_pay", false):
					continue
				out.append({"a": "payment", "bi": bi})
	return out


static func attack_targets(s: Dictionary, p: int, only: String = "") -> Array:
	var B := board(s)
	var out := []
	for nid in B["node"]:
		var o: int = s.nodes[nid].owner
		if o < 0 or o == p:
			continue
		var rid: String = B["node"][nid]["region"]
		if only != "" and rid != only:
			continue
		if not s.regions[rid].open or presence(s, p, rid) == 0:
			continue
		if node_protected(s, nid):
			continue
		out.append(nid)
	return out


static func casualties(s: Dictionary, p: int, nid: String) -> int:
	for x in s.exploits:
		if x_available(s, p, x) and _exploit(x).attack_without_casualty(s, p, nid):
			return 0
	return int(GameData.rules["attack_casualties"])


# ═════════════════════════════ PILA DI FRAME ═════════════════════════════

## Frame "steps": azioni normali da eseguire (passi successivi di un edificio, azioni immediate).
## Frame "x": sotto-decisioni di un Exploit.
static func push_frame(s: Dictionary, fr: Dictionary) -> void:
	s.stack.append(fr)


static func push_steps(s: Dictionary, p: int, steps: Array, ctx: Dictionary = {}) -> void:
	if steps.is_empty():
		return
	push_frame(s, {"f": "steps", "p": p, "steps": steps.duplicate(), "ctx": ctx})


static func pop_frame(s: Dictionary) -> void:
	var fr: Dictionary = s.stack.pop_back()
	if fr.get("f", "") == "steps" and fr.steps.size() > 1:
		fr.steps.remove_at(0)
		s.stack.append(fr)
		return
	_after_stack(s)


static func frame_moves(s: Dictionary, fr: Dictionary) -> Array:
	if fr.get("f", "") == "steps":
		var ctx: Dictionary = fr.get("ctx", {}).duplicate()
		ctx.erase("harbor")
		var out := []
		var seen := {}
		for o in options(s, fr.p, String(fr.steps[0]).split("|"), ctx):
			var k := str(o)
			if not seen.has(k):
				seen[k] = true
				out.append({"t": "opt", "o": o})
		out.append({"t": "skip"})
		return out
	return _exploit(fr.x).frame_moves(s, fr)


static func _after_stack(s: Dictionary) -> void:
	if s.stack.is_empty() and s.phase == "action":
		_next_turn(s)


# ═════════════════════════════ APPLICAZIONE ═════════════════════════════

static func apply(s: Dictionary, m: Dictionary) -> void:
	var d := current_decision(s)
	var p: int = d.p
	s.last = {"p": p, "m": m}
	match m["t"]:
		"build":
			apply_build(s, p, m.b)
		"galleon":
			_do_growth(s, p, int(m.k))
			s.idx += 1
		"keep":
			var kept: Array = s.get("salary_keep", [])
			kept.append(m.bi)
			s["salary_keep"] = kept
		"salary":
			free_building(s, p, m.bi)
			s.salary_left -= 1
			log_line(s, "%s paga: libera %s." % [s.players[p].name, bname(s, p, m.bi)])
		"activate":
			var pl: Dictionary = s.players[p]
			pl.buildings[m.bi].occ = m.w
			if m.w == "disc":
				pl.harbor -= 1
			log_line(s, "%s attiva %s%s." % [pl.name, bname(s, p, m.bi), " con un cannone" if m.w == "cannon" else ""])
			var steps: Array = GameData.buildings[pl.buildings[m.bi].id]["actions"]
			push_steps(s, p, steps.slice(1), {"bi": m.bi})
			if m.o.get("a", "") != "skip":
				exec_option(s, p, m.o, {"bi": m.bi})
			_after_stack(s)
		"token":
			var pl: Dictionary = s.players[p]
			var tok: Dictionary = pl.tokens[m.ti]
			pl.tokens.remove_at(m.ti)
			log_line(s, "%s usa un token %s." % [pl.name, GameData.token_text(tok)])
			exec_option(s, p, m.o, {"bi": -1})
			_after_stack(s)
		"opt":
			var fr: Dictionary = s.stack.back()
			# Il passo corrente è consumato prima di eseguire (l'opzione può impilare altro).
			s.stack.pop_back()
			if fr.steps.size() > 1:
				fr.steps.remove_at(0)
				s.stack.append(fr)
			exec_option(s, p, m.o, fr.get("ctx", {}))
			_after_stack(s)
		"skip":
			pop_frame(s)
		"pass":
			s.passed[p] = true
			log_line(s, "%s passa." % s.players[p].name)
			_next_turn(s)
		"discard":
			discard_card(s, p, m.c)
		_:
			if not s.stack.is_empty() and s.stack.back().get("f", "") == "x":
				var fr: Dictionary = s.stack.back()
				_exploit(fr.x).frame_apply(s, fr, m)
				_after_stack(s)
			else:
				push_error("Mossa sconosciuta: " + str(m))


static func apply_build(s: Dictionary, p: int, bid: String) -> void:
	var b: Dictionary = GameData.buildings[bid]
	if b.has("charter"):
		s.charters.erase(b["charter"])
		s.players[p]["charter"] = bid
		log_line(s, "%s prende la %s." % [s.players[p].name, b["name"]])
	else:
		s.bsupply[bid] -= 1
		log_line(s, "%s costruisce %s." % [s.players[p].name, b["name"]])
	s.players[p].buildings.append({"id": bid, "occ": ""})
	s.idx += 1


static func _do_growth(s: Dictionary, p: int, galleon_salary: int) -> void:
	var pl: Dictionary = s.players[p]
	var g := int(pl.get("galleons", 0))
	pl["galleon_salary"] = galleon_salary
	var amt := mini(growth(s, p) + g - galleon_salary, pl.supply)
	pl.supply -= amt
	pl.harbor += amt
	log_line(s, "%s: crescita +%d popolazione." % [pl.name, amt])


static func _next_turn(s: Dictionary) -> void:
	if not s.stack.is_empty():
		return
	for k in s.n:
		s.turn_i = (s.turn_i + 1) % s.n
		if not s.passed[order(s, s.turn_i)]:
			return


static func exec_option(s: Dictionary, p: int, o: Dictionary, ctx: Dictionary) -> void:
	if o.has("x"):
		log_line(s, "  ⚑ %s" % GameData.exploit_by_id[o.x]["name"])
		var use: Dictionary = s.get("xuse", {})
		use[o.x + ":" + String(o.get("k", ""))] = int(use.get(o.x + ":" + String(o.get("k", "")), 0)) + 1
		s["xuse"] = use
		_exploit(o.x).execute(s, p, o, ctx)
		return
	var pl: Dictionary = s.players[p]
	match o.a:
		"ship":
			match o.k:
				"track":
					ship_to_track(s, p, o.r)
				"sea":
					pl.harbor -= 1
					s.regions[o.r].sea[p] += 1
					log_line(s, "  → nave in mare aperto: %s." % GameData.region_name(o.r))
				"fleet":
					pl.harbor -= 1
					set_node_owner(s, o.n, p)
					log_line(s, "  → nave nello spazio flotta %s." % node_label(s, o.n))
		"occupy":
			pl.harbor -= 1
			set_node_owner(s, o.n, p)
			log_line(s, "  → occupa %s." % node_label(s, o.n))
		"attack":
			do_attack(s, p, o.n, "harbor")
		"draw":
			if o.get("k", "") == "discard":
				s.discard.erase(o.c)
				gain_card(s, p, o.c, "dalla pila degli scarti")
			else:
				draw_top(s, p, o.r, o.d)
		"payment":
			free_building(s, p, int(o.bi))
			log_line(s, "  → pagamento: libera %s." % bname(s, p, int(o.bi)))


# ───────────── effetti elementari (usati anche dagli Exploit) ─────────────

static func ship_to_track(s: Dictionary, p: int, rid: String) -> void:
	var r: Dictionary = s.regions[rid]
	s.players[p].harbor -= 1
	var idx: int = r.track.size()
	r.track.append(p)
	take_token(s, p, r.track_tokens[idx])
	r.track_tokens[idx] = null
	log_line(s, "  → nave verso %s (%d/%d)." % [GameData.region_name(rid), r.track.size(), r.track_tokens.size()])
	if r.track.size() == r.track_tokens.size():
		open_region(s, rid)


## Attacco: il disco del difensore torna alla sua riserva; l'attaccante piazza un disco
## e subisce le perdite. casualty_mode: "harbor" (normale) o "none" (già gestite).
static func do_attack(s: Dictionary, p: int, nid: String, casualty_mode: String = "harbor") -> void:
	var pl: Dictionary = s.players[p]
	var defender: int = s.nodes[nid].owner
	var cas := casualties(s, p, nid) if casualty_mode == "harbor" else 0
	pl.harbor -= 1
	for k in cas:
		lose_disc(s, p, "harbor")
	s.nodes[nid].owner = -1
	lose_disc(s, defender, "board")
	set_node_owner(s, nid, p)
	log_line(s, "  → attacca %s, scacciando %s%s." % [node_label(s, nid), s.players[defender].name,
		"" if cas > 0 else " (senza perdite)"])


## Un disco perso in combattimento: va in riserva, o diventa un token col Memoriale.
static func lose_disc(s: Dictionary, p: int, from: String) -> void:
	var pl: Dictionary = s.players[p]
	if from == "harbor":
		pl.harbor -= 1
	var memorial := false
	for b in pl.buildings:
		if b.id == "memorial":
			memorial = true
	if memorial:
		var best := "industry"
		var bv := 99
		for t in GameData.TRACKS:
			var v := attr(s, p, t)
			if v < bv:
				bv = v
				best = t
		pl.tokens.append({"icons": {best: 1}, "disc": true})
		log_line(s, "  (Memoriale: la perdita di %s diventa %s)" % [pl.name, GameData.ICON_NAMES[best]])
	else:
		pl.supply += 1


static func set_node_owner(s: Dictionary, nid: String, p: int) -> void:
	s.nodes[nid].owner = p
	var t = s.nodes[nid].token
	if t != null and p >= 0:
		take_token(s, p, t)
		s.nodes[nid].token = null
	update_links(s, nid)


static func update_links(s: Dictionary, nid: String) -> void:
	var B := board(s)
	for li in B["node_links"][nid]:
		var o := link_owner(s, li)
		var ls: Dictionary = s.links[li]
		if o >= 0 and not ls.claimed:
			ls.claimed = true
			if ls.token != null:
				take_token(s, o, ls.token)
				ls.token = null
			var l: Dictionary = B["link"][li]
			log_line(s, "  → %s controlla il collegamento %s–%s." % [s.players[o].name, node_label(s, l["a"]), node_label(s, l["b"])])


static func take_token(s: Dictionary, p: int, tok) -> void:
	if tok == null:
		return
	s.players[p].tokens.append(tok.duplicate())


static func free_building(s: Dictionary, p: int, bi: int) -> void:
	var b: Dictionary = s.players[p].buildings[bi]
	if b.occ == "disc":
		s.players[p].harbor += 1
	b.occ = ""


static func open_region(s: Dictionary, rid: String) -> void:
	var r: Dictionary = s.regions[rid]
	if r.open:
		return
	r.open = true
	log_line(s, "★ %s si apre!" % GameData.region_name(rid))
	if r.governor != "":
		var best := -1
		var best_n := 0
		for p in s.n:
			var c: int = r.track.count(p)
			# Pareggio: vince chi tra i pari ha piazzato per ultimo sul tracciato.
			if c > best_n or (c == best_n and c > 0 and r.track.rfind(p) > r.track.rfind(best)):
				best = p
				best_n = c
		if best >= 0:
			var pl: Dictionary = s.players[best]
			if pl.gov == "":
				pl.gov = r.governor
			else:
				pl.cards.append(r.governor)
			log_line(s, "  Il Governatore va a %s." % pl.name)
			r.governor = ""
	for x in s.exploits:
		if s.unlocked[x]:
			continue
		var all_open := true
		for xr in GameData.exploit_by_id[x]["regions"]:
			if not s.regions[xr].open:
				all_open = false
		if all_open:
			s.unlocked[x] = true
			log_line(s, "⚑ Exploit sbloccato: %s" % GameData.exploit_by_id[x]["name"])
			_exploit(x).on_unlock(s)


static func draw_top(s: Dictionary, p: int, rid: String, d: String) -> void:
	var deck: Array = s.regions[rid].decks[d]
	if deck.is_empty():
		return
	var cid: String = deck.pop_back()
	gain_card(s, p, cid, "da " + GameData.region_name(rid) + (" (schiavitù)" if d == "slavery" else ""))


static func can_draw_top(s: Dictionary, p: int, rid: String) -> bool:
	var deck: Array = s.regions[rid].decks["main"]
	return not deck.is_empty() and int(GameData.cards[deck.back()]["value"]) <= presence(s, p, rid, true)


static func gain_card(s: Dictionary, p: int, cid: String, from: String) -> void:
	var pl: Dictionary = s.players[p]
	var c: Dictionary = GameData.cards[cid]
	pl.cards.append(cid)
	log_line(s, "  → %s prende %s %s %s." % [pl.name, GameData.region_name(c["region"]), str(int(c["value"])) if not c.get("governor", false) else "Governatore", from])
	if c.get("bonus_disc", false) and not pl.disc_cards.has(cid) and pl.supply > 0:
		pl.disc_cards[cid] = true
		pl.supply -= 1
		pl.harbor += 1
		log_line(s, "    +1 popolazione dalla carta.")
	if c.get("abolition", false) and not s.abolished:
		abolition(s)


static func abolition(s: Dictionary) -> void:
	s.abolished = true
	log_line(s, "⚖ Abolizione della schiavitù.")
	for pl in s.players:
		var keep := []
		for cid in pl.cards:
			if GameData.cards[cid].get("slavery", false):
				pl.slavery_aside += 1
			else:
				keep.append(cid)
		pl.cards = keep
	s.regions["europe"].decks["slavery"] = []
	var keep_d := []
	for cid in s.discard:
		if not GameData.cards[cid].get("slavery", false):
			keep_d.append(cid)
	s.discard = keep_d


static func discard_card(s: Dictionary, p: int, cid: String) -> void:
	var pl: Dictionary = s.players[p]
	pl.cards.erase(cid)
	var c: Dictionary = GameData.cards[cid]
	log_line(s, "%s scarta %s %s." % [pl.name, GameData.region_name(c["region"]), "Governatore" if c.get("governor", false) else str(int(c["value"]))])
	if c.get("slavery", false):
		pl.slavery_aside += 1
	elif c.get("governor", false):
		pass  # i Governatori scartati escono dal gioco
	else:
		s.discard.append(cid)


static func _end_round(s: Dictionary) -> void:
	log_line(s, "— Fine del round %d —" % s.round)
	s.round += 1
	var full := true
	for pl in s.players:
		if pl.buildings.size() < int(GameData.rules["building_slots"]):
			full = false
	if s.round > int(GameData.rules["rounds"]) or full:
		s.phase = "game_over"
		var sc := []
		for p in s.n:
			sc.append("%s %d" % [s.players[p].name, score(s, p)["total"]])
		log_line(s, "Partita finita. " + ", ".join(sc))
		return
	s.first = (s.first + 1) % s.n
	s.phase = "build"
	s.idx = 0


# ───────────── utilità per gli Exploit ─────────────

static func icon_token_index(s: Dictionary, p: int, key: String) -> int:
	var toks: Array = s.players[p].tokens
	# preferisce i token veri a quelli nati da dischi
	for pass_i in 2:
		for i in toks.size():
			var t: Dictionary = toks[i]
			if t.has("icons") and int(t["icons"].get(key, 0)) > 0 and (pass_i == 1 or not t.get("disc", false)):
				return i
	return -1


static func has_icon_token(s: Dictionary, p: int, key: String) -> bool:
	return icon_token_index(s, p, key) >= 0


static func spend_icon_token(s: Dictionary, p: int, key: String) -> bool:
	var i := icon_token_index(s, p, key)
	if i < 0:
		return false
	var t: Dictionary = s.players[p].tokens[i]
	s.players[p].tokens.remove_at(i)
	if t.get("disc", false):
		s.players[p].supply += 1
	return true


static func gain_discs(s: Dictionary, p: int, n: int) -> int:
	var pl: Dictionary = s.players[p]
	var k := mini(n, pl.supply)
	pl.supply -= k
	pl.harbor += k
	return k


## Fortificazioni condivise fra Main spagnolo e Compagnia olandese (10 pezzi).
static func forts_left(s: Dictionary) -> int:
	return int(s.get("forts_left", 10))


static func use_fort(s: Dictionary) -> void:
	s["forts_left"] = forts_left(s) - 1


static func region_of(s: Dictionary, nid: String) -> String:
	return board(s)["node"][nid]["region"]


# ═════════════════════════════ PUNTEGGIO ═════════════════════════════

static func score(s: Dictionary, p: int) -> Dictionary:
	var R := GameData.rules
	var B := board(s)
	var pl: Dictionary = s.players[p]
	var res := {}
	var tracks := 0
	for t in GameData.TRACKS:
		tracks += GameData.table("glory_at", attr(s, p, t))
	res["tracciati"] = tracks
	var cities := 0
	for nid in s.nodes:
		if s.nodes[nid].owner == p:
			cities += int(B["node"][nid]["glory"])
	res["città"] = cities
	var links := 0
	for li in s.links.size():
		if link_owner(s, li) == p:
			links += int(R["link_glory"])
	res["collegamenti"] = links
	var g := 0
	var draw_symbols := 0
	var has_city_hall := false
	for b in pl.buildings:
		g += int(GameData.buildings[b.id]["icons"].get("glory", 0))
		draw_symbols += symbol_count(b.id, "draw")
		if b.id == "city_hall":
			has_city_hall = true
	if has_city_hall:
		g += draw_symbols
	res["edifici"] = g
	var cg := 0
	for cid in pl.cards:
		cg += int(GameData.cards[cid]["icons"].get("glory", 0))
	for t in pl.tokens:
		if t.has("icons"):
			cg += int(t["icons"].get("glory", 0))
	res["carte"] = cg
	res["Governatore"] = int(R["empty_governor_slot_glory"]) if pl.gov == "" else int(GameData.cards[pl.gov]["icons"].get("glory", 0))
	res["porto"] = int(pl.harbor / int(R["harbor_glory_per"]))
	res["schiavitù"] = -int(R["slavery_penalty"]) * int(pl.slavery_aside)
	var xg := int(pl.bonus_glory)
	for x in s.exploits:
		xg += _exploit(x).tile_glory(s, p)
		if x_eligible(s, p, x):
			xg += _exploit(x).end_glory(s, p)
	res["exploit"] = xg
	var tot := 0
	for k in res:
		tot += int(res[k])
	res["total"] = tot
	return res


static func region_table(count: int) -> int:
	var t: Dictionary = GameData.rules["region_table"]
	if count < 2:
		return 0
	return int(t.get(str(mini(count, 7)), 0))


## Dischi totali di un giocatore ovunque si trovino (controllo di conservazione).
static func disc_total(s: Dictionary, p: int) -> int:
	var pl: Dictionary = s.players[p]
	var n: int = pl.supply + pl.harbor
	for b in pl.buildings:
		if b.occ == "disc":
			n += 1
	for rid in s.regions:
		n += s.regions[rid].track.count(p) + int(s.regions[rid].sea[p])
	for nid in s.nodes:
		if s.nodes[nid].owner == p:
			n += 1
	for t in pl.tokens:
		if t.get("disc", false):
			n += 1
	for x in s.exploits:
		n += _exploit(x).discs_on_tile(s, p)
	return n


# ═════════════════════════════ EXPLOIT ═════════════════════════════

static func _exploit(id: String) -> ExploitBase:
	if not _xinst.has(id):
		var def: Dictionary = GameData.exploit_by_id[id]
		var inst: ExploitBase = load(def["script"]).new()
		inst.id = id
		inst.def = def
		_xinst[id] = inst
	return _xinst[id]


static func exploit(id: String) -> ExploitBase:
	return _exploit(id)


# ═════════════════════════════ TESTI ═════════════════════════════

static func bname(s: Dictionary, p: int, bi: int) -> String:
	return GameData.buildings[s.players[p].buildings[bi].id]["name"]


static func node_label(s: Dictionary, nid: String) -> String:
	var nd: Dictionary = board(s)["node"][nid]
	var kind := "città" if nd["kind"] == "city" else "flotta"
	return "%s (%s, %s)" % [kind, GameData.region_name(nd["region"]), nid]


static func log_line(s: Dictionary, msg: String) -> void:
	s.log.append(msg)
	if s.log.size() > LOG_MAX:
		s.log = s.log.slice(s.log.size() - LOG_MAX)


static func option_text(s: Dictionary, p: int, o: Dictionary) -> String:
	if o.has("x"):
		return GameData.exploit_by_id[o.x]["name"] + ": " + String(o.get("label", ""))
	match o.a:
		"skip":
			return "salta il primo passo"
		"ship":
			match o.k:
				"track":
					return "Navigare verso %s" % GameData.region_name(o.r)
				"sea":
					return "Navigare in mare aperto (%s)" % GameData.region_name(o.r)
				"fleet":
					return "Navigare nello spazio %s" % node_label(s, o.n)
		"occupy":
			return "Occupare %s" % node_label(s, o.n)
		"attack":
			return "Attaccare %s (di %s)" % [node_label(s, o.n), s.players[s.nodes[o.n].owner].name]
		"draw":
			if o.get("k", "") == "discard":
				var c: Dictionary = GameData.cards[o.c]
				return "Pescare dagli scarti: %s %d" % [GameData.region_name(c["region"]), int(c["value"])]
			var deck: Array = s.regions[o.r].decks[o.d]
			var top: Dictionary = GameData.cards[deck.back()]
			return "Pescare %s %d (%s)" % [GameData.region_name(o.r) + (" schiavitù" if o.d == "slavery" else ""),
				int(top["value"]), GameData.icons_text(top["icons"])]
		"payment":
			return "Pagamento: libera %s" % bname(s, p, int(o.bi))
	return str(o)


static func describe(s: Dictionary, p: int, m: Dictionary) -> String:
	match m["t"]:
		"build":
			var b: Dictionary = GameData.buildings[m.b]
			if b.has("charter"):
				return "Prendi la %s — %s — %s" % [b["name"], GameData.icons_text(b["icons"]), GameData.steps_text(b["actions"])]
			return "Costruisci %s (liv. %d) — %s — %s" % [b["name"], int(b["level"]),
				GameData.icons_text(b["icons"]) if not b["icons"].is_empty() else "nessuna icona", GameData.steps_text(b["actions"])]
		"galleon":
			return "Galeoni: %d come pagamenti, il resto come popolazione" % int(m.k)
		"keep":
			return "Tieni impegnato %s (#%d)" % [bname(s, p, m.bi), m.bi + 1]
		"salary":
			return "Libera %s (#%d)" % [bname(s, p, m.bi), m.bi + 1]
		"activate":
			return "%s%s → %s" % [bname(s, p, m.bi), " (cannone)" if m.w == "cannon" else "", option_text(s, p, m.o)]
		"token":
			return "Token → %s" % option_text(s, p, m.o)
		"opt":
			return option_text(s, p, m.o)
		"skip":
			return "Salta"
		"pass":
			return "Passa"
		"discard":
			var c: Dictionary = GameData.cards[m.c]
			return "Scarta %s %s (%s)" % [GameData.region_name(c["region"]), "Gov." if c.get("governor", false) else str(int(c["value"])),
				GameData.icons_text(c["icons"])]
	return String(m.get("label", str(m)))


## Bersaglio cliccabile di una mossa. Mappa: node:, sea:, region: (tracciato), deck:rid/d, discard.
## Plancia: bld:<indice edificio>, card:<id carta>.
static func move_target(m: Dictionary) -> String:
	match m["t"]:
		"keep", "salary":
			return "bld:%d" % int(m.bi)
		"discard":
			return "card:" + String(m.c)
		"build":
			var bd: Dictionary = GameData.buildings[m.b]
			if bd.has("charter"):
				return "charter:" + String(bd["charter"])
			return "supply:" + String(m.b)
	var o: Dictionary = m.get("o", m)
	var a: String = o.get("a", "")
	var k: String = o.get("k", "")
	if a == "payment" and o.has("bi") and not o.has("x"):
		return "bld:%d" % int(o.bi)
	if a == "draw" and not o.has("x"):
		if k == "discard":
			return "discard"
		return "deck:%s/%s" % [o.r, o.d]
	if o.has("n"):
		return "node:" + String(o.n)
	if o.has("to"):
		return "sea:" + String(o.to)
	if o.has("r") and String(o.r) != "":
		if k in ["sea", "sea_attack", "sea_draw"]:
			return "sea:" + String(o.r)
		if o.has("d"):
			return "deck:%s/%s" % [o.r, o.d]
		return "region:" + String(o.r)
	if o.has("x"):
		return "x:" + String(o.x)   # si gioca cliccando la tessera dell'Exploit
	return ""
