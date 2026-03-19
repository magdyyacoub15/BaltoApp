import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError();
});

class AppScaleNotifier extends Notifier<double> {
  static const String _scaleKey = 'app_scale_key';

  @override
  double build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getDouble(_scaleKey) ?? 1.0;
  }

  Future<void> setScale(double scale) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setDouble(_scaleKey, scale);
    state = scale;
  }
}

final appScaleProvider = NotifierProvider<AppScaleNotifier, double>(() {
  return AppScaleNotifier();
});
