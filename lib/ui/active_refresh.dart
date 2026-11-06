import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:prism_ui/inherited.dart';
import 'package:prism_ui/route_motion_hold.dart';

mixin ActiveRefreshMixin<T extends StatefulWidget>
    on State<T>, RouteMotionHoldMixin<T> {
  late final AppLifecycleListener _lifecycle;
  Timer? _refreshTimer;
  VoidCallback? _pendingRefresh;
  bool _pageActive = false;
  bool _attached = true;
  bool _resumeScheduled = false;

  bool get _canRefresh =>
      mounted &&
      _attached &&
      _pageActive &&
      switch (WidgetsBinding.instance.lifecycleState) {
        null || AppLifecycleState.resumed || AppLifecycleState.inactive => true,
        _ => false,
      };

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: (_) => _syncRefresh());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pageActive =
        PageActivityScope.isActiveOf(context) &&
        TickerMode.valuesOf(context).enabled;
    _syncRefresh();
  }

  void scheduleActiveRefresh(VoidCallback refresh, {required Duration delay}) {
    _pendingRefresh = refresh;
    if (!_canRefresh || _resumeScheduled) return;
    _refreshTimer ??= Timer(delay, _releaseRefresh);
  }

  void _cancelTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  void _syncRefresh() {
    if (!_canRefresh) {
      _cancelTimer();
      return;
    }
    if (_pendingRefresh == null || _resumeScheduled || _refreshTimer != null) {
      return;
    }
    _resumeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resumeScheduled = false;
      _releaseRefresh();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _releaseRefresh() {
    _cancelTimer();
    if (!_canRefresh || _pendingRefresh == null) return;
    updateWhenRouteSettled(_runRefresh);
  }

  void _runRefresh() {
    if (!_canRefresh) return;
    final refresh = _pendingRefresh;
    _pendingRefresh = null;
    _cancelTimer();
    refresh?.call();
  }

  @override
  void deactivate() {
    _attached = false;
    _cancelTimer();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _attached = true;
    _pageActive = false;
  }

  @override
  void dispose() {
    _attached = false;
    _pendingRefresh = null;
    _cancelTimer();
    _lifecycle.dispose();
    super.dispose();
  }
}
