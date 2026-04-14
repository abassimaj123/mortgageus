/// Strip currency symbols and thousands separators, then parse to double.
/// Returns 0.0 for empty or invalid input.
double parseCurrency(String value) {
  if (value.isEmpty) return 0.0;
  final cleaned = value.replaceAll(RegExp(r'[\$,\s]'), '');
  return double.tryParse(cleaned) ?? 0.0;
}
