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


func _on_start() -> void:
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
	start_requested.emit(specs, sv, opts)
