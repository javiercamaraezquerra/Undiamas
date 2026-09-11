import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/ad_consent_controller.dart';
import '../services/app_lock_controller.dart';

/// Profile entries only. Consent collection remains owned by its controller.
class ProfilePrivacyLinks extends StatefulWidget {
  const ProfilePrivacyLinks({
    super.key,
    required this.foreground,
    required this.policyUri,
    this.consentController,
    this.appLock,
    this.openPolicy,
  });

  final Color foreground;
  final Uri policyUri;
  final AdConsentController? consentController;
  final AppLockController? appLock;
  final Future<bool> Function(Uri)? openPolicy;

  @override
  State<ProfilePrivacyLinks> createState() => _ProfilePrivacyLinksState();
}

class _ProfilePrivacyLinksState extends State<ProfilePrivacyLinks> {
  bool _openingPolicy = false;
  bool _openingAdPrivacy = false;
  AdConsentController get _consent =>
      widget.consentController ?? AdConsentController.instance;
  AppLockController get _lock => widget.appLock ?? AppLockController.instance;

  bool get _canOpen =>
      _lock.initialized &&
      !_lock.covered &&
      !_lock.obscured &&
      !_lock.authenticating &&
      !_lock.changingSetting &&
      !_openingPolicy &&
      !_openingAdPrivacy &&
      !_consent.busy;

  void _failure(String message) {
    if (!mounted) return;
    // The Scaffold is inside AppLockGate, so this never appears above its cover.
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showPolicy() async {
    if (!_canOpen) return;
    setState(() => _openingPolicy = true);
    try {
      final opened =
          await (widget.openPolicy ?? _launchPolicy)(widget.policyUri);
      if (!opened) {
        _failure('No se pudo abrir la política de privacidad. '
            'Vuelve a intentarlo.');
      }
    } catch (_) {
      _failure('No se pudo abrir la política de privacidad. '
          'Vuelve a intentarlo.');
    } finally {
      if (mounted) setState(() => _openingPolicy = false);
    }
  }

  static Future<bool> _launchPolicy(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  Future<void> _showAdPrivacy() async {
    if (!_canOpen || !_consent.privacyOptionsRequired) return;
    setState(() => _openingAdPrivacy = true);
    try {
      final completed = await _consent.showPrivacyOptions();
      if (!completed) {
        _failure(_consent.message ??
            'No se pudieron abrir las opciones de privacidad de anuncios. '
                'Vuelve a intentarlo.');
      }
    } catch (_) {
      _failure('No se pudieron abrir las opciones de privacidad de anuncios. '
          'Vuelve a intentarlo.');
    } finally {
      if (mounted) setState(() => _openingAdPrivacy = false);
    }
  }

  Widget _tile({
    required Key key,
    required String title,
    required IconData icon,
    required bool opening,
    required VoidCallback onTap,
  }) =>
      ListTile(
        key: key,
        leading: Icon(icon, color: widget.foreground),
        title: Text(title, style: TextStyle(color: widget.foreground)),
        subtitle: opening
            ? Text('Abriendo…', style: TextStyle(color: widget.foreground))
            : null,
        enabled: _canOpen,
        onTap: _canOpen ? onTap : null,
        iconColor: widget.foreground,
        textColor: widget.foreground,
      );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([_consent, _lock]),
        builder: (_, __) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _tile(
              key: const ValueKey('profile-privacy-policy'),
              title: 'Política de privacidad',
              icon: Icons.policy_outlined,
              opening: _openingPolicy,
              onTap: _showPolicy,
            ),
            if (_consent.privacyOptionsRequired)
              _tile(
                key: const ValueKey('profile-ad-privacy'),
                title: 'Privacidad de anuncios',
                icon: Icons.tune,
                opening: _openingAdPrivacy,
                onTap: _showAdPrivacy,
              ),
          ],
        ),
      );
}
