import 'package:flutter/material.dart';
import 'native_ui.dart';
import 'domain.dart';

class TaskFieldEditor extends StatefulWidget {
  const TaskFieldEditor({super.key, this.initial, required this.names});
  final TaskField? initial;
  final Iterable<String> names;
  @override
  State<TaskFieldEditor> createState() => _TaskFieldEditorState();
}

class _TaskFieldEditorState extends State<TaskFieldEditor> {
  late final TextEditingController name, value;
  late String type;
  bool checked = false;
  String? error;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.initial?.name ?? '');
    value = TextEditingController(text: widget.initial?.display ?? '');
    type = widget.initial?.type ?? 'Text';
    checked = widget.initial?.value == true;
  }

  @override
  void dispose() {
    name.dispose();
    value.dispose();
    super.dispose();
  }

  void submit() {
    try {
      if (widget.names
          .any((n) => n.toLowerCase() == name.text.trim().toLowerCase())) {
        throw const FormatException('This task already has that field name.');
      }
      final Object data = type == 'Checkbox'
          ? checked
          : type == 'Number'
              ? num.tryParse(value.text.trim()) ?? double.nan
              : value.text.trim();
      Navigator.pop(context, TaskField(name.text.trim(), type, data));
    } on FormatException catch (e) {
      setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          scrollable: true,
          title: Text(widget.initial == null
              ? 'Add custom field'
              : 'Edit custom field'),
          content: SizedBox(
              width: 380,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                    controller: name,
                    autofocus: true,
                    maxLength: 40,
                    decoration: const InputDecoration(
                        labelText: 'Field name',
                        hintText: 'Course, Client, Credits…')),
                const SizedBox(height: 12),
                GritChoiceField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Field type'),
                    items: ['Text', 'Number', 'Checkbox', 'Date']
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (t) => setState(() => type = t!)),
                const SizedBox(height: 12),
                if (type == 'Checkbox')
                  SwitchListTile(
                      title: const Text('Value'),
                      value: checked,
                      onChanged: (v) => setState(() => checked = v))
                else
                  TextField(
                      controller: value,
                      maxLength: type == 'Text' ? 500 : null,
                      keyboardType: type == 'Number'
                          ? const TextInputType.numberWithOptions(
                              decimal: true, signed: true)
                          : TextInputType.text,
                      decoration: InputDecoration(
                          labelText: 'Value',
                          hintText: type == 'Date' ? 'YYYY-MM-DD' : null,
                          errorText: error)),
                if (type == 'Checkbox' && error != null) Text(error!),
              ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(onPressed: submit, child: const Text('Save field'))
          ]);
}
