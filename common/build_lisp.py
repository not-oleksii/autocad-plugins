"""Check a plugin's messages against the code that uses them, then build its LISP file and messages.json.

Usage:
    py -3 common/build_lisp.py PLUGIN OUT

PLUGIN is the plugin's folder (pdfall); its src/plugin.json names it and its LISP prefix:
    {"name": "PDFALL", "prefix": "pa", "debug": "PDFDEBUG"}
OUT is a folder; the build writes into it:
    <name>.lsp      common/lsp/*.lsp and PLUGIN/src/lsp/*.lsp in name order (common first on a tie),
                    with the messages written as LISP lists right after the plugin's 00-settings.lsp
    messages.json   common/messages.json and PLUGIN/src/messages.json in one file, for install.ps1,
                    the ribbon and merge.exe

The common LISP files are written once for every plugin (../docs/adr/0002-share-code-between-plugins.md).
AutoLISP has one namespace, so each plugin gets its own copy under its own prefix: in them
    @@NAME@@  becomes the plugin's name (PDFALL)     @@DEBUG@@  its debug command (PDFDEBUG)
    *@@-      becomes *pdfall-                       @:  becomes pa:      *@-  becomes *pa-

It fails, and writes nothing, when:
  - the code uses a key that the messages don't have, in the section it reads it from;
  - a message and the code that shows it disagree on its {names};
  - common and the plugin both have a key (a plugin can't change a common text by accident);
  - a Ukrainian string is written in LISP outside the plugin's 00-settings.lsp (it belongs in messages.json);
  - the version in 00-settings.lsp and PackageContents.xml differ or isn't <major>.<minor>.<patch>.
The updater is checked against common/messages.json alone, since that is all it has.
A key that no code uses is only a warning; program.<exe> keys are read by install.ps1 by name.
"""

import ast
import json
import re
import sys
from pathlib import Path

COMMON = Path(__file__).resolve().parent
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
    def __init__(self, data, prefix):
        self.data = data
        self.prefix = prefix
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

    def lisp(self, name, text, ukrainian_ok):
        tokens = list(lisp_tokens(text))
        if not ukrainian_ok:
            for kind, value, line in tokens:
                if kind == "str" and CYRILLIC.search(value):
                    self.errors.append(f"{name}:{line}: Ukrainian text \"{value}\" belongs in messages.json")
        msg, label, file = (f"{self.prefix}:{f}" for f in ("msg", "label", "file"))
        for form in walk(lisp_forms(tokens)):
            if not (isinstance(form, list) and form and form[0][:2] in
                    (("atom", msg), ("atom", label), ("atom", file))):
                continue
            func, line = form[0][1], form[0][2]
            where = f"{name}:{line}"
            if len(form) < 2 or not isinstance(form[1], tuple) or form[1][0] != "str":
                self.errors.append(f"{where}: ({func} ...) needs a literal key so the build can check it")
                continue
            key = form[1][1]
            if func == label:
                self.key("labels", key, where)
            elif func == file:
                self.key("files", key, where)
            elif len(form) != 3:
                self.errors.append(f"{where}: ({msg} \"{key}\" ...) takes the key and one list of values")
            elif form[2][:2] == ("atom", "nil"):
                self.names(key, [], where)
            elif (isinstance(form[2], list) and form[2] and form[2][0][:2] == ("atom", "list")
                  and len(form[2]) % 2 == 1
                  and all(isinstance(x, tuple) and x[0] == "str" for x in form[2][1::2])):
                self.names(key, [x[1] for x in form[2][1::2]], where)
            else:
                self.errors.append(f"{where}: ({msg} \"{key}\" ...) needs nil or a literal (list \"name\" value ...)")

    def python(self, path):
        """Calls msg("key", name=value), label("key") and file_word("key") in the plugin's Python."""
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


def read_messages(path):
    data = json.loads(path.read_text(encoding="utf-8"))
    for section in SECTIONS:
        data.setdefault(section, {})
        for key, value in data[section].items():
            ok = isinstance(value, str) or (isinstance(value, list) and all(isinstance(v, str) for v in value))
            if not ok:
                sys.exit(f"{path}: {section}.{key} must be text or a list of texts")
    return data


def version_errors(src, lower):
    """The version must be the same in 00-settings.lsp and PackageContents.xml, and a release number."""
    lisp = re.search(r'\(setq \*' + lower + r'-version\* "([^"]*)"\)', (src / "lsp" / "00-settings.lsp").read_text(encoding="utf-8"))
    xml = re.search(r'AppVersion="([^"]*)"', (src / "PackageContents.xml").read_text(encoding="utf-8"))
    if not (lisp and xml):
        return [f"the version is missing from 00-settings.lsp (*{lower}-version*) or PackageContents.xml"]
    if lisp.group(1) != xml.group(1):
        return [f"version {lisp.group(1)} in 00-settings.lsp but {xml.group(1)} in PackageContents.xml"]
    if not re.fullmatch(r"\d+\.\d+\.\d+", lisp.group(1)):
        return [f"version {lisp.group(1)} is not <major>.<minor>.<patch>"]
    return []


def own_copy(text, plugin):
    """A common LISP file as the plugin's own: its name, debug command and prefix put in."""
    lower = plugin["name"].lower()
    for old, new in (("@@NAME@@", plugin["name"]), ("@@DEBUG@@", plugin["debug"]),
                     ("*@@-", f"*{lower}-"), ("@:", f"{plugin['prefix']}:"), ("*@-", f"*{plugin['prefix']}-")):
        text = text.replace(old, new)
    return text


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
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    for stream in (sys.stdout, sys.stderr):
        stream.reconfigure(errors="replace")  # Ukrainian in a report must not crash a non-UTF-8 console
    plugin_dir, out = Path(sys.argv[1]).resolve(), Path(sys.argv[2])
    src = plugin_dir / "src"
    plugin = json.loads((src / "plugin.json").read_text(encoding="utf-8"))
    lower, prefix = plugin["name"].lower(), plugin["prefix"]

    common = read_messages(COMMON / "messages.json")
    own = read_messages(src / "messages.json")
    errors = [f"{section}.{key} is in both common/messages.json and {plugin_dir.name}/src/messages.json"
              for section in SECTIONS for key in sorted(set(common[section]) & set(own[section]))]
    data = {"_note": own.get("_note", common.get("_note", ""))}
    for section in SECTIONS:
        data[section] = {**common[section], **own[section]}

    # (name in the built file, text, whether Ukrainian is allowed); common first on a tie
    files = [(f"common/{p.name}", own_copy(p.read_text(encoding="utf-8"), plugin), False, p.name, 0)
             for p in (COMMON / "lsp").glob("*.lsp")]
    files += [(p.name, p.read_text(encoding="utf-8"), p.name == "00-settings.lsp", p.name, 1)
              for p in (src / "lsp").glob("*.lsp")]
    files.sort(key=lambda f: (f[3], f[4]))

    checker = Checker(data, prefix)
    for name, text, ukrainian_ok, _, _ in files:
        checker.lisp(name, text, ukrainian_ok)
    for script in sorted(src.glob("*.py")):
        checker.python(script)
    for script in [COMMON / "install.ps1", COMMON / "release.ps1", *sorted(src.glob("*.ps1"))]:
        checker.powershell(script)
    updater = Checker(common, prefix)
    updater.powershell(COMMON / "updater" / "update.ps1")
    checker.errors = errors + checker.errors + [f"updater: {e}" for e in updater.errors] + version_errors(src, lower)
    if checker.errors:
        print("the messages and the code disagree:", file=sys.stderr)
        for e in checker.errors:
            print(f"  {e}", file=sys.stderr)
        sys.exit(1)
    for section in SECTIONS:
        unused = set(data[section]) - checker.used[section] - updater.used[section]
        for key in sorted(k for k in unused if not k.startswith("program.")):
            print(f"warning: {section}.{key} in messages.json is not used anywhere")

    parts = [f";;; Built by build.bat from common\\lsp, {plugin_dir.name}\\src\\lsp and the messages.json files. Edit those, not this file.\n\n"]
    for name, text, _, _, _ in files:
        parts.append(f";;; ==== {name} {'=' * max(0, 80 - len(name))}\n")
        parts.append(text.rstrip() + "\n\n")
        if name == "00-settings.lsp":
            parts.append(";;; ==== messages.json " + "=" * 68 + "\n")
            parts.append(lisp_table(f"*{prefix}-messages*", data["messages"]))
            parts.append(lisp_table(f"*{prefix}-labels*", data["labels"]))
            parts.append(lisp_table(f"*{prefix}-files*", data["files"]) + "\n")
    out.mkdir(parents=True, exist_ok=True)
    (out / f"{lower}.lsp").write_text("".join(parts), encoding="utf-8", newline="\n")
    (out / "messages.json").write_text(json.dumps(data, ensure_ascii=False, indent=4) + "\n", encoding="utf-8", newline="\n")
    print(f"Built {out / (lower + '.lsp')} and {out / 'messages.json'}")


if __name__ == "__main__":
    main()
