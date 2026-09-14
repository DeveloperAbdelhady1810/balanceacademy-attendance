import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:attendance_assistant/models/roster_student.dart';
import 'package:attendance_assistant/services/local_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The real sqflite plugin only works on an actual Android/iOS device -
  // `flutter test` runs on the host machine, so LocalDb needs the FFI
  // factory here. Production code is untouched: LocalDb itself never sets
  // databaseFactory, so a real device still uses the real native plugin.
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    channel,
    (call) async => call.method == 'getApplicationSupportDirectory' ? Directory.systemTemp.path : null,
  );

  test('saves, updates, loads and clears a local roster checkpoint', () async {
    final student = RosterStudent(id: 999001, name: 'Test Student', status: 'absent');

    await LocalDb.saveRoster(1, 1, '2026-09-14', [student]);

    var loaded = await LocalDb.loadRoster(1, 1, '2026-09-14');
    expect(loaded, isNotNull);
    expect(loaded!.length, 1);
    expect(loaded.first.name, 'Test Student');
    expect(loaded.first.status, 'absent');

    loaded.first.status = 'present';
    loaded.first.homeworkDone = true;
    loaded.first.quizMark = 8;
    await LocalDb.updateRecord(1, 1, '2026-09-14', loaded.first);

    loaded = await LocalDb.loadRoster(1, 1, '2026-09-14');
    expect(loaded!.first.status, 'present');
    expect(loaded.first.homeworkDone, true);
    expect(loaded.first.quizMark, 8);

    await LocalDb.clearSession(1, 1, '2026-09-14');
    loaded = await LocalDb.loadRoster(1, 1, '2026-09-14');
    expect(loaded, isNull);
  });

  test('persists a walk-in that was never part of the original saveRoster() batch', () async {
    // Regression test for the bug this session fixed: updateRecord() used
    // to be a plain SQL UPDATE, which silently affected zero rows for a
    // student with no existing row yet (a walk-in added via search, not on
    // the course's original expected roster) - their presence mark would
    // be lost on a crash/restart before Submit.
    final walkIn = RosterStudent(id: 999002, name: 'Walk-in Student', status: 'present', isWalkIn: true);

    await LocalDb.updateRecord(2, 1, '2026-09-14', walkIn);

    final loaded = await LocalDb.loadRoster(2, 1, '2026-09-14');
    expect(loaded, isNotNull);
    expect(loaded!.length, 1);
    expect(loaded.first.id, 999002);
    expect(loaded.first.status, 'present');

    await LocalDb.clearSession(2, 1, '2026-09-14');
  });
}
