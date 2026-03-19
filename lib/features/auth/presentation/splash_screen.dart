import 'package:flutter/material.dart';
import '../../../core/presentation/widgets/animated_gradient_background.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: AnimatedGradientBackground(
        child: Center(child: CircularProgressIndicator(color: Colors.white)),
      ),
    );
  }
}
