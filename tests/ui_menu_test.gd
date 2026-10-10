extends SceneTree
## Menu a pulsanti: screenshot e controllo delle opzioni emesse. Uso: -- <cartella>
var ss: SetupScreen
var frames := 0
func _initialize() -> void:
	GameData.ensure_loaded()
	ss = SetupScreen.new()
	root.add_child(ss)
	ss.start_requested.connect(func(specs, sv, opts): print("specs ", specs.map(func(x): return "%s ai=%s lv=%d" % [x.name, x.ai, x.ai_level]), " opts ", opts))
func _process(_d: float) -> bool:
	frames += 1
	if frames == 3:
		_shot()
	if frames == 6:
		# accendi il 4° giocatore come IA esperta, lato B, Molo, niente Exploit
		for b in ss._rows[3].row.get_children():
			if b is Button and b.text == "IA esperta":
				b.button_pressed = true
		for g in [ss._side, ss._start]:
			g.get_buttons()[g.get_buttons().size() - 1].button_pressed = true
		ss._exploits.button_pressed = false
		ss._refresh_rows()
		ss._on_start()
		# spegni tutti tranne uno: Salpa disabilitato
		for i in 5:
			ss._rows[i].group.get_buttons()[0].button_pressed = i > 0
		ss._refresh_rows()
		print("salpa disabilitato con 1 giocatore: ", ss._go.disabled, " · ", ss._warn.text)
		quit()
	return false
func _shot() -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_cmdline_user_args()[0].path_join("shot_menu.png"))
