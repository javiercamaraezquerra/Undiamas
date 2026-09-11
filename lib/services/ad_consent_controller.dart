import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'app_lock_controller.dart';

/// Native transport kept separate so tests never contact Google or show ads.
abstract class AdConsentGateway {
  Future<void> updateConsentInfo();
  Future<void> showRequiredForm();
  Future<bool> canRequestAds();
  Future<bool> privacyOptionsRequired();
  Future<void> showPrivacyOptions();
  Future<void> initializeAds();
}

/// One startup consent flow. UMP remains the authority for ad eligibility;
/// the app never stores a competing consent flag in SharedPreferences.
class AdConsentController extends ChangeNotifier with WidgetsBindingObserver {
  static final instance = AdConsentController();

  AdConsentController({
    AdConsentGateway? gateway,
    bool Function()? canPresent,
    Listenable? presentationChanges,
  })  : _gateway = gateway ?? _GoogleAdConsentGateway(),
        _canPresent = canPresent ?? _privacyAllowsPresentation,
        _presentationChanges =
            presentationChanges ?? AppLockController.instance {
    _foreground =
        (WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed) ==
            AppLifecycleState.resumed;
    _presentationChanges.addListener(_presentationChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  final AdConsentGateway _gateway;
  final bool Function() _canPresent;
  final Listenable _presentationChanges;
  Future<void>? _initializing;
  Future<void>? _sdkInitializing;
  Completer<void>? _presentationWaiter;
  bool _foreground = true;
  bool _allowed = false;
  bool _busy = false;
  bool _formVisible = false;
  bool _privacyOptionsRequired = false;
  bool _disposed = false;
  bool _retryableFailure = false;
  bool _backgroundAfterFailure = false;
  bool _resumeRetryRequested = false;
  bool _resumeRetryUsed = false;
  int _revision = 0;
  String? _message;

  // Eligibility does not disappear when an ad opens another native activity.
  // Banners retain their Ad while temporarily hidden, but cannot request more.
  bool get adsAllowed => !_disposed && _allowed;
  bool get canLoadAds => adsAllowed && _presentable && !_formVisible;
  bool get privacyOptionsRequired => _privacyOptionsRequired;
  bool get busy => _busy;
  // Includes native loading: a form may appear after its asynchronous load.
  bool get formVisible => _formVisible;
  String? get message => _message;
  bool get _presentable => !_disposed && _foreground && _canPresent();

  static bool _privacyAllowsPresentation() {
    final lock = AppLockController.instance;
    return !lock.covered && !lock.authenticating && !lock.changingSetting;
  }

  /// Main starts this after startup permission dialogs. Banners only listen.
  Future<void> initialize() {
    if (_initializing != null) return _initializing!;
    final done = Completer<void>();
    _initializing = done.future;
    unawaited(_initialize().then(done.complete, onError: done.completeError));
    return done.future;
  }

  Future<void> _initialize() async {
    if (_disposed) return;
    final revision = ++_revision;
    _busy = true;
    _notify();
    try {
      if (!await _waitForPresentation(revision)) return;
      var failed = false;
      try {
        await _gateway.updateConsentInfo();
        if (!_current(revision)) return;
        await _refreshPrivacyRequirement(revision);
        if (!await _waitForPresentation(revision)) return;
        await _showForm(_gateway.showRequiredForm, revision);
      } catch (_) {
        failed = true;
      }
      // Google explicitly allows UMP's still-valid previous-session state
      // after a failed update/form. No app-maintained cache can grant consent.
      await _completeEligibility(revision, failed: failed);
    } finally {
      if (_current(revision)) {
        _busy = false;
        _notify();
      }
    }
  }

  Future<bool> showPrivacyOptions() async {
    if (_disposed || _busy || !_privacyOptionsRequired || !_presentable) {
      return false;
    }
    final revision = ++_revision;
    _busy = true;
    _allowed = false; // Dispose existing banners before consent can change.
    _message = null;
    _notify();
    try {
      await _showForm(_gateway.showPrivacyOptions, revision);
      if (!_current(revision)) return false;
      return await _completeEligibility(revision, failed: false);
    } catch (_) {
      if (_current(revision)) {
        await _completeEligibility(revision, failed: true);
      }
      return false;
    } finally {
      if (_current(revision)) {
        _busy = false;
        _notify();
      }
    }
  }

  Future<void> _showForm(Future<void> Function() show, int revision) async {
    if (!await _waitForPresentation(revision)) return;
    _formVisible = true;
    _notify();
    try {
      await show();
    } finally {
      if (_current(revision)) {
        _formVisible = false;
        _notify();
      }
    }
  }

  Future<void> _readEligibility(int revision) async {
    await _refreshPrivacyRequirement(revision);
    if (!_current(revision)) return;
    final allowed = await _gateway.canRequestAds();
    if (!_current(revision)) return;
    if (allowed) {
      // A shared Future also prevents simultaneous banners initializing SDK.
      final initializing = _sdkInitializing ??= _gateway.initializeAds();
      try {
        await initializing;
      } catch (_) {
        // A failed initialization is retryable on explicit options or the
        // bounded foreground retry. A successful initialization stays shared.
        if (identical(_sdkInitializing, initializing)) _sdkInitializing = null;
        rethrow;
      }
      if (!_current(revision)) return;
    }
    _allowed = allowed;
  }

  Future<void> _refreshPrivacyRequirement(int revision) async {
    try {
      final required = await _gateway.privacyOptionsRequired();
      if (_current(revision)) _privacyOptionsRequired = required;
    } catch (_) {
      // Keep a previously known required entry point available for retry.
    }
  }

  Future<bool> _completeEligibility(int revision,
      {required bool failed}) async {
    if (!_current(revision)) return false;
    try {
      await _readEligibility(revision);
    } catch (_) {
      failed = true;
      if (_current(revision)) _allowed = false;
    }
    if (!_current(revision)) return false;
    _message = failed
        ? 'No se pudieron actualizar las preferencias de anuncios. '
            'Vuelve a intentarlo.${_allowed ? '' : ' Puedes seguir usando la app sin anuncios.'}'
        : null;
    _retryableFailure = failed && !_allowed && !_privacyOptionsRequired;
    _backgroundAfterFailure = false;
    return !failed;
  }

  void _maybeRetryAfterResume() {
    if (!_resumeRetryRequested ||
        !_retryableFailure ||
        _resumeRetryUsed ||
        _busy ||
        !_presentable) {
      return;
    }
    _resumeRetryUsed = true;
    _resumeRetryRequested = false;
    unawaited(_refreshSilently());
  }

  Future<void> _refreshSilently() async {
    final revision = ++_revision;
    _busy = true;
    _notify();
    try {
      var failed = false;
      try {
        await _gateway.updateConsentInfo();
      } catch (_) {
        failed = true;
      }
      // At most once after an actual background/return following a failure.
      // Never reopen a form automatically; a required entry point may appear.
      await _completeEligibility(revision, failed: failed);
    } finally {
      if (_current(revision)) {
        _busy = false;
        _notify();
      }
    }
  }

  Future<bool> _waitForPresentation(int revision) async {
    while (_current(revision) && !_presentable) {
      final waiter = _presentationWaiter ??= Completer<void>();
      await waiter.future;
    }
    return _current(revision);
  }

  bool _current(int revision) => !_disposed && revision == _revision;

  void _presentationChanged() {
    if (_disposed) return;
    if (_presentable) {
      final waiter = _presentationWaiter;
      _presentationWaiter = null;
      if (waiter != null && !waiter.isCompleted) waiter.complete();
    }
    _notify();
    _maybeRetryAfterResume();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_retryableFailure &&
        (state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused)) {
      _backgroundAfterFailure = true;
    }
    if (state == AppLifecycleState.resumed && _backgroundAfterFailure) {
      _resumeRetryRequested = true;
    }
    _foreground = state == AppLifecycleState.resumed;
    _presentationChanged();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    _allowed = false;
    _presentationChanges.removeListener(_presentationChanged);
    WidgetsBinding.instance.removeObserver(this);
    final waiter = _presentationWaiter;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
    super.dispose();
  }
}

class _GoogleAdConsentGateway implements AdConsentGateway {
  @override
  Future<void> updateConsentInfo() {
    final done = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () {
        if (!done.isCompleted) done.complete();
      },
      (error) {
        if (!done.isCompleted) done.completeError(error);
      },
    );
    return done.future;
  }

  @override
  Future<void> showRequiredForm() async {
    // In google_mobile_ads 5.3.1 Android replies to this channel from UMP's
    // dismissal callback (or immediately when no form is required).
    FormError? failure;
    await ConsentForm.loadAndShowConsentFormIfRequired((error) {
      failure = error;
    });
    if (failure != null) throw failure!;
  }

  @override
  Future<void> showPrivacyOptions() async {
    // This Future also waits for the native dismissal callback in 5.3.1.
    FormError? failure;
    await ConsentForm.showPrivacyOptionsForm((error) {
      failure = error;
    });
    if (failure != null) throw failure!;
  }

  @override
  Future<bool> canRequestAds() => ConsentInformation.instance.canRequestAds();

  @override
  Future<bool> privacyOptionsRequired() async =>
      await ConsentInformation.instance.getPrivacyOptionsRequirementStatus() ==
      PrivacyOptionsRequirementStatus.required;

  @override
  Future<void> initializeAds() async {
    await MobileAds.instance.initialize();
  }
}
