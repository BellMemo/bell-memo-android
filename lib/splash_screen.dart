import 'package:flutter/material.dart';
import 'dart:math' as math;

import 'pages/home_shell.dart';

class SplashScreen extends StatefulWidget {
  final Duration duration;

  const SplashScreen({
    super.key,
    this.duration = const Duration(milliseconds: 1200),
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      // 一个周期（左->右->回到左）用 sin 曲线完成；数值越小抖动越快
      duration: const Duration(milliseconds: 160),
      vsync: this,
    );

    _controller.repeat(reverse: true);
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      _controller.stop();
      _controller.reset();
    });

    Future.delayed(widget.duration, () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeShell()),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            // 中心点不动：通过“绕中心旋转”实现左右抖动（摇头）
            final angle = math.sin(_controller.value * 2 * math.pi) * 0.08;
            return Transform.rotate(angle: angle, child: child);
          },
          child: Image.asset(
            'assets/bell.png',
            width: 120,
            height: 120,
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                Icons.notifications,
                size: 120,
                color: Theme.of(context).colorScheme.primary,
              );
            },
          ),
        ),
      ),
    );
  }
}
