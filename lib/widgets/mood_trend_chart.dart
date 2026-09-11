import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../models/diary_entry.dart';
import '../utils/mood_timeline.dart';
import 'mood_entry_detail_sheet.dart';

/// Read-only timeline. Filters and entry details never write to the Inventory.
class MoodTrendChart extends StatefulWidget {
  const MoodTrendChart(
      {super.key,
      required this.entries,
      this.now,
      this.invalidationSignal,
      this.entriesAvailable = true});
  final List<DiaryEntry> entries;
  final DateTime Function()? now;
  final Listenable? invalidationSignal;
  final bool entriesAvailable;
  @override
  State<MoodTrendChart> createState() => _MoodTrendChartState();
}

class _MoodTrendChartState extends State<MoodTrendChart>
    with WidgetsBindingObserver {
  MoodPeriod _period = MoodPeriod.month;
  late List<DiaryEntry> _snapshot;
  int _revision = 0;
  _DetailSession? _detail;

  @override
  void initState() {
    super.initState();
    _snapshot = List.of(widget.entries);
    widget.invalidationSignal?.addListener(_invalidateDetail);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant MoodTrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.invalidationSignal != widget.invalidationSignal) {
      oldWidget.invalidationSignal?.removeListener(_invalidateDetail);
      widget.invalidationSignal?.addListener(_invalidateDetail);
    }
    if (oldWidget.entriesAvailable != widget.entriesAvailable ||
        _snapshot.length != widget.entries.length ||
        Iterable<int>.generate(_snapshot.length)
            .any((i) => !identical(_snapshot[i], widget.entries[i]))) {
      _invalidateDetail();
    }
    _snapshot = List.of(widget.entries);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // Re-evaluate the local date and time zone, without a repeating timer.
      _invalidateDetail();
      setState(() {});
    }
  }

  void _invalidateDetail() {
    _revision++;
    _detail?.invalidate();
  }

  @override
  void dispose() {
    widget.invalidationSignal?.removeListener(_invalidateDetail);
    WidgetsBinding.instance.removeObserver(this);
    _detail?.invalidate(notify: false);
    super.dispose();
  }

  void _selectPeriod(MoodPeriod period) {
    if (_period == period) return;
    _invalidateDetail();
    setState(() => _period = period);
  }

  Future<void> _openEntries(List<MoodTimelinePoint> points,
      {int? initialSourceIndex, required int revision}) async {
    if (!mounted ||
        !widget.entriesAvailable ||
        revision != _revision ||
        points.isEmpty ||
        _detail != null) {
      return;
    }
    final session = _DetailSession();
    _detail = session;
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        builder: (sheetContext) {
          session.attach(ModalRoute.of(sheetContext));
          return AnimatedBuilder(
            animation: session,
            builder: (_, __) => session.valid
                ? MoodEntryDetailSheet(
                    key: const ValueKey('mood-entry-sheet'),
                    points: points,
                    initialSourceIndex: initialSourceIndex)
                : const SizedBox.shrink(),
          );
        },
      );
    } finally {
      if (identical(_detail, session)) _detail = null;
      session.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeline = MoodTimeline.build(widget.entries,
        period: _period, now: (widget.now ?? DateTime.now)());
    final revision = _revision;
    final points = timeline.points;
    final invalidMoods = points.where((p) => !hasReadableMood(p.entry)).length;
    final secondary = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _periodControls(context),
          const SizedBox(height: 12),
          if (!widget.entriesAvailable)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                    'El Inventario no está disponible mientras se actualiza.',
                    textAlign: TextAlign.center))
          else ...[
            Text(
                '${moodDateLabel(timeline.startDay)} – '
                '${moodDateLabel(timeline.endDay)} · '
                '${points.length} ${points.length == 1 ? 'entrada' : 'entradas'}',
                key: const ValueKey('mood-period-summary'),
                style: secondary),
            const SizedBox(height: 16),
            if (points.isEmpty)
              Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 30, horizontal: 8),
                  child: Column(children: [
                    Text(
                        widget.entries.isEmpty
                            ? 'Todavía no hay entradas para mostrar tu ánimo.'
                            : 'No hay entradas en ${_period == MoodPeriod.week ? 'estos 7 días' : _period == MoodPeriod.month ? 'estos 30 días' : 'este periodo'}.',
                        textAlign: TextAlign.center),
                    if (widget.entries.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text('Puedes consultar otro periodo.',
                          textAlign: TextAlign.center),
                    ],
                  ]))
            else ...[
              if (invalidMoods < points.length)
                _plot(context, timeline, revision)
              else
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                        'El ánimo de estas entradas no está disponible.',
                        textAlign: TextAlign.center)),
              const SizedBox(height: 12),
              Text(
                  timeline.hasGaps
                      ? 'Los huecos indican días sin registros.'
                      : 'Cada punto es una entrada del Inventario.',
                  style: secondary),
              Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                      key: const ValueKey('mood-view-entries'),
                      onPressed: () => _openEntries(points, revision: revision),
                      icon: const Icon(Icons.list_alt, size: 20),
                      label: const Text('Ver entradas'))),
            ],
            if (invalidMoods > 0)
              const Text(
                  'Hay entradas sin un ánimo válido. Puedes leerlas en «Ver entradas».'),
            if (timeline.skippedEntryCount > 0)
              const Text(
                  'Hay fechas que no se pueden representar en la gráfica. El Inventario se conserva.'),
          ],
        ]);
  }

  Widget _periodControls(BuildContext context) {
    const labels = {
      MoodPeriod.week: '7 días',
      MoodPeriod.month: '30 días',
      MoodPeriod.all: 'Todo'
    };
    return LayoutBuilder(builder: (context, constraints) {
      // At large text sizes the same controls can wrap without truncation.
      final scaledLabel = MediaQuery.textScalerOf(context).scale(14);
      if (constraints.maxWidth >= 245 * scaledLabel / 14) {
        return SegmentedButton<MoodPeriod>(
            showSelectedIcon: false,
            segments: [
              for (final pair in labels.entries)
                ButtonSegment(value: pair.key, label: Text(pair.value))
            ],
            selected: {_period},
            onSelectionChanged: (value) => _selectPeriod(value.single));
      }
      return Wrap(spacing: 8, runSpacing: 4, children: [
        for (final pair in labels.entries)
          ChoiceChip(
              label: Text(pair.value),
              selected: _period == pair.key,
              showCheckmark: false,
              onSelected: (_) => _selectPeriod(pair.key)),
      ]);
    });
  }

  Widget _plot(BuildContext context, MoodTimeline timeline, int revision) {
    final theme = Theme.of(context);
    final segments = <List<MoodTimelinePoint>>[];
    // Keep invalid moods readable, but do not plot or bridge across them.
    for (final segment in timeline.segments) {
      var valid = <MoodTimelinePoint>[];
      for (final point in segment) {
        if (hasReadableMood(point.entry)) {
          valid.add(point);
        } else if (valid.isNotEmpty) {
          segments.add(valid);
          valid = [];
        }
      }
      if (valid.isNotEmpty) segments.add(valid);
    }
    final scale = MediaQuery.textScalerOf(context);
    final axisWidth = scale.scale(18) + 20;
    final bars = [
      for (final segment in segments)
        LineChartBarData(
            spots: [
              for (final point in segment)
                FlSpot(point.x, point.entry.mood.toDouble())
            ],
            isCurved: false,
            color: theme.colorScheme.primary,
            barWidth: 1.2,
            belowBarData: BarAreaData(show: false),
            dotData: FlDotData(
                show: true,
                getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                    radius: timeline.points.length > 100 ? 1.8 : 3,
                    color: theme.colorScheme.primary,
                    strokeWidth: 0))),
    ];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Semantics(
          label: 'Gráfica de ${timeline.points.length} entradas. '
              'Usa Ver entradas para consultar cada fecha, hora y texto.',
          child: ExcludeSemantics(
              child: SizedBox(
            height: 220 + (scale.scale(18) - 18).clamp(0, 54) * 4,
            child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: timeline.maxX,
                  minY: -.2,
                  maxY: 4.2,
                  gridData: FlGridData(
                      drawVerticalLine: false,
                      horizontalInterval: 1,
                      getDrawingHorizontalLine: (_) => FlLine(
                          color: theme.dividerColor.withAlpha(46),
                          strokeWidth: 1,
                          dashArray: [6, 3])),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: axisWidth,
                              interval: 1,
                              getTitlesWidget: (value, _) {
                                if (value < 0 ||
                                    value > 4 ||
                                    value != value.round()) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: Text(moodEmojis[value.toInt()],
                                        style: const TextStyle(fontSize: 18)));
                              }))),
                  lineBarsData: bars,
                  lineTouchData: LineTouchData(
                      handleBuiltInTouches: false,
                      touchSpotThreshold: 24,
                      distanceCalculator: (touch, spot) =>
                          (touch - spot).distance,
                      touchCallback: (event, response) {
                        if (event is! FlTapUpEvent &&
                            event is! FlLongPressStart) {
                          return;
                        }
                        final touched = response?.lineBarSpots;
                        if (revision != _revision ||
                            touched == null ||
                            touched.isEmpty) {
                          return;
                        }
                        final hit = touched.first;
                        if (hit.barIndex < 0 ||
                            hit.barIndex >= segments.length ||
                            hit.spotIndex < 0 ||
                            hit.spotIndex >= segments[hit.barIndex].length) {
                          return;
                        }
                        final point = segments[hit.barIndex][hit.spotIndex];
                        if (hit.x != point.x || hit.y != point.entry.mood) {
                          return;
                        }
                        _openEntries(timeline.pointsOnDay(point.localDateTime),
                            initialSourceIndex: point.sourceIndex,
                            revision: revision);
                      }),
                ),
                duration: Duration.zero),
          ))),
      Padding(
          padding: EdgeInsets.only(left: axisWidth, top: 6),
          child: LayoutBuilder(builder: (context, constraints) {
            if (constraints.maxWidth >= 240 &&
                scale.scale(12) <= 15 &&
                timeline.maxX >= 4) {
              final dayOffsets = [
                0,
                (timeline.maxX / 3).floor(),
                (timeline.maxX * 2 / 3).floor(),
                timeline.maxX.floor() - 1
              ];
              return SizedBox(
                  height: scale.scale(12) * 1.8,
                  child: Stack(children: [
                    for (var i = 0; i < dayOffsets.length; i++)
                      Positioned(
                        left: i == 0
                            ? 0
                            : i == 3
                                ? constraints.maxWidth - 60
                                : constraints.maxWidth *
                                        dayOffsets[i] /
                                        timeline.maxX -
                                    30,
                        width: 60,
                        child: Builder(builder: (_) {
                          final date = DateTime.utc(
                              timeline.startDay.year,
                              timeline.startDay.month,
                              timeline.startDay.day + dayOffsets[i]);
                          return Text('${date.day}/${date.month}',
                              textAlign: i == 0
                                  ? TextAlign.start
                                  : i == 3
                                      ? TextAlign.end
                                      : TextAlign.center,
                              style: theme.textTheme.bodySmall);
                        }),
                      ),
                  ]));
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  child: Text(moodDateLabel(timeline.startDay, short: true),
                      style: theme.textTheme.bodySmall)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(moodDateLabel(timeline.endDay, short: true),
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall)),
            ]);
          })),
    ]);
  }
}

/// Invalidate first, then remove this exact route. A restoration dialog may be
/// above the sheet, so a generic Navigator.pop could close the wrong route.
class _DetailSession extends ChangeNotifier {
  bool valid = true;
  bool _disposed = false;
  bool _scheduled = false;
  ModalRoute<dynamic>? _route;

  void attach(ModalRoute<dynamic>? route) {
    _route = route;
    if (!valid) _scheduleClose();
  }

  void invalidate({bool notify = true}) {
    if (_disposed) return;
    final wasValid = valid;
    valid = false;
    if (notify &&
        wasValid &&
        SchedulerBinding.instance.schedulerPhase !=
            SchedulerPhase.persistentCallbacks) {
      notifyListeners();
    }
    _scheduleClose();
  }

  void _scheduleClose() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (_disposed || valid) return;
      final route = _route;
      final navigator = route?.navigator;
      if (route != null &&
          route.isActive &&
          navigator != null &&
          navigator.mounted) {
        navigator.removeRoute(route);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
