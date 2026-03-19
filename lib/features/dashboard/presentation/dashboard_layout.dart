import 'package:flutter/material.dart';
import 'responsive_layout.dart';
import 'mobile_scaffold.dart';
import 'desktop_scaffold.dart';

class DashboardLayout extends StatelessWidget {
  const DashboardLayout({super.key});

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      mobileScaffold: MobileScaffold(),
      desktopScaffold: DesktopScaffold(),
    );
  }
}
