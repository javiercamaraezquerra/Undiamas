import 'package:fl_chart/fl_chart.dart';
import '../models/diary_entry.dart';

/// Convierte las entradas en puntos (x = índice, y = mood 0‑4)
List<FlSpot> moodSpots(List<DiaryEntry> entries) {
  if (entries.isEmpty) return [const FlSpot(0, 2)];
  return List<FlSpot>.generate(
    entries.length,
    (i) => FlSpot(i.toDouble(), entries[i].mood.toDouble()),
  );
}

/// Resultado de la recta de tendencia
class TrendFit {
  final double m;   // pendiente
  TrendFit(this.m);
}

/// Ajuste lineal clásico. Devuelve null si hay < 2 puntos.
TrendFit? linearFit(List<FlSpot> s) {
  if (s.length < 2) return null;
  final n   = s.length;
  final sx  = s.fold<double>(0, (v, p) => v + p.x);
  final sy  = s.fold<double>(0, (v, p) => v + p.y);
  final sxx = s.fold<double>(0, (v, p) => v + p.x * p.x);
  final sxy = s.fold<double>(0, (v, p) => v + p.x * p.y);

  final denom = n * sxx - sx * sx;
  if (denom == 0) return null;

  final m = (n * sxy - sx * sy) / denom;
  return TrendFit(m);
}

/// +1 mejora, −1 empeora, 0 estable, null insuficiente
int? moodTrendSign(List<DiaryEntry> entries) {
  final fit = linearFit(moodSpots(entries));
  if (fit == null) return null;
  if (fit.m >  0.05) return  1;
  if (fit.m < -0.05) return -1;
  return 0;
}
