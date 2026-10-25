import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../data/demo/demo_repository.dart';
import '../../data/providers.dart';
import '../../data/repositories/repository.dart';
import 'auth_form_scaffold.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() => _run(() async {
    await ref
        .read(repositoryProvider)
        .signIn(email: _email.text, password: _password.text);
  });

  Future<void> _demo() => _run(() async {
    await ref
        .read(repositoryProvider)
        .signIn(
          email: DemoRepository.demoAccountByRole.values.first,
          password: demoPassword,
        );
  });

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthFormScaffold(
      title: 'Iniciar sesión',
      children: [
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(labelText: 'Correo'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _password,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          onSubmitted: (_) => _signIn(),
          decoration: const InputDecoration(labelText: 'Contraseña'),
        ),
        const SizedBox(height: 20),
        if (_error != null) FormErrorText(_error!),
        FilledButton(
          onPressed: _busy ? null : _signIn,
          child: Text(_busy ? 'Entrando…' : 'Entrar'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _busy ? null : _demo,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
          ),
          child: const Text('Probar demo'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : () => context.push(Routes.register),
          child: const Text('Crear cuenta'),
        ),
      ],
    );
  }
}
