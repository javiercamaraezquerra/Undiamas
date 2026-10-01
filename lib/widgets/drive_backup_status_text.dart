import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:intl/intl.dart';

import '../models/diary_entry.dart';
import '../services/drive_backup_service.dart';
import '../services/drive_backup_status_store.dart';
import '../services/hive_restore_service.dart';

/// Small, read-only receipt below the existing Drive switch. No network query,
/// login prompt or new backup is triggered by viewing Profile.
class DriveBackupStatusText extends StatefulWidget {
  const DriveBackupStatusText({
    super.key,
    required this.settings,
    required this.diary,
    required this.foreground,
    this.statusStore,
    this.restoreService,
  });

  final Box<dynamic> settings;
  final Box<DiaryEntry> diary;
  final Color foreground;
  final DriveBackupStatusStore? statusStore;
  final HiveRestoreService? restoreService;

  @override
  State<DriveBackupStatusText> createState() => _DriveBackupStatusTextState();
}

class _DriveBackupStatusTextState extends State<DriveBackupStatusText> {
  late final DriveBackupStatusStore _store;
  late final HiveRestoreService _restore;
  final _subscriptions = <StreamSubscription<BoxEvent>>[];
  Timer? _refreshTimer;
  DriveBackupStatus? _status;
  String? _currentHash;
  bool _readFailed = false;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _store = widget.statusStore ?? DriveBackupStatusStore.instance;
    _restore = widget.restoreService ?? HiveRestoreService.instance;
    _store.addListener(_changed);
    _restore.addListener(_changed);
    _subscriptions.add(widget.settings.watch().listen((_) => _changed()));
    _subscriptions.add(widget.diary.watch().listen((_) => _changed()));
    _changed();
  }

  void _changed() {
    _revision++;
    _refreshTimer?.cancel();
    if (mounted) setState(() {});
    // Coalesce a restore's many box events. Hash only on data/status changes,
    // never in build; compute moves JSON hashing away from the UI isolate.
    _refreshTimer = Timer(const Duration(milliseconds: 30), _refresh);
  }

  Future<void> _refresh() async {
    final revision = _revision;
    try {
      final status = await _store.read();
      String? currentHash;
      if (status.contentHash != null &&
          !_restore.busy &&
          !_restore.recoveryRequired &&
          widget.settings.isOpen &&
          widget.diary.isOpen) {
        currentHash = await compute(backupContentFingerprint,
            DriveBackupService.exportHive(widget.settings, widget.diary));
      }
      if (!mounted || revision != _revision) return;
      setState(() {
        _status = status;
        _currentHash = currentHash;
        _readFailed = false;
      });
    } catch (_) {
      if (!mounted || revision != _revision) return;
      setState(() => _readFailed = true);
    }
  }

  @override
  void dispose() {
    _revision++;
    _refreshTimer?.cancel();
    _store.removeListener(_changed);
    _restore.removeListener(_changed);
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final checkingData = _restore.busy || _restore.recoveryRequired;
    final lines = <String>[];
    if (_readFailed) {
      lines.add('No se pudo consultar la fecha de la última copia.');
    } else if (status == null) {
      lines.add('Consultando última copia…');
    } else if (status.confirmedAt == null) {
      lines.add('Sin fecha de copia registrada en este móvil.');
    } else {
      final date =
          DateFormat('dd/MM/yyyy, HH:mm').format(status.confirmedAt!.toLocal());
      lines.add('Última copia desde este móvil: $date.');
    }
    if (_store.uploading) {
      lines.add('Guardando copia en Drive…');
    } else if (!_readFailed && !checkingData && status != null) {
      if (_currentHash != null && status.differsFrom(_currentHash!)) {
        lines.add('Hay cambios guardados en el móvil pendientes de copiar.');
      } else if (status.lastAttemptFailed) {
        lines.add('No se pudo completar el último intento de copia.');
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Text(
        lines.join('\n'),
        key: const ValueKey('drive_backup_status'),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: widget.foreground.withValues(alpha: .9),
              height: 1.4,
            ),
      ),
    );
  }
}
