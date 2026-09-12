// Collection `if`, `else if`, `else` and `for` elements count like the
// statements: `if` and `for` +1 plus nesting, `else if` and `else` +1 flat,
// an element under another is one level deeper.

// expect: cognitive=1
List<int> ifElement(bool a) => [if (a) 1];

// expect: cognitive=2
List<int> ifElse(bool a) => [if (a) 1 else 2];

// expect: cognitive=3
List<int> ifElseIfElse(bool a, bool b) => [
  if (a) 1 else if (b) 2 else 3,
];

// expect: cognitive=1
List<int> ifCaseElement(Object o) => [if (o case int x) x];

// expect: cognitive=1
List<int> forElement(List<int> xs) => [for (final x in xs) x];

// expect: cognitive=3
List<int> forIf(List<int> xs) => [
  for (final x in xs)
    if (x > 0) x,
];

// expect: cognitive=6
List<int> ifForIf(bool a, List<int> xs) => [
  if (a)
    for (final x in xs)
      if (x > 0) x,
];

// expect: cognitive=3
Map<int, int> mapElements(List<int> xs) => {
  for (final x in xs)
    if (x > 0) x: x,
};

// A list of conditional children, the Flutter `build` shape: +1 each, flat.
// expect: cognitive=4
List<String> children(bool a, bool b, bool c, bool d) => [
  if (a) 'a',
  if (b) 'b',
  if (c) 'c',
  if (d) 'd',
];

// The `else` element is +1 flat; the `for` in it is one level deep: +2.
// expect: cognitive=4
List<int> nestedInElse(bool a, List<int> xs) => [
  if (a) 1 else for (final x in xs) x,
];
