class_name GameScreen
extends Control
## Schermata di gioco. Si gioca cliccando direttamente sulle cose:
## - plancia (in basso, del giocatore di turno): clic su un edificio = ci metti un colono e scegli
##   l'azione; di nuovo clic = il colono torna nel porto. Clic su un edificio occupato quando è un
##   bersaglio di Pagamento (o nei Pagamenti per scegliere cosa resta impegnato) e sulle carte per scartarle.
##   Token azione nel porto: clic per usarli.
## - tabellone: clic sul bersaglio (città, flotta, mare aperto, tracciato, mazzo, scarti).
## - edifici disponibili: clic per costruire.
## Le scelte obbligate (una sola mossa possibile) vengono eseguite da sole.

signal back_to_menu
signal rematch_requested

const PHASES := {"build": "Costruzione", "growth": "Crescita", "salary": "Pagamenti", "action": "Azioni",
	"discard": "Scarto", "game_over": "Fine partita"}

var state: Dictionary
var ai: AIPlayer
var decision: Dictionary = {}
var sel: Dictionary = {}          # {"k":"bld","bi":i,"w":"disc"} oppure {"k":"tok","ti":i}
var _tex_cache := {}

var map: MapView
var board: PlayerBoardView
var top_label: Label
var prompt: Label
var chips: HFlowContainer
var supply_flow: HFlowContainer
var players_box: VBoxContainer
var exploits_box: VBoxContainer
var log_label: RichTextLabel
var ai_timer: Timer
var speed: HSlider
var pause_btn: CheckButton
var popup: PopupMenu
var _popup_moves: Array = []
var big_view: Window
var big_tex: TextureRect
var board_window: Window
var board_big: PlayerBoardView
var board_player := 0
var _shown_player := 0


var game_specs: Array = []
var game_opts: Dictionary = {}


func setup(specs: Array, seed_value: int, opts: Dictionary = {}) -> void:
	game_specs = specs
	game_opts = opts
	state = Rules.new_game(specs, seed_value, opts)
	ai = AIPlayer.new(seed_value)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_step()


func tex(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	if not _tex_cache.has(path):
		_tex_cache[path] = load(path)
	return _tex_cache[path]


# ───────────────────────── costruzione UI ─────────────────────────

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#101a22")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := HSplitContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(left)
	var top := HBoxContainer.new()
	left.add_child(top)
	top_label = Label.new()
	top_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_label.add_theme_font_size_override("font_size", 17)
	top.add_child(top_label)
	pause_btn = CheckButton.new()
	pause_btn.text = "Pausa IA"
	pause_btn.toggled.connect(func(on): if not on: _step())
	top.add_child(pause_btn)
	var sl := Label.new()
	sl.text = "Velocità IA"
	top.add_child(sl)
	speed = HSlider.new()
	speed.min_value = 0.05
	speed.max_value = 1.5
	speed.step = 0.05
	speed.value = 0.5
	speed.custom_minimum_size = Vector2(110, 0)
	top.add_child(speed)
	var menu := Button.new()
	menu.text = "Menu"
	menu.pressed.connect(func(): back_to_menu.emit())
	top.add_child(menu)

	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(body)
	map = MapView.new()
	map.tex_fn = tex
	map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.size_flags_stretch_ratio = 1.9
	map.custom_minimum_size = Vector2(420, 400)
	map.target_clicked.connect(_on_click)
	body.add_child(map)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.custom_minimum_size = Vector2(430, 0)
	body.add_child(mid)
	board = PlayerBoardView.new()
	board.custom_minimum_size = Vector2(430, 306)
	mid.resized.connect(func(): board.custom_minimum_size = Vector2(430, maxf(306.0, mid.size.x / 1.404)))
	board.clicked.connect(_on_click)
	board.enlarge_requested.connect(func(t, title): show_big(t, title))
	mid.add_child(board)
	prompt = Label.new()
	prompt.add_theme_font_size_override("font_size", 16)
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.custom_minimum_size = Vector2(200, 0)
	mid.add_child(prompt)
	chips = HFlowContainer.new()
	mid.add_child(chips)
	var sup_l := Label.new()
	sup_l.text = "Edifici disponibili"
	sup_l.modulate = Color(1, 1, 1, 0.7)
	mid.add_child(sup_l)
	var sscroll := ScrollContainer.new()
	sscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mid.add_child(sscroll)
	supply_flow = HFlowContainer.new()
	supply_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sscroll.add_child(supply_flow)

	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(330, 0)
	root.add_child(tabs)
	var pscroll := ScrollContainer.new()
	pscroll.name = "Giocatori"
	pscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(pscroll)
	players_box = VBoxContainer.new()
	players_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pscroll.add_child(players_box)
	var xscroll := ScrollContainer.new()
	xscroll.name = "Exploit"
	xscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(xscroll)
	exploits_box = VBoxContainer.new()
	exploits_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xscroll.add_child(exploits_box)
	log_label = RichTextLabel.new()
	log_label.name = "Registro"
	log_label.scroll_following = true
	log_label.add_theme_font_size_override("normal_font_size", 12)
	tabs.add_child(log_label)
	var help := ScrollContainer.new()
	help.name = "Aiuto"
	tabs.add_child(help)
	var aid := TextureRect.new()
	aid.texture = tex("res://assets/aiuto_giocatore.jpg")
	aid.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	aid.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	aid.custom_minimum_size = Vector2(320, 380)
	help.add_child(aid)

	popup = PopupMenu.new()
	popup.id_pressed.connect(func(i): if i < _popup_moves.size(): _apply_human(_popup_moves[i]))
	add_child(popup)

	big_view = Window.new()
	big_view.title = "Dettaglio"
	big_view.size = Vector2i(860, 600)
	big_view.visible = false
	big_view.close_requested.connect(func(): big_view.hide())
	big_tex = TextureRect.new()
	big_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	big_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	big_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	big_view.add_child(big_tex)
	add_child(big_view)

	board_window = Window.new()
	board_window.size = Vector2i(1300, 940)
	board_window.visible = false
	board_window.close_requested.connect(func(): board_window.hide())
	board_big = PlayerBoardView.new()
	board_big.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board_big.enlarge_requested.connect(func(t, title): show_big(t, title))
	board_window.add_child(board_big)
	add_child(board_window)

	ai_timer = Timer.new()
	ai_timer.one_shot = true
	ai_timer.timeout.connect(_ai_move)
	add_child(ai_timer)


func show_big(t: Texture2D, title: String) -> void:
	if t == null:
		return
	big_tex.texture = t
	big_view.title = title
	big_view.popup_centered()


# ───────────────────────── ciclo di gioco ─────────────────────────

func _human() -> bool:
	return decision.get("p", -1) >= 0 and not state.players[decision.p].ai


func _step() -> void:
	decision = Rules.current_decision(state)
	sel = {}
	# Scelte obbligate del giocatore umano: si eseguono da sole.
	var guard := 0
	while _human() and decision.moves.size() == 1 and guard < 50:
		Rules.apply(state, decision.moves[0])
		decision = Rules.current_decision(state)
		guard += 1
	if decision.get("p", -1) >= 0 and (_human() or not _human_exists()):
		_shown_player = decision.p
	elif decision.get("p", -1) >= 0 and state.players[_shown_player].ai:
		_shown_player = decision.p
	_refresh_all()
	if decision.type == "game_over":
		_show_final()
		return
	if not _human() and not pause_btn.button_pressed:
		ai_timer.start(speed.value)


func _human_exists() -> bool:
	for pl in state.players:
		if not pl.ai:
			return true
	return false


func _ai_move() -> void:
	if decision.is_empty() or decision.type == "game_over" or _human():
		return
	Rules.apply(state, ai.choose(state, decision))
	_step()


func _apply_human(m: Dictionary) -> void:
	sel = {}
	Rules.apply(state, m)
	_step()


# ───────────────────────── interazione ─────────────────────────

## Mosse compatibili con la selezione corrente.
func _cands() -> Array:
	if decision.is_empty() or not decision.has("moves"):
		return []
	var moves: Array = decision.moves
	if decision.type != "action" or sel.is_empty():
		return moves
	if sel.k == "bld":
		return moves.filter(func(m): return m["t"] == "activate" and int(m.bi) == int(sel.bi) and m.w == sel.w)
	return moves.filter(func(m): return m["t"] == "token" and int(m.ti) == int(sel.ti))


func _building_moves(bi: int) -> Array:
	return decision.moves.filter(func(m): return m["t"] == "activate" and int(m.bi) == bi)


func _on_click(key: String) -> void:
	if not _human() or decision.type == "game_over":
		return
	if decision.type == "action":
		if key.begins_with("bld:"):
			var bi := int(key.substr(4))
			if sel.get("k", "") == "bld" and int(sel.bi) == bi:
				sel = {}           # il colono torna nel porto
				_refresh_interaction()
				return
			var hits := _cands().filter(func(m): return Rules.move_target(m) == key)
			if not sel.is_empty() and not hits.is_empty():
				_resolve(hits)
				return
			var bm := _building_moves(bi)
			if not bm.is_empty():
				var w: String = "disc" if bm.any(func(m): return m.w == "disc") else "cannon"
				_select({"k": "bld", "bi": bi, "w": w})
			return
		if key.begins_with("tok:"):
			var ti := int(key.substr(4))
			if sel.get("k", "") == "tok" and int(sel.ti) == ti:
				sel = {}
				_refresh_interaction()
				return
			if decision.moves.any(func(m): return m["t"] == "token" and int(m.ti) == ti):
				_select({"k": "tok", "ti": ti})
			return
	var hits := _cands().filter(func(m): return Rules.move_target(m) == key)
	if hits.is_empty() and decision.type == "action" and sel.is_empty():
		return
	_resolve(hits)


func _select(s: Dictionary) -> void:
	sel = s
	var c := _cands()
	if c.size() == 1:
		_apply_human(c[0])      # una sola possibilità: niente domande
		return
	_refresh_interaction()


func _resolve(hits: Array) -> void:
	if hits.is_empty():
		return
	if hits.size() == 1:
		_apply_human(hits[0])
		return
	_popup_moves = hits
	popup.clear()
	for i in hits.size():
		popup.add_item(Rules.describe(state, decision.p, hits[i]), i)
	popup.position = Vector2i(get_global_mouse_position()) + Vector2i(get_window().position)
	popup.popup()


func _refresh_interaction() -> void:
	var human := _human()
	var cands := _cands() if human else []
	var targets := []
	var board_keys := []
	for m in cands:
		var t := Rules.move_target(m)
		if t == "":
			continue
		if t.begins_with("bld:") or t.begins_with("card:"):
			board_keys.append(t)
		elif not t.begins_with("supply:"):
			targets.append(t)
	if human and decision.type == "action" and sel.is_empty():
		for m in decision.moves:
			if m["t"] == "activate":
				board_keys.append("bld:%d" % int(m.bi))
			elif m["t"] == "token":
				board_keys.append("tok:%d" % int(m.ti))
	map.set_highlights(targets)
	board.set_interaction(board_keys, int(sel.bi) if sel.get("k", "") == "bld" else -1,
		int(sel.ti) if sel.get("k", "") == "tok" else -1, human and _shown_player == decision.p)
	_update_prompt(cands)
	_update_chips(cands)
	_update_supply()


func _update_prompt(cands: Array) -> void:
	if decision.type == "game_over":
		prompt.text = "Partita finita."
		return
	var p: int = decision.p
	var pl: Dictionary = state.players[p]
	if not _human():
		prompt.text = "%s sta pensando…" % pl.name
		return
	var t := ""
	match decision.type:
		"build":
			t = "Costruzione: scegli un edificio qui sotto (livello massimo %d)." % Rules.industry_level(state, p)
		"growth":
			t = "Crescita: quanti Galeoni usare come pagamenti invece che come popolazione?"
		"salary":
			var occ := 0
			for b in pl.buildings:
				if b.occ == "disc":
					occ += 1
			var kept: int = state.get("salary_keep", []).size()
			if decision.get("mode", "keep") == "keep":
				var still: int = occ - kept - state.salary_left
				t = "Pagamenti: hai %d pagamenti per %d edifici occupati. Clicca %s che resta impegnato%s (ancora %d)." % [
					state.salary_left, occ, "l'edificio" if still == 1 else "gli edifici", "" if still == 1 else "i", still]
			else:
				t = "Pagamenti: hai %d pagamenti per %d edifici occupati. Clicca %s da liberare (ancora %d)." % [
					state.salary_left, occ, "l'edificio" if state.salary_left == 1 else "gli edifici", state.salary_left]
		"discard":
			t = "Scarto: hai %d carte, il limite è %d. Clicca la carta da scartare." % [pl.cards.size(), Rules.card_limit(state, p)]
		"frame":
			t = "Continua l'azione: clicca il bersaglio evidenziato."
		"action":
			if sel.is_empty():
				t = "%s, tocca a te (porto: %d). Clicca un edificio per metterci un colono, un token azione, oppure Passa." % [pl.name, pl.harbor]
			elif sel.k == "bld":
				t = "%s: clicca il bersaglio evidenziato (sul tabellone o sulla plancia). Clic di nuovo sull'edificio per ritirare il colono." % Rules.bname(state, p, int(sel.bi))
			else:
				t = "Token %s: clicca il bersaglio evidenziato." % GameData.token_text(pl.tokens[int(sel.ti)])
	prompt.text = t


func _chip(text: String, cb: Callable, tip: String = "") -> void:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(cb)
	chips.add_child(b)


func _update_chips(cands: Array) -> void:
	for c in chips.get_children():
		c.queue_free()
	if not _human():
		return
	var p: int = decision.p
	if decision.type == "action" and sel.is_empty():
		_chip("Passa", func(): _apply_human({"t": "pass"}))
	if not sel.is_empty():
		_chip("Annulla", func():
			sel = {}
			_refresh_interaction())
		if sel.k == "bld":
			var ws := {}
			for m in _building_moves(int(sel.bi)):
				ws[m.w] = true
			if ws.size() > 1:
				var other: String = "cannon" if sel.w == "disc" else "disc"
				_chip("Usa un %s" % ("cannone" if other == "cannon" else "colono"), func(): _select({"k": "bld", "bi": sel.bi, "w": other}))
	# Opzioni senza un bersaglio cliccabile (alternative Exploit, Salta, Galeoni...).
	for m in cands:
		if m["t"] in ["pass", "build", "keep", "salary", "discard"]:
			continue
		if Rules.move_target(m) != "":
			continue
		var label := Rules.describe(state, p, m)
		if m.get("o", {}).has("x"):
			label = "⚑ " + Rules.option_text(state, p, m.o)
		var mm: Dictionary = m
		_chip(label, func(): _apply_human(mm))


func _update_supply() -> void:
	for c in supply_flow.get_children():
		c.queue_free()
	var legal := {}
	if _human() and decision.type == "build":
		for m in decision.moves:
			legal[m.b] = m
	var show: Array = []
	for bid in GameData.building_order:
		if state.bsupply.has(bid) and state.bsupply[bid] > 0:
			show.append(bid)
	for rid in state.get("charters", {}):
		show.append(state.charters[rid])
	for bid in show:
		var bd: Dictionary = GameData.buildings[bid]
		var b := TextureButton.new()
		b.texture_normal = tex(bd.get("image", ""))
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		b.custom_minimum_size = Vector2(66, 88) if legal.is_empty() else Vector2(84, 112)
		if bd.has("charter"):
			b.tooltip_text = "%s\n%s\n%s\nRichiede 6 di presenza in %s; una per giocatore" % [bd["name"], GameData.icons_text(bd["icons"]), GameData.steps_text(bd["actions"]), GameData.region_name(bd["charter"])]
		else:
			b.tooltip_text = "%s (liv. %d) ×%d\n%s\n%s" % [bd["name"], int(bd["level"]), state.bsupply[bid], GameData.icons_text(bd["icons"]), GameData.steps_text(bd["actions"])]
		if legal.has(bid):
			var mv: Dictionary = legal[bid]
			b.pressed.connect(func(): _apply_human(mv))
			b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		else:
			b.modulate = Color(0.55, 0.55, 0.55) if not legal.is_empty() else Color(0.85, 0.85, 0.85)
			b.pressed.connect(func(): show_big(b.texture_normal, bd["name"]))
		supply_flow.add_child(b)


# ───────────────────────── pannelli informativi ─────────────────────────

func _refresh_all() -> void:
	map.set_state(state)
	board.set_data(state, _shown_player, tex)
	var who := ""
	if decision.has("p") and decision.p >= 0:
		who = " — tocca a " + state.players[decision.p].name + (" (IA)" if state.players[decision.p].ai else "")
	top_label.text = "Round %d/%d — %s%s" % [mini(state.round, int(GameData.rules["rounds"])), int(GameData.rules["rounds"]),
		PHASES.get(state.phase, state.phase), who]
	if board_window.visible:
		board_big.set_data(state, board_player, tex)
	for c in players_box.get_children():
		c.queue_free()
	for p in state.n:
		players_box.add_child(_player_panel(p))
	for c in exploits_box.get_children():
		c.queue_free()
	if state.exploits.is_empty():
		var l := Label.new()
		l.text = "Partita senza Exploit."
		exploits_box.add_child(l)
	for x in state.exploits:
		exploits_box.add_child(_exploit_panel(x))
	log_label.text = "\n".join(state.log.slice(maxi(0, state.log.size() - 150)))
	_refresh_interaction()


func _thumb(t: Texture2D, w: float, h: float, tip: String) -> Control:
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(w, h)
	r.tooltip_text = tip
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	r.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			show_big(t, tip.split("\n")[0]))
	return r


func _player_panel(p: int) -> Control:
	# Solo la plancia: colore dalle pedine, livelli sui tracciati, Gloria nell'angolo del porto.
	var pl: Dictionary = state.players[p]
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1b2833")
	sb.border_color = Color(pl.color) if decision.get("p", -1) == p else Color(pl.color).darkened(0.5)
	sb.set_border_width_all(4 if decision.get("p", -1) == p else 1)
	sb.set_content_margin_all(2)
	panel.add_theme_stylebox_override("panel", sb)
	if state.phase == "action" and state.passed[p]:
		panel.modulate = Color(0.75, 0.75, 0.75)
	var bv := PlayerBoardView.new()
	bv.custom_minimum_size = Vector2(316, 225)
	bv.set_data(state, p, tex)
	bv.enlarge_requested.connect(func(t, title): show_big(t, title))
	bv.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.double_click:
			_open_board(p))
	bv.tooltip_text = "%s%s — doppio clic per ingrandire" % [pl.name, " (IA)" if pl.ai else ""]
	panel.add_child(bv)
	return panel


func _open_board(p: int) -> void:
	board_player = p
	board_window.title = "Plancia di " + state.players[p].name
	board_big.set_data(state, p, tex)
	board_window.popup_centered()


func _exploit_panel(x: String) -> Control:
	var def: Dictionary = GameData.exploit_by_id[x]
	var ex := Rules.exploit(x)
	var panel := PanelContainer.new()
	var v := VBoxContainer.new()
	panel.add_child(v)
	var unlocked: bool = state.unlocked[x]
	var head := RichTextLabel.new()
	head.bbcode_enabled = true
	head.fit_content = true
	head.scroll_active = false
	var regs: Array = def["regions"].map(func(r): return GameData.region_name(r))
	var who := []
	for p in state.n:
		if Rules.x_available(state, p, x):
			who.append("[color=%s]%s[/color]" % [state.players[p].color, state.players[p].name])
	head.text = "[b]%s[/b] [i](%s)[/i]\n%s%s" % [def["name"], " + ".join(regs),
		"[color=#9be39b]Sbloccato[/color]" if unlocked else "[color=#aaaaaa]Bloccato: servono entrambe le regioni aperte[/color]",
		(" — utilizzabile da: " + ", ".join(who)) if unlocked and not who.is_empty() else ""]
	if state.xs[x].get("closed", false):
		head.text += "\n[color=#e08080]Non più utilizzabile[/color]"
	v.add_child(head)
	v.add_child(_thumb(tex(def["image"]), 316, 213, def["name"] + "\n(clic per ingrandire)"))
	var d := Label.new()
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(310, 0)
	d.text = ex.description()
	d.add_theme_font_size_override("font_size", 12)
	v.add_child(d)
	var stt := ex.status(state)
	if stt != "":
		var s2 := Label.new()
		s2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		s2.custom_minimum_size = Vector2(310, 0)
		s2.text = stt
		s2.modulate = Color("#f0d890")
		s2.add_theme_font_size_override("font_size", 12)
		v.add_child(s2)
	return panel


const SCORE_COLS := ["tracciati", "città", "collegamenti", "edifici", "carte", "Governatore", "porto", "schiavitù", "exploit"]
var _final_layer: Control


func _show_final() -> void:
	prompt.text = "Partita finita."
	if _final_layer == null:
		_final_layer = _build_final()
		add_child(_final_layer)
	_final_layer.visible = true
	for c in chips.get_children():
		c.queue_free()
	_chip("Punteggi finali", func(): _final_layer.visible = true)
	_chip("Rivincita", func(): rematch_requested.emit(), "Nuova partita con gli stessi giocatori e le stesse opzioni")
	_chip("Menu iniziale", func(): back_to_menu.emit())


func _build_final() -> Control:
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#131b25")
	sb.border_color = Color("#b08a4a")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.shadow_size = 18
	sb.shadow_color = Color(0, 0, 0, 0.55)
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)
	if ResourceLoader.exists("res://assets/logo.png"):
		var logo := TextureRect.new()
		logo.texture = load("res://assets/logo.png")
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.custom_minimum_size = Vector2(420, 92)
		box.add_child(logo)
	var rows := []
	for p in state.n:
		rows.append({"p": p, "sc": Rules.score(state, p)})
	rows.sort_custom(func(a, b): return a.sc.total > b.sc.total)
	var title := Label.new()
	var best: int = rows[0].sc.total
	var winners: Array = rows.filter(func(r): return r.sc.total == best).map(func(r): return state.players[r.p].name)
	title.text = ("Vince %s con %d Gloria" if winners.size() == 1 else "Pareggio fra %s con %d Gloria") % [" e ".join(winners), best]
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 3 + SCORE_COLS.size()
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	var head: Array = ["", "Giocatore", "Totale"]
	for k in SCORE_COLS:
		head.append(String(k).capitalize())
	for h in head:
		var l := Label.new()
		l.text = h
		l.modulate = Color(1, 1, 1, 0.65)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(l)
	var pos := 0
	var last := -99999
	for i in rows.size():
		var r: Dictionary = rows[i]
		if r.sc.total != last:
			pos = i + 1
			last = r.sc.total
		var pl: Dictionary = state.players[r.p]
		var lp := Label.new()
		lp.text = "%d°" % pos
		lp.add_theme_font_size_override("font_size", 22)
		grid.add_child(lp)
		var nb := HBoxContainer.new()
		var sw := ColorRect.new()
		sw.color = Color(pl.color)
		sw.custom_minimum_size = Vector2(18, 18)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		nb.add_child(sw)
		var ln := Label.new()
		ln.text = String(pl.name) + (" (IA)" if pl.get("ai", false) else "")
		ln.add_theme_font_size_override("font_size", 20)
		nb.add_child(ln)
		grid.add_child(nb)
		var lt := Label.new()
		lt.text = str(int(r.sc.total))
		lt.add_theme_font_size_override("font_size", 24)
		lt.add_theme_color_override("font_color", Color("#f3d27a"))
		lt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(lt)
		for k in SCORE_COLS:
			var lv := Label.new()
			var v := int(r.sc.get(k, 0))
			lv.text = str(v) if v != 0 else "–"
			lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			grid.add_child(lv)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 14)
	box.add_child(btns)
	var specs: Array = [["Guarda il tabellone", func(): layer.visible = false],
		["Rivincita", func(): rematch_requested.emit()],
		["Menu iniziale", func(): back_to_menu.emit()]]
	for spec in specs:
		var b := Button.new()
		b.text = spec[0]
		b.name = "btn_" + String(spec[0]).replace(" ", "_")
		b.custom_minimum_size = Vector2(190, 42)
		b.pressed.connect(spec[1])
		btns.add_child(b)
	return layer
