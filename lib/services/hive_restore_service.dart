import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/diary_entry.dart';
import 'encryption_service.dart';
import 'safe_hive_open.dart';

/// A detached, fully validated legacy Drive copy. Preparing never opens a box.
class PreparedHiveBackup {
  PreparedHiveBackup._(this._settings, this._entries);

  final Map<String, dynamic> _settings;
  final List<DiaryEntry> _entries;
  int get entryCount => _entries.length;
  bool get isEmptyInventory => _entries.isEmpty;
  DateTime? get startDate => _settings['startDate'] == null
      ? null
      : DateTime.parse(_settings['startDate'] as String);
}

class HiveRestoreResult {
  const HiveRestoreResult({
    required this.ok,
    required this.message,
    this.recoveryRequired = false,
    this.recovered = false,
  });

  final bool ok;
  final String message;
  final bool recoveryRequired;
  final bool recovered;
}

/// Serializes local mutations and keeps an encrypted undo journal on disk.
/// Startup MUST run recoverInterrupted before displaying or editing app data.
/// Every UI mutation shares runExclusive; callers capture generation before
/// asynchronous confirmation so an old screen cannot write after a restore.
class HiveRestoreService extends ChangeNotifier {
  static const recoveryBoxName = 'restore_recovery_secure';
  static final instance = HiveRestoreService();

  HiveRestoreService({
    Future<Box<dynamic>> Function()? openRecoveryBox,
    @visibleForTesting Future<void> Function(String step)? beforeStep,
  })  : _openRecoveryBox = openRecoveryBox ?? _openEncryptedRecovery,
        _beforeStep = beforeStep;

  final Future<Box<dynamic>> Function() _openRecoveryBox;
  final Future<void> Function(String step)? _beforeStep;
  bool _busy = false;
  bool _recoveryRequired = false;
  int _generation = 0;
  bool get busy => _busy;
  bool get recoveryRequired => _recoveryRequired;
  int get generation => _generation;

  static Future<Box<dynamic>> _openEncryptedRecovery() async =>
      openHiveBoxSafely<dynamic>(recoveryBoxName,
          encryptionCipher: await EncryptionService.getCipher());

  static PreparedHiveBackup prepare(Map<String, dynamic> data) {
    // Both sections are mandatory: {} must not masquerade as an empty copy.
    if (data.length != 2 || data['udm'] is! Map || data['diary'] is! List) {
      throw const FormatException(
          'La copia no contiene las secciones de ajustes e Inventario esperadas.');
    }
    final settings = _jsonValue(data['udm']) as Map<String, dynamic>;
    if (settings.containsKey('startDate')) {
      _date(settings['startDate']);
    }
    if (settings.containsKey('substance') && settings['substance'] is! String) {
      throw const FormatException('La sustancia de la copia no es válida.');
    }
    final entries = <DiaryEntry>[];
    for (final value in data['diary'] as List) {
      if (value is! Map ||
          value.length != 3 ||
          value['text'] is! String ||
          value['mood'] is! int ||
          (value['mood'] as int) < 0 ||
          (value['mood'] as int) > 4) {
        throw const FormatException('Una entrada del Inventario no es válida.');
      }
      entries.add(DiaryEntry(
          text: value['text'] as String,
          mood: value['mood'] as int,
          createdAt: _date(value['createdAt'])));
    }
    return PreparedHiveBackup._(settings, entries);
  }

  /// Accept JSON data without silently dropping settings unknown to this app.
  static dynamic _jsonValue(dynamic value) {
    if (value == null || value is String || value is bool || value is int) {
      return value;
    }
    if (value is double && value.isFinite) return value;
    if (value is List) return value.map(_jsonValue).toList();
    if (value is Map) {
      final copy = <String, dynamic>{};
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw const FormatException('Un ajuste tiene una clave no válida.');
        }
        copy[entry.key as String] = _jsonValue(entry.value);
      }
      return copy;
    }
    throw const FormatException('La copia contiene un ajuste no compatible.');
  }

  static DateTime _date(dynamic value) {
    if (value is! String) {
      throw const FormatException('Una fecha de la copia no es válida.');
    }
    // DateTime.parse normalizes impossible dates, e.g. February 30. Validate
    // components first. This includes every format emitted by toIso8601String
    // plus explicit ISO offsets accepted by previous versions.
    final match = RegExp(
            r'^([+-]?\d{4,6})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?(?:Z|([+-])(\d{2}):?(\d{2}))?$')
        .firstMatch(value);
    if (match == null) {
      throw const FormatException('Una fecha de la copia no es válida.');
    }
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    final hour = int.parse(match[4]!);
    final minute = int.parse(match[5]!);
    final second = int.parse(match[6]!);
    final DateTime calendar;
    try {
      calendar = DateTime.utc(year, month, day);
    } catch (_) {
      throw const FormatException('Una fecha de la copia no es válida.');
    }
    if (month < 1 ||
        month > 12 ||
        day < 1 ||
        calendar.year != year ||
        calendar.month != month ||
        calendar.day != day ||
        hour > 23 ||
        minute > 59 ||
        second > 59 ||
        (match[9] != null && int.parse(match[9]!) > 23) ||
        (match[10] != null && int.parse(match[10]!) > 59)) {
      throw const FormatException('Una fecha de la copia no es válida.');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw const FormatException('Una fecha de la copia no es válida.');
    }
    return parsed;
  }

  Future<T> runExclusive<T>(Future<T> Function() action,
      {int? expectedGeneration}) async {
    _begin(expectedGeneration: expectedGeneration);
    try {
      return await action();
    } finally {
      _end();
    }
  }

  /// The callback must remove recoveryBoxName before deleting the encryption
  /// key. It must not invoke other exclusive operations from inside itself.
  Future<T> runDeletion<T>(Future<T> Function() action) async {
    _begin(allowRecovery: true);
    _generation++;
    try {
      final result = await action();
      _recoveryRequired = false;
      return result;
    } finally {
      _end();
    }
  }

  void _begin({int? expectedGeneration, bool allowRecovery = false}) {
    if (_busy) {
      throw StateError(
          'Hay otra operación de datos en curso. Espera a que termine.');
    }
    if (_recoveryRequired && !allowRecovery) {
      throw StateError(
          'Primero hay que recuperar la restauración interrumpida.');
    }
    if (expectedGeneration != null && expectedGeneration != _generation) {
      throw StateError('Los datos han cambiado. Abre de nuevo esta pantalla.');
    }
    _busy = true;
    notifyListeners();
  }

  void _end() {
    _busy = false;
    notifyListeners();
  }

  Future<void> _step(String step) async {
    await _beforeStep?.call(step);
  }

  Future<HiveRestoreResult> restore(PreparedHiveBackup prepared,
      Box<dynamic> udm, Box<DiaryEntry> diary) async {
    try {
      _begin();
    } catch (_) {
      return HiveRestoreResult(
          ok: false,
          recoveryRequired: _recoveryRequired,
          message:
              'Hay otra operación o recuperación pendiente. Vuelve a intentarlo.');
    }
    _generation++;
    try {
      final journal = await _openRecoveryBox();
      if (await _pendingAfterFlush(journal, udm, diary)) {
        _recoveryRequired = true;
        return _needsRecovery;
      }
      await udm.flush();
      await diary.flush();
      final before = _snapshot(udm, diary);
      final transaction = <String, dynamic>{
        'version': 1,
        'phase': 'pending',
        'before': before,
      };
      // No data is touched until the encrypted undo snapshot is flushed.
      try {
        await _step('journal.prepare');
        await journal.put('transaction', transaction);
        await _step('journal.prepare.flush');
        await journal.flush();
      } catch (_) {
        // A failed flush is ambiguous; recovery is harmless even if the data
        // was not touched. Do not overwrite this journal with another restore.
        _recoveryRequired = true;
        return const HiveRestoreResult(
            ok: false,
            recoveryRequired: true,
            message: 'No se pudo confirmar la copia local de recuperación. '
                'No se ha iniciado la sustitución. Reintenta la recuperación.');
      }
      try {
        await _step('apply.settings');
        await udm.putAll(prepared._settings);
        await diary.clear();
        await _step('apply.diary');
        await diary.putAll({
          for (var i = 0; i < prepared._entries.length; i++)
            i: _cloneEntry(prepared._entries[i])
        });
        await _flushData(udm, diary, 'apply');
        final expectedSettings =
            Map<dynamic, dynamic>.from(before['udm'] as Map)
              ..addAll(prepared._settings);
        final expected = {
          'udm': expectedSettings,
          'diary': <dynamic, dynamic>{
            for (var i = 0; i < prepared._entries.length; i++)
              i: _entryMap(prepared._entries[i])
          }
        };
        if (!_equal(_snapshot(udm, diary), expected)) {
          throw StateError(
              'The restored data did not match the validated copy.');
        }
      } catch (_) {
        return await _rollback(journal, before, udm, diary);
      }
      // All new data is durable before the completion marker. If marking fails,
      // do not start an unsafe second rollback: startup can select either the
      // completed copy or the untouched undo snapshot from its durable phase.
      if (!await _complete(journal, before)) return _needsRecovery;
      return const HiveRestoreResult(ok: true, message: 'Datos restaurados.');
    } catch (_) {
      _recoveryRequired = true;
      return _needsRecovery;
    } finally {
      _end();
    }
  }

  Future<HiveRestoreResult> recoverInterrupted(
      Box<dynamic> udm, Box<DiaryEntry> diary) async {
    try {
      _begin(allowRecovery: true);
    } catch (_) {
      return const HiveRestoreResult(
          ok: false,
          recoveryRequired: true,
          message:
              'Hay una operación de datos en curso. Espera antes de recuperar.');
    }
    try {
      final journal = await _openRecoveryBox();
      if (!await _pendingAfterFlush(journal, udm, diary)) {
        _recoveryRequired = false;
        return const HiveRestoreResult(
            ok: true, message: 'No hay recuperación pendiente.');
      }
      _generation++;
      final transaction = journal.get('transaction') as Map;
      final before = _validateSnapshot(transaction['before']);
      // A previous failed prepare flush can leave a pending record only in
      // Hive's memory cache. Confirm it on disk before ANY recovery writes.
      await _step('recovery.journal.flush');
      await journal.flush();
      final result = await _rollback(journal, before, udm, diary);
      if (result.recovered) {
        return const HiveRestoreResult(
            ok: true,
            recovered: true,
            message:
                'Se recuperaron tus datos anteriores tras una restauración interrumpida.');
      }
      return result;
    } catch (_) {
      _recoveryRequired = true;
      return _needsRecovery;
    } finally {
      _end();
    }
  }

  static bool _pending(Box<dynamic> journal) {
    final record = journal.get('transaction');
    if (record == null) return false;
    if (record is! Map ||
        record['version'] != 1 ||
        !const ['pending', 'complete'].contains(record['phase'])) {
      throw const FormatException('Invalid local recovery journal.');
    }
    return record['phase'] == 'pending';
  }

  Future<bool> _pendingAfterFlush(
      Box<dynamic> journal, Box<dynamic> udm, Box<DiaryEntry> diary) async {
    if (_pending(journal)) return true;
    if (journal.get('transaction') != null) {
      // Hive may expose phase=complete in memory even though its flush failed.
      // Never admit new writes until that same phase is confirmed on disk:
      // otherwise a later restart could see pending and undo those new writes.
      await _flushData(udm, diary, 'settle');
      await _step('journal.settle.flush');
      await journal.flush();
      try {
        await journal.delete('transaction');
        await journal.flush();
      } catch (_) {
        // The durable complete phase already makes the old snapshot inert.
      }
    }
    return false;
  }

  Future<HiveRestoreResult> _rollback(
      Box<dynamic> journal,
      Map<dynamic, dynamic> before,
      Box<dynamic> udm,
      Box<DiaryEntry> diary) async {
    try {
      // Decode ALL of the undo snapshot before attempting its first write.
      final valid = _validateSnapshot(before);
      final entries = _entriesFromSnapshot(valid['diary'] as Map);
      await _step('rollback.settings');
      await udm.clear();
      await udm.putAll(valid['udm'] as Map);
      await diary.clear();
      await _step('rollback.diary');
      await diary.putAll(entries);
      await _flushData(udm, diary, 'rollback');
      if (!_equal(_snapshot(udm, diary), valid)) {
        throw StateError('The undo snapshot did not match the recovered data.');
      }
      if (!await _complete(journal, valid)) return _needsRecovery;
      return const HiveRestoreResult(
          ok: false,
          recovered: true,
          message:
              'No se pudo restaurar la copia. Se han recuperado y comprobado tus datos anteriores.');
    } catch (_) {
      _recoveryRequired = true;
      return _needsRecovery;
    }
  }

  Future<void> _flushData(
      Box<dynamic> udm, Box<DiaryEntry> diary, String prefix) async {
    await _step('$prefix.flush.settings');
    await udm.flush();
    await _step('$prefix.flush.diary');
    await diary.flush();
  }

  Future<bool> _complete(
      Box<dynamic> journal, Map<dynamic, dynamic> before) async {
    try {
      await _step('journal.complete');
      // Keep the encrypted snapshot with its phase. Never delete the only
      // rollback record while a failed disk flush might still need it.
      await journal.put('transaction', {
        'version': 1,
        'phase': 'complete',
        'before': before,
      });
      await _step('journal.complete.flush');
      await journal.flush();
      _recoveryRequired = false;
      // Once phase=complete is durable, removing the obsolete undo payload is
      // safe. A cleanup error cannot turn a completed transaction into pending.
      try {
        await journal.delete('transaction');
        await journal.flush();
      } catch (_) {
        // The encrypted completed record can be removed on the next startup.
      }
      return true;
    } catch (_) {
      _recoveryRequired = true;
      return false;
    }
  }

  static const _needsRecovery = HiveRestoreResult(
      ok: false,
      recoveryRequired: true,
      message: 'La restauración no se ha podido cerrar de forma segura. '
          'Reintenta la comprobación o recuperación local antes de seguir usando tus datos.');

  static Map<dynamic, dynamic> _snapshot(
          Box<dynamic> udm, Box<DiaryEntry> diary) =>
      {
        'udm': _copyLocalValue(udm.toMap()),
        'diary': {
          for (final key in diary.keys) key: _entryMap(diary.get(key)!)
        },
      };

  static Map<String, dynamic> _entryMap(DiaryEntry entry) => {
        'text': entry.text,
        'mood': entry.mood,
        'createdAt': entry.createdAt,
      };

  static DiaryEntry _cloneEntry(DiaryEntry entry) => DiaryEntry(
      text: entry.text, mood: entry.mood, createdAt: entry.createdAt);

  static dynamic _copyLocalValue(dynamic value) {
    if (value is Map) {
      return {for (final e in value.entries) e.key: _copyLocalValue(e.value)};
    }
    if (value is List) return value.map(_copyLocalValue).toList();
    return value;
  }

  static Map<dynamic, dynamic> _validateSnapshot(dynamic value) {
    if (value is! Map || value['udm'] is! Map || value['diary'] is! Map) {
      throw const FormatException('Invalid recovery snapshot.');
    }
    for (final key in (value['udm'] as Map).keys) {
      if (key is! String && key is! int) {
        throw const FormatException('Invalid local key.');
      }
    }
    _entriesFromSnapshot(value['diary'] as Map);
    return Map<dynamic, dynamic>.from(value);
  }

  static Map<dynamic, DiaryEntry> _entriesFromSnapshot(Map entries) {
    final result = <dynamic, DiaryEntry>{};
    for (final entry in entries.entries) {
      final value = entry.value;
      if ((entry.key is! String && entry.key is! int) ||
          value is! Map ||
          value['text'] is! String ||
          value['mood'] is! int ||
          value['createdAt'] is! DateTime) {
        throw const FormatException('Invalid inventory recovery snapshot.');
      }
      // Preserve local legacy data exactly, even if a historical mood was
      // outside today's range. Validation of incoming Drive data stays strict.
      result[entry.key] = DiaryEntry(
          text: value['text'] as String,
          mood: value['mood'] as int,
          createdAt: value['createdAt'] as DateTime);
    }
    return result;
  }

  static bool _equal(dynamic a, dynamic b) {
    if (a is DateTime && b is DateTime) {
      // Hive's existing adapter persists DateTime at millisecond precision.
      return a.millisecondsSinceEpoch == b.millisecondsSinceEpoch &&
          a.isUtc == b.isUtc;
    }
    if (a is Map && b is Map) {
      return a.length == b.length &&
          a.keys.every((k) => b.containsKey(k) && _equal(a[k], b[k]));
    }
    if (a is List && b is List) {
      return a.length == b.length &&
          List.generate(a.length, (i) => i).every((i) => _equal(a[i], b[i]));
    }
    return a == b;
  }
}
