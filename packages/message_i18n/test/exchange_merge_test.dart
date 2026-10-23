import 'dart:convert';
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:message_i18n/message_i18n.dart';
import 'package:message_i18n/src/tool/exchange.dart';
import 'package:message_i18n/src/tool/merge.dart';
import 'package:test/test.dart';

void main() {
  test('malformed JSON schema rejected, empty candidate accepted', () {
    for (final value in [
      '[]',
      '{',
      '{"":{}}',
      '{"a":1}',
      '{"a":{"en":null}}',
      '{"a":{"en_US":"a","en-US":"b"}}',
    ]) {
      expect(() => decodeJson(value), throwsFormatException);
    }
    expect(decodeJson('{}').messages, isEmpty);
  });
  test('XLSX malformed sheet, header, formula and duplicate rows rejected', () {
    expect(() => decodeXlsx([1, 2, 3]), throwsA(anything));
    final excel = Excel.createExcel();
    expect(() => decodeXlsx(excel.encode()!), throwsFormatException);
    final sheet = excel['translations'];
    sheet.appendRow([TextCellValue('KEY'), TextCellValue('en')]);
    expect(() => decodeXlsx(excel.encode()!), throwsFormatException);
    sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('key');
    sheet.appendRow([TextCellValue('a'), FormulaCellValue('1+1')]);
    expect(() => decodeXlsx(excel.encode()!), throwsFormatException);
    sheet.cell(CellIndex.indexByString('B2')).value = TextCellValue('ok');
    sheet.appendRow([TextCellValue('a'), TextCellValue('again')]);
    expect(() => decodeXlsx(excel.encode()!), throwsFormatException);
  });
  test(
    'XLSX duplicate headers, blank key row and empty rows are distinguished',
    () {
      final excel = Excel.createExcel();
      final sheet = excel['translations'];
      sheet.appendRow([
        TextCellValue('key'),
        TextCellValue('en'),
        TextCellValue('EN'),
      ]);
      expect(() => decodeXlsx(excel.encode()!), throwsFormatException);
      sheet.cell(CellIndex.indexByString('C1')).value = TextCellValue('ko');
      sheet.appendRow([null, TextCellValue('without key')]);
      expect(() => decodeXlsx(excel.encode()!), throwsFormatException);
      sheet.cell(CellIndex.indexByString('B2')).value = null;
      expect(decodeXlsx(excel.encode()!).messages, isEmpty);
    },
  );
  test('JSON/XLSX text-only roundtrip and no metadata', () {
    final values = [
      '=1+1',
      '+cmd',
      '-12',
      '@SUM(A1)',
      '한글 🌍\nline',
      '<b>hello</b>',
      r'$ " \',
      '{name}',
      '',
    ];
    final document = ExchangeDocument(
      {
        for (var i = 0; i < values.length; i++)
          'key$i': {'ko': values[i], 'en': values[i]},
      },
      locales: ['ko', 'en'],
    );
    expect(decodeJson(encodeJson(document)).messages, document.messages);
    final bytes = encodeXlsx(document);
    final restored = decodeXlsx(bytes);
    expect(restored.messages, document.messages);
    final workbook = Excel.decodeBytes(bytes);
    expect(workbook.tables.keys, ['translations']);
    final rows = workbook.tables['translations']!.rows;
    expect(rows.first.map((d) => d!.value.toString()), ['key', 'ko', 'en']);
    for (final row in rows.skip(1)) {
      for (final cell in row.whereType<Data>()) {
        expect(cell.value, isA<TextCellValue>());
      }
    }
    expect(jsonDecode(encodeJson(document)), document.messages);
  });
  const original = MessageCatalog(
    defaultLocale: 'ko',
    supportedLocales: ['ko', 'en'],
    messages: {
      'old': LocalizedMessage({'ko': '원본', 'en': 'source'}),
      'same': LocalizedMessage({'ko': '같음', 'en': 'same'}),
    },
  );
  test(
    'merge is independent, last input wins, semantic issues do not block',
    () {
      final merged = mergeDocuments(original, [
        decodeJson('{"same":{"ko":""},"new":{"ja":"{name}"}}'),
        decodeJson('{"same":{"ko":"최종","en":"{other}"}}'),
      ]);
      expect(merged.candidate.messages.keys, ['new', 'same']);
      expect(merged.candidate.messages['same']!.translations['ko'], '최종');
      expect(merged.candidate.supportedLocales, ['ko', 'en', 'ja']);
      expect(merged.comparison.originalOnly, ['old']);
      expect(merged.comparison.mergedOnly, ['new']);
      expect(merged.warnings.join('\n'), contains('input=1->2'));
      expect(merged.warnings.join('\n'), contains('placeholder_mismatch'));
      expect(
        merged.candidate.messages['new']!.translations.containsKey('ko'),
        isFalse,
      );
      expect(
        mergeDocuments(original, [decodeJson('{}')]).candidate.messages,
        isEmpty,
      );
    },
  );
  test('key report covers all four states and never compares values', () {
    expect(
      KeyComparison(['b', 'a'], ['a', 'b']).report(),
      '원본과 병합본의 키가 일치합니다.',
    );
    expect(KeyComparison(['b', 'a'], []).originalOnly, ['a', 'b']);
    expect(KeyComparison([], ['c']).mergedOnly, ['c']);
    expect(KeyComparison(['a'], ['c']).toJson(), {
      'matched': false,
      'originalOnly': ['a'],
      'mergedOnly': ['c'],
    });
  });
  test(
    'merge output stays in build and never overwrites existing output',
    () async {
      final root = Directory(
        Directory.systemTemp
            .createTempSync('merge_')
            .resolveSymbolicLinksSync(),
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final merged = mergeDocuments(original, [decodeJson('{}')]);
      await expectLater(
        writeMerge(merged, root.path, '${root.path}/outside'),
        throwsFormatException,
      );
      final first = await writeMerge(
        merged,
        root.path,
        '${root.path}/build/candidate',
      );
      final next = await writeMerge(
        merged,
        root.path,
        '${root.path}/build/candidate',
      );
      expect(first.path, isNot(next.path));
      final parallel = await Future.wait(
        List.generate(
          4,
          (_) => writeMerge(merged, root.path, '${root.path}/build/concurrent'),
        ),
      );
      expect(parallel.map((d) => d.path).toSet(), hasLength(4));
      expect(
        Directory(
          '${root.path}/build',
        ).listSync().where((f) => f.path.endsWith('.reservation')),
        isEmpty,
      );
      expect(
        File('${first.path}/merged_catalog.dart').readAsStringSync(),
        contains('messages: {}'),
      );
    },
  );
}
