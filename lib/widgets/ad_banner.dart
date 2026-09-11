import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/ad_consent_controller.dart';

/// Banner reutilizable (tamaño fijo) centrado.
/// Los márgenes laterales quedan transparentes para mostrar el fondo.
class AdBanner extends StatefulWidget {
  final String adUnitId;
  final AdConsentController? consentController;
  const AdBanner({super.key, required this.adUnitId, this.consentController});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _banner;
  bool _loaded = false;
  late AdConsentController _consent;

  /*──────────────────────── lifecycle ────────────────────────*/
  @override
  void initState() {
    super.initState();
    _consent = widget.consentController ?? AdConsentController.instance;
    _consent.addListener(_consentChanged);
    if (_consent.canLoadAds) _loadFixedBanner();
  }

  @override
  void didUpdateWidget(AdBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    final consent = widget.consentController ?? AdConsentController.instance;
    if (consent != _consent || oldWidget.adUnitId != widget.adUnitId) {
      _consent.removeListener(_consentChanged);
      _discardBanner();
      _consent = consent;
      _consent.addListener(_consentChanged);
      if (_consent.canLoadAds) _loadFixedBanner();
    }
  }

  void _consentChanged() {
    if (!mounted) return;
    if (!_consent.adsAllowed) {
      _discardBanner();
    } else if (_banner == null && _consent.canLoadAds) {
      _loadFixedBanner();
    }
    setState(() {});
  }

  void _discardBanner() {
    final banner = _banner;
    _banner = null;
    _loaded = false;
    if (banner != null) _disposeAd(banner);
  }

  void _disposeAd(Ad ad) {
    unawaited(ad.dispose().catchError((Object _) {
      dev.log('No se pudo liberar el anuncio.');
    }));
  }

  /*────────────── carga de banner estándar 320 × 50 ──────────*/
  void _loadFixedBanner() {
    if (!_consent.canLoadAds || _banner != null) return;
    final banner = BannerAd(
      // ⇣ Cambia aquí si prefieres otro tamaño oficial
      size: AdSize.banner, // 320×50 (largeBanner = 320×100)
      adUnitId: const bool.fromEnvironment('UDM_PREVIEW')
          ? 'ca-app-pub-3940256099942544/6300978111'
          : widget.adUnitId,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted || ad != _banner || !_consent.adsAllowed) {
            _disposeAd(ad);
            return;
          }
          final s = (ad as BannerAd).size;
          dev.log('✅ Banner loaded (${s.width}×${s.height})');
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, err) {
          dev.log('⛔️ Banner failed: ${err.code} – ${err.message}');
          if (mounted && ad == _banner) {
            setState(() {
              _banner = null;
              _loaded = false;
            });
          }
          _disposeAd(ad);
        },
      ),
    );
    _banner = banner;
    unawaited(_load(banner));
  }

  Future<void> _load(BannerAd banner) async {
    try {
      await banner.load();
    } catch (_) {
      if (mounted && banner == _banner) {
        setState(() {
          _banner = null;
          _loaded = false;
        });
      }
      _disposeAd(banner);
    }
  }

  @override
  void dispose() {
    _consent.removeListener(_consentChanged);
    _discardBanner();
    super.dispose();
  }

  /*──────────────────────────── UI ───────────────────────────*/
  @override
  Widget build(BuildContext context) {
    if (!_consent.adsAllowed || !_loaded || _banner == null) {
      return const SizedBox.shrink();
    }

    final h = _banner!.size.height.toDouble();
    final w = _banner!.size.width.toDouble();

    return Offstage(
      offstage: !_consent.canLoadAds,
      child: IgnorePointer(
        ignoring: !_consent.canLoadAds,
        child: ExcludeSemantics(
          excluding: !_consent.canLoadAds,
          child: Container(
            color: Colors.transparent, // deja ver el fondo dibujado
            width: double.infinity, // ocupa todo el ancho disponible
            height: h, // pero solo la altura del banner
            alignment: Alignment.center, // centra el anuncio
            child: SizedBox(
              // caja exacta del AdWidget
              width: w,
              height: h,
              child: AdWidget(ad: _banner!),
            ),
          ),
        ),
      ),
    );
  }
}
