import 'package:ota_update/ota_update.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'appwrite_client.dart';

class UpdateInfo {
  final int updateCode;
  final String apkUrl;
  final String changelog;

  UpdateInfo({
    required this.updateCode,
    required this.apkUrl,
    required this.changelog,
  });

  factory UpdateInfo.fromMap(Map<String, dynamic> map) {
    return UpdateInfo(
      updateCode: map['updateCode'] ?? 0,
      apkUrl: map['apkUrl'] ?? '',
      changelog: map['changelog'] ?? '',
    );
  }
}

final updateServiceProvider = Provider((ref) => UpdateService(ref));

class UpdateService {
  final Ref _ref;
  UpdateService(this._ref);

  static const String _kLocalUpdateCode = 'local_update_code';
  static const String _kLastShownChangelog = 'last_shown_changelog_code';

  Future<UpdateInfo?> getUpdateInfo() async {
    final databases = _ref.read(appwriteTablesDBProvider);
    try {
      final doc = await databases.getRow(
        databaseId: appwriteDatabaseId,
        tableId: 'config',
        rowId: 'update_info',
      );
      return UpdateInfo.fromMap(doc.data);
    } catch (e) {
      return null;
    }
  }

  Future<int> getLocalUpdateCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kLocalUpdateCode) ?? 0;
  }

  Future<void> saveLocalUpdateCode(int code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLocalUpdateCode, code);
  }

  Future<bool> isUpdateRequired(UpdateInfo info) async {
    final localCode = await getLocalUpdateCode();
    return info.updateCode > localCode;
  }

  Stream<OtaEvent> executeUpdate(String url) {
    return OtaUpdate().execute(url, destinationFilename: 'baltopro_update.apk');
  }

  Future<void> markChangelogAsShown(int code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastShownChangelog, code);
  }

  Future<bool> shouldShowChangelog(int code) async {
    final prefs = await SharedPreferences.getInstance();
    final lastShown = prefs.getInt(_kLastShownChangelog);
    // Show if we are on this version but haven't shown changelog for it yet
    return lastShown != code;
  }
}

class UpdateCheckedNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  @override
  set state(bool value) => super.state = value;
}

final isUpdateCheckedProvider = NotifierProvider<UpdateCheckedNotifier, bool>(
  UpdateCheckedNotifier.new,
);
