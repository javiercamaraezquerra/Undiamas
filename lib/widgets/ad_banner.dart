import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Banner reutilizable (anchored‑adaptive) sin bandas laterales.
/// El contenedor sobrante es transparente para mostrar el fondo.
class AdBanner extends StatefulWidget {
  final String adUnitId;
  const AdBanner({super.key, required this.adUnitId});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _banner;
  bool _loaded = false;

  /*───────────────────────────── lifecycle ───────────────────────────────*/
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadAdaptiveBanner(); // necesita MediaQuery → aquí
  }

  /*─────────────────── carga de Banner adaptativo ────────────────────────*/
  Future<void> _loadAdaptiveBanner() async {
    if (_banner != null) return;

    final width = MediaQuery.of(context).size.width.truncate();
    final adSize =
        await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width) ??
            AdSize.banner; // fallback

    _banner = BannerAd(
      size: adSize,
      adUnitId: widget.adUnitId,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          // cast necesario para acceder a .size
          final size = (ad as BannerAd).size;
          dev.log('✅ Banner loaded (${size.width}×${size.height})');
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, err) {
          dev.log('⛔️ Banner failed: ${err.code} – ${err.message}');
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

  /*────────────────────────────────  UI  ────────────────────────────────*/
  @override
  Widget build(BuildContext context) {
    if (!_loaded || _banner == null) return const SizedBox.shrink();

    return Container(
      color: Colors.transparent,                 // deja ver el fondo
      width: double.infinity,                   // ancho completo
      height: _banner!.size.height.toDouble(),  // alto del banner real
      alignment: Alignment.center,
      child: AdWidget(ad: _banner!),
    );
  }
}
