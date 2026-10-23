import 'package:flutter_test/flutter_test.dart';
import 'package:build_runner_consumer/catalog.message_i18n.g.dart';
import 'package:build_runner_consumer/models.dart';
import 'package:build_runner_consumer/routes.dart';

void main() {
  test('all generators produce usable code', () {
    final resolver = createMessageResolver(selected: 'en-US');
    expect(resolver.text(MessageKeys.save), 'Save');
    resolver.select('ko-KR');
    // Raw strings remain compatible with generated key constants.
    expect(resolver.text('save'), '저장');
    expect(
      Person.fromJson({'name': 'Dart'}).copyWith(name: 'Flutter').toJson(),
      {'name': 'Flutter'},
    );
    expect(const HomeRoute().location, '/');
    expect($appRoutes, isNotEmpty);
  });
}
