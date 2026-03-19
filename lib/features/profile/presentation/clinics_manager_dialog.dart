import 'package:flutter/material.dart';
import '../../auth/data/auth_repository.dart';
import '../../../core/localization/app_translations.dart';

/// Dialog for managing multi-clinic memberships.
/// Mirrors the _GroupsManagerDialog from manger3, adapted for Firebase/Riverpod.
class ClinicsManagerDialog extends StatefulWidget {
  final String userId;
  final String activeClinicId;
  final AuthRepository authRepo;

  const ClinicsManagerDialog({
    super.key,
    required this.userId,
    required this.activeClinicId,
    required this.authRepo,
  });

  @override
  State<ClinicsManagerDialog> createState() => _ClinicsManagerDialogState();
}

class _ClinicsManagerDialogState extends State<ClinicsManagerDialog> {
  bool _isLoading = true;
  bool _isSwitching = false;
  List<dynamic> _memberships = [];
  String _activeClinicId = '';
  final TextEditingController _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _activeClinicId = widget.activeClinicId;
    _loadMemberships();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadMemberships() async {
    setState(() => _isLoading = true);
    try {
      // 1. Self-healing: Ensure primary clinic has a membership
      await widget.authRepo.selfHealMembership(
        widget.userId,
        widget.activeClinicId,
      );

      // 2. Load all memberships
      final list = await widget.authRepo.getUserMemberships(widget.userId);
      if (mounted) setState(() => _memberships = list);
    } catch (e) {
      debugPrint('Error loading memberships: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _switchClinic(String clinicId) async {
    setState(() => _isSwitching = true);
    try {
      await widget.authRepo.switchClinic(widget.userId, clinicId);
      if (mounted) {
        setState(() => _activeClinicId = clinicId);
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_tr('switch_clinic')),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      final key = e.toString().replaceFirst('Exception: ', '');
      final msg = _tryTr(key) ?? _tr('switch_error', e.toString());
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
        setState(() => _isSwitching = false);
      }
    }
  }

  Future<void> _leaveMembership(String membershipId) async {
    setState(() => _isLoading = true);
    try {
      await widget.authRepo.leaveMembership(membershipId);
      await _loadMemberships();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_tr('leave_error', e.toString()))),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _joinNew() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      await widget.authRepo.joinClinicByCode(widget.userId, code);
      _codeController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_tr('join_request_sent')),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      final key = e.toString().replaceFirst('Exception: ', '');
      final msg = _tryTr(key) ?? key;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
        setState(() => _isLoading = false);
      }
    }
  }

  void _confirmLeave(String membershipId, String clinicName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_tr('leave_group_confirm_title')),
        content: Text(_tr('leave_group_confirm_msg')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_tr('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _leaveMembership(membershipId);
            },
            child: Text(_tr('leave_group_btn')),
          ),
        ],
      ),
    );
  }

  void _confirmSwitchWithPendingOps(String clinicId) {
    // Mirroring manger3's behavior with a sync warning dialog
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            const SizedBox(width: 8),
            Text(_tr('pending_sync_warning')),
          ],
        ),
        content: Text(_tr('pending_sync_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_tr('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _switchClinic(clinicId);
            },
            child: Text(_tr('switch_anyway')),
          ),
        ],
      ),
    );
  }

  String _tr(String key, [String? arg]) {
    final locale = Localizations.localeOf(context).languageCode;
    final map =
        AppTranslations.translations[locale] ??
        AppTranslations.translations['ar']!;
    return map[key]?.replaceAll('{}', arg ?? '') ?? key;
  }

  String? _tryTr(String key) {
    final locale = Localizations.localeOf(context).languageCode;
    final map =
        AppTranslations.translations[locale] ??
        AppTranslations.translations['ar']!;
    return map[key];
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        _tr('my_groups'),
        textAlign: TextAlign.right,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      content: _isLoading
          ? SizedBox(
              height: 120,
              child: const Center(child: CircularProgressIndicator()),
            )
          : Stack(
              children: [
                SizedBox(
                  width: double.maxFinite,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.65,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Membership tiles
                          ..._memberships.map((m) {
                            final gid = m.clinicId as String;
                            final mid = m.id as String;
                            final name = (m.clinicName as String).isNotEmpty
                                ? m.clinicName as String
                                : _tr('unnamed_clinic');
                            final isPending = m.isPending as bool;
                            final isActive = _activeClinicId == gid;

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              leading: Icon(
                                isPending ? Icons.hourglass_top : Icons.church,
                                color: isPending
                                    ? Colors.orange
                                    : (isActive ? Colors.green : Colors.blue),
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                                tooltip: _tr('leave_group'),
                                onPressed: isActive
                                    ? () {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              _tr('cannot_leave_active_clinic'),
                                            ),
                                          ),
                                        );
                                      }
                                    : () => _confirmLeave(mid, name),
                              ),
                              title: Wrap(
                                alignment: WrapAlignment.end,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                textDirection: TextDirection.rtl,
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  Text(
                                    name,
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (isPending)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.shade100,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        _tr('pending_status'),
                                        style: TextStyle(
                                          color: Colors.orange.shade900,
                                          fontSize: 10,
                                        ),
                                      ),
                                    )
                                  else if (isActive)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade100,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        _tr('active_clinic'),
                                        style: TextStyle(
                                          color: Colors.green.shade900,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Text(
                                "ID: $gid",
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey,
                                ),
                              ),
                              onTap: isActive || isPending
                                  ? null
                                  : () => _confirmSwitchWithPendingOps(gid),
                            );
                          }),

                          const Divider(),
                          // Join new clinic section (Styled like manger3)
                          TextField(
                            controller: _codeController,
                            textCapitalization: TextCapitalization.characters,
                            textAlign: TextAlign.right,
                            decoration: InputDecoration(
                              hintText: _tr('join_code_hint'),
                              prefixIcon: const Icon(Icons.add),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Switching overlay
                if (_isSwitching)
                  Positioned.fill(
                    child: Container(
                      color: Colors.white.withAlpha(200),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 10),
                            Text(
                              _tr('switching_clinic_msg'),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: _isSwitching ? null : () => Navigator.of(context).pop(),
          child: Text(_tr('cancel')),
        ),
        ElevatedButton(
          onPressed: _isSwitching ? null : _joinNew,
          child: Text(_tr('join_btn')),
        ),
      ],
    );
  }
}
