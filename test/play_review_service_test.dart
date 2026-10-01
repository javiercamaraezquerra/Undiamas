import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:un_dia_mas/services/play_review_service.dart';

class MemoryReviewPreferences implements PlayReviewPreferences {
  String? value;
  bool failWrite = false;
  bool throwRead = false;
  bool throwWrite = false;
  Completer<bool>? pendingWrite;
  int writes = 0;

  @override
  Future<String?> read() async {
    if (throwRead) throw StateError('private internal detail');
    return value;
  }

  @override
  Future<bool> write(String next) async {
    writes++;
    if (throwWrite) throw StateError('private internal detail');
    final committed =
        pendingWrite == null ? !failWrite : await pendingWrite!.future;
    if (committed) value = next;
    return committed;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryReviewPreferences storage;
  late DateTime now;
  late List<Uri> links;
  late PlayReviewService service;

  setUp(() {
    storage = MemoryReviewPreferences();
    now = DateTime(2026, 10, 1, 12);
    links = [];
    service = PlayReviewService(
      preferences: storage,
      now: () => now,
      launch: (uri) async {
        links.add(uri);
        return true;
      },
    );
  });
  tearDown(() => service.dispose());

  Future<void> threeDays() async {
    for (final day in [1, 2, 3]) {
      now = DateTime(2026, 10, day, 12);
      await service.recordUsageDay();
    }
  }

  test('three distinct used dates, never three opens or installation age',
      () async {
    await service.recordUsageDay();
    await service.recordUsageDay();
    await service.recordUsageDay();
    expect(await service.claimInvitation(canShow: () => true), isFalse);
    expect(storage.writes, 1);
    now = DateTime(2026, 11, 1);
    await service.recordUsageDay();
    expect(await service.claimInvitation(canShow: () => true), isFalse);
    now = DateTime(2026, 11, 2);
    await service.recordUsageDay();
    expect(await service.claimInvitation(canShow: () => true), isTrue);
    expect(await service.claimInvitation(canShow: () => true), isFalse);
  });

  test('day counting survives restart and suppression survives another restart',
      () async {
    await threeDays();
    service.dispose();
    service = PlayReviewService(preferences: storage);
    expect(await service.claimInvitation(canShow: () => true), isTrue);
    service.dispose();
    service = PlayReviewService(preferences: storage);
    expect(await service.claimInvitation(canShow: () => true), isFalse);
  });

  test('concurrent interactions cannot overwrite history or claim twice',
      () async {
    await threeDays();
    final claims = await Future.wait([
      service.claimInvitation(canShow: () => true),
      service.claimInvitation(canShow: () => true),
      service.recordUsageDay().then((_) => false),
    ]);
    expect(claims.where((value) => value).length, 1);
    expect((jsonDecode(storage.value!)['days'] as List).length, 3);
  });

  test('blocked context leaves invitation available for a later neutral moment',
      () async {
    await threeDays();
    expect(await service.claimInvitation(canShow: () => false), isFalse);
    expect(await service.claimInvitation(canShow: () => true), isTrue);
  });

  test('navigation during persistence skips the prompt and never repeats it',
      () async {
    await threeDays();
    storage.pendingWrite = Completer<bool>();
    var current = true;
    final claiming = service.claimInvitation(canShow: () => current);
    await Future<void>.delayed(Duration.zero);
    current = false;
    storage.pendingWrite!.complete(true);
    expect(await claiming, isFalse);
    expect(await service.claimInvitation(canShow: () => true), isFalse);
  });

  for (final throws in [false, true]) {
    test(
        'failed durable reservation skips dialog (${throws ? 'throw' : 'false'})',
        () async {
      await threeDays();
      storage.failWrite = !throws;
      storage.throwWrite = throws;
      expect(await service.claimInvitation(canShow: () => true), isFalse);
      expect(await service.claimInvitation(canShow: () => true), isFalse);
    });
  }

  test('failed day write does not manufacture a day of usage', () async {
    storage.failWrite = true;
    await service.recordUsageDay();
    storage.failWrite = false;
    now = DateTime(2026, 10, 2);
    await service.recordUsageDay();
    now = DateTime(2026, 10, 3);
    await service.recordUsageDay();
    expect(await service.claimInvitation(canShow: () => true), isFalse);
  });

  for (final malformed in [
    '{not json',
    '{"version":1,"days":["2026-02-30"],"prompted":false}',
    '{"version":2,"days":[],"prompted":false}',
  ]) {
    test(
        'unreadable history suppresses auto request, voluntary listing still opens $malformed',
        () async {
      storage.value = malformed;
      await threeDays();
      expect(await service.claimInvitation(canShow: () => true), isFalse);
      expect(await service.openListing(), isTrue);
      expect(storage.value, malformed);
    });
  }

  test(
      'successful manual listing visit suppresses future automatic invitation only',
      () async {
    await threeDays();
    expect(await service.openListing(), isTrue);
    expect(await service.claimInvitation(canShow: () => true), isFalse);
    expect(await service.openListing(), isTrue);
    expect(links, [PlayReviewService.marketUri, PlayReviewService.marketUri]);
    expect(storage.value, isNot(contains('rated')));
  });

  test(
      'market exception falls back to HTTPS without preview package or private data',
      () async {
    service.dispose();
    service = PlayReviewService(
        preferences: storage,
        launch: (uri) async {
          links.add(uri);
          if (uri.scheme == 'market') throw StateError('No Play');
          return true;
        });
    expect(await service.openListing(), isTrue);
    expect(links, [PlayReviewService.marketUri, PlayReviewService.webUri]);
    expect(
        links.every(
            (uri) => uri.queryParameters['id'] == 'com.celsoriaapps.undiamas'),
        isTrue);
  });

  test('failed link is retryable and does not suppress invitation', () async {
    service.dispose();
    service = PlayReviewService(
        preferences: storage,
        now: () => now,
        launch: (uri) async {
          links.add(uri);
          return false;
        });
    await threeDays();
    expect(await service.openListing(), isFalse);
    expect(await service.openListing(), isFalse);
    expect(links.length, 4);
    expect(await service.claimInvitation(canShow: () => true), isTrue);
  });

  test(
      'single flight; context loss blocks web fallback after async platform failure',
      () async {
    final pending = Completer<bool>();
    var available = true;
    service.dispose();
    service = PlayReviewService(
        preferences: storage,
        launch: (uri) {
          links.add(uri);
          return pending.future;
        });
    final first = service.openListing(canLaunch: () => available);
    expect(await service.openListing(), isFalse);
    available = false;
    pending.complete(false);
    expect(await first, isFalse);
    expect(links, [PlayReviewService.marketUri]);
  });

  test(
      'shared preferences stores only bounded device history and keeps other data',
      () async {
    SharedPreferences.setMockInitialValues(
        {'isDarkMode': true, 'start_date': 'old'});
    service.dispose();
    service = PlayReviewService(now: () => now, launch: (_) async => true);
    await threeDays();
    expect(await service.claimInvitation(canShow: () => true), isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('isDarkMode'), isTrue);
    expect(prefs.getString('start_date'), 'old');
    final history =
        jsonDecode(prefs.getString(PlayReviewService.preferenceKey)!);
    expect(history.keys.toSet(), {'version', 'days', 'prompted'});
    expect(history['days'], hasLength(3));
  });
}
