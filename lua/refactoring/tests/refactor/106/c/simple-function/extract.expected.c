#include <stdio.h>

void foo_bar(int a, int test, int test_other) {
  for (int idx = test - 1; idx < test_other; idx++) {
    printf("%d %d", idx, a);
  }
}


void simple_function(int a) {
  int test = 1, test_other = 1;

  foo_bar(a, test, test_other);
}
