# Changelog

## Unreleased

- Fail generation without output when a catalog key violates the lowercase ASCII segment grammar.
- Generate `MessageKeys` string constants and fail on ambiguous or non-declarable generated member names.

## 0.1.0

- Generate standalone localization libraries from annotated const catalogs.
- Integrate validation and incremental generation with build_runner 2.16.x.
