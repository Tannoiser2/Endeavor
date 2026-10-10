"""Allinea le scansioni del tabellone alle coordinate del mod TTS.

Per ogni spazio noto (città, flotte, tracciati, cerchi dei collegamenti) cerca il cerchio stampato
più vicino nella scansione (trasformata di Hough), poi calcola con i minimi quadrati la
trasformazione tavolo → pixel (scala e traslazione separate per x e z) e la salva in
data/board_*.json come "image_bounds": il rettangolo del tavolo coperto dall'immagine.
Uso: python3 tools/calibra_scansioni.py
"""
import json
import os
import sys

import cv2
import numpy as np

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


def calibrate(side):
    path = os.path.join(ROOT, "data", "board_%s.json" % side)
    b = json.load(open(path))
    img = cv2.imread(os.path.join(ROOT, "assets", "board_%s.jpg" % side))
    if img is None:
        print("scansione mancante, lato", side)
        return
    H, W = img.shape[:2]
    x0, z0, x1, z1 = b["bounds"]
    gray = cv2.medianBlur(cv2.cvtColor(img, cv2.COLOR_BGR2GRAY), 5)
    ppu = W / (x1 - x0)

    def to_px(p):
        return ((p[0] - x0) / (x1 - x0) * W, (z1 - p[1]) / (z1 - z0) * H)

    pts = [(n["pos"], 0.53) for n in b["nodes"]]
    pts += [(l["pos"], 0.58) for l in b["links"] if l["token"]]
    for tr in b["tracks"].values():
        pts += [(p, 0.55) for p in tr]
    world, pix = [], []
    for p, r_units in pts:
        px, py = to_px(p)
        win = int(ppu * 1.2)
        xa, ya = int(max(0, px - win)), int(max(0, py - win))
        crop = gray[ya:int(py + win), xa:int(px + win)]
        r = r_units * ppu
        circles = cv2.HoughCircles(crop, cv2.HOUGH_GRADIENT, dp=1, minDist=r, param1=90, param2=22,
                                   minRadius=int(r * 0.75), maxRadius=int(r * 1.25))
        if circles is None:
            continue
        cx, cy = px - xa, py - ya
        best = min(circles[0], key=lambda c: (c[0] - cx) ** 2 + (c[1] - cy) ** 2)
        if (best[0] - cx) ** 2 + (best[1] - cy) ** 2 > (ppu * 0.6) ** 2:
            continue
        world.append(p)
        pix.append((best[0] + xa, best[1] + ya))
    world = np.array(world, float)
    pix = np.array(pix, float)
    # Le scansioni possono essere fatte di due metà unite: calibro le due metà (sopra/sotto la
    # cucitura) separatamente e salvo per ognuna la porzione di immagine e il rettangolo del tavolo.
    parts = []
    for top in (True, False):
        sel = pix[:, 1] < H / 2 if top else pix[:, 1] >= H / 2
        w, q = world[sel], pix[sel]
        keep = np.ones(len(w), bool)
        for _ in range(3):
            ax, bx = np.polyfit(w[keep, 0], q[keep, 0], 1)
            ay, by = np.polyfit(w[keep, 1], q[keep, 1], 1)
            err = np.hypot(w[:, 0] * ax + bx - q[:, 0], w[:, 1] * ay + by - q[:, 1])
            keep = err < max(5.0, np.median(err) * 3)
        err = err[keep]
        # le due porzioni si sovrappongono di qualche pixel per non lasciare una fessura alla cucitura
        py0, py1 = (0, H // 2 + 14) if top else (H // 2 - 14, H)
        dst = [(0 - bx) / ax, (py1 - by) / ay, (W - bx) / ax, (py0 - by) / ay]   # x0, z0, x1, z1
        parts.append({"src": [0, int(py0), int(W), int(py1 - py0)], "dst": [round(float(v), 4) for v in dst]})
        print("  lato %s metà %s: %d cerchi, errore medio %.1f px (max %.1f)" % (
            side.upper(), "alta" if top else "bassa", keep.sum(), err.mean(), err.max()))
    b["image_parts"] = parts
    b.pop("image_bounds", None)
    json.dump(b, open(path, "w"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    for side in sys.argv[1:] or ["a", "b"]:
        calibrate(side)
