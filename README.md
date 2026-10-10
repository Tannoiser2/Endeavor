# Endeavor: Age of Sail — versione digitale (Godot 4)

Endeavor: Age of Sail con tutti e 15 gli Exploit, per 2–5 giocatori, in hotseat e/o contro IA
(principiante, normale, esperta). Dati e grafica arrivano dal mod Tabletop Simulator
"Endeavor - Age of Sail (Scripted)" (Workshop 1709680050).

## Avvio
Apri la cartella con Godot 4.5+ (testato su 4.5, compatibile con 4.7) e premi Play.
Al primo avvio Godot importa le immagini in `assets/`.

## Menu e fine partita
- Menu iniziale: copertina a sinistra (`tools/immagini_extra/copertina.webp`, convertita dall'estrattore in
  `assets/copertina.jpg`), impostazioni a destra; senza copertina si usa il logo del tavolo del mod.
- A fine partita: classifica con il dettaglio dei punti e tre pulsanti, **Guarda il tabellone** (chiude la
  classifica; il pulsante **Punteggi finali** la riapre), **Rivincita** (stessi giocatori e opzioni) e **Menu iniziale**.

## Come si gioca (tutto a clic)
- **Tabellone** (a sinistra, scansioni originali dei lati A e B): token commercio originali sugli
  spazi, carte regione a faccia in su nei loro spazi, Governatori ancora da assegnare fuori dal
  bordo, pila degli scarti di Europa, dischi dei giocatori che arrivano animati.
- **Plance** (al centro quella di turno, a destra tutte): solo la plancia originale, senza
  intestazioni; la Gloria attuale è nell'angolo del porto, sotto porto e riserva.
- **Plancia del giocatore di turno** (al centro): clic su un edificio = ci metti un colono e si
  illuminano i bersagli possibili; clic sul bersaglio (città, flotta, mare aperto, tracciato,
  mazzo, scarti, oppure un edificio occupato per un Pagamento) = l'azione parte. Di nuovo clic
  sull'edificio = il colono torna nel porto. I token azione nel porto si usano allo stesso modo.
  Nello Scarto si clicca la carta da scartare.
- **Edifici disponibili** (sotto la plancia): clic per costruire.
- **Tessere Exploit** (sotto il tabellone, come nel mod): coloni, token, città e pile sugli spazi
  veri delle tessere; scudi colorati del mod sopra il testo = chi può usarle (presenza in entrambe le
  regioni); una chiave sullo stemma di ogni regione aperta, velo scuro finché non ci sono le due chiavi. Clic sulla tessera per giocarne l'azione (se ce ne sono più, un menu breve).
- Pulsanti solo per Passa, Annulla e poche sotto-scelte degli Exploit (es. quale token Libertà).
- **Scelte obbligate automatiche**: un'azione con un solo bersaglio parte subito; se i pagamenti
  bastano gli edifici si liberano da soli; altrimenti clicchi la scelta più breve, cioè gli edifici
  da liberare o quelli che restano impegnati (marcati subito "RESTA IMPEGNATO"); con un
  solo edificio costruibile si costruisce da solo; i Galeoni chiedono solo se servono come pagamento.
- Tasto destro su carte ed edifici per ingrandirli; doppio clic su una plancia nella scheda
  Giocatori per vederla in grande; rotellina e tasto destro trascinato per zoom e spostamento sul tabellone.

## Da dove vengono i dati
`tools/estrai_tts.py` legge il salvataggio del mod (oggetti + script Lua) e la cache immagini:

```
python3 tools/estrai_tts.py "~/Desktop/Endeavor/Mods" .
```

- **Tabellone, lati A e B**: scansione del lato A dalla cache del mod; per il lato B la scansione
  aggiunta in `Mods/Images` (capovolta di 180° rispetto al tavolo e raddrizzata dall'estrattore,
  che ricalcola anche il mare aperto, nel mod copiato dal lato A). Città, spazi flotta, collegamenti (tondi con token e a rombo senza),
  tracciati di navigazione, mare aperto e le 95 posizioni dei token, dalle tabelle Lua del mod.
- **Token**: facce dei token commercio e azione ritagliate dalle texture dei modelli del mod.
- **Carte**: icone, Gloria e bonus +1 disco dalle tabelle Lua; valori dall'ordine dei mazzi;
  immagini ritagliate dai fogli del mod.
- **Tabelle della plancia**: soglie 0/2/4/7/10 per livello edifici, crescita (2–6), pagamenti (1–5),
  carte (1–5 + uno slot per una carta Schiavitù) e Gloria dei tracciati.
- **Edifici**: trascritti dalle tessere; 3 edifici di livello 5 su 7 per partita, come nel mod.
- **Compagnie privilegiate** (Charter Co., attivabili dal menu): una per regione, sul tavolo dove le
  mette il mod. In Costruzione, con 6+ presenza nella regione, se ne prende una al posto di un
  edificio (una per giocatore, occupa uno spazio del porto); due azioni insieme, e il colono sopra
  non si libera con un'azione Pagamento. Icone e simboli dalle tessere e dallo script del mod.
- **Molo mercantile**: immagine fornita a parte (`tools/immagini_extra/`).
- **Token degli Exploit** (`assets/xtokens/`): Missionari, Cannoni migliorati, Fortificazioni, Galeoni,
  token Libertà e Transito, le 5 Azioni della Compagnia dei Mari del Sud (con il retro). Sulle tessere
  stanno nel riquadro della scorta; quelli presi vanno sulla plancia (Libertà/Transito nei cerchi dei
  tracciati, Cannoni/Galeoni/Azioni/Gloria nella riga del porto, Cannoni al lavoro sugli edifici).
- **Azioni dei Mari del Sud** (dai token): Pagamento / +1 Industria · +1 disco / Gloria ·
  +1 disco / +1 Industria · Pagamento / Gloria · +2 dischi / +1 Industria (in alto subito, in basso se la tieni);
  le Azioni sono scoperte e chi le prende sceglie quale.
- **Calibrazione**: `tools/calibra_scansioni.py` trova i cerchi stampati sulle scansioni e allinea
  immagine e dati (lato B in due metà, perché la scansione è cucita): errore 2-4 px su 3000.
- **Exploit**: regioni dallo script del mod, regole dalle tessere. 3 per partita; si sbloccano
  quando entrambe le regioni sono aperte e si usano solo con presenza in entrambe.

## Struttura
```
data/                  JSON generati (board_a/b, cards, buildings, rules, tokens, exploits)
assets/                tabellone A, carte, edifici, tessere Exploit, aiuto giocatore
scripts/core/rules.gd  motore delle regole puro (stato = Dictionary)
scripts/core/exploits/ uno script per Exploit (agganci in exploit_base.gd)
scripts/ai/            IA a simulazione con pesi in AIPlayer.W
scripts/ui/            menu, tabellone, schermata di gioco
tests/                 sim.gd (IA vs IA), fuzz.gd (mosse casuali), screenshot dell'interfaccia (ui_*.gd)
tools/                 estrattore dal mod TTS
```

## Test
```
godot --headless --path . -s res://tests/sim.gd -- 15 4        # 15 partite IA, 4 giocatori
godot --headless --path . -s res://tests/fuzz.gd -- 90 4       # mosse casuali, regioni aperte
godot --headless --path . -s res://tests/payment_test.gd       # pagamenti: regole e clic
godot --headless --path . -s res://tests/charter_test.gd       # Compagnie privilegiate
godot --headless --path . -s res://tests/share_test.gd         # Azioni dei Mari del Sud
```
Entrambi controllano che i 35 dischi di ogni giocatore siano sempre tutti al loro posto.

## Da verificare sulla copia fisica
Mancano nella cache del mod e sono quindi ipotesi segnate con `verify` nei JSON:
- **Borsa** e **Memoriale** (livello 5): immagine assente; azioni ricavate dai conteggi dello script.
- **Simbolo "scala"** su Mercato e Cartografo: non interpretato.
- **Transito di Venere**: la ramificazione dopo Tahiti (Nuova Zelanda / Australia) è interpretata dall'immagine.
- Non implementata: variante a 2 giocatori "Silent Fleet" (il foglio della variante non è nella cache).
- Il Governatore ottenuto va automaticamente nello spazio libero se è vuoto.
- Il Governatore del Sud America è disegnato sul bordo sinistro (nel mod sta sotto il tabellone), per far
  posto alle tessere Exploit, che ora occupano tutta la larghezza.
