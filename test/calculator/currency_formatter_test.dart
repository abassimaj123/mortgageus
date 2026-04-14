import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mortgage_us/core/formatters/currency_input_formatter.dart';
import 'package:mortgage_us/core/utils/number_parser.dart';

TextEditingValue _apply(CurrencyInputFormatter fmt, String text) {
  return fmt.formatEditUpdate(
    TextEditingValue.empty,
    TextEditingValue(text: text),
  );
}

void main() {
  final fmt = CurrencyInputFormatter();

  group('CurrencyInputFormatter', () {

    test('Adds thousand separators correctly', () {
      expect(_apply(fmt, '300000').text, equals('300,000'));
    });

    test('Handles empty input', () {
      expect(_apply(fmt, '').text, equals(''));
    });

    test('Strips existing commas before reformatting', () {
      expect(_apply(fmt, '1,500,000').text, equals('1,500,000'));
    });

    test('Single digits pass through unchanged', () {
      expect(_apply(fmt, '5').text, equals('5'));
    });
  });

  group('parseCurrency', () {

    test('Removes commas and returns double', () {
      expect(parseCurrency('300,000'), equals(300000.0));
    });

    test('Removes dollar signs', () {
      expect(parseCurrency('\$1,500,000'), equals(1500000.0));
    });

    test('Returns 0.0 for empty input', () {
      expect(parseCurrency(''), equals(0.0));
    });

    test('Returns 0.0 for invalid input', () {
      expect(parseCurrency('abc'), equals(0.0));
    });
  });
}
