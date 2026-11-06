import 'dart:async';

import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod/riverpod.dart';

class MockCoreHandlerInterface extends Mock implements CoreHandlerInterface {}

const runningVersion = '0.8.96';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockCoreHandlerInterface core;

  setUpAll(() {
    core = MockCoreHandlerInterface();
    globalState.packageInfo = PackageInfo(
      appName: 'FlClash',
      packageName: 'com.follow.clash',
      version: runningVersion,
      buildNumber: '1',
    );
  });

  setUp(() => reset(core));

  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('CommonAction.updateMode', () {
    test('advances through every mode and wraps back to the first', () {
      final container = buildContainer();
      final action = container.read(commonActionProvider.notifier);
      container
          .read(patchClashConfigProvider.notifier)
          .update((state) => state.copyWith(mode: Mode.values.first));

      final seen = <Mode>[container.read(patchClashConfigProvider).mode];
      for (var i = 0; i < Mode.values.length; i++) {
        action.updateMode();
        seen.add(container.read(patchClashConfigProvider).mode);
      }

      expect(seen.sublist(0, Mode.values.length), Mode.values);
      expect(seen.last, Mode.values.first, reason: 'wraps after the last mode');
    });
  });

  group('CommonAction.updateSpeedStatistics', () {
    test('toggles the tray title flag both ways', () {
      final container = buildContainer();
      final action = container.read(commonActionProvider.notifier);
      final initial = container.read(appSettingProvider).showTrayTitle;

      action.updateSpeedStatistics();
      expect(container.read(appSettingProvider).showTrayTitle, !initial);

      action.updateSpeedStatistics();
      expect(container.read(appSettingProvider).showTrayTitle, initial);
    });
  });

  group('CommonAction.updateTraffic', () {
    test('records the sampled traffic and the running total', () async {
      final container = buildContainer();
      container
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(onlyStatisticsProxy: true));
      when(
        () => core.getTraffic(true),
      ).thenAnswer((_) async => const Traffic(up: 10, down: 20));
      when(
        () => core.getTotalTraffic(true),
      ).thenAnswer((_) async => const Traffic(up: 100, down: 200));

      await container.read(commonActionProvider.notifier).updateTraffic();

      expect(container.read(trafficsProvider).list.last.up, 10);
      expect(container.read(trafficsProvider).list.last.down, 20);
      expect(
        container.read(totalTrafficProvider),
        const Traffic(up: 100, down: 200),
      );
      verify(() => core.getTraffic(true)).called(1);
      verify(() => core.getTotalTraffic(true)).called(1);
    });

    test('a current-only sample leaves the total untouched', () async {
      final container = buildContainer();
      final before = container.read(totalTrafficProvider);
      when(
        () => core.getTraffic(any()),
      ).thenAnswer((_) async => const Traffic(up: 1, down: 2));

      await container
          .read(commonActionProvider.notifier)
          .updateTraffic(includeTotal: false);

      expect(container.read(trafficsProvider).list.last.up, 1);
      expect(container.read(totalTrafficProvider), before);
      verifyNever(() => core.getTotalTraffic(any()));
    });

    test(
      'a full sample adds a total read to an in-flight current read',
      () async {
        final container = buildContainer();
        final current = Completer<Traffic>();
        when(() => core.getTraffic(any())).thenAnswer((_) => current.future);
        when(
          () => core.getTotalTraffic(any()),
        ).thenAnswer((_) async => const Traffic(up: 100));
        final action = container.read(commonActionProvider.notifier);

        final hidden = action.updateTraffic(includeTotal: false);
        await action.updateTraffic();

        expect(container.read(totalTrafficProvider), const Traffic(up: 100));
        verify(() => core.getTraffic(any())).called(1);
        verify(() => core.getTotalTraffic(any())).called(1);
        current.complete(const Traffic(up: 1));
        await hidden;
        expect(container.read(trafficsProvider).list.last.up, 1);
      },
    );

    test('a slow total read does not hold up later current samples', () async {
      final container = buildContainer();
      final total = Completer<Traffic>();
      when(
        () => core.getTraffic(any()),
      ).thenAnswer((_) async => const Traffic(up: 1));
      when(() => core.getTotalTraffic(any())).thenAnswer((_) => total.future);
      final action = container.read(commonActionProvider.notifier);

      final first = action.updateTraffic();
      await Future<void>.delayed(Duration.zero);
      await action.updateTraffic();

      verify(() => core.getTraffic(any())).called(2);
      verify(() => core.getTotalTraffic(any())).called(1);
      total.complete(const Traffic(up: 100));
      await first;
    });

    test(
      'a fresh sample waits for in-flight reads then samples again',
      () async {
        final container = buildContainer();
        final current = Completer<Traffic>();
        final total = Completer<Traffic>();
        when(() => core.getTraffic(any())).thenAnswer((_) => current.future);
        when(() => core.getTotalTraffic(any())).thenAnswer((_) => total.future);
        final action = container.read(commonActionProvider.notifier);

        final first = action.updateTraffic();
        final fresh = action.updateTraffic(fresh: true);
        current.complete(const Traffic(up: 1));
        await Future<void>.delayed(Duration.zero);
        verify(() => core.getTraffic(any())).called(1);
        verify(() => core.getTotalTraffic(any())).called(1);
        when(
          () => core.getTraffic(any()),
        ).thenAnswer((_) async => const Traffic(up: 2));
        when(
          () => core.getTotalTraffic(any()),
        ).thenAnswer((_) async => const Traffic(up: 200));
        total.complete(const Traffic(up: 100));
        await Future.wait([first, fresh]);

        verify(() => core.getTraffic(any())).called(1);
        verify(() => core.getTotalTraffic(any())).called(1);
        expect(container.read(trafficsProvider).list.last.up, 2);
        expect(container.read(totalTrafficProvider), const Traffic(up: 200));
      },
    );

    for (final pendingTotal in [false, true]) {
      test(
        'a fresh current-only sample ignores a pending total: $pendingTotal',
        () async {
          final container = buildContainer();
          final current = Completer<Traffic>();
          final total = Completer<Traffic>();
          when(() => core.getTraffic(any())).thenAnswer((_) => current.future);
          when(
            () => core.getTotalTraffic(any()),
          ).thenAnswer((_) => total.future);
          final action = container.read(commonActionProvider.notifier);
          final old = action.updateTraffic(includeTotal: pendingTotal);
          var completed = false;
          final fresh = action
              .updateTraffic(includeTotal: false, fresh: true)
              .then((_) => completed = true);
          when(
            () => core.getTraffic(any()),
          ).thenAnswer((_) async => const Traffic(up: 2));

          current.complete(const Traffic(up: 1));
          await Future<void>.delayed(Duration.zero);
          final completedBeforeTotal = completed;
          total.complete(const Traffic(up: 100));
          await Future.wait([old, fresh]);

          expect(completedBeforeTotal, isTrue);
          expect(container.read(trafficsProvider).list.last.up, 2);
          verify(() => core.getTraffic(any())).called(2);
          if (pendingTotal) {
            verify(() => core.getTotalTraffic(any())).called(1);
          } else {
            verifyNever(() => core.getTotalTraffic(any()));
          }
        },
      );
    }

    test('concurrent fresh callers wait for their shared new sample', () async {
      final container = buildContainer();
      final oldCurrent = Completer<Traffic>();
      final oldTotal = Completer<Traffic>();
      final newCurrent = Completer<Traffic>();
      final newTotal = Completer<Traffic>();
      when(() => core.getTraffic(any())).thenAnswer((_) => oldCurrent.future);
      when(
        () => core.getTotalTraffic(any()),
      ).thenAnswer((_) => oldTotal.future);
      final action = container.read(commonActionProvider.notifier);
      final old = action.updateTraffic();
      var firstCompleted = false;
      var secondCompleted = false;
      final first = action.updateTraffic(fresh: true).then((_) {
        firstCompleted = true;
      });
      final second = action.updateTraffic(fresh: true).then((_) {
        secondCompleted = true;
      });
      when(() => core.getTraffic(any())).thenAnswer((_) => newCurrent.future);
      when(
        () => core.getTotalTraffic(any()),
      ).thenAnswer((_) => newTotal.future);

      oldCurrent.complete(const Traffic(up: 1));
      oldTotal.complete(const Traffic(up: 100));
      await old;
      await Future<void>.delayed(Duration.zero);

      verify(() => core.getTraffic(any())).called(2);
      verify(() => core.getTotalTraffic(any())).called(2);
      expect(firstCompleted, isFalse);
      expect(secondCompleted, isFalse);
      newCurrent.complete(const Traffic(up: 2));
      await Future<void>.delayed(Duration.zero);
      expect(firstCompleted, isFalse);
      expect(secondCompleted, isFalse);
      newTotal.complete(const Traffic(up: 200));
      await Future.wait([first, second]);
      expect(container.read(totalTrafficProvider), const Traffic(up: 200));
    });

    test('disposal drops pending results and a waiting fresh sample', () async {
      final container = buildContainer();
      final current = Completer<Traffic>();
      final total = Completer<Traffic>();
      when(() => core.getTraffic(any())).thenAnswer((_) => current.future);
      when(() => core.getTotalTraffic(any())).thenAnswer((_) => total.future);
      final action = container.read(commonActionProvider.notifier);

      final first = action.updateTraffic();
      final fresh = action.updateTraffic(fresh: true);
      container.dispose();
      current.complete(const Traffic(up: 1));
      total.complete(const Traffic(up: 100));
      await expectLater(Future.wait([first, fresh]), completes);

      verify(() => core.getTraffic(any())).called(1);
      verify(() => core.getTotalTraffic(any())).called(1);
    });

    test('swallows a core failure and leaves the total untouched', () async {
      final container = buildContainer();
      final before = container.read(totalTrafficProvider);
      when(() => core.getTraffic(any())).thenThrow(StateError('core down'));

      await expectLater(
        container.read(commonActionProvider.notifier).updateTraffic(),
        completes,
      );
      expect(container.read(totalTrafficProvider), before);
    });

    test('does not record a total when only the total call fails', () async {
      final container = buildContainer();
      final before = container.read(totalTrafficProvider);
      when(
        () => core.getTraffic(any()),
      ).thenAnswer((_) async => const Traffic(up: 1, down: 2));
      when(() => core.getTotalTraffic(any())).thenThrow(StateError('boom'));

      await container.read(commonActionProvider.notifier).updateTraffic();

      expect(container.read(trafficsProvider).list.last.up, 1);
      expect(container.read(totalTrafficProvider), before);
    });

    test(
      'a failed query releases its in-flight guard for the next sample',
      () async {
        final container = buildContainer();
        when(
          () => core.getTraffic(any()),
        ).thenThrow(StateError('current failed'));
        when(
          () => core.getTotalTraffic(any()),
        ).thenThrow(StateError('total failed'));
        final action = container.read(commonActionProvider.notifier);
        await action.updateTraffic();
        when(
          () => core.getTraffic(any()),
        ).thenAnswer((_) async => const Traffic(up: 1));
        when(
          () => core.getTotalTraffic(any()),
        ).thenAnswer((_) async => const Traffic(up: 100));

        await action.updateTraffic();

        expect(container.read(trafficsProvider).list.last.up, 1);
        expect(container.read(totalTrafficProvider), const Traffic(up: 100));
        verify(() => core.getTraffic(any())).called(2);
        verify(() => core.getTotalTraffic(any())).called(2);
      },
    );

    test(
      'drops concurrent in-flight updates while one is in progress',
      () async {
        final container = buildContainer();
        final completer = Completer<Traffic>();
        when(() => core.getTraffic(any())).thenAnswer((_) => completer.future);
        when(
          () => core.getTotalTraffic(any()),
        ).thenAnswer((_) => completer.future);

        final first = container
            .read(commonActionProvider.notifier)
            .updateTraffic();
        final second = container
            .read(commonActionProvider.notifier)
            .updateTraffic();

        await expectLater(second, completes);
        completer.complete(const Traffic(up: 5, down: 10));
        await first;

        verify(() => core.getTraffic(any())).called(1);
        verify(() => core.getTotalTraffic(any())).called(1);
      },
    );
  });

  group('CommonAction.autoCheckUpdate', () {
    test('returns without a network call when the setting is off', () async {
      final container = buildContainer();
      container
          .read(appSettingProvider.notifier)
          .update((state) => state.copyWith(autoCheckUpdate: false));

      await expectLater(
        container.read(commonActionProvider.notifier).autoCheckUpdate(),
        completion(isFalse),
      );
    });
  });
}
