import 'package:flutter/material.dart';

import '../services/app_lock_controller.dart';

/// Follows the existing Profile ListTile + Switch layout.
class AppLockTile extends StatefulWidget {
  const AppLockTile({super.key, required this.foreground, this.controller});

  final Color foreground;
  final AppLockController? controller;

  @override
  State<AppLockTile> createState() => _AppLockTileState();
}

class _AppLockTileState extends State<AppLockTile> {
  bool _confirming = false;
  AppLockController get _lock =>
      widget.controller ?? AppLockController.instance;

  Future<void> _toggle(bool enabled) async {
    if (_confirming || _lock.changingSetting) return;
    if (enabled) {
      setState(() => _confirming = true);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Privacidad y bloqueo de la app'),
          content: const SingleChildScrollView(
            child: Text(
              'Al abrir Un día más o volver desde otra aplicación, tendrás que '
              'desbloquearla con la seguridad de tu móvil: huella, rostro '
              'compatible, PIN, patrón o contraseña.\n\n'
              'Usarás el mismo desbloqueo que ya tienes configurado; no tendrás '
              'que crear otro código. La app no recibe ni guarda tu código '
              'ni tus datos biométricos.\n\n'
              'Para activarlo o desactivarlo tendrás que verificarte. Si tu '
              'móvil no tiene un bloqueo configurado, configúralo primero en '
              'sus Ajustes.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      setState(() => _confirming = false);
      if (confirmed != true) return;
    }

    final changed = await _lock.setEnabled(enabled);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(changed
          ? (enabled
              ? 'Bloqueo de la app activado.'
              : 'Bloqueo de la app desactivado.')
          : (_lock.message ?? 'No se ha cambiado el bloqueo de la app.')),
    ));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _lock,
        builder: (context, _) => ListTile(
          leading: Icon(Icons.lock_outline, color: widget.foreground),
          title: Text('Privacidad y bloqueo de la app',
              style: TextStyle(color: widget.foreground)),
          trailing: Switch(
            value: _lock.enabled,
            onChanged:
                !_lock.initialized || _confirming || _lock.changingSetting
                    ? null
                    : _toggle,
            activeColor: Theme.of(context).colorScheme.primary,
          ),
          iconColor: widget.foreground,
          textColor: widget.foreground,
        ),
      );
}
