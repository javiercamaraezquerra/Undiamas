import 'package:flutter/material.dart';
import '../models/diary_entry.dart';
import '../utils/mood_timeline.dart';
import 'inventory_photo_attachment.dart';

const moodEmojis = ['😢', '😕', '😐', '🙂', '😄'];
const _moodLabels = ['Muy bajo', 'Bajo', 'Neutro', 'Bueno', 'Muy bueno'];
const _months = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sept',
  'oct',
  'nov',
  'dic'
];
bool hasReadableMood(DiaryEntry entry) => entry.mood >= 0 && entry.mood < 5;
String moodDateLabel(DateTime date, {bool short = false}) => short
    ? '${date.day}/${date.month}/${date.year}'
    : '${date.day} ${_months[date.month - 1]} ${date.year}';
String _time(DateTime date) => '${date.hour.toString().padLeft(2, '0')}:'
    '${date.minute.toString().padLeft(2, '0')}';
String _mood(DiaryEntry entry) =>
    hasReadableMood(entry) ? moodEmojis[entry.mood] : '—';
String _moodDescription(DiaryEntry entry) => hasReadableMood(entry)
    ? 'Ánimo: ${_moodLabels[entry.mood]}'
    : 'Ánimo no disponible';

/// Displays snapshots only; no storage, editing, or persistence.
class MoodEntryDetailSheet extends StatefulWidget {
  const MoodEntryDetailSheet(
      {super.key, required this.points, this.initialSourceIndex});
  final List<MoodTimelinePoint> points;
  final int? initialSourceIndex;
  @override
  State<MoodEntryDetailSheet> createState() => _MoodEntryDetailSheetState();
}

class _MoodEntryDetailSheetState extends State<MoodEntryDetailSheet> {
  MoodTimelinePoint? _selected;
  final _scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    for (final point in widget.points) {
      if (point.sourceIndex == widget.initialSourceIndex) _selected = point;
    }
  }

  void _select(MoodTimelinePoint? point) {
    setState(() => _selected = point);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selected;
    final sameDay = widget.points.every((point) =>
        point.localDateTime.year == widget.points.first.localDateTime.year &&
        point.localDateTime.month == widget.points.first.localDateTime.month &&
        point.localDateTime.day == widget.points.first.localDateTime.day);
    final compact = selected != null &&
        selected.entry.photoId == null &&
        selected.entry.text.length < 300 &&
        MediaQuery.textScalerOf(context).scale(16) <= 20 &&
        MediaQuery.sizeOf(context).height >= 650;
    return FractionallySizedBox(
        heightFactor: compact ? .62 : .85,
        child: SafeArea(
            top: false,
            child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(
                                selected == null
                                    ? 'Entradas del periodo'
                                    : 'Entrada del Inventario',
                                style: theme.textTheme.titleMedium)),
                        IconButton(
                            tooltip: 'Cerrar',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close)),
                      ]),
                      const SizedBox(height: 8),
                      Expanded(
                          child: selected == null
                              ? _entryList()
                              : SingleChildScrollView(
                                  key: const ValueKey('mood-entry-reading'),
                                  controller: _scroll,
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (widget.points.length > 1) ...[
                                          if (widget.points.length <= 6 &&
                                              sameDay)
                                            Wrap(
                                                spacing: 8,
                                                runSpacing: 6,
                                                children: [
                                                  for (final point
                                                      in widget.points)
                                                    ChoiceChip(
                                                        key: ValueKey(
                                                            'mood-select-${point.sourceIndex}'),
                                                        label: Text(
                                                            '${_mood(point.entry)} ${_time(point.localDateTime)} · '
                                                            '${widget.points.indexOf(point) + 1}'),
                                                        tooltip:
                                                            '${moodDateLabel(point.localDateTime)}, ${_time(point.localDateTime)}, '
                                                            '${_moodDescription(point.entry)}',
                                                        selected: identical(
                                                            selected, point),
                                                        onSelected: (_) =>
                                                            _select(point)),
                                                ]),
                                          Align(
                                              alignment: Alignment.centerLeft,
                                              child: TextButton.icon(
                                                  onPressed: () =>
                                                      _select(null),
                                                  icon: const Icon(
                                                      Icons.list_alt),
                                                  label: Text(
                                                      'Elegir otra entrada (${widget.points.length})'))),
                                          const SizedBox(height: 12),
                                        ],
                                        Semantics(
                                            label: _moodDescription(
                                                selected.entry),
                                            child: ExcludeSemantics(
                                                child: Text(
                                                    _mood(selected.entry),
                                                    style: const TextStyle(
                                                        fontSize: 30)))),
                                        Text(
                                            '${moodDateLabel(selected.localDateTime)} · ${_time(selected.localDateTime)}',
                                            key: const ValueKey(
                                                'mood-entry-date'),
                                            style: theme.textTheme.titleMedium),
                                        if (!hasReadableMood(selected.entry))
                                          const Text('Ánimo no disponible'),
                                        const SizedBox(height: 16),
                                        SelectableText(selected.entry.text,
                                            key: const ValueKey(
                                                'mood-entry-text'),
                                            style: theme.textTheme.bodyLarge
                                                ?.copyWith(height: 1.5)),
                                        if (selected.entry.photoId != null) ...[
                                          const SizedBox(height: 16),
                                          InventoryPhotoAttachment(
                                              photoId: selected.entry.photoId!),
                                        ],
                                        const SizedBox(height: 24),
                                      ]))),
                    ]))));
  }

  Widget _entryList() => ListView.separated(
      key: const ValueKey('mood-entry-list'),
      itemCount: widget.points.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final point = widget.points[index];
        return ListTile(
            key: ValueKey('mood-entry-${point.sourceIndex}'),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            title: Text(
                '${moodDateLabel(point.localDateTime)} · ${_time(point.localDateTime)}'),
            subtitle: Text(
                '${_moodDescription(point.entry)} · ${point.entry.text}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _select(point));
      });
}
