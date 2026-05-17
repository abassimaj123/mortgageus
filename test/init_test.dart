import 'package:flutter_test/flutter_test.dart';
import 'package:mortgageus/main.dart';

void main() {
  group('App Initialization', () {
    testWidgets('App launches without errors', (WidgetTester tester) async {
      await tester.pumpWidget(const MortgageUSApp());
      await tester.pumpAndSettle();

      // Verify splash or home screen appears
      expect(find.byType(MortgageUSApp), findsOneWidget);
    });

    testWidgets('Navigation bar is present', (WidgetTester tester) async {
      await tester.pumpWidget(const MortgageUSApp());
      await tester.pumpAndSettle();

      // Verify we have navigation
      expect(find.byType(NavigationBar), findsWidgets);
    });
  });
}
