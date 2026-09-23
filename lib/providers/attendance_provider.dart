import 'package:flutter/foundation.dart';
import '../models/center.dart';
import '../models/course.dart';
import '../models/roster_student.dart';
import '../models/search_field.dart';
import '../services/api_client.dart';
import '../services/api_exception.dart';
import '../services/local_db.dart';

class AttendanceProvider extends ChangeNotifier {
  final ApiClient _api = ApiClient();

  List<AttendanceCenter> centers = [];
  List<FilterOption> stages = [];
  List<FilterOption> grades = [];
  List<AttendanceCourse> courses = [];

  AttendanceCenter? selectedCenter;
  String? selectedStage;
  String? selectedGrade;
  AttendanceCourse? selectedCourse;

  List<RosterStudent> roster = [];
  int? sessionId;
  String? sessionStatus;
  String? _rosterDate;

  bool isLoading = false;
  String? error;

  /// True when the current roster came from the local checkpoint (the
  /// online fetch failed) rather than a fresh server response - the UI
  /// shows an offline banner off this, matching the sibling desktop app.
  bool isOffline = false;

  void _setLoading(bool value) {
    isLoading = value;
    notifyListeners();
  }

  Future<bool> loadCenters(String token) async {
    _setLoading(true);
    error = null;
    try {
      final result = await _api.get('/assistant/centers', token: token);
      centers = (result['centers'] as List)
          .map((c) => AttendanceCenter.fromJson(c as Map<String, dynamic>))
          .toList();
      _setLoading(false);
      return true;
    } catch (e) {
      error = e is ApiException ? e.message : 'Could not load centers.';
      _setLoading(false);
      return false;
    }
  }

  Future<bool> loadFilters(String token) async {
    _setLoading(true);
    error = null;
    try {
      final result = await _api.get('/assistant/filters', token: token);
      stages = (result['stages'] as List)
          .map((s) => FilterOption.fromJson(s as Map<String, dynamic>))
          .toList();
      grades = (result['grades'] as List)
          .map((g) => FilterOption.fromJson(g as Map<String, dynamic>))
          .toList();
      _setLoading(false);
      return true;
    } catch (e) {
      error = e is ApiException ? e.message : 'Could not load filters.';
      _setLoading(false);
      return false;
    }
  }

  Future<bool> loadCourses(String token) async {
    _setLoading(true);
    error = null;
    try {
      final result = await _api.get(
        '/assistant/courses',
        token: token,
        query: {
          if (selectedStage != null) 'stage': selectedStage!,
          if (selectedGrade != null) 'grade': selectedGrade!,
          if (selectedCenter != null)
            'center_id': selectedCenter!.id.toString(),
        },
      );
      courses = (result['courses'] as List)
          .map((c) => AttendanceCourse.fromJson(c as Map<String, dynamic>))
          .toList();
      _setLoading(false);
      return true;
    } catch (e) {
      error = e is ApiException ? e.message : 'Could not load courses.';
      _setLoading(false);
      return false;
    }
  }

  Future<bool> loadRoster(String token, AttendanceCourse course) async {
    if (selectedCenter == null) return false;
    _setLoading(true);
    error = null;
    selectedCourse = course;
    _rosterDate = DateTime.now().toIso8601String().split('T').first;
    final centerId = selectedCenter!.id;

    try {
      final result = await _api.get(
        '/assistant/courses/${course.id}/roster',
        token: token,
        query: {'center_id': centerId.toString(), 'date': _rosterDate!},
      );
      roster = (result['students'] as List)
          .map((s) => RosterStudent.fromJson(s as Map<String, dynamic>))
          .toList();
      sessionId = result['session_id'] as int?;
      sessionStatus = result['session_status'] as String?;
      isOffline = false;
      await LocalDb.saveRoster(course.id, centerId, _rosterDate!, roster);
      _setLoading(false);
      return true;
    } catch (e) {
      // Online fetch failed - fall back to whatever was last checkpointed
      // locally for this exact course/center/date, so a dropped connection
      // doesn't block the assistant from continuing where they left off.
      final local = await LocalDb.loadRoster(course.id, centerId, _rosterDate!);
      if (local != null) {
        roster = local;
        sessionId = null;
        sessionStatus = null;
        isOffline = true;
        error = null;
        _setLoading(false);
        return true;
      }
      error = e is ApiException ? e.message : 'Could not load the roster.';
      _setLoading(false);
      return false;
    }
  }

  /// Persists one student's mark (or a newly-added walk-in) to the local
  /// checkpoint - call this any time a StudentTile mutates present/absent,
  /// homework, or quiz mark, in addition to the setState()/notifyListeners()
  /// that already redraws the UI.
  void persistCurrent(RosterStudent s) {
    if (selectedCourse == null || selectedCenter == null || _rosterDate == null)
      return;
    LocalDb.updateRecord(
      selectedCourse!.id,
      selectedCenter!.id,
      _rosterDate!,
      s,
    );
  }

  /// Marks a student present by matching a scanned QR code's student number
  /// against the already-loaded roster - no extra API call needed, the
  /// roster response already carries every expected student's number.
  /// Returns the matched student, or null if nobody in the roster matches
  /// (the app then falls back to a manual server-side search).
  RosterStudent? markPresentByStudentNumber(int studentNumber) {
    final match = roster
        .where((s) => s.studentNumber == studentNumber)
        .firstOrNull;
    if (match != null) {
      match.status = 'present';
      persistCurrent(match);
      notifyListeners();
    }
    return match;
  }

  Future<List<RosterStudent>> searchStudents(
    String token,
    String query, {
    SearchField field = SearchField.all,
  }) async {
    if (query.trim().length < field.minLength) return [];
    try {
      final result = await _api.get(
        '/assistant/students/search',
        token: token,
        query: {'q': query.trim(), 'field': field.apiValue},
      );
      return (result['students'] as List)
          .map((s) => RosterStudent.fromSearchJson(s as Map<String, dynamic>))
          .toList();
    } catch (e) {
      error = e is ApiException ? e.message : 'Search failed.';
      return [];
    }
  }

  /// Adds a walk-in (from QR scan or manual search) to the roster if they're
  /// not already on it, marking them present either way.
  void addOrMarkPresent(RosterStudent student) {
    final existingIndex = roster.indexWhere((s) => s.id == student.id);
    final RosterStudent persisted;
    if (existingIndex >= 0) {
      roster[existingIndex].status = 'present';
      persisted = roster[existingIndex];
    } else {
      roster.add(student);
      persisted = student;
    }
    persistCurrent(persisted);
    notifyListeners();
  }

  Future<bool> updateQuizMaxMark(String token, int maxMark) async {
    if (selectedCourse == null) return false;
    try {
      await _api.put(
        '/assistant/courses/${selectedCourse!.id}/quiz-max-mark',
        token: token,
        body: {'quiz_max_mark': maxMark},
      );
      selectedCourse!.quizMaxMark = maxMark;
      return true;
    } catch (e) {
      error = e is ApiException
          ? e.message
          : 'Could not update the quiz scale.';
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>?> submitAttendance(String token) async {
    if (selectedCourse == null || selectedCenter == null) return null;
    _setLoading(true);
    error = null;
    try {
      final date =
          _rosterDate ?? DateTime.now().toIso8601String().split('T').first;
      final result = await _api.post(
        '/assistant/courses/${selectedCourse!.id}/submit',
        token: token,
        body: {
          'center_id': selectedCenter!.id,
          'date': date,
          'records': roster.map((s) => s.toRecordJson()).toList(),
        },
      );
      await LocalDb.clearSession(selectedCourse!.id, selectedCenter!.id, date);
      _setLoading(false);
      return result as Map<String, dynamic>;
    } catch (e) {
      error = e is ApiException ? e.message : 'Could not submit attendance.';
      _setLoading(false);
      return null;
    }
  }

  void resetCourseSelection() {
    selectedStage = null;
    selectedGrade = null;
    courses = [];
    notifyListeners();
  }

  void resetRoster() {
    roster = [];
    selectedCourse = null;
    sessionId = null;
    sessionStatus = null;
    _rosterDate = null;
    isOffline = false;
    notifyListeners();
  }
}
