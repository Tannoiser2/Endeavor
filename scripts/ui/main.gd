extends Control
## Punto d'ingresso: alterna menu iniziale e partita.

var _current: Control
## Collegamento a Firebase per il gioco online (resta vivo fra menu e partita).
var net: Net
## Stanza online in preparazione: {role, code, seat}. Vuota se non si è in una stanza.
var lobby := {}


func _ready() -> void:
	GameData.ensure_loaded()
	_show_setup()


func get_net() -> Net:
	if net == null:
		net = Net.new()
		add_child(net)
	return net


func _show_setup() -> void:
	var ss := SetupScreen.new()
	ss.main = self
	_swap(ss)
	ss.start_requested.connect(_start_game)


func _start_game(specs: Array, seed_value: int, opts: Dictionary = {}) -> void:
	var gs := GameScreen.new()
	gs.setup(specs, seed_value, opts)
	gs.back_to_menu.connect(_show_setup)
	gs.rematch_requested.connect(func(): _start_game(gs.game_specs, -1, gs.game_opts))
	_swap(gs)


## Avvio (o rientro) di una partita online: g = {"cfg": var_to_str({specs, seed, opts})}.
func start_online(g: Dictionary, rejoin: bool) -> String:
	var n := get_net()
	var lob := lobby
	var cfg = str_to_var(str(g.get("cfg", "")))
	if not (cfg is Dictionary):
		return "Configurazione della partita non valida."
	var backlog: Array = []
	if rejoin:
		backlog = await n.get_acts(lob["code"])
		n.set_away(lob["code"], int(lob["seat"]), false)
	var ses := OnlineSession.new()
	ses.setup(n, lob["code"], int(lob["seat"]), lob["role"], backlog)
	lobby = {}
	var gs := GameScreen.new()
	gs.setup(cfg["specs"], int(cfg["seed"]), cfg["opts"], ses)
	gs.back_to_menu.connect(_show_setup)
	_swap(gs)
	return ""


func _swap(c: Control) -> void:
	if _current:
		_current.queue_free()
	_current = c
	add_child(c)
