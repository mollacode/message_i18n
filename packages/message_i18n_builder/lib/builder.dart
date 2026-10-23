/// build_runner integration for const message catalogs.
library;

import 'package:build/build.dart';
import 'src/catalog_builder.dart';

/// Creates the catalog builder registered in build.yaml.
Builder messageI18nBuilder(BuilderOptions options) => CatalogBuilder();
