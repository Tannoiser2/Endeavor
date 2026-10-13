class_name SetupScreen
extends Control
## Schermata iniziale: giocatori (umano/IA), lato del tabellone, edificio iniziale, Exploit.

signal start_requested(specs: Array, seed_value: int, opts: Dictionary)

const COLORS := ["#2f6fd0", "#d23c3c", "#e8e8e8", "#8a4fc0", "#e0b52a"]
const DEFAULT_NAMES := ["Blu", "Rosso", "Bianco", "Viola", "Giallo"]
const TYPES := ["Umano", "IA principiante", "IA normale", "IA esperta"]

var _rows: Array = []
var _seed: LineEdit
var _side: ButtonGroup
var _start: ButtonGroup
var _exploits: Button
var _charters: Button
var _go: Button
var main                      # nodo principale (main.gd): collegamento Firebase e stanza
var _online_btn: Button
var on_panel: Control
var on_name: LineEdit
var on_code: LineEdit
var on_lbl: Label
var on_start: Button
var _warn: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := TextureRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	if ResourceLoader.exists("res://assets/board_a.jpg"):
		bg.texture = load("res://assets/board_a.jpg")
		bg.modulate = Color(0.3, 0.3, 0.36)
	add_child(bg)
	# Copertina a sinistra (tools/immagini_extra/copertina.*, copiata in assets dall'estrattore), menu a destra.
	var has_cover := ResourceLoader.exists("res://assets/copertina.jpg")
	if has_cover:
		var cover := TextureRect.new()
		cover.texture = load("res://assets/copertina.jpg")
		cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cover.anchor_left = 0.0
		cover.anchor_right = 0.56
		cover.anchor_top = 0.0
		cover.anchor_bottom = 1.0
		cover.offset_left = 40
		cover.offset_right = -20
		cover.offset_top = 40
		cover.offset_bottom = -40
		add_child(cover)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if has_cover:
		center.anchor_left = 0.56
		center.offset_left = 0
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	if not has_cover and ResourceLoader.exists("res://assets/logo.png"):
		var logo := TextureRect.new()
		logo.texture = load("res://assets/logo.png")
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.custom_minimum_size = Vector2(560, 124)
		box.add_child(logo)
	else:
		var title := Label.new()
		title.text = "Nuova partita" if has_cover else "Endeavor – Age of Sail"
		title.add_theme_font_size_override("font_size", 36)
		box.add_child(title)
	var sub := Label.new()
	sub.text = "con gli Exploit — dati e grafica dal mod Tabletop Simulator"
	sub.modulate = Color(1, 1, 1, 0.65)
	box.add_child(sub)

	box.add_child(_lbl("Giocatori (da 2 a 5): scegli chi gioca e come"))
	for i in 5:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var sw := ColorRect.new()
		sw.color = Color(COLORS[i])
		sw.custom_minimum_size = Vector2(22, 22)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(sw)
		var name := LineEdit.new()
		name.text = DEFAULT_NAMES[i]
		name.custom_minimum_size = Vector2(150, 0)
		row.add_child(name)
		var grp := _seg(row, ["—", "Umano", "IA facile", "IA normale", "IA esperta"], [-1, 0, 1, 2, 3],
			[0, 2, 2, -1, -1][i], ["Non gioca", "Giocatore umano", "IA principiante", "IA normale", "IA esperta"])
		grp.pressed.connect(func(_b): _refresh_rows())
		box.add_child(row)
		_rows.append({"row": row, "name": name, "sw": sw, "group": grp})

	box.add_child(_lbl("Tabellone"))
	var o1 := HBoxContainer.new()
	_side = _seg(o1, ["Automatico", "Lato A (2-4)", "Lato B (4-5)"], ["", "A", "B"], "", ["Lato A con 2-4 giocatori, lato B con 5"])
	box.add_child(o1)
	box.add_child(_lbl("Edificio iniziale"))
	var o2 := HBoxContainer.new()
	_start = _seg(o2, ["Casa coloniale (Occupare)", "Molo mercantile (Navigare, +1 Ricchezza)"], ["colonial_house", "merchant_dock"], "colonial_house")
	box.add_child(o2)
	box.add_child(_lbl("Moduli"))
	var o3 := HBoxContainer.new()
	o3.add_theme_constant_override("separation", 6)
	_exploits = _toggle(o3, "Exploit (3 a caso)", true)
	_charters = _toggle(o3, "Compagnie privilegiate", true)
	box.add_child(o3)

	var sh := HBoxContainer.new()
	sh.add_child(_lbl("Seed (vuoto = casuale):"))
	_seed = LineEdit.new()
	_seed.custom_minimum_size = Vector2(120, 0)
	sh.add_child(_seed)
	box.add_child(sh)

	_warn = _lbl("")
	_warn.add_theme_color_override("font_color", Color("#ff9a7a"))
	box.add_child(_warn)
	_go = Button.new()
	_go.text = "Salpa!"
	_go.custom_minimum_size = Vector2(0, 46)
	_go.pressed.connect(_on_start)
	var gs := StyleBoxFlat.new()
	gs.bg_color = Color("#b8862f")
	gs.border_color = Color("#f1d38a")
	gs.set_border_width_all(2)
	gs.set_corner_radius_all(8)
	var gh := gs.duplicate()
	gh.bg_color = Color("#d29c3c")
	var gd := gs.duplicate()
	gd.bg_color = Color("#3a3a3a")
	gd.border_color = Color("#555555")
	_go.add_theme_stylebox_override("normal", gs)
	_go.add_theme_stylebox_override("hover", gh)
	_go.add_theme_stylebox_override("pressed", gh)
	_go.add_theme_stylebox_override("disabled", gd)
	_go.add_theme_color_override("font_color", Color("#1a1206"))
	_go.add_theme_color_override("font_hover_color", Color("#1a1206"))
	_go.add_theme_font_size_override("font_size", 22)
	box.add_child(_go)
	_online_btn = Button.new()
	_online_btn.text = "Gioca online"
	_online_btn.tooltip_text = "Partita con amici lontani: i colori su Umano diventano i posti della stanza"
	_online_btn.custom_minimum_size = Vector2(0, 40)
	_online_btn.focus_mode = Control.FOCUS_NONE
	_style(_online_btn)
	_online_btn.pressed.connect(_online_panel)
	box.add_child(_online_btn)
	_refresh_rows()


func _lbl(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


## Pulsanti a scelta singola (uno solo acceso). Restituisce il gruppo; il valore sta nel meta "v".
func _seg(parent: HBoxContainer, labels: Array, values: Array, selected, tips: Array = []) -> ButtonGroup:
	var grp := ButtonGroup.new()
	parent.add_theme_constant_override("separation", 4)
	for j in labels.size():
		var b := Button.new()
		b.text = labels[j]
		b.toggle_mode = true
		b.button_group = grp
		b.set_meta("v", values[j])
		b.focus_mode = Control.FOCUS_NONE
		if j < tips.size():
			b.tooltip_text = tips[j]
		_style(b)
		b.button_pressed = values[j] == selected
		parent.add_child(b)
	return grp


func _toggle(parent: HBoxContainer, label: String, on: bool) -> Button:
	var b := Button.new()
	b.text = label
	b.toggle_mode = true
	b.button_pressed = on
	b.focus_mode = Control.FOCUS_NONE
	_style(b)
	parent.add_child(b)
	return b


## Acceso = oro pieno, spento = scuro: si capisce a colpo d'occhio cosa è scelto.
func _style(b: Button) -> void:
	var off := StyleBoxFlat.new()
	off.bg_color = Color("#1d2732")
	off.border_color = Color("#3b4a58")
	off.set_border_width_all(1)
	off.set_corner_radius_all(6)
	off.content_margin_left = 10
	off.content_margin_right = 10
	off.content_margin_top = 6
	off.content_margin_bottom = 6
	var hov := off.duplicate()
	hov.bg_color = Color("#2a3644")
	var on := off.duplicate()
	on.bg_color = Color("#c79a3e")
	on.border_color = Color("#f1d38a")
	b.add_theme_stylebox_override("normal", off)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	b.add_theme_color_override("font_pressed_color", Color("#1a1206"))
	b.add_theme_color_override("font_hover_pressed_color", Color("#1a1206"))


func _val(grp: ButtonGroup):
	var b := grp.get_pressed_button()
	return b.get_meta("v") if b else null


func _active() -> Array:
	var out := []
	for i in _rows.size():
		if int(_val(_rows[i].group)) >= 0:
			out.append(i)
	return out


func _refresh_rows() -> void:
	for i in _rows.size():
		var on := int(_val(_rows[i].group)) >= 0
		_rows[i].name.editable = on
		_rows[i].name.modulate = Color(1, 1, 1, 1.0 if on else 0.4)
		_rows[i].sw.modulate = Color(1, 1, 1, 1.0 if on else 0.3)
	var n := _active().size()
	if _go:
		_go.disabled = n < 2
		_warn.text = "Servono almeno 2 giocatori." if n < 2 else ""


## Giocatori, seme e opzioni scelti nel menu.
func _config() -> Dictionary:
	var specs := []
	for i in _active():
		var t := int(_val(_rows[i].group))
		var nm: String = _rows[i].name.text.strip_edges()
		specs.append({"name": nm if nm != "" else DEFAULT_NAMES[i], "ai": t > 0, "ai_level": t, "color": COLORS[i]})
	var opts := {"exploits": _exploits.button_pressed, "charters": _charters.button_pressed,
		"start_building": String(_val(_start))}
	if String(_val(_side)) != "":
		opts["side"] = String(_val(_side))
	var sv := int(_seed.text) if _seed.text.is_valid_int() else -1
	return {"specs": specs, "opts": opts, "seed": sv}


func _on_start() -> void:
	var c := _config()
	start_requested.emit(c.specs, c.seed, c.opts)


# ───────────────────────── gioco online ─────────────────────────

func _online_panel() -> void:
	if main == null:
		return
	if is_instance_valid(on_panel):
		on_panel.queue_free()
	on_panel = Control.new()
	on_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	on_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(on_panel)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	on_panel.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	on_panel.add_child(center)
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#131b25")
	sb.border_color = Color("#b08a4a")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	box.add_theme_stylebox_override("panel", sb)
	box.custom_minimum_size = Vector2(640, 0)
	center.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	box.add_child(vb)
	var title := Label.new()
	title.text = "Gioca online"
	title.add_theme_font_size_override("font_size", 32)
	vb.add_child(title)
	var info := Label.new()
	info.text = "Chi crea la stanza sceglie prima nel menu colori, IA e opzioni: i colori su Umano diventano i posti per gli amici (il primo è il suo). Gli amici entrano con il codice di 4 lettere. I posti rimasti liberi li gioca l'IA."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(600, 0)
	info.modulate = Color(1, 1, 1, 0.75)
	vb.add_child(info)
	var ses: Dictionary = main.get_net().load_session()
	on_name = LineEdit.new()
	on_name.placeholder_text = "Il tuo nome"
	on_name.max_length = 20
	on_name.text = str(ses.get("name", ""))
	on_name.custom_minimum_size = Vector2(0, 42)
	vb.add_child(on_name)
	var b_create := Button.new()
	b_create.text = "Crea una stanza"
	b_create.custom_minimum_size = Vector2(0, 44)
	_style(b_create)
	b_create.pressed.connect(_online_create)
	vb.add_child(b_create)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	on_code = LineEdit.new()
	on_code.placeholder_text = "Codice"
	on_code.max_length = 4
	on_code.custom_minimum_size = Vector2(160, 42)
	on_code.text_changed.connect(func(t):
		on_code.text = t.to_upper()
		on_code.caret_column = t.length())
	row.add_child(on_code)
	var b_join := Button.new()
	b_join.text = "Entra"
	b_join.custom_minimum_size = Vector2(140, 42)
	_style(b_join)
	b_join.pressed.connect(_online_join)
	row.add_child(b_join)
	vb.add_child(row)
	on_lbl = Label.new()
	on_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	on_lbl.custom_minimum_size = Vector2(600, 96)
	vb.add_child(on_lbl)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	on_start = Button.new()
	on_start.text = "Inizia online"
	on_start.custom_minimum_size = Vector2(260, 46)
	on_start.add_theme_stylebox_override("normal", _go.get_theme_stylebox("normal"))
	on_start.add_theme_stylebox_override("hover", _go.get_theme_stylebox("hover"))
	on_start.add_theme_color_override("font_color", Color("#1a1206"))
	on_start.add_theme_color_override("font_hover_color", Color("#1a1206"))
	on_start.pressed.connect(_online_start)
	on_start.visible = main.lobby.get("role", "") == "host"
	row2.add_child(on_start)
	var b_close := Button.new()
	b_close.text = "Indietro"
	b_close.custom_minimum_size = Vector2(160, 46)
	_style(b_close)
	b_close.pressed.connect(func(): on_panel.queue_free())
	row2.add_child(b_close)
	vb.add_child(row2)
	if not main.lobby.is_empty():
		on_code.text = main.lobby["code"]
		_say("Stanza %s…" % main.lobby["code"])
		_lobby_poll(main.lobby["code"])
	elif str(ses.get("room", "")) != "":
		on_code.text = str(ses["room"])
		_say("Eri nella stanza %s: premi Entra per rientrare." % ses["room"])


func _say(t: String) -> void:
	if is_instance_valid(on_lbl):
		on_lbl.text = t


func _seats_text(room: Dictionary) -> String:
	var seats := Net._as_dict(room.get("seats", {}))
	var specs: Array = _config().specs
	var parts := []
	for idx in room.get("open", []):
		var k := str(int(idx))
		var who := str(seats[k].get("name", "?")) if seats.has(k) and seats[k] is Dictionary else "libero"
		var cname: String = specs[int(idx)]["name"] if int(idx) < specs.size() else "posto %d" % (int(idx) + 1)
		parts.append("%s: %s" % [cname, who])
	return ", ".join(parts)


func _online_create() -> void:
	var nm := on_name.text.strip_edges()
	if nm == "":
		_say("Scrivi il tuo nome.")
		return
	var specs: Array = _config().specs
	var seats := []
	for i in specs.size():
		if not specs[i]["ai"]:
			seats.append(i)
	if specs.size() < 2 or seats.size() < 2:
		_say("Metti su Umano almeno due colori: il primo è il tuo, gli altri sono i posti per gli amici.")
		return
	_say("Creo la stanza…")
	var net: Net = main.get_net()
	var code := await net.create_room(nm, seats)
	if code == "":
		_say("Non riesco a creare la stanza.\n%s" % net.last_error)
		return
	main.lobby = {"role": "host", "code": code, "seat": seats[0]}
	net.remember_room(code, seats[0])
	net._save({"name": nm})
	if is_instance_valid(on_code):
		on_code.text = code
	if is_instance_valid(on_start):
		on_start.visible = true
	_lobby_poll(code)


func _online_join() -> void:
	var code := on_code.text.strip_edges().to_upper()
	var nm := on_name.text.strip_edges()
	if nm == "" or code.length() != 4:
		_say("Scrivi il tuo nome e il codice di 4 lettere.")
		return
	_say("Entro nella stanza %s…" % code)
	var net: Net = main.get_net()
	var seat := await net.join_room(code, nm)
	if seat == -2:
		_say("Stanza %s non trovata, oppure la partita è già iniziata.%s" % [code, ("\n" + net.last_error) if net.last_error != "" else ""])
		return
	if seat == -1:
		_say("Nella stanza %s non ci sono posti liberi." % code)
		return
	var room: Dictionary = net.last_room
	main.lobby = {"role": "host" if room.get("host", "") == net.uid else "guest", "code": code, "seat": seat}
	net.remember_room(code, seat)
	net._save({"name": nm})
	if room.get("status", "") in ["playing", "over"] and room.has("game"):
		_say("Rientro nella partita della stanza %s…" % code)
		var err: String = await main.start_online(room["game"], true)
		if err != "":
			_say(err)
		return
	if is_instance_valid(on_start):
		on_start.visible = main.lobby["role"] == "host"
	_lobby_poll(code)


func _lobby_poll(code: String) -> void:
	var net: Net = main.get_net()
	while is_inside_tree() and main.lobby.get("code", "") == code:
		var room := await net.room(code)
		if not is_inside_tree() or main.lobby.get("code", "") != code:
			return
		if room.is_empty():
			_say("La stanza %s non esiste più." % code)
			main.lobby = {}
			return
		if main.lobby["role"] == "host":
			_say("Stanza [ %s ]: dai il codice ai tuoi amici.\nPosti: %s.\nQuando ci siete tutti premi Inizia online: i posti liberi li gioca l'IA." % [code, _seats_text(room)])
		else:
			if room.get("status", "") == "playing" and room.has("game"):
				var err: String = await main.start_online(room["game"], false)
				if err != "":
					_say(err)
				return
			_say("Sei nella stanza [ %s ].\nPosti: %s.\nAspetta che chi l'ha creata avvii la partita." % [code, _seats_text(room)])
		await get_tree().create_timer(2.0).timeout


## Chi ha creato la stanza avvia: giocatori, opzioni e seme valgono per tutti.
func _online_start() -> void:
	var code: String = main.lobby["code"]
	var net: Net = main.get_net()
	var room := await net.room(code)
	if room.is_empty():
		_say("La stanza %s non esiste più." % code)
		main.lobby = {}
		return
	var seats_db := Net._as_dict(room.get("seats", {}))
	var cfg := _config()
	var specs: Array = cfg.specs
	var my_seat := int(main.lobby["seat"])
	if my_seat >= specs.size() or not seats_db.has(str(my_seat)) or specs[my_seat]["ai"]:
		_say("Hai cambiato i colori dopo aver creato la stanza: creane una nuova.")
		return
	for i in specs.size():
		var k := str(i)
		if seats_db.has(k) and seats_db[k] is Dictionary and not specs[i]["ai"]:
			specs[i]["name"] = str(seats_db[k].get("name", specs[i]["name"]))
		elif not specs[i]["ai"]:
			specs[i]["ai"] = true          # posto rimasto libero: lo gioca l'IA
			specs[i]["ai_level"] = 2
	if int(cfg.seed) < 0:
		cfg["seed"] = 1 + randi() % 2000000000
	var g := {"cfg": var_to_str(cfg)}
	if not await net.start_room(code, g):
		_say("Non riesco ad avviare la partita (%s)." % net.last_error)
		return
	var err: String = await main.start_online(g, false)
	if err != "":
		_say(err)
