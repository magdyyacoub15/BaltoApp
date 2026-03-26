// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:appwrite/appwrite.dart';
import '../../../core/services/appwrite_client.dart';
import '../../../core/services/subscription_service.dart';

import '../../../core/localization/language_provider.dart';
import '../../auth/presentation/auth_providers.dart';

class SubscriptionPage extends ConsumerStatefulWidget {
  const SubscriptionPage({super.key});

  @override
  ConsumerState<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends ConsumerState<SubscriptionPage>
    with SingleTickerProviderStateMixin {
  AnimationController? _animationController;

  SubscriptionStatus _status = SubscriptionStatus.trial;
  int _daysRemaining = 0;
  bool _isLoading = true;

  String _vodafoneNumber = "01061438566";
  String _instapayNumber = "01112800404";
  String _whatsappNumber = "+201112800404";

  // Dynamic Prices
  String _price1m = "75";
  String _price3m = "199";
  String _price6m = "349";
  String _price1y = "599";

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat();
    _loadStatus();
    _loadPrices();
  }

  @override
  void dispose() {
    _animationController?.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    final clinic = ref.read(clinicStreamProvider).value;
    if (clinic == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final subscriptionService = ref.read(subscriptionServiceProvider);
      final status = await subscriptionService.checkSubscriptionStatus(
        clinic.id,
      );
      final days = await subscriptionService.getDaysRemaining(clinic.id);

      if (mounted) {
        setState(() {
          _status = status;
          _daysRemaining = days;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error loading subscription status: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPrices() async {
    try {
      final databases = ref.read(appwriteTablesDBProvider);
      final doc = await databases.getRow(
        databaseId: appwriteDatabaseId,
        tableId: 'config',
        rowId: 'subscription_prices',
      );
      if (doc.data.isNotEmpty) {
        final data = doc.data;
        if (mounted) {
          setState(() {
            _price1m = data['price_1m']?.toString() ?? _price1m;
            _price3m = data['price_3m']?.toString() ?? _price3m;
            _price6m = data['price_6m']?.toString() ?? _price6m;
            _price1y = data['price_1y']?.toString() ?? _price1y;
            _vodafoneNumber =
                data['vodafone_number']?.toString() ?? _vodafoneNumber;
            _instapayNumber =
                data['instapay_number']?.toString() ?? _instapayNumber;
            _whatsappNumber =
                data['whatsapp_number']?.toString() ?? _whatsappNumber;
          });
        }
      }
    } on AppwriteException catch (e) {
      if (e.code == 404) {
        // It's ok if the config document doesn't exist yet
        debugPrint("Price config doc not found.");
      } else {
        debugPrint("Error loading prices from appwrite: $e");
      }
    } catch (e) {
      debugPrint("Error loading prices: $e");
    }
  }

  void _showPriceEditDialog() {
    final TextEditingController p1m = TextEditingController(text: _price1m);
    final TextEditingController p3m = TextEditingController(text: _price3m);
    final TextEditingController p6m = TextEditingController(text: _price6m);
    final TextEditingController p1y = TextEditingController(text: _price1y);
    final TextEditingController vCash =
        TextEditingController(text: _vodafoneNumber);
    final TextEditingController iPay =
        TextEditingController(text: _instapayNumber);
    final TextEditingController wApp =
        TextEditingController(text: _whatsappNumber);
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(ref.tr('edit_plan_prices'), textAlign: TextAlign.right),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildPriceField(p1m, ref.tr('price_1_month')),
                _buildPriceField(p3m, ref.tr('price_3_months')),
                _buildPriceField(p6m, ref.tr('price_6_months')),
                _buildPriceField(p1y, ref.tr('price_1_year')),
                const Divider(),
                _buildPriceField(vCash, ref.tr('vodafone_cash'), isPrice: false),
                _buildPriceField(iPay, ref.tr('instapay'), isPrice: false),
                _buildPriceField(wApp, ref.tr('whatsapp'), isPrice: false),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(ref.tr('cancel')),
            ),
            if (isSaving)
              const CircularProgressIndicator()
            else
              ElevatedButton(
                onPressed: () async {
                  setDialogState(() => isSaving = true);
                  final data = {
                    'price_1m': double.tryParse(p1m.text) ?? 0.0,
                    'price_3m': double.tryParse(p3m.text) ?? 0.0,
                    'price_6m': double.tryParse(p6m.text) ?? 0.0,
                    'price_1y': double.tryParse(p1y.text) ?? 0.0,
                    'vodafone_number': vCash.text,
                    'instapay_number': iPay.text,
                    'whatsapp_number': wApp.text,
                  };

                  try {
                    final databases = ref.read(appwriteTablesDBProvider);
                    try {
                      await databases.updateRow(
                        databaseId: appwriteDatabaseId,
                        tableId: 'config',
                        rowId: 'subscription_prices',
                        data: data,
                      );
                    } on AppwriteException catch (e) {
                      if (e.code == 404) {
                        await databases.createRow(
                          databaseId: appwriteDatabaseId,
                          tableId: 'config',
                          rowId: 'subscription_prices',
                          data: data,
                        );
                      } else {
                        rethrow;
                      }
                    }

                    if (context.mounted) {
                      setState(() {
                        _price1m = p1m.text;
                        _price3m = p3m.text;
                        _price6m = p6m.text;
                        _price1y = p1y.text;
                        _vodafoneNumber = vCash.text;
                        _instapayNumber = iPay.text;
                        _whatsappNumber = wApp.text;
                      });
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(ref.tr('prices_updated_success')),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      setDialogState(() => isSaving = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ref.tr('error_updating', [e.toString()]),
                          ),
                        ),
                      );
                    }
                  }
                },
                child: Text(ref.tr('save_changes')),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceField(TextEditingController controller, String label,
      {bool isPrice = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        textAlign: TextAlign.right,
        keyboardType: isPrice
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.phone,
        inputFormatters: [
          if (isPrice) FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        ],
        decoration: InputDecoration(
          labelText: label,
          hintText: isPrice ? ref.tr('enter_price') : label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  Future<void> _launchWhatsApp() async {
    final clinic = ref.read(clinicStreamProvider).value;
    final user = ref.read(currentUserProvider).value;

    final clinicInfo = clinic != null
        ? '${clinic.name} (${user?.email ?? ""})'
        : 'BaltoPro Clinic';

    final String msg = ref.tr('hello_subscribe_msg', [clinicInfo]);

    final Uri url = Uri.parse(
      "https://wa.me/$_whatsappNumber?text=${Uri.encodeComponent(msg)}",
    );
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ref.tr('cannot_open_whatsapp'))));
      }
    }
  }

  Future<void> _copyNumber(String number) async {
    await Clipboard.setData(ClipboardData(text: number));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(ref.tr('number_copied'))));
    }
  }

  Widget _buildPremiumBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0D47A1), Color(0xFF1976D2), Color(0xFF42A5F5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          if (_animationController != null)
            AnimatedBuilder(
              animation: _animationController!,
              builder: (context, child) {
                return Stack(
                  children: [
                    _buildAnimatedBlob(
                      top: -50,
                      left: -50,
                      offset: Offset(
                        sin(_animationController!.value * 2 * pi) * 60,
                        cos(_animationController!.value * 2 * pi) * 40,
                      ),
                      color: Colors.white.withAlpha(25),
                      size: 300,
                    ),
                    _buildAnimatedBlob(
                      top: 300,
                      left: 150,
                      offset: Offset(
                        cos(_animationController!.value * 2 * pi) * 70,
                        sin(_animationController!.value * 2 * pi) * 50,
                      ),
                      color: Colors.white.withAlpha(18),
                      size: 250,
                    ),
                    _buildAnimatedBlob(
                      top: 600,
                      left: -30,
                      offset: Offset(
                        sin(_animationController!.value * 2 * pi) * 40,
                        -cos(_animationController!.value * 2 * pi) * 60,
                      ),
                      color: Colors.white.withAlpha(13),
                      size: 200,
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildAnimatedBlob({
    double? top,
    double? left,
    required Offset offset,
    required Color color,
    required double size,
  }) {
    return Positioned(
      top: top,
      left: left,
      child: Transform.translate(
        offset: offset,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).value;

    return Scaffold(
      body: Stack(
        children: [
          _buildPremiumBackground(),
          _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverAppBar(
                      expandedHeight: 80,
                      floating: true,
                      pinned: false,
                      elevation: 0,
                      backgroundColor: Colors.transparent,
                      title: Text(
                        ref.tr('manage_subscription'),
                        style: const TextStyle(color: Colors.white),
                      ),
                      centerTitle: true,
                      iconTheme: const IconThemeData(color: Colors.white),
                      actions: [
                        if (user?.email == 'magdyyacoub41@gmail.com')
                          IconButton(
                            icon: const Icon(Icons.edit_calendar_rounded),
                            onPressed: _showPriceEditDialog,
                            tooltip: ref.tr('edit_plan_prices'),
                          ),
                      ],
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.all(20),
                      sliver: SliverList(
                        delegate: SliverChildListDelegate([
                          _buildStatusCard(),
                          const SizedBox(height: 20),
                          Center(
                            child: Text(
                              ref.tr('subscription_plans'),
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          _buildPlanCard(ref.tr('plan_1_month'), _price1m),
                          _buildPlanCard(ref.tr('plan_3_months'), _price3m),
                          _buildPlanCard(ref.tr('plan_6_months'), _price6m),
                          _buildPlanCard(ref.tr('plan_1_year'), _price1y),
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withAlpha(25),
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: Colors.white.withAlpha(50),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.info_outline,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    ref.tr('subscription_instructions'),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 30),
                          Center(
                            child: Text(
                              ref.tr('payment_methods'),
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          _buildPaymentMethod(
                            ref.tr('vodafone_cash'),
                            _vodafoneNumber,
                          ),
                          _buildPaymentMethod(
                            ref.tr('instapay'),
                            _instapayNumber,
                          ),
                          const SizedBox(height: 30),
                          ElevatedButton.icon(
                            onPressed: _launchWhatsApp,
                            icon: const Icon(Icons.chat),
                            label: Text(ref.tr('send_receipt_whatsapp')),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(16),
                              minimumSize: const Size(double.infinity, 50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                          ),
                          const SizedBox(height: 40),
                        ]),
                      ),
                    ),
                  ],
                ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    IconData icon;
    Color statusColor;
    String statusText;

    switch (_status) {
      case SubscriptionStatus.offline:
        statusColor = Colors.grey;
        icon = Icons.wifi_off;
        statusText = ref.tr('offline_grace_period');
        break;
      case SubscriptionStatus.active:
        statusColor = Colors.greenAccent;
        icon = Icons.check_circle;
        statusText = ref.tr('active');
        break;
      case SubscriptionStatus.trial:
        statusColor = Colors.lightBlueAccent;
        icon = Icons.access_time;
        statusText = ref.tr('trial_period');
        break;
      case SubscriptionStatus.expired:
        statusColor = Colors.redAccent;
        icon = Icons.cancel;
        statusText = ref.tr('expired');
        break;
    }

    return Card(
      color: Colors.white.withAlpha(25),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: Colors.white.withAlpha(50)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, color: statusColor, size: 40),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ref.tr('subscription_status', [statusText]),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (_status != SubscriptionStatus.expired)
                    Text(
                      ref.tr('days_remaining', [_daysRemaining.toString()]),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Colors.white70,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard(String duration, String price) {
    return Card(
      color: Colors.white.withAlpha(25),
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        title: Text(
          duration,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        trailing: Text(
          '$price ${ref.tr('currency')}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.amber,
          ),
        ),
        leading: const Icon(Icons.star, color: Colors.amber),
      ),
    );
  }

  Widget _buildPaymentMethod(String name, String number) {
    return Card(
      color: Colors.white.withAlpha(25),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        title: Text(name, style: const TextStyle(color: Colors.white70)),
        subtitle: Text(
          number,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.copy, color: Colors.white70),
          onPressed: () => _copyNumber(number),
        ),
      ),
    );
  }
}
