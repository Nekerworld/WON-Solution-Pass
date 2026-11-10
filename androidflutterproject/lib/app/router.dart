import 'package:flutter/foundation.dart';

/// 화면 ID 허용목록. 이 목록 밖의 화면으로는 이동하지 않는다.
enum ScreenId {
  home,
  transfer,
  plan,
  otp,
  limit,
  kyc,
  result,
  support,
  chat;

  static ScreenId? parse(String? id) {
    for (final s in ScreenId.values) {
      if (s.name == id) return s;
    }
    return null;
  }
}

typedef Params = Map<String, Object?>;
typedef ScreenLoader = Future<Object?> Function(ScreenId id, Params params);

class RouteEntry {
  const RouteEntry({
    required this.id,
    required this.params,
    required this.data,
    required this.key,
    required this.version,
    required this.nav,
  });

  final ScreenId id;
  final Params params;

  /// 화면을 그리기 전에 미리 조회한 데이터 (Mock Bank 응답)
  final Object? data;

  /// 같은 key는 같은 페이지(라우트)로 취급된다.
  final int key;

  /// 같은 자리에서 다시 그릴 때마다 증가
  final int version;

  /// 화면 이동마다 새 값. 다시 그리기(rerender)는 유지되어 스크롤 위치를 지킨다.
  final int nav;
}

/// 히스토리 스택 기반 라우터. 화면은 이동 전에 데이터를 조회한 뒤 표시된다.
class AppRouter extends ChangeNotifier {
  AppRouter({required this.loader});

  final ScreenLoader loader;
  List<RouteEntry> _stack = [];
  RouteEntry? _current;
  int _keySeq = 0;
  int _navToken = 0;
  int _rerenderToken = 0;

  RouteEntry? get current => _current;
  List<RouteEntry> get pages => [..._stack, ?_current];
  bool get canGoBack => _stack.isNotEmpty;

  Future<Object?> _load(ScreenId id, Params params) async {
    try {
      return await loader(id, params);
    } catch (e, st) {
      debugPrint('[WSP UI] 화면 데이터 조회 오류 $e\n$st');
      return const ScreenLoadError();
    }
  }

  /// [replace] 현재 화면을 히스토리에 남기지 않는다.
  /// [backTo] 히스토리에 같은 화면이 있으면 그 지점까지 되돌아간다.
  /// [resetHistory] 히스토리를 비운다.
  /// [animate]가 false이고 같은 화면을 replace하면 같은 자리에서 다시 그린다.
  Future<bool> navigate(
    ScreenId id, {
    Params params = const {},
    bool replace = false,
    bool backTo = false,
    bool resetHistory = false,
    bool animate = true,
    int? reuseKey,
  }) async {
    final token = ++_navToken;
    final data = await _load(id, params);
    if (token != _navToken) return false;

    var key = reuseKey;
    if (resetHistory) {
      final all = pages;
      if (all.isNotEmpty && all.first.id == id) key ??= all.first.key;
      _stack = [];
    } else if (backTo) {
      final idx = _stack.lastIndexWhere((e) => e.id == id);
      if (idx >= 0) {
        key ??= _stack[idx].key;
        _stack = _stack.sublist(0, idx);
      }
    } else if (!replace && _current != null) {
      _stack.add(_current!);
    }
    if (replace && !animate && _current?.id == id) key ??= _current!.key;
    if (_stack.length > 20) _stack = _stack.sublist(_stack.length - 20);

    final sameRoute = key != null && key == _current?.key;
    _current = RouteEntry(
      id: id,
      params: Map.unmodifiable(params),
      data: data,
      key: key ?? ++_keySeq,
      version: sameRoute ? _current!.version + 1 : 0,
      nav: token,
    );
    notifyListeners();
    return true;
  }

  /// 현재 화면을 같은 자리에서 다시 그린다.
  Future<void> rerender([Params patch = const {}]) async {
    final cur = _current;
    if (cur == null) return;
    final nav = _navToken;
    final token = ++_rerenderToken;
    final params = {...cur.params, ...patch};
    final data = await _load(cur.id, params);
    if (nav != _navToken || token != _rerenderToken || _current?.key != cur.key) return;
    _current = RouteEntry(
      id: cur.id,
      params: Map.unmodifiable(params),
      data: data,
      key: cur.key,
      version: cur.version + 1,
      nav: cur.nav,
    );
    notifyListeners();
  }

  /// 이전 화면으로 돌아가 다시 그린다. 히스토리가 없으면 홈으로 간다.
  Future<void> goBack() async {
    if (_stack.isEmpty) {
      await navigate(ScreenId.home, resetHistory: true);
      return;
    }
    final prev = _stack.removeLast();
    await navigate(prev.id, params: prev.params, replace: true, reuseKey: prev.key);
  }

  void resetHistory() => _stack = [];
}

class ScreenLoadError {
  const ScreenLoadError();
}
