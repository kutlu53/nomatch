import 'package:flutter/material.dart';
import 'dart:developer' as dev;

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  static const Duration _displayDuration = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    dev.log('SplashScreen: initState - loading logo');
    print('[SPLASH] Loading logo from assets - will display for ${_displayDuration.inSeconds}s');
    
    // ✅ NO auto-navigate here - let AppRouter handle transitions via AppPhase changes
    // The coordinator handles phase changes which will trigger router updates
  }

  @override
  Widget build(BuildContext context) {
    print('[SPLASH] 🎬 build() called - rendering SplashScreen');
    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(
        child: Container(
          color: Colors.black,
          child: Center(
            child: Image.asset(
              'assets/branding/logo_full_screen.png',
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                print('[SPLASH] ❌ PNG failed, trying WebP: $error');
                return Image.asset(
                  'assets/branding/logo_full_screen.webp',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    print('[SPLASH] ❌ WebP also failed: $error');
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'Loading...',
                            style: TextStyle(color: Colors.white, fontSize: 24),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            error.toString(),
                            style: const TextStyle(color: Colors.red, fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

