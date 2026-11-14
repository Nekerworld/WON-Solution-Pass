/// 계획 7장 검증 항목 (시연 제어 → 자가 테스트, flutter test).
/// 테스트마다 별도의 가상 은행·흐름을 새로 만들어 돌리므로 시연 중인 상태는 바뀌지 않는다.
/// 화면 이동·모달은 headless 모드로 대체하고 실제 흐름 코드를 그대로 실행한다.
library;

import '../app/app_controller.dart';
import '../app/join_flow.dart';
import '../app/sessions.dart';
import '../data/key_value_storage.dart';
import '../domain/ai_schema.dart';
import '../domain/asset_advisor.dart' as aa;
import '../domain/bank_state.dart';
import '../domain/fsm.dart';
import '../domain/rule_engine.dart' as re;
import '../domain/scenario.dart';
import '../ui/app_scope.dart';

const _pid = 'SAVINGS_GOAL';

class SelfTestResult {
  const SelfTestResult(this.name, this.ok, [this.detail]);
  final String name;
  final bool ok;
  final String? detail;
}

class SelfTestReport {
  const SelfTestReport(this.results);
  final List<SelfTestResult> results;
  int get total => results.length;
  int get passed => results.where((r) => r.ok).length;
  int get failed => total - passed;
}

class _Fail implements Exception {
  _Fail(this.message);
  final String message;
  @override
  String toString() => message;
}

void _assert(bool cond, [String msg = '조건 불일치']) {
  if (!cond) throw _Fail(msg);
}

/// 테스트 1개가 쓰는 격리된 앱
class _Env {
  _Env([void Function(BankState d)? mutator]) : s = createServices(MemoryStorage(), latencyScale: 0, headless: true) {
    if (mutator != null) s.store.update(mutator, '[자가 테스트] 상태 설정');
  }

  final AppServices s;
  AppController get app => s.controller;
  JoinFlow get j => app.join;
  JoinSession get js => app.session.join!;
  AssetSession get as => app.session.asset!;
  Fsm get jf => app.joinFsm;
  Fsm get af => app.assetFsm;

  void dispose() => app.dispose();

  /// 묻는 질문에는 answers(없으면 true)로 답한다
  Future<void> startJoin([Map<String, bool> answers = const {}, String productId = _pid]) async {
    j.start(productId);
    await j.agree();
    for (var i = 0; i < 5 && app.session.join?.pendingKey != null; i++) {
      final key = app.session.join!.pendingKey!;
      await j.answer(key, answers[key] ?? true);
    }
  }

  /// 모달에서 업무를 진행한 것처럼 처리하고 닫는다. run=false면 진행 없이 닫기
  Future<void> doTask(String taskId, bool run) async {
    await j.chooseOption(taskId);
    final ct = js.currentTask!;
    var status = 'OPEN';
    if (run) {
      final r = await s.bank.runTask(ct.sessionId, {'job': '회사원', 'purpose': '저축·자산 형성'});
      status = r.ok ? r.data!.status : 'REJECTED';
    }
    await j.modalClosed(status);
  }

  Future<re.Evaluation> evaluate([String pid = _pid]) async => re.evaluate(pid, await s.bank.checkConditions(pid));
}

void _onlyIdentityMissing(BankState d) {
  for (final k in d.facts.keys.toList()) {
    d.facts[k] = true;
  }
  d.facts['identityVerified'] = false;
}

void _allMet(BankState d) {
  for (final k in d.facts.keys.toList()) {
    d.facts[k] = true;
  }
}

typedef _TestFn = Future<void> Function();

final List<(String, _TestFn)> _tests = [];
void _t(String name, _TestFn fn) => _tests.add((name, fn));

/// [mutator]로 은행 상태를 설정한 격리 환경에서 [fn]을 실행한다
Future<void> _with(void Function(BankState d)? mutator, Future<void> Function(_Env e) fn) async {
  final e = _Env(mutator);
  try {
    await fn(e);
  } finally {
    e.app.invalidate();
    e.dispose();
  }
}

/// 0-1 원본 워크플로우 화살표 (from, event, to)
const Map<FsmKind, List<(String, String, String)>> _diagram = {
  FsmKind.join: [
    ('IDLE', 'START', 'CONSENT'),
    ('CONSENT', 'AGREE', 'CHECKING'),
    ('CHECKING', 'NONE_MISSING', 'READY_TO_APPLY'),
    ('CHECKING', 'MISSING', 'CLARIFYING'),
    ('CLARIFYING', 'CLARIFIED', 'ROUTE_CHECK'),
    ('ROUTE_CHECK', 'ROUTE_FOUND', 'OPTIONS_READY'),
    ('ROUTE_CHECK', 'NO_ROUTE', 'ESCALATED'),
    ('OPTIONS_READY', 'TASK_OPENED', 'TASK_OPEN'),
    ('TASK_OPEN', 'MODAL_CLOSED', 'RECHECKING'),
    ('RECHECKING', 'ALL_MET', 'READY_TO_APPLY'),
    ('RECHECKING', 'REMAINING', 'REMAINING'),
    ('RECHECKING', 'EXCEPTION', 'INVESTIGATING'),
    ('REMAINING', 'TASK_OPENED', 'TASK_OPEN'),
    ('INVESTIGATING', 'UNRESOLVABLE', 'ESCALATED'),
    ('READY_TO_APPLY', 'APPROVED', 'APPLYING'),
    ('APPLYING', 'SUBMITTED', 'VERIFYING'),
    ('VERIFYING', 'RESULT_SUCCESS', 'COMPLETED'),
    ('VERIFYING', 'RESULT_FAILED', 'FAILED'),
    ('VERIFYING', 'RESULT_UNKNOWN', 'RESULT_UNCERTAIN'),
  ],
  FsmKind.asset: [
    ('IDLE', 'START', 'CONSENT'),
    ('CONSENT', 'AGREE', 'GOAL'),
    ('GOAL', 'GOAL_SET', 'COLLECTING'),
    ('COLLECTING', 'COLLECTED', 'TAGGING'),
    ('TAGGING', 'TAGGED', 'CALCULATING'),
    ('CALCULATING', 'CALCULATED', 'INTERPRETING'),
    ('INTERPRETING', 'INTERPRETED', 'GAP_CHECK'),
    ('GAP_CHECK', 'NO_GAP', 'PROPOSED_FULL'),
    ('GAP_CHECK', 'ASK', 'ASKING'),
    ('GAP_CHECK', 'LIMIT_OR_STOP', 'PROPOSABLE_CHECK'),
    ('ASKING', 'ANSWERED', 'RECALC_ANSWER'),
    ('ASKING', 'UNKNOWN_OR_REFUSED', 'PROPOSABLE_CHECK'),
    ('ASKING', 'STOP_REQUEST', 'PROPOSABLE_CHECK'),
    ('RECALC_ANSWER', 'RECALCULATED', 'INTERPRETING'),
    ('PROPOSABLE_CHECK', 'PROPOSABLE', 'PROPOSED_LIMITED'),
    ('PROPOSABLE_CHECK', 'NOT_PROPOSABLE', 'HOLD'),
    ('PROPOSED_FULL', 'SHOWN', 'REVIEW'),
    ('PROPOSED_LIMITED', 'SHOWN', 'REVIEW'),
    ('REVIEW', 'ACCEPT', 'NEXT_ACTION'),
    ('REVIEW', 'MODIFY', 'RECALC_CHANGE'),
    ('REVIEW', 'END', 'CLOSED'),
    ('RECALC_CHANGE', 'RECALCULATED', 'INTERPRETING'),
    ('NEXT_ACTION', 'CONSULT', 'HANDOFF'),
    ('NEXT_ACTION', 'KEEP', 'CLOSED'),
    ('NEXT_ACTION', 'RECHECK_INFO', 'RECONSULT'),
    ('NEXT_ACTION', 'EXPLORE', 'EXPLORE'),
    ('EXPLORE', 'PRODUCT_SELECTED', 'TO_JOIN'),
  ],
  FsmKind.direct: [
    ('IDLE', 'START', 'D_START'),
    ('D_START', 'BEGIN', 'D_STEP'),
    ('D_STEP', 'STEP_DONE', 'D_CHECK'),
    ('D_CHECK', 'PASS', 'D_STEP'),
    ('D_CHECK', 'UNMET', 'D_NOTICE'),
    ('D_NOTICE', 'GO_FIX', 'D_SELF_FIX'),
    ('D_VERIFYING', 'RESULT_SUCCESS', 'D_DONE'),
  ],
};

void _defineTests() {
  if (_tests.isNotEmpty) return;

  _t('조회 실패는 미충족이 아니라 UNKNOWN으로 판정', () => _with((d) => d.simulation.queryFailure = true, (e) async {
        final ev = await e.evaluate();
        _assert(!ev.ok, '조회 실패가 ok로 판정됨');
        _assert(ev.conditions.every((c) => c.status == 'UNKNOWN'), 'UNKNOWN이 아닌 조건이 있음');
        _assert(ev.unmet.isEmpty && !ev.allMet, '미충족·충족으로 단정함');
        _assert(e.s.pathfinder.computeRoute(ev, {}).status == 'UNKNOWN', '조회 실패로 경로를 만듦');
      }));

  _t('조회 실패 시 가입 지원은 CHECK_FAILED(P3)로 멈춤', () => _with((d) => d.simulation.queryFailure = true, (e) async {
        await e.startJoin();
        _assert(e.jf.state == 'CHECK_FAILED', '상태 ${e.jf.state}');
      }));

  _t('고객 제약에 따라 경로가 걸러짐 (신분증 없음 → 모바일 신분증)', () => _with(null, (e) async {
        final ev = await e.evaluate();
        final pf = e.s.pathfinder;
        final r1 = pf.computeRoute(ev, {'hasIdCard': false, 'hasMobileId': true, 'hasOtherBankAccount': true});
        _assert(r1.status == 'PLAN' && r1.steps.isNotEmpty && r1.steps.first.actionId == 'MOBILE_ID_VERIFY', '첫 단계 ${r1.steps.isEmpty ? '-' : r1.steps.first.actionId}');
        _assert(r1.options.firstWhere((o) => o.actionId == 'ID_CARD_VERIFY').availability == 'BLOCKED', '신분증 수단이 막히지 않음');
        final r2 = pf.computeRoute(ev, {'hasIdCard': true, 'hasMobileId': false, 'hasOtherBankAccount': true});
        _assert(r2.steps.first.actionId == 'ID_CARD_VERIFY', '신분증 경로가 아님');
        final r3 = pf.computeRoute(ev, {'hasIdCard': false, 'hasMobileId': false, 'hasOtherBankAccount': true});
        _assert(r3.status == 'NO_PATH', '실명확인 수단이 없는데 경로가 있음');
      }));

  _t('필요한 경우에만 질문 (P4): 모르는 사정은 질문 목록, 확인된 경로가 있으면 질문 없음', () => _with(null, (e) async {
        final ev = await e.evaluate();
        final r1 = e.s.pathfinder.computeRoute(ev, {'hasIdCard': null, 'hasMobileId': null, 'hasOtherBankAccount': true});
        _assert(r1.questions.isNotEmpty && r1.questions.first == 'hasIdCard', '질문 ${r1.questions.join(',')}');
        final r2 = e.s.pathfinder.computeRoute(ev, {'hasIdCard': true, 'hasMobileId': null, 'hasOtherBankAccount': true});
        _assert(r2.questions.isEmpty, '확인된 경로가 있는데 질문함');
      }));

  _t('순환(계좌↔인증서) 감지 → 상담 전환', () => _with((d) => d.finance.otherBankAccounts = [], (e) async {
        await e.startJoin({'hasIdCard': false, 'hasMobileId': true, 'hasOtherBankAccount': false});
        _assert(e.jf.state == 'ESCALATED', '상태 ${e.jf.state}');
        final esc = e.js.escalation;
        _assert(esc != null && esc.reason == 'CYCLE', '사유 ${esc?.reason}');
        final chain = esc!.cause?.chain ?? const [];
        _assert(chain.contains('hasDepositAccount') && chain.contains('certRegistered'), '순환 구성 $chain');
      }));

  _t('은행이 아는 정보(다른 은행 계좌·휴대폰 명의)는 다시 묻지 않음', () => _with(null, (e) async {
        await e.startJoin({'hasIdCard': false, 'hasMobileId': true});
        final j = e.js;
        _assert(j.constraintSource['hasOtherBankAccount']?.$1 == 'BANK', '다른 은행 계좌 출처');
        _assert(j.skipped.length >= 2, '생략 기록 없음');
        _assert(j.questionsAsked == 2, '질문 수 ${j.questionsAsked}');
      }));

  _t('모달을 닫기만 하면 완료로 판정하지 않음', () => _with(null, (e) async {
        await e.startJoin();
        _assert(e.jf.state == 'OPTIONS_READY', '시작 상태 ${e.jf.state}');
        await e.doTask('ID_CARD_VERIFY', false);
        _assert(e.jf.state == 'REMAINING', '상태 ${e.jf.state}');
        _assert(e.s.store.state.facts['identityVerified'] == false, '은행 사실이 바뀜');
      }));

  _t('모달 결과 5가지 → 조건 충족 / 남은 조건 / 예외 3분기 (P3)', () async {
    const cases = [
      ('성공', 'NORMAL', true, 'READY_TO_APPLY'),
      ('취소', 'NORMAL', false, 'REMAINING'),
      ('일부 완료', 'PARTIAL', true, 'REMAINING'),
      ('처리 중', 'IN_PROGRESS', true, 'INVESTIGATING'),
      ('확인 실패', 'QUERY_FAIL', true, 'INVESTIGATING'),
    ];
    for (final c in cases) {
      await _with(_onlyIdentityMissing, (e) async {
        await e.startJoin();
        if (c.$2 != 'QUERY_FAIL') e.s.store.update((d) => d.simulation.nextTaskOutcome = c.$2, '[자가 테스트] 업무 결과');
        await e.j.chooseOption('ID_CARD_VERIFY');
        final ct = e.js.currentTask!;
        var status = 'OPEN';
        if (c.$3) status = (await e.s.bank.runTask(ct.sessionId, {})).data?.status ?? 'REJECTED';
        if (c.$2 == 'QUERY_FAIL') e.s.store.update((d) => d.simulation.queryFailure = true, '[자가 테스트] 조회 실패');
        await e.j.modalClosed(status);
        _assert(e.jf.state == c.$4, '${c.$1}: 기대 ${c.$4}, 실제 ${e.jf.state}');
      });
    }
  });

  _t('처리 중 업무는 결과 재조회 후 해결되면 재확인(P2)', () => _with(_onlyIdentityMissing, (e) async {
        await e.startJoin();
        e.s.store.update((d) => d.simulation.nextTaskOutcome = 'IN_PROGRESS', '[자가 테스트]');
        await e.doTask('ID_CARD_VERIFY', true);
        _assert(e.jf.state == 'INVESTIGATING', '상태 ${e.jf.state}');
        await e.j.investigate('requery');
        _assert(e.jf.state == 'READY_TO_APPLY', '상태 ${e.jf.state}');
      }));

  _t('완료 불일치가 2회 반복되면 같은 업무를 반복시키지 않고 상담 전환', () => _with((d) {
        _onlyIdentityMissing(d);
        d.simulation.nextTaskOutcome = 'MISMATCH_ALWAYS';
      }, (e) async {
        await e.startJoin();
        await e.doTask('ID_CARD_VERIFY', true);
        _assert(e.jf.state == 'INVESTIGATING', '1회 후 ${e.jf.state}');
        await e.j.investigate('retry');
        _assert(e.jf.state == 'REMAINING', '재시도 후 ${e.jf.state}');
        await e.doTask('ID_CARD_VERIFY', true);
        _assert(e.jf.state == 'ESCALATED', '2회 후 ${e.jf.state}');
        _assert(e.js.escalation?.reason == 'REPEAT', '사유 ${e.js.escalation?.reason}');
      }));

  _t('AI 가입 지원 주 경로: 신분증 없음 → 모바일 신분증 → 계좌 → 인증서·고객정보 → 승인 → 완료', () => _with(null, (e) async {
        await e.startJoin({'hasIdCard': false, 'hasMobileId': true});
        final order = <String>[];
        for (var i = 0; i < 6 && (e.jf.state == 'OPTIONS_READY' || e.jf.state == 'REMAINING'); i++) {
          final next = e.js.route!.steps.first.actionId;
          order.add(next);
          await e.doTask(next, true);
        }
        _assert(order.first == 'MOBILE_ID_VERIFY', '첫 업무 ${order.first}');
        final acc = order.indexOf('OPEN_ACCOUNT_OTHERBANK');
        _assert(acc != -1 && acc < order.indexOf('ISSUE_CERT'), '계좌보다 인증서가 먼저: ${order.join(',')}');
        _assert(order.length == 4 && order.contains('KYC_UPDATE'), '업무 ${order.join(',')}');
        _assert(e.jf.state == 'READY_TO_APPLY', '준비 상태 ${e.jf.state}');
        _assert(e.s.store.state.applications.isEmpty, '승인 전에 가입 요청됨');
        await e.j.approve(const ApplyTerms(monthly: 300000, months: 24, account: 'WON 통장'));
        _assert(e.jf.state == 'COMPLETED', '결과 ${e.jf.state}');
      }));

  _t('통합 시나리오 상담: 해외주식 투자 상담 → 투자 방향 제안 → 해외주식 계좌로 연결', () => _with(null, (e) async {
        final f = e.app.asset;
        f.start();
        f.agree();
        await f.setGoal('해외주식 투자를 처음 시작해 보고 싶어요');
        final a = e.as;
        _assert(a.purpose == 'INVEST', '목적 ${a.purpose}');
        var n = 0;
        while (e.af.state == 'ASKING' && n < 4) {
          final q = aa.questions[a.pendingQuestion]!;
          await f.answerChip('${q.options[0].$2}', q.options[0].$1);
          n += 1;
        }
        _assert(e.af.state == 'REVIEW' && a.proposal?.level == 'FULL', '상태 ${e.af.state} / ${a.proposal?.level}');
        _assert(a.proposal!.basis.monthly == 490000, '월 투자 금액 ${a.proposal!.basis.monthly}');
        final prop = a.chat.lastWhere((m) => m.kind == 'proposal', orElse: () => ChatMsg(id: 0, at: 0, role: 'ai', text: ''));
        _assert(prop.text.contains('원금 손실'), '투자 위험 안내 없음');
        await f.accept();
        f.nextAction('explore');
        _assert(e.af.state == 'EXPLORE', '상태 ${e.af.state}');
        final t = a.handoffTerms!;
        final list = aa.matchProducts(tags: t.tags, monthly: t.monthly, months: t.months);
        _assert(list.length == 1 && list.first.productId == DemoScenario.productId, '추천 상품 ${list.map((x) => x.productId)}');
      }));

  _t('통합 시나리오 가입: 신분증 없음 → 숨은 선행조건 7단계 → 투자성향은 주식계좌 직전 → 승인 → 개설', () => _with(null, (e) async {
        await e.startJoin({'hasIdCard': false, 'hasMobileId': true}, DemoScenario.productId);
        _assert(e.js.questionsAsked == 2, '질문 ${e.js.questionsAsked}');
        final order = <String>[];
        for (var i = 0; i < 10 && (e.jf.state == 'OPTIONS_READY' || e.jf.state == 'REMAINING'); i++) {
          final next = e.js.route!.steps.first.actionId;
          order.add(next);
          await e.doTask(next, true);
        }
        const expected = ['MOBILE_ID_VERIFY', 'OPEN_ACCOUNT_OTHERBANK', 'ISSUE_CERT', 'KYC_UPDATE', 'FX_REGISTER', 'OPEN_FX_ACCOUNT', 'INVESTOR_PROFILE'];
        _assert(order.join(',') == expected.join(','), '업무 순서 ${order.join(',')}');
        _assert(e.jf.state == 'READY_TO_APPLY', '준비 상태 ${e.jf.state}');
        await e.j.approve(const ApplyTerms(market: '미국', account: 'WON 통장', fxAccount: 'WON 외화통장(USD)'));
        _assert(e.jf.state == 'COMPLETED', '결과 ${e.jf.state}');
        final s = e.s.store.state;
        _assert(DemoScenario.stages.every((st) => st.facts.every((k) => s.facts[k] == true)), '진행 단계 사실 미충족');
      }));

  _t('가입 결과 조회는 요청을 다시 보내지 않고, 같은 requestId는 중복 가입을 만들지 않음', () => _with((d) {
        _allMet(d);
        d.simulation.nextApplicationOutcome = 'PENDING';
      }, (e) async {
        final bank = e.s.bank;
        final req = bank.newRequestId();
        final r1 = await bank.submitApplication(requestId: req, productId: _pid, terms: const ApplyTerms());
        final r2 = await bank.submitApplication(requestId: req, productId: _pid, terms: const ApplyTerms());
        _assert(r1.ok && r2.ok && r2.data!.duplicate, '중복 차단 안 됨');
        final id = r1.data!.application.id;
        for (var i = 0; i < 3; i++) {
          await bank.getApplicationResult(id);
        }
        final apps = e.s.store.state.applications;
        _assert(apps.length == 1, '가입 요청 ${apps.length}건');
        _assert(apps[id]?.status == 'PENDING', '조회만으로 상태가 바뀜');
      }));

  _t('결과 불명 → 결과 조회만 허용, 은행 확정 후 완료', () => _with((d) {
        _allMet(d);
        d.simulation.nextApplicationOutcome = 'UNKNOWN';
      }, (e) async {
        await e.startJoin();
        _assert(e.jf.state == 'READY_TO_APPLY', '시작 ${e.jf.state}');
        await e.j.approve(const ApplyTerms(monthly: 300000, months: 24, account: 'WON 통장'));
        _assert(e.jf.state == 'RESULT_UNCERTAIN', '상태 ${e.jf.state}');
        _assert(!e.jf.can('APPROVED'), '재신청 전이가 열려 있음');
        e.s.bank.demoResolveApplication(e.js.appId!, 'SUCCESS');
        await e.j.queryResult();
        _assert(e.jf.state == 'COMPLETED', '조회 후 ${e.jf.state}');
        _assert(e.s.store.state.applications.length == 1, '가입 요청이 추가됨');
      }));

  _t('늦게 도착한 응답과 연타는 무시됨', () => _with(null, (e) async {
        e.s.bank.latencyScale = 1;
        e.j.start(_pid);
        final p = e.j.agree();
        e.app.invalidate();
        await p;
        _assert(e.js.evaluation == null, '무효화 이후 조회 결과가 반영됨');
        e.s.bank.latencyScale = 0;
        var calls = 0;
        Future<int> slow() => Future.delayed(const Duration(milliseconds: 30), () => ++calls);
        await Future.wait([e.app.guard('t', slow), e.app.guard('t', slow)]);
        _assert(calls == 1, '연타가 $calls회 실행됨');
      }));

  _t('정정된 정보로 지표를 다시 계산하고 이력을 남김', () => _with(null, (e) async {
        final info = aa.createInfo(e.s.store.state.finance.items);
        aa.setItem(info, 'goalMonths', 24, 'STATED', '목표');
        final m1 = aa.computeMetrics(info);
        aa.setItem(info, 'monthlyExpense', 1500000, 'STATED', '고객 정정');
        final m2 = aa.computeMetrics(info);
        _assert(m1['surplus'].value == 1400000 && m2['surplus'].value == 2000000, '여유자금 ${m1['surplus'].value}→${m2['surplus'].value}');
        final h = info.history.where((x) => x.key == 'monthlyExpense').firstOrNull;
        _assert(h != null && h.correction && h.fromSource == 'ESTIMATED' && h.toSource == 'STATED', '정정 이력 없음');
        _assert(aa.computeMetrics(info)['needMonthly'].value == m2['needMonthly'].value, '같은 입력에 다른 결과');
      }));

  _t('질문 중단 요청 → 제한적 제안 (PROPOSABLE_CHECK → PROPOSED_LIMITED)', () => _with(null, (e) async {
        final f = e.app.asset;
        f.start();
        f.agree();
        await f.setGoal('2년 뒤 집 살 때 보탤 목돈');
        _assert(e.af.state == 'ASKING', '질문 상태 아님 ${e.af.state}');
        await f.answerChip('STOP', '질문은 그만');
        _assert(e.af.state == 'REVIEW', '상태 ${e.af.state}');
        _assert(e.as.proposal?.level == 'LIMITED', '제안 수준 ${e.as.proposal?.level}');
      }));

  _t('질문 한도(3회)에 도달하면 더 묻지 않고 제안 가능 판단으로', () => _with((d) {
        d.finance.items['monthlyIncome'] = FinItem(value: null, source: 'UNKNOWN', basis: '');
        d.finance.items['monthlyExpense'] = FinItem(value: null, source: 'UNKNOWN', basis: '');
      }, (e) async {
        final f = e.app.asset;
        f.start();
        f.agree();
        await f.setGoal('2년 뒤 목돈 마련');
        var n = 0;
        while (e.af.state == 'ASKING' && n < 6) {
          final q = aa.questions[e.as.pendingQuestion]!;
          await f.answerChip('${q.options[1].$2}', q.options[1].$1);
          n += 1;
        }
        _assert(n == Policy.assetQuestionLimit, '질문 $n회');
        _assert(e.af.history().any((h) => h.event == 'LIMIT_OR_STOP'), '한도 분기 없음');
        _assert(e.af.state == 'REVIEW' && e.as.proposal?.level == 'LIMITED', '상태 ${e.af.state}');
        final chat = e.as.chat;
        _assert(!chat.any((m) => m.text.contains('반영했어요')), '답변 확인 메시지가 남아 있음');
        final props = chat.where((m) => m.kind == 'proposal').toList();
        final prop = props.isEmpty ? null : props.last;
        _assert(prop != null && (prop.figures?.length ?? 0) >= 2, '제안 큰 숫자 없음');
        _assert(prop!.text.contains('실제와 다를 수 있어요'), '불확실성 안내 없음: ${prop.text}');
      }));

  _t('모름·답변 거부는 재계산 없이 제안 가능 판단으로 가고, 최소 정보가 없으면 보류', () => _with((d) {
        d.finance.items['monthlyIncome'] = FinItem(value: null, source: 'UNKNOWN', basis: '');
      }, (e) async {
        final f = e.app.asset;
        f.start();
        f.agree();
        await f.setGoal('2년 뒤 목돈 마련');
        _assert(e.as.pendingQuestion == 'monthlyIncome', '질문 ${e.as.pendingQuestion}');
        final before = e.af.history().length;
        await f.answerChip('UNKNOWN', '잘 모르겠어요');
        final after = e.af.history().sublist(before).map((h) => h.to).toList();
        _assert(after.isNotEmpty && after.first == 'PROPOSABLE_CHECK', '다음 상태 ${after.firstOrNull}');
        _assert(!after.contains('RECALC_ANSWER'), '재계산을 거침');
        _assert(e.af.state == 'HOLD', '상태 ${e.af.state}');
      }));

  _t('AI 출력 검증기: 경로에 없는 업무·가입 실행·완료 단정을 거부', () async {
    final ok = validateAi(
      const AiOutput(intent: 'X', message: '방법을 골라 주세요', actions: [AiAction('PRESENT_OPTIONS', {'options': ['ID_CARD_VERIFY']})]),
      const AiContext(allowedActionIds: ['ID_CARD_VERIFY']),
    );
    _assert(ok.valid, '정상 출력 거부: ${ok.errors.join(',')}');
    _assert(
      !validateAi(
        const AiOutput(intent: 'X', message: '', actions: [AiAction('PRESENT_OPTIONS', {'options': ['ISSUE_CERT']})]),
        const AiContext(allowedActionIds: ['ID_CARD_VERIFY']),
      ).valid,
      '허용 안 된 업무 통과',
    );
    _assert(!validateAi(const AiOutput(intent: 'X', message: '', actions: [AiAction('CALL_TOOL', {'tool': 'submitApplication'})]), const AiContext()).valid, '가입 실행 도구 통과');
    _assert(!validateAi(const AiOutput(intent: 'X', message: '가입이 완료됐어요', actions: []), const AiContext()).valid, '완료 단정 통과');
    _assert(!validateAi(const AiOutput(intent: 'X', message: '', actions: [AiAction('SET_CONSTRAINT', {'key': 'hasCar', 'value': true})]), const AiContext()).valid, '모르는 제약 통과');
    await _with(null, (e) async {
      e.s.ai.injectInvalidNext();
      final r = await e.s.ai.joinAsk('hasIdCard', const []);
      _assert(r.fallback && !r.valid, '주입한 위반이 통과됨');
    });
  });

  _t('같은 데이터로 AI 경로와 직접 가입의 조건 판정이 일치', () => _with(null, (e) async {
        final keys = facts.keys.where((k) => k != 'adult').toList();
        for (final pid in [_pid, DemoScenario.productId]) {
          for (var mask = 0; mask < 1 << keys.length; mask++) {
            e.s.store.reset('[자가 테스트] 초기화');
            e.s.store.update((d) {
              for (var i = 0; i < keys.length; i++) {
                d.facts[keys[i]] = mask & (1 << i) != 0;
              }
            }, '[자가 테스트] 상태 설정');
            final c = await e.s.bank.checkConditions(pid);
            final aiUnmet = [...re.evaluate(pid, c).unmet]..sort();
            final directUnmet = <String>[];
            for (final st in getProduct(pid)!.directSteps) {
              for (final id in st.checks) {
                if (!c.data!.conditions.firstWhere((x) => x.id == id).value) directUnmet.add(id);
              }
            }
            directUnmet.sort();
            _assert(aiUnmet.join(',') == directUnmet.join(','), '$pid mask $mask: $aiUnmet / $directUnmet');
          }
        }
      }));

  _t('직접 가입: 부족 조건 안내 → 메뉴에서 해결 → 1단계부터 다시 (P6)', () => _with(_onlyIdentityMissing, (e) async {
        final d = e.app.direct;
        d.start(_pid);
        d.begin();
        e.app.session.direct!.input.agreed = true;
        await d.next();
        await d.next();
        await d.next();
        _assert(e.app.directFsm.state == 'D_NOTICE', '상태 ${e.app.directFsm.state}');
        _assert(e.app.session.direct!.notice?.conditions.first.id == 'IDENTITY', '안내 조건');
        d.goFix();
        e.s.store.update((s) => s.facts['identityVerified'] = true, '[자가 테스트] 메뉴에서 실명확인');
        d.restart();
        _assert(e.app.directFsm.state == 'D_STEP' && e.app.session.direct!.stepIndex == 0, '1단계로 돌아가지 않음');
        _assert(e.app.session.direct!.metrics.restarts == 1, '다시 시작 횟수');
      }));

  _t('상태머신 전이표가 원본 화살표를 모두 포함하고, 추가 전이는 제안(P1~P8)·안전(S)뿐', () async {
    final src = RegExp(r'^(P[1-8]|S)$');
    _diagram.forEach((kind, list) {
      final tbl = fsmTables[kind]!;
      for (final (from, ev, to) in list) {
        _assert(tbl.table[from]?[ev] == to, '${kind.name} 원본 화살표 누락: $from $ev $to');
      }
      final keys = {for (final (from, ev, _) in list) '$from|$ev'};
      for (final e in fsmDefs[kind]!.edges) {
        final k = '${e.$1}|${e.$2}';
        if (keys.contains(k)) continue;
        _assert(src.hasMatch(e.$4), '${kind.name} 원본에 없는데 제안·안전 전이로 표시되지 않음: $k (${e.$4})');
      }
    });
  });

  _t('상담 접수 실패와 요약 생성을 구분', () => _with((d) => d.simulation.nextConsultOutcome = 'FAILED', (e) async {
        final r = await e.s.bank.createConsultation(['요약']);
        _assert(!r.ok && r.error!.code == 'CONSULT_FAILED', '실패가 접수로 처리됨');
        _assert(e.s.store.state.consultations.isEmpty, '실패했는데 접수 기록 생성');
      }));
}

int get selfTestCount {
  _defineTests();
  return _tests.length;
}

/// 자가 테스트를 모두 실행한다. [onProgress]는 테스트 1개가 끝날 때마다 불린다.
Future<SelfTestReport> runSelfTests({void Function(SelfTestResult r)? onProgress}) async {
  _defineTests();
  final results = <SelfTestResult>[];
  for (final (name, fn) in _tests) {
    SelfTestResult r;
    try {
      await fn();
      r = SelfTestResult(name, true);
    } catch (e) {
      r = SelfTestResult(name, false, e.toString());
    }
    results.add(r);
    onProgress?.call(r);
  }
  return SelfTestReport(results);
}
