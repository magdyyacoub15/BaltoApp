import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const String appwriteEndpoint = 'https://fra.cloud.appwrite.io/v1';
const String appwriteProjectId = '69bd3ccd0017752f2a36';
const String appwriteDatabaseId = 'baltoDB';

final appwriteClientProvider = Provider<Client>((ref) {
  final client = Client();
  client
      .setEndpoint(appwriteEndpoint)
      .setProject(appwriteProjectId)
      .setSelfSigned(status: kDebugMode); // Only allow self-signed in debug mode
  return client;
});

final appwriteAccountProvider = Provider<Account>((ref) {
  return Account(ref.watch(appwriteClientProvider));
});

final appwriteDatabasesProvider = Provider<Databases>((ref) {
  return Databases(ref.watch(appwriteClientProvider));
});

final appwriteTablesDBProvider = Provider<TablesDB>((ref) {
  return TablesDB(ref.watch(appwriteClientProvider));
});

final appwriteTeamsProvider = Provider<Teams>((ref) {
  return Teams(ref.watch(appwriteClientProvider));
});
