import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/roster_student.dart';
import '../models/search_field.dart';
import '../widgets/search_field_dropdown.dart';
import '../providers/attendance_provider.dart';
import '../providers/auth_provider.dart';

/// Pops with the picked RosterStudent, or null if the user backs out.
/// Used to find a walk-in who isn't on the expected roster (e.g. a student
/// whose home center doesn't match, or who registered but was never
/// assigned one) - see AssistantController::searchStudents() for why this
/// deliberately searches every student on the platform, not just this
/// course's expected roster.
class StudentSearchScreen extends StatefulWidget {
  const StudentSearchScreen({super.key});

  @override
  State<StudentSearchScreen> createState() => _StudentSearchScreenState();
}

class _StudentSearchScreenState extends State<StudentSearchScreen> {
  final _controller = TextEditingController();
  SearchField _field = SearchField.all;
  bool _searched = false;
  List<RosterStudent> _results = [];
  bool _searching = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final token = context.read<AuthProvider>().token;
    if (token == null || query.trim().length < _field.minLength) {
      setState(() {
        _results = [];
        _searched = false;
      });
      return;
    }

    setState(() => _searching = true);
    final results = await context.read<AttendanceProvider>().searchStudents(
      token,
      query,
      field: _field,
    );
    if (!mounted) return;
    setState(() {
      _results = results;
      _searching = false;
      _searched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Find a Student')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: _search,
              decoration: InputDecoration(
                labelText:
                    'Search by ${_field.label.toLowerCase()} - press Enter',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: SearchFieldDropdown(
                  value: _field,
                  onChanged: (f) {
                    setState(() => _field = f);
                    if (_controller.text.trim().isNotEmpty)
                      _search(_controller.text);
                  },
                ),
              ),
            ),
          ),
          if (_searching) const LinearProgressIndicator(),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(
                      _searched
                          ? 'No students found.'
                          : 'Pick what to search by, type, then press Enter.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (context, index) {
                      final student = _results[index];
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(student.name),
                        subtitle: Text(
                          [
                            if (student.studentNumber != null)
                              '#${student.studentNumber}',
                            if (student.phone != null) student.phone!,
                          ].join(' · '),
                        ),
                        onTap: () => Navigator.of(context).pop(student),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
