import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';

import '../../data/models/profile.dart';
import '../../data/providers.dart';
import '../../data/repositories/repository.dart';
import 'auth_form_scaffold.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  UserRole _role = UserRole.owner;
  bool _accepted = false;
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(repositoryProvider)
          .signUp(
            email: _email.text,
            password: _password.text,
            fullName: _name.text,
            role: _role,
            acceptedTerms: _accepted,
          );
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthFormScaffold(
      title: 'Crear cuenta',
      showBack: true,
      children: [
        SegmentedButton<UserRole>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: UserRole.owner, label: Text('Soy dueño')),
            ButtonSegment(value: UserRole.sitter, label: Text('Soy cuidador')),
          ],
          selected: {_role},
          onSelectionChanged: (s) => setState(() => _role = s.first),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Nombre completo'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Correo'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Contraseña'),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: _accepted,
          onChanged: (v) => setState(() => _accepted = v ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            'Soy mayor de 18 años y acepto los términos y la política de privacidad',
          ),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            TextButton(
              onPressed: () => context.push(Routes.terms),
              child: const Text('Ver términos'),
            ),
            TextButton(
              onPressed: () => context.push(Routes.privacy),
              child: const Text('Ver política de privacidad'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_error != null) FormErrorText(_error!),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Creando…' : 'Crear cuenta'),
        ),
      ],
    );
  }
}
