# Changelog

## Unreleased

- Restrict canonical message keys to lowercase ASCII alphanumeric segments separated by one dot, hyphen or underscore.
- Generate compile-time `MessageKeys` string constants with strict collision and identifier diagnostics.
- Add annotated const catalogs and optional message_i18n_builder integration.
- Document build_runner build/watch/only-check as the default workflow.
- Preserve existing runtime APIs and MessageI18nTool commands.

## 0.1.0

Initial message-centered Dart core/tool and Flutter adapter implementation.
