import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_lock_controller.dart';

/// Sits above the root Navigator, including notification routes and dialogs.
/// Once opened, the Navigator stays mounted while hidden to retain form drafts.
class AppLockGate extends StatefulWidget {
  const AppLockGate({
    super.key,
    required this.child,
    this.controller,
    this.nativeModalChanges,
    this.nativeModalVisible,
  });

  final Widget child;
  final AppLockController? controller;
  final Listenable? nativeModalChanges;
  final bool Function()? nativeModalVisible;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  static const _privacy = MethodChannel('undiamas/privacy');
  late final AppLockController _lock;
  bool _hasOpened = false;
  bool _resumeNeedsAuth = false;
  bool? _nativeLocked;
  late AppLifecycleState _lastLifecycle;
  bool _keepCoverInBackground = true;
  bool _automaticUnlockPending = false;
  bool _automaticUnlockScheduled = false;

  bool get _nativeModalVisible => widget.nativeModalVisible?.call() ?? false;

  @override
  void initState() {
    super.initState();
    _lock = widget.controller ?? AppLockController.instance;
    final initialState =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    _lastLifecycle = initialState;
    _lock.handleLifecycle(initialState);
    _resumeNeedsAuth = initialState != AppLifecycleState.resumed;
    _hasOpened = !_lock.covered;
    _keepCoverInBackground = _lock.covered;
    _lock.addListener(_changed);
    widget.nativeModalChanges?.addListener(_nativeModalChanged);
    WidgetsBinding.instance.addObserver(this);
    _syncNative();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryAutomaticUnlock();
    });
  }

  @override
  void didUpdateWidget(AppLockGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nativeModalChanges != widget.nativeModalChanges) {
      oldWidget.nativeModalChanges?.removeListener(_nativeModalChanged);
      widget.nativeModalChanges?.addListener(_nativeModalChanged);
      _nativeModalChanged();
    }
  }

  void _tryAutomaticUnlock() {
    if (!mounted ||
        _lastLifecycle != AppLifecycleState.resumed ||
        !_lock.initialized ||
        !_lock.enabled ||
        !_lock.locked ||
        _lock.authenticating ||
        _lock.changingSetting) {
      return;
    }
    if (_nativeModalVisible) {
      _automaticUnlockPending = true;
      return;
    }
    _automaticUnlockPending = false;
    unawaited(_lock.unlock());
  }

  void _nativeModalChanged() {
    if (!mounted) return;
    setState(() {});
    if (!_automaticUnlockPending ||
        _nativeModalVisible ||
        _automaticUnlockScheduled) {
      return;
    }
    _automaticUnlockScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _automaticUnlockScheduled = false;
      _tryAutomaticUnlock();
    });
  }

  void _changed() {
    if (!mounted) return;
    _syncNative();
    setState(() {
      if (!_lock.covered) _hasOpened = true;
    });
  }

  void _syncNative() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (_nativeLocked != _lock.covered) {
      _nativeLocked = _lock.covered;
      unawaited(_privacy
          .invokeMethod<void>('setLocked', _lock.covered)
          .catchError((Object error) {
        _nativeLocked = null;
        debugPrint('Could not update Android lock navigation: $error');
      }));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Keep the last authenticated screen available to Android's normal Recents
    // snapshot. Returning still locks before any input is accepted. A session
    // that was already locked must never reveal old content on its way out.
    if (_lastLifecycle == AppLifecycleState.resumed &&
        state != AppLifecycleState.resumed) {
      _keepCoverInBackground = !_hasOpened ||
          _lock.locked ||
          _lock.authenticating ||
          _lock.changingSetting;
    }
    final wasBackground = _lastLifecycle == AppLifecycleState.paused ||
        _lastLifecycle == AppLifecycleState.hidden;
    final enteringBackground = (state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden) &&
        !wasBackground;
    _lastLifecycle = state;
    if (enteringBackground && !_lock.authenticating && !_lock.changingSetting) {
      _resumeNeedsAuth = true;
    }
    _lock.handleLifecycle(state);
    if (state == AppLifecycleState.resumed && _resumeNeedsAuth) {
      _resumeNeedsAuth = false;
      _tryAutomaticUnlock();
    }
  }

  Future<void> _retry() async {
    if (_nativeModalVisible) return;
    if (!_lock.initialized) await _lock.initialize();
    if (_lock.initialized && !_nativeModalVisible) await _lock.unlock();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lock.removeListener(_changed);
    widget.nativeModalChanges?.removeListener(_nativeModalChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inputBlocked = _lock.covered;
    final covered = inputBlocked &&
        (_lastLifecycle == AppLifecycleState.resumed ||
            _keepCoverInBackground ||
            !_hasOpened);
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: covered,
          child: TickerMode(
            enabled: !covered,
            child: IgnorePointer(
              ignoring: inputBlocked,
              child: ExcludeSemantics(
                excluding: inputBlocked,
                child: ExcludeFocus(
                  excluding: inputBlocked,
                  child: _hasOpened ? widget.child : const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        ),
        if (covered)
          Positioned.fill(
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(28),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_outline,
                              size: 48,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(height: 20),
                          Text('Un día más',
                              style: Theme.of(context).textTheme.headlineSmall),
                          const SizedBox(height: 12),
                          const Text('Desbloquea la app para continuar.',
                              textAlign: TextAlign.center),
                          if (_lock.message != null) ...[
                            const SizedBox(height: 16),
                            Text(_lock.message!, textAlign: TextAlign.center),
                          ],
                          const SizedBox(height: 24),
                          if (_lock.authenticating || _lock.changingSetting)
                            const CircularProgressIndicator()
                          else
                            FilledButton.icon(
                              onPressed: _nativeModalVisible ? null : _retry,
                              icon: const Icon(Icons.lock_open),
                              label: Text(_lock.initialized
                                  ? 'Desbloquear'
                                  : 'Reintentar'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
