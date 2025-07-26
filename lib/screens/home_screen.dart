import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/encryption_service.dart';
import 'sos_screen.dart';

/* ───────── helper simple ───────── */
class _YearMonth {
  final int years;
  final int months;
  const _YearMonth(this.years, this.months);
}

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

      // Escucha cambios en la clave 'startDate'
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

  /* ───────── Actualiza duración y frase ───────── */
  void _updateElapsed() {
    if (_startDate == null) return;
    final diff = DateTime.now().difference(_startDate!);

    if (diff.inDays != _lastQuoteDay) {
      _loadQuote(diff.inDays);
      _lastQuoteDay = diff.inDays;
    }
    setState(() => _elapsed = diff);
  }

  Future<void> _loadQuote(int dayIndex) async {
    final data = await rootBundle.loadString('assets/data/quotes.json');
    final list = jsonDecode(data) as List<dynamic>;
    if (list.isEmpty) return;
    setState(() => _quote = list[dayIndex % list.length] as String);
  }

  /* ───────── Círculo reutilizable ───────── */
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
            Text(value,
                style: TextStyle(
                    fontSize: size * 0.35,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(ctx).colorScheme.primary)),
            const SizedBox(height: 2),
            Text(label, style: Theme.of(ctx).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  /* ───────── Años + meses desde inicio ───────── */
  _YearMonth _yearsMonthsFrom(DateTime start, DateTime now) {
    int years  = now.year  - start.year;
    int months = now.month - start.month;

    if (now.day < start.day) months--; // mes incompleto

    if (months < 0) {
      years--;
      months += 12;
    }
    if (years < 0) years = 0;
    return _YearMonth(years, months);
  }

  /* ───────── Build ───────── */
  @override
  Widget build(BuildContext context) {
    if (_startDate == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final now          = DateTime.now();
    final ym           = _yearsMonthsFrom(_startDate!, now);
    final years        = ym.years;
    final monthsAll    = ym.months;

    // restamos años+meses completos para calcular días/horas/min
    DateTime tmp = DateTime(
      _startDate!.year + years,
      _startDate!.month + monthsAll,
      _startDate!.day,
      _startDate!.hour,
      _startDate!.minute,
      _startDate!.second,
    );
    final durAfter = now.difference(tmp);

    final days    = durAfter.inDays;
    final hours   = durAfter.inHours % 24;
    final minutes = durAfter.inMinutes % 60;

    /* tamaño adaptativo */
    double mainSize;
    if (years > 0) {
      mainSize = 110;
    } else if (monthsAll > 0) {
      mainSize = 140;
    } else {
      mainSize = 180;
    }

    /* lista dinámica de círculos */
    final List<Widget> mainCircles = [];
    if (years > 0) {
      mainCircles.add(_circle(
          years.toString(), years == 1 ? 'año' : 'años', mainSize, context));
    }
    if (monthsAll > 0 || years > 0) {
      mainCircles.add(_circle(monthsAll.toString(),
          monthsAll == 1 ? 'mes' : 'meses', mainSize, context));
    }
    mainCircles.add(_circle(days.toString(), days == 1 ? 'día' : 'días',
        mainSize, context));

    return Scaffold(
      appBar: AppBar(title: const Text('Inicio')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 20,
                runSpacing: 20,
                children: mainCircles,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _circle(hours.toString().padLeft(2, '0'),
                      'horas', 90, context),
                  const SizedBox(width: 16),
                  _circle(minutes.toString().padLeft(2, '0'),
                      'min', 90, context),
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
                    child: Text(_quote,
                        style: const TextStyle(
                            fontSize: 18, fontStyle: FontStyle.italic),
                        textAlign: TextAlign.center),
                  ),
                ),
                const SizedBox(height: 32),
              ],
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 48, vertical: 12),
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
