/// 앱 공통 오케스트레이션.
/// - 트랙별 상태머신 3개(가입 지원 AI / 직접 가입 / 자산관리)와 화면 세션을 보관한다.
/// - 앱을 다시 열면 세션을 복원하고, 처리 중이던 단계는 각 흐름의 resume()이 은행 재조회로 이어 간다.
/// - 데모 초기화 시 epoch를 올려 진행 중이던 비동기 흐름이 이후 상태를 건드리지 못하게 한다.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/bank_store.dart';
import '../data/key_value_storage.dart';
import '../data/mock_bank.dart';
import '../domain/bank_state.dart';
import '../domain/bank_types.dart';
import '../domain/event_log.dart';
import '../domain/formatters.dart';
import '../domain/fsm.dart';
import '../domain/pathfinder.dart';
import '../domain/scenario.dart';
import 'ai_agent.dart';
import 'asset_flow.dart';
import 'direct_flow.dart';
import 'join_flow.dart';
import 'overlays.dart';
import 'router.dart';
import 'sessions.dart';

const String sessionKey = 'wsp.session.v3';

/// 화면 데이터 (이동 전에 가상 은행에서 조회)
class HomeData {
  const HomeData(this.summary);
  final BankResult<AccountSummary> summary;
}

class MenuData {
  const MenuData(this.conditions);
  final BankResult<ConditionsData> conditions;
}

class AccountData {
  const AccountData(this.summary);
  final BankResult<AccountSummary> summary;
}

class AppController extends ChangeNotifier {
  AppController({
    required this.store,
    required this.bank,
    required this.events,
    required this.pathfinder,
    required this.ai,
    this.storage,
    this.headless = false,
  }) {
    fsms = {for (final k in FsmKind.values) k: Fsm(k, events: events)};
    router = AppRouter(loader: _loadScreen);
    join = JoinFlow(this);
    direct = DirectFlow(this);
    asset = AssetFlow(this);
    _load();
    for (final f in fsms.values) {
      f.addListener(_onFsmChanged);
    }
    store.addListener(_refreshDataSoon);
  }

  final BankStore store;
  final MockBank bank;
  final EventLog events;
  final Pathfinder pathfinder;
  final AiAgent ai;
  final KeyValueStorage? storage;

  /// 자가 테스트용: 화면 이동·모달을 그리지 않고, 확인 모달은 자동 승인한다.
  final bool headless;

  late final Map<FsmKind, Fsm> fsms;
  late final AppRouter router;
  late final JoinFlow join;
  late final DirectFlow direct;
  late final AssetFlow asset;

  Fsm get joinFsm => fsms[FsmKind.join]!;
  Fsm get directFsm => fsms[FsmKind.direct]!;
  Fsm get assetFsm => fsms[FsmKind.asset]!;

  AppSession session = AppSession();
  int _epoch = 0;
  int get epoch => _epoch;
  final Set<String> _busy = {};
  Timer? _dataTimer;

  /* ==================================================================
   * 오버레이 상태 (셸이 그린다)
   * ================================================================== */
  SheetState? sheet;
  ConfirmRequest? modal;
  TaskModalState? taskModal;
  final List<ToastMessage> toasts = [];
  int _toastSeq = 0;

  /// 지연 대기. 가상 은행의 지연 배율을 따른다.
  Future<void> sleep(num ms) {
    final v = ms.round();
    return v > 0 ? Future.delayed(Duration(milliseconds: v)) : Future.value();
  }

  /* ==================================================================
   * 세션 저장 / 복원
   * ================================================================== */

  void save() {
    final s = storage;
    if (s == null) return;
    try {
      s.write(
        sessionKey,
        jsonEncode({
          'fsm': {
            for (final e in fsms.entries) e.key.name: {'state': e.value.state, 'history': e.value.history().map((h) => h.toJson()).toList()},
          },
          'session': session.toJson(),
        }),
      );
    } catch (e) {
      debugPrint('[WSP] 세션 저장 실패 $e');
    }
  }

  void _load() {
    final raw = storage?.read(sessionKey);
    if (raw == null) return;
    try {
      final d = asJson(jsonDecode(raw));
      session = AppSession.fromJson(asJson(d['session']));
      final f = asJson(d['fsm']);
      for (final e in fsms.entries) {
        final saved = f[e.key.name];
        if (saved is! Map) continue;
        final states = fsmTables[e.key]!.states;
        final st = saved['state'] as String?;
        if (st == null || !states.contains(st)) continue;
        final history = asList(saved['history']).map(TransitionRecord.fromJson).whereType<TransitionRecord>().toList();
        e.value.restore(st, history);
      }
      events.add('APP', '세션 복원 (가입 ${joinFsm.state} / 직접 ${directFsm.state} / 자산 ${assetFsm.state})');
    } catch (e) {
      debugPrint('[WSP] 세션 복원 실패 $e');
      session = AppSession();
    }
  }

  void _onFsmChanged() {
    save();
    notifyListeners();
  }

  /// 은행 상태가 바뀌면 은행 데이터를 쓰는 화면을 다시 조회한다
  void _refreshDataSoon() {
    if (headless) return;
    _dataTimer?.cancel();
    _dataTimer = Timer(const Duration(milliseconds: 120), () {
      final id = router.current?.id;
      if (id == ScreenId.home || id == ScreenId.menu || id == ScreenId.apply || id == ScreenId.direct) router.rerender();
    });
  }

  /// 저장하고 화면을 다시 그린다. [screens]가 있으면 그 화면이 열려 있을 때만 다시 조회한다.
  void refresh([List<ScreenId>? screens]) {
    save();
    notifyListeners();
    if (headless) return;
    final cur = router.current;
    if (cur == null) return;
    if (screens == null || screens.contains(cur.id)) router.rerender();
  }

  /// 같은 동작의 중복 실행(연타)을 막는다
  Future<T?> guard<T>(String name, Future<T> Function() fn) async {
    if (_busy.contains(name)) return null;
    _busy.add(name);
    try {
      return await fn();
    } finally {
      _busy.remove(name);
    }
  }

  bool isBusy(String name) => _busy.contains(name);

  /// 진행 중인 비동기 흐름의 이후 결과를 무효로 만든다
  void invalidate() => _epoch += 1;

  /// 자가 테스트·시연 제어가 세션을 바꿔 끼울 때만 쓴다
  void replaceSession(AppSession? s) {
    session = s ?? AppSession();
    save();
    notifyListeners();
  }

  void resetDemo() {
    _epoch += 1;
    closeAllOverlays();
    store.reset('데모 초기화');
    for (final f in fsms.values) {
      f.reset();
    }
    // AI 경로와 직접 가입을 같은 초기 상태에서 번갈아 시연해 비교할 수 있도록 지난 기록은 남긴다
    final lastJoin = session.lastJoinMetrics, lastDirect = session.lastDirectMetrics;
    session = AppSession()
      ..lastJoinMetrics = lastJoin
      ..lastDirectMetrics = lastDirect;
    ai.clearTrace();
    events.clear();
    events.add('APP', '데모 초기화');
    save();
    notifyListeners();
    navigate(ScreenId.home, resetHistory: true, animate: false);
  }

  /* ==================================================================
   * 화면 이동
   * ================================================================== */

  /// 허용목록 화면으로만 이동한다. 이동 뒤 처리 중이던 단계를 이어 간다.
  Future<bool> navigate(
    ScreenId id, {
    Params params = const {},
    bool replace = false,
    bool backTo = false,
    bool resetHistory = false,
    bool animate = true,
  }) async {
    if (headless) return true;
    final ok = await router.navigate(id, params: params, replace: replace, backTo: backTo, resetHistory: resetHistory, animate: animate);
    if (ok) _afterNavigate(id, params);
    return ok;
  }

  void _afterNavigate(ScreenId id, Params params) {
    switch (id) {
      case ScreenId.join:
        join.resume();
      case ScreenId.applyResult:
        if (params['track'] == 'direct') {
          direct.resume();
        } else {
          join.resume();
        }
      case ScreenId.direct:
        direct.resume();
      case ScreenId.asset:
        asset.resume();
      case ScreenId.support:
        ensureHandoff(params['track'] == 'asset' ? 'asset' : 'join');
      default:
    }
  }

  Future<void> goBack() async {
    if (headless) return;
    await router.goBack();
  }

  Future<Object?> _loadScreen(ScreenId id, Params p) async {
    switch (id) {
      case ScreenId.home:
        return HomeData(await bank.getAccountSummary());
      case ScreenId.menu:
        return MenuData(await bank.checkConditions(products.first.id));
      case ScreenId.apply:
        if (session.join == null || joinFsm.state != 'READY_TO_APPLY') return null;
        return AccountData(await bank.getAccountSummary());
      case ScreenId.direct:
        final d = session.direct;
        if (d == null) return null;
        final p = getProduct(d.productId)!;
        final st = directFsm.state;
        if ((st == 'D_STEP' || st == 'D_CHECK') && p.directSteps[d.stepIndex].id == 'account') {
          return AccountData(await bank.getAccountSummary());
        }
        return null;
      default:
        return null;
    }
  }

  /* ==================================================================
   * 오버레이: 토스트 / 시트 / 확인 모달 / 업무 모달
   * ================================================================== */

  void toast(String text, [UiTone tone = UiTone.neutral]) {
    if (headless) return;
    final msg = ToastMessage(id: ++_toastSeq, text: text, tone: tone);
    toasts.add(msg);
    while (toasts.length > 2) {
      toasts.removeAt(0);
    }
    notifyListeners();
    Timer(const Duration(milliseconds: 2600), () {
      toasts.remove(msg);
      notifyListeners();
    });
  }

  void openSheet(SheetState value, {VoidCallback? onClose}) {
    if (headless) return;
    closeSheet();
    value.onClose = onClose;
    sheet = value;
    notifyListeners();
  }

  void closeSheet() {
    final s = sheet;
    if (s == null) return;
    sheet = null;
    s.onClose?.call();
    notifyListeners();
  }

  /// 시트 바깥(배경)을 눌렀을 때
  void dismissSheet() {
    if (sheet?.dismissible == true) closeSheet();
  }

  Future<bool> confirm(ConfirmRequest request) {
    if (headless) return Future.value(true);
    modal?.resolve(false);
    modal = request;
    notifyListeners();
    return request.completer.future.whenComplete(() {
      if (modal == request) {
        modal = null;
        notifyListeners();
      }
    });
  }

  void resolveModal(bool value) => modal?.resolve(value);

  bool get isTaskModalOpen => taskModal != null;

  void openTaskModal(String taskId, String sessionId, {required String mode, void Function(String status)? onClose}) {
    if (headless) return;
    closeTaskModal(silent: true);
    taskModal = TaskModalState(taskId: taskId, sessionId: sessionId, mode: mode, onClose: onClose);
    notifyListeners();
  }

  void closeTaskModal({bool silent = false}) {
    final cur = taskModal;
    if (cur == null) return;
    taskModal = null;
    notifyListeners();
    final status = cur.status == 'RUNNING' ? 'OPEN' : cur.status;
    if (!silent) cur.onClose?.call(status);
  }

  /// 업무 모달의 닫기 버튼 (처리 중에는 닫지 않는다)
  void taskModalClose() {
    if (taskModal == null || taskModal!.running) return;
    closeTaskModal();
  }

  void taskModalField(String field, String value) {
    final tm = taskModal;
    if (tm == null || tm.status != 'OPEN') return;
    tm.input[field] = value;
    tm.changed();
  }

  Future<void> taskModalRun() async {
    final own = taskModal;
    if (own == null || own.status != 'OPEN') return;
    final t = getTask(own.taskId)!;
    for (final f in t.fields) {
      if ((own.input[f.id] ?? '').isEmpty) {
        toast('${josa(f.label, '을')} 선택해 주세요.', UiTone.warning);
        return;
      }
    }
    own.status = 'RUNNING';
    own.progress = 0;
    own.changed();
    final timer = Timer.periodic(Duration(milliseconds: max(120, (260 * (bank.latencyScale == 0 ? 0.5 : bank.latencyScale)).round())), (tm) {
      if (taskModal != own) return tm.cancel();
      if (own.progress < t.steps.length - 1) {
        own.progress += 1;
        own.changed();
      }
    });
    final r = await bank.runTask(own.sessionId, own.input);
    timer.cancel();
    if (taskModal != own) return;
    if (!r.ok) {
      own.status = 'REJECTED';
      own.message = r.error!.message;
    } else {
      own.status = r.data!.status;
      own.message = r.data!.message ?? '';
    }
    own.changed();
  }

  void closeAllOverlays() {
    final s = sheet;
    sheet = null;
    s?.onClose?.call();
    modal?.resolve(false);
    modal = null;
    closeTaskModal(silent: true);
    notifyListeners();
  }

  /* ==================================================================
   * 공통 동작
   * ================================================================== */

  void noop() {}

  Future<void> goHome() => navigate(ScreenId.home, resetHistory: true);

  void toggleBalance() {
    session.ui.hideBalance = !session.ui.hideBalance;
    refresh([ScreenId.home]);
  }

  void closeDisclaimer() {
    session.ui.disclaimerClosed = true;
    refresh([ScreenId.home]);
  }

  Future<void> goProducts() => navigate(ScreenId.products);

  Future<void> goProductList() => navigate(ScreenId.productList);

  Future<void> openProduct(String productId, {String? from}) => navigate(ScreenId.product, params: {'productId': productId, 'from': from});

  Future<void> goMenu({String? highlight, String? from}) => navigate(ScreenId.menu, params: {'highlight': highlight, 'from': from});

  /// 상품 상세의 '상품 가입' → 가입 방법 선택
  void openJoinMethod(String productId, {String? from}) {
    final joinActive = joinFsm.state != 'IDLE' && session.join?.productId == productId;
    final directActive = directFsm.state != 'IDLE' && session.direct?.productId == productId;
    openSheet(JoinMethodSheet(productId: productId, from: from, joinActive: joinActive, directActive: directActive));
  }

  Future<void> chooseJoinMethod(bool ai, String productId, String? from) async {
    closeSheet();
    if (ai) {
      await join.startAction(productId, from: from);
    } else {
      await direct.startAction(productId);
    }
  }

  /// 전체 메뉴에서 업무 화면을 연다 (기존 업무 화면)
  void menuTask(String taskId) {
    final r = bank.openTask(taskId, mode: 'menu');
    if (!r.ok) {
      toast(r.error!.message, UiTone.danger);
      return;
    }
    final ds = session.direct;
    if (ds != null && directFsm.state == 'D_SELF_FIX') ds.metrics.menuVisits += 1;
    save();
    final sid = r.data!;
    openTaskModal(taskId, sid, mode: 'menu', onClose: (status) {
      if (status == 'OPEN') bank.cancelTask(sid);
      if (router.current?.id == ScreenId.menu) router.rerender();
    });
  }

  /* ==================================================================
   * 상담 연결 (가입 지원·자산관리 공용)
   * ================================================================== */

  final Set<String> _summarizing = {};

  SupportCase? supportCase(String track) => track == 'asset' ? session.asset : session.join;

  bool supportValid(String track) => track == 'asset' ? (session.asset != null && assetFsm.state == 'HANDOFF') : (session.join != null && joinFsm.state == 'ESCALATED');

  /// 상담 연결 화면 진입 시 상담 요약을 만든다
  void ensureHandoff(String track) {
    final c = supportCase(track);
    if (c == null || !supportValid(track) || c.handoff != null || _summarizing.contains(track)) return;
    final ctx = track == 'asset' ? asset.handoffContext() : join.handoffContext();
    if (ctx == null) return;
    _summarizing.add(track);
    final ep = _epoch;
    ai.handoffSummary(ctx).then((res) {
      _summarizing.remove(track);
      if (ep != _epoch) return;
      var lines = res.output.summary ?? ctx.lines ?? const <String>[];
      if (res.fallback) {
        lines = [...?ctx.lines, if (ctx.reasonText != null && ctx.reasonText!.isNotEmpty) '연결 사유: ${ctx.reasonText}'];
      }
      c.handoff = Handoff(lines: lines, fallback: res.fallback);
      refresh([ScreenId.support]);
    });
  }

  void toggleSupportConsent(String track) {
    final c = supportCase(track);
    if (c == null) return;
    c.handoffConsent = !c.handoffConsent;
    refresh([ScreenId.support]);
  }

  Future<void> supportSubmit(String track) async {
    await guard('support-submit', () async {
      final c = supportCase(track);
      if (c == null || !supportValid(track) || c.handoff == null || !c.handoffConsent) return;
      final ep = _epoch;
      notifyListeners();
      final r = await bank.createConsultation(c.handoff!.lines);
      if (ep != _epoch) return;
      c.consult = r.ok ? ConsultState(status: 'ACCEPTED', ticket: r.data) : const ConsultState(status: 'FAILED');
      events.add('APP', r.ok ? '상담 접수 완료 ${r.data!.id}' : '상담 접수 실패 — 후속 안내 표시');
      refresh([ScreenId.support]);
    });
  }

  Future<void> supportAssetEnd() async {
    asset.end();
    await navigate(ScreenId.asset, replace: true);
  }

  /* ==================================================================
   * 뒤로 가기
   * ================================================================== */

  /// 앱바·시스템 뒤로 가기. 처리했으면 true, 앱을 닫아도 되면 false.
  Future<bool> back() async {
    if (modal != null) {
      modal!.resolve(false);
      return true;
    }
    if (taskModal != null) {
      taskModalClose();
      return true;
    }
    if (sheet != null) {
      closeSheet();
      return true;
    }
    final cur = router.current;
    if (cur == null) return false;
    if (cur.id == ScreenId.explore) {
      await asset.backFromExplore();
      return true;
    }
    if (cur.id == ScreenId.home && !router.canGoBack) return false;
    await router.goBack();
    return true;
  }

  Future<void> start() async {
    events.add('APP', '앱 시작');
    await navigate(ScreenId.home, resetHistory: true, animate: false);
  }

  @override
  void dispose() {
    _dataTimer?.cancel();
    for (final f in fsms.values) {
      f.removeListener(_onFsmChanged);
    }
    store.removeListener(_refreshDataSoon);
    super.dispose();
  }
}
