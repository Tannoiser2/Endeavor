extends Control
## Punto d'ingresso: alterna menu iniziale e partita.

var _current: Control


func _ready() -> void:
	GameData.ensure_loaded()
	_show_setup()


func _show_setup() -> void:
	var ss := SetupScreen.new()
	_swap(ss)
	ss.start_requested.connect(_start_game)


func _start_game(specs: Array, seed_value: int, opts: Dictionary = {}) -> void:
	var gs := GameScreen.new()
	gs.setup(specs, seed_value, opts)
	gs.back_to_menu.connect(_show_setup)
	gs.rematch_requested.connect(func(): _start_game(gs.game_specs, -1, gs.game_opts))
	_swap(gs)


func _swap(c: Control) -> void:
	if _current:
		_current.queue_free()
	_current = c
	add_child(c)
