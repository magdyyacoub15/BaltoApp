import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/presentation/widgets/animated_gradient_background.dart';
import '../../../core/presentation/widgets/update_dialog.dart';
import '../../../core/presentation/widgets/changelog_dialog.dart';
import '../../../core/services/update_service.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    _checkUpdates();
  }

  Future<void> _checkUpdates() async {
    final updateService = ref.read(updateServiceProvider);
    
    // 1. Fetch update info from Appwrite with a timeout
    final updateInfo = await updateService.getUpdateInfo().timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        debugPrint('⚠️ [SplashScreen] Update check timed out');
        return null; // Skip update if it takes too long
      },
    );
    
    if (updateInfo != null) {
      // 2. Check if update is required based on numeric code
      final isRequired = await updateService.isUpdateRequired(updateInfo);
      
      if (isRequired && mounted) {
        // Show mandatory update dialog
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => UpdateDialog(info: updateInfo),
        );
        // After dialog is closed (e.g. if we allowed cancellation, but we didn't)
        // If they updated, the app would have restarted.
        return; 
      }

      // 3. If no update required, check if we should show changelog
      // We show it if serverCode == localCode (we are up to date)
      // but we haven't shown the changelog for this specific code yet.
      final localCode = await updateService.getLocalUpdateCode();
      final shouldShow = await updateService.shouldShowChangelog(localCode);
      
      if (shouldShow && localCode > 0 && mounted) {
        await showDialog(
          context: context,
          builder: (context) => ChangelogDialog(
            updateCode: localCode, 
            changelog: updateInfo.changelog,
          ),
        );
      }
    }

    if (mounted) {
      ref.read(isUpdateCheckedProvider.notifier).state = true;
      setState(() {
        _isChecking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedGradientBackground(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
               const CircularProgressIndicator(color: Colors.white),
               if (_isChecking) ...[
                 const SizedBox(height: 20),
                 const Text(
                   'Checking for updates...',
                   style: TextStyle(color: Colors.white70),
                 ),
               ],
            ],
          ),
        ),
      ),
    );
  }
}
