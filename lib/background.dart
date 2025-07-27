import 'package:flutter/material.dart';

class Background extends StatelessWidget {
  final Widget child;
  final double dimOpacity;

  const Background({
    super.key,
    required this.child,
    this.dimOpacity = 0.4,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Background image
        Positioned.fill(
          child: Image.asset(
            'assets/bg.jpg',
            fit: BoxFit.cover,
          ),
        ),

        // Dimming overlay
        Positioned.fill(
          child: Container(
            color: Colors.black12,
          ),
        ),

        // Foreground content
        Positioned.fill(
          child: child,
        ),
      ],
    );
  }
}
