import 'package:flutter/material.dart';

import '../../shared/widgets/doggo_logo.dart';

/// Pantalla provisional: el login real llega en la fase 2.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DoggoLogo(size: 140),
              const SizedBox(height: 16),
              Text(
                'Iniciar sesión',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
