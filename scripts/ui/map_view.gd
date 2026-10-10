class_name MapView
extends Control
## Tabellone con le scansioni originali (lato A dalla cache del mod, lato B dalla scansione aggiunta).
## Posizioni da data/board_*.json (coordinate x,z del tavolo TTS). Sopra disegna i token originali,
## le carte regione a faccia in su nei loro spazi, i Governatori ancora da assegnare (fuori dal bordo,
## come nel mod), la pila degli scarti e i dischi dei giocatori, che arrivano con un'animazione.
##
## Chiavi cliccabili: node:<id>, sea:<regione>, region:<regione> (tracciato), deck:<regione>/<mazzo>, discard.

signal target_clicked(key: String)

var state: Dictionary = {}
var B: Dictionary = {}
var tex: Texture2D
var tex_fn: Callable
var highlights: Dictionary = {}
var hover_key := ""
var zoom := 1.0
var pan := Vector2.ZERO
var _drag := false
var _snap: Dictionary = {}
var anims: Array = []
var _anim_keys: Dictionary = {}

const ANIM_TIME := 0.45
const MARGIN := 3.1              # bordo attorno al tabellone per Governatori e scarti
const CITY_R := 0.55
const FLEET_R := 0.45
const TOKEN_R := 0.5
const CARD := Vector2(2.3, 3.55)
const CHARTER := Vector2(1.75, 2.34)     # tessera Compagnia privilegiata, unità del tavolo  # carta in verticale, unità del tavolo
const LANDSCAPE := ["north_america", "india", "far_east", "south_america"]
## Tessere Exploit sotto il tabellone, come nel mod. Spazi misurati sulle tessere (pixel 833×559).
const XTILE_PX := Vector2(833, 559)
const XTILE_GAP := 0.35
const XTILE_TOP_GAP := 0.55
## Governatori spostati rispetto al mod per liberare il bordo sotto il tabellone (posizione, verticale).
const GOV_OVERRIDE := {"south_america": [[-17.33, -14.1], false]}
const XSPOTS := {
	"underground_railroad": [Vector2(732, 472), Vector2(592, 465), Vector2(544, 362), Vector2(615, 287), Vector2(642, 212)],
	"transit_of_venus": [Vector2(727, 325), Vector2(647, 325), Vector2(570, 290), Vector2(535, 218), Vector2(448, 222),
		Vector2(346, 282), Vector2(301, 202), Vector2(212, 295)],
	"transit_rewards": [Vector2(395, 438), Vector2(476, 438), Vector2(558, 438), Vector2(640, 438), Vector2(720, 438)],
	# Riquadri delle scorte (pixel della tessera) dove stanno i token ancora disponibili.
	"stock": {"underground_railroad": Vector2(727, 363), "transit_of_venus": Vector2(710, 235),
		"saltpeter": Vector2(693, 419), "manila_galleons": Vector2(676, 397), "south_sea_company": Vector2(693, 466),
		"jesuit_missionaries": Vector2(643, 282), "spanish_main": Vector2(648, 268), "dutch_east_india": Vector2(296, 330)},
	"south_sea_company": [Vector2(91, 353), Vector2(165, 418), Vector2(240, 353), Vector2(317, 418), Vector2(391, 353),
		Vector2(465, 418), Vector2(540, 353), Vector2(698, 355)],
}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func _tex(path: String) -> Texture2D:
	if path == "":
		return null
	if tex_fn.is_valid():
		return tex_fn.call(path)
	return load(path) if ResourceLoader.exists(path) else null


func set_state(s: Dictionary) -> void:
	var first: bool = state.is_empty() or state.get("seed", -1) != s.get("seed", -2)
	state = s
	var nb := Rules.board(s)
	if nb != B:
		B = nb
		tex = _tex(String(B.get("image", "")))
		first = true
	var snap := _occupancy()
	if not first:
		for key in snap:
			if not _snap.has(key) or _snap[key][0] != snap[key][0]:
				var info: Array = snap[key]
				anims.append({"key": key, "to": info[1], "col": _pc(info[0]), "t": 0.0})
	_snap = snap
	_rebuild_anim_keys()
	set_process(not anims.is_empty())
	queue_redraw()


func set_highlights(keys: Array) -> void:
	highlights.clear()
	for k in keys:
		if k != "":
			highlights[k] = true
	queue_redraw()


# ───────── animazioni ─────────

func _occupancy() -> Dictionary:
	var out := {}
	for nid in state.nodes:
		var o: int = state.nodes[nid].owner
		if o >= 0:
			out["node:" + nid] = [o, B["node"][nid]["pos"]]
	for rid in B["tracks"]:
		var tr: Array = state.regions[rid].track
		for i in tr.size():
			out["track:%s:%d" % [rid, i]] = [tr[i], B["tracks"][rid][i]]
	for reg in B["regions"]:
		if reg["sea"] == null:
			continue
		for q in state.n:
			for k in int(state.regions[reg["id"]].sea[q]):
				out["sea:%s:%d:%d" % [reg["id"], q, k]] = [q, reg["sea"]]
	return out


func _rebuild_anim_keys() -> void:
	_anim_keys.clear()
	for a in anims:
		_anim_keys[a.key] = true


func _process(delta: float) -> void:
	if anims.is_empty():
		set_process(false)
		return
	for a in anims:
		a.t += delta / ANIM_TIME
	anims = anims.filter(func(a): return a.t < 1.0)
	_rebuild_anim_keys()
	queue_redraw()


func _draw_anims(k: float) -> void:
	var start := Vector2(size.x * 0.5, size.y + 20)
	for a in anims:
		var e := 1.0 - pow(1.0 - clampf(a.t, 0.0, 1.0), 3.0)
		var to := w2s(a.to)
		var pos := start.lerp(to, e) + Vector2(0, -sin(e * PI) * 120.0)
		var r := (0.42 + 0.25 * (1.0 - e)) * k
		draw_circle(pos + Vector2(4, 6), r, Color(0, 0, 0, 0.35))
		_disc(pos, r, a.col)


# ───────── trasformazioni ─────────

func _board_rect() -> Rect2:
	var b: Array = B["bounds"]
	return Rect2(Vector2(b[0], b[1]), Vector2(b[2] - b[0], b[3] - b[1]))


func _view_rect() -> Rect2:
	var r := _board_rect().grow(MARGIN)
	if not state.is_empty() and not state.exploits.is_empty():
		var bottom := _xtile_rect(0).position.y - 0.5
		if bottom < r.position.y:
			r.size.y += r.position.y - bottom
			r.position.y = bottom
	return r


## Rettangolo (in unità del tavolo, position.y = z minima) della i-esima tessera Exploit.
func _xtile_rect(i: int) -> Rect2:
	var br := _board_rect().grow_individual(MARGIN - 0.3, 0, MARGIN - 0.3, 0)
	var w := (br.size.x - XTILE_GAP * 2) / 3.0
	var h := w * XTILE_PX.y / XTILE_PX.x
	var top := br.position.y - XTILE_TOP_GAP
	return Rect2(Vector2(br.position.x + i * (w + XTILE_GAP), top - h), Vector2(w, h))


## Da pixel della tessera a coordinate del tavolo.
func _xp(i: int, px: Vector2) -> Array:
	var r := _xtile_rect(i)
	return [r.position.x + px.x / XTILE_PX.x * r.size.x, r.end.y - px.y / XTILE_PX.y * r.size.y]


func _scale() -> float:
	var r := _view_rect()
	return minf(size.x / r.size.x, size.y / r.size.y) * zoom


func _origin() -> Vector2:
	var r := _view_rect()
	return (size - r.size * _scale()) / 2.0 + pan


func w2s(p) -> Vector2:
	var r := _view_rect()
	return _origin() + Vector2(float(p[0]) - r.position.x, r.end.y - float(p[1])) * _scale()


func s2w(v: Vector2) -> Vector2:
	var r := _view_rect()
	var u := (v - _origin()) / _scale()
	return Vector2(u.x + r.position.x, r.end.y - u.y)


func _pc(p: int) -> Color:
	return Color(state.players[p].color)


# ───────── disegno ─────────

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#0e1820"))
	if state.is_empty():
		return
	var k := _scale()
	var font := get_theme_default_font()
	var br := _board_rect()
	var tl := w2s([br.position.x, br.end.y])
	var bsize := br.size * k
	draw_rect(Rect2(tl + Vector2(6, 8), bsize), Color(0, 0, 0, 0.45))
	if tex and B.has("image_parts"):
		# scansione calibrata (in due metà se unite): ogni porzione al suo rettangolo del tavolo
		var parts: Array = B["image_parts"].duplicate()
		parts.reverse()   # la metà alta per ultima, sopra la sovrapposizione
		for part in parts:
			var src: Array = part["src"]
			var dst: Array = part["dst"]
			var p0 := w2s([dst[0], dst[3]])
			var p1 := w2s([dst[2], dst[1]])
			var scale_tex := float(tex.get_width()) / float(src[2])
			var srect := Rect2(Vector2(src[0], src[1]) * scale_tex, Vector2(src[2], src[3]) * scale_tex)
			draw_texture_rect_region(tex, Rect2(p0, p1 - p0), srect)
	elif tex:
		draw_texture_rect(tex, Rect2(tl, bsize), false)
	else:
		draw_rect(Rect2(tl, bsize), Color("#3b4a52"))

	# Carte regione a faccia in su, Governatori da assegnare, mazzo schiavitù, scarti.
	for reg in B["regions"]:
		var rid: String = reg["id"]
		var rs: Dictionary = state.regions[rid]
		var land: bool = rid in LANDSCAPE
		_draw_deck(rs.decks["main"], reg["deck_pos"], land, "deck:%s/main" % rid, not rs.open, font, k)
		if rs.governor != "" and reg["gov_pos"] != null:
			var gpos = reg["gov_pos"]
			var gland := land
			if GOV_OVERRIDE.has(rid):
				gpos = GOV_OVERRIDE[rid][0]
				gland = GOV_OVERRIDE[rid][1]
			_draw_card(GameData.cards[rs.governor], gpos, gland, k, 0.92, false)
		if rid == "europe":
			_draw_deck(rs.decks["slavery"], B["slavery_deck_pos"], false, "deck:europe/slavery", false, font, k)
	if not state.discard.is_empty():
		_draw_card(GameData.cards[state.discard.back()], B["discard_pos"], false, k, 0.9, false)
		_badge(font, w2s(B["discard_pos"]) + Vector2(0, CARD.y * 0.45 * k), "scarti %d" % state.discard.size())
	_hl_card("discard", B["discard_pos"], false, k)

	# Compagnie privilegiate ancora libere.
	for rid in state.get("charters", {}):
		var cb: Dictionary = GameData.buildings[state.charters[rid]]
		var cpos: Array = _charter_pos(cb)
		var cr := Rect2(w2s(cpos) - CHARTER * k / 2, CHARTER * k)
		draw_rect(Rect2(cr.position + Vector2(3, 4), cr.size), Color(0, 0, 0, 0.4))
		var ct := _tex(cb.get("image", ""))
		if ct:
			draw_texture_rect(ct, cr, false)
		var ck: String = "charter:" + rid
		if highlights.has(ck) or hover_key == ck:
			draw_rect(cr.grow(3), Color.YELLOW if highlights.has(ck) else Color.WHITE, false, 4.0)

	# Mare aperto.
	for reg in B["regions"]:
		if reg["sea"] != null:
			_draw_sea(reg["id"], reg["sea"], k, font)

	# Tracciati di navigazione.
	for rid in B["tracks"]:
		var pts: Array = B["tracks"][rid]
		var rs: Dictionary = state.regions[rid]
		for i in pts.size():
			var c := w2s(pts[i])
			if i < rs.track.size():
				if not _anim_keys.has("track:%s:%d" % [rid, i]):
					_disc(c, 0.42 * k, _pc(rs.track[i]))
			elif rs.track_tokens[i] != null:
				_token(c, rs.track_tokens[i], TOKEN_R * k)
		var key: String = "region:" + rid
		if not rs.open and (highlights.has(key) or hover_key == key):
			var c := w2s(pts[mini(rs.track.size(), pts.size() - 1)])
			draw_arc(c, 0.62 * k, 0, TAU, 28, Color.YELLOW if highlights.has(key) else Color.WHITE, 3.0, true)

	# Collegamenti: linea del colore di chi li controlla, token o blocco sul cerchio.
	for l in B["link"]:
		var li: int = l["i"]
		var o := Rules.link_owner(state, li)
		if o >= 0:
			draw_line(w2s(B["node"][l["a"]]["pos"]), w2s(B["node"][l["b"]]["pos"]), _pc(o), 0.2 * k, true)
	for l in B["link"]:
		var li: int = l["i"]
		var lp := w2s(l["pos"])
		if state.links[li].token != null:
			_token(lp, state.links[li].token, TOKEN_R * 1.05 * k)
		if Rules.link_blocked(state, li):
			if not _ximg("blockade", lp + Vector2(0, -0.05) * k, 0.62 * k):
				var rr := Rect2(lp - Vector2(0.36, 0.2) * k, Vector2(0.72, 0.4) * k)
				draw_rect(rr, Color("#a12020"))
				draw_rect(rr, Color.WHITE, false, 1.5)

	# Città e flotte.
	for nid in B["node"]:
		var nd: Dictionary = B["node"][nid]
		var ns: Dictionary = state.nodes[nid]
		var c := w2s(nd["pos"])
		var rad := (CITY_R if nd["kind"] == "city" else FLEET_R) * k
		if not tex:
			draw_circle(c, rad, Color("#e8dfc8") if nd["kind"] == "city" else Color("#a9c4d6"))
		if ns.owner >= 0:
			if not _anim_keys.has("node:" + nid):
				_disc(c, rad * 0.82, _pc(ns.owner))
		elif ns.token != null:
			_token(c, ns.token, rad * 0.9)
		if ns.get("fort", false):
			_fort(c + Vector2(rad * 0.75, -rad * 0.75), rad * 0.55)
		var key: String = "node:" + nid
		if highlights.has(key) or hover_key == key:
			draw_arc(c, rad * 1.18, 0, TAU, 28, Color.YELLOW if highlights.has(key) else Color.WHITE, 3.5, true)
	_draw_exploit_pieces(k, font)
	for i in state.exploits.size():
		_draw_xtile(i, state.exploits[i], k, font)
	_draw_anims(k)


func _charter_pos(cb: Dictionary) -> Array:
	return cb.get("pos_b", cb.get("pos_a")) if state.side == "B" else cb.get("pos_a")


func _draw_deck(deck: Array, pos, land: bool, key: String, closed: bool, font: Font, k: float) -> void:
	if deck.is_empty():
		_hl_card(key, pos, land, k)
		return
	var top: Dictionary = GameData.cards[deck.back()]
	# spessore del mazzo
	for i in mini(deck.size() - 1, 4):
		var off := Vector2(-(i + 1) * 0.05, (i + 1) * 0.05)
		_card_rect(pos, land, k, Color(0.15, 0.1, 0.05, 0.6), off)
	_draw_card(top, pos, land, k, 1.0, closed)
	_badge(font, w2s(pos) + Vector2(CARD.x * 0.32 * k if not land else CARD.y * 0.36 * k, -(CARD.y if not land else CARD.x) * 0.38 * k), str(deck.size()))
	_hl_card(key, pos, land, k)


func _card_rect(pos, land: bool, k: float, col: Color, off: Vector2 = Vector2.ZERO) -> void:
	var sz := (Vector2(CARD.y, CARD.x) if land else CARD) * k
	draw_rect(Rect2(w2s(pos) + off * k - sz / 2, sz), col)


func _draw_card(c: Dictionary, pos, land: bool, k: float, scale: float, dim: bool) -> void:
	var t := _tex(c.get("image", ""))
	var center := w2s(pos)
	var sz := CARD * k * scale
	draw_set_transform(center, -PI / 2 if land else 0.0, Vector2.ONE)
	var r := Rect2(-sz / 2, sz)
	draw_rect(Rect2(r.position + Vector2(3, 4), r.size), Color(0, 0, 0, 0.4))
	if t:
		draw_texture_rect(t, r, false, Color(0.62, 0.62, 0.62) if dim else Color.WHITE)
	else:
		draw_rect(r, Color("#d9cba6"))
	draw_rect(r, Color(0, 0, 0, 0.7), false, 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _hl_card(key: String, pos, land: bool, k: float) -> void:
	if not (highlights.has(key) or hover_key == key):
		return
	var sz := (Vector2(CARD.y, CARD.x) if land else CARD) * k
	var r := Rect2(w2s(pos) - sz / 2, sz).grow(4)
	draw_rect(r, Color.YELLOW if highlights.has(key) else Color.WHITE, false, 4.0)


func _draw_sea(rid: String, pos, k: float, font: Font) -> void:
	var c := w2s(pos)
	var rs: Dictionary = state.regions[rid]
	var i := 0
	for p in state.n:
		var nd := int(rs.sea[p])
		if nd > 0:
			var off := Vector2(cos(i * 2.1), sin(i * 2.1)) * 0.55 * k if state.n > 1 else Vector2.ZERO
			_disc(c + off, 0.38 * k, _pc(p))
			if nd > 1:
				_badge(font, c + off, str(nd))
			i += 1
	var key: String = "sea:" + rid
	if highlights.has(key) or hover_key == key:
		draw_arc(c, 1.15 * k, 0, TAU, 36, Color.YELLOW if highlights.has(key) else Color.WHITE, 3.5, true)


func _draw_exploit_pieces(k: float, font: Font) -> void:
	if state.xs.has("jesuit_missionaries"):
		for nid in state.xs["jesuit_missionaries"].get("at", {}):
			var c := w2s(B["node"][nid]["pos"])
			if not _ximg("missionary", c + Vector2(0.5, -0.5) * k, 0.42 * k):
				_badge(font, c + Vector2(0.45, -0.5) * k, "✝")
	if state.xs.has("republic_of_pirates"):
		var at: String = state.xs["republic_of_pirates"].get("ship", "")
		if B["node"].has(at):
			var pc := w2s(B["node"][at]["pos"])
			if not _ximg("pirate_ship", pc + Vector2(0, -0.15) * k, 0.85 * k):
				_badge(font, pc, "☠")


func _draw_xtile(i: int, xid: String, k: float, font: Font) -> void:
	var def: Dictionary = GameData.exploit_by_id[xid]
	var wr := _xtile_rect(i)
	var tl := w2s([wr.position.x, wr.end.y])
	var rect := Rect2(tl, wr.size * k)
	var px := wr.size.x * k / XTILE_PX.x      # pixel schermo per pixel tessera
	draw_rect(Rect2(rect.position + Vector2(5, 7), rect.size), Color(0, 0, 0, 0.45))
	var t := _tex(def["image"])
	if t:
		draw_texture_rect(t, rect, false)
	var st: Dictionary = state.xs[xid]
	var dr := 20.0 * px
	var X := func(p: Vector2) -> Vector2: return w2s(_xp(i, p))
	match xid:
		"underground_railroad":
			var sp: Array = XSPOTS[xid]
			for j in sp.size():
				if int(st.spots[j]) >= 0:
					_disc(X.call(sp[j]), dr * 1.4, _pc(st.spots[j]))
			_xgrid(st.free.map(func(t): return "freedom_" + t), X.call(XSPOTS.stock[xid]), dr * 0.95, 3, 34.0 * px)
		"transit_of_venus":
			var sp: Array = XSPOTS[xid]
			for j in sp.size():
				if int(st.spots[j]) >= 0:
					_disc(X.call(sp[j]), dr * 1.5, _pc(st.spots[j]))
			_xgrid(st.tokens.map(func(t): return "transit_" + t), X.call(XSPOTS.stock[xid]), dr * 1.0, 4, 38.0 * px)
			var rw: Array = XSPOTS["transit_rewards"]
			for j in rw.size():
				if int(st.rewards[j]) >= 0:
					_token(X.call(rw[j]), {"icons": {"finance": 1}}, dr * 1.5)
		"south_sea_company":
			var sp: Array = XSPOTS[xid]
			for j in sp.size():
				if int(st.spots[j]) >= 0:
					_disc(X.call(sp[j]), dr * 1.5, _pc(st.spots[j]))
			_xgrid(st.get("deck", []).map(func(sid): return "share_" + sid), X.call(XSPOTS.stock[xid]), dr * 1.25, 3, 54.0 * px)
		"dutch_east_india":
			for pair in [["cape", Vector2(460, 342)], ["batavia", Vector2(715, 285)]]:
				var cs: Dictionary = st[pair[0]]
				if int(cs.owner) >= 0:
					_disc(X.call(pair[1]), dr * 1.9, _pc(cs.owner))
				if cs.fort:
					_fort(X.call(pair[1] + Vector2(34, -34)), dr * 1.4)
			_xstack("fort", X.call(XSPOTS.stock[xid]), dr * 2.4, _forts_here(xid), font)
		"republic_of_pirates":
			if int(st.nassau) >= 0:
				_disc(X.call(Vector2(710, 300)), dr * 1.7, _pc(st.nassau))
			if int(st.gov) >= 0:
				_disc(X.call(Vector2(712, 443)), dr * 1.9, _pc(st.gov))
			if st.ship == "nassau":
				if not _ximg("pirate_ship", X.call(Vector2(712, 300)), dr * 3.2):
					_badge(font, X.call(Vector2(690, 262)), "☠")
		"sun_never_sets":
			var j := 0
			for q in state.n:
				for c in int(st.tile[q]):
					_disc(X.call(Vector2(560 + j * 34, 300 + (j % 2) * 26)), dr * 1.3, _pc(q))
					j += 1
		"saltpeter":
			var j := 0
			for q in state.n:
				if st.tile.has(str(q)):
					_disc(X.call(Vector2(670 + j * 30, 247)), dr * 1.6, _pc(q))
					j += 1
			_xstack("cannon", X.call(XSPOTS.stock[xid]), dr * 2.4, int(st.left), font)
		"manila_galleons":
			var j := 0
			for q in state.n:
				if int(st.manila[q]) > 0:
					_disc(X.call(Vector2(650 + j * 32, 275)), dr * 1.3, _pc(q))
					j += 1
			_xstack("galleon_disc", X.call(XSPOTS.stock[xid]), dr * 1.8, int(st.left), font)
		"jesuit_missionaries":
			_xstack("missionary", X.call(XSPOTS.stock[xid]), dr * 2.3, int(st.tile), font)
		"spanish_main":
			_xstack("fort", X.call(XSPOTS.stock[xid]), dr * 2.8, _forts_here(xid), font)
		"haitian_revolution":
			var stack: Array = st.stack
			for j in mini(stack.size(), 6):
				var c: Dictionary = GameData.cards[stack[stack.size() - 1 - j]]
				var ct := _tex(c.get("image", ""))
				var cc: Vector2 = X.call(Vector2(687 - j * 8, 360 + j * 8))
				var csz := Vector2(150, 230) * px
				if ct:
					draw_texture_rect(ct, Rect2(cc - csz / 2, csz), false)
			if not stack.is_empty():
				_badge(font, X.call(Vector2(687, 505)), "%d carte" % stack.size())
		"imperialism":
			var j := 0
			for q in state.n:
				var held := int(st.held.get(str(q), 0))
				if held > 0:
					var hc: Vector2 = X.call(Vector2(600 + j * 100, 480))
					_xstack("blockade", hc, dr * 2.4, held, font)
					_disc(hc + Vector2(-dr * 2.2, dr * 0.6), dr * 0.7, _pc(q))
					j += 1
	# Chiavi: una sullo stemma di ogni regione aperta; con due l'Exploit è sbloccato.
	var regs: Array = def["regions"]
	if not state.unlocked.get(xid, false):
		draw_rect(rect, Color(0, 0, 0, 0.5))
	for ri in regs.size():
		if state.regions[regs[ri]].open:
			var kc: Vector2 = X.call(Vector2(630 + ri * 118, 92))
			var kt := _tex(GameData.xtoken_image("key"))
			if kt:
				var ks := Vector2(120, 46) * px
				draw_set_transform(kc, -0.75, Vector2.ONE)
				draw_texture_rect(kt, Rect2(-ks / 2 + Vector2(3, 4), ks), false, Color(0, 0, 0, 0.5))
				draw_texture_rect(kt, Rect2(-ks / 2, ks), false)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if not state.unlocked.get(xid, false):
		_badge(font, rect.get_center() + Vector2(0, -11), "Bloccato")
		_badge(font, rect.get_center() + Vector2(0, 11), " + ".join(regs.map(func(r): return GameData.region_name(r))))
	elif st.get("closed", false):
		draw_rect(rect, Color(0.2, 0, 0, 0.45))
		_badge(font, rect.get_center(), "Non più utilizzabile")
	# Scudi dei giocatori che possono usarlo (presenza in entrambe le regioni), come nel mod.
	var e := 0
	for q in state.n:
		if Rules.x_available(state, q, xid):
			var sc: Vector2 = X.call(Vector2(480 - e * 78, 112))
			var stx := _tex(GameData.xtoken_image(_shield_name(state.players[q].color)))
			var ss := Vector2(70, 86) * px
			if stx:
				draw_texture_rect(stx, Rect2(sc - ss / 2 + Vector2(3, 4), ss), false, Color(0, 0, 0, 0.45))
				draw_texture_rect(stx, Rect2(sc - ss / 2, ss), false)
			else:
				_disc(sc, dr, _pc(q))
			e += 1
	var key := "x:" + xid
	if highlights.has(key) or hover_key == key:
		draw_rect(rect.grow(3), Color.YELLOW if highlights.has(key) else Color.WHITE, false, 4.0)


func _disc(c: Vector2, r: float, col: Color) -> void:
	draw_circle(c + Vector2(r * 0.12, r * 0.18), r, Color(0, 0, 0, 0.35))
	draw_circle(c, r, col)
	draw_arc(c, r, 0, TAU, 28, col.darkened(0.55), maxf(1.5, r * 0.12), true)
	draw_arc(c, r * 0.72, PI * 1.05, PI * 1.6, 10, Color(1, 1, 1, 0.45), maxf(1.0, r * 0.12), true)


func _token(c: Vector2, tok: Dictionary, r: float) -> void:
	var t := _tex(GameData.token_image(tok))
	draw_circle(c + Vector2(r * 0.1, r * 0.14), r, Color(0, 0, 0, 0.35))
	if t:
		draw_texture_rect(t, Rect2(c - Vector2(r, r), Vector2(r, r) * 2), false)
	else:
		draw_circle(c, r, Color("#2a2a2a"))
		draw_arc(c, r, 0, TAU, 16, Color.WHITE, 1.5, true)


const SHIELDS := {"shield_blue": Color("#2f6fd0"), "shield_red": Color("#d23c3c"), "shield_white": Color("#e8e8e8"),
	"shield_purple": Color("#8a4fc0"), "shield_yellow": Color("#e0b52a")}


## Scudo del mod più vicino al colore del giocatore.
func _shield_name(col) -> String:
	var c := Color(col)
	var best := "shield_white"
	var bd := 99.0
	for n in SHIELDS:
		var o: Color = SHIELDS[n]
		var d := Vector3(c.r - o.r, c.g - o.g, c.b - o.b).length()
		if d < bd:
			bd = d
			best = n
	return best


## Disegna un token Exploit; false se l'immagine manca.
func _ximg(name: String, c: Vector2, r: float, shadow: bool = true) -> bool:
	var t := _tex(GameData.xtoken_image(name))
	if t == null:
		return false
	if shadow:
		draw_circle(c + Vector2(r * 0.1, r * 0.16), r * 0.8, Color(0, 0, 0, 0.3))
	draw_texture_rect(t, Rect2(c - Vector2(r, r), Vector2(r, r) * 2), false)
	return true


## Pila di token uguali con il numero (se più di uno).
func _xstack(name: String, c: Vector2, r: float, n: int, font: Font, always_count: bool = false) -> void:
	if n <= 0:
		return
	for j in mini(n, 4):
		var o := Vector2(-j * r * 0.12, -j * r * 0.16)
		if not _ximg(name, c + o, r, j == 0):
			_badge(font, c, "%s %d" % [name, n])
			return
	if n > 1 or always_count:
		_badge(font, c + Vector2(r * 0.9, r * 0.75), "×%d" % n)


## Token diversi in griglia (per Libertà e Transito).
func _xgrid(names: Array, c: Vector2, r: float, cols: int, step: float) -> void:
	var n := names.size()
	var rows := int(ceil(float(n) / cols))
	for i in n:
		var row := i / cols
		var in_row := mini(cols, n - row * cols)
		var col := i % cols
		var p := c + Vector2((col - (in_row - 1) / 2.0) * step, (row - (rows - 1) / 2.0) * step)
		_ximg(names[i], p, r)


## Fortificazioni rimaste, divise tra le tessere che le tengono (8 sul Main spagnolo, 2 sulla VOC).
func _forts_here(xid: String) -> int:
	var left := Rules.forts_left(state)
	var both: bool = state.exploits.has("spanish_main") and state.exploits.has("dutch_east_india")
	if not both:
		return left
	var dutch := mini(left, 2)
	return dutch if xid == "dutch_east_india" else left - dutch


func _fort(c: Vector2, r: float) -> void:
	if _ximg("fort", c, r * 1.25):
		return
	var pts := PackedVector2Array([c + Vector2(-r, r), c + Vector2(-r, -r * 0.4), c + Vector2(-r * 0.5, -r * 0.4),
		c + Vector2(-r * 0.5, -r), c + Vector2(r * 0.5, -r), c + Vector2(r * 0.5, -r * 0.4), c + Vector2(r, -r * 0.4), c + Vector2(r, r)])
	draw_colored_polygon(pts, Color("#8a8a8a"))
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color.BLACK, 1.5, true)


func _badge(font: Font, center: Vector2, text: String) -> void:
	var fs := 13
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var r := Rect2(center - Vector2(w / 2 + 5, 10), Vector2(w + 10, 19))
	draw_rect(r, Color(0, 0, 0, 0.7))
	draw_string(font, Vector2(r.position.x + 5, r.position.y + 15), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


# ───────── input ─────────

func key_at(screen_pos: Vector2) -> String:
	if B.is_empty():
		return ""
	var w := s2w(screen_pos)
	var best := ""
	var bd := 0.72
	for nid in B["node"]:
		var d := w.distance_to(Vector2(B["node"][nid]["pos"][0], B["node"][nid]["pos"][1]))
		if d < bd:
			bd = d
			best = "node:" + nid
	if best != "":
		return best
	for rid in B["tracks"]:
		for tp in B["tracks"][rid]:
			if w.distance_to(Vector2(tp[0], tp[1])) < 0.6:
				return "region:" + rid
	for reg in B["regions"]:
		if reg["sea"] != null and w.distance_to(Vector2(reg["sea"][0], reg["sea"][1])) < 1.2:
			return "sea:" + reg["id"]
	for reg in B["regions"]:
		if _in_card(w, reg["deck_pos"], reg["id"] in LANDSCAPE):
			return "deck:%s/main" % reg["id"]
	if _in_card(w, B["slavery_deck_pos"], false):
		return "deck:europe/slavery"
	if _in_card(w, B["discard_pos"], false):
		return "discard"
	for i in state.exploits.size():
		if _xtile_rect(i).has_point(w):
			return "x:" + String(state.exploits[i])
	for rid in state.get("charters", {}):
		var cp: Array = _charter_pos(GameData.buildings[state.charters[rid]])
		if Rect2(Vector2(cp[0], cp[1]) - CHARTER / 2, CHARTER).has_point(w):
			return "charter:" + rid
	return ""


func _in_card(w: Vector2, pos, land: bool) -> bool:
	var sz := Vector2(CARD.y, CARD.x) if land else CARD
	return Rect2(Vector2(pos[0], pos[1]) - sz / 2, sz).has_point(w)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _drag:
			pan += event.relative
			queue_redraw()
			return
		var k := key_at(event.position)
		if k != hover_key:
			hover_key = k
			tooltip_text = _tooltip(k)
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if highlights.has(k) else Control.CURSOR_ARROW
			queue_redraw()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var k := key_at(event.position)
			if k != "":
				target_clicked.emit(k)
		elif event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_drag = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var before := s2w(event.position)
			zoom = clampf(zoom * (1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12), 1.0, 4.0)
			if zoom == 1.0:
				pan = Vector2.ZERO
			else:
				pan += event.position - w2s([before.x, before.y])
			queue_redraw()


func _tooltip(k: String) -> String:
	if k == "" or state.is_empty():
		return ""
	var parts := k.split(":")
	match parts[0]:
		"node":
			var nd: Dictionary = B["node"][parts[1]]
			var ns: Dictionary = state.nodes[parts[1]]
			var t := "%s — %s, Gloria %d" % ["Città" if nd["kind"] == "city" else "Spazio flotta", GameData.region_name(nd["region"]), int(nd["glory"])]
			if ns.owner >= 0:
				t += "\nDi " + state.players[ns.owner].name
			if ns.token != null:
				t += "\nToken: " + GameData.token_text(ns.token)
			if ns.get("fort", false):
				t += "\nFortificata"
			return t
		"sea":
			var t := "Mare aperto — " + GameData.region_name(parts[1])
			for p in state.n:
				if int(state.regions[parts[1]].sea[p]) > 0:
					t += "\n%s: %d" % [state.players[p].name, int(state.regions[parts[1]].sea[p])]
			return t
		"region":
			var rid := parts[1]
			var rs: Dictionary = state.regions[rid]
			var t: String = "Tracciato di navigazione — %s (%d/%d)" % [GameData.region_name(rid), rs.track.size(), rs.track_tokens.size()]
			for p in state.n:
				var pr := Rules.presence(state, p, rid)
				if pr > 0:
					t += "\n%s: presenza %d" % [state.players[p].name, pr]
			return t
		"deck":
			var rd := parts[1].split("/")
			var deck: Array = state.regions[rd[0]].decks[rd[1]]
			var t: String = "Mazzo %s%s — %d carte%s" % [GameData.region_name(rd[0]), " (schiavitù)" if rd[1] == "slavery" else "",
				deck.size(), "" if state.regions[rd[0]].open else " · regione chiusa"]
			if not deck.is_empty():
				var c: Dictionary = GameData.cards[deck.back()]
				t += "\nIn cima: valore %d — %s" % [int(c["value"]), GameData.icons_text(c["icons"])]
			return t
		"charter":
			var cb: Dictionary = GameData.buildings[state.charters[parts[1]]]
			return "%s\n%s — %s\nSi prende in Costruzione al posto di un edificio con almeno 6 di presenza in %s (una per giocatore).\nIl colono sopra non si libera con un'azione Pagamento." % [
				cb["name"], GameData.icons_text(cb["icons"]), GameData.steps_text(cb["actions"]), GameData.region_name(parts[1])]
		"x":
			var def: Dictionary = GameData.exploit_by_id[parts[1]]
			var ex := Rules.exploit(parts[1])
			var t: String = "%s (%s)\n%s" % [def["name"], " + ".join(def["regions"].map(func(r): return GameData.region_name(r))), ex.description()]
			var stt := ex.status(state)
			if stt != "":
				t += "\n\n" + stt
			return t
		"discard":
			var t := "Pila degli scarti (si pesca con presenza in Europa)"
			for cid in state.discard:
				var c: Dictionary = GameData.cards[cid]
				t += "\n%s %d — %s" % [GameData.region_name(c["region"]), int(c["value"]), GameData.icons_text(c["icons"])]
			return t
	return ""
