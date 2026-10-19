# Split the LISP into modules joined at build time, and build its texts into it

The LISP source is one file per module in `src\lsp`, and `build_lisp.py` joins them in name order into the single `pdfall.lsp` that the bundle loads. Every Ukrainian text the commands, merge.exe, the installer and the ribbon show or look for lives in `src\messages.json`, which the build writes into that `pdfall.lsp` as LISP lists, packs into merge.exe and puts next to `install.ps1`.

We chose joining at build time over a small `pdfall.lsp` that `(load)`s the other files at runtime because nothing about installing changes: the bundle still has one `pdfall.lsp`, `*pdfall-home*` is still found through it, the installer still removes it from the Startup Suite, and the tests still load it. A loader would need its files flat in `Contents`, since a TRUSTEDPATHS entry does not cover subfolders ([ADR 0002](0002-install-as-a-bundle.md)), and a missing file would only show up at load time on a colleague's PC. We chose it over one `ComponentEntry` per file in `PackageContents.xml` because AutoCAD does not promise the order it loads them in, and later files need the settings and helpers of earlier ones.

We chose building the texts in over reading `messages.json` at runtime because AutoLISP has no JSON reader, and because a broken JSON or a missing key should fail the build on the developer's PC rather than a command on a colleague's. Changing a text means rebuilding and reinstalling, as every other change already does.

## Consequences

- The number prefix of a file in `src\lsp` sets its place in `pdfall.lsp`. `00-settings.lsp` comes first, so the installed file still opens with the settings, and the texts follow it.
- All the files share one namespace. Each file's header lists the functions the other files may call; the rest are its own.
- Every key is a literal string in the code (`pa:msg`, `msg`, `Msg` ...), so `build_lisp.py` can check each one, and each message's `{names}` against what its caller gives. It also fails the build on Ukrainian text written in `src\lsp` outside `00-settings.lsp`.
- `labels` and `files` in `messages.json` are not translations: they must match the drawings and the PDFs that already exist.
- `install.ps1` keeps one message of its own, for when `messages.json` is missing from the zip.
