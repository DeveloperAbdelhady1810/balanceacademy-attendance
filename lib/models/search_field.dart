import 'roster_student.dart';

/// What the assistant is searching by. [apiValue] is the `field` param the
/// backend's /assistant/students/search understands.
enum SearchField {
  all('all', 'All'),
  name('name', 'Name'),
  studentId('student_id', 'Student ID'),
  phone('phone', 'Phone'),
  parentPhone('parent_phone', 'Parent phone'),
  email('email', 'Email');

  final String apiValue;
  final String label;
  const SearchField(this.apiValue, this.label);

  /// Student IDs are short, so one character is enough there.
  int get minLength => this == SearchField.studentId ? 1 : 2;

  /// Local (already-loaded roster) equivalent of the backend search.
  bool matches(RosterStudent s, String rawQuery) {
    var q = rawQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    final idQuery = q.replaceFirst(RegExp(r'^mk-?'), '');
    final number = s.studentNumber?.toString() ?? '';
    switch (this) {
      case SearchField.name:
        return s.name.toLowerCase().contains(q);
      case SearchField.studentId:
        return number.contains(idQuery);
      case SearchField.phone:
        return (s.phone ?? '').contains(q);
      case SearchField.parentPhone:
        return (s.parentPhone ?? '').contains(q);
      case SearchField.email:
        return (s.email ?? '').toLowerCase().contains(q);
      case SearchField.all:
        return s.name.toLowerCase().contains(q) ||
            (s.phone ?? '').contains(q) ||
            (s.parentPhone ?? '').contains(q) ||
            (s.email ?? '').toLowerCase().contains(q) ||
            number.contains(q);
    }
  }
}
