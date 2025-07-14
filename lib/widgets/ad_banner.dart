import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'dart:developer' as dev;

/// Widget de banner reutilizable.
/// Muestra mensaje en consola cuando el anuncio se carga o falla.
class AdBanner extends StatefulWidget {
  final String adUnitId;
  const AdBanner({super.key, required this.adUnitId});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _banner;

  @override
  void initState() {
    super.initState();
    _banner = BannerAd(
      size: AdSize.banner,
      adUnitId: widget.adUnitId,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) => dev.log('✅ Banner loaded'),
        onAdFailedToLoad: (ad, error) {
          dev.log('⛔️ Banner failed: ${error.code} – ${error.message}');
          ad.dispose();
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_banner == null) return const SizedBox.shrink();
    return SizedBox(
      width: _banner!.size.width.toDouble(),
      height: _banner!.size.height.toDouble(),
      child: AdWidget(ad: _banner!),
    );
  }
}
