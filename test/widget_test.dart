// Basic smoke test - the app builds and shows the Listit home header.
import 'package:flutter_test/flutter_test.dart';
import 'package:listit_app/main.dart';

void main() {
  testWidgets('App boots to home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ListitApp());
    expect(find.text('list'), findsWidgets);
  });
}
