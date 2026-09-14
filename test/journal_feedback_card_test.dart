import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:un_dia_mas/widgets/journal_feedback_card.dart';

void main() {
  testWidgets('feedback is opaque and its actions wrap with large text',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    var retry = 0;
    var other = 0;
    var dismissed = 0;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!),
      home: Scaffold(
          body: SingleChildScrollView(
              child: Padding(
        padding: const EdgeInsets.all(16),
        child: JournalFeedbackCard(
          title: 'No se pudo abrir la foto',
          message:
              'Vuelve a elegirla en la galería. Tu mensaje y la foto anterior se conservan.',
          isError: true,
          onDismiss: () => dismissed++,
          actions: [
            TextButton(
                onPressed: () => retry++, child: const Text('Reintentar')),
            TextButton(
                onPressed: () => other++, child: const Text('Elegir otra')),
          ],
        ),
      ))),
    ));
    await tester.pumpAndSettle();
    final decoration = tester
        .widget<DecoratedBox>(find
            .descendant(
                of: find.byType(JournalFeedbackCard),
                matching: find.byType(DecoratedBox))
            .first)
        .decoration as BoxDecoration;
    expect(decoration.color!.a, 1);
    expect(
        find.textContaining('la foto anterior se conservan'), findsOneWidget);
    await tester.ensureVisible(find.text('Reintentar'));
    await tester.tap(find.text('Reintentar'));
    await tester.ensureVisible(find.text('Elegir otra'));
    await tester.tap(find.text('Elegir otra'));
    await tester.ensureVisible(find.byTooltip('Cerrar aviso'));
    await tester.tap(find.byTooltip('Cerrar aviso'));
    expect(retry, 1);
    expect(other, 1);
    expect(dismissed, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('busy feedback announces the preparation without an error action',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: JournalFeedbackCard(
                message: 'Preparando foto…', isBusy: true))));
    await tester.pump();
    expect(find.text('Preparando foto…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byTooltip('Cerrar aviso'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
