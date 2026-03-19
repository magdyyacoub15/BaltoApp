import 'package:flutter/material.dart';

class ScaledIcon extends StatelessWidget {
  final IconData? icon;
  final double size;
  final Color? color;

  const ScaledIcon(this.icon, {super.key, required this.size, this.color});

  @override
  Widget build(BuildContext context) {
    return Icon(
      icon,
      size: MediaQuery.textScalerOf(context).scale(size),
      color: color,
    );
  }
}
