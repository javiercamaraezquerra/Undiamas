// lib/screens/tutorial_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/mountain_background.dart';
import '../widgets/bottom_nav_bar.dart';
import '../routes/fade_transparent_route.dart';

class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key});

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _StepData {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> bullets;
  const _StepData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.bullets,
  });
}

class _TutorialScreenState extends State<TutorialScreen> {
  final PageController _controller = PageController();
  final ValueNotifier<int> _index = ValueNotifier(0);

  final List<_StepData> _steps = const [
    _StepData(
      title: 'Inicio',
      subtitle: 'Tu progreso, de un vistazo',
      icon: Icons.home,
      bullets: [
        'Contador limpio en años/meses/días.',
        'Frase motivacional del día (offline).',
        'Botón SOS con respiración/relajación.',
      ],
    ),
    _StepData(
      title: 'Diario',
      subtitle: 'Pon en palabras cómo te sientes',
      icon: Icons.edit,
      bullets: [
        'Marca tu estado de ánimo (0‑4).',
        'Escribe y guarda (cifrado con Hive).',
        'Consulta el historial cuando quieras.',
      ],
    ),
    _StepData(
      title: 'Reflexión',
      subtitle: '“Sólo por hoy”',
      icon: Icons.auto_stories,
      bullets: [
        'Reflexión diaria para centrar el día.',
        'Activa recordatorios diarios si quieres.',
        'Accesos a recursos útiles al final.',
      ],
    ),
    _StepData(
      title: 'Recursos',
      subtitle: 'Herramientas y guías prácticas',
      icon: Icons.lightbulb_outline,
      bullets: [
        'Filtra por categoría o busca por texto.',
        'Marca ★ para guardar favoritos.',
        'Los enlaces se abren fuera por seguridad.',
      ],
    ),
    _StepData(
      title: 'Perfil',
      subtitle: 'Ajustes, copias y progreso',
      icon: Icons.person,
      bullets: [
        'Modo oscuro, notificaciones y logros.',
        'Copias en Google Drive y restauración.',
        'Tendencia de ánimo y reinicio del contador.',
      ],
    ),
  ];

  Future<void> _finishToApp() async {
    // Guardamos flag por si lo quieres usar más adelante
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seenTutorial', true);

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      FadeTransparentRoute(builder: (_) => const BottomNavBar()),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _index.dispose();
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
            onPressed: _finishToApp,
            child: const Text('Saltar'),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Fondo coherente con la app
          ValueListenableBuilder<int>(
            valueListenable: _index,
            builder: (_, i, __) => MountainBackground(pageIndex: i),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 12),
                // Indicador de progreso
                ValueListenableBuilder<int>(
                  valueListenable: _index,
                  builder: (_, i, __) => Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_steps.length, (j) {
                      final active = i == j;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: active ? 20 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: active
                              ? theme.colorScheme.primary
                              : theme.colorScheme.primary.withOpacity(.3),
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
                    itemCount: _steps.length,
                    onPageChanged: (i) => _index.value = i,
                    itemBuilder: (_, i) {
                      final s = _steps[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const SizedBox(height: 12),
                            Icon(s.icon, size: 64),
                            const SizedBox(height: 12),
                            Text(
                              s.title,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              s.subtitle,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(color: theme.hintColor),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            Card(
                              elevation: 1,
                              margin: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (final b in s.bullets) ...[
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(
                                            height: 24,
                                            width: 24,
                                            child: Icon(Icons.check_circle_outline),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              b,
                                              style: theme.textTheme.bodyLarge,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const Spacer(),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: i == 0
                                        ? null
                                        : () => _controller.previousPage(
                                              duration: const Duration(milliseconds: 250),
                                              curve: Curves.easeOut,
                                            ),
                                    icon: const Icon(Icons.arrow_back),
                                    label: const Text('Atrás'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: i == _steps.length - 1
                                        ? _finishToApp
                                        : () => _controller.nextPage(
                                              duration: const Duration(milliseconds: 250),
                                              curve: Curves.easeOut,
                                            ),
                                    icon: Icon(
                                      i == _steps.length - 1
                                          ? Icons.check
                                          : Icons.arrow_forward,
                                    ),
                                    label: Text(
                                      i == _steps.length - 1
                                          ? 'Empezar ahora'
                                          : 'Siguiente',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
