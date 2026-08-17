import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import 'main_shell.dart';

/// Branded launch screen: the Listit wordmark over "Simple. Safe. Secure.",
/// on the brand navy. It slides + fades in, holds, then slides out as the app
/// itself fades in underneath.
class SplashScreen extends StatefulWidget {
  final ApiService api;
  final AuthService auth;
  const SplashScreen({super.key, required this.api, required this.auth});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _in = false; // content has slid in
  bool _out = false; // content is sliding out

  // Held so they can be cancelled on dispose rather than left to fire into a
  // torn-down tree.
  Timer? _slideOut;
  Timer? _handOver;

  @override
  void initState() {
    super.initState();
    // Slide in on the first frame, hold, then slide out and hand over.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _in = true);
    });
    _slideOut = Timer(const Duration(milliseconds: 1900), () {
      if (mounted) setState(() => _out = true);
    });
    _handOver = Timer(const Duration(milliseconds: 2350), _goHome);
  }

  @override
  void dispose() {
    _slideOut?.cancel();
    _handOver?.cancel();
    super.dispose();
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (_, _, _) => MainShell(api: widget.api, auth: widget.auth),
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final offset = _out
        ? const Offset(0, -0.22)
        : (_in ? Offset.zero : const Offset(0, 0.22));
    final opacity = (_in && !_out) ? 1.0 : 0.0;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0E2A3F), AppColors.ink],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: AnimatedSlide(
              offset: offset,
              duration: const Duration(milliseconds: 520),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: opacity,
                duration: const Duration(milliseconds: 520),
                curve: Curves.easeOut,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/listit_logo.png',
                      height: 58,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      color: Colors.white,
                      colorBlendMode: BlendMode.srcIn,
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Simple. Safe. Secure.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
