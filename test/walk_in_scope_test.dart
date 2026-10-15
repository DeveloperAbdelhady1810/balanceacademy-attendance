import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:attendance_assistant/providers/attendance_provider.dart';
import 'package:attendance_assistant/providers/auth_provider.dart';
import 'package:attendance_assistant/screens/student_search_screen.dart';

Future<void> _open(WidgetTester tester) async {
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider(create: (_) => AttendanceProvider()),
    ],
    child: const MaterialApp(home: StudentSearchScreen()),
  ));
  await tester.pump();
}

void main() {
  testWidgets('the walk-in search scope the assistant picked is kept for the next students', (tester) async {
    await _open(tester);
    expect(find.text('All'), findsOneWidget);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Student ID').last);
    await tester.pumpAndSettle();
    expect(find.text('Student ID'), findsOneWidget);

    // next walk-in student: page reopened, scope is still Student ID
    await tester.pumpWidget(const SizedBox());
    await _open(tester);
    expect(find.text('Student ID'), findsOneWidget);
    expect(find.text('All'), findsNothing);

    // changing it again sticks too
    await tester.tap(find.text('Student ID'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name').last);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await _open(tester);
    expect(find.text('Name'), findsOneWidget);
  });
}
