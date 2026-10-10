class_name PlayerBoardView
extends Control
## Plancia giocatore originale (immagine del mod) con sopra lo stato vero e interazione diretta:
## - segnalini sui 4 tracciati, token originali nei cerchi a sinistra dei tracciati;
## - edifici negli 8 spazi del porto, coloni sui cerchietti (con animazione porto ↔ edificio);
## - carte negli slot, Governatore nello spazio dedicato, porto con i coloni e i token azione.
## Chiavi cliccabili emesse da `clicked`: bld:<i>, card:<id>, tok:<i>, harbor.
## Tasto destro (o clic su qualcosa di non giocabile) ingrandisce carte ed edifici.
## Coordinate in pixel della plancia a 2000×1425 (assets/plancia.jpg).

signal clicked(key: String)
signal enlarge_requested(tex: Texture2D, title: String)

const BOARD_SIZE := Vector2(2000, 1425)
const TRACK_X0 := 403.0
const TRACK_DX := 101.9
const TRACK_Y := [60.0, 232.0, 403.0, 574.0]
const TOKEN_C := [Vector2(262, 85), Vector2(262, 257), Vector2(262, 428), Vector2(262, 598)]
const SLOT_X0 := 19.0
const SLOT_W := 244.4
const SLOT_Y := 700.0
const SLOT_H := 330.0
const CARD_X := [865.0, 1112.0, 1360.0, 1607.0, 1855.0]
const CARD_Y := 1222.0
const CARD_SIZE := Vector2(230, 347)
const GOV_C := Vector2(592, 1222)
const HARBOR := Rect2(30, 1065, 405, 340)
const ANIM_TIME := 0.4

var state: Dictionary = {}
var p := 0
var tex_fn: Callable
var board_tex: Texture2D
var highlights: Dictionary = {}      # chiavi giocabili ora (contorno giallo)
var pending_bi := -1                 # edificio scelto, colono "in mano" sopra il cerchietto
var pending_tok := -1
var interactive := false
var _hits: Array = []                # [Rect2 plancia, chiave, tooltip, texture]
var _hover := ""
var _snap: Dictionary = {}
var anims: Array = []                # {from, to (plancia), col, t}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if ResourceLoader.exists("res://assets/plancia.jpg"):
		board_tex = load("res://assets/plancia.jpg")


func set_data(s: Dictionary, player: int, texture_loader: Callable) -> void:
	var same: bool = not state.is_empty() and player == p and state.get("seed", -1) == s.get("seed", -2)
	state = s
	p = player
	tex_fn = texture_loader
	var snap := _occupancy()
	if same:
		for bi in snap:
			var before: String = _snap.get(bi, "")
			if before == "" and snap[bi] != "":
				anims.append({"from": _harbor_slot(0), "to": _circle(bi), "col": _col(snap[bi]), "t": 0.0})
			elif before != "" and snap[bi] == "":
				anims.append({"from": _circle(bi), "to": _harbor_slot(0), "col": _col(before), "t": 0.0})
	_snap = snap
	set_process(not anims.is_empty())
	queue_redraw()


func set_interaction(keys: Array, sel_bi: int, sel_tok: int, active: bool) -> void:
	highlights.clear()
	for k in keys:
		highlights[k] = true
	pending_bi = sel_bi
	pending_tok = sel_tok
	interactive = active
	queue_redraw()


func _occupancy() -> Dictionary:
	var out := {}
	if state.is_empty():
		return out
	var bs: Array = state.players[p].buildings
	for i in bs.size():
		out[i] = bs[i].occ
	return out


func _col(occ: String) -> Color:
	return Color("#3a3a3a") if occ == "cannon" else Color(state.players[p].color)


func _process(delta: float) -> void:
	for a in anims:
		a.t += delta / ANIM_TIME
	anims = anims.filter(func(a): return a.t < 1.0)
	if anims.is_empty():
		set_process(false)
	queue_redraw()


# ───────── geometria ─────────

func _k() -> float:
	return minf(size.x / BOARD_SIZE.x, size.y / BOARD_SIZE.y)


func _o() -> Vector2:
	return (size - BOARD_SIZE * _k()) / 2.0


func P(v: Vector2) -> Vector2:
	return _o() + v * _k()


func R(r: Rect2) -> Rect2:
	return Rect2(P(r.position), r.size * _k())


func _slot(bi: int) -> Rect2:
	return Rect2(SLOT_X0 + SLOT_W * bi, SLOT_Y, SLOT_W - 6, SLOT_H)


func _circle(bi: int) -> Vector2:
	var s := _slot(bi)
	return s.position + Vector2(s.size.x * 0.775, s.size.y * 0.66)


func _harbor_slot(i: int) -> Vector2:
	return HARBOR.position + Vector2(44 + (i % 6) * 62, 44 + (i / 6) * 56)


func _tex(path: String) -> Texture2D:
	if path == "":
		return null
	return tex_fn.call(path) if tex_fn.is_valid() else null


# ───────── disegno ─────────

func _draw() -> void:
	if state.is_empty():
		return
	_hits.clear()
	var k := _k()
	var pl: Dictionary = state.players[p]
	var col := Color(pl.color)
	var font := get_theme_default_font()
	if board_tex:
		draw_texture_rect(board_tex, R(Rect2(Vector2.ZERO, BOARD_SIZE)), false)
	else:
		draw_rect(R(Rect2(Vector2.ZERO, BOARD_SIZE)), Color("#5a4630"))

	# Segnalini sui tracciati.
	for i in GameData.TRACKS.size():
		var t: String = GameData.TRACKS[i]
		var raw := Rules.icons(state, p, t)
		var v := clampi(raw, 0, 15)
		var c := P(Vector2(TRACK_X0 + TRACK_DX * v, TRACK_Y[i]))
		var half := 30.0 * k
		draw_rect(Rect2(c - Vector2(half, half) + Vector2(3, 4) * k, Vector2(half, half) * 2), Color(0, 0, 0, 0.4))
		draw_rect(Rect2(c - Vector2(half, half), Vector2(half, half) * 2), col)
		draw_rect(Rect2(c - Vector2(half, half), Vector2(half, half) * 2), col.darkened(0.6), false, maxf(1.0, 4 * k))
		if raw > 15:
			_text(font, c + Vector2(0, half + 16 * k), "+%d" % (raw - 15), 46 * k, Color.WHITE)
		_hits.append([Rect2(Vector2(TRACK_X0 - 50, TRACK_Y[i] - 50), Vector2(TRACK_DX * 16, 100)), "",
			"%s: %d icone (segnalino su %d)" % [GameData.ICON_NAMES[t], raw, v], null])

	# Token commercio nei cerchi accanto ai tracciati (impilati, con il numero).
	var by_attr := {}
	var actions := {}        # testo -> [indici]
	var glory_imgs := []
	for ti in pl.tokens.size():
		var tok: Dictionary = pl.tokens[ti]
		if tok.has("action"):
			var a: String = tok["action"]
			if not actions.has(a):
				actions[a] = []
			actions[a].append(ti)
		else:
			var img_path := GameData.token_image(tok)
			for key in tok["icons"]:
				for _n in int(tok["icons"][key]):
					if key == "glory":
						glory_imgs.append(img_path)
					else:
						if not by_attr.has(key):
							by_attr[key] = []
						by_attr[key].append(img_path)
	for i in GameData.TRACKS.size():
		var t: String = GameData.TRACKS[i]
		var imgs: Array = by_attr.get(t, [])
		var n := imgs.size()
		var c := P(TOKEN_C[i])
		# I token speciali (Libertà, Transito) in cima alla pila, così si vedono.
		imgs.sort_custom(func(a, b): return String(a).contains("tokens/") and not String(b).contains("tokens/"))
		var shown_n := mini(n, 5)
		for j in shown_n:
			var img := _tex(imgs[j])
			var special: bool = String(imgs[j]).contains("xtokens/")
			_token_img(img, c + Vector2(-(shown_n - 1 - j) * 5, -(shown_n - 1 - j) * 7) * k, (118.0 if special else 96.0) * k, not special)
		if n > 1:
			_text(font, c + Vector2(48, 60) * k, "×%d" % n, 46 * k, Color.WHITE)
		_hits.append([Rect2(TOKEN_C[i] - Vector2(65, 65), Vector2(130, 130)), "", "Token %s: %d" % [GameData.ICON_NAMES[t], n], null])

	# Edifici negli spazi del porto.
	for bi in pl.buildings.size():
		var b: Dictionary = pl.buildings[bi]
		var bd: Dictionary = GameData.buildings[b.id]
		var slot := _slot(bi)
		var t := _tex(bd.get("image", ""))
		var key := "bld:%d" % bi
		if t:
			draw_texture_rect(t, R(slot), false)
		else:
			draw_rect(R(slot), Color("#c9b48a"))
			_text(font, P(slot.get_center()), bd["name"], 40 * k, Color.BLACK)
		if highlights.has(key) or bi == pending_bi:
			draw_rect(R(slot).grow(-2), Color(1, 0.9, 0.2) if bi != pending_bi else Color.WHITE, false, maxf(2.0, 7 * k))
		if b.occ != "" and not _animating_to(_circle(bi)):
			var ct := _tex(GameData.xtoken_image("cannon")) if b.occ == "cannon" else null
			if ct:
				draw_texture_rect(ct, Rect2(P(_circle(bi)) - Vector2(52, 52) * k, Vector2(104, 104) * k), false)
			else:
				_disc(P(_circle(bi)), 38.0 * k, _col(b.occ))
				if b.occ == "cannon":
					_text(font, P(_circle(bi)) + Vector2(0, 14 * k), "C", 40 * k, Color.WHITE)
		if bi == pending_bi:
			_disc(P(_circle(bi)) + Vector2(0, -10 * k), 40.0 * k, col, true)
		if state.phase == "salary" and state.get("salary_keep", []).has(bi) and Rules.order(state, state.idx) == p:
			var lr := R(Rect2(slot.position + Vector2(10, slot.size.y - 70), Vector2(slot.size.x - 20, 58)))
			draw_rect(lr, Color(0.55, 0.1, 0.1, 0.85))
			_text(font, lr.get_center() + Vector2(0, 14 * k), "RESTA IMPEGNATO", 30 * k, Color.WHITE)
		var tip := "%s (liv. %d)\n%s\n%s" % [bd["name"], int(bd["level"]), GameData.icons_text(bd["icons"]), GameData.steps_text(bd["actions"])]
		if b.occ != "":
			tip += "\nOccupato"
		_hits.append([slot, key, tip, t])

	# Governatore e carte.
	if pl.gov != "":
		var gc: Dictionary = GameData.cards[pl.gov]
		var gr := Rect2(GOV_C - CARD_SIZE / 2, CARD_SIZE)
		var gt := _tex(gc.get("image", ""))
		if gt:
			draw_texture_rect(gt, R(gr), false)
		_hits.append([gr, "gov", "Governatore %s (spazio libero)\n%s" % [GameData.region_name(gc["region"]), GameData.icons_text(gc["icons"])], gt])
	var n_cards: int = pl.cards.size()
	for ci in n_cards:
		var cid: String = pl.cards[ci]
		var c: Dictionary = GameData.cards[cid]
		var x: float = CARD_X[ci] if n_cards <= 5 else lerpf(CARD_X[0], CARD_X[4], float(ci) / float(n_cards - 1))
		var cr := Rect2(Vector2(x, CARD_Y) - CARD_SIZE / 2, CARD_SIZE)
		var ct := _tex(c.get("image", ""))
		if ct:
			draw_texture_rect(ct, R(cr), false)
		if ci >= Rules.card_limit(state, p):
			draw_rect(R(cr), Color(0.8, 0.1, 0.1, 0.22))
		var key := "card:" + cid
		if highlights.has(key):
			draw_rect(R(cr).grow(-2), Color(1, 0.9, 0.2), false, maxf(2.0, 7 * k))
		_hits.append([cr, key, "%s %s\n%s" % [GameData.region_name(c["region"]), "Governatore" if c.get("governor", false) else str(int(c["value"])),
			GameData.icons_text(c["icons"])], ct])

	# Porto (angolo in basso a sinistra): coloni, token azione, porto/riserva e Gloria.
	var hb := R(HARBOR)
	draw_rect(hb, Color(0, 0, 0, 0.32))
	var shown: int = pl.harbor - (1 if pending_bi >= 0 else 0)
	for i in clampi(shown, 0, 12):
		_disc(P(_harbor_slot(i)), 25.0 * k, col)
	if shown > 12:
		_text(font, P(_harbor_slot(11) + Vector2(44, 14)), "+%d" % (shown - 12), 34 * k, Color.WHITE)
	if highlights.has("harbor"):
		draw_rect(hb.grow(-2), Color(1, 0.9, 0.2), false, maxf(2.0, 6 * k))
	_hits.append([HARBOR, "harbor", "Porto: %d coloni, riserva %d\nGloria attuale: %d" % [pl.harbor, pl.supply, Rules.score(state, p)["total"]], null])
	# Riga dei token nel porto: azioni, poi i token degli Exploit (Gloria, Cannoni liberi,
	# Galeoni, Azioni della Compagnia tenute). Si stringono se sono tanti.
	var items := []          # {img, n, key, tip, idxs}
	for a in actions:
		var idxs: Array = actions[a]
		items.append({"img": GameData.token_image({"action": a}), "n": idxs.size(), "key": "tok:%d" % idxs[0], "idxs": idxs,
			"tip": "Token " + GameData.token_text({"action": a}) + (" ×%d" % idxs.size())})
	if not glory_imgs.is_empty():
		items.append({"img": glory_imgs[0], "n": glory_imgs.size(), "key": "", "idxs": [], "tip": "Token Gloria ×%d (1 Gloria ciascuno a fine partita)" % glory_imgs.size()})
	var busy := 0
	for b in pl.buildings:
		if b.occ == "cannon":
			busy += 1
	var free_cannons := int(pl.get("cannons", 0)) - busy
	if free_cannons > 0:
		items.append({"img": GameData.xtoken_image("cannon"), "n": free_cannons, "key": "", "idxs": [], "big": true,
			"tip": "Cannoni migliorati liberi: %d (di %d)" % [free_cannons, int(pl.get("cannons", 0))]})
	if int(pl.get("galleons", 0)) > 0:
		items.append({"img": GameData.xtoken_image("galleon_disc"), "n": int(pl.galleons), "key": "", "idxs": [],
			"tip": "Galeoni: %d (+1 popolazione o +1 pagamento ogni round; 2 Gloria ciascuno)" % int(pl.galleons)})
	if state.xs.has("south_sea_company"):
		for sid in state.xs["south_sea_company"].get("held", {}).get(str(p), []):
			items.append({"img": GameData.xtoken_image("share_" + sid), "n": 1, "key": "", "idxs": [], "square": true,
				"tip": "Azione della Compagnia dei Mari del Sud: " + ("+1 Industria finché la tieni" if String(sid).ends_with("industry") else "1 Gloria a fine partita")})
	var step := 80.0
	if items.size() > 1:
		step = minf(80.0, (HARBOR.size.x - 88.0) / (items.size() - 1))
	for ix in items.size():
		var it: Dictionary = items[ix]
		var tc := HARBOR.position + Vector2(44 + ix * step, 172)
		var img := _tex(it.img)
		var d := minf(68.0, step * 0.92)
		if it.get("square", false) and img:
			draw_texture_rect(img, Rect2(P(tc) - Vector2(d, d) * 0.47 * k, Vector2(d, d) * 0.94 * k), false)
		elif it.get("big", false) and img:
			draw_texture_rect(img, Rect2(P(tc) - Vector2(d, d) * 0.6 * k, Vector2(d, d) * 1.2 * k), false)
		else:
			_token_img(img, P(tc), d * k)
		if int(it.n) > 1:
			_text(font, P(tc + Vector2(26, 36)), "×%d" % int(it.n), 32 * k, Color.WHITE)
		var key: String = it.key
		var idxs: Array = it.idxs
		if key != "" and (highlights.has(key) or idxs.has(pending_tok)):
			draw_arc(P(tc), 38 * k, 0, TAU, 28, Color.WHITE if idxs.has(pending_tok) else Color(1, 0.9, 0.2), maxf(2.0, 6 * k), true)
		_hits.append([Rect2(tc - Vector2(36, 36), Vector2(72, 72)), key, it.tip, img])
	_text(font, hb.position + Vector2(hb.size.x / 2, 252 * k), "Porto %d · riserva %d" % [pl.harbor, pl.supply], 36 * k, Color.WHITE)
	_text(font, hb.position + Vector2(hb.size.x / 2, 318 * k), "Gloria %d" % Rules.score(state, p)["total"], 54 * k, Color("#f3d27a"))

	# Animazioni dei coloni.
	for a in anims:
		var e := 1.0 - pow(1.0 - clampf(a.t, 0.0, 1.0), 3.0)
		var pos: Vector2 = a.from.lerp(a.to, e) + Vector2(0, -sin(e * PI) * 90.0)
		_disc(P(pos), 40.0 * k, a.col, true)


func _animating_to(target: Vector2) -> bool:
	for a in anims:
		if a.to.distance_to(target) < 1.0:
			return true
	return false


func _disc(c: Vector2, r: float, col: Color, lifted: bool = false) -> void:
	draw_circle(c + Vector2(r * 0.15, r * (0.5 if lifted else 0.2)), r, Color(0, 0, 0, 0.35))
	draw_circle(c, r, col)
	draw_arc(c, r, 0, TAU, 28, col.darkened(0.55), maxf(1.5, r * 0.12), true)
	draw_arc(c, r * 0.72, PI * 1.05, PI * 1.6, 10, Color(1, 1, 1, 0.45), maxf(1.0, r * 0.12), true)


func _token_img(t: Texture2D, c: Vector2, d: float, shadow: bool = true) -> void:
	if shadow or t == null:
		draw_circle(c + Vector2(d * 0.05, d * 0.08), d / 2, Color(0, 0, 0, 0.35))
	if t:
		draw_texture_rect(t, Rect2(c - Vector2(d, d) / 2, Vector2(d, d)), false)
	else:
		draw_circle(c, d / 2, Color("#888888"))


func _text(font: Font, center: Vector2, text: String, fs: float, col: Color) -> void:
	var f := maxi(8, int(fs))
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, f).x
	draw_string_outline(font, center - Vector2(w / 2, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, f, maxi(2, f / 6), Color.BLACK)
	draw_string(font, center - Vector2(w / 2, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, f, col)


# ───────── input ─────────

func _hit_at(pos: Vector2) -> Array:
	var bp := (pos - _o()) / _k()
	for i in range(_hits.size() - 1, -1, -1):
		if _hits[i][0].has_point(bp):
			return _hits[i]
	return []


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := _hit_at(event.position)
		var key: String = h[1] if not h.is_empty() else ""
		tooltip_text = h[2] if not h.is_empty() else ""
		var playable := interactive and key != "" and (highlights.has(key) or (key.begins_with("bld:") and int(key.substr(4)) == pending_bi))
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if playable else Control.CURSOR_ARROW
	elif event is InputEventMouseButton and event.pressed:
		var h := _hit_at(event.position)
		if h.is_empty():
			return
		var key: String = h[1]
		if event.button_index == MOUSE_BUTTON_LEFT and interactive and key != "":
			clicked.emit(key)
		elif h[3] != null and (event.button_index == MOUSE_BUTTON_RIGHT or not interactive or not highlights.has(key)):
			enlarge_requested.emit(h[3], String(h[2]).split("\n")[0])
