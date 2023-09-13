int calculate(int a, int b) {
	return a + b;
}

int main(void) {
  int a = 12;
  int b = 20;
  int c = calculate(a, b);
  return c != 22;
}
