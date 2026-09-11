// Switch expressions count like statements: refutable arms +1, `_` 0.
// expect: cyclomatic=4
String constants(int a) => switch (a) {
  1 => 'one',
  2 => 'two',
  3 => 'three',
  _ => 'many',
};

// expect: cyclomatic=6
String patterns(Object o) => switch (o) {
  int _ => 'int', // +1
  String s when s.isEmpty => 'empty', // +1 arm, +1 when
  (int a, int b) => '$a$b', // +1
  >= 100 => 'big', // +1
  var other => '$other', // 0
};
