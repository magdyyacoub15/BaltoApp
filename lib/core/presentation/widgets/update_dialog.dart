import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ota_update/ota_update.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/update_service.dart';
import '../../localization/language_provider.dart';

class UpdateDialog extends ConsumerStatefulWidget {
  final UpdateInfo info;
  const UpdateDialog({super.key, required this.info});

  @override
  ConsumerState<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends ConsumerState<UpdateDialog> {
  double _progress = 0;
  bool _isDownloading = false;
  String _status = '';

  void _startUpdate() async {
    // Ensure permission to install from unknown sources is granted.
    const status = Permission.requestInstallPackages;
    if (await status.isDenied) {
      await status.request();
    }

    // Re-check after request.
    if (await status.isDenied) {
       if (mounted) {
         setState(() {
           _status = 'Permission denied to install update.';
         });
       }
       return;
    }

    setState(() {
      _isDownloading = true;
      _status = ref.tr('downloading_update');
    });

    debugPrint('OTA START: URL: ${widget.info.apkUrl}');
    ref.read(updateServiceProvider).executeUpdate(widget.info.apkUrl).listen(
      (OtaEvent event) {
        debugPrint('OTA EVENT: status=${event.status}, value=${event.value}');
        setState(() {
          if (event.status == OtaStatus.DOWNLOADING) {
            _status = '${ref.tr('downloading_update')}... ${event.value}%';
            _progress = double.tryParse(event.value ?? '0') ?? 0;
          } else if (event.status == OtaStatus.INSTALLING) {
            _status = ref.tr('installing_update');
            debugPrint('OTA SUCCESS: INSTALLING triggered.');
            // Save the update code ONLY when we are sure the install is starting.
            ref.read(updateServiceProvider).saveLocalUpdateCode(widget.info.updateCode);
          } else {
            _status = event.status.name;
          }
        });
      },
      onError: (e) {
        debugPrint('OTA ERROR: $e');
        setState(() {
          _isDownloading = false;
          _status = '${ref.tr('update_error_label')}: $e';
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.system_update, color: Colors.blue),
            const SizedBox(width: 10),
            Text(ref.tr('update_available_title')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ref.tr('update_available_message')),
            const SizedBox(height: 10),
            if (widget.info.changelog.isNotEmpty) ...[
              Text(
                ref.tr('what_is_new'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 5),
              Text(widget.info.changelog),
            ],
            if (_isDownloading) ...[
              const SizedBox(height: 20),
              LinearProgressIndicator(
                value: _progress / 100,
                backgroundColor: Colors.grey.shade200,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
              const SizedBox(height: 10),
              Center(child: Text('$_progress%')),
              const SizedBox(height: 5),
              Center(
                child: Text(
                  _status,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (!_isDownloading)
            ElevatedButton(
              onPressed: _startUpdate,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(ref.tr('update_now_button')),
            ),
          if (_status == 'Permission denied to install update.')
            TextButton(
              onPressed: () => openAppSettings(),
              child: const Text('Open Settings'),
            ),
        ],
      ),
    );
  }
}
