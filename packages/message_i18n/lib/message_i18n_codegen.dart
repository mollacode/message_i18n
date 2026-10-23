/// Pure authoring APIs for generator integrations; not an application import.
library;

export 'src/tool/emission.dart' show emitStandaloneCatalog;
export 'src/tool/validation.dart'
    show ValidationCode, ValidationIssue, validateCatalog;
