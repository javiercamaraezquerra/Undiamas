import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../routes/fade_transparent_route.dart';
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
  static const _boxName = 'udm_secure';

  late Box _box;
  StreamSubscription<BoxEvent>? _sub;
  DateTime? _startDate;
  Duration _elapsed = Duration.zero;
  late Timer _ticker;

  String _quote = '';
  int _lastQuoteDay = -1;

  /* ───────── Ciclo de vida ───────── */
  @override
  void initState() {
    super.initState();
    _initDates().then((_) {
      _updateElapsed();
      _ticker =
          Timer.periodic(const Duration(minutes: 1), (_) => _updateElapsed());

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

  /* ───────── Carga / migración ───────── */
  Future<void> _initDates() async {
    final cipher = await EncryptionService.getCipher();
    _box = await Hive.openBox(_boxName, encryptionCipher: cipher);

    if (_box.containsKey('startDate')) {
      _startDate = DateTime.parse(_box.get('startDate') as String);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
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

  Future<void> _loadQuote(int day) async {
    final data = await rootBundle.loadString('assets/data/quotes.json');
    final list = jsonDecode(data) as List<dynamic>;
    if (list.isEmpty) return;
    setState(() => _quote = list[day % list.length] as String);
  }

  /* ───────── Círculo estilo glass chip ───────── */
  Widget _circle(String value, String label, double size, BuildContext ctx) {
    final border = Colors.white.withOpacity(.40);
    final c1 = Colors.white.withOpacity(.60);
    final c2 = Colors.white.withOpacity(.25);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [c1, c2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: border, width: 1.4),
        boxShadow: const [
          BoxShadow(
            blurRadius: 12,
            spreadRadius: 1,
            color: Colors.black26,
            offset: Offset(0, 4),
          ),
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
                    color: Colors.black87)),
            const SizedBox(height: 2),
            Text(label,
                style: Theme.of(ctx)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.black87)),
          ],
        ),
      ),
    );
  }

  /* ───────── utilidades tiempo ───────── */
  DateTime _clippedDate(DateTime start, int addY, int addM) {
    final baseMonth = start.month + addM;
    final y = start.year + addY + (baseMonth - 1) ~/ 12;
    final m = ((baseMonth - 1) % 12) + 1;
    final lastDay = DateTime(y, m + 1, 0).day;
    final d = start.day <= lastDay ? start.day : lastDay;
    return DateTime(y, m, d, start.hour, start.minute, start.second);
  }

  _YearMonth _yearsMonthsFrom(DateTime start, DateTime now) {
    int y = now.year - start.year;
    int m = now.month - start.month;
    if (m < 0) {
      y--;
      m += 12;
    }
    final candidate = _clippedDate(start, y, m);
    if (now.isBefore(candidate)) {
      if (m == 0) {
        y--;
        m = 11;
      } else {
        m--;
      }
    }
    if (y < 0) y = 0;
    return _YearMonth(y, m);
  }

  /* ───────── Build ───────── */
  @override
  Widget build(BuildContext context) {
    if (_startDate == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final now = DateTime.now();
    final ym = _yearsMonthsFrom(_startDate!, now);
    final anchor = _clippedDate(_startDate!, ym.years, ym.months);
    final after = now.difference(anchor);

    final days = after.inDays;
    final hours = after.inHours % 24;
    final minutes = after.inMinutes % 60;

    double mainSize;
    if (ym.years > 0) {
      mainSize = 110;
    } else if (ym.months > 0) {
      mainSize = 140;
    } else {
      mainSize = 180;
    }

    final circles = <Widget>[
      if (ym.years > 0)
        _circle(ym.years.toString(), ym.years == 1 ? 'año' : 'años', mainSize,
            context),
      if (ym.months > 0 || ym.years > 0)
        _circle(ym.months.toString(), ym.months == 1 ? 'mes' : 'meses',
            mainSize, context),
      _circle(days.toString(), days == 1 ? 'día' : 'días', mainSize, context),
    ];

    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Inicio'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 20,
                  runSpacing: 20,
                  children: circles,
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _circle(hours.toString().padLeft(2, '0'), 'horas', 90,
                        context),
                    const SizedBox(width: 16),
                    _circle(minutes.toString().padLeft(2, '0'), 'min', 90,
                        context),
                  ],
                ),
                const SizedBox(height: 32),
                if (_quote.isNotEmpty) ...[
                  Card(
                    color: dark
                        ? Colors.black.withOpacity(.75)
                        : Colors.white.withOpacity(.80),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _quote,
                        style: TextStyle(
                            fontSize: 18,
                            fontStyle: FontStyle.italic,
                            color: dark ? Colors.white : Colors.grey.shade800),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: dark
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.primary,
                    foregroundColor: dark
                        ? theme.colorScheme.onPrimaryContainer
                        : Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 48, vertical: 12),
                    shape: const StadiumBorder(),
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    FadeTransparentRoute(builder: (_) => const SosScreen()),
                  ),
                  child: const Text('Necesito ayuda'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
