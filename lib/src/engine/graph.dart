/// Directed-graph algorithms over string-named nodes, shared by the coupling
/// metric (cycle membership per library) and the `deps` view (components
/// and back edges over libraries and over directories), so the two never
/// disagree about what a cycle is.
library;

/// A vertex order that a greedy heuristic makes as few edges as it can point
/// backwards (Eades, Lin and Smyth, 1993): sinks go last, sources first, and
/// among what remains the vertex with the largest weighted out-minus-in
/// degree goes next. An edge from a later vertex to an earlier one is a back
/// edge, and removing every back edge leaves the graph acyclic, so the back
/// edges are the imports that hold a cycle together. The minimum such set is
/// NP-hard to find; this one is close and deterministic (ties by name).
/// Self-edges are ignored; parallel edges add up.
List<String> feedbackOrder(
  Iterable<String> nodes,
  Iterable<(String from, String to, num weight)> edges,
) {
  final g = _Weighted(nodes, edges);
  final head = <String>[];
  final tail = <String>[];
  while (g.remaining.isNotEmpty) {
    var peeled = true;
    while (peeled) {
      peeled = g.peel(tail, sinks: true);
      peeled = g.peel(head, sinks: false) || peeled;
    }
    if (g.remaining.isNotEmpty) head.add(g.pick());
  }
  return [...head, ...tail.reversed];
}

/// The graph as [feedbackOrder] consumes it: weighted adjacency both ways,
/// and the vertices not yet placed.
class _Weighted {
  final List<String> sorted;
  final Map<String, Map<String, num>> out;
  final Map<String, Map<String, num>> into;
  late final Set<String> remaining = sorted.toSet();

  _Weighted._(this.sorted, this.out, this.into);

  factory _Weighted(
    Iterable<String> nodes,
    Iterable<(String, String, num)> edges,
  ) {
    final sorted = nodes.toList()..sort();
    final out = {for (final n in sorted) n: <String, num>{}};
    final into = {for (final n in sorted) n: <String, num>{}};
    for (final (from, to, w) in edges) {
      if (from == to) continue;
      out[from]![to] = (out[from]![to] ?? 0) + w;
      into[to]![from] = (into[to]![from] ?? 0) + w;
    }
    return _Weighted._(sorted, out, into);
  }

  /// Weighted degree over the vertices still remaining.
  num degree(Map<String, num> side) => side.entries
      .where((e) => remaining.contains(e.key))
      .fold(0, (sum, e) => sum + e.value);

  /// Moves every current sink (or source) into [to]; true when any moved.
  /// Sinks are read back reversed, so they are peeled in reverse name order
  /// and isolated vertices still come out sorted.
  bool peel(List<String> to, {required bool sinks}) {
    var any = false;
    for (final n in sinks ? sorted.reversed : sorted) {
      if (!remaining.contains(n)) continue;
      if (degree(sinks ? out[n]! : into[n]!) != 0) continue;
      remaining.remove(n);
      to.add(n);
      any = true;
    }
    return any;
  }

  /// Removes and returns the remaining vertex with the largest out-minus-in
  /// degree, first by name on a tie.
  String pick() {
    String? best;
    num bestDelta = double.negativeInfinity;
    for (final n in sorted) {
      if (!remaining.contains(n)) continue;
      final delta = degree(out[n]!) - degree(into[n]!);
      if (delta > bestDelta) {
        best = n;
        bestDelta = delta;
      }
    }
    remaining.remove(best!);
    return best;
  }
}

/// Whether the edge points from a later vertex of [position] (a node to its
/// index in a [feedbackOrder]) to an earlier one.
bool isBackEdge(Map<String, int> position, String from, String to) =>
    position[from]! > position[to]!;

/// Tarjan's algorithm. Components come out in reverse topological order of
/// the condensation; the caller sorts. Iterative, so a long import chain
/// cannot overflow the stack.
List<List<String>> stronglyConnectedComponents(
  Iterable<String> nodes,
  List<String> Function(String) edges,
) => _Tarjan(nodes, edges).components();

class _Tarjan {
  final Iterable<String> nodes;
  final List<String> Function(String) edges;
  final _index = <String, int>{};
  final _low = <String, int>{};
  final _onStack = <String>{};
  final _stack = <String>[];
  final _out = <List<String>>[];
  var _next = 0;

  _Tarjan(this.nodes, this.edges);

  List<List<String>> components() {
    for (final n in nodes) {
      if (!_index.containsKey(n)) _visit(n);
    }
    return _out;
  }

  void _visit(String root) {
    final work = <(String, Iterator<String>)>[(root, _enter(root))];
    while (work.isNotEmpty) {
      final (node, it) = work.last;
      if (it.moveNext()) {
        final next = it.current;
        if (!_index.containsKey(next)) {
          work.add((next, _enter(next)));
        } else if (_onStack.contains(next)) {
          _low[node] = _low[node]!.clamp(0, _index[next]!);
        }
        continue;
      }
      work.removeLast();
      if (work.isNotEmpty) {
        final parent = work.last.$1;
        _low[parent] = _low[parent]!.clamp(0, _low[node]!);
      }
      if (_low[node] == _index[node]) _pop(node);
    }
  }

  Iterator<String> _enter(String node) {
    _index[node] = _low[node] = _next++;
    _stack.add(node);
    _onStack.add(node);
    return edges(node).iterator;
  }

  void _pop(String root) {
    final component = <String>[];
    String member;
    do {
      member = _stack.removeLast();
      _onStack.remove(member);
      component.add(member);
    } while (member != root);
    _out.add(component);
  }
}
