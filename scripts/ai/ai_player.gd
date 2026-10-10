class_name AIPlayer
extends RefCounted
## IA euristica: per ogni mossa legale simula l'esito su una copia dello stato e la valuta.
## Livello 1 = principiante (molto rumore), 2 = normale, 3 = esperta (con un passo di
## anticipo sulle sotto-decisioni dello stesso giocatore).
## I pesi sono tutti in W: il primo posto da ritoccare dopo le partite di prova.

const W := {
	"glory": 1.0,
	"growth": 0.32,            # per round rimanente, per disco di crescita
	"salary": 0.28,            # per round rimanente, per pagamento utile
	"card_limit": 0.22,        # per round rimanente
	"industry_level": 0.7,     # accesso a edifici migliori (finché si costruisce)
	"building_action": 0.26,   # per round rimanente, per passo d'azione dell'edificio
	"harbor": 0.22,
	"action_token": 0.6,
	"free_building": 0.2,
	"governor_race": 0.9,      # maggioranza su un tracciato ancora chiuso
	"presence_closed": 0.3,
	"presence_open": 0.18,
	"exploit_access": 0.8,     # presenza in entrambe le regioni di un Exploit
	"over_limit": 0.9,
	"rival": 0.3,
	"charter_progress": 12.0,   # avvicinarsi alle 6 presenze che sbloccano una Compagnia privilegiata
}
const NOISE := [0.0, 1.2, 0.5, 0.1]
const MAX_EVAL := 220          # oltre questo numero di mosse si campiona

var rng := RandomNumberGenerator.new()


func _init(seed_value: int = -1) -> void:
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()


func choose(s: Dictionary, decision: Dictionary) -> Dictionary:
	var moves: Array = decision.moves
	if moves.size() == 1:
		return moves[0]
	var p: int = decision.p
	var level: int = clampi(int(s.players[p].get("ai_level", 2)), 0, 3)
	var noise: float = NOISE[level]
	var pool := moves
	if moves.size() > MAX_EVAL:
		pool = []
		var idx := range(moves.size())
		for i in range(idx.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t = idx[i]
			idx[i] = idx[j]
			idx[j] = t
		for i in MAX_EVAL:
			pool.append(moves[idx[i]])
		for m in moves:
			if m["t"] == "pass" and not pool.has(m):
				pool.append(m)
	var best: Dictionary = pool[0]
	var best_v := -INF
	for m in pool:
		var v := _value_after(s, p, m, level >= 3)
		v += rng.randf_range(-noise, noise)
		if v > best_v:
			best_v = v
			best = m
	return best


func _value_after(s: Dictionary, p: int, m: Dictionary, lookahead: bool) -> float:
	var c := clone(s)
	Rules.apply(c, m)
	if lookahead:
		var d := Rules.current_decision(c)
		if d.type == "frame" and d.p == p and d.moves.size() <= 60:
			var bv := -INF
			for m2 in d.moves:
				var c2 := clone(c)
				Rules.apply(c2, m2)
				bv = maxf(bv, evaluate(c2, p))
			return bv
	return evaluate(c, p)


static func clone(s: Dictionary) -> Dictionary:
	var lg = s.log
	s.log = []
	var c: Dictionary = s.duplicate(true)
	s.log = lg
	return c


static func evaluate(s: Dictionary, p: int) -> float:
	var mine := _raw(s, p)
	var rival := -INF
	for q in s.n:
		if q != p:
			rival = maxf(rival, _raw(s, q))
	if rival == -INF:
		rival = 0.0
	return mine - W.rival * rival


## Valore "liscio" di una tabella a scalini: anticipa una parte del prossimo gradino.
static func smooth(name: String, v: int) -> float:
	var t: Array = GameData.rules[name]
	v = clampi(v, 0, t.size() - 1)
	var cur := float(t[v])
	var j := v + 1
	while j < t.size() and t[j] == t[v]:
		j += 1
	if j >= t.size():
		return cur
	var lo := v
	while lo > 0 and t[lo - 1] == t[v]:
		lo -= 1
	return cur + (float(t[j]) - cur) * float(v - lo + 1) / float(j - lo) * 0.8


static func _raw(s: Dictionary, p: int) -> float:
	var R := GameData.rules
	var rounds_left := maxi(0, int(R["rounds"]) - int(s.round) + (1 if s.phase != "game_over" else 0))
	var pl: Dictionary = s.players[p]
	var sc := Rules.score(s, p)
	if rounds_left == 0:
		return float(sc["total"])
	# A partita in corso: niente Gloria "a scalini" per porto e tracciati, si usano valori continui.
	var v: float = float(sc["total"] - sc["porto"] - sc["tracciati"]) * W.glory
	var rl := float(rounds_left)
	for t in GameData.TRACKS:
		v += smooth("glory_at", Rules.attr(s, p, t))
	var action_buildings := 0
	for b in pl.buildings:
		if not GameData.buildings[b.id]["actions"].is_empty():
			action_buildings += 1
	v += rl * (W.growth * smooth("growth", Rules.attr(s, p, "culture"))
		+ W.salary * minf(smooth("salary", Rules.attr(s, p, "finance")), float(action_buildings))
		+ W.card_limit * smooth("card_limit", Rules.attr(s, p, "influence")))
	v += W.industry_level * smooth("industry_level", Rules.attr(s, p, "industry")) * clampf(rl - 1.0, 0.0, 3.0) / 3.0
	for b in pl.buildings:
		for st in GameData.buildings[b.id]["actions"]:
			v += W.building_action * rl * (0.5 if st == "payment" else 1.0)
	v += pl.harbor * W.harbor * minf(1.0, rl / 2.0)
	for t in pl.tokens:
		if t.has("action"):
			v += W.action_token
	for b in pl.buildings:
		if b.occ == "" and not GameData.buildings[b.id]["actions"].is_empty():
			v += W.free_building
	for rid in s.regions:
		var r: Dictionary = s.regions[rid]
		var mine := Rules.presence(s, p, rid)
		if mine == 0:
			continue
		if not r.open:
			var best_other := 0
			for q in s.n:
				if q != p:
					best_other = maxi(best_other, r.track.count(q))
			if r.track.count(p) >= best_other and r.governor != "":
				v += W.governor_race
			v += W.presence_closed * mine
		else:
			v += W.presence_open * minf(mine, 5.0)
	# Compagnie privilegiate: 6 presenze in una regione sbloccano la sua Compagnia (una a testa).
	# Senza questo termine l'IA si sparpaglia e non arriva quasi mai a 6.
	if String(pl.get("charter", "")) != "":
		v += W.charter_progress * clampf(rl - 1.0, 0.0, 3.0) / 3.0   # obiettivo raggiunto: niente calo prendendola
	elif not s.get("charters", {}).is_empty() and rl >= 2.0:
		var best := 0
		for rid in s.charters:
			best = maxi(best, Rules.presence(s, p, rid))
		var f := minf(float(best), 6.0) / 6.0
		v += W.charter_progress * f * f * clampf(rl - 1.0, 0.0, 3.0) / 3.0
	for x in s.exploits:
		var ok := true
		for xr in GameData.exploit_by_id[x]["regions"]:
			if Rules.presence(s, p, xr) == 0:
				ok = false
		if ok:
			v += W.exploit_access * minf(rl, 3.0) / 3.0
	var over: int = pl.cards.size() - Rules.card_limit(s, p)
	if over > 0:
		v -= over * W.over_limit
	return v
