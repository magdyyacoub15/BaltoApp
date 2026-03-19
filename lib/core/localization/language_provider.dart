import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';
import 'app_translations.dart';

final languageProvider = NotifierProvider<LanguageNotifier, Locale>(() {
  return LanguageNotifier();
});

class LanguageNotifier extends Notifier<Locale> {
  static const String _langKey = 'app_language_key';

  @override
  Locale build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final langCode = prefs.getString(_langKey) ?? 'ar';
    return Locale(langCode);
  }

  Future<void> setLanguage(String langCode) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_langKey, langCode);
    state = Locale(langCode);
  }

  bool get isArabic => state.languageCode == 'ar';
}

extension AppLocalization on WidgetRef {
  String tr(String key, [List<dynamic>? args]) {
    final locale = watch(languageProvider);
    final translations =
        AppTranslations.translations[locale.languageCode] ??
        AppTranslations.translations['ar']!;
    String value = translations[key] ?? key;
    if (args != null && args.isNotEmpty) {
      for (final arg in args) {
        value = value.replaceFirst('{}', arg.toString());
      }
    }
    return value;
  }
}

extension BuildContextLocalization on BuildContext {
  String tr(WidgetRef ref, String key, [List<dynamic>? args]) {
    final locale = ref.watch(languageProvider);
    final translations =
        AppTranslations.translations[locale.languageCode] ??
        AppTranslations.translations['ar']!;
    String value = translations[key] ?? key;
    if (args != null && args.isNotEmpty) {
      for (final arg in args) {
        value = value.replaceFirst('{}', arg.toString());
      }
    }
    return value;
  }
}
