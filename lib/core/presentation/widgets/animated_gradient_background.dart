import 'package:flutter/material.dart';
import 'dart:math';

class AnimatedGradientBackground extends StatefulWidget {
  final Widget child;

  const AnimatedGradientBackground({super.key, required this.child});

  @override
  State<AnimatedGradientBackground> createState() =>
      _AnimatedGradientBackgroundState();
}

class _AnimatedGradientBackgroundState extends State<AnimatedGradientBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _animationController.repeat();
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
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
    return Stack(
      children: [
        Container(
          height: double.infinity,
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0D47A1), Color(0xFF1976D2), Color(0xFF42A5F5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return Stack(
                children: [
                  _buildAnimatedBlob(
                    top: -50,
                    left: -50,
                    offset: Offset(
                      sin(_animationController.value * 2 * pi) * 60,
                      cos(_animationController.value * 2 * pi) * 40,
                    ),
                    color: Colors.white.withAlpha(25), // approx 0.1
                    size: 300,
                  ),
                  _buildAnimatedBlob(
                    top: 300,
                    left: 150,
                    offset: Offset(
                      cos(_animationController.value * 2 * pi) * 70,
                      sin(_animationController.value * 2 * pi) * 50,
                    ),
                    color: Colors.white.withAlpha(18), // approx 0.07
                    size: 250,
                  ),
                  _buildAnimatedBlob(
                    top: 600,
                    left: -30,
                    offset: Offset(
                      sin(_animationController.value * 2 * pi) * 40,
                      -cos(_animationController.value * 2 * pi) * 60,
                    ),
                    color: Colors.white.withAlpha(13), // approx 0.05
                    size: 200,
                  ),
                ],
              );
            },
          ),
        ),
        Positioned.fill(child: widget.child),
      ],
    );
  }
}
