import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dashboard_screen.dart';
import '../../patients/presentation/patients_list_screen.dart';
import '../../accounts/presentation/accounts_screen.dart';
import '../../appointments/presentation/patient_reminders_screen.dart';
import '../../profile/presentation/account_screen.dart';
import '../../../core/localization/language_provider.dart';
import '../../auth/presentation/auth_providers.dart';

class MobileScaffold extends ConsumerStatefulWidget {
  const MobileScaffold({super.key});

  @override
  ConsumerState<MobileScaffold> createState() => _MobileScaffoldState();
}

class _MobileScaffoldState extends ConsumerState<MobileScaffold> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider).value;

    final bool canViewPatients = user?.isAdmin == true || (user?.canViewPatients ?? true);
    final bool canViewAccounts = user?.isAdmin == true || (user?.canViewAccounts ?? true);

    final List<Widget> screens = [
      DashboardScreen(),
      if (canViewPatients) const PatientsListScreen(),
      if (canViewAccounts) const AccountsScreen(),
      const PatientRemindersScreen(),
      const AccountScreen(),
    ];

    final List<BottomNavigationBarItem> navItems = [
      BottomNavigationBarItem(
        icon: const Icon(Icons.dashboard),
        label: ref.tr('nav_home'),
      ),
      if (canViewPatients)
        BottomNavigationBarItem(
          icon: const Icon(Icons.people),
          label: ref.tr('nav_patients'),
        ),
      if (canViewAccounts)
        BottomNavigationBarItem(
          icon: const Icon(Icons.account_balance_wallet),
          label: ref.tr('nav_accounts'),
        ),
      BottomNavigationBarItem(
        icon: const Icon(Icons.notifications),
        label: ref.tr('nav_reminders'),
      ),
      BottomNavigationBarItem(
        icon: const Icon(Icons.person),
        label: ref.tr('nav_profile'),
      ),
    ];

    // Ensure _selectedIndex is valid if the number of tabs change dynamically
    int safeIndex = _selectedIndex;
    if (safeIndex >= screens.length) {
      safeIndex = 0;
    }

    return Scaffold(
      body: screens[safeIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: safeIndex,
        type: BottomNavigationBarType.fixed, // Ensure all items are visible
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: navItems,
      ),
    );
  }
}

