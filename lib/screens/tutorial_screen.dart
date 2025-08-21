import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/mountain_background.dart';
import '../widgets/bottom_nav_bar.dart';
import '../routes/fade_transparent_route.dart';

class TutorialScreen extends StatefulWidget {
  final bool returnToOnboarding;
  const TutorialScreen({super.key, this.returnToOnboarding = false});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final PageController _controller = PageController();
  final ValueNotifier<int> _index = ValueNotifier(0);
  final ValueNotifier<double> _page = ValueNotifier(0);
  bool _showSwipeHint = true;

  final List<_PreviewData> _slides = const [
    _PreviewData(
      title: 'Inicio',
      subtitle: 'Tu progreso de un vistazo.',
      icon: Icons.home_rounded,
      kind: _PreviewKind.home,
      semantics: 'Pantalla de inicio, muestra el contador de días limpio y accesos rápidos.',
    ),
    _PreviewData(
      title: 'Inventario',
      subtitle: 'Pon en palabras cómo te sientes.',
      icon: Icons.edit_rounded,
      kind: _PreviewKind.diary,
      semantics: 'Diario para registrar estado de ánimo y notas.',
    ),
    _PreviewData(
      title: 'Reflexión',
      subtitle: 'Una idea para hoy, breve y clara.',
      icon: Icons.auto_stories_rounded,
      kind: _PreviewKind.reflection,
      semantics: 'Reflexión diaria con recordatorio opcional.',
    ),
    _PreviewData(
      title: 'Recursos',
      subtitle: 'Guías y herramientas. Marca ★ para guardar.',
      icon: Icons.lightbulb_outline,
      kind: _PreviewKind.resources,
      semantics: 'Recursos prácticos con favoritos.',
    ),
    _PreviewData(
      title: 'Perfil',
      subtitle: 'Ajustes, copias y recordatorios.',
      icon: Icons.person_rounded,
      kind: _PreviewKind.profile,
      semantics: 'Preferencias, copias en Drive y progreso.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final p = _controller.page ?? _index.value.toDouble();
      _page.value = p;
      if (_showSwipeHint && (p - _index.value).abs() > 0.01) {
        setState(() => _showSwipeHint = false);
      }
    });
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seenTutorial', true);
    if (!mounted) return;

    if (widget.returnToOnboarding) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        FadeTransparentRoute(builder: (_) => const BottomNavBar()),
        (route) => false,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _index.dispose();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _finish,
            child: const Text('Saltar'),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          ValueListenableBuilder<int>(
            valueListenable: _index,
            builder: (_, i, __) => MountainBackground(pageIndex: i),
          ),
          _ParallaxDecor(page: _page),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 12),
                ValueListenableBuilder<int>(
                  valueListenable: _index,
                  builder: (_, i, __) => Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_slides.length, (j) {
                      final active = i == j;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: active ? 20 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary
                              .withValues(alpha: active ? 1 : .35),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    itemCount: _slides.length,
                    onPageChanged: (i) {
                      _index.value = i;
                      if (_showSwipeHint && i > 0) {
                        setState(() => _showSwipeHint = false);
                      }
                    },
                    physics: const BouncingScrollPhysics(),
                    itemBuilder: (_, i) {
                      final s = _slides[i];
                      return Semantics(
                        label: s.semantics,
                        child: _Slide(
                          data: s,
                          index: i,
                          onNext: () {
                            HapticFeedback.lightImpact();
                            if (i == _slides.length - 1) {
                              _finish();
                            } else {
                              _controller.nextPage(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOut,
                              );
                            }
                          },
                          onBack: i == 0
                              ? null
                              : () {
                                  HapticFeedback.selectionClick();
                                  _controller.previousPage(
                                    duration: const Duration(milliseconds: 250),
                                    curve: Curves.easeOut,
                                  );
                                },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: true,
              child: ValueListenableBuilder<int>(
                valueListenable: _index,
                builder: (_, i, __) => AnimatedOpacity(
                  duration: const Duration(milliseconds: 300),
                  opacity: (i == 0 && _showSwipeHint) ? 1 : 0,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: EdgeInsets.only(
                        bottom: 16 + MediaQuery.of(context).padding.bottom,
                      ),
                      child: const _SwipeHint(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _PreviewKind { home, diary, reflection, resources, profile }

class _PreviewData {
  final String title;
  final String subtitle;
  final IconData icon;
  final _PreviewKind kind;
  final String semantics;
  const _PreviewData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.kind,
    required this.semantics,
  });
}

class _Slide extends StatelessWidget {
  final _PreviewData data;
  final int index;
  final VoidCallback onNext;
  final VoidCallback? onBack;
  const _Slide({
    required this.data,
    required this.index,
    required this.onNext,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 6),
          Icon(data.icon, size: 64),
          const SizedBox(height: 12),
          Text(
            data.title,
            style: t.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            data.subtitle,
            style: t.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          _PreviewCard(kind: data.kind),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Atrás'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onNext,
                  icon: Icon(
                    _isLast(context) ? Icons.check_rounded : Icons.arrow_forward,
                  ),
                  label: Text(_isLast(context) ? 'Listo' : 'Siguiente'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  bool _isLast(BuildContext context) {
    final total = context
            .findAncestorStateOfType<_TutorialScreenState>()
            ?._slides
            .length ??
        0;
    return index == total - 1;
  }
}

class _ParallaxDecor extends StatelessWidget {
  final ValueListenable<double> page;
  const _ParallaxDecor({required this.page});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: page,
        builder: (_, __) {
          final p = page.value;
          return LayoutBuilder(
            builder: (_, c) {
              final w = c.maxWidth;
              final h = c.maxHeight;
              Offset off(double factorX, double factorY) =>
                  Offset((p * 12) * factorX, (p * 6) * factorY);

              return Stack(
                children: [
                  Positioned(
                    top: h * .18,
                    left: w * .12 + off(1, .6).dx,
                    child: _cloud(38),
                  ),
                  Positioned(
                    top: h * .30 + off(-.6, .4).dy,
                    right: w * .18,
                    child: _cloud(52),
                  ),
                  Positioned(
                    top: h * .55 + off(.4, -.7).dy,
                    left: w * .28,
                    child: _cloud(28),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _cloud(double size) => Container(
        width: size,
        height: size * .64,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .16),
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .12),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
      );
}

class _PreviewCard extends StatelessWidget {
  final _PreviewKind kind;
  const _PreviewCard({required this.kind});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg =
        theme.brightness == Brightness.dark ? Colors.white : Colors.black87;
    final subtle = Colors.white.withValues(alpha: .14);
    final strong = Colors.white.withValues(alpha: .24);

    late final Widget mock;
    switch (kind) {
      case _PreviewKind.home:
        mock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _pill('Días limpio', fg),
            const SizedBox(height: 10),
            Row(
              children: [
                _metricBox('1', 'año', strong, fg),
                const SizedBox(width: 8),
                _metricBox('3', 'meses', strong, fg),
                const SizedBox(width: 8),
                _metricBox('12', 'días', strong, fg),
              ],
            ),
            const SizedBox(height: 12),
            _line(fg, widthFactor: .85),
            const SizedBox(height: 6),
            _line(fg, widthFactor: .55),
            const SizedBox(height: 12),
            _chipRow([Icons.sos, Icons.air, Icons.self_improvement], subtle, fg),
          ],
        );
        break;
      case _PreviewKind.diary:
        mock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _pill('Estado de ánimo', fg),
            const SizedBox(height: 10),
            _emojiRow(),
            const SizedBox(height: 12),
            _line(fg, widthFactor: .95),
            const SizedBox(height: 6),
            _line(fg, widthFactor: .75),
            const SizedBox(height: 6),
            _line(fg, widthFactor: .55),
          ],
        );
        break;
      case _PreviewKind.reflection:
        mock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _pill('Sólo por hoy', fg),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.format_quote, color: fg.withValues(alpha: .8)),
                const SizedBox(width: 8),
                Expanded(child: _line(fg, widthFactor: .95, height: 14)),
              ],
            ),
            const SizedBox(height: 6),
            _line(fg, widthFactor: .88),
            const SizedBox(height: 6),
            _line(fg, widthFactor: .66),
          ],
        );
        break;
      case _PreviewKind.resources:
        mock = Column(
          children: [
            _resourceTile('Respiración 4‑7‑8', fg, strong, starred: true),
            const SizedBox(height: 8),
            _resourceTile('Plan para craving', fg, strong),
            const SizedBox(height: 8),
            _resourceTile('Líneas de ayuda', fg, strong),
          ],
        );
        break;
      case _PreviewKind.profile:
        mock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _pill('Preferencias', fg),
            const SizedBox(height: 8),
            _switchRow(fg, 'Notificación diaria', true),
            const SizedBox(height: 8),
            _switchRow(fg, 'Modo oscuro', true),
            const SizedBox(height: 8),
            _switchRow(fg, 'Logros', true),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.cloud_sync, color: fg),
                const SizedBox(width: 8),
                Expanded(child: _line(fg, widthFactor: .6)),
              ],
            ),
          ],
        );
        break;
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: .95, end: 1),
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      builder: (_, scale, child) => AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: 1,
        child: Transform.scale(scale: scale, child: child),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: .90),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .2),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: mock,
      ),
    );
  }

  Widget _pill(String text, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: fg.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text, style: TextStyle(color: fg)),
      );

  Widget _metricBox(String big, String small, Color bg, Color fg) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Text(
                big,
                style: TextStyle(
                  color: fg,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(small, style: TextStyle(color: fg.withValues(alpha: .8))),
            ],
          ),
        ),
      );

  Widget _line(
    Color fg, {
    double widthFactor = 1,
    double height = 12,
  }) =>
      FractionallySizedBox(
        widthFactor: widthFactor,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: fg.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );

  Widget _emojiRow() => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(5, (i) {
          final icons = [
            Icons.sentiment_very_dissatisfied,
            Icons.sentiment_dissatisfied,
            Icons.sentiment_neutral,
            Icons.sentiment_satisfied,
            Icons.sentiment_very_satisfied,
          ];
          return Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .22),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icons[i],
              color: Colors.black.withValues(alpha: .75),
              size: 26,
            ),
          );
        }),
      );

  Widget _chipRow(List<IconData> icons, Color bg, Color fg) => Row(
        children: icons
            .map(
              (ic) => Container(
                margin: const EdgeInsets.only(right: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Icon(ic, color: fg),
              ),
            )
            .toList(),
      );

  Widget _resourceTile(
    String text,
    Color fg,
    Color bg, {
    bool starred = false,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.link_rounded),
            const SizedBox(width: 8),
            Expanded(child: Text(text)),
            Icon(starred ? Icons.star_rounded : Icons.star_border_rounded),
          ],
        ),
      );

  Widget _switchRow(Color fg, String text, bool on) => Row(
        children: [
          Expanded(child: Text(text, style: TextStyle(color: fg))),
          Container(
            width: 46,
            height: 28,
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: fg.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      );
}

class _SwipeHint extends StatefulWidget {
  const _SwipeHint();

  @override
  State<_SwipeHint> createState() => _SwipeHintState();
}

class _SwipeHintState extends State<_SwipeHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac;
  late final Animation<double> _dx;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _dx = Tween<double>(begin: 0, end: 6).animate(
      CurvedAnimation(parent: _ac, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = theme.colorScheme.surface.withValues(alpha: .90);
    final fgColor = theme.colorScheme.onSurface;

    return AnimatedBuilder(
      animation: _dx,
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .18),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Desliza para ver más', style: TextStyle(color: fgColor)),
            const SizedBox(width: 8),
            Transform.translate(
              offset: Offset(_dx.value, 0),
              child: Icon(Icons.chevron_right_rounded, color: fgColor),
            ),
          ],
        ),
      ),
    );
  }
}
