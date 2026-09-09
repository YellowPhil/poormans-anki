enum Rating {
  again(1),
  hard(2),
  good(3),
  easy(4);

  const Rating(this.value);

  final int value;

  static Rating fromValue(int value) =>
      values.firstWhere((r) => r.value == value);
}
