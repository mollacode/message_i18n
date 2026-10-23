# Changelog

## 0.1.0

- Add message-centered Dart catalogs and strict validation.
- Validate canonical message keys with `^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$` without rewriting invalid keys.
- Generate locale loaders and resolve messages with named placeholders.
- Generate deterministic `MessageKeys` string constants in standalone runtime libraries.
- Add annotated const catalogs and shared code generation support for `message_i18n_builder`.
- Add check, generate, watch, JSON/XLSX export, and review-only merge commands.
- Support build_runner build, watch, and read-only generated-output checks as the default workflow.
- Preserve generated output on failures and report translation diagnostics.
