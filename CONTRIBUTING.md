# Contributing

- **DCO:** every commit carries `Signed-off-by:` (`git commit -s`). Substantial contributions (> 300 lines) also sign the lightweight CLA so dual licensing stays possible (docs/09 §1).
- **Conventional commits** with the feature ID as scope: `feat(VID-067): system PiP on iOS via sample-buffer layer`.
- **Feature IDs** from `docs/04` appear in test names (`test('VID-062 speed presets persist per item', ...)`) and in `STATUS.md`.
- **Strings** go in your module's ARB fragment (`<module>/l10n/<module>_en.arb`); no concatenated sentences.
- **No** `print`, direct `MethodChannel`, `dynamic` in public APIs, GPL dependencies, analytics or unlisted network calls.
- Run `tools/bootstrap` once, then `tools/check` before pushing (analyze, format, custom lints, tests, status check).
