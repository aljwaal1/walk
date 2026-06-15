import 'package:flutter_test/flutter_test.dart';
import 'package:walking_companion/main.dart';

void main() {
  testWidgets('Walking Companion starts', (tester) async {
    await tester.pumpWidget(const WalkingCompanionApp());
    expect(find.text('رفيق المشي'), findsOneWidget);
  });
}
