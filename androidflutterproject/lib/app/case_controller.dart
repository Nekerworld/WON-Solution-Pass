/// 해결패스 오케스트레이터.
/// - 사용자 동작을 받아 Mock Bank 조회 → 규칙 엔진 → 경로 탐색 → FSM 전이 → 화면 이동을 조율한다.
/// - 상태 전이는 반드시 fsm.transition()을 거친다. 테이블에 없는 전이는 거부된다.
/// - 이체는 사용자의 명시적 승인(확인 모달) 없이는 절대 요청하지 않는다.
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
import '../domain/chatbot_nlu.dart';
import '../domain/event_log.dart';
import '../domain/formatters.dart';
import '../domain/fsm.dart';
import '../domain/pathfinder.dart';
import '../domain/policy.dart';
import 'chatbot_service.dart';
import 'diagnosis.dart';
import 'overlays.dart';
import 'router.dart';
import 'screen_data.dart';
import 'session.dart';

const String _sessionKey = 'wsp.session.v1';

/// 해결 단계 화면 연결: flowId → 해결 행동
const Map<String, String> _stepFlows = {
  'otp-registration': 'REGISTER_OTP',
  'limit-management': 'CHANGE_TRANSFER_LIMIT',
  'kyc-flow': 'COMPLETE_KYC',
};

class CaseController extends ChangeNotifier {
  CaseController({
    required this.store,
    required this.bank,
    required this.events,
    required this.pathfinder,
    required this.chatbot,
    this.storage,
    this.timeScale = 1,
    Random? random,
  }) : _random = random ?? Random() {
    fsm = CaseFsm(events: events);
    router = AppRouter(loader: _loadScreen);
    _loadSession();
    fsm.addListener(_onFsmChanged);
    store.addListener(_refreshHomeSoon);
  }

  final BankStore store;
  final MockBank bank;
  final EventLog events;
  final Pathfinder pathfinder;
  final ChatbotService chatbot;
  final KeyValueStorage? storage;

  /// 화면 연출용 최소 대기 시간 배율 (테스트에서 0)
  final double timeScale;
  final Random _random;

  late final CaseFsm fsm;
  late final AppRouter router;
  Session session = Session();

  /// 데모 초기화 시 증가. 진행 중이던 비동기 흐름이 초기화 이후 상태를 건드리지 않게 한다.
  int _epoch = 0;

  // ---- 오버레이 상태 (셸이 그린다) ----
  SheetState? sheet;
  ConfirmRequest? modal;
  final List<ToastMessage> toasts = [];
  int _toastSeq = 0;
  bool chatTyping = false;
  ProgressAnim? progress;

  bool _diagnosing = false;
  bool _flowBusy = false;
  bool _transferBusy = false;
  bool _chatBusy = false;
  Completer<String>? _continue;
  Timer? _homeTimer;

  Future<void> _sleep(int ms) {
    final scaled = (ms * timeScale).round();
    return scaled > 0 ? Future.delayed(Duration(milliseconds: scaled)) : Future.value();
  }

  bool get isCaseActive => fsm.state != FsmState.idle;

  /* ==================================================================
   * 세션 저장 / 복원
   * ================================================================== */

  void saveSession() {
    try {
      storage?.write(
        _sessionKey,
        jsonEncode({
          'fsm': fsm.state.code,
          'history': fsm.history().map((h) => h.toJson()).toList(),
          'session': session.toJson(),
        }),
      );
    } catch (_) {
      // 무시
    }
  }

  void _loadSession() {
    final raw = storage?.read(_sessionKey);
    if (raw == null) return;
    try {
      final d = (jsonDecode(raw) as Map).cast<String, Object?>();
      session = d['session'] is Map ? Session.fromJson((d['session'] as Map).cast()) : Session();
      final history = ((d['history'] as List?) ?? const [])
          .map((h) => TransitionRecord.fromJson((h as Map).cast()))
          .whereType<TransitionRecord>()
          .toList();
      fsm.restore(FsmState.fromCode(d['fsm'] as String?) ?? FsmState.idle, history);
      // 진단/재확인 도중 앱이 종료된 경우: 일시 상태를 안정 상태로 복원한다.
      if (fsm.state == FsmState.diagnosing) {
        fsm.restore(FsmState.idle, fsm.history());
        session.caseCtx = null;
        session.plan = null;
      } else if (fsm.state == FsmState.rechecking) {
        fsm.restore(session.plan != null ? FsmState.planReady : FsmState.idle, fsm.history());
      } else if (fsm.state == FsmState.escalated && session.caseCtx?.escalation?.code == 'TRANSFER_UNKNOWN') {
        fsm.restore(FsmState.resultUncertain, fsm.history());
      }
      events.add('APP', '세션 복원 (FSM ${fsm.state.code})');
    } catch (_) {
      session = Session();
    }
  }

  void _onFsmChanged() {
    saveSession();
    _refreshHomeSoon();
    notifyListeners();
  }

  /// 홈 화면은 상태 변경 시 다시 그린다 (잔액, 거래, 진행 배너)
  void _refreshHomeSoon() {
    _homeTimer?.cancel();
    _homeTimer = Timer(const Duration(milliseconds: 120), () {
      if (router.current?.id == ScreenId.home) router.rerender();
    });
  }

  /* ==================================================================
   * 화면 데이터 조회
   * ================================================================== */

  Future<Object?> _loadScreen(ScreenId id, Params p) async {
    switch (id) {
      case ScreenId.home:
        return HomeData(customer: await bank.getCustomerState());
      case ScreenId.transfer:
        final (dr, cs) = await (bank.getTransferDraft(), bank.getCustomerState()).wait;
        if (dr.ok) session.lastDraft = dr.data!.draft;
        return TransferData(draft: dr, customer: cs);
      case ScreenId.otp:
        if (p['phase'] != null) return null;
        final (st, el) = await (bank.getOtpStatus(), bank.checkOtpEligibility()).wait;
        return OtpData(status: st, eligibility: el);
      case ScreenId.kyc:
        if (p['phase'] != null) return null;
        final (k, cs) = await (bank.getKycStatus(), bank.getCustomerState()).wait;
        return KycData(kyc: k, customer: cs);
      case ScreenId.limit:
        if (p['phase'] == 'done') return null;
        final (lim, otp, dr) = await (bank.getTransferLimit(), bank.getOtpStatus(), bank.getTransferDraft()).wait;
        if (!lim.ok || !otp.ok || !dr.ok) {
          return LimitData(limit: lim, otp: otp, draft: dr, options: const [], selected: null, recommended: 0);
        }
        final current = lim.data!.transferLimit;
        final draftAmount = dr.data!.draft.amount;
        final recommended = max(draftAmount, DemoPolicy.minTransferLimit);
        final options = <int>{recommended, 2000000, 3000000, 5000000}.where((v) => v > current).toList()..sort();
        final shown = options.take(4).toList();
        final selected = (p['selected'] as int?) ?? (shown.isNotEmpty ? shown.first : current);
        session.limitSelection = selected;
        return LimitData(limit: lim, otp: otp, draft: dr, options: shown, selected: selected, recommended: recommended);
      case ScreenId.result:
        if (p['processing'] == true || p['notSent'] == true) return null;
        final id = (p['transactionId'] as String?) ?? session.resultCtx?.transactionId;
        if (id == null) return const ResultData(transactionId: null, result: null);
        return ResultData(transactionId: id, result: await bank.getTransferResult(id));
      case ScreenId.chat:
        return ChatData(customer: await bank.getCustomerState());
      case ScreenId.plan:
      case ScreenId.support:
        return null;
    }
  }

  /* ==================================================================
   * 오버레이: 토스트 / 시트 / 모달
   * ================================================================== */

  void toast(String text, [UiTone tone = UiTone.neutral]) {
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

  void _openSheet(SheetState value, {VoidCallback? onClose}) {
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

  /* ==================================================================
   * 해결 건 / 계획 반영
   * ================================================================== */

  Future<ComputeResult> _compute() async {
    final result = await computeFromBank(bank, pathfinder);
    if (result.draft != null) session.lastDraft = result.draft;
    return result;
  }

  void _newCase(String trigger, List<RejectReason>? reasons) {
    final d = DateTime.now();
    final ymd = '${d.year}${pad2(d.month)}${pad2(d.day)}';
    const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final suffix = List.generate(4, (_) => chars[_random.nextInt(chars.length)]).join();
    session.caseCtx = CaseCtx(
      caseId: 'CASE-$ymd-$suffix',
      trigger: trigger,
      startedAt: d.millisecondsSinceEpoch,
      reasons: reasons ?? [],
    );
    session.plan = null;
    session.resultCtx = null;
    session.returnedFromPass = false;
    events.add('APP', '새 해결 건 생성 ${session.caseCtx!.caseId} ($trigger)');
  }

  void _setEscalation(String code) {
    session.caseCtx?.escalation = Escalation(code: code, at: DateTime.now().millisecondsSinceEpoch);
  }

  void _mergeTimeline(Plan plan) {
    final ctx = session.caseCtx;
    if (ctx == null) return;
    for (final s in plan.actionSteps) {
      if (!ctx.timeline.contains(s.actionId)) ctx.timeline.add(s.actionId);
    }
  }

  /// 계산된 계획을 FSM에 반영한다. @returns 'plan' | 'support'
  String _applyPlanToFsm(ComputeResult result) {
    final plan = result.plan;
    session.plan = plan;
    _mergeTimeline(plan);
    if (plan.status == PlanStatus.blocked || plan.status == PlanStatus.noPath) {
      final code = plan.status == PlanStatus.noPath ? 'NO_PATH' : plan.blocker!.code;
      _setEscalation(code);
      fsm.transition(FsmEvent.escalate, {'code': code});
      saveSession();
      return 'support';
    }
    session.caseCtx?.escalation = null;
    if (plan.status == PlanStatus.ready) {
      fsm.transition(fsm.state == FsmState.diagnosing ? FsmEvent.noActionNeeded : FsmEvent.allMet);
    } else {
      fsm.transition(FsmEvent.pathFound, {'steps': plan.steps.map((s) => s.actionId).toList()});
    }
    saveSession();
    return 'plan';
  }

  /* ==================================================================
   * 자동 진단 (하단 시트)
   * ================================================================== */

  List<(String, String, String, UiTone)> _diagnosisRows(ComputeResult result) {
    const keys = ['request', 'limit', 'otp', 'kyc', 'account', 'balance'];
    if (!result.ok) return keys.map((k) => (k, '', '확인 불가', UiTone.neutral)).toList();
    final ev = result.evaluation!;
    final c = ev.ctx;
    final f = ev.facts;
    final g = ev.goal;
    return [
      ('request', '${c.recipient} · ${formatWon(c.amount)}', '확인', UiTone.info),
      ('limit', formatWon(c.transferLimit), f['limitSufficient'] == true ? '충족' : '부족',
          f['limitSufficient'] == true ? UiTone.success : UiTone.warning),
      (
        'otp',
        c.otpRegistered ? '등록됨' : '미등록',
        c.otpRegistered ? '정상' : (g['otpRegistered'] == true ? '등록 필요' : '이번 이체엔 불필요'),
        c.otpRegistered ? UiTone.success : (g['otpRegistered'] == true ? UiTone.warning : UiTone.neutral),
      ),
      ('kyc', c.kycCompleted ? '완료' : '미완료', c.kycCompleted ? '정상' : '필요', c.kycCompleted ? UiTone.success : UiTone.warning),
      ('account', c.accountRestricted ? '제한 확인됨' : '정상', c.accountRestricted ? '제한' : '정상',
          c.accountRestricted ? UiTone.danger : UiTone.success),
      ('balance', formatWon(c.balance), c.balance >= c.amount ? '충분' : '부족', c.balance >= c.amount ? UiTone.success : UiTone.danger),
    ];
  }

  DiagSummary _diagnosisSummary(ComputeResult result, String target) {
    final plan = result.plan;
    final codes = (session.caseCtx?.reasons ?? const <RejectReason>[]).map((r) => r.code).where((c) => c.isNotEmpty).toList();
    final codeLine = codes.isNotEmpty ? '은행 응답 사유: ${codes.join(', ')}' : null;
    if (!result.ok) {
      return DiagSummary(
        tone: UiTone.danger,
        title: '은행 상태를 확인할 수 없어 진단을 멈췄어요.',
        body: '정상 진단을 가장하지 않고 안내를 보류할게요.',
        buttonLabel: '안내 보기',
        codeLine: codeLine,
      );
    }
    if (target == 'support') {
      final b = plan.blocker;
      final (title, body) = plan.status == PlanStatus.noPath
          ? ('허용된 해결 경로를 찾지 못했어요.', '상담 절차로 안내할게요.')
          : b!.code == 'ACCOUNT_RESTRICTED'
              ? ('계좌 이용 제한이 확인되었어요.', '자동 해결 경로를 만들지 않고 공식 상담 절차로 안내할게요.')
              : (b.title, b.guidance);
      return DiagSummary(tone: UiTone.danger, title: title, body: body, buttonLabel: '안내 보기', codeLine: codeLine);
    }
    if (plan.status == PlanStatus.ready) {
      return DiagSummary(
        tone: UiTone.success,
        title: '추가 조치 없이 이체할 수 있어요.',
        body: '원래 이체 정보를 그대로 유지했어요.',
        buttonLabel: '해결 계획 보기',
        codeLine: codeLine,
      );
    }
    return DiagSummary(
      tone: UiTone.info,
      title: '확인 결과 ${countWord(plan.actionSteps.length)} 가지 조치가 필요해요.',
      body: plan.evaluation!.requirements.map((r) => r.title).join(' · '),
      buttonLabel: '해결 계획 보기',
      codeLine: codeLine,
    );
  }

  Future<String> _waitForContinue() {
    final c = Completer<String>();
    _continue = c;
    sheet?.setDismissible(true);
    return c.future;
  }

  void _resolveContinue(String value) {
    final c = _continue;
    if (c == null) return;
    _continue = null;
    if (!c.isCompleted) c.complete(value);
  }

  /// 진단 요약의 버튼
  void diagContinue() => _resolveContinue('continue');

  /// 오류 발생(TRANSFER_FAILED) 또는 수동 확인(MANUAL) 시 자동 진단을 실행한다.
  /// 사용자에게 원인을 묻지 않고, 은행 상태를 조회해 모든 원인을 한 번에 찾는다.
  Future<void> startDiagnosis(String trigger, [List<RejectReason>? reasons]) async {
    if (_diagnosing) return;
    final st = fsm.state;
    if (st == FsmState.verifying || st == FsmState.resultUncertain) {
      await openResult();
      return;
    }
    if (st == FsmState.diagnosing || st == FsmState.rechecking) return;

    _diagnosing = true;
    try {
      final d0 = await bank.getTransferDraft();
      final tx0 = d0.data?.transaction;
      if (tx0 != null && tx0.status.isUnresolved) {
        toast('처리 결과를 확인 중인 이체가 있어요. 중복 출금을 막기 위해 결과부터 확인할게요.', UiTone.warning);
        await openResult();
        return;
      }
      if (fsm.state == FsmState.completed) fsm.transition(FsmEvent.newCase);
      if (fsm.state == FsmState.idle) {
        _newCase(trigger, reasons);
        fsm.transition(
          trigger == 'TRANSFER_FAILED' ? FsmEvent.transferFailed : FsmEvent.manualDiagnose,
          {'reasons': (reasons ?? const <RejectReason>[]).map((r) => r.code).toList()},
        );
      } else if (fsm.can(FsmEvent.recheck)) {
        if (session.caseCtx != null && reasons != null) session.caseCtx!.reasons = reasons;
        fsm.transition(FsmEvent.recheck, {'trigger': trigger});
      } else {
        return;
      }

      final myEpoch = _epoch;
      final diag = DiagnosisSheetState(isFailure: trigger == 'TRANSFER_FAILED');
      _openSheet(diag, onClose: () => _resolveContinue('dismissed'));
      final started = DateTime.now();
      final result = await _compute();
      final elapsed = DateTime.now().difference(started).inMilliseconds;
      if (elapsed < 650) await _sleep(650 - elapsed);
      if (myEpoch != _epoch) return;
      for (final (key, sub, text, tone) in _diagnosisRows(result)) {
        diag.revealRow(key, sub, text, tone);
        await _sleep(110);
      }
      if (myEpoch != _epoch) return;
      final target = _applyPlanToFsm(result);
      diag.showSummary(_diagnosisSummary(result, target));
      final choice = await _waitForContinue();
      if (myEpoch != _epoch) return;
      if (choice != 'continue') {
        events.add('APP', '진단 결과 확인 후 시트를 닫음 (해결패스에서 다시 볼 수 있음)');
        toast('진단 결과는 홈의 해결패스에서 다시 볼 수 있어요.');
        return;
      }
      closeSheet();
      await router.navigate(target == 'support' ? ScreenId.support : ScreenId.plan);
    } finally {
      _diagnosing = false;
    }
  }

  /* ==================================================================
   * 해결 단계 화면 연결 / 복귀 / 재확인
   * ================================================================== */

  /// 허용목록에 있는 내부 화면만 연다 (open_native 개념)
  Future<void> openFlow(String flowId) async {
    final screen = ScreenId.parse(bank.resolveFlow(flowId));
    if (screen == null) {
      events.add('APP', '차단된 화면 연결 요청: $flowId');
      toast('허용되지 않은 화면 연결이에요.', UiTone.danger);
      return;
    }
    if (flowId == 'transfer') return returnToTransfer();
    if (flowId == 'transfer-result') return openResult();
    final action = _stepFlows[flowId];
    if (action != null && fsm.state == FsmState.planReady) {
      fsm.transition(FsmEvent.stepSelected, {'action': action});
    }
    await router.navigate(screen);
  }

  Future<void> _runRecheck(Plan? prevPlan) async {
    final myEpoch = _epoch;
    final started = DateTime.now();
    final result = await _compute();
    final elapsed = DateTime.now().difference(started).inMilliseconds;
    if (elapsed < 700) await _sleep(700 - elapsed);
    if (myEpoch != _epoch || fsm.state != FsmState.rechecking) return;
    final target = _applyPlanToFsm(result);
    if (target == 'support') {
      toast('자동 안내를 멈추고 상담 절차로 안내할게요.', UiTone.warning);
      await router.navigate(ScreenId.support, replace: true);
      return;
    }
    final prevIds = prevPlan?.actionSteps.map((s) => s.actionId).toList() ?? const <String>[];
    final nowIds = result.plan.actionSteps.map((s) => s.actionId).toList();
    final resolved = prevIds.where((id) => !nowIds.contains(id)).map((id) => getAction(id)!.label).toList();
    String msg;
    var tone = UiTone.neutral;
    if (result.plan.status == PlanStatus.ready) {
      msg = '${resolved.isNotEmpty ? '${resolved.join(', ')} 완료를 확인했어요. ' : ''}모든 사전 조건을 충족했어요.';
      tone = UiTone.success;
    } else if (resolved.isNotEmpty) {
      msg = '${resolved.join(', ')} 완료를 은행에서 확인했어요. 남은 경로를 다시 계산했어요.';
      tone = UiTone.success;
    } else {
      msg = '아직 바뀐 상태가 없어요. 남은 절차를 진행해 주세요.';
    }
    if (router.current?.id == ScreenId.plan) {
      await router.rerender({'rechecking': false});
    } else {
      await router.navigate(ScreenId.plan, backTo: true);
    }
    toast(msg, tone);
  }

  /// 해결 단계 화면에서 해결패스로 돌아온다 → 이전 상태를 믿지 않고 재조회
  Future<void> returnFromFlow() async {
    if (fsm.state != FsmState.waitingUser) {
      await router.goBack();
      return;
    }
    final prev = session.plan;
    fsm.transition(FsmEvent.userReturned);
    await router.navigate(ScreenId.plan, params: {'rechecking': true}, backTo: true);
    await _runRecheck(prev);
  }

  bool _leaveFlow() {
    if (fsm.state == FsmState.waitingUser) {
      returnFromFlow();
      return true;
    }
    return false;
  }

  Future<void> planRecheck() async {
    if (session.plan == null || !isCaseActive) return startDiagnosis('MANUAL');
    if (fsm.state == FsmState.waitingUser) return returnFromFlow();
    if (!fsm.can(FsmEvent.recheck)) {
      toast('지금은 다시 확인할 수 없는 단계예요.');
      return;
    }
    final prev = session.plan;
    fsm.transition(FsmEvent.recheck, {'trigger': 'PLAN_REFRESH'});
    await router.rerender({'rechecking': true});
    await _runRecheck(prev);
  }

  Future<void> openPass() async {
    switch (fsm.state) {
      case FsmState.planReady:
      case FsmState.readyToRetry:
        await router.navigate(ScreenId.plan);
      case FsmState.waitingUser:
        await returnFromFlow();
      case FsmState.verifying:
      case FsmState.resultUncertain:
        await openResult();
      case FsmState.escalated:
        if (session.caseCtx?.escalation?.code == 'TRANSFER_FAILED') {
          await openResult();
        } else {
          await router.navigate(ScreenId.support);
        }
      default:
        await startDiagnosis('MANUAL');
    }
  }

  /// RETURN_TO_TRANSFER: 실제 송금이 아니라 원래 이체 화면으로 복귀하는 행동
  Future<void> returnToTransfer() async {
    final st = fsm.state;
    if (st == FsmState.readyToRetry) {
      session.returnedFromPass = true;
      saveSession();
      events.add('APP', 'RETURN_TO_TRANSFER: 원래 이체 화면으로 복귀 (자동 실행 없음)');
      await router.navigate(ScreenId.transfer, params: {'returned': true}, backTo: true);
      return;
    }
    if (st == FsmState.idle || st == FsmState.completed) {
      await router.navigate(ScreenId.transfer);
      return;
    }
    if (st == FsmState.verifying || st == FsmState.resultUncertain) return openResult();
    if (st == FsmState.waitingUser || fsm.can(FsmEvent.recheck)) {
      fsm.transition(st == FsmState.waitingUser ? FsmEvent.userReturned : FsmEvent.recheck);
      final result = await _compute();
      final target = _applyPlanToFsm(result);
      if (fsm.state == FsmState.readyToRetry) return returnToTransfer();
      toast('아직 남은 절차가 있어요. 해결 계획을 확인해 주세요.');
      await router.navigate(target == 'support' ? ScreenId.support : ScreenId.plan);
    }
  }

  /* ==================================================================
   * 해결 단계 실행 (기존 은행 업무 화면 시뮬레이션)
   * ================================================================== */

  Future<void> _runStepFlow(ScreenId screen, Future<BankResult<int>> Function() call) async {
    if (_flowBusy) return;
    _flowBusy = true;
    try {
      final anim = ProgressAnim(total: 3, sleep: _sleep);
      progress = anim;
      await router.navigate(screen, params: {'phase': 'processing'}, replace: true, animate: false);
      final r = await call();
      await anim.finish(r.ok);
      if (r.ok) {
        await router.navigate(screen, params: {'phase': 'done', 'stateVersion': r.data}, replace: true, animate: false);
      } else {
        await router.navigate(screen, params: {'error': r.error!.message}, replace: true, animate: false);
      }
      if (progress == anim) progress = null;
      anim.dispose();
    } finally {
      _flowBusy = false;
    }
  }

  Future<void> registerOtp() => _runStepFlow(ScreenId.otp, bank.registerDigitalOtp);

  Future<void> completeKyc() => _runStepFlow(ScreenId.kyc, bank.completeKyc);

  Future<void> limitSelect(int value) => router.rerender({'selected': value, 'check': null, 'custom': null});

  Future<void> limitCheck(String customText) async {
    final custom = digitsOf(customText);
    final value = custom != 0 ? custom : session.limitSelection;
    if (value == null || value == 0) {
      toast('변경할 한도를 선택하거나 입력해 주세요.');
      return;
    }
    final r = await bank.checkLimitChange(value);
    if (!r.ok) {
      toast(r.error!.message, UiTone.danger);
      return;
    }
    await router.rerender({
      'selected': value,
      'custom': custom != 0 ? custom : null,
      'check': LimitCheckView(allowed: r.data!.allowed, reasons: r.data!.reasons, value: value),
    });
  }

  Future<void> limitApply(int value) async {
    if (_flowBusy) return;
    _flowBusy = true;
    try {
      final r = await bank.changeTransferLimit(value);
      if (r.ok) {
        await router.navigate(
          ScreenId.limit,
          params: {
            'phase': 'done',
            'newLimit': r.data!.transferLimit,
            'previousLimit': r.data!.previousLimit,
            'stateVersion': r.data!.stateVersion,
          },
          replace: true,
          animate: false,
        );
      } else {
        final e = r.error!;
        await router.rerender({
          'check': LimitCheckView(
            allowed: false,
            reasons: e.reasons ?? [RejectReason(code: e.code, message: e.message)],
            value: value,
          ),
        });
      }
    } finally {
      _flowBusy = false;
    }
  }

  /* ==================================================================
   * 이체 시도 / 사용자 승인 / 결과 검증
   * ================================================================== */

  /// 입력 중인 금액을 은행 이체 초안에 반영한다. [amountText]가 null이면 금액이 잠긴 상태다.
  Future<bool> _flushAmountInput(String? amountText) async {
    if (amountText == null) return true;
    final n = digitsOf(amountText);
    if (n == 0) {
      toast('보낼 금액을 입력해 주세요.');
      return false;
    }
    final r = await bank.updateTransferAmount(n);
    if (!r.ok && r.error!.kind == ErrorKind.businessReject) {
      toast(r.error!.message, UiTone.warning);
      return false;
    }
    return true;
  }

  /// 금액 입력란에서 포커스가 빠지거나 빠른 금액 버튼을 눌렀을 때
  void commitAmount(int amount) {
    if (amount > 0) bank.updateTransferAmount(amount);
  }

  /// 이체하기 버튼 로딩 표시 (확인 모달이 떠 있는 동안은 끈다)
  bool transferLoading = false;

  void _setTransferLoading(bool value) {
    if (transferLoading == value) return;
    transferLoading = value;
    notifyListeners();
  }

  Future<void> attemptTransfer(String? amountText) async {
    if (_transferBusy) return;
    _transferBusy = true;
    _setTransferLoading(true);
    List<RejectReason>? diagnoseWith;
    try {
      if (!await _flushAmountInput(amountText)) return;
      final d = await bank.getTransferDraft();
      if (!d.ok) {
        diagnoseWith = [RejectReason(code: d.error!.code, message: d.error!.message)];
        return;
      }
      final draft = d.data!.draft;
      final tx = d.data!.transaction;
      if (tx != null && (tx.status.isUnresolved || tx.status == TransferStatus.success)) {
        await openResult();
        return;
      }
      final v = await bank.validateTransfer(draft);
      if (!v.ok) {
        diagnoseWith = [RejectReason(code: v.error!.code, message: v.error!.message)];
        return;
      }
      if (!v.data!.valid) {
        events.add('BANK', '이체 사전 검사 실패: ${v.data!.reasons.map((r) => r.code).join(', ')}');
        diagnoseWith = v.data!.reasons;
        return;
      }
      _setTransferLoading(false);
      final approved = await confirm(ConfirmRequest(
        title: '${draft.recipient}님에게\n${formatWon(draft.amount)}을 보낼까요?',
        rows: [
          ConfirmRow('출금 계좌', draft.fromAccount),
          ConfirmRow('받는 분', draft.recipient),
          ConfirmRow('받는 은행', '${draft.recipientBank} ${draft.recipientAccount}'),
          ConfirmRow('보낼 금액', formatWon(draft.amount), strong: true),
        ],
        fineprint: '보내기를 누르기 전에는 이체가 실행되지 않아요. (가상 거래)',
        confirmText: '보내기',
        cancelText: '취소',
      ));
      if (!approved) {
        events.add('APP', '사용자가 이체 승인을 취소함 (거래 미실행)');
        return;
      }
      _setTransferLoading(true);
      await _approveAndSubmit(draft);
    } finally {
      _transferBusy = false;
      _setTransferLoading(false);
      if (diagnoseWith != null) await startDiagnosis('TRANSFER_FAILED', diagnoseWith);
    }
  }

  void _applyTxToFsm(Transaction tx) {
    final rc = session.resultCtx;
    if (rc == null || !rc.viaPass || rc.transactionId != tx.id) return;
    if (fsm.state != FsmState.verifying) return;
    switch (tx.status) {
      case TransferStatus.success:
        fsm.transition(FsmEvent.resultSuccess, {'transactionId': tx.id});
      case TransferStatus.failed:
        _setEscalation('TRANSFER_FAILED');
        fsm.transition(FsmEvent.resultFailed, {'transactionId': tx.id});
      case TransferStatus.unknown:
        _setEscalation('TRANSFER_UNKNOWN');
        fsm.transition(FsmEvent.resultUnknown, {'transactionId': tx.id});
      default:
      // PENDING: VERIFYING 유지, 결과 조회만 허용
    }
    saveSession();
  }

  Future<void> _approveAndSubmit(TransferDraft draft) async {
    final viaPass = fsm.state != FsmState.idle && fsm.state != FsmState.completed;
    if (fsm.state == FsmState.completed) fsm.transition(FsmEvent.newCase);

    if (viaPass && fsm.state != FsmState.readyToRetry) {
      if (fsm.state == FsmState.waitingUser) {
        fsm.transition(FsmEvent.userReturned);
      } else if (fsm.can(FsmEvent.recheck)) {
        fsm.transition(FsmEvent.recheck, {'trigger': 'BEFORE_APPROVAL'});
      } else {
        toast('진행 중인 확인이 끝난 뒤 다시 시도해 주세요.');
        return;
      }
      final result = await _compute();
      final target = _applyPlanToFsm(result);
      if (fsm.state != FsmState.readyToRetry) {
        await router.navigate(target == 'support' ? ScreenId.support : ScreenId.plan);
        return;
      }
    }
    if (viaPass) fsm.transition(FsmEvent.userApproved, {'amount': draft.amount});

    final requestId = draft.requestId != null && draft.status != TransferStatus.failed ? draft.requestId! : bank.newRequestId();
    events.add('APP', '사용자 승인 → 이체 요청 $requestId');
    await router.navigate(ScreenId.result, params: {'processing': true});

    final res = await bank.submitTransfer(draft.copyWith(requestId: requestId));
    session.returnedFromPass = false;

    if (!res.ok) {
      final e = res.error!;
      if (e.kind == ErrorKind.businessReject && e.reasons != null) {
        if (viaPass && fsm.state == FsmState.verifying) {
          _setEscalation('TRANSFER_REJECTED');
          fsm.transition(FsmEvent.escalate, {'code': 'TRANSFER_REJECTED'});
        }
        toast('이체 조건이 바뀌어 거래가 실행되지 않았어요. 상태를 다시 확인할게요.', UiTone.warning);
        await router.navigate(ScreenId.transfer, backTo: true);
        await startDiagnosis('TRANSFER_FAILED', e.reasons);
        return;
      }
      if (viaPass && fsm.state == FsmState.verifying) {
        _setEscalation('BANK_UNAVAILABLE');
        fsm.transition(FsmEvent.escalate, {'code': e.code});
      }
      await router.navigate(ScreenId.result, params: {'notSent': true, 'message': e.message}, replace: true, animate: false);
      return;
    }

    final tx = res.data!.transaction;
    session.resultCtx = ResultCtx(transactionId: tx.id, viaPass: viaPass, duplicate: res.data!.duplicate);
    _applyTxToFsm(tx);
    saveSession();
    await router.navigate(
      ScreenId.result,
      params: {'transactionId': tx.id, 'duplicate': res.data!.duplicate},
      replace: true,
      animate: false,
    );
  }

  String? _currentTxId() => session.resultCtx?.transactionId ?? session.lastDraft?.transactionId;

  Future<void> openResult() async {
    var id = _currentTxId();
    if (id == null) {
      final d = await bank.getTransferDraft();
      if (d.ok) id = d.data!.draft.transactionId;
    }
    await router.navigate(ScreenId.result, params: {'transactionId': id});
  }

  /// 거래 결과 조회 전용. 재전송하지 않는다.
  Future<void> queryResult() async {
    final id = _currentTxId();
    if (id == null) return;
    final rc = session.resultCtx;
    var movedFromUncertain = false;
    if (rc != null && rc.viaPass && rc.transactionId == id && fsm.state == FsmState.resultUncertain) {
      movedFromUncertain = fsm.transition(FsmEvent.resultQuery, {'transactionId': id}).ok;
    }
    final r = await bank.getTransferResult(id);
    if (!r.ok) {
      if (movedFromUncertain) fsm.transition(FsmEvent.resultUnknown, {'transactionId': id, 'reason': 'QUERY_FAILURE'});
      toast('결과를 조회하지 못했어요. 다시 이체하지 말고 잠시 후 조회해 주세요.', UiTone.warning);
      return;
    }
    final tx = r.data!;
    _applyTxToFsm(tx);
    await router.navigate(ScreenId.result, params: {'transactionId': id}, replace: true, animate: false);
    final (msg, tone) = switch (tx.status) {
      TransferStatus.success => ('은행 성공 응답을 확인했어요.', UiTone.success),
      TransferStatus.pending => ('아직 처리 중이에요. 잠시 후 다시 조회해 주세요.', UiTone.neutral),
      TransferStatus.failed => ('실패로 확인되었어요. 출금되지 않았어요.', UiTone.danger),
      _ => ('아직 결과가 확정되지 않았어요.', UiTone.warning),
    };
    toast(msg, tone);
  }

  /* ==================================================================
   * 기타 동작
   * ================================================================== */

  Future<void> goSupport([String? code]) => router.navigate(ScreenId.support, params: {'code': code});

  Future<void> supportConnect() async {
    final ok = await confirm(ConfirmRequest(
      title: '상담 연결에 동의하시겠어요?',
      body: '해결패스가 확인한 상태와 안내된 절차만 상담사에게 전달돼요. 비밀번호·OTP 번호 같은 인증 정보는 전달되지 않아요.',
      fineprint: '시연용 시뮬레이션이며 실제 상담이 연결되지 않습니다.',
      confirmText: '동의하고 연결',
      cancelText: '취소',
    ));
    if (!ok) return;
    events.add('APP', '상담 연결 요청 (시뮬레이션) ${session.caseCtx?.caseId ?? ''}');
    toast('상담 연결을 요청했어요. (시연용 시뮬레이션)', UiTone.success);
  }

  Future<void> showAccountDetail() async {
    final (cs, txs) = await (bank.getCustomerState(), bank.getTransactions()).wait;
    if (!cs.ok) {
      toast(cs.error!.message, UiTone.danger);
      return;
    }
    _openSheet(AccountSheetState(customer: cs.data!, transactions: txs.data ?? const []));
  }

  Future<void> sendChat(String text) async {
    final q = text.trim();
    if (q.isEmpty || _chatBusy) return;
    _chatBusy = true;
    try {
      session.chat.add(ChatMessage(isUser: true, text: q));
      chatTyping = true;
      notifyListeners();
      final started = DateTime.now();
      ChatReply reply;
      try {
        reply = await chatbot.respond(q);
      } catch (e) {
        debugPrint('[WSP] 챗봇 오류 $e');
        reply = const ChatReply(
          text: '답변을 준비하는 중 문제가 발생했어요. 상담을 이용해 주세요.',
          tone: Tone.warning,
          links: [FlowLink('상담 연결 안내', 'support')],
          analysis: null,
          ruleIds: [],
          stateVersion: null,
        );
      }
      final elapsed = DateTime.now().difference(started).inMilliseconds;
      if (elapsed < 450) await _sleep(450 - elapsed);
      chatTyping = false;
      session.chat.add(ChatMessage(
        isUser: false,
        text: reply.text,
        links: reply.links,
        tone: reply.tone,
        intents: reply.analysis?.intents ?? const [],
        amount: reply.analysis?.amount,
        ruleIds: reply.ruleIds,
        stateVersion: reply.stateVersion,
      ));
      if (session.chat.length > 40) session.chat = session.chat.sublist(session.chat.length - 40);
      saveSession();
      notifyListeners();
    } finally {
      _chatBusy = false;
    }
  }

  void chatReset() {
    session.chat = [];
    saveSession();
    notifyListeners();
  }

  void toggleBalance() {
    session.hideBalance = !session.hideBalance;
    saveSession();
    router.rerender();
  }

  void noticeClose() {
    session.hideNotice = true;
    saveSession();
    router.rerender();
  }

  void noop() => toast('프로토타입 시연 범위 밖의 기능이에요.');

  /* ==================================================================
   * 뒤로 가기 / 홈 / 초기화
   * ================================================================== */

  /// 결과 화면을 떠나면 사건을 종료한다(NEW_CASE → IDLE).
  /// 전이 테이블상 COMPLETED·ESCALATED에서만 가능하며, VERIFYING·RESULT_UNCERTAIN은 그대로 남는다.
  void _closeCase() {
    if (!fsm.can(FsmEvent.newCase)) return;
    final from = fsm.state;
    fsm.transition(FsmEvent.newCase, {'closedFrom': from.code});
    events.add('APP', '결과 확인 후 사건 종료 (${from.code} → IDLE)');
    saveSession();
  }

  /// 결과 화면을 떠날 때는 사건을 닫는다. 화면이 바뀐 뒤에 닫아야 나가는 결과 화면이 바뀌지 않는다.
  Future<void> goHome() async {
    final leavingResult = router.current?.id == ScreenId.result;
    await router.navigate(ScreenId.home, resetHistory: true);
    if (leavingResult) _closeCase();
  }

  /// 앱바·시스템 뒤로 가기. 처리했으면 true, 앱을 닫아도 되면 false.
  Future<bool> back() async {
    if (modal != null) {
      modal!.resolve(false);
      return true;
    }
    if (sheet != null) {
      dismissSheet();
      return true;
    }
    final cur = router.current;
    if (cur == null) return false;
    switch (cur.id) {
      case ScreenId.plan:
      case ScreenId.result:
        await goHome();
        return true;
      case ScreenId.otp:
      case ScreenId.limit:
      case ScreenId.kyc:
        if (cur.params['phase'] == 'processing') return true;
        if (_leaveFlow()) return true;
      case ScreenId.home:
        if (!router.canGoBack) return false;
      default:
    }
    await router.goBack();
    return true;
  }

  void resetDemo({bool silent = false, bool navigate = true}) {
    _epoch += 1;
    _resolveContinue('dismissed');
    modal?.resolve(false);
    closeSheet();
    store.reset('데모 초기화');
    fsm.reset();
    session = Session();
    saveSession();
    if (navigate) router.navigate(ScreenId.home, resetHistory: true, animate: false);
    if (!silent) toast('데모가 초기 상태로 복원되었어요.');
    notifyListeners();
  }

  /// 시연 제어 화면에서 세션을 통째로 바꿀 때
  void replaceSession(Session value) {
    session = value;
    saveSession();
    notifyListeners();
  }

  Future<void> goTransfer() => router.navigate(ScreenId.transfer);

  Future<void> goChat() => router.navigate(ScreenId.chat);

  Future<void> start() => router.navigate(ScreenId.home, resetHistory: true);

  @override
  void dispose() {
    _homeTimer?.cancel();
    fsm.removeListener(_onFsmChanged);
    store.removeListener(_refreshHomeSoon);
    super.dispose();
  }
}
