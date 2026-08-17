// Basic smoke test - the app builds and shows the Listit splash.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listit_app/main.dart';

void main() {
  testWidgets('App boots to the splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ListitApp());
    // The splash is the logo mark over the strapline; the logo itself is an
    // image, so the strapline is what there is to assert on.
    expect(find.text('Simple. Safe. Secure.'), findsOneWidget);

    // Tear the tree down before the hand-over fires: past that point the shell
    // starts fetching, and there is no network in a widget test.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
