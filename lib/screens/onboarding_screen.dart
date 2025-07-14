import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

import '../widgets/bottom_nav_bar.dart';
import '../services/achievement_service.dart';
import '../services/encryption_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageCtrl = PageController();
  DateTime? _startDateTime;
  String? _substance;
  final _options = [
    'Alcohol',
    'Hachís',
    'Cannabis',
    'Heroína',
    'Cocaína',
    'Varias'
  ];

  /* ───────── Guardar y entrar ───────── */
  Future<void> _finish() async {
    final cipher = await EncryptionService.getCipher();
    final box = await Hive.openBox('udm_secure', encryptionCipher: cipher);

    await box.putAll({
      'startDate': _startDateTime!.toIso8601String(),
      'substance': _substance,
    });

    await AchievementService.scheduleMilestones(_startDateTime!);

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const BottomNavBar()),
    );
  }

  /* ───────── Selección fecha y hora ───────── */
  Future<void> _pickDateTime() async {
    final pickedDate = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDate: DateTime.now(),
    );
    if (!mounted || pickedDate == null) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (!mounted || pickedTime == null) return;

    setState(() {
      _startDateTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });

    await _pageCtrl.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.ease,
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: PageView(
        controller: _pageCtrl,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          /* ── PASO 1 ── */
          _StepContainer(
            headline: 'Selecciona la fecha y hora\nde tu sobriedad',
            center: ElevatedButton.icon(
              icon: const Icon(Icons.calendar_month_outlined),
              label: const Text('Elegir fecha y hora'),
              onPressed: _pickDateTime,
            ),
            subhead: _startDateTime == null
                ? null
                : 'Elegido: ${_startDateTime!.day}/${_startDateTime!.month}/${_startDateTime!.year} – '
                    '${_startDateTime!.hour.toString().padLeft(2, '0')}:'
                    '${_startDateTime!.minute.toString().padLeft(2, '0')}',
          ),

          /* ── PASO 2 ── */
          _StepContainer(
            headline: '¿Cuál es tu sustancia principal?',
            center: Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: _options
                  .map(
                    (e) => ChoiceChip(
                      label: Text(e),
                      selected: _substance == e,
                      selectedColor: color.withAlpha(0x26), // 15 %
                      onSelected: (_) => setState(() => _substance = e),
                    ),
                  )
                  .toList(),
            ),
            bottom: ElevatedButton(
              onPressed: _substance == null
                  ? null
                  : () => _pageCtrl.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.ease,
                      ),
              child: const Text('Siguiente'),
            ),
          ),

          /* ── PASO 3 ── */
          _StepContainer(
            headline: '¡Todo listo!',
            subhead: 'Recibirás frases motivacionales cada mañana.',
            center: Icon(
              Icons.celebration_rounded,
              size: 96,
              color: color.withAlpha(0xCC), // 80 %
            ),
            bottom: ElevatedButton(
              onPressed:
                  (_startDateTime != null && _substance != null) ? _finish : null,
              child: const Text('Comenzar'),
            ),
          ),
        ],
      ),
    );
  }
}

/* ───────── Contenedor genérico ───────── */
class _StepContainer extends StatelessWidget {
  final String headline;
  final String? subhead;
  final Widget center;
  final Widget? bottom;

  const _StepContainer({
    super.key,
    required this.headline,
    this.subhead,
    required this.center,
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(headline,
              style: textTheme.headlineMedium, textAlign: TextAlign.center),
          if (subhead != null) ...[
            const SizedBox(height: 8),
            Text(subhead!,
                style: textTheme.bodyMedium, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 36),
          center,
          if (bottom != null) ...[
            const SizedBox(height: 48),
            bottom!,
          ],
        ],
      ),
    );
  }
}
