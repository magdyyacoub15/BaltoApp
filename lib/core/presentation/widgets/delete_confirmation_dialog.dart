import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../localization/language_provider.dart';

class DeleteConfirmationDialog extends ConsumerStatefulWidget {
  final String title;
  final String content;
  final String? confirmText;
  final String? deleteButtonText;
  final VoidCallback onDelete;

  const DeleteConfirmationDialog({
    super.key,
    required this.title,
    required this.content,
    this.confirmText,
    this.deleteButtonText,
    required this.onDelete,
  });

  @override
  ConsumerState<DeleteConfirmationDialog> createState() =>
      _DeleteConfirmationDialogState();
}

class _DeleteConfirmationDialogState
    extends ConsumerState<DeleteConfirmationDialog> {
  final TextEditingController _controller = TextEditingController();
  bool _isValid = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final confirmTextToUse = widget.confirmText ?? ref.tr('delete');
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(widget.title, textAlign: TextAlign.right),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(widget.content, textAlign: TextAlign.right),
            const SizedBox(height: 20),
            Text(
              ref.tr('type_to_confirm', [confirmTextToUse]),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: ref.tr('confirmation_word'),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: _isValid ? Colors.green : Colors.red,
                  ),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _isValid = value.trim() == confirmTextToUse;
                });
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(ref.tr('cancel')),
        ),
        ElevatedButton(
          onPressed: _isValid
              ? () {
                  Navigator.pop(context, true);
                  widget.onDelete();
                }
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey.shade300,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(widget.deleteButtonText ?? ref.tr('final_delete')),
        ),
      ],
    );
  }
}
