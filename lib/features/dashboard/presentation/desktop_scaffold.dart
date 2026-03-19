import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dashboard_screen.dart';
import '../../patients/presentation/patients_list_screen.dart';
import '../../accounts/presentation/accounts_screen.dart';
import '../../appointments/presentation/patient_reminders_screen.dart';
import '../../auth/data/auth_repository.dart';
import '../../profile/presentation/account_screen.dart';
import '../../../core/localization/language_provider.dart';

class DesktopScaffold extends ConsumerStatefulWidget {
  const DesktopScaffold({super.key});

  @override
  ConsumerState<DesktopScaffold> createState() => _DesktopScaffoldState();
}

class _DesktopScaffoldState extends ConsumerState<DesktopScaffold> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    DashboardScreen(),
    const PatientsListScreen(),
    const AccountsScreen(),
    const PatientRemindersScreen(),
    const AccountScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          Drawer(
            elevation: 1,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                DrawerHeader(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  child: Center(
                    child: Text(
                      ref.tr('smart_clinic'),
                      style: const TextStyle(color: Colors.white, fontSize: 24),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.dashboard),
                  title: Text(ref.tr('dashboard_title')),
                  selected: _selectedIndex == 0,
                  onTap: () {
                    setState(() {
                      _selectedIndex = 0;
                    });
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.people),
                  title: Text(ref.tr('patients_record')),
                  selected: _selectedIndex == 1,
                  onTap: () {
                    setState(() {
                      _selectedIndex = 1;
                    });
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet),
                  title: Text(ref.tr('accounts_and_finances')),
                  selected: _selectedIndex == 2,
                  onTap: () {
                    setState(() {
                      _selectedIndex = 2;
                    });
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.notifications),
                  title: Text(ref.tr('nav_reminders')),
                  selected: _selectedIndex == 3,
                  onTap: () {
                    setState(() {
                      _selectedIndex = 3;
                    });
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.person),
                  title: Text(ref.tr('nav_profile')),
                  selected: _selectedIndex == 4,
                  onTap: () {
                    setState(() {
                      _selectedIndex = 4;
                    });
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: Text(
                    ref.tr('logout'),
                    style: const TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    ref.read(authRepositoryProvider).logOut();
                  },
                ),
              ],
            ),
          ),
          // Main Content
          Expanded(child: _screens[_selectedIndex]),
        ],
      ),
    );
  }
}
