import 'dart:async';

import 'package:flutter/material.dart';

import '../services/ad_consent_controller.dart';
import '../services/app_lock_controller.dart';
import '../services/hive_restore_service.dart';
import '../services/play_review_service.dart';

/// Invalidates a pending invitation when another screen/dialog takes focus.
class ReviewNavigationObserver extends NavigatorObserver {
  final revision = ValueNotifier<int>(0);
  void _changed() => revision.value++;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _changed();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _changed();
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _changed();
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _changed();
}

final reviewNavigationObserver = ReviewNavigationObserver();

bool reviewEnvironmentAvailable() {
  final lock = AppLockController.instance;
  final consent = AdConsentController.instance;
  final restore = HiveRestoreService.instance;
  return !lock.covered &&
      !lock.obscured &&
      !lock.authenticating &&
      !lock.changingSetting &&
      !consent.busy &&
      !consent.formVisible &&
      !restore.busy &&
      !restore.recoveryRequired;
}

Listenable reviewEnvironmentChanges() => Listenable.merge([
      AppLockController.instance,
      AdConsentController.instance,
      HiveRestoreService.instance,
    ]);

/// Only a deliberate tab change can trigger the one-time invitation. Startup,
/// resume, returning from SOS and completing another modal never trigger it.
class PlayReviewPromptHost extends StatefulWidget {
  const PlayReviewPromptHost({
    super.key,
    required this.tabIndex,
    required this.child,
    this.service,
    this.canPresent,
    this.environmentChanges,
    this.navigationObserver,
  });

  final int tabIndex;
  final Widget child;
  final PlayReviewService? service;
  final bool Function()? canPresent;
  final Listenable? environmentChanges;
  final ReviewNavigationObserver? navigationObserver;

  @override
  State<PlayReviewPromptHost> createState() => _PlayReviewPromptHostState();
}

class _PlayReviewPromptHostState extends State<PlayReviewPromptHost>
    with WidgetsBindingObserver {
  late final PlayReviewService _service;
  late final Listenable _changes;
  late final ReviewNavigationObserver _navigation;
  Timer? _timer;
  int _epoch = 0;
  bool _foreground = true;
  DialogRoute<void>? _dialog;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? PlayReviewService.instance;
    _changes = widget.environmentChanges ?? reviewEnvironmentChanges();
    _navigation = widget.navigationObserver ?? reviewNavigationObserver;
    _foreground =
        (WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed) ==
            AppLifecycleState.resumed;
    _changes.addListener(_invalidate);
    _navigation.revision.addListener(_invalidate);
    FocusManager.instance.addListener(_invalidate);
    WidgetsBinding.instance.addObserver(this);
  }

  bool get _available =>
      mounted &&
      _foreground &&
      _service.startupReady &&
      (widget.canPresent?.call() ?? reviewEnvironmentAvailable());

  bool get _current =>
      _available &&
      ModalRoute.of(context)?.isCurrent == true &&
      !_editing &&
      (MediaQuery.maybeOf(context)?.viewInsets.bottom ?? 0) == 0;

  bool get _editing {
    final focused = FocusManager.instance.primaryFocus?.context;
    return focused?.widget is EditableText ||
        focused?.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void _invalidate() {
    _epoch++;
    _timer?.cancel();
    final dialog = _dialog;
    if (dialog != null &&
        dialog.isActive &&
        (!_available || !dialog.isCurrent)) {
      // Remove only our own route, never another flow placed on top of it.
      // NavigatorObserver may run while its route stack is locked.
      _dialog = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (dialog.isActive) dialog.navigator?.removeRoute(dialog);
      });
      // Adding a post-frame callback alone does not request a frame. A state
      // signal may otherwise leave the stale dialog up until the next touch.
      WidgetsBinding.instance.ensureVisualUpdate();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _invalidate();
  }

  @override
  void didUpdateWidget(covariant PlayReviewPromptHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabIndex == widget.tabIndex) return;
    _invalidate();
    // Includes screen-reader/keyboard activation of the navigation bar.
    if (_current) unawaited(_service.recordUsageDay());
    // Protect composing and reading. The neutral tabs share this behaviour.
    if (![0, 3, 4].contains(widget.tabIndex) || !_current) return;
    final epoch = _epoch;
    // Let the page transition and its initialization finish before checking.
    _timer = Timer(const Duration(milliseconds: 600), () => _tryShow(epoch));
  }

  Future<void> _tryShow(int epoch) async {
    bool current() => epoch == _epoch && _dialog == null && _current;
    if (!current()) return;
    final claimed = await _service.claimInvitation(canShow: current);
    if (!mounted || !claimed || !current()) return;
    final route = DialogRoute<void>(
      context: context,
      builder: (_) => PlayReviewInvitation(
        service: _service,
        canLaunch: () => _available,
      ),
    );
    _dialog = route;
    await Navigator.of(context, rootNavigator: true).push(route);
    if (identical(_dialog, route)) _dialog = null;
  }

  @override
  void dispose() {
    _epoch++;
    _timer?.cancel();
    _changes.removeListener(_invalidate);
    _navigation.revision.removeListener(_invalidate);
    FocusManager.instance.removeListener(_invalidate);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          // A new task (scrolling, editing, opening help) cancels the delayed
          // invitation. A subsequent deliberate tab change can try again.
          _invalidate();
          if (_current) unawaited(_service.recordUsageDay());
        },
        child: widget.child,
      );
}

class PlayReviewInvitation extends StatefulWidget {
  const PlayReviewInvitation({
    super.key,
    required this.service,
    required this.canLaunch,
  });
  final PlayReviewService service;
  final bool Function() canLaunch;

  @override
  State<PlayReviewInvitation> createState() => _PlayReviewInvitationState();
}

class _PlayReviewInvitationState extends State<PlayReviewInvitation> {
  bool _opening = false;
  String? _message;

  Future<void> _open() async {
    if (_opening || !widget.canLaunch()) return;
    setState(() {
      _opening = true;
      _message = null;
    });
    final opened = await widget.service.openListing(
        canLaunch: () =>
            mounted &&
            widget.canLaunch() &&
            ModalRoute.of(context)?.isCurrent == true);
    if (!mounted) return;
    if (opened) {
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) route.navigator?.removeRoute(route);
    } else {
      setState(() {
        _opening = false;
        _message = 'No se pudo abrir Google Play. Puedes volver a intentarlo '
            'cuando quieras desde Perfil.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Tu opinión nos ayuda'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tus comentarios nos ayudan a seguir mejorando '
                'Un día más. Gracias por dedicarnos un momento.'),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(_message!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: _opening ? null : _open,
            child: Text(_opening ? 'Abriendo…' : 'Valorar en Google Play'),
          ),
        ],
      );
}
