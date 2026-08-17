// The app should render in Inter, the same typeface as the website and the CRM.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listit_app/theme.dart';

void main() {
  testWidgets('text styles resolve to Inter', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      // Inside a Scaffold, as every screen in the app is — the bare root has
      // its own default style that no real page ever sees.
      home: Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const Text('Handgloves');
      })),
    ));

    final t = Theme.of(ctx);
    expect(t.textTheme.bodyMedium!.fontFamily, 'Inter');
    expect(t.textTheme.titleLarge!.fontFamily, 'Inter');
    expect(DefaultTextStyle.of(ctx).style.fontFamily, 'Inter');
  });
}
