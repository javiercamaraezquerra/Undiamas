import 'package:flutter/material.dart';

/// A standalone startup screen; it never mounts the normal application or data.
///
/// [message] and errors returned by [retry] must already be safe, user-facing
/// messages. Exception details are deliberately never displayed.
class InventoryRecoveryApp extends StatefulWidget {
  const InventoryRecoveryApp({
    super.key,
    required this.retry,
    required this.onRecovered,
    required this.message,
  });

  final Future<String?> Function() retry;
  final VoidCallback onRecovered;
  final String message;

  @override
  State<InventoryRecoveryApp> createState() => _InventoryRecoveryAppState();
}

class _InventoryRecoveryAppState extends State<InventoryRecoveryApp> {
  static const _retryError =
      'No hemos podido recuperar el inventario. Puedes volver a intentarlo.';
  static const _openError =
      'No hemos podido abrir la aplicación. Ciérrala y vuelve a abrirla.';

  late String _message = _displayMessage(widget.message);
  bool _busy = false;
  bool _reportedRecovery = false;

  String _displayMessage(String value) =>
      value.trim().isEmpty ? _retryError : value;

  Future<void> _retry() async {
    if (_busy || _reportedRecovery) return;
    setState(() => _busy = true);
    String? error;
    try {
      error = await widget.retry();
    } catch (_) {
      error = _retryError;
    }
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _message = _displayMessage(error!);
        _busy = false;
      });
      return;
    }

    // Keep the cover in place until the owner replaces this entire application.
    // Mark first, because the callback may synchronously throw or trigger work.
    _reportedRecovery = true;
    try {
      widget.onRecovered();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = _openError;
        _busy = false;
      });
    }
  }

  ThemeData _theme(Brightness brightness) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF354DFF),
          brightness: brightness,
        ),
      );

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Un día más',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: PopScope(
          canPop: false,
          child: Scaffold(
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Icon(Icons.inventory_2_outlined, size: 48),
                              const SizedBox(height: 20),
                              Semantics(
                                header: true,
                                child: Text(
                                  'Recuperar el inventario',
                                  textAlign: TextAlign.center,
                                  style:
                                      Theme.of(context).textTheme.headlineSmall,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Hay una restauración pendiente. Antes de abrir '
                                'la aplicación necesitamos recuperar el inventario.',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  _message,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(height: 24),
                              if (_busy) ...[
                                const Center(
                                  child: SizedBox.square(
                                    dimension: 28,
                                    child: CircularProgressIndicator(
                                      semanticsLabel:
                                          'Recuperando el inventario',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                              FilledButton(
                                onPressed:
                                    _busy || _reportedRecovery ? null : _retry,
                                child: Text(
                                  _busy ? 'Reintentando…' : 'Reintentar',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
