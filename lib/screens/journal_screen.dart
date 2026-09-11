import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/diary_entry.dart';
import '../services/drive_backup_service.dart';
import '../services/encryption_service.dart';
import '../services/hive_restore_service.dart';

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key, this.uploadBackup});

  /// Optional transport for isolated widget tests; normal use keeps Google Drive.
  final Future<BackupResult<void>> Function(Map<String, dynamic>)? uploadBackup;
  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  final TextEditingController _controller = TextEditingController();
  int? _selectedMood;
  late final Future<Box<DiaryEntry>> _futureBox;
  bool _saving = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _futureBox = EncryptionService.getCipher().then(
      (c) => Hive.openBox<DiaryEntry>('diary_secure', encryptionCipher: c),
    );
    _controller.addListener(() => setState(() {}));
  }

  Future<void> _saveEntry(Box<DiaryEntry> box) async {
    if (_saving ||
        _deleting ||
        _selectedMood == null ||
        _controller.text.trim().isEmpty) return;
    final submittedText = _controller.text;
    final submittedMood = _selectedMood;
    final entry = DiaryEntry(
      createdAt: DateTime.now(),
      mood: submittedMood!,
      text: submittedText.trim(),
    );
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await HiveRestoreService.instance.runExclusive(() async {
        await box.add(entry);
        // Clear only the submitted draft, never text entered during disk IO.
        if (mounted &&
            _controller.text == submittedText &&
            _selectedMood == submittedMood) {
          FocusScope.of(context).unfocus();
          _controller.clear();
          setState(() => _selectedMood = null);
        }
        final backupWarning = await _backupAfterChange(box);
        if (backupWarning != null && messenger.mounted) {
          messenger.showSnackBar(SnackBar(content: Text(backupWarning)));
        }
      });
    } catch (_) {
      if (messenger.mounted) {
        messenger.showSnackBar(const SnackBar(
            content: Text(
          'No se pudo guardar la entrada. Espera a que termine cualquier '
          'restauración y vuelve a intentarlo.',
        )));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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

  Future<void> _deleteEntry(
      Box<DiaryEntry> box, Object key, DiaryEntry entry) async {
    if (_saving || _deleting) return;
    final restore = HiveRestoreService.instance;
    final generation = restore.generation;
    setState(() => _deleting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('¿Eliminar esta entrada?'),
          scrollable: true,
          content: const Text(
            'Se eliminará esta entrada del Inventario. Las demás entradas '
            'y lo que estés escribiendo se conservarán.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: TextButton.styleFrom(
                  foregroundColor: Theme.of(dialogContext).colorScheme.error),
              child: const Text('Eliminar'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await restore.runExclusive(() async {
        // Use Hive's stable key, not its changing position in the reversed list.
        if (!identical(box.get(key), entry)) {
          throw StateError('The entry changed while confirmation was open.');
        }
        await box.delete(key);
        await box.flush();
        if (messenger.mounted) {
          messenger.showSnackBar(
              const SnackBar(content: Text('Entrada eliminada.')));
        }
        final backupWarning = await _backupAfterChange(box);
        if (backupWarning != null && messenger.mounted) {
          messenger.showSnackBar(SnackBar(content: Text(backupWarning)));
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
    _controller.dispose();
    super.dispose();
  }

  /* ───────── UI ───────── */
  @override
  Widget build(BuildContext context) {
    const moods = ['😢', '😕', '😐', '🙂', '😄'];
    final canSave = !_saving &&
        !_deleting &&
        _selectedMood != null &&
        _controller.text.trim().isNotEmpty;
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    return FutureBuilder<Box<DiaryEntry>>(
      future: _futureBox,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final box = snap.data!;
        return ValueListenableBuilder(
          valueListenable: box.listenable(),
          builder: (context, Box<DiaryEntry> b, _) {
            final entryKeys = b.keys.toList().reversed.toList();
            return Scaffold(
              extendBodyBehindAppBar: true,
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                title: const Text('Inventario'),
                backgroundColor: Colors.transparent,
                elevation: 0,
              ),
              body: SafeArea(
                top: true,
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text('¿Cómo te sientes hoy?',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                  color: dark ? Colors.white : Colors.black)),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(moods.length, (i) {
                          final sel = i == _selectedMood;
                          return GestureDetector(
                            onTap: () => setState(() => _selectedMood = i),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: EdgeInsets.all(sel ? 12 : 8),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: sel
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withAlpha(0x33)
                                    : Colors.transparent,
                              ),
                              child: Text(moods[i],
                                  style: TextStyle(fontSize: sel ? 32 : 28)),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _controller,
                        maxLines: 3,
                        style: TextStyle(
                            color: dark ? Colors.white : Colors.black87),
                        decoration: InputDecoration(
                          hintText: 'Escribe tus pensamientos…',
                          hintStyle: TextStyle(
                              color:
                                  dark ? Colors.white70 : Colors.grey.shade700),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: canSave ? () => _saveEntry(box) : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: dark
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context).colorScheme.primary,
                          foregroundColor: dark
                              ? Theme.of(context).colorScheme.onPrimaryContainer
                              : Colors.white,
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 12,
                          ),
                        ),
                        child: const Text('Guardar mi día'),
                      ),
                      const SizedBox(height: 24),
                      Expanded(
                        child: entryKeys.isEmpty
                            ? const Center(child: Text('No hay entradas aún.'))
                            : ListView.builder(
                                itemCount: entryKeys.length,
                                itemBuilder: (_, i) {
                                  final entryKey = entryKeys[i];
                                  final e = b.get(entryKey)!;
                                  final date =
                                      '${e.createdAt.day}/${e.createdAt.month}/${e.createdAt.year} '
                                      '${e.createdAt.hour.toString().padLeft(2, '0')}:'
                                      '${e.createdAt.minute.toString().padLeft(2, '0')}';
                                  return Card(
                                    color: dark
                                        ? Colors.black.withOpacity(.75)
                                        : null,
                                    margin:
                                        const EdgeInsets.symmetric(vertical: 4),
                                    child: ListTile(
                                      leading: Text(moods[e.mood],
                                          style: const TextStyle(fontSize: 24)),
                                      title: Text(e.text),
                                      subtitle: Text(date),
                                      trailing: PopupMenuButton<String>(
                                        key: ValueKey('entry-menu-$entryKey'),
                                        tooltip: 'Opciones de la entrada',
                                        enabled: !_saving && !_deleting,
                                        onSelected: (_) =>
                                            _deleteEntry(b, entryKey, e),
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(
                                            value: 'delete',
                                            child: Text('Eliminar entrada'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
