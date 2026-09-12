// Collection if: +1 (kind if). else element: 0.
// expect: cyclomatic=2
List<int> ifElement(bool b) => [1, if (b) 2 else 3];

// Collection if-case: +1 (kind if-case); its guard counts.
// expect: cyclomatic=3
List<int> ifCaseElement(Object o) => [if (o case int x when x > 0) x];

// Collection for: +1 (kind loop).
// expect: cyclomatic=2
List<int> forElement(List<int> xs) => [for (final x in xs) x * 2];

// Null-aware elements `?x`, `?k: v`, `k: ?v` (Dart 3.8+): +1 each (kind if),
// like the `if (x != null) x` they replace. Spreads, null-aware or not: 0.
// expect: cyclomatic=3
Map<String, int> nullAwareMap(int? a, String? k, Map<String, int>? m) => {
  ?k: 1,
  'b': ?a,
  ...?m,
  ...{'c': 3},
};

// expect: cyclomatic=2
List<int> nullAwareList(int? a, List<int>? xs) => [
  ?a,
  ...?xs,
  ...[1],
];

// Nested elements compose: for + if + else-if.
// expect: cyclomatic=4
List<int> nested(List<int> xs, bool b) => [
  for (final x in xs)
    if (b) x else if (x > 0) -x,
];
