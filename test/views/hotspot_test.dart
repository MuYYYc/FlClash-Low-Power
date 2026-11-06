import 'package:fl_clash/common/windows_hotspot.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/hotspot.dart';
import 'package:fl_clash/views/config/hotspot.dart';
import 'package:flutter/widgets.dart';
import 'package:prism_ui/prism_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import '../helpers/host_scaffold.dart';

class _Backend implements HotspotBackend {
  final calls = <HotspotCommand>[];

  @override
  Future<HotspotSnapshot> execute(HotspotCommand command) async {
    calls.add(command);
    return const HotspotSnapshot(managed: true, on: true, throughTun: true);
  }
}

void main() {
  Future<void> pump(
    WidgetTester tester,
    _Backend backend, {
    bool safeMode = false,
    bool ready = true,
  }) async {
    await tester.pumpWidget(
      TestApp(
        locale: const Locale('zh', 'CN'),
        overrides: [
          hotspotBackendProvider.overrideWithValue(backend),
          hotspotSupportedProvider.overrideWithValue(true),
          hotspotReadyProvider.overrideWithValue(ready),
          safeModeProvider.overrideWithValue(safeMode),
        ],
        child: const HostScaffold(body: HotspotSharingSection()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('显示中文开关并调用共享入口', (tester) async {
    final backend = _Backend();
    await pump(tester, backend);
    expect(find.text('热点共享分流'), findsWidgets);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(backend.calls, [HotspotCommand.enable]);
  });

  testWidgets('安全模式开关不可操作且不会调用系统', (tester) async {
    final backend = _Backend();
    await pump(tester, backend, safeMode: true);
    expect(find.text('安全模式仅预览，不修改热点'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    expect(backend.calls, isEmpty);
  });

  testWidgets('缺少规则模式 TUN 时明确提示且不启动热点', (tester) async {
    final backend = _Backend();
    await pump(tester, backend, ready: false);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(find.text('请先启动代理，开启 TUN 并使用规则模式'), findsOneWidget);
    expect(backend.calls, isEmpty);
  });
}
