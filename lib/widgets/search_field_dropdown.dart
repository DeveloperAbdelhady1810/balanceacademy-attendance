import 'package:flutter/material.dart';
import '../models/search_field.dart';

/// Suffix dropdown for a search TextField: picks what the query is matched
/// against.
class SearchFieldDropdown extends StatelessWidget {
  final SearchField value;
  final ValueChanged<SearchField> onChanged;

  const SearchFieldDropdown({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<SearchField>(
          value: value,
          isDense: true,
          items: [
            for (final f in SearchField.values)
              DropdownMenuItem(value: f, child: Text(f.label)),
          ],
          onChanged: (f) {
            if (f != null) onChanged(f);
          },
        ),
      ),
    );
  }
}
