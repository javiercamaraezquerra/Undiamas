import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/hive_restore_service.dart';

/// Consent to replacing local data, separate from permission to access Drive.
class RestoreBackupConfirmation extends StatelessWidget {
  const RestoreBackupConfirmation({
    super.key,
    required this.currentEntryCount,
    required this.backup,
  });

  final int currentEntryCount;
  final PreparedHiveBackup backup;

  @override
  Widget build(BuildContext context) {
    final startDate = backup.startDate;
    return AlertDialog(
      scrollable: true,
      title: const Text('Revisar antes de restaurar'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Inventario actual: $currentEntryCount entradas.'),
          const SizedBox(height: 8),
          Text('Inventario de la copia: ${backup.entryCount} entradas.'),
          if (backup.photoCount > 0) ...[
            const SizedBox(height: 8),
            Text('Fotos incluidas: ${backup.photoCount}.'),
          ],
          const SizedBox(height: 16),
          const Text(
            'La copia sustituirá tu inventario actual. Las entradas actuales '
            'que no estén en la copia dejarán de aparecer. '
            'El borrador sin guardar se descartará.',
          ),
          if (backup.isEmptyInventory) ...[
            const SizedBox(height: 12),
            Text(
              'Esta copia no contiene entradas. Si continúas, tu inventario '
              'quedará vacío.',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(startDate == null
              ? 'La copia no incluye una fecha de inicio: se conservará la actual.'
              : 'También se restaurará la fecha de inicio: '
                  '${DateFormat('dd/MM/yyyy HH:mm').format(startDate.toLocal())}.'),
          const SizedBox(height: 12),
          const Text('Si cancelas, no se cambiará ningún dato.'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Sustituir y restaurar'),
        ),
      ],
    );
  }
}

/// Keeps the rest of the app inaccessible until both boxes are consistent.
/// Call with showDialog(barrierDismissible: false). A recovery failure offers
/// another recovery attempt, never a return to the potentially partial data.
class RestoreBackupOperation extends StatefulWidget {
  const RestoreBackupOperation({
    super.key,
    required this.restore,
    required this.recover,
  });

  final Future<HiveRestoreResult> Function() restore;
  final Future<HiveRestoreResult> Function() recover;

  @override
  State<RestoreBackupOperation> createState() => _RestoreBackupOperationState();
}

class _RestoreBackupOperationState extends State<RestoreBackupOperation> {
  bool _busy = true;
  bool _running = false;
  bool _recoveryRequired = false;
  String? _message;
  HiveRestoreResult? _result;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _run(recover: false);
    });
  }

  Future<void> _run({required bool recover}) async {
    if (_running) return;
    _running = true;
    setState(() => _busy = true);
    try {
      final result = await (recover ? widget.recover() : widget.restore());
      if (!mounted) return;
      if (result.ok && !result.recoveryRequired) {
        Navigator.pop(context, result);
        return;
      }
      setState(() {
        _busy = false;
        _recoveryRequired = result.recoveryRequired;
        _message = result.message;
        _result = result;
      });
    } catch (_) {
      if (!mounted) return;
      // An unexpected exception cannot prove that both boxes are consistent.
      // Recovery is therefore required before dismissing this route.
      setState(() {
        _busy = false;
        _recoveryRequired = true;
        _message = 'No se pudo completar la operación. Reintenta recuperar '
            'los datos anteriores antes de continuar.';
      });
    } finally {
      _running = false;
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy && !_recoveryRequired,
        child: AlertDialog(
          scrollable: true,
          title: Text(_busy
              ? (_recoveryRequired
                  ? 'Recuperando datos…'
                  : 'Restaurando copia…')
              : (_recoveryRequired
                  ? 'Es necesario recuperar los datos'
                  : 'La copia no se ha restaurado')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_busy) ...[
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 16),
                const Text('Espera a que termine. Estamos comprobando que el '
                    'inventario y la fecha de inicio queden guardados juntos.'),
              ] else ...[
                Text(_message ?? 'No se pudo restaurar la copia.'),
                if (_recoveryRequired) ...[
                  const SizedBox(height: 12),
                  const Text('El acceso al inventario seguirá bloqueado hasta '
                      'recuperar los datos anteriores.'),
                ],
              ],
            ],
          ),
          actions: _busy
              ? null
              : [
                  if (_recoveryRequired)
                    FilledButton(
                      onPressed: () => _run(recover: true),
                      child: const Text('Reintentar recuperación'),
                    )
                  else
                    TextButton(
                      onPressed: () => Navigator.pop(context, _result),
                      child: const Text('Cerrar'),
                    ),
                ],
        ),
      );
}
