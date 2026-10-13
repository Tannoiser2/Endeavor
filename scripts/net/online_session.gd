class_name OnlineSession
extends Node
## Partita online in lockstep, come negli altri giochi (Kingsburg, STATUS, Snow Tails).
## Il motore di Endeavor è puro: stato + decisione corrente + mossa. Ogni decisione con più di una
## mossa possibile diventa una mossa numerata nel database (acts/0, acts/1, …); quelle obbligate
## (una sola mossa) le applica ogni dispositivo da solo, perché sono uguali ovunque.
## Tutti partono dallo stesso seme e dalle stesse opzioni, quindi la partita è identica ovunque e
## sul database viaggiano solo le scelte.
## - la decisione del proprio colore la prende la persona davanti al dispositivo;
## - i colori IA li gioca il dispositivo di chi ha creato la stanza;
## - le altre si aspettano dal database. Se un giocatore tace per un minuto, al suo posto gioca l'IA
##   (sul dispositivo di chi ha creato la stanza) finché non rientra.

var net: Net
var code := ""
var seat := -1
var role := "guest"
var n := 0                     # prossima mossa del registro
var backlog: Array = []        # mosse già giocate (rientro in una partita in corso)
var away := {}
var alive := true
var waiting_seat := -1
var slow := false
var view                       # GameScreen: messaggi di stato
## Intervallo fra due letture del database mentre si aspetta (EN_POLL per le prove automatiche).
var poll := 1.2


func setup(p_net: Net, p_code: String, p_seat: int, p_role: String, p_backlog: Array) -> void:
	net = p_net
	code = p_code
	seat = p_seat
	role = p_role
	backlog = p_backlog
	if OS.get_environment("EN_POLL") != "":
		poll = float(OS.get_environment("EN_POLL"))


func _exit_tree() -> void:
	alive = false


func catching_up() -> bool:
	return n < backlog.size()


## Mossa successiva del registro già scaricata (rientro), oppure {}.
func next_backlog() -> Dictionary:
	if n >= backlog.size():
		return {}
	var a: Dictionary = backlog[n]
	n += 1
	return _val(a)


static func _val(a: Dictionary) -> Dictionary:
	var v = str_to_var(str(a.get("v", "")))
	return v if v is Dictionary else {}


## Pubblica la mossa del posto s come mossa numero n. Se quel numero è già stato scritto da un altro
## dispositivo (per esempio l'IA al posto di un assente) vale quella, che viene restituita.
func publish(s: int, m: Dictionary) -> Dictionary:
	var a := {"s": s, "k": "m", "v": var_to_str(m)}
	while alive:
		if await net.post_act(code, n, a):
			n += 1
			return m
		var ex := await net.get_act(code, n)
		if not ex.is_empty() and not ex.has("_err"):
			n += 1
			return _val(ex)
		_status("Rete non raggiungibile, riprovo… (%s)" % net.last_error)
		await get_tree().create_timer(2.0).timeout
	return m


## Controlla, mentre si decide al proprio posto, se la mossa è già arrivata da un altro dispositivo
## (succede se si era stati segnati assenti e l'IA ha giocato al proprio posto).
func check_forced(my_n: int) -> Dictionary:
	if n != my_n:
		return {}
	var a := await net.get_act(code, my_n)
	if n != my_n or a.is_empty() or a.has("_err"):
		return {}
	n = my_n + 1
	return _val(a)


## Mossa di un posto che non è il proprio: IA (la gioca chi ha creato la stanza), assente, oppure
## da aspettare dal database. ai_fn: Callable che restituisce la mossa dell'IA per quel posto.
func remote_move(s: int, is_ai: bool, ai_fn: Callable, pname: String) -> Dictionary:
	if role == "host":
		if is_ai:
			return await publish(s, ai_fn.call())
		if away.has(s):
			var st := await net.seat(code, s)
			if not alive:
				return {}
			if not st.is_empty() and not st.get("away", false):
				away.erase(s)
			else:
				return await publish(s, ai_fn.call())
	return await _wait(s, ai_fn, pname)


func _wait(s: int, ai_fn: Callable, pname: String) -> Dictionary:
	var my_n := n
	var t0 := Time.get_ticks_msec()
	var last_seen = null
	var seen_t := t0
	var polls := 0
	waiting_seat = s
	slow = false
	_waiting(s, false)
	while alive:
		var a := await net.get_act(code, my_n)
		if not alive:
			break
		if not a.is_empty() and not a.has("_err"):
			n = my_n + 1
			waiting_seat = -1
			_waiting(-1, false)
			return _val(a)
		var now := Time.get_ticks_msec()
		if role == "host" and polls % 4 == 0:
			var st := await net.seat(code, s)
			if not alive:
				break
			if not st.is_empty():
				var seen = st.get("seen", null)
				if seen != last_seen:
					last_seen = seen
					seen_t = now
				if st.get("away", false) or (now - seen_t > 45000 and now - t0 > 60000):
					await net.set_away(code, s, true)
					away[s] = true
					waiting_seat = -1
					_waiting(-1, false)
					_status("%s non risponde: per ora gioca l'IA." % pname)
					return await publish(s, ai_fn.call())
		var sl := now - t0 > 60000
		if sl != slow:
			slow = sl
			_waiting(s, slow)
		polls += 1
		await get_tree().create_timer(poll).timeout
	return {}


## Segnale di presenza ogni 5 secondi (per chi non ha creato la stanza).
func heartbeat_loop() -> void:
	while alive:
		net.heartbeat(code, seat)
		await get_tree().create_timer(5.0).timeout


func finish() -> void:
	if role == "host":
		net.set_status(code, "over")
	net.remember_room("")


func _status(t: String) -> void:
	if view != null and view.has_method("online_status"):
		view.online_status(t)


func _waiting(s: int, is_slow: bool) -> void:
	if view != null and view.has_method("online_waiting"):
		view.online_waiting(s, is_slow)
