import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dashboard_screen.dart';
import '../../patients/presentation/patients_list_screen.dart';
import '../../accounts/presentation/accounts_screen.dart';
import '../../appointments/presentation/patient_reminders_screen.dart';
import '../../profile/presentation/account_screen.dart';
import '../../../core/localization/language_provider.dart';

class MobileScaffold extends ConsumerStatefulWidget {
  const MobileScaffold({super.key});

  @override
  ConsumerState<MobileScaffold> createState() => _MobileScaffoldState();
}

class _MobileScaffoldState extends ConsumerState<MobileScaffold> {
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
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        type: BottomNavigationBarType.fixed, // Ensure all items are visible
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: ref.tr('nav_home'),
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.people),
            label: ref.tr('nav_patients'),
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet),
            label: ref.tr('nav_accounts'),
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications),
            label: ref.tr('nav_reminders'),
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: ref.tr('nav_profile'),
          ),
        ],
      ),
    );
  }
}
