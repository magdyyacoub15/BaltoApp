import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/update_service.dart';
import '../../localization/language_provider.dart';

class ChangelogDialog extends ConsumerWidget {
  final int updateCode;
  final String changelog;
  
  const ChangelogDialog({
    super.key, 
    required this.updateCode, 
    required this.changelog,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.auto_awesome, color: Colors.amber),
          const SizedBox(width: 10),
          Text(ref.tr('whats_new_title', ['#$updateCode'])),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ref.tr('whats_new_message'),
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 15),
            Text(changelog),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            ref.read(updateServiceProvider).markChangelogAsShown(updateCode);
            Navigator.pop(context);
          },
          child: Text(ref.tr('got_it_button')),
        ),
      ],
    );
  }
}
