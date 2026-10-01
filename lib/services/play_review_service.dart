import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

abstract class PlayReviewPreferences {
  Future<String?> read();
  Future<bool> write(String value);
}

/// This device's invitation history, never diary content or a review result.
/// Kept outside Hive/Drive so restoring an old diary cannot repeat the prompt.
class PlayReviewService extends ChangeNotifier {
  PlayReviewService({
    PlayReviewPreferences? preferences,
    Future<bool> Function(Uri)? launch,
    DateTime Function()? now,
  })  : _preferences = preferences ?? _SharedReviewPreferences(),
        _launch = launch ?? _launchExternal,
        _now = now ?? DateTime.now;

  static final instance = PlayReviewService();
  static const preferenceKey = 'playReviewInvitationV1';
  static final marketUri =
      Uri.parse('market://details?id=com.celsoriaapps.undiamas');
  static final webUri = Uri.parse(
      'https://play.google.com/store/apps/details?id=com.celsoriaapps.undiamas');

  final PlayReviewPreferences _preferences;
  final Future<bool> Function(Uri) _launch;
  final DateTime Function() _now;
  Future<void> _queue = Future<void>.value();
  _ReviewHistory? _history;
  bool _read = false;
  bool _sessionSuppressed = false;
  bool _opening = false;
  bool _startupReady = false;

  bool get opening => _opening;
  bool get startupReady => _startupReady;

  void finishStartup() {
    if (_startupReady) return;
    _startupReady = true;
    notifyListeners();
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.then<void>((_) {}, onError: (_, __) {});
    return next;
  }

  Future<_ReviewHistory?> _load() async {
    if (_read) return _history;
    try {
      final raw = await _preferences.read();
      _history =
          raw == null ? _ReviewHistory({}, false) : _ReviewHistory.parse(raw);
    } catch (_) {
      // No trustworthy history: omit automatic requests for this session.
      // The voluntary Play link remains usable.
      _sessionSuppressed = true;
    }
    _read = true;
    return _history;
  }

  /// Called only on an actual foreground interaction with the app's main tabs.
  Future<void> recordUsageDay() => _serialized(() async {
        if (_sessionSuppressed) return;
        final history = await _load();
        if (history == null || history.prompted || history.days.length >= 3) {
          return;
        }
        final date = _now().toLocal();
        final day = '${date.year.toString().padLeft(4, '0')}-'
            '${date.month.toString().padLeft(2, '0')}-'
            '${date.day.toString().padLeft(2, '0')}';
        if (history.days.contains(day)) return;
        final updated = _ReviewHistory({...history.days, day}, false);
        try {
          if (!await _preferences.write(updated.encode())) return;
          _history = updated;
        } catch (_) {
          // A missed invitation is preferable to interrupting normal app use.
        }
      });

  /// Persist before showing: dismiss/back/relaunch never cause repeated asking.
  /// If navigation changes during storage, the invitation is safely skipped.
  Future<bool> claimInvitation({required bool Function() canShow}) =>
      _serialized(() async {
        if (_sessionSuppressed || _opening || !canShow()) return false;
        final history = await _load();
        if (history == null ||
            history.prompted ||
            history.days.length < 3 ||
            !canShow()) {
          return false;
        }
        _sessionSuppressed = true;
        final updated = _ReviewHistory(history.days, true);
        try {
          if (!await _preferences.write(updated.encode())) return false;
          _history = updated;
          return canShow();
        } catch (_) {
          return false;
        }
      });

  /// Both entry points open the real production listing, including previews.
  /// Opening Play says nothing about whether a review was submitted.
  Future<bool> openListing({bool Function()? canLaunch}) async {
    if (_opening || !(canLaunch?.call() ?? true)) return false;
    _opening = true;
    notifyListeners();
    try {
      var opened = false;
      try {
        opened = await _launch(marketUri);
      } catch (_) {
        // Some phones have no Play app. Try its HTTPS listing below.
      }
      if (!opened && (canLaunch?.call() ?? true)) {
        try {
          opened = await _launch(webUri);
        } catch (_) {
          opened = false;
        }
      }
      if (opened) {
        _sessionSuppressed = true;
        await _serialized(() async {
          final history = await _load();
          if (history == null || history.prompted) return;
          final updated = _ReviewHistory(history.days, true);
          try {
            if (await _preferences.write(updated.encode())) _history = updated;
          } catch (_) {
            // Play opened successfully; preference failure is not launch failure.
          }
        });
      }
      return opened;
    } finally {
      _opening = false;
      notifyListeners();
    }
  }

  static Future<bool> _launchExternal(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
}

class _ReviewHistory {
  _ReviewHistory(this.days, this.prompted);
  final Set<String> days;
  final bool prompted;

  factory _ReviewHistory.parse(String raw) {
    final value = jsonDecode(raw);
    if (value is! Map ||
        value['version'] != 1 ||
        value['days'] is! List ||
        value['prompted'] is! bool) {
      throw const FormatException('Invalid invitation history');
    }
    final days = <String>{};
    for (final day in value['days'] as List) {
      if (day is! String ||
          !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day) ||
          DateTime.tryParse(day)?.toIso8601String().split('T').first != day) {
        throw const FormatException('Invalid invitation day');
      }
      days.add(day);
    }
    if (days.length > 3) throw const FormatException('Invalid day count');
    return _ReviewHistory(days, value['prompted'] as bool);
  }

  String encode() => jsonEncode({
        'version': 1,
        'days': days.toList(),
        'prompted': prompted,
      });
}

class _SharedReviewPreferences implements PlayReviewPreferences {
  @override
  Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getString(PlayReviewService.preferenceKey);
  }

  @override
  Future<bool> write(String value) async =>
      (await SharedPreferences.getInstance())
          .setString(PlayReviewService.preferenceKey, value);
}
