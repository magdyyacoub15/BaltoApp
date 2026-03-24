import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/settings_provider.dart';
import 'core/localization/language_provider.dart';
import 'core/services/hive_cache_service.dart';
import 'core/services/sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initHive(); // initialises all Hive boxes including offline_queue
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const ClinicApp(),
    ),
  );
}

class ClinicApp extends ConsumerStatefulWidget {
  const ClinicApp({super.key});

  @override
  ConsumerState<ClinicApp> createState() => _ClinicAppState();
}

class _ClinicAppState extends ConsumerState<ClinicApp> {
  @override
  void initState() {
    super.initState();
    // Start the background sync listener as soon as the widget tree is ready.
    // Uses addPostFrameCallback so that all providers are initialised first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncServiceProvider).startListening();
    });
  }

  @override
  Widget build(BuildContext context) {
    final router   = ref.watch(routerProvider);
    final appScale = ref.watch(appScaleProvider);
    final locale   = ref.watch(languageProvider);

    return MaterialApp.router(
      title: 'BaltoPro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,

      // Routing
      routerConfig: router,

      // Localization
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ar', 'SA'), Locale('en', 'US')],
      locale: locale,
      builder: (context, child) {
        final mediaQueryData = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQueryData.copyWith(
            textScaler: TextScaler.linear(appScale),
          ),
          child: IconTheme(
            data: IconTheme.of(context).copyWith(size: 22.0 * appScale),
            child: Directionality(
              textDirection: locale.languageCode == 'ar'
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: child!,
            ),
          ),
        );
      },
    );
  }
}
