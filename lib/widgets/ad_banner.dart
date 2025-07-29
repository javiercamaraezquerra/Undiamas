import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Banner reutilizable (tamaño fijo) centrado.
/// Los márgenes laterales quedan transparentes para mostrar el fondo.
class AdBanner extends StatefulWidget {
  final String adUnitId;
  const AdBanner({super.key, required this.adUnitId});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _banner;
  bool _loaded = false;

  /*──────────────────────── lifecycle ────────────────────────*/
  @override
  void initState() {
    super.initState();
    _loadFixedBanner();
  }

  /*────────────── carga de banner estándar 320 × 50 ──────────*/
  void _loadFixedBanner() {
    _banner = BannerAd(
      // ⇣ Cambia aquí si prefieres otro tamaño oficial
      size: AdSize.banner, // 320×50 (largeBanner = 320×100)
      adUnitId: widget.adUnitId,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          final s = (ad as BannerAd).size;
          dev.log('✅ Banner loaded (${s.width}×${s.height})');
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

  /*──────────────────────────── UI ───────────────────────────*/
  @override
  Widget build(BuildContext context) {
    if (!_loaded || _banner == null) return const SizedBox.shrink();

    final h = _banner!.size.height.toDouble();
    final w = _banner!.size.width.toDouble();

    return Container(
      color: Colors.transparent,       // deja ver el fondo dibujado
      width: double.infinity,          // ocupa todo el ancho disponible
      height: h,                       // pero solo la altura del banner
      alignment: Alignment.center,     // centra el anuncio
      child: SizedBox(                 // caja exacta del AdWidget
        width: w,
        height: h,
        child: AdWidget(ad: _banner!),
      ),
    );
  }
}
