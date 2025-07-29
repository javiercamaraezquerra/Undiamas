import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Banner reutilizable.
/// • Carga un **anchored‑adaptive banner** que ocupa todo el ancho disponible,  
///   por lo que desaparecen las “barras negras” laterales.  
/// • La zona que no ocupa el anuncio es transparente para que se vea el fondo.
class AdBanner extends StatefulWidget {
  final String adUnitId;
  const AdBanner({super.key, required this.adUnitId});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _banner;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadAdaptiveBanner();               // necesita MediaQuery → en didChange
  }

  /*───────────────────────────  Carga banner adaptativo  ───────────────────*/
  Future<void> _loadAdaptiveBanner() async {
    if (_banner != null) return;         // ya creado

    final width = MediaQuery.of(context).size.width.truncate();
    final size = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);

    // Fallback si size == null (caso muy raro en emulador)
    final adSize = size ?? AdSize.banner;

    _banner = BannerAd(
      size: adSize,
      adUnitId: widget.adUnitId,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          dev.log('✅ Banner loaded (${ad.size.width}×${ad.size.height})');
          setState(() => _loaded = true);
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
      color: Colors
          .transparent,                // ← mantiene visible el fondo del Scaffold
      width: double.infinity,         // ocupa todo el ancho del dispositivo
      height: _banner!.size.height.toDouble(),
      alignment: Alignment.center,    // centra el anuncio dentro del contenedor
      child: AdWidget(ad: _banner!),
    );
  }
}
