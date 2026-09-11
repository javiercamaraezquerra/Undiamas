import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:un_dia_mas/services/hive_restore_service.dart';
import 'package:un_dia_mas/widgets/restore_backup_dialog.dart';

PreparedHiveBackup _backup({int entries = 2, bool withDate = true}) =>
    HiveRestoreService.prepare({
      'udm': {if (withDate) 'startDate': '2025-04-03T10:15:00.000'},
      'diary': [
        for (var i = 0; i < entries; i++)
          {
            'text': 'Entrada ficticia $i',
            'mood': 2,
            'createdAt': '2026-09-10T10:15:00.000',
          },
      ],
    });

Future<void> _openConfirmation(
  WidgetTester tester, {
  required PreparedHiveBackup backup,
  required ValueChanged<bool?> onResult,
  double textScale = 1,
}) async {
  await tester.pumpWidget(MaterialApp(
    builder: (_, child) => MediaQuery(
      data: MediaQuery.of(_).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async => onResult(await showDialog<bool>(
            context: context,
            builder: (_) => RestoreBackupConfirmation(
              currentEntryCount: 7,
              backup: backup,
            ),
          )),
          child: const Text('Revisar copia'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Revisar copia'));
  await tester.pumpAndSettle();
}

Future<void> _openOperation(
  WidgetTester tester, {
  required Future<HiveRestoreResult> Function() restore,
  required Future<HiveRestoreResult> Function() recover,
  required ValueChanged<HiveRestoreResult?> onResult,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async => onResult(await showDialog<HiveRestoreResult>(
            context: context,
            barrierDismissible: false,
            builder: (_) => RestoreBackupOperation(
              restore: restore,
              recover: recover,
            ),
          )),
          child: const Text('Aplicar copia'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Aplicar copia'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  testWidgets('shows both entry counts and a separate cancelable replacement',
      (tester) async {
    final decisions = <bool?>[];
    await _openConfirmation(tester, backup: _backup(), onResult: decisions.add);
    expect(find.text('Inventario actual: 7 entradas.'), findsOneWidget);
    expect(find.text('Inventario de la copia: 2 entradas.'), findsOneWidget);
    expect(find.textContaining('sustituirá tu inventario'), findsOneWidget);
    expect(find.textContaining('03/04/2025 10:15'), findsOneWidget);
    expect(decisions, isEmpty);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(decisions, [false]);
    expect(find.byType(RestoreBackupOperation), findsNothing);

    await tester.tap(find.text('Revisar copia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sustituir y restaurar'));
    await tester.pumpAndSettle();
    expect(decisions, [false, true]);
  });

  testWidgets('valid empty copy warns explicitly at 320px and text 200%',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final decisions = <bool?>[];
    await _openConfirmation(tester,
        backup: _backup(entries: 0, withDate: false),
        textScale: 2,
        onResult: decisions.add);
    expect(find.text('Inventario de la copia: 0 entradas.'), findsOneWidget);
    expect(find.textContaining('quedará vacío'), findsOneWidget);
    expect(find.textContaining('se conservará la actual'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Cancelar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(decisions, [false]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'writing blocks back and outside taps until successful completion',
      (tester) async {
    final pending = Completer<HiveRestoreResult>();
    final results = <HiveRestoreResult?>[];
    var calls = 0;
    await _openOperation(tester,
        restore: () {
          calls++;
          return pending.future;
        },
        recover: () async => throw StateError('Recovery must not run'),
        onResult: results.add);
    expect(calls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await Navigator.of(tester.element(find.byType(RestoreBackupOperation)))
        .maybePop();
    await tester.pump();
    expect(find.byType(RestoreBackupOperation), findsOneWidget);
    expect(results, isEmpty);
    pending.complete(const HiveRestoreResult(ok: true, message: 'Restaurado'));
    await tester.pumpAndSettle();
    expect(results.single!.ok, isTrue);
    expect(find.byType(RestoreBackupOperation), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'recovery-required never returns to inventory and retry runs once',
      (tester) async {
    final pending = Completer<HiveRestoreResult>();
    final results = <HiveRestoreResult?>[];
    var retries = 0;
    await _openOperation(tester,
        restore: () async => const HiveRestoreResult(
            ok: false,
            recoveryRequired: true,
            message: 'Recuperación pendiente'),
        recover: () {
          retries++;
          return pending.future;
        },
        onResult: results.add);
    await tester.pumpAndSettle();
    expect(find.text('Reintentar recuperación'), findsOneWidget);
    expect(find.text('Cerrar'), findsNothing);
    await Navigator.of(tester.element(find.byType(RestoreBackupOperation)))
        .maybePop();
    await tester.pumpAndSettle();
    expect(find.byType(RestoreBackupOperation), findsOneWidget);
    await tester.tap(find.text('Reintentar recuperación'));
    await tester.tap(find.text('Reintentar recuperación'));
    await tester.pump();
    expect(retries, 1);
    expect(results, isEmpty);
    pending.complete(const HiveRestoreResult(
        ok: true, recovered: true, message: 'Datos anteriores recuperados'));
    await tester.pumpAndSettle();
    expect(results.single!.recovered, isTrue);
    expect(find.byType(RestoreBackupOperation), findsNothing);
  });

  testWidgets('safe rollback failure explains result and permits closing',
      (tester) async {
    final results = <HiveRestoreResult?>[];
    await _openOperation(tester,
        restore: () async => const HiveRestoreResult(
            ok: false,
            recovered: true,
            message: 'Datos anteriores conservados'),
        recover: () async => throw StateError('Already recovered'),
        onResult: results.add);
    await tester.pumpAndSettle();
    expect(find.text('Datos anteriores conservados'), findsOneWidget);
    expect(find.text('Reintentar recuperación'), findsNothing);
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    expect(results.single!.ok, isFalse);
    expect(results.single!.recoveryRequired, isFalse);
    expect(results.single!.recovered, isTrue);
  });

  testWidgets('unexpected exception requires recovery before it can close',
      (tester) async {
    final results = <HiveRestoreResult?>[];
    await _openOperation(tester,
        restore: () async => throw StateError('Simulated IO exception'),
        recover: () async => const HiveRestoreResult(
            ok: true, recovered: true, message: 'Recuperado'),
        onResult: results.add);
    await tester.pumpAndSettle();
    expect(find.text('Reintentar recuperación'), findsOneWidget);
    expect(find.text('Cerrar'), findsNothing);
    expect(results, isEmpty);
    await tester.tap(find.text('Reintentar recuperación'));
    await tester.pumpAndSettle();
    expect(results.single!.recovered, isTrue);
    expect(tester.takeException(), isNull);
  });
}
