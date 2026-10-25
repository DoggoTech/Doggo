import 'package:doggo/shared/widgets/error_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('muestra un mensaje claro y reintenta', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ErrorState(
            'No pudimos cargar tus perros.',
            onRetry: () => retries++,
          ),
        ),
      ),
    );
    expect(find.text('No pudimos cargar tus perros.'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    expect(retries, 1);
  });
}
