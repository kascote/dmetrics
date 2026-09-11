class Parser {
  final List<Token> tokens = [];
  int pos = 0;

  Expr parseExpr() {
    final t = tokens[pos];
    switch (t.kind) {
      case Kind.number when t.text.isNotEmpty:
        return Num(t.text);
      case Kind.string:
        return Str(t.text);
      case Kind.ident:
        if (peek() == Kind.lparen) {
          return parseCall(t);
        }
        return Ref(t.text);
      case Kind.lbracket when pos < tokens.length:
        final items = <Expr>[];
        if (peek() == Kind.rbracket) {
          return ListLit(items);
        }
        tokens.forEach((x) {
          if (x.kind == Kind.comma) items.add(Ref(','));
        });
        return ListLit(items);
      case Kind.minus:
        final operand = parseExpr();
        return Neg(operand ?? Num('0'));
      case Kind.lparen:
        final inner = parseExpr();
        if (peek() != Kind.rparen) {
          throw StateError('expected )');
        }
        return inner;
      default:
        throw StateError('unexpected ${t.kind}');
    }
  }
}
