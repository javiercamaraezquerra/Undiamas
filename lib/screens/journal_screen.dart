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
import '../widgets/inventory_photo_attachment.dart';

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
          const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                  'Si usas las copias en Drive, también incluirán tus fotos.')),
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
      if (composer.busy)
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: LinearProgressIndicator()),
      if (composer.progress != null)
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(composer.progress!, textAlign: TextAlign.center)),
      if (composer.error != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(composer.error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      if (!composer.ready)
        TextButton(
            onPressed: composer.initialize,
            child: const Text('Reintentar borrador')),
      const SizedBox(height: 8),
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
        '${entry.createdAt.day}/${entry.createdAt.month}/${entry.createdAt.year} '
        '${entry.createdAt.hour.toString().padLeft(2, '0')}:'
        '${entry.createdAt.minute.toString().padLeft(2, '0')}';
    return Card(
      color: dark ? Colors.black.withValues(alpha: .75) : null,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListTile(
          leading:
              Text(moods[entry.mood], style: const TextStyle(fontSize: 24)),
          title: entry.text.isEmpty ? null : Text(entry.text),
          subtitle: Text(date),
          trailing: PopupMenuButton<String>(
            key: ValueKey('entry-menu-$key'),
            tooltip: 'Opciones de la entrada',
            enabled: !(_composer?.busy ?? true) && !_deleting,
            onSelected: (action) => _deleteEntry(box, key, entry,
                photoOnly: action == 'remove-photo'),
            itemBuilder: (_) => [
              if (entry.photoId != null && entry.text.trim().isNotEmpty)
                const PopupMenuItem(
                    value: 'remove-photo', child: Text('Quitar foto')),
              const PopupMenuItem(
                  value: 'delete', child: Text('Eliminar entrada')),
            ],
          ),
        ),
        if (entry.photoId != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: InventoryPhotoAttachment(
                photoId: entry.photoId!, readPhoto: _attachments.readPhoto),
          ),
      ]),
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
                    if (keys.isEmpty)
                      const SliverToBoxAdapter(
                          child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child:
                                  Center(child: Text('No hay entradas aún.'))))
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverList.builder(
                            itemCount: keys.length,
                            itemBuilder: (_, index) => _entryCard(current,
                                keys[index], current.get(keys[index])!, dark)),
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
