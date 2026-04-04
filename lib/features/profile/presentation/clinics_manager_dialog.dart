import 'package:flutter/material.dart';
import '../../auth/data/auth_repository.dart';
import '../../../core/localization/app_translations.dart';

/// Dialog for managing multi-clinic memberships.
/// Shows: current clinics list, join by code, create new clinic.
class ClinicsManagerDialog extends StatefulWidget {
  final String userId;
  final String activeClinicId;
  final AuthRepository authRepo;
  final String userEmail;

  const ClinicsManagerDialog({
    super.key,
    required this.userId,
    required this.activeClinicId,
    required this.authRepo,
    this.userEmail = '',
  });

  @override
  State<ClinicsManagerDialog> createState() => _ClinicsManagerDialogState();
}

class _ClinicsManagerDialogState extends State<ClinicsManagerDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _isLoading = true;
  bool _isSwitching = false;
  bool _isActing = false;
  List<dynamic> _memberships = [];
  String _activeClinicId = '';

  final TextEditingController _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _activeClinicId = widget.activeClinicId;
    _loadMemberships();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadMemberships() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch all memberships first
      final list = await widget.authRepo.getUserMemberships(widget.userId);

      // 2. Self-healing (manger3 approach): check client-side if active clinic
      //    is missing from the fetched list, no extra DB query needed
      if (widget.activeClinicId.isNotEmpty) {
        final alreadyPresent = list.any(
          (m) => m.clinicId == widget.activeClinicId,
        );
        if (!alreadyPresent) {
          debugPrint(
            'Self-healing: active clinic ${widget.activeClinicId} missing — creating membership...',
          );
          try {
            await widget.authRepo.ensureAdminMembership(
              widget.userId,
              widget.activeClinicId,
            );
          } catch (e) {
            debugPrint('Self-healing failed (non-fatal): $e');
          }
          // Reload recursively (same as manger3: return _loadMemberships())
          if (mounted) setState(() => _isLoading = false);
          return _loadMemberships();
        }
      }

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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
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
    setState(() => _isActing = true);
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
        setState(() => _isActing = false);
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

  void _confirmSwitch(String clinicId) {
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
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.corporate_fare, color: Colors.white, size: 26),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _tr('my_groups'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: () => Navigator.of(context).pop(),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TabBar(
                      controller: _tabController,
                      indicatorColor: Colors.white,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white54,
                      indicatorWeight: 3,
                      tabs: [
                        Tab(
                          icon: const Icon(Icons.list_alt_rounded, size: 18),
                          text: _tr('my_groups'),
                        ),
                        Tab(
                          icon: const Icon(Icons.link_rounded, size: 18),
                          text: _tr('join_btn'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Tab content
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.5,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildMyClinicsList(),
                    _buildJoinTab(),
                  ],
                ),
              ),
            ],
          ),

          // Switching overlay
          if (_isSwitching)
            Positioned.fill(
              child: Container(
                color: Colors.white.withAlpha(220),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(
                        _tr('switching_clinic_msg'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMyClinicsList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_memberships.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.home_work_outlined, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              _tr('unnamed_clinic'),
              style: TextStyle(color: Colors.grey.shade400),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _memberships.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
      itemBuilder: (context, index) {
        final m = _memberships[index];
        final gid = m.clinicId as String;
        final mid = m.id as String;
        final name = (m.clinicName as String).isNotEmpty
            ? m.clinicName as String
            : _tr('unnamed_clinic');
        final isPending = m.isPending as bool;
        final isActive = _activeClinicId == gid;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: CircleAvatar(
            radius: 20,
            backgroundColor: isPending
                ? Colors.orange.shade50
                : isActive
                    ? Colors.green.shade50
                    : Colors.blue.shade50,
            child: Icon(
              isPending
                  ? Icons.hourglass_top_rounded
                  : isActive
                      ? Icons.check_circle_rounded
                      : Icons.corporate_fare_rounded,
              size: 20,
              color: isPending
                  ? Colors.orange
                  : isActive
                      ? Colors.green
                      : Colors.blue,
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isActive ? Colors.green.shade700 : null,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              if (isPending)
                _buildBadge(_tr('pending_status'), Colors.orange)
              else if (isActive)
                _buildBadge(_tr('active_clinic'), Colors.green),
            ],
          ),
          subtitle: Text(
            isPending ? _tr('group_pending_admin_approval') : '',
            style: const TextStyle(fontSize: 10, color: Colors.grey),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: SizedBox(
            width: isActive ? 44 : (isPending ? 44 : 110),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!isActive && !isPending)
                  Flexible(
                    child: TextButton(
                      onPressed: () => _confirmSwitch(gid),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.blue,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      child: Text(
                        _tr('switch_clinic'),
                        style: const TextStyle(fontSize: 11),
                        maxLines: 1,
                      ),
                    ),
                  ),
                if (!isActive)
                  IconButton(
                    icon: const Icon(Icons.exit_to_app_rounded, color: Colors.red, size: 18),
                    tooltip: _tr('leave_group'),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _confirmLeave(mid, name),
                  )
                else
                  IconButton(
                    icon: Icon(Icons.exit_to_app_rounded, color: Colors.grey.shade300, size: 18),
                    tooltip: _tr('cannot_leave_active_clinic'),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(_tr('cannot_leave_active_clinic'))),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildJoinTab() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.link_rounded, size: 48, color: Colors.blue.shade300),
          const SizedBox(height: 12),
          Text(
            _tr('join_new_clinic'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            _tr('join_code_hint'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _codeController,
            textCapitalization: TextCapitalization.characters,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
            ),
            decoration: InputDecoration(
              hintText: 'XXXXXX',
              hintStyle: const TextStyle(letterSpacing: 4, color: Colors.grey),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            maxLength: 10,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _isActing ? null : _joinNew,
            icon: _isActing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.login_rounded),
            label: Text(_tr('join_btn')),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

}
