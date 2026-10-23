# message_i18n example

A Flutter application demonstrating message lookup, named placeholders, language
switching, navigation, dialogs, and hot reload with a shared resolver.

From this directory:

```bash
flutter pub get
dart run tool/i18n.dart generate
flutter run -d <device-id>
```

The example includes Android, iOS, macOS, Web, and Windows runners. Use
`flutter devices` to find a connected device ID. Windows builds require a
Windows development host.

Generated translations and dependency lockfiles are not committed. Run generation
before analysis, tests, or builds after a fresh checkout. The source catalog is
`lib/i18n/catalog.dart`.

For live translation edits, run `dart run tool/i18n.dart watch` in another terminal,
wait for generation to succeed, and trigger Flutter hot reload.

From the repository root, `dart run tool/verify.dart` resolves dependencies,
generates translations, and runs analysis and tests. Add `--build` to also verify
a debug build.
