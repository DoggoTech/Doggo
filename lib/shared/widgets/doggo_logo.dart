import 'package:flutter/material.dart';

class DoggoLogo extends StatelessWidget {
  const DoggoLogo({super.key, this.size = 160});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Logo de Doggo',
      image: true,
      child: Image.asset('assets/logo.png', height: size),
    );
  }
}
