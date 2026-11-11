import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/models/sitter_case.dart';
import '../data/providers.dart';
import '../data/repositories/repository.dart';

/// Abre un enlace (videollamada, documento) en una pestaña nueva.
Future<void> openExternal(BuildContext context, Uri uri) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = await launchUrl(
    uri,
    mode: LaunchMode.externalApplication,
    webOnlyWindowName: '_blank',
  );
  if (!ok) {
    messenger.showSnackBar(
      const SnackBar(content: Text('No pudimos abrir el enlace.')),
    );
  }
}

/// Muestra un certificado. Con Supabase abre un enlace temporal; en la demo
/// (archivo en memoria) previsualiza las imágenes aquí mismo.
Future<void> openSitterDocument(
  BuildContext context,
  WidgetRef ref,
  SitterDocument doc,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final uri = await ref.read(repositoryProvider).documentUrl(doc);
    if (!context.mounted) return;
    if (uri.scheme != 'data') return await openExternal(context, uri);
    if (!doc.isImage) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'En el modo demo solo se pueden previsualizar imágenes.',
          ),
        ),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(doc.fileName),
        content: Image.memory(uri.data!.contentAsBytes(), fit: BoxFit.contain),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  } on ValidationFailure catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// "1,2 MB" / "350 KB".
String formatFileSize(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB';
  }
  return '${(bytes / 1024).ceil()} KB';
}
