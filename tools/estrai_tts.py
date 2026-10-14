"""Estrae i dati di gioco dal salvataggio Tabletop Simulator "Endeavor - Age of Sail (Scripted)".

Uso:
    python3 tools/estrai_tts.py <cartella Mods del mod TTS> [cartella progetto]

Legge Mods/Workshop/1709680050.json (oggetti + script Lua) e Mods/Images, e scrive:
    data/board_a.json, data/board_b.json   mappa dei due lati del tabellone
    data/cards.json                        carte (icone, gloria, valore, immagine)
    data/buildings.json                    edifici (trascritti dalle tessere)
    assets/...                             immagini ritagliate e ridimensionate

Le coordinate sono quelle del tavolo TTS (x, z). Il lato A ha la scansione del tabellone;
il lato B non è nella cache del mod, quindi viene disegnato in modo procedurale.
"""
import json
import os
import re
import shutil
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lua_table as L  # noqa: E402

MODS = sys.argv[1] if len(sys.argv) > 1 else "/mnt/user-data/uploads/Desktop/Endeavor/Mods"
PROJ = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
DATA = os.path.join(PROJ, "data")
ASSETS = os.path.join(PROJ, "assets")
IMAGES = os.path.join(MODS, "Images")

REGIONS = ["north_america", "india", "far_east", "africa", "south_america", "caribbean", "europe"]
REGION_NAMES = {
    "north_america": "Nord America", "india": "India", "far_east": "Estremo Oriente",
    "africa": "Africa", "south_america": "Sud America", "caribbean": "Caraibi",
    "europe": "Europa e Mediterraneo",
}
REGION_COLORS = {
    "north_america": "#4f8a7c", "india": "#8a6aa8", "far_east": "#c98a2e", "africa": "#8a7a5a",
    "south_america": "#6f8a4a", "caribbean": "#b0703c", "europe": "#3f6f8f",
}
TOL = 0.35
# Mare aperto del lato B, misurato sulla scansione (x, z del tavolo).
SEA_B = {"north_america": [-8.33, 3.01], "india": [2.89, 5.11], "far_east": [14.54, 3.91],
         "africa": [12.42, -15.88], "south_america": [-10.44, -14.63], "caribbean": [-6.38, -2.89]}


def board_b_source():
    """Scansione del lato B (4-5 giocatori): l'immagine grande aggiunta a Mods/Images."""
    best = None
    for f in os.listdir(IMAGES):
        if f.startswith("httpssteamusercontent") and f.lower().endswith(".jpg"):
            path = os.path.join(IMAGES, f)
            if best is None or os.path.getsize(path) > os.path.getsize(best):
                best = path
    return best

save = json.load(open(os.path.join(MODS, "Workshop", "1709680050.json")))
lua = save["LuaScript"]
T = lambda name: L.extract(lua, name)  # noqa: E731


def local_image(url):
    key = re.sub(r"[^A-Za-z0-9]", "", url or "")
    for f in os.listdir(IMAGES):
        if os.path.splitext(f)[0] == key:
            return os.path.join(IMAGES, f)
    return None


def xz(p):
    return [round(p[0], 2), round(p[2], 2)]


def same(a, b, tol=TOL):
    return abs(a[0] - b[0]) <= tol and abs(a[1] - b[1]) <= tol


def find(lst, p):
    for i, q in enumerate(lst):
        if same(q, p):
            return i
    return -1


def flat_positions(entry):
    """CheckDisc / LinkToken: 0, una posizione, o una lista di posizioni."""
    if entry == 0 or entry is None:
        return []
    if isinstance(entry[0], (int, float)):
        return [xz(entry)]
    return [xz(e) for e in entry]


def build_side(side):
    s = str(side)
    tracks_raw = T("tPosTracksByRegion" + s)
    presence = T("tPosPresence" + s)
    cities_by_region = T("tPosCitiesByRegion" + s)
    link_index = [xz(p) for p in T("tPosLinkIndex" + s)]
    check_disc = T("tPosCheckDisc" + s)
    link_tok = T("tPosLinkToken" + s)
    glory1 = [xz(p) for p in T("tPos1Glory" + s)]
    glory2 = [xz(p) for p in T("tPos2Glory" + s)]
    seas = [xz(p) for p in T("tPosSeaZones" + s)]
    if side == 2:
        # Nel mod il lato B riusa le posizioni del mare del lato A: corrette sulla scansione del lato B.
        seas = [SEA_B[r] for r in REGIONS[:6]]
    token_spots = [xz(p) for p in T("tPosTradeTokens" + s)]

    # Tracciati: nel Lua l'indice 1 è lo spazio vicino al mazzo (riempito per ultimo).
    tracks = {}
    for ri, lst in enumerate(tracks_raw):
        tracks[REGIONS[ri]] = [xz(p) for p in reversed(lst)]

    nodes = []
    for ri, lst in enumerate(presence):
        rid = REGIONS[ri]
        track_pts = tracks.get(rid, [])
        city_pts = [xz(p) for p in cities_by_region[ri]]
        for p in lst:
            p = xz(p)
            if find(track_pts, p) >= 0:
                continue
            kind = "city" if find(city_pts, p) >= 0 else "fleet"
            glory = 2 if find(glory2, p) >= 0 else (1 if find(glory1, p) >= 0 else 0)
            if kind == "fleet":
                glory = 0
            nodes.append({"id": "%s_%d" % (rid[:2] if rid != "south_america" else "sa", len([n for n in nodes if n["region"] == rid]) + 1),
                          "region": rid, "kind": kind, "glory": glory, "pos": p})
    # nomi stabili e univoci
    for n in nodes:
        n["id"] = "%s_%s" % ({"north_america": "na", "india": "in", "far_east": "fe", "africa": "af",
                              "south_america": "sa", "caribbean": "ca", "europe": "eu"}[n["region"]], n["id"].split("_")[-1])
    node_pts = [n["pos"] for n in nodes]
    for p in link_index:
        assert find(node_pts, p) >= 0, ("nodo collegato non trovato", side, p)

    links = []
    seen = set()
    for i, p in enumerate(link_index):
        a = find(node_pts, p)
        others = flat_positions(check_disc[i])
        toks = flat_positions(link_tok[i])
        for k, q in enumerate(others):
            b = find(node_pts, q)
            assert b >= 0, ("vicino non trovato", side, q)
            key = tuple(sorted((a, b)))
            if a == b or key in seen:
                continue
            seen.add(key)
            tp = toks[k] if k < len(toks) else [(p[0] + q[0]) / 2, (p[1] + q[1]) / 2]
            links.append({"a": nodes[a]["id"], "b": nodes[b]["id"], "pos": [round(tp[0], 2), round(tp[1], 2)],
                          "token": find(token_spots, tp) >= 0})

    # Collegamenti "quadrati" (senza token): solo nella tabella di punteggio tBoardLinks.
    for i, entry in enumerate(T("tBoardLinks" + s)):
        for j in (entry if isinstance(entry, list) else [entry]):
            if not j:
                continue
            a = find(node_pts, link_index[i])
            b = find(node_pts, link_index[j - 1])
            key = tuple(sorted((a, b)))
            if a == b or key in seen:
                continue
            seen.add(key)
            pa, pb = nodes[a]["pos"], nodes[b]["pos"]
            links.append({"a": nodes[a]["id"], "b": nodes[b]["id"],
                          "pos": [round((pa[0] + pb[0]) / 2, 2), round((pa[1] + pb[1]) / 2, 2)], "token": False})

    # Verifica: ogni posizione token deve corrispondere a uno spazio noto.
    used = 0
    for tp in token_spots:
        if any(find(v, tp) >= 0 for v in tracks.values()) or find(node_pts, tp) >= 0 \
                or any(same(l["pos"], tp) for l in links):
            used += 1
        else:
            print("  token non assegnato (lato %s): %s" % (s, tp))
    n_link_tok = sum(1 for l in links if l["token"])
    node_tok = len(nodes)
    print("Lato %s: %d nodi (%d città, %d flotte), %d collegamenti (%d con token), tracciati %s, token %d/%d" % (
        s, len(nodes), sum(n["kind"] == "city" for n in nodes), sum(n["kind"] == "fleet" for n in nodes),
        len(links), n_link_tok, {k: len(v) for k, v in tracks.items()}, used, len(token_spots)))
    total = node_tok + n_link_tok + sum(len(v) for v in tracks.values())
    print("  spazi con token calcolati:", total)

    decks = {
        "north_america": [-10.97, 11.35], "india": [-4.37, 11.35], "far_east": [8.25, 11.29],
        "africa": [14.26, -12.13], "south_america": [-13.77, -17.35], "caribbean": [-14.29, -10.23],
        "europe": [14.27, -1.94], "slavery": [14.27, -6.86],
    }
    govs = {REGIONS[i]: xz(p) for i, p in enumerate(T("tPosGovCards"))}
    if side == 2:
        decks["far_east"] = xz(T("tPosFarEast2")[0])
        govs["far_east"] = xz(T("tPosFarEast2")[1])
    regions = []
    for i, rid in enumerate(REGIONS):
        regions.append({"id": rid, "name": REGION_NAMES[rid], "color": REGION_COLORS[rid],
                        "start_open": rid == "europe", "sea": seas[i] if i < 6 else None,
                        "deck_pos": decks[rid], "gov_pos": govs.get(rid)})
    out = {
        "_nota": "Generato da tools/estrai_tts.py dal mod TTS 1709680050. Coordinate x,z del tavolo TTS.",
        "side": "A" if side == 1 else "B",
        "players": "2-4" if side == 1 else "4-5",
        "bounds": [-16.09, -19.1, 16.09, 13.1],
        "image": "res://assets/board_a.jpg" if side == 1 else ("res://assets/board_b.jpg" if board_b_source() else ""),
        "regions": regions, "nodes": nodes, "links": links, "tracks": tracks,
        "slavery_deck_pos": decks["slavery"], "discard_pos": [17.98, -1.95],
    }
    json.dump(out, open(os.path.join(DATA, "board_%s.json" % ("a" if side == 1 else "b")), "w"), ensure_ascii=False, indent=1)
    return out


def objects():
    def walk(o):
        yield o
        for c in o.get("ContainedObjects") or []:
            yield from walk(c)
        for st in (o.get("States") or {}).values():
            yield from walk(st)
    for top in save["ObjectStates"]:
        yield from walk(top)


def build_cards():
    os.makedirs(os.path.join(ASSETS, "cards"), exist_ok=True)
    guid_obj = {o.get("GUID"): o for o in objects()}
    icons = T("tTrackCards")
    glory = T("tGloryCards")
    order = T("tAssetCardGUIDs")
    one_disc = set(T("tCard1DiscGUIDs"))
    attr = ["industry", "culture", "finance", "influence"]
    deck_names = REGIONS[:6] + ["europe", "slavery"]
    sheets = {}
    cards = []
    for di, guids in enumerate(order):
        rid = deck_names[di]
        for k, g in enumerate(guids):
            o = guid_obj[g]
            ic = {}
            for a, v in zip(attr, icons.get(g, [0, 0, 0, 0])):
                if v:
                    ic[a] = v
            if glory.get(g):
                ic["glory"] = glory[g]
            if rid in ("europe", "slavery"):
                value = k
                cid = "%s_%d" % (rid, value)
            elif k == 0:
                value = 0
                cid = rid + "_gov"
            else:
                value = k
                cid = "%s_%d" % (rid, value)
            c = {"id": cid, "region": "europe" if rid == "slavery" else rid,
                 "deck": "slavery" if rid == "slavery" else "main", "value": value, "icons": ic}
            if rid not in ("europe", "slavery") and k == 0:
                c["governor"] = True
            if rid == "slavery":
                c["slavery"] = True
            if rid == "europe" and value == 5:
                c["abolition"] = True
            if g in one_disc:
                c["bonus_disc"] = True
            # immagine
            cd = list(o["CustomDeck"].items())[0][1]
            src = local_image(cd["FaceURL"])
            idx = o["CardID"] % 100
            nw, nh = cd["NumWidth"], cd["NumHeight"]
            if src not in sheets:
                sheets[src] = Image.open(src).convert("RGB")
            im = sheets[src]
            w, h = im.width / nw, im.height / nh
            crop = im.crop((int((idx % nw) * w), int((idx // nw) * h), int((idx % nw + 1) * w), int((idx // nw + 1) * h)))
            crop.thumbnail((300, 460))
            crop.save(os.path.join(ASSETS, "cards", cid + ".jpg"), quality=88)
            c["image"] = "res://assets/cards/%s.jpg" % cid
            cards.append(c)
    json.dump({"_nota": "Icone e gloria dallo script del mod TTS, valori dall'ordine dei mazzi; verificati sulle immagini.",
               "cards": cards}, open(os.path.join(DATA, "cards.json"), "w"), ensure_ascii=False, indent=1)
    print("Carte:", len(cards))


# Edifici trascritti dalle tessere (immagini nel mod). Azioni: "a|b" = una a scelta, voci separate = entrambe.
BUILDINGS = [
    # id, nome, livello, copie, icone, azioni, url immagine, extra
    ("colonial_house", "Casa coloniale", 0, 0, {}, ["occupy"], "rmbpwL2", {"start": True}),
    ("merchant_dock", "Molo mercantile", 0, 0, {"finance": 1}, ["ship"], "77ocXjo", {"start": True}),
    ("workshop", "Laboratorio", 1, 5, {"industry": 2}, [], "72T9hdg", {}),
    ("market", "Mercato", 1, 5, {}, ["draw"], "P7CTiV1", {"verify": "simbolo scala in basso a sinistra"}),
    ("shipyard", "Cantiere navale", 1, 5, {"culture": 1}, ["ship"], "MRm0ZS6", {}),
    ("bank", "Banca", 2, 4, {"finance": 2}, [], "gE1VEI9", {}),
    ("barracks", "Caserma", 2, 4, {}, ["attack"], "qbK2V7j", {}),
    ("guild_hall", "Corporazione", 2, 4, {}, ["draw|ship"], "N1y8o4G", {}),
    ("theatre", "Teatro", 3, 3, {"culture": 2}, [], "EbnR2hX", {}),
    ("fortress", "Fortezza", 3, 3, {"influence": 1}, ["occupy|attack"], "AS4jNo3", {}),
    ("docks", "Moli", 3, 3, {}, ["ship", "occupy"], "955j0I5", {}),
    ("university", "Università", 4, 2, {"glory": 3}, [], "RBa7O3O", {}),
    ("trade_office", "Ufficio commerciale", 4, 2, {}, ["draw", "draw"], "ttiE8Mq", {}),
    ("cartographer", "Cartografo", 4, 2, {}, ["ship", "ship"], "16YupgY", {"verify": "simbolo scala in basso a sinistra"}),
    ("museum", "Museo", 5, 1, {"culture": 2}, ["payment"], "NF5mlJS", {}),
    ("palace", "Palazzo", 5, 1, {"industry": 1, "culture": 1, "finance": 1, "influence": 1}, [], "F9Hv4Xy", {}),
    ("treasury", "Tesoreria", 5, 1, {"glory": 2}, ["payment", "payment"], "DT3zJaX", {}),
    ("city_hall", "Municipio", 5, 1, {}, ["occupy|draw"], "cGcgkkb", {"special": "city_hall"}),
    ("parliament", "Parlamento", 5, 1, {"influence": 2}, ["payment"], "8luMQ7u", {}),
    ("exchange", "Borsa", 5, 1, {"finance": 2}, ["payment"], "eEyHNpF", {}),
    ("memorial", "Memoriale", 5, 1, {}, ["ship|attack"], "LHBXv9t", {"special": "memorial"}),
]


# Compagnie privilegiate (mini-espansione Charter Companies, presente nel mod).
# Icone e simboli dalle tessere, confermati dalle tabelle Lua (tTrackCharters, tGloryBuildings,
# tDraw/Attack/ShipCharterGUIDs). Si prendono in Costruzione con 6+ presenza nella regione,
# una per giocatore per partita; il colono sopra non si libera con un'azione Pagamento.
CHARTERS = [
    ("north_america", "Nord America", {"finance": 1, "influence": 1}, ["ship", "draw"], "hQVXtja", [-14.19, 14.89]),
    ("india", "India", {"industry": 1, "influence": 1}, ["attack", "occupy"], "y6Yc0pu", [-1.07, 14.88]),
    ("far_east", "Estremo Oriente", {"glory": 2}, ["draw", "attack"], "QboQCyI", [11.55, 14.86]),
    ("africa", "Africa", {"culture": 1, "influence": 1}, ["ship", "payment"], "2GuX5Go", [17.37, -15.89]),
    ("south_america", "Sud America", {"industry": 2}, ["draw", "payment"], "YGwJm9X", [-17.37, -17.33]),
    ("caribbean", "Caraibi", {"culture": 1, "finance": 1}, ["ship", "attack"], "Mv0aupa", [-17.36, -6.56]),
]
CHARTER_POS_B = {"far_east": [11.30, 14.86]}   # sul lato B il mod sposta i pezzi dell'Estremo Oriente
EXTRA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "immagini_extra")


def build_buildings():
    os.makedirs(os.path.join(ASSETS, "buildings"), exist_ok=True)
    out = []
    for bid, name, lvl, cnt, icons, actions, key, extra in BUILDINGS:
        src = None
        for f in os.listdir(IMAGES):
            if key in f:
                src = os.path.join(IMAGES, f)
        extra_img = os.path.join(EXTRA, bid + ".png")
        if os.path.exists(extra_img):
            src = extra_img
        b = {"id": bid, "name": name, "level": lvl, "count": cnt, "icons": icons, "actions": actions}
        b.update(extra)
        if src:
            im = Image.open(src).convert("RGBA")
            im.thumbnail((265, 354))
            im.save(os.path.join(ASSETS, "buildings", bid + ".png"))
            b["image"] = "res://assets/buildings/%s.png" % bid
        out.append(b)
    for rid, rname, icons, actions, key, pos in CHARTERS:
        bid = "charter_" + rid
        b = {"id": bid, "name": "Compagnia privilegiata " + rname, "level": 0, "count": 0, "icons": icons,
             "actions": actions, "charter": rid, "presence": 6, "no_pay": True,
             "pos_a": pos, "pos_b": CHARTER_POS_B.get(rid, pos)}
        src = local_image("https://i.imgur.com/%s.png" % key)
        if src:
            im = Image.open(src).convert("RGBA")
            im.thumbnail((265, 354))
            im.save(os.path.join(ASSETS, "buildings", bid + ".png"))
            b["image"] = "res://assets/buildings/%s.png" % bid
        out.append(b)
    json.dump({"_nota": "Trascritti dalle tessere del mod. Le voci con 'verify' hanno l'immagine mancante o un simbolo non chiaro.",
               "buildings": out}, open(os.path.join(DATA, "buildings.json"), "w"), ensure_ascii=False, indent=1)
    print("Edifici:", len(out))


TOKEN_TEX = {"influence": "wk5k5cX", "industry": "6j7kfqH", "culture": "UYS72sv", "finance": "opYsUoJ",
             "occupy_draw": "yAIwtfH", "ship_draw": "Q3XSIg1", "attack": "KHMUEst", "payment": "nE5QNOK"}


def build_tokens():
    """Facce dei token commercio/azione: la texture del modello TTS ha la faccia a sinistra e il retro a destra."""
    from PIL import ImageDraw
    os.makedirs(os.path.join(ASSETS, "tokens"), exist_ok=True)
    for name, key in TOKEN_TEX.items():
        src = local_image("https://i.imgur.com/%s.png" % key)
        if not src:
            print("  token mancante:", name)
            continue
        im = Image.open(src).convert("RGBA")
        sx = im.width / 672.0
        cx, cy, r = 160 * sx, 140 * sx, 127 * sx
        face = im.crop((int(cx - r), int(cy - r), int(cx + r), int(cy + r))).resize((192, 192), Image.LANCZOS)
        mask = Image.new("L", (192 * 4, 192 * 4), 0)
        ImageDraw.Draw(mask).ellipse((6, 6, 192 * 4 - 6, 192 * 4 - 6), fill=255)
        face.putalpha(mask.resize((192, 192), Image.LANCZOS))
        face.save(os.path.join(ASSETS, "tokens", name + ".png"))
    print("Token pronti")


## Token degli Exploit (immagini dei Custom_Token / Custom_Tile del mod).
XTOKEN_TEX = {
    "missionary": "mdOUM8u", "cannon": "JImFILT", "fort": "XVQmceW",
    "freedom_finance": "x1gzt3X", "freedom_culture": "ttI2apE", "freedom_influence": "I6ytoGX",
    "transit_finance": "3kGhKdT", "transit_culture": "cgTrjRS", "transit_influence": "DASIxis",
    "transit_glory": "UCNc7eq",
    # Azioni della Compagnia dei Mari del Sud: in alto il bonus immediato, in basso quello continuo.
    "share_back": "uLKA1AB", "share_pay_industry": "LGsOKOP", "share_disc_glory": "OdeRoCw",
    "share_disc_industry": "fS7FgCd", "share_pay_glory": "7azRCM7", "share_disc2_industry": "jZanaww",
    # Scudi dei giocatori: il mod ne mette uno sull'Exploit quando il giocatore ha presenza in
    # entrambe le regioni (= può usarlo). Chiave: una per regione aperta, due sbloccano l'Exploit.
    "shield_blue": "EafYQrw", "shield_red": "uKFBc6Q", "shield_white": "N4FKFGd",
    "shield_purple": "spMHGgw", "shield_yellow": "rdWuWFX", "key": "SO7n3tS",
    "blockade": "YhXObXr", "pirate_ship": "thjCYhS",
}
GALLEON_TEX = "LbgypPG"   # modello del Galeone: faccia "+1 disco" a sinistra, "pagamento" a destra


def build_xtokens():
    from PIL import ImageDraw
    out_dir = os.path.join(ASSETS, "xtokens")
    os.makedirs(out_dir, exist_ok=True)
    for name, key in XTOKEN_TEX.items():
        src = local_image("https://i.imgur.com/%s.png" % key)
        if not src:
            print("  token Exploit mancante:", name)
            continue
        im = Image.open(src).convert("RGBA")
        bb = im.getchannel("A").point(lambda a: 255 if a > 20 else 0).getbbox()
        if bb:
            im = im.crop(bb)
        side = max(im.size)
        sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        sq.alpha_composite(im, ((side - im.width) // 2, (side - im.height) // 2))
        sq.resize((192, 192), Image.LANCZOS).save(os.path.join(out_dir, name + ".png"))
    src = local_image("https://i.imgur.com/%s.png" % GALLEON_TEX)
    if src:
        im = Image.open(src).convert("RGBA")
        sx = im.width / 672.0
        for name, cx in [("galleon_disc", 160), ("galleon_pay", 432)]:
            r = 127 * sx
            face = im.crop((int(cx * sx - r), int(140 * sx - r), int(cx * sx + r), int(140 * sx + r))).resize((192, 192), Image.LANCZOS)
            mask = Image.new("L", (768, 768), 0)
            ImageDraw.Draw(mask).ellipse((6, 6, 762, 762), fill=255)
            face.putalpha(mask.resize((192, 192), Image.LANCZOS))
            face.save(os.path.join(out_dir, name + ".png"))
    else:
        print("  Galeone mancante")
    print("Token Exploit pronti")


def build_menu_art():
    """Logo del gioco (dal piano del tavolo del mod) e copertina, se fornita in immagini_extra."""
    import numpy as np
    src = local_image("https://i.imgur.com/i1JopUx.jpg")
    if src:
        im = Image.open(src).convert("RGB").crop((690, 0, 2210, 335))
        w, h = im.size
        a = np.ones((h, w), dtype=float)
        f = 60
        for i in range(f):
            v = (i + 1) / f
            a[:, i] = np.minimum(a[:, i], v)
            a[:, w - 1 - i] = np.minimum(a[:, w - 1 - i], v)
            a[i, :] = np.minimum(a[i, :], v)
            a[h - 1 - i, :] = np.minimum(a[h - 1 - i, :], v)
        out = np.dstack([np.asarray(im), (a * 255).astype(np.uint8)])
        Image.fromarray(out, "RGBA").resize((w * 2 // 3, h * 2 // 3), Image.LANCZOS).save(os.path.join(ASSETS, "logo.png"))
    for ext in ("jpg", "jpeg", "png", "webp"):
        cov = os.path.join(EXTRA, "copertina." + ext)
        if os.path.exists(cov):
            im = Image.open(cov).convert("RGB")
            im.thumbnail((2400, 2400))
            im.save(os.path.join(ASSETS, "copertina.jpg"), quality=90)
            print("Copertina pronta")
            break
    print("Logo pronto")


def clean_seams(im):
    """La scansione del lato B è cucita: righe chiare lungo la cucitura e una colonna bianca sul bordo
    destro della metà alta. Si sostituiscono con i pixel vicini (si cercano, non sono a posizioni fisse)."""
    import numpy as np
    a = np.asarray(im).astype(np.int16)
    h, w = a.shape[:2]
    lum = a.mean(axis=2)
    mid = h // 2
    band = range(max(1, mid - 60), min(h - 1, mid + 60))
    base = np.median(lum[mid - 80:mid + 80, w // 10:w * 9 // 10])
    bad = [y for y in band if (lum[y, w // 10:w * 9 // 10] > 235).mean() > 0.25 or lum[y, w // 10:w * 9 // 10].mean() > base + 25]
    for y in bad:
        y0 = y - 1
        while y0 in bad:
            y0 -= 1
        y1 = y + 1
        while y1 in bad:
            y1 += 1
        t = (y - y0) / (y1 - y0)
        a[y] = (a[y0] * (1 - t) + a[y1] * t).astype(np.int16)
    for x in range(w - 6, w):
        top = lum[: mid, x]
        if top.mean() > 180:
            a[: mid, x] = a[: mid, w - 7]
    print("  cuciture ripulite: righe", bad)
    return Image.fromarray(a.clip(0, 255).astype(np.uint8))


def build_images():
    src_b = board_b_source()
    if src_b:
        im = Image.open(src_b).convert("RGB").rotate(180)  # la scansione è capovolta rispetto al tavolo TTS
        im.thumbnail((3072, 3072))
        im = clean_seams(im)
        im.save(os.path.join(ASSETS, "board_b.jpg"), quality=86)
    board = local_image("https://i.imgur.com/GNK2dFK.jpg")
    im = Image.open(board).convert("RGB")
    im.thumbnail((3072, 3072))
    im.save(os.path.join(ASSETS, "board_a.jpg"), quality=86)
    # tessere Exploit (6x3 sul foglio)
    os.makedirs(os.path.join(ASSETS, "exploits"), exist_ok=True)
    sheet = Image.open(local_image("https://i.imgur.com/B7r8Xhh.jpg")).convert("RGB")
    w, h = sheet.width / 6, sheet.height / 3
    for o in objects():
        n = o.get("Nickname", "")
        if n.startswith("Exploit (") and "CardID" in o:
            idx = o["CardID"] % 100
            crop = sheet.crop((int((idx % 6) * w), int((idx // 6) * h), int((idx % 6 + 1) * w), int((idx // 6 + 1) * h)))
            crop.save(os.path.join(ASSETS, "exploits", o["GUID"] + ".jpg"), quality=90)
    for key, name in [("drOAjxC", "aiuto_giocatore.jpg"), ("s5V38kn", "plancia.jpg")]:
        src = local_image("https://i.imgur.com/%s.jpg" % key)
        if src:
            im = Image.open(src).convert("RGB")
            im.thumbnail((2000, 2000))
            im.save(os.path.join(ASSETS, name), quality=86)
    print("Immagini pronte")


if __name__ == "__main__":
    os.makedirs(DATA, exist_ok=True)
    os.makedirs(ASSETS, exist_ok=True)
    build_side(1)
    build_side(2)
    build_cards()
    build_buildings()
    build_images()
    build_tokens()
    build_xtokens()
    build_menu_art()
    try:   # allinea le scansioni ai dati (richiede opencv)
        import calibra_scansioni
        calibra_scansioni.calibrate("a")
        calibra_scansioni.calibrate("b")
    except ImportError:
        print("opencv assente: scansioni non calibrate (si usano i bounds del tabellone)")
