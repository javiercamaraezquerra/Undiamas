import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/diary_entry.dart';
import '../services/drive_backup_service.dart';
import '../services/encryption_service.dart';
import '../services/hive_restore_service.dart';
import '../services/journal_composer_controller.dart';
import '../services/journal_search_query.dart';
import '../widgets/inventory_photo_attachment.dart';
import '../widgets/journal_feedback_card.dart';

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key, this.uploadBackup, this.attachmentGateway});

  /// Optional transports for isolated tests; production keeps Drive and files.
  final Future<BackupResult<void>> Function(Map<String, dynamic>)? uploadBackup;
  final JournalAttachmentGateway? attachmentGateway;
  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  JournalSearchQuery _searchQuery = JournalSearchQuery('');
  bool _searchOpen = false;
  DateTime? _selectedDay;
  bool _choosingDay = false;
  late final Future<Box<DiaryEntry>> _futureBox;
  late final JournalAttachmentGateway _attachments;
  JournalComposerController? _composer;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _attachments = widget.attachmentGateway ?? DeviceJournalAttachmentGateway();
    _futureBox = _openEditor();
    _controller.addListener(_textChanged);
  }

  Future<Box<DiaryEntry>> _openEditor() async {
    final cipher = await EncryptionService.getCipher();
    final box = await Hive.openBox<DiaryEntry>('diary_secure',
        encryptionCipher: cipher);
    if (!mounted) return box;
    final composer = JournalComposerController(box: box, gateway: _attachments);
    _composer = composer;
    composer.addListener(_draftChanged);
    await composer.initialize();
    return box;
  }

  void _textChanged() => _composer?.updateText(_controller.text);

  void _draftChanged() {
    if (!mounted) return;
    final text = _composer!.text;
    if (_controller.text != text) {
      _controller.value = TextEditingValue(
          text: text, selection: TextSelection.collapsed(offset: text.length));
    }
    setState(() {});
  }

  Future<void> _saveEntry(Box<DiaryEntry> box) async {
    final composer = _composer;
    if (composer == null || !composer.canSave || _deleting) return;
    FocusScope.of(context).unfocus();
    final messenger = ScaffoldMessenger.of(context);
    await composer.saveEntry(afterSave: () async {
      final warning = await _backupAfterChange(box);
      if (warning != null && messenger.mounted) {
        messenger.showSnackBar(SnackBar(content: Text(warning)));
      }
    });
  }

  Future<String?> _backupAfterChange(Box<DiaryEntry> diary) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool('autoBackup') ?? false)) return null;
      final cipher = await EncryptionService.getCipher();
      final udm = await Hive.openBox('udm_secure', encryptionCipher: cipher);
      final upload = widget.uploadBackup ?? DriveBackupService.uploadBackup;
      final result = await upload(DriveBackupService.exportHive(udm, diary));
      if (result.ok) return null;
    } catch (_) {
      // The local change already succeeded. A network error must not undo it.
    }
    return 'El cambio está guardado en este móvil, pero no se pudo actualizar '
        'Drive. La copia anterior sigue pendiente de actualizar.';
  }

  Future<void> _choosePhoto() async {
    final composer = _composer;
    if (composer == null || !composer.ready || composer.busy || _deleting) {
      return;
    }
    final generation = HiveRestoreService.instance.generation;
    FocusScope.of(context).unfocus();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
          child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Hacer foto'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera)),
          ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery)),
          const SizedBox(height: 8),
        ],
      )),
    );
    if (!mounted ||
        source == null ||
        generation != HiveRestoreService.instance.generation) {
      return;
    }
    await composer.choosePhoto(source);
  }

  Future<void> _deleteEntry(Box<DiaryEntry> box, Object key, DiaryEntry entry,
      {bool photoOnly = false}) async {
    final composer = _composer;
    if (composer == null || composer.busy || _deleting) return;
    final restore = HiveRestoreService.instance;
    final generation = restore.generation;
    setState(() => _deleting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
              photoOnly ? '¿Quitar esta foto?' : '¿Eliminar esta entrada?'),
          scrollable: true,
          content: Text(photoOnly
              ? 'Se quitará la foto del Inventario. El texto y el ánimo se conservarán.'
              : 'Se eliminará esta entrada del Inventario. Las demás entradas '
                  'y lo que estés escribiendo se conservarán.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar')),
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: TextButton.styleFrom(
                    foregroundColor: Theme.of(dialogContext).colorScheme.error),
                child: Text(photoOnly ? 'Quitar foto' : 'Eliminar')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await composer.flushDraft();
      await restore.runExclusive(() async {
        if (!identical(box.get(key), entry)) {
          throw StateError('The entry changed while confirmation was open.');
        }
        if (photoOnly) {
          await box.put(
              key,
              DiaryEntry(
                  createdAt: entry.createdAt,
                  mood: entry.mood,
                  text: entry.text));
        } else {
          await box.delete(key);
        }
        await box.flush();
        // Delete only an app-owned attachment with no other entry/draft reference.
        try {
          await composer.deleteUnusedPhoto(entry.photoId);
        } catch (_) {
          // A leftover encrypted file is safer than rolling back a committed edit.
          // Startup pruning retries removal of unreferenced media.
        }
        if (messenger.mounted) {
          messenger.showSnackBar(SnackBar(
              content: Text(photoOnly
                  ? 'Foto eliminada del Inventario.'
                  : 'Entrada eliminada.')));
        }
        final warning = await _backupAfterChange(box);
        if (warning != null && messenger.mounted) {
          messenger.showSnackBar(SnackBar(content: Text(warning)));
        }
      }, expectedGeneration: generation);
    } catch (_) {
      if (messenger.mounted) {
        messenger.showSnackBar(const SnackBar(
            content: Text(
          'No se pudo completar la eliminación. Comprueba el Inventario '
          'y vuelve a intentarlo cuando termine cualquier restauración.',
        )));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  void dispose() {
    _composer?.removeListener(_draftChanged);
    _composer?.dispose();
    _controller.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Widget _editor(Box<DiaryEntry> box, bool dark) {
    const moods = ['😢', '😕', '😐', '🙂', '😄'];
    const labels = ['Muy bajo', 'Bajo', 'Neutro', 'Bueno', 'Muy bueno'];
    final composer = _composer!;
    final enabled = composer.ready && !composer.busy && !_deleting;
    final photoButtonStyle = TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        backgroundColor: Theme.of(context).colorScheme.surface.withAlpha(235));
    return Column(children: [
      Text('¿Cómo te sientes hoy?',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(color: dark ? Colors.white : Colors.black)),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(moods.length, (i) {
          final selected = i == composer.mood;
          return Semantics(
            button: true,
            selected: selected,
            label: 'Ánimo: ${labels[i]}',
            child: InkWell(
              borderRadius: BorderRadius.circular(40),
              onTap: enabled ? () => composer.updateMood(i) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.all(selected ? 12 : 8),
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected
                        ? Theme.of(context).colorScheme.primary.withAlpha(0x33)
                        : Colors.transparent),
                child: ExcludeSemantics(
                    child: Text(moods[i],
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(fontSize: selected ? 32 : 28))),
              ),
            ),
          );
        }),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _controller,
        maxLines: 3,
        enabled: enabled,
        style: TextStyle(color: dark ? Colors.white : Colors.black87),
        decoration: InputDecoration(
          hintText: 'Escribe tus pensamientos…',
          hintStyle:
              TextStyle(color: dark ? Colors.white70 : Colors.grey.shade700),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      const SizedBox(height: 4),
      if (composer.photoId == null)
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('journal-add-photo'),
              style: photoButtonStyle,
              onPressed: enabled && composer.canAttach ? _choosePhoto : null,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Añadir foto'),
            ))
      else ...[
        const SizedBox(height: 8),
        InventoryPhotoAttachment(
            key: ValueKey('draft-photo-${composer.photoId}'),
            photoId: composer.photoId!,
            height: 100,
            readPhoto: _attachments.readPhoto),
        Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: 8, children: [
              TextButton.icon(
                  style: photoButtonStyle,
                  onPressed:
                      enabled && composer.canAttach ? _choosePhoto : null,
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Cambiar')),
              TextButton.icon(
                  style: photoButtonStyle,
                  onPressed: enabled && composer.canAttach
                      ? composer.removePhoto
                      : null,
                  icon: const Icon(Icons.close),
                  label: const Text('Quitar')),
            ])),
      ],
      if (composer.busy || composer.progress != null)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: JournalFeedbackCard(
                key: const ValueKey('journal-progress'),
                message: composer.progress ?? 'Un momento…',
                isBusy: true)),
      if (composer.photoIssue != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: JournalFeedbackCard(
            key: const ValueKey('journal-photo-issue'),
            title: composer.photoIssue!.title,
            message: composer.photoIssue!.message,
            icon: Icons.photo_outlined,
            isError: true,
            onDismiss: composer.dismissPhotoIssue,
            actions: [
              if (composer.photoIssue!.canRetry)
                TextButton.icon(
                    key: const ValueKey('journal-retry-photo'),
                    onPressed: enabled && composer.canAttach
                        ? () async {
                            FocusScope.of(context).unfocus();
                            await composer.retryPhoto();
                          }
                        : null,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar')),
              if (composer.photoIssue!.canChooseOther)
                TextButton.icon(
                    key: const ValueKey('journal-choose-other-photo'),
                    onPressed: enabled && composer.canAttach
                        ? () async {
                            FocusScope.of(context).unfocus();
                            await composer.choosePhoto(ImageSource.gallery);
                          }
                        : null,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Elegir otra')),
            ],
          ),
        ),
      if (composer.error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: JournalFeedbackCard(
              key: const ValueKey('journal-editor-issue'),
              message: composer.error!,
              icon: Icons.info_outline,
              isError: true),
        ),
      if (!composer.ready)
        TextButton(
            style: photoButtonStyle,
            onPressed: composer.initialize,
            child: const Text('Reintentar borrador')),
      const SizedBox(height: 8),
      if (composer.ready &&
          !composer.busy &&
          composer.mood == null &&
          (composer.text.trim().isNotEmpty || composer.photoId != null)) ...[
        const JournalFeedbackCard(
            key: ValueKey('journal-mood-hint'),
            message: 'Elige cómo te sientes para guardar tu día.',
            icon: Icons.mood_outlined,
            compact: true),
        const SizedBox(height: 8),
      ],
      ElevatedButton(
        onPressed:
            composer.canSave && !_deleting ? () => _saveEntry(box) : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: dark
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.primary,
          foregroundColor: dark
              ? Theme.of(context).colorScheme.onPrimaryContainer
              : Colors.white,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
        ),
        child: const Text('Guardar mi día'),
      ),
      const SizedBox(height: 24),
    ]);
  }

  Widget _entryCard(
      Box<DiaryEntry> box, Object key, DiaryEntry entry, bool dark) {
    const moods = ['😢', '😕', '😐', '🙂', '😄'];
    final date =
        '${entry.createdAt.day}/${entry.createdAt.month}/${entry.createdAt.year}';
    final time = '${entry.createdAt.hour.toString().padLeft(2, '0')}:'
        '${entry.createdAt.minute.toString().padLeft(2, '0')}';
    final menu = PopupMenuButton<String>(
      key: ValueKey('entry-menu-$key'),
      tooltip: 'Opciones de la entrada',
      enabled: !(_composer?.busy ?? true) && !_deleting,
      onSelected: (action) =>
          _deleteEntry(box, key, entry, photoOnly: action == 'remove-photo'),
      itemBuilder: (_) => [
        if (entry.photoId != null && entry.text.trim().isNotEmpty)
          const PopupMenuItem(
              value: 'remove-photo', child: Text('Quitar foto')),
        const PopupMenuItem(value: 'delete', child: Text('Eliminar entrada')),
      ],
    );
    final mood = Text(moods[entry.mood], style: const TextStyle(fontSize: 24));
    return Card(
      key: ValueKey(key),
      color: dark ? Colors.black.withValues(alpha: .75) : null,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(builder: (context, constraints) {
          final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
          if (!largeText && constraints.maxWidth >= 328) {
            return ListTile(
              leading: mood,
              title: entry.text.isEmpty ? null : Text(entry.text),
              subtitle: Text('$date $time'),
              trailing: menu,
            );
          }
          // Keep the reading width when larger type or a narrow phone would
          // squeeze the message between its mood and menu into a slim column.
          final textTheme = Theme.of(context).textTheme;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [mood, const Spacer(), menu]),
                if (entry.text.isNotEmpty) ...[
                  Text(entry.text, style: textTheme.bodyLarge),
                  const SizedBox(height: 4),
                ],
                Wrap(spacing: 8, children: [
                  Text(date, style: textTheme.bodyMedium),
                  Text(time, style: textTheme.bodyMedium),
                ]),
              ],
            ),
          );
        }),
        if (entry.photoId != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: InventoryPhotoAttachment(
                photoId: entry.photoId!, readPhoto: _attachments.readPhoto),
          ),
      ]),
    );
  }

  void _closeSearch() {
    _searchFocus.unfocus();
    _searchController.clear();
    setState(() {
      _searchOpen = false;
      _searchQuery = JournalSearchQuery('');
    });
  }

  void _openSearch() {
    setState(() {
      _selectedDay = null;
      _searchOpen = true;
    });
  }

  Future<void> _chooseDay(Box<DiaryEntry> box) async {
    if (_choosingDay) return;
    FocusScope.of(context).unfocus();
    final today = DateUtils.dateOnly(DateTime.now());
    var firstDay = today;
    var lastDay = today;
    // Include legacy/restored dates and the active filter, even if the last
    // matching entry was deleted. Match the calendar date displayed on cards.
    for (final day in [
      if (_selectedDay != null) _selectedDay!,
      ...box.values.map((entry) => DateUtils.dateOnly(entry.createdAt)),
    ]) {
      if (day.isBefore(firstDay)) firstDay = day;
      if (day.isAfter(lastDay)) lastDay = day;
    }
    final compactLargeText = MediaQuery.sizeOf(context).width < 360 &&
        MediaQuery.textScalerOf(context).scale(14) > 14 * 1.3;
    final pickerMode = ValueNotifier(compactLargeText
        ? DatePickerEntryMode.input
        : DatePickerEntryMode.calendar);
    setState(() => _choosingDay = true);
    try {
      final chosen = await showDatePicker(
        context: context,
        initialDate: _selectedDay ?? today,
        firstDate: firstDay,
        lastDate: lastDay,
        initialEntryMode: pickerMode.value,
        onDatePickerModeChange: (mode) => pickerMode.value = mode,
        builder: compactLargeText
            ? (context, child) => ValueListenableBuilder<DatePickerEntryMode>(
                  valueListenable: pickerMode,
                  child: child,
                  builder: (context, mode, child) {
                    final media = MediaQuery.of(context);
                    // Keep the wrapper stable so switching modes preserves the
                    // picker state. Only the seven-column grid limits scaling.
                    return MediaQuery(
                      data: media.copyWith(
                        textScaler: mode == DatePickerEntryMode.calendar
                            ? media.textScaler.clamp(maxScaleFactor: 1.4)
                            : media.textScaler,
                      ),
                      child: child!,
                    );
                  },
                )
            : null,
        helpText: 'Ver entradas de un día',
        fieldLabelText: 'Fecha',
        cancelText: 'Cancelar',
        confirmText: 'Ver día',
      );
      if (!mounted || chosen == null) return;
      _searchController.clear();
      setState(() {
        _searchOpen = false;
        _searchQuery = JournalSearchQuery('');
        _selectedDay = DateUtils.dateOnly(chosen);
      });
    } finally {
      pickerMode.dispose();
      if (mounted) setState(() => _choosingDay = false);
    }
  }

  Widget _historySearch(Box<DiaryEntry> box, int resultCount) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface.withAlpha(235),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
                child: Text('Tus entradas', style: theme.textTheme.titleSmall)),
            IconButton(
              key: const ValueKey('journal-date-toggle'),
              tooltip: 'Buscar por día',
              isSelected: _selectedDay != null,
              onPressed: _choosingDay ? null : () => _chooseDay(box),
              icon: const Icon(Icons.calendar_month_outlined),
              selectedIcon: const Icon(Icons.calendar_month),
            ),
            IconButton(
              key: const ValueKey('journal-search-toggle'),
              tooltip:
                  _searchOpen ? 'Cerrar búsqueda' : 'Buscar en el Inventario',
              onPressed: _searchOpen ? _closeSearch : _openSearch,
              icon: Icon(_searchOpen ? Icons.close : Icons.search),
            ),
          ]),
          if (_selectedDay != null) ...[
            Row(key: const ValueKey('journal-date-filter'), children: [
              Expanded(
                child: Text(
                  'Día: ${MaterialLocalizations.of(context).formatShortDate(_selectedDay!)}',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              IconButton(
                key: const ValueKey('journal-date-clear'),
                tooltip: 'Quitar filtro de fecha',
                onPressed: () => setState(() => _selectedDay = null),
                icon: const Icon(Icons.close),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Text(
                '$resultCount ${resultCount == 1 ? 'entrada encontrada' : 'entradas encontradas'}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
          if (_searchOpen) ...[
            TextField(
              key: const ValueKey('journal-search-field'),
              controller: _searchController,
              focusNode: _searchFocus,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _searchFocus.unfocus(),
              onChanged: (value) =>
                  setState(() => _searchQuery = JournalSearchQuery(value)),
              decoration: InputDecoration(
                labelText: 'Buscar texto',
                filled: true,
                fillColor: theme.colorScheme.surface,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar búsqueda',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = JournalSearchQuery(''));
                          _searchFocus.requestFocus();
                        },
                        icon: const Icon(Icons.clear)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
              child: Text(
                _searchQuery.isEmpty
                    ? 'Busca una palabra o varias en tus entradas guardadas.'
                    : '$resultCount ${resultCount == 1 ? 'entrada encontrada' : 'entradas encontradas'}',
                key: const ValueKey('journal-search-summary'),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return FutureBuilder<Box<DiaryEntry>>(
      future: _futureBox,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Scaffold(
              body: Center(
                  child: Padding(
            padding: EdgeInsets.all(24),
            child:
                Text('No se pudo abrir el Inventario. Vuelve a abrir la app; '
                    'tus datos no se han borrado.'),
          )));
        }
        if (!snapshot.hasData || _composer == null) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final box = snapshot.data!;
        return ValueListenableBuilder(
          valueListenable: box.listenable(),
          builder: (context, Box<DiaryEntry> current, _) {
            final keys = current.keys.toList().reversed.toList();
            // Legacy keys are numeric; new durable drafts use string keys.
            // Their lexical order must never change the diary's chronology.
            keys.sort((a, b) =>
                current.get(b)!.createdAt.compareTo(current.get(a)!.createdAt));
            // Filter only the view. Actions keep the original Hive key, never
            // a result index, and every box event refreshes the current results.
            final visibleKeys = keys.where((key) {
              final entry = current.get(key)!;
              return _selectedDay != null
                  ? DateUtils.isSameDay(entry.createdAt, _selectedDay)
                  : _searchQuery.matches(entry.text);
            }).toList();
            return Scaffold(
              extendBodyBehindAppBar: true,
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                  title: const Text('Inventario'),
                  backgroundColor: Colors.transparent,
                  elevation: 0),
              body: SafeArea(
                top: true,
                bottom: false,
                child: CustomScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        sliver: SliverToBoxAdapter(child: _editor(box, dark))),
                    if (keys.isNotEmpty || _searchOpen || _selectedDay != null)
                      SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          sliver: SliverToBoxAdapter(
                              child:
                                  _historySearch(current, visibleKeys.length))),
                    if (visibleKeys.isEmpty)
                      SliverToBoxAdapter(
                          child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 24),
                              child: _selectedDay != null
                                  ? const JournalFeedbackCard(
                                      message:
                                          'No hay entradas guardadas este día. '
                                          'Puedes elegir otro día o quitar el filtro de fecha.',
                                      icon: Icons.calendar_month_outlined,
                                      compact: true)
                                  : _searchQuery.isEmpty
                                      ? const Center(
                                          child: Text('No hay entradas aún.'))
                                      : const JournalFeedbackCard(
                                          message:
                                              'No hay entradas con esas palabras. '
                                              'Prueba otra búsqueda o límpiala para verlas todas.',
                                          icon: Icons.search_off,
                                          compact: true)))
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverList.builder(
                            itemCount: visibleKeys.length,
                            itemBuilder: (_, index) => _entryCard(
                                current,
                                visibleKeys[index],
                                current.get(visibleKeys[index])!,
                                dark)),
                      ),
                    SliverToBoxAdapter(
                        child: SizedBox(
                            height: MediaQuery.paddingOf(context).bottom + 24)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
