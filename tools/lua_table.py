"""Mini parser per costruttori di tabelle Lua (numeri, stringhe, tabelle annidate, chiavi)."""
import re


class _P:
    def __init__(self, s):
        self.s, self.i = s, 0

    def ws(self):
        while self.i < len(self.s):
            if self.s.startswith("--", self.i):
                j = self.s.find("\n", self.i)
                self.i = len(self.s) if j < 0 else j + 1
            elif self.s[self.i] in " \t\r\n":
                self.i += 1
            else:
                break

    def val(self):
        self.ws()
        c = self.s[self.i]
        if c == "{":
            return self.table()
        if c in "\"'":
            j = self.s.index(c, self.i + 1)
            v = self.s[self.i + 1:j]
            self.i = j + 1
            return v
        m = re.compile(r"-?\d+(\.\d+)?").match(self.s, self.i)
        if m:
            self.i = m.end()
            t = m.group(0)
            return float(t) if "." in t else int(t)
        m = re.compile(r"true|false|nil").match(self.s, self.i)
        if m:
            self.i = m.end()
            return {"true": True, "false": False, "nil": None}[m.group(0)]
        raise ValueError("token inatteso a %d: %r" % (self.i, self.s[self.i:self.i + 30]))

    def table(self):
        self.i += 1
        arr, dic = [], {}
        while True:
            self.ws()
            if self.s[self.i] == "}":
                self.i += 1
                break
            if self.s[self.i] == "[":
                self.i += 1
                k = self.val()
                self.ws()
                self.i += 1  # ]
                self.ws()
                self.i += 1  # =
                dic[k] = self.val()
            else:
                m = re.compile(r"([A-Za-z_]\w*)\s*=(?!=)").match(self.s, self.i)
                if m:
                    self.i = m.end()
                    dic[m.group(1)] = self.val()
                else:
                    arr.append(self.val())
            self.ws()
            if self.s[self.i] in ",;":
                self.i += 1
        return dic if dic else arr


def extract(lua: str, name: str):
    m = re.search(r"\b%s\s*=\s*\{" % re.escape(name), lua)
    if not m:
        raise KeyError(name)
    p = _P(lua)
    p.i = m.end() - 1
    return p.table()
