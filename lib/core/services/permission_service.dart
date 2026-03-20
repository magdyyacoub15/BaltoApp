import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'subscription_service.dart';

final permissionServiceProvider = Provider((ref) {
  final subscriptionService = ref.watch(subscriptionServiceProvider);
  return PermissionService(subscriptionService);
});

class PermissionService {
  final SubscriptionService _subscriptionService;

  PermissionService(this._subscriptionService);

  /// Centralized check for write permissions (enforces subscription)
  Future<bool> canWrite(String clinicId) async {
    final status = await _subscriptionService.checkSubscriptionStatus(clinicId);

    // Active, Trial, or Offline (trust cache for 48h as per service logic)
    return status == SubscriptionStatus.active ||
        status == SubscriptionStatus.trial ||
        status == SubscriptionStatus.offline;
  }
}
