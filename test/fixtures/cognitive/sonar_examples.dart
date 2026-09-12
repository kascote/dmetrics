// The SonarSource whitepaper's worked examples, transliterated to Dart, with
// the numbers the paper gives. The cross-check that this is the same metric.

// Cognitive complexity 7 (cyclomatic 4).
// expect: cognitive=7
int sumOfPrimes(int max) {
  var total = 0;
  outer:
  for (var i = 1; i <= max; ++i) {
    // +1
    for (var j = 2; j < i; ++j) {
      // +2
      if (i % j == 0) {
        // +3
        continue outer; // +1
      }
    }
    total += i;
  }
  return total;
}

// Cognitive complexity 1 (cyclomatic 4).
// expect: cognitive=1
String getWords(int number) {
  switch (number) {
    // +1
    case 1:
      return 'one';
    case 2:
      return 'a couple';
    case 3:
      return 'a few';
    default:
      return 'lots';
  }
}

// The nesting example: 9.
// expect: cognitive=9
void myMethod(bool condition1, bool condition2) {
  try {
    if (condition1) {
      // +1
      for (var i = 0; i < 10; i++) {
        // +2 (nesting 1)
        while (condition2) {
          // +3 (nesting 2)
          condition2 = false;
        }
      }
    }
  } on FormatException catch (_) {
    // +1
    if (condition2) {
      // +2 (nesting 1)
      print('x');
    }
  }
}

// The boolean-operator example: 4.
// expect: cognitive=4
void sequences(bool a, bool b, bool c, bool d, bool e, bool f) {
  if (a && b && c || d || e && f) {
    // +1 if, +1 &&, +1 ||, +1 &&
    print('x');
  }
}

// The lambda example: the `if` inside the lambda pays for the lambda's
// nesting. As one method in the paper: 2. Here the closure is its own
// scope and the method folds it in under include_in_parent.
// expect: cognitive=0 rolled=2
void withLambda(List<int> xs) {
  // expect: cognitive=2
  xs.forEach((x) {
    if (x > 0) print(x); // +2 (nesting 1)
  });
}
