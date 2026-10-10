class_name GameData
extends RefCounted
## Carica e indicizza i dati di gioco dai JSON in res://data/ (generati da tools/estrai_tts.py
## a partire dal mod Tabletop Simulator). Il motore delle regole non contiene numeri "magici".

const TRACKS := ["industry", "culture", "finance", "influence"]
const ICONS := ["industry", "culture", "finance", "influence", "glory"]
const ACTIONS := ["ship", "occupy", "attack", "draw", "payment"]
const ICON_NAMES := {
	"industry": "Industria", "culture": "Cultura", "finance": "Ricchezza",
	"influence": "Influenza", "glory": "Gloria",
}
const ACTION_NAMES := {
	"ship": "Navigare", "occupy": "Occupare", "attack": "Attaccare",
	"draw": "Pescare", "payment": "Pagamento",
}
const REGION_ORDER := ["north_america", "india", "far_east", "africa", "south_america", "caribbean", "europe"]

static var _loaded := false
static var rules: Dictionary = {}
static var buildings: Dictionary = {}
static var building_order: Array = []
static var cards: Dictionary = {}
static var tokens: Array = []
static var exploits: Array = []
static var exploit_by_id: Dictionary = {}
static var boards: Dictionary = {}     # "A"/"B" -> board indicizzato


static func ensure_loaded() -> void:
	if _loaded:
		return
	rules = _read("res://data/rules.json")
	for b in _read("res://data/buildings.json")["buildings"]:
		buildings[b["id"]] = b
		building_order.append(b["id"])
	for c in _read("res://data/cards.json")["cards"]:
		cards[c["id"]] = c
	tokens = _read("res://data/tokens.json")["tokens"]
	exploits = _read("res://data/exploits.json")["exploits"]
	for x in exploits:
		exploit_by_id[x["id"]] = x
	boards["A"] = _index_board(_read("res://data/board_a.json"))
	boards["B"] = _index_board(_read("res://data/board_b.json"))
	_loaded = true


static func _index_board(b: Dictionary) -> Dictionary:
	var nodes := {}
	var region_nodes := {}
	var region := {}
	for r in b["regions"]:
		region[r["id"]] = r
		region_nodes[r["id"]] = []
	for n in b["nodes"]:
		nodes[n["id"]] = n
		region_nodes[n["region"]].append(n["id"])
	var links := []
	var node_links := {}
	for nid in nodes:
		node_links[nid] = []
	for i in b["links"].size():
		var l: Dictionary = b["links"][i]
		var e := {"i": i, "a": l["a"], "b": l["b"], "pos": l["pos"], "token": l["token"]}
		links.append(e)
		node_links[l["a"]].append(i)
		node_links[l["b"]].append(i)
	b["node"] = nodes
	b["region"] = region
	b["region_nodes"] = region_nodes
	b["link"] = links
	b["node_links"] = node_links
	return b


static func table(name: String, value: int) -> int:
	var t: Array = rules[name]
	return int(t[clampi(value, 0, t.size() - 1)])


static func region_name(rid: String) -> String:
	for side in boards:
		if boards[side]["region"].has(rid):
			return boards[side]["region"][rid]["name"]
	return rid


static func icons_text(icons: Dictionary) -> String:
	var parts := []
	for k in ICONS:
		if icons.has(k) and int(icons[k]) != 0:
			parts.append("%s %+d" % [ICON_NAMES[k], int(icons[k])])
	return ", ".join(parts)


static func steps_text(steps: Array) -> String:
	var parts := []
	for st in steps:
		parts.append(" o ".join(Array(String(st).split("|")).map(func(a): return ACTION_NAMES[a])))
	return " + ".join(parts) if not parts.is_empty() else "nessuna azione"


static func token_text(tok: Dictionary) -> String:
	if tok.has("action"):
		return "azione " + " o ".join(Array(String(tok["action"]).split("|")).map(func(a): return ACTION_NAMES[a]))
	return icons_text(tok["icons"])


## Immagine originale di un token (commercio o azione), "" se non esiste.
## Immagine di un token degli Exploit (assets/xtokens).
static func xtoken_image(name: String) -> String:
	var path := "res://assets/xtokens/%s.png" % name
	return path if ResourceLoader.exists(path) else ""


static func token_image(tok: Dictionary) -> String:
	if tok.has("kind") and tok.has("icons") and not tok["icons"].is_empty():
		var xp := xtoken_image("%s_%s" % [tok["kind"], tok["icons"].keys()[0]])
		if xp != "":
			return xp
	var key := ""
	if tok.has("action"):
		key = String(tok["action"]).replace("|", "_")
	elif tok.has("icons") and not tok["icons"].is_empty():
		key = String(tok["icons"].keys()[0])
	var path := "res://assets/tokens/%s.png" % key
	return path if key != "" and ResourceLoader.exists(path) else ""


static func _read(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Impossibile aprire " + path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("JSON non valido: " + path)
		return {}
	return parsed
