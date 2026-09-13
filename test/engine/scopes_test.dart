import 'package:dmetrics/dmetrics.dart';
import 'package:test/test.dart';

import 'recording_metric.dart';

void main() {
  List<ScopeContext> scopesOf(String content, {String path = 'lib/c.dart'}) {
    final m = RecordingMetric();
    analyze([src(content, path: path)], [m], const AnalysisConfig());
    return m.scopes;
  }

  FileReport fileOf(String content) => analyze(
    [src(content)],
    [RecordingMetric()],
    const AnalysisConfig(),
  ).files.single;

  group('scope kinds and names', () {
    test('every measured kind', () {
      final scopes = scopesOf('''
int f() => 0;
int get g => 0;
set s(int v) {}
class C {
  C();
  C.named();
  int m() => 0;
  int get x => 0;
  set x(int v) {}
  bool operator ==(Object o) => true;
  int operator -() => 0;
  int operator -(int o) => 0;
  void l() {
    int local() => 0;
    final c = () => 0;
  }
}
''');
      expect(
        {for (final s in scopes) s.qualifiedName: s.kind},
        {
          'f': ScopeKind.function,
          'g': ScopeKind.getter,
          's': ScopeKind.setter,
          'C.new': ScopeKind.constructor,
          'C.named': ScopeKind.constructor,
          'C.m': ScopeKind.method,
          'C.x': ScopeKind.getter,
          'C.x#2': ScopeKind.setter,
          'C.==': ScopeKind.operator,
          'C.unary-': ScopeKind.operator,
          'C.-': ScopeKind.operator,
          'C.l': ScopeKind.method,
          'C.l.local': ScopeKind.localFunction,
          'C.l.<closure#1>': ScopeKind.closure,
        }.map((k, v) => MapEntry(k.replaceFirst('#2', ''), v)),
      );
      expect(scopes.map((s) => s.name), contains('new'));
    });

    test('class-like contexts: mixin, enum, extension, extension type', () {
      final scopes = scopesOf('''
mixin M { void m() {} }
enum E { a; void e() {} }
extension X on int { void x() {} }
extension on int { void anon() {} }
extension type T(int i) { void t() {} }
''');
      expect(scopes.map((s) => s.qualifiedName), [
        'M.m',
        'E.e',
        'X.x',
        '<extension>.anon',
        'T.t',
      ]);
      expect(scopes.map((s) => s.parent!.kind).toSet(), {ScopeKind.class_});
    });

    test(
      'abstract, external and redirecting-factory declarations open no scope',
      () {
        final scopes = scopesOf('''
abstract class A {
  void abstractMethod();
  external void externalMethod();
  factory A.redirect() = B;
  A.real() : super();
  external A.ext();
}
class B extends A { B() : super.real(); }
external void topExternal();
''');
        expect(scopes.map((s) => s.qualifiedName), ['A.real', 'B.new']);
      },
    );
  });

  group('scope identity (§7.3)', () {
    test('kind is part of the id so display-name collisions stay distinct', () {
      final scopes = scopesOf('''
class C {
  C.foo();
  void foo() {}
  int get x => 0;
  set x(int v) {}
}
''');
      expect(scopes.map((s) => s.id.value), [
        'lib/c.dart::constructor:C.foo',
        'lib/c.dart::method:C.foo',
        'lib/c.dart::getter:C.x',
        'lib/c.dart::setter:C.x',
      ]);
    });

    test('recovered source with a duplicated method gets the #2 fallback', () {
      final file = fileOf('''
class C {
  void m() {}
  void m() {}
  void m() {}
}
''');
      expect(file.partial, isFalse, reason: 'duplicates are not parse errors');
      expect(file.scopes.map((s) => s.id.value), [
        'lib/c.dart::method:C.m',
        'lib/c.dart::method:C.m#2',
        'lib/c.dart::method:C.m#3',
      ]);
      expect(file.scopes.map((s) => s.scope.qualifiedName), [
        'C.m',
        'C.m',
        'C.m',
      ]);
    });

    test('closure ids are ordinal under the parent id, display per owner', () {
      final scopes = scopesOf('''
class C {
  final a = () => 1;
  final b = () => 2;
  void m() {
    f(() => 1, () => 2);
    g(() { h(() => 3); });
  }
}
''');
      expect(
        {
          for (final s in scopes)
            if (s.kind == ScopeKind.closure) s.id.value: s.qualifiedName,
        },
        {
          'lib/c.dart::class:C::closure#1': 'C.a.<closure#1>',
          'lib/c.dart::class:C::closure#2': 'C.b.<closure#1>',
          'lib/c.dart::method:C.m::closure#1': 'C.m.<closure#1>',
          'lib/c.dart::method:C.m::closure#2': 'C.m.<closure#2>',
          'lib/c.dart::method:C.m::closure#3': 'C.m.<closure#3>',
          'lib/c.dart::method:C.m::closure#3::closure#1':
              'C.m.<closure#3>.<closure#1>',
        },
      );
    });

    test('fingerprint ignores the declared name, follows the body', () {
      String fp(String source) => scopesOf(source).single.fingerprint;
      expect(fp('int a(int x) => x + 1;'), fp('int renamed(int x) => x + 1;'));
      expect(fp('int a(int x) => x + 1;'), isNot(fp('int a(int x) => x + 2;')));
      expect(
        fp('class C { C.foo(int x) : assert(x > 0); }'),
        fp('class D { D.bar(int x) : assert(x > 0); }'),
      );
      expect(
        fp('class C { void m() { m(); } }'),
        isNot(fp('class C { void n() { n(); } }')),
        reason: 'the name is masked only where it is declared',
      );
      expect(fp('int a(int x) => x + 1;'), matches(r'^[0-9a-f]{8}$'));
    });

    test('two packages with identical relative paths get distinct ids', () {
      const content = 'class C { void m() {} }';
      final report = analyze(
        [
          const SourceFile(
            path: 'a/lib/src/parser.dart',
            content: content,
            configRoot: 'a',
          ),
          const SourceFile(
            path: 'b/lib/src/parser.dart',
            content: content,
            configRoot: 'b',
          ),
        ],
        [RecordingMetric()],
        const AnalysisConfig(),
      );
      expect(report.files.map((f) => f.scopes.single.id.value), [
        'a/lib/src/parser.dart::method:C.m',
        'b/lib/src/parser.dart::method:C.m',
      ]);
    });
  });

  group('spans and ordering', () {
    test('span covers metadata through body, excluding the doc comment', () {
      const content = '''
class C {
  /// Docs.
  @override
  int m(int a) {
    return a;
  }
}
''';
      final s = scopesOf(content).single;
      expect(
        content.substring(s.span.start.offset, s.span.end.offset),
        '@override\n  int m(int a) {\n    return a;\n  }',
      );
      expect(s.span.start.line + 1, 3);
    });

    test('scopes are reported by start offset, then end offset', () {
      final file = fileOf('''
void b() { f(() { g(() {}); }); }
void a() {}
''');
      expect(file.scopes.map((s) => s.scope.qualifiedName), [
        'b',
        'b.<closure#1>',
        'b.<closure#1>.<closure#1>',
        'a',
      ]);
    });

    test('parse errors mark every scope partial and keep measuring', () {
      final file = fileOf('''
void ok() {}
void broken( {
  if (x) {}
}
''');
      expect(file.partial, isTrue);
      expect(file.diagnostics, isNotEmpty);
      expect(file.scopes.map((s) => s.scope.qualifiedName), ['ok', 'broken']);
      expect(file.scopes.map((s) => s.scope.partial), everyElement(isTrue));
    });
  });
}
