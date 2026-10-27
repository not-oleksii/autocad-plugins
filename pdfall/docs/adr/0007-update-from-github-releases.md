# Update from GitHub releases when the user asks

> Since PDFALL 1.12.0 this updater is shared by every plugin of the repository, as **Оновити плагіни AutoCAD**, and lives outside the bundle ([../../../docs/adr/0001](../../../docs/adr/0001-one-updater-for-every-plugin.md)). What follows still holds for each plugin's versions.

Colleagues update PDFALL with **Оновити PDFALL** in the Start menu, which runs `update.bat` from the installed bundle. It reads the public repository's releases from the GitHub API and lists them, newest first, with the installed one marked. The user moves through the list with the arrow keys, newer or older, and sees the notes of the chosen version; Enter installs the chosen version, Esc stops. Going back is allowed on purpose: when a new version breaks something, a colleague can return to the last one that worked without asking the developer for an old zip. Choosing a version before 1.8.0 warns that it has no updater to come back with. Without a keyboard (input redirected) it only offers the newest version, as before 1.9.0. Then it downloads `PDFALL-<version>.zip`, checks it against the release's `PDFALL-<version>.zip.sha256`, waits for AutoCAD to close and runs the zip's own `install.ps1`.

We chose this over checking at AutoCAD startup or updating silently, because `install.ps1` must run with AutoCAD closed ([ADR 0002](0002-install-as-a-bundle.md)) and because code that replaces itself without asking would let whoever controls the GitHub account run anything on every colleague's PC. Asking every time also shows colleagues what changed before they get it.

Releases are tagged `pdfall-v<major>.<minor>.<patch>` so that other plugins in this repository can have their own releases; the updater ignores every other tag, drafts and pre-releases, and so doesn't rely on GitHub's single "latest" release. The notes come from `CHANGELOG.md`, which is written in Ukrainian for colleagues; `release.ps1` adds install help after a `---` line, which the updater doesn't show.

## Consequences

- The repository must stay public: the updater makes unauthenticated requests (GitHub allows 60 an hour per address, plenty for a click now and then).
- The `.sha256` comes from the same release as the zip, so it catches a broken download, not a compromised account. Protect the account with two-factor sign-in.
- The updater replaces the folder it runs from. `update.bat` changes to `%TEMP%` and runs on one line, and `update.ps1` moves its own current folder to `%TEMP%`, because Windows can't delete a folder that a program is in and cmd reads a `.bat` file line by line.
- Installs older than 1.8.0 have no updater; they take one release by hand.
- Releases are built and published from a developer's PC with `release.ps1`, because building the ribbon and running the tests needs AutoCAD.
