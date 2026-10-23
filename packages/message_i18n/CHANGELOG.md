# Changelog

## Unreleased

- Validate canonical message keys with `^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$`; keys are never rewritten automatically.
- Generate deterministic `MessageKeys` string constants in standalone runtime libraries while preserving legacy CLI output.
- Add annotated const catalogs and optional message_i18n_builder integration.
- Document build_runner build/watch/only-check as the default workflow.
- Preserve existing runtime APIs and MessageI18nTool commands.

## 0.1.0

- Add message-centered Dart catalogs and strict validation.
- Generate locale loaders and resolve messages with named placeholders.
- Add check, generate, watch, JSON/XLSX export, and review-only merge commands.
- Preserve generated output on failures and report translation diagnostics.
