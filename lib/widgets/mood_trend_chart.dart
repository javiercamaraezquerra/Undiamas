import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/diary_entry.dart';
import '../utils/mood_trend.dart';

class MoodTrendChart extends StatelessWidget {
  final List<DiaryEntry> entries;
  const MoodTrendChart({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final spots  = moodSpots(entries);
    final df     = DateFormat('d/M/yy');
    final maxX   = (spots.length - 1).clamp(0, double.infinity).toDouble();
    final first  = entries.isNotEmpty ? df.format(entries.first.createdAt) : '';
    final last   = entries.isNotEmpty ? df.format(entries.last.createdAt)  : '';
    const emojis = ['😢', '😕', '😐', '🙂', '😄'];

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX < 1 ? 1 : maxX,
        minY: 0,
        maxY: 4,
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: 1,
          getDrawingHorizontalLine: (v) => FlLine(
            strokeWidth: 1,
            dashArray: [6, 3],
            color: theme.dividerColor.withAlpha(0x2E), // 18 %
          ),
        ),
        titlesData: FlTitlesData(
          topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              reservedSize: 32,
              showTitles: true,
              getTitlesWidget: (val, _) =>
                  (val < 0 || val > 4)
                      ? const SizedBox.shrink()
                      : Text(emojis[val.toInt()],
                          style: const TextStyle(fontSize: 16)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              reservedSize: 32,
              showTitles: true,
              getTitlesWidget: (val, meta) {
                if (meta.max == 0) return const SizedBox.shrink();
                if (val == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 4, left: 4),
                    child: Text(first, style: const TextStyle(fontSize: 12)),
                  );
                }
                if (val == meta.max) {
                  return SizedBox(
                    width: 48,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 4, right: 4),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(last,
                            style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        borderData:
            FlBorderData(show: true, border: Border.all(color: theme.dividerColor)),
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: theme.colorScheme.surface,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (touched) => touched.map((t) {
              final idx   = t.x.toInt();
              final entry = entries[idx];
              final emoji = emojis[t.y.round()];
              return LineTooltipItem(
                '$emoji  (${t.y.toInt()})\n${df.format(entry.createdAt)}',
                TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 12,
                ),
              );
            }).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: theme.colorScheme.primary,
            barWidth: 1.2,
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary.withAlpha(0x29), // 16 %
                  theme.colorScheme.primary.withAlpha(0x0A), //  4 %
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            dotData: FlDotData(
              show: true,
              getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                radius: 2,
                color: theme.colorScheme.primary,
                strokeWidth: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
