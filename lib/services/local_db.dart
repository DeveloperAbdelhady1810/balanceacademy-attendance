import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../models/roster_student.dart';
import '../models/search_field.dart';

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
      version: 2,
      onCreate: (db, version) async {
        await _createDirectory(db);
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
            is_walk_in INTEGER NOT NULL DEFAULT 0,
            updated_at TEXT NOT NULL,
            PRIMARY KEY (course_id, center_id, session_date, student_id)
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE local_records ADD COLUMN is_walk_in INTEGER NOT NULL DEFAULT 0');
          await _createDirectory(db);
        }
      },
    );
    return _db!;
  }

  static Future<void> _createDirectory(Database db) => db.execute('''
        CREATE TABLE IF NOT EXISTS student_directory (
          student_id INTEGER PRIMARY KEY,
          name TEXT NOT NULL,
          email TEXT,
          phone TEXT,
          student_number INTEGER,
          parent_phone TEXT
        )
      ''');

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
        'is_walk_in': s.isWalkIn ? 1 : 0,
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
              isWalkIn: (r['is_walk_in'] as int?) == 1,
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

  // ── student directory (offline walk-in search) ───────────────────────────

  static List<RosterStudent>? _directoryCache;

  /// Replaces the downloaded student list - every student on the platform,
  /// so a walk-in can be found with no connection.
  static Future<void> saveDirectory(List<RosterStudent> students) async {
    final db = await _open();
    final batch = db.batch();
    batch.delete('student_directory');
    for (final s in students) {
      batch.insert('student_directory', {
        'student_id': s.id,
        'name': s.name,
        'email': s.email,
        'phone': s.phone,
        'student_number': s.studentNumber,
        'parent_phone': s.parentPhone,
      });
    }
    await batch.commit(noResult: true);
    _directoryCache = null;
  }

  static Future<List<RosterStudent>> _directory() async {
    final cached = _directoryCache;
    if (cached != null) return cached;
    final db = await _open();
    final rows = await db.query('student_directory', orderBy: 'name');
    return _directoryCache = rows
        .map((r) => RosterStudent(
              id: r['student_id'] as int,
              name: r['name'] as String,
              email: r['email'] as String?,
              phone: r['phone'] as String?,
              studentNumber: r['student_number'] as int?,
              parentPhone: r['parent_phone'] as String?,
              status: 'present',
              isWalkIn: true,
            ))
        .toList();
  }

  /// Number of students in the downloaded list (0 = never downloaded).
  static Future<int> directorySize() async => (await _directory()).length;

  /// Same search the server offers, run on the downloaded list (max 20 hits).
  static Future<List<RosterStudent>> searchDirectory(String query, SearchField field) async {
    final all = await _directory();
    return all.where((s) => field.matches(s, query)).take(20).toList();
  }
}
