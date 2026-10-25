import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/providers.dart';
import '../../data/repositories/repository.dart';
import '../bookings/bookings_providers.dart';
import '../map/sitter_list.dart';

/// Foto del cuidador con el botón para cambiarla (JPG, PNG o WEBP, ≤ 2 MB).
class SitterPhoto extends ConsumerStatefulWidget {
  const SitterPhoto({super.key});

  @override
  ConsumerState<SitterPhoto> createState() => _SitterPhotoState();
}

class _SitterPhotoState extends ConsumerState<SitterPhoto> {
  bool _busy = false;

  static String _mimeOf(XFile f) {
    final known = f.mimeType;
    if (known != null && known.isNotEmpty) return known;
    final name = f.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
    return 'application/octet-stream';
  }

  Future<void> _pick() async {
    final messenger = ScaffoldMessenger.of(context);
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 85,
    );
    if (file == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(repositoryProvider)
          .saveMyPhoto(await file.readAsBytes(), _mimeOf(file));
      ref.invalidate(mySitterProfileProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Foto actualizada')));
    } on ValidationFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sitter = ref.watch(mySitterProfileProvider).value;
    return Column(
      children: [
        if (sitter == null)
          const SizedBox(
            height: 88,
            child: Center(child: CircularProgressIndicator()),
          )
        else
          SitterAvatar(sitter: sitter, radius: 44),
        TextButton.icon(
          onPressed: _busy ? null : _pick,
          icon: const Icon(Icons.photo_camera_outlined),
          label: Text(_busy ? 'Subiendo…' : 'Cambiar foto'),
        ),
      ],
    );
  }
}
