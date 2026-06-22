import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibeide/app.dart';

void main() {
  testWidgets('VibeIDE smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: VibeIdeApp()));
    expect(find.text('VibeIDE'), findsOneWidget);
  });
}
