import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/diary_entry.dart';
import '../services/drive_backup_service.dart';
import '../services/encryption_service.dart';

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});
  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  final TextEditingController _controller = TextEditingController();
  int? _selectedMood;
  late final Future<Box<DiaryEntry>> _futureBox;

  @override
  void initState() {
    super.initState();
    _futureBox = EncryptionService.getCipher().then(
      (c) => Hive.openBox<DiaryEntry>('diary_secure', encryptionCipher: c),
    );
    _controller.addListener(() => setState(() {}));
  }

  Future<void> _saveEntry(Box<DiaryEntry> box) async {
    final entry = DiaryEntry(
      createdAt: DateTime.now(),
      mood: _selectedMood!,
      text: _controller.text.trim(),
    );
    await box.add(entry);

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('autoBackup') ?? false) {
      final cipher = await EncryptionService.getCipher();
      final udm = await Hive.openBox('udm_secure', encryptionCipher: cipher);
      await DriveBackupService.uploadBackup(
          DriveBackupService.exportHive(udm, box));
    }

    if (!mounted) return;
    FocusScope.of(context).unfocus();
    _controller.clear();
    setState(() => _selectedMood = null);
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
    final canSave = _selectedMood != null && _controller.text.trim().isNotEmpty;
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
            final entries = b.values.toList().reversed.toList();
            return Scaffold(
              extendBodyBehindAppBar: true,
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                title: const Text('Diario'),
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
                                  color:
                                      dark ? Colors.white : Colors.black)),
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
                              ? Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer
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
                        child: entries.isEmpty
                            ? const Center(child: Text('No hay entradas aún.'))
                            : ListView.builder(
                                itemCount: entries.length,
                                itemBuilder: (_, i) {
                                  final e = entries[i];
                                  final date =
                                      '${e.createdAt.day}/${e.createdAt.month}/${e.createdAt.year} '
                                      '${e.createdAt.hour.toString().padLeft(2, '0')}:'
                                      '${e.createdAt.minute.toString().padLeft(2, '0')}';
                                  return Card(
                                    color: dark
                                        ? Colors.black.withOpacity(.75)
                                        : null,
                                    margin: const EdgeInsets.symmetric(
                                        vertical: 4),
                                    child: ListTile(
                                      leading: Text(moods[e.mood],
                                          style: const TextStyle(fontSize: 24)),
                                      title: Text(e.text),
                                      subtitle: Text(date),
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
