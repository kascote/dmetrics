// @dart=2.19
// Pre-pattern language versions: `case` arms are constant expressions and
// always count. The `// @dart=` override is honored by the parser (§7.2).
// expect: cyclomatic=3
void legacy(int a) {
  switch (a) {
    case 1:
      print(1);
      break;
    case 2:
      print(2);
      break;
    default:
      print('d');
  }
}
