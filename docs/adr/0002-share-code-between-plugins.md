# Share code between plugins by giving each its own copy

PDFALL's text helpers, settings, debug log, DCL helpers, installer, updater, ribbon builder and release script would all be written again for BPTOOLS. They now live once in `common\`, and each plugin's build takes them from there.

AutoLISP has one namespace for every file AutoCAD loads. If PDFALL and BPTOOLS both defined `pa:msg`, the plugin loaded last would replace the other's, and two plugins at different versions would run each other's code. So the shared LISP files in `common\lsp` are written with placeholders, and `common\build_lisp.py` gives each plugin its own copy under its own prefix: `@:msg` becomes `pa:msg` in PDFALL and `bp:msg` in BPTOOLS, `*@-messages*` becomes `*pa-messages*`, `*@@-version*` becomes `*pdfall-version*`, and `@@NAME@@` and `@@DEBUG@@` become the plugin's name and debug command. The prefix and those names are in the plugin's `src\plugin.json`. The build joins `common\lsp\*.lsp` and the plugin's `src\lsp\*.lsp` in name order (common first on a tie), so a shared file numbered 10 opens before the plugin's files that use it.

Texts are split the same way: `common\messages.json` has the installer's, the updater's, the debug log's and the dialogs' texts, and the plugin's `src\messages.json` the rest. The build joins them into one `messages.json` for the plugin and fails when a key is in both, so a plugin can't change a common text by accident. The updater has only the common file, and the build checks it against that file alone.

Only what is truly the same is shared: what a рамка or a марка is stays in PDFALL. A plugin that needs another's knowledge asks it through one public function ([ADR 0003](0003-plugins-talk-through-one-function.md)).

## Considered options

- **One shared LISP file that every plugin loads.** Rejected: two plugins at different versions would ship different copies of it, and the one loaded last would win for both.
- **Copying the helpers by hand into each plugin.** Rejected: fixes would have to be made in several places, and the copies would drift apart.

## Consequences

- A change to `common\` changes every plugin at its next build, so it is tested with every plugin's tests.
- A plugin's built `.lsp` is still one self-contained file ([pdfall ADR 0004](../../pdfall/docs/adr/0004-split-the-lisp-and-build-in-its-texts.md)).
- `@` must not be used in shared LISP code for anything but these placeholders.
