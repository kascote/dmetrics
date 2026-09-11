import 'package:dmetrics/dmetrics.dart';
import 'package:test/test.dart';

import 'recording_metric.dart';

void main() {
  group('traversal lifecycle (§5.0.1)', () {
    const source = '''
class C {
  void m(int a) {
    if (a > 0) {
      list.forEach((x) { if (x) f(); });
    }
  }
}
''';

    test('the spec example event sequence', () {
      final m = RecordingMetric(
        nodeTypes: {
          'CompilationUnit',
          'ClassDeclaration',
          'MethodDeclaration',
          'FormalParameterList',
          'BlockFunctionBody',
          'IfStatement',
          'FunctionExpression',
        },
      );
      analyze([src(source)], [m], const AnalysisConfig());
      expect(m.events, [
        'enterNode CompilationUnit ctx=lib/c.dart',
        'enterNode ClassDeclaration ctx=lib/c.dart',
        'enterNode MethodDeclaration ctx=C',
        'enterScope C.m',
        'enterNode FormalParameterList ctx=C.m',
        'exitNode FormalParameterList ctx=C.m',
        'enterNode BlockFunctionBody ctx=C.m',
        'enterNode IfStatement ctx=C.m',
        'enterNode FunctionExpression ctx=C.m',
        'enterScope C.m.<closure#1>',
        'enterNode FormalParameterList ctx=C.m.<closure#1>',
        'exitNode FormalParameterList ctx=C.m.<closure#1>',
        'enterNode BlockFunctionBody ctx=C.m.<closure#1>',
        'enterNode IfStatement ctx=C.m.<closure#1>',
        'exitNode IfStatement ctx=C.m.<closure#1>',
        'exitNode BlockFunctionBody ctx=C.m.<closure#1>',
        'exitScope C.m.<closure#1>',
        'exitNode FunctionExpression ctx=C.m',
        'exitNode IfStatement ctx=C.m',
        'exitNode BlockFunctionBody ctx=C.m',
        'exitScope C.m',
        'exitNode MethodDeclaration ctx=C',
        'exitNode ClassDeclaration ctx=lib/c.dart',
        'exitNode CompilationUnit ctx=lib/c.dart',
      ]);
    });

    test('every node has a non-null context and events are bracketed', () {
      final m = RecordingMetric(nodeTypes: {'SimpleIdentifier', 'Block'});
      analyze([src(source)], [m], const AnalysisConfig());
      expect(
        m.events.where((e) => e.startsWith('enterNode')).length,
        m.events.where((e) => e.startsWith('exitNode')).length,
      );
      expect(m.events.where((e) => e.startsWith('enterScope')).length, 2);
      expect(m.events.where((e) => e.startsWith('exitScope')).length, 2);
    });

    test(
      'closure inside build: parent chain closure → method → class → file',
      () {
        final m = RecordingMetric();
        analyze(
          [
            src('''
class W {
  Widget build(BuildContext context) {
    return Builder(builder: (c) {
      if (c != null) return Text('x');
      return Text('y');
    });
  }
}
'''),
          ],
          [m],
          const AnalysisConfig(),
        );
        final closure = m.scopes.singleWhere(
          (s) => s.kind == ScopeKind.closure,
        );
        expect(closure.qualifiedName, 'W.build.<closure#1>');
        expect(closure.id.value, 'lib/c.dart::method:W.build::closure#1');
        expect(_chain(closure), ['closure', 'method', 'class_', 'file']);
        expect(closure.parent!.qualifiedName, 'W.build');
      },
    );

    test(
      'closure in a field initializer: parent chain closure → class_ → file',
      () {
        final m = RecordingMetric(nodeTypes: {'ConditionalExpression'});
        analyze(
          [
            src('''
class C {
  final int x = cond ? 1 : 2;
  final void Function() onTap = () { if (a) b(); };
  static final List<int> Function(int) make = (n) => [n];
}
'''),
          ],
          [m],
          const AnalysisConfig(),
        );
        expect(m.scopes.map((s) => s.qualifiedName), [
          'C.onTap.<closure#1>',
          'C.make.<closure#1>',
        ]);
        expect(m.scopes.map((s) => s.id.value), [
          'lib/c.dart::class:C::closure#1',
          'lib/c.dart::class:C::closure#2',
        ]);
        expect(_chain(m.scopes.first), ['closure', 'class_', 'file']);
        // The initializer-level `?:` is delivered with the class context.
        expect(m.events, contains('enterNode ConditionalExpression ctx=C'));
      },
    );

    test('closure in a top-level variable initializer', () {
      final m = RecordingMetric();
      analyze(
        [src('final handler = () { if (a) b(); };\n')],
        [m],
        const AnalysisConfig(),
      );
      expect(m.scopes.single.qualifiedName, 'handler.<closure#1>');
      expect(m.scopes.single.id.value, 'lib/c.dart::closure#1');
      expect(_chain(m.scopes.single), ['closure', 'file']);
    });

    test('local function in a constructor', () {
      final m = RecordingMetric();
      analyze(
        [
          src('''
class C {
  final int x;
  C(int a) : x = a {
    int helper(int v) => v + 1;
    print(helper(x));
  }
}
'''),
        ],
        [m],
        const AnalysisConfig(),
      );
      expect(m.events, [
        'enterScope C.new',
        'enterScope C.new.helper',
        'exitScope C.new.helper',
        'exitScope C.new',
      ]);
      final helper = m.scopes.last;
      expect(helper.kind, ScopeKind.localFunction);
      expect(helper.id.value, 'lib/c.dart::localFunction:C.new.helper');
      expect(_chain(helper), [
        'localFunction',
        'constructor',
        'class_',
        'file',
      ]);
    });

    test(
      'parameters, metadata and initializers are delivered inside the scope',
      () {
        final m = RecordingMetric(
          nodeTypes: {
            'FormalParameterList',
            'Annotation',
            'ConstructorFieldInitializer',
            'ConditionalExpression',
          },
        );
        analyze(
          [
            src('''
class C {
  final int x;
  @Deprecated('no')
  C(int a, {int b = 0}) : x = a > 0 ? a : b;
}
'''),
          ],
          [m],
          const AnalysisConfig(),
        );
        expect(m.events, [
          'enterScope C.new',
          'enterNode Annotation ctx=C.new',
          'exitNode Annotation ctx=C.new',
          'enterNode FormalParameterList ctx=C.new',
          'exitNode FormalParameterList ctx=C.new',
          'enterNode ConstructorFieldInitializer ctx=C.new',
          'enterNode ConditionalExpression ctx=C.new',
          'exitNode ConditionalExpression ctx=C.new',
          'exitNode ConstructorFieldInitializer ctx=C.new',
          'exitScope C.new',
        ]);
      },
    );

    test('the opening node is delivered to the enclosing context', () {
      final m = RecordingMetric(
        nodeTypes: {
          'FunctionDeclaration',
          'MethodDeclaration',
          'ConstructorDeclaration',
          'FunctionExpression',
        },
      );
      analyze(
        [
          src('''
void f() {}
class C {
  C();
  void m() { g(() {}); }
}
'''),
        ],
        [m],
        const AnalysisConfig(),
      );
      expect(m.events, [
        'enterNode FunctionDeclaration ctx=lib/c.dart',
        'enterScope f',
        // The FunctionExpression under a FunctionDeclaration is not a closure.
        'enterNode FunctionExpression ctx=f',
        'exitNode FunctionExpression ctx=f',
        'exitScope f',
        'exitNode FunctionDeclaration ctx=lib/c.dart',
        'enterNode ConstructorDeclaration ctx=C',
        'enterScope C.new',
        'exitScope C.new',
        'exitNode ConstructorDeclaration ctx=C',
        'enterNode MethodDeclaration ctx=C',
        'enterScope C.m',
        'enterNode FunctionExpression ctx=C.m',
        'enterScope C.m.<closure#1>',
        'exitScope C.m.<closure#1>',
        'exitNode FunctionExpression ctx=C.m',
        'exitScope C.m',
        'exitNode MethodDeclaration ctx=C',
      ]);
    });

    test('measures filters scope events but not node contexts', () {
      final m = RecordingMetric(
        measures: {ScopeKind.method},
        nodeTypes: {'IfStatement'},
      );
      analyze([src(source)], [m], const AnalysisConfig());
      expect(m.events, [
        'enterScope C.m',
        'enterNode IfStatement ctx=C.m',
        // The closure is not measured by this metric, yet its nodes still
        // arrive with the closure context: ctx is engine truth.
        'enterNode IfStatement ctx=C.m.<closure#1>',
        'exitNode IfStatement ctx=C.m.<closure#1>',
        'exitNode IfStatement ctx=C.m',
        'exitScope C.m',
      ]);
    });

    test('onStartRun and finish fire once per run, files in path order', () {
      final m = RecordingMetric();
      final report = analyze(
        [
          src('void b() {}', path: 'lib/b.dart'),
          src('void a() {}', path: 'lib/a.dart'),
        ],
        [m],
        const AnalysisConfig(),
      );
      expect(m.startRuns, 1);
      expect(m.finishes, 1);
      expect(report.files.map((f) => f.path), ['lib/a.dart', 'lib/b.dart']);
      expect(m.events, [
        'enterScope a',
        'exitScope a',
        'enterScope b',
        'exitScope b',
      ]);
    });

    test('duplicate source paths and metric ids are rejected', () {
      expect(
        () => analyze(
          [src(''), src('')],
          [RecordingMetric()],
          const AnalysisConfig(),
        ),
        throwsArgumentError,
      );
      expect(
        () => analyze(
          [src('')],
          [RecordingMetric(), RecordingMetric()],
          const AnalysisConfig(),
        ),
        throwsArgumentError,
      );
    });
  });
}

List<String> _chain(ScopeContext ctx) => [
  for (ScopeContext? c = ctx; c != null; c = c.parent) c.kind.name,
];
