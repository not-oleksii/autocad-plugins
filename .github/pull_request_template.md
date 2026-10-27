## Summary

<!-- What changes for the people who use the plugin, and why. Name the plugin if the repo has several. -->

## Version impact

<!-- Pick one (https://semver.org). The version itself is raised later, in the release pull request. -->

- [ ] **patch**: only fixes
- [ ] **minor**: something new; drawings, PDFs and habits keep working
- [ ] **major**: something works differently and colleagues must know (e.g. PDF or command names)
- [ ] **none**: nothing users get changes (tests, docs for developers, tooling)

## Checklist

- [ ] `CHANGELOG.md`: a line under **Невипущене**, in Ukrainian, written for colleagues (skip for "none")
- [ ] User-facing texts are in the plugin's `src/messages.json` (or `common/messages.json` when every plugin shows them), in Ukrainian; code and developer docs in English
- [ ] The colleagues' guide `src/Instruktsiia.html` (plus `README.md` if the basics change) and `DEVELOPING.md` describe the change
- [ ] A design decision has an ADR in the plugin's `docs/adr`, or in the root `docs/adr` when it concerns every plugin
- [ ] No real drawings, PDFs, names or other private data added (`examples/` stays out of git)

## Test plan

<!-- CI only checks messages.json; build and tests need AutoCAD 2024 on Windows. -->

- [ ] `build.bat`, then `tests\run.ps1` and `tests\install.ps1` report "All passed" (for a change to `common/`, in every plugin)
- [ ] Checked by hand in AutoCAD:
