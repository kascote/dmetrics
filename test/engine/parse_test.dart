import 'package:dmetrics/dmetrics.dart';
import 'package:dmetrics/src/engine/parse.dart';
import 'package:test/test.dart';

/// Files are parsed at their package's language version, not the latest:
/// syntax the latest version has dropped is still valid in older packages.
void main() {
  group('LanguageVersion.fromSdkConstraint', () {
    test('takes the lower bound, major and minor only', () {
      expect(
        LanguageVersion.fromSdkConstraint('^3.12.0'),
        LanguageVersion(3, 12),
      );
      expect(
        LanguageVersion.fromSdkConstraint('>=2.18.0 <4.0.0'),
        LanguageVersion(2, 18),
      );
      expect(
        LanguageVersion.fromSdkConstraint('3.13.2'),
        LanguageVersion(3, 13),
      );
      expect(
        LanguageVersion.fromSdkConstraint(' >=3.0.0-0 <4.0.0 '),
        LanguageVersion(3, 0),
      );
    });

    test('no lower bound or not a constraint means null (latest)', () {
      expect(LanguageVersion.fromSdkConstraint('any'), isNull);
      expect(LanguageVersion.fromSdkConstraint('<4.0.0'), isNull);
      expect(LanguageVersion.fromSdkConstraint('flutter'), isNull);
      expect(LanguageVersion.fromSdkConstraint(''), isNull);
    });
  });

  group('parseSource', () {
    ParsedSource parse(String content, {LanguageVersion? version}) =>
        parseSource(
          SourceFile(
            path: 'a.dart',
            content: content,
            configRoot: '.',
            languageVersion: version,
          ),
        );

    test('syntax dropped by the latest version still parses at the package version', () {
      // Dart 3.13 rejects `final` on a parameter; 3.12 packages use it.
      const src = 'void f(final String id) {}\n';
      expect(parse(src, version: LanguageVersion(3, 12)).partial, isFalse);
      expect(parse(src).partial, isTrue);
    });

    test('a // @dart= comment still lowers the version for one file', () {
      // Records are a syntax error before 3.0.
      const src = 'var r = (1, 2);\n';
      expect(parse(src, version: LanguageVersion(3, 12)).partial, isFalse);
      expect(
        parse('// @dart=2.19\n$src', version: LanguageVersion(3, 12)).partial,
        isTrue,
      );
    });
  });
}
