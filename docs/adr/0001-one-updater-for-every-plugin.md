# One updater for every plugin

The repository is getting a second plugin, BPTOOLS, next to PDFALL. Until now PDFALL carried its own updater in its bundle (**Оновити PDFALL**, [pdfall ADR 0007](../../pdfall/docs/adr/0007-update-from-github-releases.md)). Copying that for every plugin would give colleagues one Start menu entry, one window and one AutoCAD restart per plugin. Instead every plugin's zip carries the same installer and the same updater, from `common\`:

- **One entry, every plugin.** Installing any plugin also puts the updater in `%LOCALAPPDATA%\AutoCAD plugins` with one Start menu entry, **Оновити плагіни AutoCAD**. It lists every plugin that has a release in this repository, installed or not, with the version installed and the newest. Enter on a plugin opens that plugin's versions, newer or older, with their notes, as **Оновити PDFALL** did (Esc goes back to the list). **Оновити все** installs the newest version of every installed plugin that has one; a plugin that isn't installed is installed only when the user picks it. It asks once to close AutoCAD, before the first install.
- **Plugins are found by their tags.** A release tagged `<name>-v<major>.<minor>.<patch>` is a release of plugin `<NAME>`, whose zip is `<NAME>-<version>.zip` and bundle `<NAME>.bundle`. A new plugin needs no change to the updater: its first release puts it in the list.
- **The updater lives outside the bundles.** No plugin owns it, so uninstalling one leaves it for the others; the last uninstall removes it. A bundle is one of these plugins when it holds `plugin.json`.
- **The newest updater wins.** Every plugin zip has a copy, and `version.txt` beside it is the time of the last commit that changed `common\`. An install replaces the installed updater only with a newer one, so installing an older PDFALL, or a plugin released before a fix to the updater, never takes the updater back. Nobody has to remember to raise a number.
- **A plugin may suggest another.** Its `plugin.json` lists them in `suggests` (PDFALL suggests BPTOOLS). At the end of its install it asks once «Також встановити …?», unless that plugin is installed already or the user said no before (`declined.txt` beside the updater); a yes runs the updater with `-Install <NAME>`, which installs that plugin's newest release and asks nothing. The plugin list in the updater offers it too, so a no can be changed later.
- **Each install waits for its own programs.** The updater runs each downloaded zip's own `install.ps1`, as before. With `-WaitForPrograms`, that install waits for the plugin's programs still open (merge.exe's window) instead of stopping; a plugin names them in its messages as `program.<exe>`. An older zip's `install.ps1` doesn't know `-UpdaterDir` or `-WaitForPrograms`, so the updater passes only what it declares.

PDFALL 1.12.0 is the first release with it. Colleagues on 1.8.0–1.11.0 get it through their old **Оновити PDFALL**: its install puts the shared updater in place and replaces that entry with **Оновити плагіни AutoCAD**. Going back to a PDFALL before 1.12.0 is still allowed; the shared updater stays, and the old version adds its own **Оновити PDFALL** next to it, which the updater warns about when that version is picked.

## Considered options

- **A separate installer product** with its own releases, which then installs the plugins. Rejected: one more thing to release and to explain, and colleagues would have to get it before any plugin.
- **One updater per plugin.** Rejected: one entry, window and AutoCAD restart per plugin, and the same fixes made in several places.

## Consequences

- Every plugin's zip has `install.bat`, `install.ps1`, `uninstall.bat`, the `messages.json` they read and `updater\`, put there by `common\package.ps1`.
- A fix to the updater reaches colleagues with the next release of any plugin.
- A build from uncommitted changes to `common\` carries the stamp of the last commit, so it doesn't replace an updater installed from that commit; commit before testing an updater change by installing it.
