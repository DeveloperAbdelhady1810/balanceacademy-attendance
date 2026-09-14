import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/roster_student.dart';

/// Local checkpoint of whatever roster was last successfully loaded from
/// the server, kept in sync with every mark the assistant makes - mirrors
/// the sibling desktop app's LocalDb. Makes scanning survive a dropped
/// connection or an app restart mid-session: reopening the same
/// course/center/date restores exactly where the assistant left off, with
/// zero network needed. The only two calls that need connectivity are the
/// initial roster fetch (falls back to this checkpoint if it fails) and
/// the final submit. Cleared once that session is successfully submitted.
class LocalDb {
  static Database? _db;

  static Future<Database> _open() async {
    if (_db != null) return _db!;

    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'attendance_local.db');

    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE local_records (
            course_id INTEGER NOT NULL,
            center_id INTEGER NOT NULL,
            session_date TEXT NOT NULL,
            student_id INTEGER NOT NULL,
            name TEXT NOT NULL,
            email TEXT,
            phone TEXT,
            student_number INTEGER,
            parent_phone TEXT,
            status TEXT NOT NULL,
            homework_done INTEGER,
            quiz_mark INTEGER,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (course_id, center_id, session_date, student_id)
          )
        ''');
      },
    );
    return _db!;
  }

  static Map<String, dynamic> _row(int courseId, int centerId, String date, RosterStudent s) => {
        'course_id': courseId,
        'center_id': centerId,
        'session_date': date,
        'student_id': s.id,
        'name': s.name,
        'email': s.email,
        'phone': s.phone,
        'student_number': s.studentNumber,
        'parent_phone': s.parentPhone,
        'status': s.status,
        'homework_done': s.homeworkDone == null ? null : (s.homeworkDone! ? 1 : 0),
        'quiz_mark': s.quizMark,
        'updated_at': DateTime.now().toIso8601String(),
      };

  /// Overwrites the local checkpoint for this course/center/date with a
  /// freshly-fetched roster - called right after a successful online load.
  static Future<void> saveRoster(int courseId, int centerId, String date, List<RosterStudent> students) async {
    final db = await _open();
    final batch = db.batch();
    batch.delete(
      'local_records',
      where: 'course_id = ? AND center_id = ? AND session_date = ?',
      whereArgs: [courseId, centerId, date],
    );
    for (final s in students) {
      batch.insert('local_records', _row(courseId, centerId, date, s));
    }
    await batch.commit(noResult: true);
  }

  /// Persists one student's mark (or a newly-added walk-in) as the
  /// assistant makes it - fire-and-forget from the UI's point of view, no
  /// network involved. Insert-or-replace so a walk-in with no existing row
  /// yet is still saved, not silently dropped by a plain UPDATE.
  static Future<void> updateRecord(int courseId, int centerId, String date, RosterStudent s) async {
    final db = await _open();
    await db.insert(
      'local_records',
      _row(courseId, centerId, date, s),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Returns the locally-checkpointed roster for this course/center/date,
  /// or null if nothing was ever saved for it (never loaded online before).
  static Future<List<RosterStudent>?> loadRoster(int courseId, int centerId, String date) async {
    final db = await _open();
    final rows = await db.query(
      'local_records',
      where: 'course_id = ? AND center_id = ? AND session_date = ?',
      whereArgs: [courseId, centerId, date],
      orderBy: 'name',
    );
    if (rows.isEmpty) return null;

    return rows
        .map((r) => RosterStudent(
              id: r['student_id'] as int,
              name: r['name'] as String,
              email: r['email'] as String?,
              phone: r['phone'] as String?,
              studentNumber: r['student_number'] as int?,
              parentPhone: r['parent_phone'] as String?,
              status: r['status'] as String,
              homeworkDone: r['homework_done'] == null ? null : (r['homework_done'] as int) == 1,
              quizMark: r['quiz_mark'] as int?,
            ))
        .toList();
  }

  /// Drops the local checkpoint once a session is safely submitted - the
  /// server is now the source of truth for it.
  static Future<void> clearSession(int courseId, int centerId, String date) async {
    final db = await _open();
    await db.delete(
      'local_records',
      where: 'course_id = ? AND center_id = ? AND session_date = ?',
      whereArgs: [courseId, centerId, date],
    );
  }
}
