import 'package:dmetrics/src/engine/graph.dart';
import 'package:test/test.dart';

/// The shared graph algorithms. Components are what the coupling metric
/// reports as `cycle`; the feedback order is what `deps` marks as back
/// edges, so both must be deterministic and the order must leave a DAG
/// with no back edge at all.
void main() {
  List<String> edges(Map<String, List<String>> g, String n) => g[n] ?? [];

  Set<(String, String)> backEdges(
    Map<String, List<String>> g, {
    Map<(String, String), num> weights = const {},
  }) {
    final order = feedbackOrder(g.keys, [
      for (final e in g.entries)
        for (final t in e.value) (e.key, t, weights[(e.key, t)] ?? 1),
    ]);
    final position = {for (var i = 0; i < order.length; i++) order[i]: i};
    return {
      for (final e in g.entries)
        for (final t in e.value)
          if (isBackEdge(position, e.key, t)) (e.key, t),
    };
  }

  group('stronglyConnectedComponents', () {
    test('a DAG is all singletons; a cycle is one component', () {
      final g = {
        'a': ['b', 'c'],
        'b': ['c'],
        'c': ['a'],
        'd': ['a'],
        'e': <String>[],
      };
      final components = stronglyConnectedComponents(
        g.keys,
        (n) => edges(g, n),
      );
      expect(components.map((c) => (c..sort()).join(',')).toSet(), {
        'a,b,c',
        'd',
        'e',
      });
    });

    test('a long chain does not overflow', () {
      final g = {
        for (var i = 0; i < 20000; i++) 'n$i': ['n${i + 1}'],
      };
      g['n20000'] = ['n0'];
      final components = stronglyConnectedComponents(
        g.keys,
        (n) => edges(g, n),
      );
      expect(components.single.length, 20001);
    });
  });

  group('feedbackOrder', () {
    test('a DAG orders dependents first and has no back edge', () {
      final g = {
        'app': ['ui', 'data'],
        'ui': ['core'],
        'data': ['core'],
        'core': <String>[],
      };
      final order = feedbackOrder(g.keys, [
        for (final e in g.entries)
          for (final t in e.value) (e.key, t, 1),
      ]);
      expect(order.first, 'app');
      expect(order.last, 'core');
      expect(backEdges(g), isEmpty);
    });

    test('between two mutually dependent nodes the lighter edge is back', () {
      final g = {
        'engine': ['config'],
        'config': ['engine'],
      };
      expect(
        backEdges(
          g,
          weights: {('engine', 'config'): 5, ('config', 'engine'): 3},
        ),
        {('config', 'engine')},
      );
      expect(
        backEdges(
          g,
          weights: {('engine', 'config'): 2, ('config', 'engine'): 9},
        ),
        {('engine', 'config')},
      );
    });

    test('a three-cycle needs exactly one back edge', () {
      final g = {
        'a': ['b'],
        'b': ['c'],
        'c': ['a'],
      };
      expect(backEdges(g), hasLength(1));
    });

    test('ties break by name, so the order is stable', () {
      final g = {
        'x': ['y'],
        'y': ['x'],
      };
      expect(feedbackOrder(g.keys, [('x', 'y', 1), ('y', 'x', 1)]), ['x', 'y']);
      expect(feedbackOrder(['y', 'x'], [('y', 'x', 1), ('x', 'y', 1)]), [
        'x',
        'y',
      ]);
    });

    test('self-edges are ignored and nodes without edges are kept', () {
      expect(feedbackOrder(['b', 'a'], [('a', 'a', 1)]), ['a', 'b']);
    });
  });
}
