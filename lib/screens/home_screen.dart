import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/encryption_service.dart';          // ← nuevo
import 'sos_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _prefsKey = 'start_date';
  static const _boxName  = 'udm_secure';

  late Box _box;
  StreamSubscription<BoxEvent>? _sub;
  DateTime? _startDate;
  Duration _elapsed = Duration.zero;
  late Timer _ticker;

  String _quote = '';
  int _lastQuoteDay = -1;

  /* ───────── Ciclo de vida ───────── */
  @override
  void initState() {
    super.initState();
    _initDates().then((_) {
      _updateElapsed();
      _ticker =
          Timer.periodic(const Duration(minutes: 1), (_) => _updateElapsed());

      // Escucha cambios en la clave 'startDate' para refrescar al instante
      _sub = _box.watch(key: 'startDate').listen((e) {
        _startDate = DateTime.parse(e.value as String);
        _updateElapsed();
      });
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    _sub?.cancel();
    super.dispose();
  }

  /* ───────── Carga (y migración) de fecha ───────── */
  Future<void> _initDates() async {
    final cipher = await EncryptionService.getCipher();
    _box = await Hive.openBox(_boxName, encryptionCipher: cipher);

    if (_box.containsKey('startDate')) {
      _startDate = DateTime.parse(_box.get('startDate') as String);
      return;
    }

    // Migración desde SharedPreferences (versiones ≤ 1.0.6)
    final prefs  = await SharedPreferences.getInstance();
    final legacy = prefs.getString(_prefsKey);

    if (legacy != null) {
      _startDate = DateTime.parse(legacy);
      await _box.put('startDate', legacy);
      await prefs.remove(_prefsKey);
    } else {
      _startDate = DateTime.now();
      await _box.put('startDate', _startDate!.toIso8601String());
    }
  }

  /* ───────── Cálculo del tiempo transcurrido ───────── */
  void _updateElapsed() {
    if (_startDate == null) return;
    final diff = DateTime.now().difference(_startDate!);

    if (diff.inDays != _lastQuoteDay) {
      _loadQuote(diff.inDays);
      _lastQuoteDay = diff.inDays;
    }
    setState(() => _elapsed = diff);
  }

  /* ───────── Frase motivacional diaria ───────── */
  Future<void> _loadQuote(int dayIndex) async {
    final data = await rootBundle.loadString('assets/data/quotes.json');
    final list = jsonDecode(data) as List<dynamic>;
    if (list.isEmpty) return;
    setState(() => _quote = list[dayIndex % list.length] as String);
  }

  /* ───────── Widget auxiliar: círculo contador ───────── */
  Widget _circle(String value, String label, double size, BuildContext ctx) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(ctx).colorScheme.surface,
        boxShadow: const [
          BoxShadow(blurRadius: 8, spreadRadius: 1, color: Colors.black12),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: size * 0.35,
                fontWeight: FontWeight.bold,
                color: Theme.of(ctx).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(ctx).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  /* ───────── Build ───────── */
  @override
  Widget build(BuildContext context) {
    final days    = _elapsed.inDays;
    final hours   = _elapsed.inHours % 24;
    final minutes = _elapsed.inMinutes % 60;

    return Scaffold(
      appBar: AppBar(title: const Text('Inicio')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _circle('$days', 'días', 180, context),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _circle(hours.toString().padLeft(2, '0'), 'horas', 90, context),
                  const SizedBox(width: 16),
                  _circle(minutes.toString().padLeft(2, '0'), 'min', 90, context),
                ],
              ),
              const SizedBox(height: 32),
              if (_quote.isNotEmpty) ...[
                Card(
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _quote,
                      style: const TextStyle(
                          fontSize: 18, fontStyle: FontStyle.italic),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 48, vertical: 12),
                  shape: const StadiumBorder(),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SosScreen()),
                ),
                child: const Text('Necesito ayuda'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
