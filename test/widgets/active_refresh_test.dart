import 'dart:async';

import 'package:fl_clash/ui/active_refresh.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';

import '../helpers/test_app.dart';
import '../helpers/host_scaffold.dart';

const _delay = Duration(milliseconds: 300);

class _Feed extends StatefulWidget {
  const _Feed({super.key, required this.source, required this.refreshes});

  final ValueNotifier<int> source;
  final List<int> refreshes;

  @override
  State<_Feed> createState() => _FeedState();
}

class _FeedState extends State<_Feed>
    with RouteMotionHoldMixin<_Feed>, ActiveRefreshMixin<_Feed> {
  late int _shown = widget.source.value;

  @override
  void initState() {
    super.initState();
    widget.source.addListener(_changed);
  }

  void _changed() {
    scheduleActiveRefresh(() {
      widget.refreshes.add(widget.source.value);
      setState(() => _shown = widget.source.value);
    }, delay: _delay);
  }

  @override
  void dispose() {
    widget.source.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('shown $_shown');
}

void main() {
  late ValueNotifier<int> source;
  late ValueNotifier<bool> active;
  late List<int> refreshes;
  late GlobalKey<NavigatorState> navigator;

  setUp(() {
    source = ValueNotifier(0);
    active = ValueNotifier(true);
    refreshes = [];
    navigator = GlobalKey<NavigatorState>();
  });

  tearDown(() {
    source.dispose();
    active.dispose();
  });

  Future<void> mount(
    WidgetTester tester, {
    bool useTickerMode = false,
    GlobalKey<_FeedState>? feedKey,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      HostApp(
        navigatorKey: navigator,
        home: ValueListenableBuilder(
          valueListenable: active,
          builder: (_, value, child) => useTickerMode
              ? TickerMode(enabled: value, child: child!)
              : PageActivityScope(isActive: value, child: child!),
          child: _Feed(key: feedKey, source: source, refreshes: refreshes),
        ),
      ),
    );
  }

  void hide(WidgetTester tester) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }

  void show(WidgetTester tester) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  testWidgets('throttles visible bursts and keeps refreshing without focus', (
    tester,
  ) async {
    await mount(tester);
    source.value = 1;
    await tester.pump(const Duration(milliseconds: 100));
    source.value = 2;
    await tester.pump(const Duration(milliseconds: 199));
    expect(refreshes, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(refreshes, [2]);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    source.value = 3;
    await tester.pump(_delay);
    expect(refreshes, [2, 3]);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  for (final useTickerMode in [false, true]) {
    testWidgets('coalesces off-page updates (TickerMode: $useTickerMode)', (
      tester,
    ) async {
      await mount(tester, useTickerMode: useTickerMode);
      source.value = 1;
      active.value = false;
      await tester.pump();
      for (var i = 2; i <= 20; i++) {
        source.value = i;
        await tester.pump(_delay);
      }
      expect(refreshes, isEmpty);
      expect(find.text('shown 0'), findsOneWidget);
      active.value = true;
      await tester.pumpAndSettle();
      expect(refreshes, [20]);
      expect(find.text('shown 20'), findsOneWidget);
      await tester.pump(_delay);
      expect(refreshes, [20]);
    });
  }

  testWidgets('cancels pending work when hidden and catches up once shown', (
    tester,
  ) async {
    await mount(tester);
    source.value = 1;
    hide(tester);
    for (var i = 2; i <= 20; i++) {
      source.value = i;
      await tester.pump(_delay);
    }
    expect(refreshes, isEmpty);
    show(tester);
    await tester.pumpAndSettle();
    expect(refreshes, [20]);
    expect(find.text('shown 20'), findsOneWidget);
  });

  testWidgets('window visibility does not resume an inactive page', (
    tester,
  ) async {
    await mount(tester);
    active.value = false;
    await tester.pump();
    hide(tester);
    source.value = 10;
    show(tester);
    await tester.pumpAndSettle();
    expect(refreshes, isEmpty);
    active.value = true;
    await tester.pumpAndSettle();
    expect(refreshes, [10]);
  });

  testWidgets('a route-held update stays pending if the window hides', (
    tester,
  ) async {
    await mount(tester);
    navigator.currentState!.didStartUserGesture();
    source.value = 1;
    await tester.pump(_delay);
    expect(refreshes, isEmpty);
    hide(tester);
    navigator.currentState!.didStopUserGesture();
    source.value = 2;
    await tester.pump(_delay);
    expect(refreshes, isEmpty);
    show(tester);
    await tester.pumpAndSettle();
    expect(refreshes, [2]);
  });

  testWidgets('an opaque route pauses the covered feed until it is uncovered', (
    tester,
  ) async {
    await mount(tester);
    navigator.currentState!.push(
      CardPageRoute<void>(builder: (_) => const HostScaffold()),
    );
    await tester.pumpAndSettle();
    source.value = 1;
    await tester.pump(_delay);
    expect(refreshes, isEmpty);
    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    source.value = 2;
    expect(refreshes, isEmpty);
    await tester.pumpAndSettle();
    expect(refreshes, [2]);
  });

  testWidgets('disposing cancels timer and resume callbacks', (tester) async {
    await mount(tester);
    source.value = 1;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(_delay);
    expect(refreshes, isEmpty);
    await mount(tester);
    hide(tester);
    source.value = 2;
    show(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(_delay);
    expect(refreshes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reparenting resumes a pending update exactly once', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final feedKey = GlobalKey<_FeedState>();
    await tester.pumpWidget(
      HostApp(
        home: ValueListenableBuilder(
          valueListenable: active,
          builder: (_, first, child) => Row(
            children: [
              SizedBox(child: first ? child : null),
              SizedBox(child: first ? null : child),
            ],
          ),
          child: _Feed(key: feedKey, source: source, refreshes: refreshes),
        ),
      ),
    );
    final before = feedKey.currentState;
    source.value = 1;
    active.value = false;
    await tester.pumpAndSettle();
    expect(feedKey.currentState, same(before));
    expect(refreshes, [1]);
    await tester.pump(_delay);
    expect(refreshes, [1]);
  });

  testWidgets('a failed refresh does not block the next update', (
    tester,
  ) async {
    final feedKey = GlobalKey<_FeedState>();
    await mount(tester, feedKey: feedKey);
    final errors = <Object>[];
    runZonedGuarded(
      () => feedKey.currentState!.scheduleActiveRefresh(
        () => throw StateError('refresh failed'),
        delay: _delay,
      ),
      (error, _) => errors.add(error),
    );
    await tester.pump(_delay);
    expect(errors.single, isA<StateError>());
    source.value = 1;
    await tester.pump(_delay);
    expect(refreshes, [1]);
  });
}
