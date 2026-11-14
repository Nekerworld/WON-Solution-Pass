/// 가입 지원 - 직접 가입 (상태머신 direct)
/// 기존 가입 화면 흐름: 단계마다 입력하고, 단계별로 은행이 조건을 확인한다.
/// 조건이 부족하면 안내만 받고 고객이 직접 메뉴를 찾아 해결한 뒤 처음부터 다시 시작한다(P6).
/// 가입 승인·결과 확인은 AI 경로와 같은 은행 API와 규칙을 쓴다(P5).
library;

import '../domain/bank_state.dart';
import '../domain/formatters.dart';
import '../domain/fsm.dart';
import '../domain/scenario.dart';
import 'app_controller.dart';
import 'overlays.dart';
import 'router.dart';
import 'sessions.dart';

const List<ScreenId> _screens = [ScreenId.direct, ScreenId.applyResult, ScreenId.menu, ScreenId.home];

/// 조건별로 고객이 찾아가야 하는 메뉴 (직접 가입 화면은 대체 수단까지 안내하지 않는다)
const Map<String, String?> fixMenu = {
  'IDENTITY': '실명확인',
  'ACCOUNT': '계좌 개설',
  'KYC': '내 정보 관리',
  'CERT': '인증센터',
  'FX': '외환',
  'FX_ACCOUNT': '외환',
  'PROFILE': '투자',
  'ADULT': null,
};

class DirectFlow {
  DirectFlow(this.app);

  final AppController app;

  Fsm get fsm => app.directFsm;
  DirectSession? get s => app.session.direct;
  ProductDef get product => getProduct(s!.productId)!;

  bool _stale(int ep) => ep != app.epoch || s == null;

  DirectSession _fresh(String productId) {
    final p = getProduct(productId)!;
    final months = p.periods.length > 1 ? p.periods[1] : (p.periods.isNotEmpty ? p.periods.first : 0);
    return DirectSession(productId: productId, input: DirectInput(months: months));
  }

  bool start(String productId) {
    if (fsm.state != 'IDLE') return false;
    app.session.direct = _fresh(productId);
    fsm.transition('START', {'productId': productId});
    return true;
  }

  void begin() {
    if (fsm.state != 'D_START') return;
    s!.stepIndex = 0;
    fsm.transition('BEGIN');
    app.refresh(_screens);
  }

  /// 현재 단계 입력값 검증 (화면 입력 규칙)
  String? _validateStep(DirectStep step) {
    final d = s!;
    final p = product;
    if (step.id == 'terms' && !d.input.agreed) return '상품 안내와 약관에 동의해 주세요.';
    if (step.id == 'amount') {
      if (p.maxMonthly != 0 && (d.input.monthly == 0 || d.input.monthly < p.minMonthly || d.input.monthly > p.maxMonthly)) {
        return '월 납입액은 ${formatMan(p.minMonthly)}~${formatMan(p.maxMonthly)} 사이로 입력해 주세요.';
      }
      if (p.periods.isNotEmpty && d.input.months == 0) return '가입 기간을 선택해 주세요.';
    }
    return null;
  }

  Future<void> next() async {
    final d = s;
    if (d == null || fsm.state != 'D_STEP') return;
    final p = product;
    final step = p.directSteps[d.stepIndex];
    final msg = _validateStep(step);
    if (msg != null) {
      app.toast(msg, UiTone.warning);
      return;
    }
    final ep = app.epoch;
    d.metrics.steps += 1;
    fsm.transition('STEP_DONE', {'step': step.id});
    d.checking = true;
    app.refresh(_screens);
    var unmet = <NoticeCondition>[];
    if (step.checks.isNotEmpty) {
      final c = await app.bank.checkConditions(d.productId);
      if (_stale(ep)) return;
      d.checking = false;
      if (!c.ok) {
        fsm.transition('QUERY_FAILED', {'code': c.error!.code});
        app.toast('확인하지 못했어요. 잠시 후 다시 시도해 주세요.', UiTone.danger);
        app.refresh(_screens);
        return;
      }
      // 기존 가입 화면처럼 첫 번째 미충족 조건 하나만 알려 준다
      unmet = [
        for (final x in c.data!.conditions)
          if (step.checks.contains(x.id) && !x.value) NoticeCondition(id: x.id, label: conditions[x.id]!.label, menu: fixMenu[x.id]),
      ].take(1).toList();
    }
    d.checking = false;
    if (unmet.isNotEmpty) {
      d.metrics.notices += 1;
      d.notice = DirectNotice(stepId: step.id, stepLabel: step.label, conditions: unmet);
      fsm.transition('UNMET', {'step': step.id, 'unmet': unmet.map((x) => x.id).toList()});
      app.refresh(_screens);
      return;
    }
    if (d.stepIndex >= p.directSteps.length - 1) {
      d.requestId ??= app.bank.newRequestId();
      fsm.transition('ALL_PASSED');
    } else {
      d.stepIndex += 1;
      fsm.transition('PASS', {'next': p.directSteps[d.stepIndex].id});
    }
    app.refresh(_screens);
  }

  void goFix() {
    final d = s;
    if (fsm.state != 'D_NOTICE') return;
    fsm.transition('GO_FIX');
    final menus = [for (final c in d?.notice?.conditions ?? const <NoticeCondition>[]) if (c.menu != null) c.menu!];
    app.navigate(ScreenId.menu, params: {'highlight': menus.isNotEmpty ? menus.first : null, 'from': 'direct'});
  }

  void restart() {
    final d = s;
    if (d == null || fsm.state != 'D_SELF_FIX') return;
    d.stepIndex = 0;
    d.notice = null;
    d.input.agreed = false;
    d.metrics.restarts += 1;
    fsm.transition('RESTART');
    app.navigate(ScreenId.direct, backTo: true);
  }

  Future<void> approve() async {
    final d = s;
    if (d == null || fsm.state != 'D_APPROVE') return;
    final p = product;
    final ok = await app.confirm(ConfirmRequest(
      title: '가입을 신청할까요?',
      rows: [
        ConfirmRow('상품', p.name),
        if (p.maxMonthly != 0) ConfirmRow('월 납입액', formatMan(d.input.monthly)),
        if (p.periods.isNotEmpty) ConfirmRow('가입 기간', '${d.input.months}개월'),
      ],
      fineprint: '가입 완료는 은행 처리 결과로 확인해요.',
      confirmText: '가입 신청',
      cancelText: '취소',
    ));
    if (!ok || fsm.state != 'D_APPROVE') return;
    final ep = app.epoch;
    d.applyNotice = null;
    d.checking = true;
    app.refresh(_screens);
    final r = await app.bank.submitApplication(
      requestId: d.requestId!,
      productId: d.productId,
      terms: p.isBrokerage ? ApplyTerms(market: p.markets.first) : ApplyTerms(monthly: d.input.monthly, months: d.input.months),
      channel: 'DIRECT',
    );
    if (_stale(ep)) return;
    d.checking = false;
    if (!r.ok) {
      final e = r.error!;
      if (e.code == 'CONDITION_UNMET') {
        d.notice = DirectNotice(stepId: 'approve', stepLabel: '가입 신청', conditions: [for (final l in e.unmet ?? const <String>[]) NoticeCondition(label: l)]);
        fsm.transition('REJECTED', {'code': e.code});
      } else {
        d.applyNotice = '${e.message} 다시 신청해도 중복 가입되지 않아요.';
      }
      app.refresh(_screens);
      return;
    }
    d.appId = r.data!.application.id;
    d.application = r.data!.application;
    fsm.transition('APPROVED', {'appId': d.appId});
    app.navigate(ScreenId.applyResult, params: {'track': 'direct'}, replace: true);
    await _verify(ep);
  }

  bool _verifying = false;
  Future<void> _verify(int ep) async {
    if (_verifying) return;
    _verifying = true;
    try {
      await _verifyOnce(ep);
    } finally {
      _verifying = false;
    }
  }

  Future<void> _verifyOnce(int ep) async {
    final d = s!;
    final r = await app.bank.getApplicationResult(d.appId!);
    if (_stale(ep) || fsm.state != 'D_VERIFYING') return;
    if (r.ok) d.application = r.data;
    final status = r.ok ? r.data!.status : 'UNKNOWN';
    if (status == 'SUCCESS') {
      d.metrics.endedAt = nowMs();
      app.session.lastDirectMetrics = d.metrics;
      fsm.transition('RESULT_SUCCESS');
    } else if (status == 'FAILED') {
      fsm.transition('RESULT_FAILED');
    } else {
      fsm.transition('RESULT_UNKNOWN', {'status': status});
    }
    app.refresh(_screens);
  }

  Future<void> queryResult() async {
    if (fsm.state != 'D_UNCERTAIN') return;
    fsm.transition('RESULT_QUERY');
    app.refresh(_screens);
    await _verify(app.epoch);
  }

  Future<void> exit() async {
    if (!fsm.can('EXIT')) return;
    final ok = await app.confirm(ConfirmRequest(
      title: '가입을 그만할까요?',
      paragraphs: const ['입력한 내용은 저장되지 않아요. 다시 가입하면 처음부터 입력해야 해요.'],
      confirmText: '그만하기',
      cancelText: '계속하기',
    ));
    if (!ok || !fsm.can('EXIT')) return;
    fsm.transition('EXIT');
    app.session.direct = null;
    app.navigate(ScreenId.home, resetHistory: true);
  }

  void newCase() {
    if (!fsm.can('NEW_CASE')) return;
    fsm.transition('NEW_CASE');
    app.session.direct = null;
    app.navigate(ScreenId.home, resetHistory: true);
  }

  /// 앱을 다시 여는 등으로 확인 단계에서 멈춘 경우
  void resume() {
    final st = fsm.state;
    if (s == null) return;
    if (st == 'D_CHECK' && !s!.checking) {
      fsm.transition('QUERY_FAILED', {'reason': 'RESUME'});
      app.refresh(_screens);
    } else if (st == 'D_VERIFYING') {
      _verify(app.epoch);
    }
  }

  /* ---------------- 화면 동작 ---------------- */

  /// '직접 가입' 선택
  Future<void> startAction(String productId) async {
    if (fsm.state != 'IDLE') {
      if (s?.productId == productId) {
        await app.navigate(ScreenId.direct);
        return;
      }
      app.toast('진행 중인 직접 가입이 있어요. 홈에서 이어 가거나 그만해 주세요.', UiTone.warning);
      return;
    }
    if (start(productId)) await app.navigate(ScreenId.direct);
  }

  void open() {
    final st = fsm.state;
    if (st == 'IDLE') return;
    if (const ['D_VERIFYING', 'D_UNCERTAIN', 'D_DONE', 'D_FAILED'].contains(st)) {
      app.navigate(ScreenId.applyResult, params: {'track': 'direct'});
    } else if (st == 'D_SELF_FIX') {
      app.navigate(ScreenId.menu, params: {'from': 'direct'});
    } else {
      app.navigate(ScreenId.direct);
    }
  }

  void toggleAgree() {
    final d = s;
    if (d == null) return;
    d.input.agreed = !d.input.agreed;
    app.refresh(const []);
  }

  void setMonths(int months) {
    final d = s;
    if (d == null) return;
    d.input.months = months;
    app.refresh(const []);
  }

  void setMonthly(String text) {
    final d = s;
    if (d == null) return;
    d.input.monthly = digitsOf(text);
    app.save();
  }
}
