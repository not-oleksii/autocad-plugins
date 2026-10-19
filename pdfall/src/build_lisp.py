"""Check messages.json against the code that uses it, then build the bundle's pdfall.lsp.

Usage:
    py -3 build_lisp.py OUT

build.bat runs it. It fails, and writes nothing, when:
  - the code uses a key that messages.json doesn't have, in the section it reads it from;
  - a message and the code that shows it disagree on its {names};
  - a Ukrainian string is written in src/lsp outside 00-settings.lsp (it belongs in messages.json);
  - the version in 00-settings.lsp and PackageContents.xml differ or isn't <major>.<minor>.<patch>.
A key that no code uses is only a warning.

pdfall.lsp is src/lsp/*.lsp in name order, with messages.json written as LISP lists right after
00-settings.lsp, so the settings still open the file.
"""

import ast
import json
import re
import sys
from pathlib import Path

SRC = Path(__file__).resolve().parent
LSP = SRC / "lsp"
SECTIONS = ("messages", "labels", "files")
CYRILLIC = re.compile("[\u0400-\u04ff]")
PLACEHOLDER = re.compile(r"\{(\w+)\}")


def lisp_tokens(text):
    """The tokens of a LISP file as (kind, value, line): kind is "(", ")", "'", "str" or "atom"."""
    i, line, n = 0, 1, len(text)
    while i < n:
        c = text[i]
        if c == "\n":
            line += 1
            i += 1
        elif c.isspace():
            i += 1
        elif c == ";":
            while i < n and text[i] != "\n":
                i += 1
        elif c in "()'":
            yield c, c, line
            i += 1
        elif c == '"':
            j, out = i + 1, []
            while text[j] != '"':
                if text[j] == "\\":
                    out.append({"n": "\n", "t": "\t", "\\": "\\", '"': '"'}.get(text[j + 1], text[j + 1]))
                    j += 2
                else:
                    out.append(text[j])
                    j += 1
            yield "str", "".join(out), line
            line += text.count("\n", i, j)
            i = j + 1
        else:
            j = i
            while j < n and not text[j].isspace() and text[j] not in "()';\"":
                j += 1
            yield "atom", text[i:j], line
            i = j


def lisp_forms(tokens):
    """Nested lists of the tokens; a quoted form becomes ["quote", form]."""
    stack = [[]]
    quote = []
    for kind, value, line in tokens:
        if kind == "'":
            quote.append(len(stack))
            continue
        if kind == "(":
            stack.append([])
            continue
        if kind == ")":
            item = stack.pop()
        else:
            item = (kind, value, line)
        while quote and quote[-1] == len(stack):
            quote.pop()
            item = ["quote", item]
        stack[-1].append(item)
    return stack[0]


def walk(form):
    yield form
    if isinstance(form, list):
        for item in form:
            yield from walk(item)


class Checker:
    def __init__(self, data):
        self.data = data
        self.used = {s: set() for s in SECTIONS}
        self.errors = []

    def key(self, section, key, where):
        self.used[section].add(key)
        if key not in self.data[section]:
            self.errors.append(f"{where}: '{key}' is not in the {section} of messages.json")
            return None
        return self.data[section][key]

    def names(self, key, given, where):
        text = self.key("messages", key, where)
        if text is None:
            return
        wanted = set(PLACEHOLDER.findall(text))
        if wanted != set(given):
            self.errors.append(f"{where}: message '{key}' takes {sorted(wanted)}, the code gives {sorted(given)}")

    def lisp(self, path):
        tokens = list(lisp_tokens(path.read_text(encoding="utf-8")))
        if path.name != "00-settings.lsp":
            for kind, value, line in tokens:
                if kind == "str" and CYRILLIC.search(value):
                    self.errors.append(f"{path.name}:{line}: Ukrainian text \"{value}\" belongs in messages.json")
        for form in walk(lisp_forms(tokens)):
            if not (isinstance(form, list) and form and form[0][:2] in
                    (("atom", "pa:msg"), ("atom", "pa:label"), ("atom", "pa:file"))):
                continue
            func, line = form[0][1], form[0][2]
            where = f"{path.name}:{line}"
            if len(form) < 2 or not isinstance(form[1], tuple) or form[1][0] != "str":
                self.errors.append(f"{where}: ({func} ...) needs a literal key so the build can check it")
                continue
            key = form[1][1]
            if func == "pa:label":
                self.key("labels", key, where)
            elif func == "pa:file":
                self.key("files", key, where)
            elif len(form) != 3:
                self.errors.append(f"{where}: (pa:msg \"{key}\" ...) takes the key and one list of values")
            elif form[2] == ("atom", "nil", line) or form[2][:2] == ("atom", "nil"):
                self.names(key, [], where)
            elif (isinstance(form[2], list) and form[2] and form[2][0][:2] == ("atom", "list")
                  and len(form[2]) % 2 == 1
                  and all(isinstance(x, tuple) and x[0] == "str" for x in form[2][1::2])):
                self.names(key, [x[1] for x in form[2][1::2]], where)
            else:
                self.errors.append(f"{where}: (pa:msg \"{key}\" ...) needs nil or a literal (list \"name\" value ...)")

    def python(self, path):
        """Calls msg("key", name=value), label("key") and file_word("key") in merge_blueprints.py."""
        tree = ast.parse(path.read_text(encoding="utf-8"))
        funcs = {"msg": "messages", "label": "labels", "file_word": "files"}
        for node in ast.walk(tree):
            if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in funcs):
                continue
            where = f"{path.name}:{node.lineno}"
            if not (node.args and isinstance(node.args[0], ast.Constant) and isinstance(node.args[0].value, str)):
                self.errors.append(f"{where}: {node.func.id}() needs a literal key so the build can check it")
                continue
            key = node.args[0].value
            if node.func.id == "msg":
                self.names(key, [k.arg for k in node.keywords], where)
            else:
                self.key(funcs[node.func.id], key, where)

    def powershell(self, path):
        """Calls Msg 'key' or Msg 'key' @{ name = value; ... } in the PowerShell scripts."""
        text = path.read_text(encoding="utf-8-sig")
        for m in re.finditer(r"\bMsg\s+'([^']+)'(\s+@\{([^}]*)\})?", text):
            where = f"{path.name}:{text.count(chr(10), 0, m.start()) + 1}"
            given = re.findall(r"(\w+)\s*=", m.group(3) or "")
            self.names(m.group(1), given, where)


def version_errors():
    """The version must be the same in 00-settings.lsp and PackageContents.xml, and a release number."""
    lisp = re.search(r'\(setq \*pdfall-version\* "([^"]*)"\)', (LSP / "00-settings.lsp").read_text(encoding="utf-8"))
    xml = re.search(r'AppVersion="([^"]*)"', (SRC / "PackageContents.xml").read_text(encoding="utf-8"))
    if not (lisp and xml):
        return ["the version is missing from 00-settings.lsp or PackageContents.xml"]
    if lisp.group(1) != xml.group(1):
        return [f"version {lisp.group(1)} in 00-settings.lsp but {xml.group(1)} in PackageContents.xml"]
    if not re.fullmatch(r"\d+\.\d+\.\d+", lisp.group(1)):
        return [f"version {lisp.group(1)} is not <major>.<minor>.<patch>"]
    return []


def lisp_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t") + '"'


def lisp_table(name, section):
    rows = []
    for key, value in section.items():
        if isinstance(value, list):
            rows.append(f"  ({lisp_string(key)} {' '.join(map(lisp_string, value))})")
        else:
            rows.append(f"  ({lisp_string(key)} . {lisp_string(value)})")
    return f"(setq {name} '(\n" + "\n".join(rows) + "))\n"


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(errors="replace")  # Ukrainian in a report must not crash a non-UTF-8 console
    out = Path(sys.argv[1])
    data = json.loads((SRC / "messages.json").read_text(encoding="utf-8"))
    for section in SECTIONS:
        for key, value in data[section].items():
            ok = isinstance(value, str) or (isinstance(value, list) and all(isinstance(v, str) for v in value))
            if not ok:
                sys.exit(f"messages.json: {section}.{key} must be text or a list of texts")

    files = sorted(LSP.glob("*.lsp"))
    checker = Checker(data)
    for path in files:
        checker.lisp(path)
    checker.python(SRC / "merge_blueprints.py")
    for script in ("install.ps1", "update.ps1", "ribbon.ps1", "../release.ps1"):
        checker.powershell(SRC / script)
    checker.errors += version_errors()
    if checker.errors:
        print("messages.json and the code disagree:", file=sys.stderr)
        for e in checker.errors:
            print(f"  {e}", file=sys.stderr)
        sys.exit(1)
    for section in SECTIONS:
        for key in sorted(set(data[section]) - checker.used[section]):
            print(f"warning: {section}.{key} in messages.json is not used anywhere")

    parts = [";;; Built by build.bat from src\\lsp\\*.lsp and src\\messages.json. Edit those, not this file.\n\n"]
    for path in files:
        parts.append(f";;; ==== {path.name} {'=' * (80 - len(path.name))}\n")
        parts.append(path.read_text(encoding="utf-8").rstrip() + "\n\n")
        if path.name.startswith("00-"):
            parts.append(";;; ==== messages.json " + "=" * 68 + "\n")
            parts.append(lisp_table("*pa-messages*", data["messages"]))
            parts.append(lisp_table("*pa-labels*", data["labels"]))
            parts.append(lisp_table("*pa-files*", data["files"]) + "\n")
    out.write_text("".join(parts), encoding="utf-8", newline="\n")
    print(f"Built {out}")


if __name__ == "__main__":
    main()
