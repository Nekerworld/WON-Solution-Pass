/// 계획 7장 검증 항목 (시연 제어 → 자가 테스트, flutter test).
/// 테스트마다 별도의 가상 은행·흐름을 새로 만들어 돌리므로 시연 중인 상태는 바뀌지 않는다.
/// 화면 이동·모달은 headless 모드로 대체하고 실제 흐름 코드를 그대로 실행한다.
library;

import 'dart:convert';

import '../app/app_controller.dart';
import '../app/asset_flow.dart' show cookieLines;
import '../app/demo_profile.dart';
import '../app/join_flow.dart';
import '../app/sessions.dart';
import '../data/key_value_storage.dart';
import '../domain/ai_schema.dart';
import '../domain/asset_advisor.dart' as aa;
import '../domain/bank_state.dart';
import '../domain/formatters.dart';
import '../domain/fsm.dart';
import '../domain/goal_info.dart' as gi;
import '../domain/lumpsum_advisor.dart' as la;
import '../domain/lumpsum_script.dart' as ls;
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
  Fsm get lf => app.lumpsumFsm;

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

  void setMoney(int income, int expense, [int debt = 0]) {
    final pay = la.debtPayment(debt);
    s.store.update((d) {
      d.finance.items['monthlyIncome']!.value = income;
      d.finance.items['monthlyExpense']!.value = expense;
      d.finance.items['debt']!.value = debt;
      d.finance.items['debtPayment']!.value = pay;
    }, '[자가 테스트] 목돈 프로필');
  }

  /// 손실 질문에 답한 뒤 목표에 못 미치면 부족 안내가 한 번 나온다. 기존 흐름 테스트는 "지금 비중으로"를 골라 추천으로 간다
  Future<void> keepShare() async {
    if (lf.state == 'SHORTFALL') await app.lumpsum.accept('지금 비중으로 갈게요', 'sf-keep');
  }

  Future<LumpsumSession> lumpUntilGoal([String goalId = 'goal-100']) async {
    final l = app.lumpsum;
    final goal = la.lumpGoals[goalId]!;
    _assert(l.startNew(), '목돈 상담 시작 ${lf.state}');
    await l.accept(ls.opening);
    // 월 여유가 없으면 목표를 묻지 않고 바로 지출 계획으로 간다
    if (lf.state == 'GOAL') await l.accept(goal.text, goalId);
    return app.session.lumpsum!;
  }
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

/// 계좌가 없는 첫 거래 고객. 기본 시연 고객은 계좌·인증서·고객정보가 있다.
void asNewCustomer(BankState d) {
  d.customer.firstTimeCustomer = true;
  d.facts['identityVerified'] = false;
  d.facts['hasDepositAccount'] = false;
  d.facts['certRegistered'] = false;
  d.facts['kycDone'] = false;
}

String _kindsOf(LumpRow m) => m.blocks.map((b) => b.t).join(',');

String _rowJson(LumpRow m) => jsonEncode(m.toJson());

/// AI 메시지에 들어 있는 카드 묶음 목록 (메시지 순서대로)
List<List<aa.Figure>> _figsRows(LumpsumSession s) => [
      for (final m in s.chat)
        for (final b in m.blocks)
          if (b.t == 'figures') b.figures,
    ];

String _values(List<aa.Figure> figs) => figs.map((f) => f.value).join('|');

void _assertClean(String text) {
  _assert(!ls.banned.hasMatch(text), '금지어: $text');
  for (final re in aiForbiddenPhrases) {
    _assert(!re.hasMatch(text), '완료 단정: $text');
  }
}

String _aiLast(LumpsumSession s) => s.chat.last.text;

LumpRow _lastAi(LumpsumSession s) => s.chat.lastWhere((m) => m.role == 'ai');

String _allText(LumpsumSession s) => s.chat.map((m) => m.text).join('\n');

la.LumpAdvice _advise({
  int income = 3500000,
  int expense = 2100000,
  int debt = 0,
  int deposit = la.depositDefault,
  int goalAmount = 80000000,
  int goalMonths = 36,
  String expText = '',
  String lossText = '',
  bool investFocus = false,
  double? boldShare,
}) =>
    la.advise(la.AdviseInput(
      income: income,
      expense: expense,
      debt: debt,
      deposit: deposit,
      goalAmount: goalAmount,
      goalMonths: goalMonths,
      expText: expText,
      lossText: lossText,
      investFocus: investFocus,
      boldShare: boldShare,
    ));

/// JS 숫자 문자열과 같게 쓴다 (7.0 → "7")
String _jsNum(num v) => aa.numText(v);

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
    ('ASKING', 'SKIP_ONE', 'GAP_CHECK'),
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

  _t('프롬프트 쿠키는 종목을 추천하지 않는다', () => _with(null, (e) async {
        final lines = cookieLines(e.s.store.state);
        final banned = RegExp(r'종목|매수|매도|수익률|추천주|사세요');
        _assert(lines.length >= 8, '문장 수 ${lines.length}');
        for (final line in lines) {
          _assert(!banned.hasMatch(line), line);
          _assert(line.length <= 120, '${line.length} $line');
        }
      }));

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

  _t('고객 제약에 따라 경로가 걸러짐 (신분증 없음 → 모바일 신분증)', () => _with(asNewCustomer, (e) async {
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

  _t('필요한 경우에만 질문 (P4): 모르는 사정은 질문 목록, 확인된 경로가 있으면 질문 없음', () => _with(asNewCustomer, (e) async {
        final ev = await e.evaluate();
        final r1 = e.s.pathfinder.computeRoute(ev, {'hasIdCard': null, 'hasMobileId': null, 'hasOtherBankAccount': true});
        _assert(r1.questions.isNotEmpty && r1.questions.first == 'hasIdCard', '질문 ${r1.questions.join(',')}');
        final r2 = e.s.pathfinder.computeRoute(ev, {'hasIdCard': true, 'hasMobileId': null, 'hasOtherBankAccount': true});
        _assert(r2.questions.isEmpty, '확인된 경로가 있는데 질문함');
      }));

  _t('순환(계좌↔인증서) 감지 → 상담 전환', () => _with((d) {
        asNewCustomer(d);
        d.finance.otherBankAccounts = [];
      }, (e) async {
        await e.startJoin({'hasIdCard': false, 'hasMobileId': true, 'hasOtherBankAccount': false});
        _assert(e.jf.state == 'ESCALATED', '상태 ${e.jf.state}');
        final esc = e.js.escalation;
        _assert(esc != null && esc.reason == 'CYCLE', '사유 ${esc?.reason}');
        final chain = esc!.cause?.chain ?? const [];
        _assert(chain.contains('hasDepositAccount') && chain.contains('certRegistered'), '순환 구성 $chain');
      }));

  _t('은행이 아는 정보(다른 은행 계좌·휴대폰 명의)는 다시 묻지 않음', () => _with(asNewCustomer, (e) async {
        await e.startJoin({'hasIdCard': false, 'hasMobileId': true});
        final j = e.js;
        _assert(j.constraintSource['hasOtherBankAccount']?.$1 == 'BANK', '다른 은행 계좌 출처');
        _assert(j.skipped.length >= 2, '생략 기록 없음');
        _assert(j.questionsAsked == 2, '질문 수 ${j.questionsAsked}');
      }));

  _t('모달을 닫기만 하면 완료로 판정하지 않음', () => _with(asNewCustomer, (e) async {
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

  _t('AI 가입 지원 주 경로: 신분증 없음 → 모바일 신분증 → 계좌 → 인증서·고객정보 → 승인 → 완료', () => _with(asNewCustomer, (e) async {
        await e.startJoin({'hasIdCard': false, 'hasMobileId': true});
        final order = <String>[];
        for (var i = 0; i < 6 && (e.jf.state == 'OPTIONS_READY' || e.jf.state == 'REMAINING'); i++) {
          final next = e.js.route!.steps.first.actionId;
          order.add(next);
          await e.doTask(next, true);
        }
        _assert(order.isNotEmpty && order.first == 'MOBILE_ID_VERIFY', '첫 업무 ${order.firstOrNull}');
        final acc = order.indexOf('OPEN_ACCOUNT_OTHERBANK');
        _assert(acc != -1 && acc < order.indexOf('ISSUE_CERT'), '계좌보다 인증서가 먼저: ${order.join(',')}');
        _assert(order.length == 4 && order.contains('KYC_UPDATE'), '업무 ${order.join(',')}');
        _assert(e.jf.state == 'READY_TO_APPLY', '준비 상태 ${e.jf.state}');
        _assert(e.s.store.state.applications.isEmpty, '승인 전에 가입 요청됨');
        await e.j.approve(const ApplyTerms(monthly: 300000, months: 24, account: 'WON 통장'));
        _assert(e.jf.state == 'COMPLETED', '결과 ${e.jf.state}');
      }));

  _t('첫 질문의 해외주식 칩은 이전 상담으로 넘기지 않고 목돈 채팅에서 이어 간다', () => _with(null, (e) async {
        final l = e.app.lumpsum;
        _assert(l.startNew(), '목돈 상담 시작');
        final chip = ls.introChoices().where((c) => c.text.contains('해외주식')).firstOrNull;
        _assert(chip != null, '해외주식 칩이 없음');
        await l.accept(chip!.text, chip.id);
        final s = e.app.session.lumpsum;
        _assert(s != null && s.intent == 'OVERSEAS', '목돈 채팅이 끊김 / intent ${s?.intent}');
        _assert(e.lf.state == 'NO_ACCOUNT', '상태 ${e.lf.state}');
        _assert(s!.goal == null && s.goalKind == 'OVERSEAS_ACCOUNT', '목표 없이 해외 계좌로 감 / goalKind ${s.goalKind}');
        final first = s.chat.where((m) => m.role == 'ai' && m.text.contains('해외주식 투자를 처음')).firstOrNull;
        _assert(first != null, '해외주식 첫 답이 없음');
        final all = _allText(s);
        _assert(!RegExp(r'목돈|목표가 얼마|월 약|매달 남는').hasMatch(all), '목돈 흐름 문구가 섞임: $all');
        final ids = s.prompt.choices.map((c) => c.id).join('|');
        _assert(ids == 'open-yes|open-no', '개설 선택지 $ids');
        _assertClean(all);
        final panel = gi.describe(lumpsum: s, lumpsumState: e.lf.state);
        final panelLabels = panel.rows.map((r) => r.label).join('|');
        _assert(panelLabels == '목표|해외 계좌', '해외 첫 시작 패널 줄 $panelLabels');
      }));

  _t('통합 시나리오 상담: 목돈 불리기 7턴 → 해외주식 개설 신청', () => _with(null, (e) async {
        e.setMoney(3500000, 2100000);
        final s = await e.lumpUntilGoal('goal-100');
        _assert(s.advice?.decisionId == 'MIX', '판단 ${s.advice?.decisionId}');
        _assert(s.advice!.surplus == 1400000, '월 여유 ${s.advice!.surplus}');
        _assert(e.lf.state == 'DEBT_CHECK', '상태 ${e.lf.state}');
        final want = _values(s.advice!.figures.decision);
        _assert(_figsRows(s).any((card) => _values(card) == want), '판단 카드 숫자');
        _assert(s.prompt.choices.isNotEmpty, '추천 질문이 없음');
        final l = e.app.lumpsum;
        await l.accept(ls.situationText());
        await l.accept(la.experienceTexts['exp-1']!, 'exp-1');
        await l.accept(la.lossTexts['loss-1']!, 'loss-1');
        await e.keepShare();
        _assert(s.advice!.profile.id == 'NEUTRAL' && !s.advice!.leverage, '성향 ${s.advice!.profile.id} / 레버리지 ${s.advice!.leverage}');
        _assert(!s.prompt.choices.any((c) => c.id == 'prod-lev'), '기본 경로에 레버리지');
        final reco = s.chat.where((m) => m.role == 'ai' && m.text.contains('성향은')).lastOrNull;
        final recoFigs = reco?.blocks.where((b) => b.t == 'figures').firstOrNull;
        _assert(recoFigs != null && _values(recoFigs.figures) == _values(s.advice!.figures.recommend), '추천 카드 숫자');
        _assert(!reco!.text.contains('매달 투자 참고 금액'), '추천 문장에 금액 문장이 남음');
        // 부족 안내에서 "그래도 이 비중으로"를 골랐으면 받아 주는 문장이 맨 앞에 붙는다
        _assert(_kindsOf(reco) == 'text,text,figures,text' && reco.blocks[0].text == ls.keepAck(), '추천 블록 순서 ${_kindsOf(reco)}');
        await l.accept('해외주식', 'prod-os');
        await l.accept('네, 개설해 주세요', 'open-yes');
        _assert(e.lf.state == 'TO_JOIN', '상태 ${e.lf.state}');
        _assert(e.jf.state == 'CONSENT', '가입 ${e.jf.state}');
        final ctx = e.app.session.customerContext;
        _assert(ctx?.decisionId == 'MIX', '판단 전달 ${ctx?.decisionId}');
        _assert(ctx!.financialSummary?.monthly == s.advice!.monthlyInvest, '월 투자금 ${ctx.financialSummary?.monthly}');
        _assert(ctx.goal == la.lumpGoals['goal-100']!.text, '목표 전달');
        for (final m in s.chat) {
          _assertClean(m.text);
        }
      }));

  _t('적금+투자 판단: 소비를 줄이면 필요한 연 수익이 내려가고, 여유가 없으면 나오지 않음', () async {
    final exp1 = la.experienceTexts['exp-1']!, loss1 = la.lossTexts['loss-1']!;
    la.LumpAdvice mk({int income = 3500000, int expense = 2100000, int goalAmount = 80000000, int goalMonths = 36}) =>
        _advise(income: income, expense: expense, goalAmount: goalAmount, goalMonths: goalMonths, expText: exp1, lossText: loss1);
    final a = mk();
    final cut = la.cutForYield(a);
    _assert(a.decisionId == 'MIX' && cut != null && cut.plan.total > 0, '줄이기 계산 ${a.decisionId}');
    _assert((cut!.yieldBefore - a.yieldRate).abs() < 1e-9 && cut.yieldAfter < cut.yieldBefore, '연 수익 ${cut.yieldBefore} → ${cut.yieldAfter}');
    _assert(cut.plan.total <= cut.extra, '줄이는 금액이 필요한 만큼을 넘음 ${cut.plan.total} / ${cut.extra}');
    final blocks = ls.decisionMessage(a).blocks;
    final text = blocks.where((b) => b.t == 'text').map((b) => b.text).join('\n');
    final drop = blocks.where((b) => b.t == 'details').toList();
    _assert(blocks[0].text == '목표까지 월 ${la.about(a.requiredMonthly)}을 모아야 하는데, 적금만으로는 부족해요.', '결론 한 줄 ${blocks[0].text}');
    _assert(text.contains('소비를 **매달 ${formatMan(cut.plan.total)}** 줄이면 필요한 연 수익이 ${_jsNum(la.jsRound(cut.yieldBefore * 1000) / 10)}%에서'), '줄이기 한 줄 $text');
    _assert(
      drop.length == 1 &&
          drop[0].label == '지출 줄이기 제안' &&
          drop[0].cuts?.length == cut.plan.items.length &&
          drop[0].cuts!.every((c) => c.label.isNotEmpty && c.saved > 0 && c.reason.isNotEmpty),
      '지출 줄이기 제안 드롭다운',
    );
    // 문장 4개: 결론 / 소비를 줄이면 / 투자로도 어렵다 / 질문
    _assert(
      !blocks.any((b) => b.t == 'figures' && b.figures.any((f) => f.label.contains('줄인 뒤'))) && blocks.where((b) => b.t == 'text').length == 4,
      '항목 문단과 전후 카드는 드롭다운 안으로',
    );
    final hopeTexts = blocks.where((b) => b.t == 'text').map((b) => b.text).toList();
    _assert(RegExp(r'여유 돈을 전부 투자해도\(연 6% 가정\)').hasMatch(hopeTexts[2]) && RegExp(r'쉽지 않아요|현실적으로 어려워요').hasMatch(hopeTexts[2]), '투자로도 어렵다는 문구 ${hopeTexts[2]}');
    _assert(hopeTexts[3] == '**목표를 조정할까요, 아니면 그래도 투자도 알아볼까요?**', '조정할지 그래도 투자할지 묻는 질문 ${hopeTexts[3]}');
    final inf = la.infeasible(a);
    _assert(inf != null && inf.unrealistic == (inf.yieldRate >= 0.12), '비현실 판정');
    final wild = mk(goalAmount: 100000000, goalMonths: 24);
    _assert(
      la.infeasible(wild) != null && la.infeasible(wild)!.unrealistic && ls.decisionMessage(wild).blocks.map((b) => b.text).join('\n').contains('현실적으로 어려워요'),
      '크게 모자라면 현실적으로 어렵다고 말함',
    );
    _assertClean(text + drop[0].cuts!.map((c) => c.label + c.reason).join(''));
    final link = blocks.where((b) => b.t == 'link').toList();
    _assert(link.length == 1 && link[0].action == 'spend-open' && link[0].label.contains('소비 분석'), '소비 분석 버튼 없음');
    _assert(!ls.bothMessage(a, false).blocks.map((b) => b.text).join('').contains('개별 이름은 말하지 않고'), '두 계좌 답변에 군더더기 문장');
    final rich = mk(income: 5000000, expense: 2000000, goalAmount: 30000000);
    _assert(rich.decisionId != 'MIX' && la.cutForYield(rich) == null, '적금만으로 충분하면 줄이기 없음 ${rich.decisionId}');
    final tight = mk(expense: 3600000);
    _assert(tight.decisionId == 'SPEND_CHECK' && la.cutForYield(tight) == null, '여유 없음은 기존 줄이기 계획 경로');
    _assert(!ls.decisionMessage(tight).blocks.any((b) => b.t == 'text' && b.text.contains('줄인 뒤 필요한 연 수익')), '여유 없음에 MIX 블록이 섞임');
  });

  _t('판단 카드 금액은 만원 단위, 홈 쿠키의 물어보기는 진행 중이어도 새 채팅', () => _with(null, (e) async {
        final exp1 = la.experienceTexts['exp-1']!, loss1 = la.lossTexts['loss-1']!;
        la.LumpAdvice mk({int income = 3500000, int debt = 0, int deposit = la.depositDefault, int goalAmount = 80000000}) =>
            _advise(income: income, debt: debt, deposit: deposit, goalAmount: goalAmount, expText: exp1, lossText: loss1);
        final unit = RegExp(r'(만|억)원$|개월$');
        for (final a in [mk(), mk(debt: 30000000), mk(goalAmount: 30000000, income: 5000000), mk(deposit: 3000000)]) {
          final all = [...a.figures.income, ...a.figures.balance, ...a.figures.decision, ...a.figures.recommend];
          final bad = all.where((f) => !unit.hasMatch(f.value.replaceFirst(RegExp(r'^월 '), ''))).toList();
          _assert(bad.isEmpty, '${a.decisionId} 카드에 원 단위: ${bad.map((f) => '${f.label}=${f.value}').join(', ')}');
          final noAbout = all.where((f) => f.label != '목표' && RegExp(r'(만|억)원$').hasMatch(f.value) && !RegExp(r'^(월 )?약 ').hasMatch(f.value)).toList();
          _assert(noAbout.isEmpty, '${a.decisionId} 카드에 "약" 없음: ${noAbout.map((f) => '${f.label}=${f.value}').join(', ')}');
        }
        final mix = mk();
        _assert(mix.figures.decision[0].value == '약 6,216만원' && mix.figures.decision[1].value == '약 1,784만원', '적금으로 모이는 돈·부족한 돈 ${_values(mix.figures.decision)}');

        e.setMoney(3500000, 2100000);
        final s = await e.lumpUntilGoal('goal-100');
        final l = e.app.lumpsum;
        _assert(e.lf.state == 'DEBT_CHECK' && s.chat.length > 3, '진행 중 상담');
        _assert(l.startFresh() == true, '새 채팅 열기');
        final n = e.app.session.lumpsum!;
        _assert(e.lf.state == 'INTRO' && !identical(n, s) && n.chat.length == 1 && n.chat[0].role == 'ai' && n.goalKind.isEmpty, '새 채팅 상태 ${e.lf.state} / 채팅 ${n.chat.length}');
        _assert(l.startFresh() == true && e.app.session.lumpsum!.chat.length == 1, '새 채팅 위에서 다시 눌러도 새 채팅');

        // 쿠키의 문장은 새 채팅에서 입력되어 전송까지 된다
        const line = '비상자금이 충분한지 알고 싶어요.';
        _assert(l.startFresh(line) == true, '쿠키 새 채팅');
        await Future<void>.delayed(const Duration(milliseconds: 120));
        final sent = e.app.session.lumpsum!.chat.where((m) => m.role == 'user').toList();
        _assert(sent.length == 1 && sent[0].text == line, '쿠키 문장 전송 ${sent.map((m) => m.text).toList()}');
        _assert(e.lf.state != 'INTRO', '전송 뒤 다음 단계로 진행 ${e.lf.state}');
      }));

  _t('판단 뒤에는 질문이 나오고, 아니요는 투자 없이 마치며, 질문 없는 선택지는 없음', () => _with(null, (e) async {
        e.setMoney(3500000, 2100000);
        final s = await e.lumpUntilGoal('goal-100');
        _assert(e.lf.state == 'DEBT_CHECK', '판단 뒤 단계 ${e.lf.state}');
        // 기본 인물의 1억 3년은 투자로도 어렵다: 성향을 묻기 전에 먼저 알리고, 목표 조정과 "그래도 투자"를 함께 묻는다
        _assert(_rowJson(s.chat.last).contains('목표를 조정할까요, 아니면 그래도 투자도 알아볼까요?'), '판단 뒤 질문 없음');
        final choices = s.prompt.choices.map((c) => '${c.id}:${c.text}').join('|');
        _assert(choices == 'sf-amount:목표를 5천만 원·5년으로 낮출게요|sf-period:기간을 5년으로 늘릴게요|inv-yes:그래도 투자도 알아볼게요|inv-no:아니요, 여기서 마칠게요', '선택지 $choices');
        await e.app.lumpsum.accept('아니요, 여기서 마칠게요', 'inv-no');
        _assert(e.lf.state == 'CLOSED' && s.investFocus != true, '아니요 → 종료 ${e.lf.state}');
        final end = _aiLast(s);
        _assert(end.contains('투자는 빼고') && end.contains('목표나 기간을 조정') && !end.contains('위 금액'), '종료 안내');

        // 판단마다 질문과 마무리 문장이 맞는다: 적금으로 충분하면 주식을 하고 싶을 때만 이어 간다
        la.LumpAdvice mk({int income = 3500000, int expense = 2100000, int debt = 0, int deposit = la.depositDefault, int goalAmount = 20000000, int goalMonths = 12}) =>
            _advise(income: income, expense: expense, debt: debt, deposit: deposit, goalAmount: goalAmount, goalMonths: goalMonths);
        final enough = mk(goalAmount: 20000000, goalMonths: 12, income: 8000000, expense: 2000000);
        _assert(enough.decisionId == 'SAVINGS_ENOUGH', '적금 충분 ${enough.decisionId}');
        _assert(
          ls.investQuestion(enough) == '**혹시 주식 투자도 해 보고 싶으세요?**' && ls.investChoices(enough, null).map((c) => c.text).join('|') == '네, 투자도 해보고 싶어요|아니요, 적금으로 갈게요',
          '적금 충분 질문',
        );
        _assert(ls.stopMessage(enough).text.contains('주식은 빼고 적금으로 가요') && !ls.stopMessage(enough).text.contains('위 금액'), '적금 충분 마무리');
        final debt = mk(debt: 30000000, goalAmount: 100000000, goalMonths: 36);
        _assert(debt.decisionId == 'DEBT_FIRST' && ls.investQuestion(debt) == '**그래도 투자도 알아볼까요?**' && ls.stopMessage(debt).text.contains('대출 상환을 먼저'), '상환 우선 질문·마무리');
        _assert(ls.decisionSentence(debt).contains('목표는 상환을 이어 가면서'), '상환 우선 판단에 목표 언급');
        final emg = mk(deposit: 1000000, goalAmount: 100000000, goalMonths: 36);
        final emgText = ls.decisionSentence(emg);
        _assert(
          emg.decisionId == 'EMERGENCY_FIRST' && RegExp(r'매달 약 \d+만원씩 예금에 모으면 \d+개월이면 채워져요').hasMatch(emgText) && emgText.contains('그다음에 보는 게 안전'),
          '비상자금 우선: 채우는 방법과 목표 언급 $emgText',
        );
        _assert(ls.stopMessage(emg).text.contains('비상자금부터 채워') && ls.investChoices(emg, null)[1].text == '아니요, 비상자금부터 채울게요', '비상자금 우선 마무리');
      }));

  // '제자리 갱신 (morphInner)'는 브라우저 DOM 갱신 테스트라 Flutter에는 대응 기능이 없어 옮기지 않는다

  _t('목표에 못 미치면 부족분과 필요한 투자 비중을 알리고, 닿으면 안내하지 않음', () async {
    la.LumpAdvice mk({int goalAmount = 80000000, int goalMonths = 36, double? boldShare}) => _advise(
          income: 3200000,
          expense: 2000000,
          goalAmount: goalAmount,
          goalMonths: goalMonths,
          expText: la.experienceTexts['exp-0']!,
          lossText: la.lossTexts['loss-0']!,
          investFocus: true,
          boldShare: boldShare,
        );
    final a = mk();
    final info = la.shortfall(a);
    _assert(a.decisionId == 'MIX' && info != null && info.shortfall > 0, '부족 판정 ${a.decisionId} ${info?.toJson()}');
    final needed = info!.neededShare;
    _assert(needed == null || (needed > a.investShare && needed <= 1), '필요한 비중 $needed');
    if (needed != null) {
      _assert(la.plannedFuture(a, needed) >= a.goalAmount && la.plannedFuture(a, needed - 0.05) < a.goalAmount, '필요한 비중은 최소값');
    }
    _assert(la.shortfall(mk(goalAmount: 50000000, goalMonths: 60)) == null, '5천 5년은 적금으로 닿음');
    final bold = mk(boldShare: needed ?? 1);
    _assert(bold.boldApplied && bold.investShare == (needed ?? 1) && bold.monthlyInvest > a.monthlyInvest, '과감한 비중 적용 ${bold.monthlyInvest}');
  });

  _t('손실 답 뒤 부족 단계: 안내와 선택지, 과감한 투자는 비중을 올리고 목표 조정은 다시 계산', () async {
    Future<void> toShortfall(_Env e) async {
      e.setMoney(3200000, 2000000);
      final l = e.app.lumpsum;
      _assert(l.startNew(), '부족 흐름 시작');
      await l.accept(ls.opening);
      await l.accept(la.goalTyped.text);
      await l.accept(ls.situationText());
      await l.accept(la.experienceTexts['exp-0']!, 'exp-0');
      await l.accept(la.lossTexts['loss-0']!, 'loss-0');
    }

    await _with(null, (e) async {
      await toShortfall(e);
      final l = e.app.lumpsum;
      final s = e.app.session.lumpsum!;
      final info = la.shortfall(s.advice);
      _assert(info != null && e.lf.state == 'SHORTFALL', '부족 단계 ${e.lf.state}');
      final last = _rowJson(s.chat.last);
      _assert(RegExp(r'목표에는? .*못 미쳐요').hasMatch(last) && last.contains('연 6%로 가정'), '부족 안내 문장');
      // 이미 "투자로도 어렵다"고 알렸으므로 같은 말을 되풀이하지 않고 그걸 이어받는다
      if (info!.neededShare == null) _assert(last.contains('앞서 말씀드린 대로') && !last.contains('여유 돈을 전부 투자해도'), '부족 안내가 앞 안내를 되풀이함');
      final ids = s.prompt.choices.map((c) => c.id).toList();
      _assert(ids.contains('sf-keep') && ids.contains('sf-period') && ids.contains('sf-bold') == (info.neededShare != null), '선택지 ${ids.join(',')}');
      if (info.neededShare != null) {
        final bold = s.prompt.choices.firstWhere((c) => c.id == 'sf-bold');
        await l.accept(bold.text, 'sf-bold');
        _assert(e.lf.state == 'RECOMMEND' && s.boldShare == info.neededShare && s.advice!.investShare == info.neededShare, '과감한 투자 ${s.advice!.investShare}');
      }
    });
    await _with(null, (e) async {
      await toShortfall(e);
      final l = e.app.lumpsum;
      final adj = e.app.session.lumpsum!.prompt.choices.firstWhere((c) => c.id == 'sf-period');
      await l.accept(adj.text, 'sf-period');
      final t = e.app.session.lumpsum!;
      // 목표를 바꾸면 바뀐 목표로 판단을 다시 내고(DEBT_CHECK), 이미 답한 성향은 다시 묻지 않는다
      _assert(t.goal?.months == 60 && e.lf.state == 'DEBT_CHECK', '기간 조정 ${e.lf.state} ${t.goal?.months}');
      final again = t.chat.last;
      _assert(RegExp(r'목표를 \*\*5년 안에 8,000만원\*\*으로 바꿔서 다시 계산했어요').hasMatch(again.blocks[0].text), '바꾼 목표 안내 ${again.blocks[0].text}');
      _assert(t.advice?.decisionId == 'SAVINGS_ENOUGH' && _rowJson(again).contains('혹시 주식 투자도 해 보고 싶으세요'), '적금으로 충분하면 주식은 원할 때만 ${t.advice?.decisionId}');
      _assert(!_rowJson(again).contains('투자 비중도 같이 볼까요'), '이미 닿는 목표에 투자 비중을 다시 권함');
      await l.accept('네, 투자도 해보고 싶어요', 'inv-yes');
      _assert(e.lf.state == 'RECOMMEND', '성향을 다시 묻지 않고 추천으로 ${e.lf.state}');
      final rec = t.chat.last;
      _assert(rec.text.contains('목표는 적금으로 채워지니') && !_allText(t).contains('투자에 더 집중하고 싶다고 하셔서'), '적금 충분 추천 문장 ${rec.text}');
    });
  });

  _t('투자 질문의 "예"는 투자에 더 집중한다는 말이 아니고, 직접 쓴 말만 비중을 높인다', () async {
    Future<(LumpsumSession, String)> run(_Env e, bool typed) async {
      final l = e.app.lumpsum;
      e.setMoney(3500000, 2100000);
      _assert(l.startNew(), '시작');
      await l.accept(ls.opening);
      await l.accept(la.lumpGoals['goal-100']!.text, 'goal-100');
      if (typed) {
        await l.accept(ls.situationText());
      } else {
        await l.accept('그래도 투자도 알아볼게요', 'inv-yes');
      }
      await l.accept(la.experienceTexts['exp-1']!, 'exp-1');
      await l.accept(la.lossTexts['loss-1']!, 'loss-1');
      await e.keepShare();
      final s = e.app.session.lumpsum!;
      return (s, _allText(s));
    }

    await _with(null, (e) async {
      final (s, all) = await run(e, false);
      _assert(s.investFocus == false && !all.contains('투자에 더 집중') && RegExp(r'투자도 같이 볼게요|그래도 투자로 얼마나 가까워지는지').hasMatch(all), '선택지 예에서 집중이라고 함 $all');
      _assert(!s.advice!.focusApplied && s.advice!.investShare == 0.45, '비중 가산 없음 ${s.advice!.investShare}');
    });
    await _with(null, (e) async {
      final (s, all) = await run(e, true);
      _assert(s.investFocus == true && all.contains('투자에 더 집중') && s.advice!.focusApplied, '직접 쓴 말은 집중 $all');
    });
  });

  _t('투자 성향 읽기 문장은 두 답변을 각각 읽고 서로 어긋나지 않는다', () async {
    String mk(String ex, String lo) {
      final et = la.experienceTexts[ex]!, lt = la.lossTexts[lo]!;
      final a = _advise(goalAmount: 20000000, goalMonths: 12, expText: et, lossText: lt);
      return ls.recommendMessage(a, et, lt, 1).blocks[0].text;
    }

    final m20 = mk('exp-2', 'loss-0');
    _assert(!m20.contains('경험이 적') && m20.contains('경험은 꽤 있는 편') && m20.contains('안정으로'), '자주 하는데 경험이 적다고 함 $m20');
    final m21 = mk('exp-2', 'loss-1');
    _assert(!m21.contains('경험은 적지만') && m21.contains('경험은 꽤 있는 편'), '자주 하는데 경험은 적지만 $m21');
    final m02 = mk('exp-0', 'loss-2');
    _assert(m02.contains('아직 없는 편') && m02.contains('더 살 수 있는 쪽'), '경험 없음 + 더 산다');
    final pt = ls.typed['PROFILING']!, lt = ls.typed['LOSS']!;
    final a = _advise(goalAmount: 20000000, goalMonths: 12, expText: pt, lossText: lt);
    final typed = ls.recommendMessage(a, pt, lt, 1).blocks[0].text;
    _assert(typed.contains('연금이나 펀드를 조금') && typed.contains('반등하면 정리하는 쪽') && !typed.contains('장기로 볼 수 있는'), '직접 쓴 답변 읽기 $typed');
  });

  _t('추천 카드는 투자 금액과 근거만, 국내·해외 비중은 시장을 고른 뒤', () async {
    final exp = la.experienceTexts['exp-1']!;
    final loss = la.lossTexts['loss-1']!;
    final a = _advise(debt: 30000000, goalAmount: 80000000, goalMonths: 36, expText: exp, lossText: loss, investFocus: true);
    _assert(a.decisionId == 'DEBT_FIRST' && a.focusApplied, '판단 ${a.decisionId} / 집중 ${a.focusApplied}');
    _assert((a.investShare - 0.6).abs() < 1e-9, '비중 ${a.investShare}');
    _assert(a.monthlyInvest == la.jsRound(a.investBase * a.investShare / 10000) * 10000, '금액 ${a.monthlyInvest}');
    final msg = ls.recommendMessage(a, exp, loss, 1);
    final figs = msg.blocks.where((b) => b.t == 'figures').toList();
    _assert(figs.length == 1 && figs[0].figures.length == 1 && figs[0].figures[0].label == '매달 투자할 돈', '추천 카드 ${figs.length}');
    _assert(RegExp(r'갚고 남는 돈 .*의 60%').hasMatch(figs[0].figures[0].note), '근거 문구 ${figs[0].figures[0].note}');
    final all = jsonEncode(msg.blocks.map((b) => b.toJson()).toList()) + msg.text;
    _assert(!RegExp(r'국내 비중|해외 비중').hasMatch(all), '추천 카드에 비중이 보임');
    final side = ls.sideStop(a).text;
    // 100%가 무엇의 100%인지 풀어 쓴다: 매달 투자할 돈 전부를 그 시장에 넣는다
    _assert(RegExp(r'매달 투자할 .+ 전부를 국내주식에 넣는 거예요\(국내 100%\)').hasMatch(side) && side.contains(la.about(a.monthlyInvest)), '국내만 보면 국내 100% $side');
    final no = ls.noAccount(a, false, false).text;
    _assert(
      RegExp(r'매달 투자할 .+ 전부를 해외주식에 넣는 거예요\(해외 100%\)').hasMatch(no) &&
          no.contains(la.about(a.monthlyInvest)) &&
          no.contains('외화 계좌가 필요한데 아직 없네요') &&
          no.contains('개설 도와드릴까요'),
      '해외만 보면 해외 100% $no',
    );
    final noFx = ls.noAccount(a, false, true).text;
    _assert(noFx.contains('외화 계좌는 이미 있어요') && !noFx.contains('아직 없네요') && noFx.contains('개설을 도와드릴까요'), '외화 계좌가 있으면 있다고 말함 $noFx');
    final both = ls.bothMessage(a, false).blocks.map((b) => b.text).join(' ');
    _assert(
      both.contains('국내주식에 ${a.domesticShare}%(${la.about(a.domesticAmount)})') && both.contains('해외주식에 ${a.overseasShare}%(${la.about(a.overseasAmount)})') && both.contains('개설 도와드릴까요'),
      '두 시장은 추천 비중 $both',
    );
    _assert((a.domesticAmount + a.overseasAmount - a.monthlyInvest).abs() <= 10000, '비중 금액 합계');
    _assertClean(msg.blocks.where((b) => b.t == 'text').map((b) => b.text).join('\n') + side + no);
  });

  _t('목돈 판단 분기, 성향, 스냅샷, 금지 문구', () async {
    _assert(la.inferRiskProfile(la.experienceTexts['exp-0'], la.lossTexts['loss-0']).id == 'STABLE', '안정');
    _assert(la.inferRiskProfile(la.experienceTexts['exp-1'], la.lossTexts['loss-1']).id == 'NEUTRAL', '중립');
    _assert(la.inferRiskProfile(la.experienceTexts['exp-2'], la.lossTexts['loss-2']).id == 'ACTIVE', '적극');
    ls.allFixedLines().forEach(_assertClean);

    await _with(null, (e) async {
      e.setMoney(3500000, 3600000);
      final s = await e.lumpUntilGoal('goal-100');
      _assert(s.advice?.decisionId == 'SPEND_CHECK', '여유 없음 ${s.advice?.decisionId}');
      _assert(e.lf.state == 'SPEND_PLAN', '계획 상태 ${e.lf.state}');
      _assert(s.prompt.choices.map((c) => c.id).join('|') == 'spend-view|spend-save', '여유 없음인데 추천 질문');
      _assertClean(_allText(s));
    });

    await _with(null, (e) async {
      e.setMoney(3500000, 2100000, 30000000);
      final s = await e.lumpUntilGoal('goal-100');
      _assert(s.advice?.decisionId == 'DEBT_FIRST', '부채 ${s.advice?.decisionId}');
      _assert(s.advice!.debtPayment == la.debtPayment(30000000), '상환액');
      _assertClean(_allText(s));
    });

    await _with(null, (e) async {
      e.setMoney(3500000, 3000000);
      final s = await e.lumpUntilGoal('goal-100');
      _assert(s.advice?.decisionId == 'EMERGENCY_FIRST', '비상자금 ${s.advice?.decisionId} ${s.advice?.emergencyMonths}');
    });

    await _with(null, (e) async {
      e.setMoney(3500000, 2100000);
      var s = await e.lumpUntilGoal('goal-20');
      _assert(s.advice?.decisionId == 'SAVINGS_ENOUGH' && s.advice!.goalAmount == 20000000, '적금 달성 ${s.advice?.decisionId}');
      e.lf.transition('EXIT');
      e.lf.transition('NEW_CASE');
      s = await e.lumpUntilGoal('goal-50');
      _assert(s.advice?.goalAmount == 50000000 && s.advice!.goalMonths == 60, '5천만 목표');
    });

    await _with(null, (e) async {
      e.setMoney(3500000, 2100000);
      var s = await e.lumpUntilGoal('goal-100');
      final frozen = s.snap.expense;
      final frozenId = s.advice?.decisionId;
      e.setMoney(3500000, 3600000);
      _assert(s.snap.expense == frozen && s.advice?.decisionId == frozenId, '진행 중 스냅샷이 바뀜');
      await e.app.lumpsum.accept('그래도 투자도 알아볼게요', 'inv-yes');
      _assert(s.advice?.decisionId == 'MIX' && s.investFocus == false, '투자 질문 답이 판단을 바꿈');
      e.lf.transition('EXIT');
      e.lf.transition('NEW_CASE');
      s = await e.lumpUntilGoal('goal-100');
      _assert(s.advice?.decisionId == 'SPEND_CHECK', '새 채팅 반영 ${s.advice?.decisionId}');
    });

    await _with(null, (e) async {
      final l = e.app.lumpsum;
      e.setMoney(3500000, 2600000);
      _assert(l.startNew(), '레버리지 상담');
      await l.accept(ls.opening);
      await l.accept(la.lumpGoals['goal-100']!.text, 'goal-100');
      await l.accept(ls.situationText());
      await l.accept(la.experienceTexts['exp-2']!, 'exp-2');
      await l.accept(la.lossTexts['loss-2']!, 'loss-2');
      await e.keepShare();
      final s = e.app.session.lumpsum!;
      _assert(s.advice?.decisionId == 'MIX' && s.advice!.profile.id == 'ACTIVE' && s.advice!.leverage, '레버리지 조건 ${s.advice?.decisionId} ${s.advice?.yieldRate}');
      _assert(s.prompt.choices.any((c) => c.id == 'prod-lev'), '레버리지 선택지');
      _assert(_allText(s).contains('넣은 돈보다 더 잃을 수 있어요'), '손실 경고');
      // 레버리지를 고르면 같은 경고를 되풀이하지 않고, 이번 상담에서 이어 가지 않는다고 말한 뒤 국내·해외를 다시 묻는다
      await l.accept('레버리지 상품', 'prod-lev');
      final ids = s.prompt.choices.map((c) => c.id).join('|');
      _assert(e.lf.state == 'RECOMMEND' && ids == 'prod-dom|prod-os', '레버리지 뒤 다시 국내·해외 ${e.lf.state} $ids');
      _assert(_aiLast(s).contains('국내주식과 해외주식 중 어느 쪽으로 볼까요'), '다시 묻는 문장');
      _assert(_allText(s).split('넣은 돈보다 더 잃을 수 있어요').length == 2, '경고가 한 번만 나옴');
      await l.accept('국내주식', 'prod-dom');
      _assert(e.lf.state == 'CLOSED' && e.jf.state == 'IDLE', '국내주식은 가입으로 가지 않음');
    });

    final cats = _advise(goalAmount: 100000000, goalMonths: 36).categories;
    final sum = cats.fold<int>(0, (n, c) => n + c.amount);
    _assert(sum == 2100000, '막대 합 $sum');
  });

  _t('목돈 첫 질문: 인사와 선택지 3개, 해외주식 외 선택지는 이전 상담으로 이어짐', () => _with(null, (e) async {
        e.setMoney(3500000, 2100000);
        _assert(e.app.lumpsum.startNew(), '상담 시작');
        final s = e.app.session.lumpsum!;
        _assert(s.chat.length == 1 && s.chat[0].role == 'ai' && s.chat[0].text.contains('어떤 목표로 상담받고 싶으세요'), '첫 AI 질문 ${s.chat.firstOrNull?.text}');
        _assert(s.chat[0].thoughtMs == 0, '첫 질문에 생각 연출');
        _assert(s.prompt.choices.map((c) => c.text).join('|') == ls.assetGoalChips.join('|'), '선택지가 이전 3개가 아님');
        _assert(s.prompt.choices.length == 3 && s.prompt.typeText == ls.opening, '빈 곳 타이핑 문장');
        _assert(!s.prompt.choices.any((c) => c.text.contains('목돈')), '목돈 선택지가 있음');
        // 어떤 칩도 이전 룰베이스 상담(assetFlow)으로 넘기지 않는다. 세 칩은 각각 아래 별도 테스트에서 이 채팅 안에서 이어 간다
        _assert(e.app.session.asset == null, '이전 상담이 열려 있음');
      }));

  _t('첫 질문의 결혼 자금 칩은 목표를 다시 묻지 않고 목돈 채팅에서 바로 판단한다', () async {
    await _with(null, (e) async {
      e.setMoney(3500000, 2100000);
      final l = e.app.lumpsum;
      _assert(l.startNew(), '목돈 상담 시작');
      final chip = ls.introChoices().where((c) => c.text.contains('결혼')).firstOrNull;
      _assert(chip != null, '결혼 자금 칩이 없음');
      await l.accept(chip!.text, chip.id);
      final s = e.app.session.lumpsum;
      _assert(s != null && e.app.session.asset == null, '이전 상담으로 넘어감');
      _assert(s!.goal != null && s.goal!.amount == 30000000 && s.goal!.months == 36, '목표 ${s.goal?.toJson()}');
      _assert(e.lf.state == 'DEBT_CHECK', '상태 ${e.lf.state}');
      final all = _allText(s);
      _assert(!all.contains('목돈 목표가 얼마인가요'), '목표를 다시 물음');
      _assert(all.contains('바로 계산해 볼게요') && all.contains('주식 투자도 해 보고 싶으세요'), '분석 뒤 바로 판단 $all');
      _assert(all.contains('결혼 자금을 준비하시는군요'), '결혼을 받아 주지 않음 $all');
      final info = gi.describe(lumpsum: s, lumpsumState: e.lf.state);
      _assert(info.rows[0].value == '결혼 자금 마련', '목표 이름 ${info.rows[0].value}');
      _assertClean(all);
    });
    // 금액만 말하면 기간을 3년으로 가정하고, 가정했다고 말한다
    await _with(null, (e) async {
      e.setMoney(3500000, 2100000);
      e.app.lumpsum.startNew();
      await e.app.lumpsum.accept('결혼 자금 3천만원을 모으는 데 얼마나 부족한가요?');
      final s2 = e.app.session.lumpsum!;
      _assert(s2.goal != null && s2.goal!.amount == 30000000 && s2.goal!.months == 36 && s2.goal!.assumed, '금액만 말한 목표 ${s2.goal?.toJson()}');
      _assert(_allText(s2).contains('기간은 3년으로 보고'), '가정했다는 말이 없음');
    });
  });

  _t('첫 질문의 비상자금 칩은 점검 결과를 말하고 목돈 마련도 볼지 묻는다', () async {
    ls.LChoice chipOf() => ls.introChoices().firstWhere((c) => c.text.contains('비상자금'));
    await _with(null, (e) async {
      e.setMoney(3500000, 2100000);
      final l = e.app.lumpsum;
      _assert(l.startNew(), '목돈 상담 시작');
      await l.accept(chipOf().text, chipOf().id);
      final s = e.app.session.lumpsum;
      _assert(s != null && e.app.session.asset == null, '이전 상담으로 넘어감');
      _assert(e.lf.state == 'GOAL' && s!.intent == 'EMERGENCY', '상태 ${e.lf.state} / ${s?.intent}');
      final ids = s!.prompt.choices.map((c) => c.id).join('|');
      _assert(ids == 'em-yes|em-no', '선택지 $ids');
      final all = _allText(s);
      _assert(all.contains('예금이 생활비 4개월치예요') && all.contains('충분한 편') && all.contains('목돈 마련도 같이 볼까요'), '점검 문장 $all');
      _assert(!all.contains('목돈 목표가 얼마인가요'), '목표를 먼저 물음');
      _assert(gi.describe(lumpsum: s, lumpsumState: 'GOAL').rows.map((r) => r.label).join('|') == '목표|비상자금', '패널 줄');
      _assertClean(all);
      // 예: 목돈 마련도 보면 목표를 묻는 평소 흐름으로 이어진다
      await l.accept(ls.emergencyChoicesHigh[0].text, 'em-yes');
      _assert(e.lf.state == 'GOAL' && s.intent == '' && s.goalKind == 'LUMP_SUM', '예 뒤 상태');
      _assert(s.prompt.choices.any((c) => c.id == 'goal-100'), '목표 선택지가 나오지 않음');
      _assert(_aiLast(s).contains('목돈 목표가 얼마인가요'), '목표 질문');
    });
    // 아니요: 여기서 마친다
    await _with(null, (e) async {
      e.setMoney(3500000, 2100000);
      final l = e.app.lumpsum;
      l.startNew();
      await l.accept(chipOf().text, chipOf().id);
      await l.accept(ls.emergencyChoicesHigh[1].text, 'em-no');
      _assert(e.lf.state == 'CLOSED', '아니요 뒤 상태 ${e.lf.state}');
    });
    // 예금이 모자라면 채우는 기간을 계산해 말한다
    await _with(null, (e) async {
      e.setMoney(3500000, 2100000);
      e.s.store.update((d) => d.finance.items['liquidAssets']!.value = 1000000, '[자가 테스트] 예금 100만원');
      final l = e.app.lumpsum;
      l.startNew();
      await l.accept(chipOf().text, chipOf().id);
      final all = _allText(e.app.session.lumpsum!);
      _assert(all.contains('아직 부족해요') && all.contains('매달 약 98만원씩 예금에 모으면 6개월이면 채워져요'), '부족 점검 $all');
    });
  });

  _t('월 여유 0원 이하: 소비 분석 연동 줄이기 계획 → 칩 → 저장 → 종료', () => _with(null, (e) async {
        e.setMoney(3500000, 3600000);
        final s = await e.lumpUntilGoal('goal-100');
        final plan = la.spendPlan(s.advice!);
        _assert(s.advice!.decisionId == 'SPEND_CHECK' && e.lf.state == 'SPEND_PLAN', '계획 상태 ${e.lf.state}');
        final row = _lastAi(s);
        _assert(_kindsOf(row) == 'text,figures,text,steps,details,tags,text,figures,text', '지출 계획 블록 순서 ${_kindsOf(row)}');
        final figs = row.blocks[1].figures;
        _assert(!RegExp(r'라고 하셨군요|그 문장 기준|맞춰 봤어요').hasMatch(row.text), '되묻기 문장');
        _assert(figs[2].value == '약 10만원 부족', '음수 여유 표기 ${figs[2].value}');
        _assert(row.blocks[2].text.contains('자산·소비에서 분석한 최근 3개월'), '출처 문장');
        _assert(row.blocks[3].items.length == 3, '계획 진행 단계');
        // JS는 블록에 insight 객체를 담고, Dart는 insight 표시만 두고 화면이 같은 categories로 spendInsight를 계산한다
        final cats = row.blocks[4].categories ?? const [];
        final insight = la.spendInsight(cats);
        _assert(cats.length == 6 && row.blocks[4].insight && insight.source == la.insightSource, '소비 막대와 출처');
        _assert(insight.rows.every((r) => r.prev > 0), '지난달 대비');
        _assert(row.blocks[5].tags.length >= 3, '패턴 태그');
        _assert(plan.target == 200000 && plan.total == plan.target, '필요한 만큼만 ${plan.target} ${plan.total}');
        _assert(plan.total == plan.items.fold<int>(0, (n, it) => n + it.saved) && plan.after == s.advice!.surplus + plan.total, '계획 합계');
        _assert(plan.items.every((it) => it.category != '주거·관리' && it.category != '교통' && it.saved % 10000 == 0), '고정비를 줄임');
        _assert(plan.items.any((it) => it.trimmed), '마지막 항목은 필요한 만큼으로 줄임');
        _assert(plan.enough == (plan.after > 0), '충분 여부');
        final body = row.blocks[6].text;
        _assert(RegExp(r'한 달에 .+ 정도').hasMatch(body) && !RegExp(r'^- ', multiLine: true).hasMatch(body) && body.contains('고정비'), '대화체 계획 $body');
        _assert(
          row.blocks[7].figures.map((f) => f.label).join('|') == '줄이기 전 월 여유|줄인 뒤 월 여유' && row.blocks[7].figures[1].value == la.about(plan.after),
          '전후 카드',
        );
        _assert(s.prompt.choices.map((c) => c.id).join('|') == 'spend-view|spend-save', '칩 2개');
        _assert(!row.text.contains('새 상담을 시작하면'), '옛 마무리 문장');

        // 소비 분석 화면(spendView.render) 내용 검사는 위젯이라 옮기지 않고, 화면 이동만으로 저장되지 않는지만 본다
        await e.app.lumpsum.choice('spend-view', ls.spendChoices()[0].text);
        _assert(e.lf.state == 'SPEND_PLAN' && e.app.session.spendGoal == null, '이동만으로 저장되지 않음');
        await e.app.lumpsum.accept(ls.spendChoices()[1].text, 'spend-save');
        final g = e.app.session.spendGoal;
        _assert(e.lf.state == 'CLOSED' && g != null && g.total == plan.total && g.items.length == plan.items.length, '저장 뒤 종료');
        _assert(_aiLast(s).contains('줄이기 목표를 저장했어요'), '저장 응답');
        final all = _allText(s);
        _assertClean(all);
        _assert(!RegExp(r'가상|예시|시연').hasMatch(all), '가상/예시/시연 문구');
      }));

  _t('타이핑 문장은 선택지와 같지 않고, 직접 입력으로도 흐름이 이어짐', () => _with(null, (e) async {
        e.setMoney(3500000, 2100000);
        final l = e.app.lumpsum;
        void dup(String where) {
          final p = e.app.session.lumpsum!.prompt;
          _assert(p.typeText.isNotEmpty && !p.choices.any((c) => c.text == p.typeText), '$where 타이핑 문장이 선택지와 같거나 없음: ${p.typeText}');
        }

        _assert(l.startNew(), '시작');
        dup('첫 질문');
        await l.accept(ls.typed['INTRO']!);
        await l.accept(ls.typed['GOAL']!);
        var s = e.app.session.lumpsum!;
        _assert(s.goal?.amount == la.goalTyped.amount && s.advice?.decisionId == 'MIX', '직접 입력한 목표 ${s.goal?.amount} ${s.advice?.decisionId}');
        dup('상황');
        await l.accept(ls.situationText());
        dup('경험');
        await l.accept(ls.typed['PROFILING']!);
        dup('손실');
        await l.accept(ls.typed['LOSS']!);
        await e.keepShare();
        s = e.app.session.lumpsum!;
        _assert(e.lf.state == 'RECOMMEND' && s.advice?.profile.id == 'NEUTRAL', '직접 입력한 성향 ${s.advice?.profile.id}');
        dup('상품');
        await l.accept(ls.typed['RECOMMEND']!);
        _assert(e.lf.state == 'NO_ACCOUNT' && e.app.session.lumpsum!.goalKind == 'OVERSEAS_ACCOUNT', '직접 입력한 상품 ${e.lf.state}');
        s = e.app.session.lumpsum!;
        final both = s.chat.last;
        _assert(_kindsOf(both) == 'text,text' && both.blocks[0].text.startsWith('국내주식은') && both.blocks[1].text.contains('개설 도와드릴까요'), '두 계좌 응답 ${_kindsOf(both)}');
        final all = _allText(s);
        _assert(!all.contains('대출 권유') && s.investFocus == true && all.contains('투자에 더 집중'), '투자 집중 흐름');
        dup('계좌');
        ls.allFixedLines().forEach(_assertClean);
      }));

  _t('줄이기 계획: 부족분이 크면 후보를 모두 담고 고정비를 안내', () async {
    final a = _advise(expense: 4200000, goalAmount: 100000000, goalMonths: 36);
    final plan = la.spendPlan(a);
    _assert(plan.items.length == 4 && plan.items.every((it) => !it.trimmed), '후보 모두');
    _assert(plan.after <= 0 && !plan.enough, '부족 ${plan.after}');
    final blocks = ls.spendPlanBlocks(a);
    final txt = blocks.where((b) => b.t == 'text').last;
    final planText = blocks[4].text;
    _assert(planText.contains('고정비도 같이 봐야 해요') && txt.text.isNotEmpty, '고정비 안내');
  });

  _t('목돈 응답 블록 순서: 분석, 판단, 추천', () async {
    await _with(null, (e) async {
      e.setMoney(3500000, 2100000);
      final l = e.app.lumpsum;
      _assert(l.startNew(), '시작');
      await l.accept(ls.opening);
      final s = e.app.session.lumpsum!;
      var row = _lastAi(s);
      _assert(_kindsOf(row) == 'text,steps,details,figures,figures,text', '분석 블록 순서 ${_kindsOf(row)}');
      _assert(row.blocks[0].text == '월급과 지출을 분석해볼게요.', '분석 첫 문장');
      _assert(row.blocks[1].items.length == 3, '진행 단계 3개');
      _assert(row.blocks[2].label == '내 소비 자세히 보기' && row.blocks[2].categories?.length == 6 && row.open == false, '소비 드롭다운');
      _assert(
        row.blocks[3].figures.map((f) => f.label + f.value).join('|') == '평균 수입${la.about(3500000)}|평균 지출${la.about(2100000)}',
        '수입·지출 카드',
      );
      _assert(row.blocks[4].figures.map((f) => f.label).join('|') == '월평균 여유 자금|예적금 및 현금', '여유·예적금 카드');
      _assert(row.blocks[4].figures[0].value == la.about(1400000) && row.blocks[4].figures[1].value == la.about(s.snap.deposit), '여유·예적금 숫자');
      final last = row.blocks[5].text;
      _assert(last == '매달 남는 돈은 약 140만원이에요.\n\n**목돈 목표가 얼마인가요?**', '부채 없음 마무리 $last');
      _assert(!RegExp(r'월급과 지출부터|계좌 내역을 읽어').hasMatch(row.text), '무작위 첫 문장');
      await l.accept(la.lumpGoals['goal-100']!.text, 'goal-100');
      row = _lastAi(s);
      // MIX이고 투자로도 어려우면: 결론 / 카드 / 소비를 줄이면 / 제안 드롭다운 / 소비 분석 버튼 / 투자로도 어렵다 / 질문
      final order = s.advice?.decisionId == 'MIX' ? 'text,figures,text,details,link,text,text' : 'text,figures,text';
      _assert(_kindsOf(row) == order, '판단 블록 순서 ${_kindsOf(row)}');
      _assert(!RegExp(r'라고 하셨군요|그 문장 기준|맞춰 봤어요').hasMatch(row.text), '되묻기 문장');
      _assert(_values(row.blocks[1].figures) == _values(s.advice!.figures.decision), '판단 카드 숫자');
      _assert(row.blocks[0].text == ls.decisionSentence(s.advice!), '판단 문장이 카드 앞');
    });
    await _with(null, (e) async {
      e.setMoney(3500000, 2100000, 30000000);
      _assert(e.app.lumpsum.startNew(), '부채 시작');
      await e.app.lumpsum.accept(ls.opening);
      final s = e.app.session.lumpsum!;
      final row = _lastAi(s);
      final pay = la.debtPayment(30000000);
      final want = '매달 남는 돈은 약 140만원이고, 부채 상환(월 ${la.about(pay)})을 빼면 매달 평균 ${la.about(1400000 - pay)} 남아요.';
      _assert(row.blocks[5].text.startsWith(want), '부채 마무리 ${row.blocks[5].text}');
      _assertClean(_allText(s));
    });
  });

  _t('goalInfo: 목표별 알고 있는 정보 줄', () async {
    String labels(gi.GoalInfo d) => d.rows.map((r) => r.label).join('|');
    String? val(gi.GoalInfo d, String l) => d.rows.where((r) => r.label == l).firstOrNull?.value;
    String dump(gi.GoalInfo d) => d.rows.map((r) => '${r.label}=${r.value}${r.note.isEmpty ? '' : '(${r.note})'}').join(', ');
    _assert(labels(gi.describe()) == '목표' && val(gi.describe(), '목표') == '아직 없음', '시작은 목표만');

    await _with(null, (e) async {
      e.setMoney(3500000, 2100000);
      final l = e.app.lumpsum;
      l.startNew();
      String st() => e.lf.state;
      final s = e.app.session.lumpsum!;
      var d = gi.describe(lumpsum: s, lumpsumState: st());
      _assert(labels(d) == '목표', '첫 문장 전');
      await l.accept(ls.opening);
      d = gi.describe(lumpsum: s, lumpsumState: st());
      _assert(labels(d) == '목표|목표 금액·기간|투자 경험|손실 감내|투자 성향' && val(d, '목표') == '목돈 마련', '목돈 마련 줄 ${labels(d)}');
      _assert(val(d, '투자 성향') == '아직 모름', '아직 모름');
      await l.accept(la.lumpGoals['goal-100']!.text, 'goal-100');
      _assert(val(gi.describe(lumpsum: s, lumpsumState: st()), '목표 금액·기간') == '3년 · 1억원', '금액·기간');
      await l.accept(ls.situationText());
      _assert(!labels(gi.describe(lumpsum: s, lumpsumState: st())).contains('부채'), '알고 있는 정보에 부채 줄이 없어야 함');
      await l.accept(la.experienceTexts['exp-1']!, 'exp-1');
      await l.accept(la.lossTexts['loss-1']!, 'loss-1');
      await e.keepShare();
      d = gi.describe(lumpsum: s, lumpsumState: st());
      _assert(val(d, '투자 경험') == '소액 ETF 경험' && val(d, '손실 감내') == '길게 버틴다' && val(d, '투자 성향') == '중립', '답한 값 ${dump(d)}');
      await l.accept('해외주식', 'prod-os');
      d = gi.describe(lumpsum: s, lumpsumState: st(), hasFxAccount: false);
      _assert(val(d, '목표') == '해외주식 계좌 개설' && labels(d).contains('월 투자 참고 금액|해외 비중|해외 계좌'), '해외 계좌 줄 ${labels(d)}');
      _assert(
        val(d, '월 투자 참고 금액') == '월 ${la.about(s.advice!.monthlyInvest)}' && val(d, '해외 비중') == '100%' && val(d, '국내 비중') == null,
        '해외만 보면 해외 100% ${dump(d)}',
      );
      _assert(val(gi.describe(lumpsum: s, lumpsumState: st(), applied: true), '해외 계좌') == '승인 대기', '승인 대기');
      _assert(val(gi.describe(lumpsum: s, lumpsumState: st(), applied: true, approved: true), '해외 계좌') == '개설 완료', '개설 완료');
      // JS는 세션 복사본에 값을 덮어쓴다. 여기서는 잠시 바꿨다가 되돌린다
      gi.GoalInfo variant({String? market, String? goalKind}) {
        final m0 = s.market, k0 = s.goalKind;
        if (market != null) s.market = market;
        if (goalKind != null) s.goalKind = goalKind;
        try {
          return gi.describe(lumpsum: s, lumpsumState: st());
        } finally {
          s.market = m0;
          s.goalKind = k0;
        }
      }

      final bothInfo = variant(market: 'both');
      _assert(val(bothInfo, '국내 비중') == '${s.advice!.domesticShare}%' && val(bothInfo, '해외 비중') == '${s.advice!.overseasShare}%', '두 시장은 추천 비중 ${dump(bothInfo)}');
      final dom = variant(goalKind: 'DOMESTIC_STOCK');
      _assert(val(dom, '목표') == '국내주식 투자 알아보기' && val(dom, '국내 비중') == '100%' && val(dom, '해외 비중') == null, '국내만 보면 국내 100%');
      final lev = variant(goalKind: 'LEVERAGE');
      _assert(RegExp(r'^연 \d').hasMatch(val(lev, '필요한 연 수익') ?? '') && !dump(lev).contains('수익률'), '레버리지 줄');
    });

    await _with(null, (e) async {
      e.setMoney(3500000, 2100000, 30000000);
      final l = e.app.lumpsum;
      l.startNew();
      final s = e.app.session.lumpsum!;
      await l.accept(ls.opening);
      await l.accept(la.lumpGoals['goal-100']!.text, 'goal-100');
      await l.accept(ls.situationText());
      final debtInfo = gi.describe(lumpsum: s, lumpsumState: e.lf.state);
      _assert(!labels(debtInfo).contains('부채'), '부채가 있어도 알고 있는 정보에 부채 줄 없음');
      _assert(ls.situationText() == '투자에 더 집중하고 싶어요', '부채 언급 없는 입력 문장');
    });

    await _with(null, (e) async {
      e.setMoney(3500000, 3600000);
      final s = await e.lumpUntilGoal('goal-100');
      var d = gi.describe(lumpsum: s, lumpsumState: e.lf.state);
      _assert(e.lf.state == 'SPEND_PLAN' && val(d, '투자 경험') == '묻지 않음' && val(d, '투자 성향') == '묻지 않음', '일찍 끝난 채팅 ${dump(d)}');

      final bank = {for (final k in ['monthlyIncome', 'monthlyExpense', 'liquidAssets']) k: FinItem(value: 1000000, source: 'BANK', basis: '')};
      AssetSession mk(String purpose, Map<String, FinItem> items, [String goalText = '내 문장']) => AssetSession(caseId: 'TEST')
        ..goalText = goalText
        ..purpose = purpose
        ..info = aa.createInfo(items);
      d = gi.describe(asset: mk('INVEST', bank));
      _assert(labels(d) == '목표|투자 속도|다른 증권 투자금|목돈 지출 계획' && d.rows[0].note == '내 문장', '해외주식 투자 시작 ${labels(d)}');
      _assert(val(d, '투자 속도') == '아직 모름', '투자 속도 모름');
      d = gi.describe(asset: mk('INVEST', {}));
      _assert(labels(d) == '목표|투자 속도|다른 증권 투자금|목돈 지출 계획|월 소득|월 지출|예금성 자산', '계좌 정보 없을 때 ${labels(d)}');
      d = gi.describe(asset: mk('GOAL_SAVING', bank));
      _assert(labels(d) == '목표|목표 금액|목표 기간|목돈 지출 계획', '목돈 마련(이전) ${labels(d)}');
      d = gi.describe(asset: mk('EMERGENCY', bank));
      _assert(labels(d) == '목표|월 지출|예금성 자산|월 소득' && val(d, '월 지출') != '아직 모름', '비상자금 ${labels(d)}');
      d = gi.describe(asset: mk('ORIENT', {}));
      _assert(labels(d) == '목표|월 지출|예금성 자산|월 소득' && val(d, '월 지출') == '아직 모름', '계좌 정보로 시작');
      d = gi.describe(asset: mk('GOAL_SAVING', {}, ''));
      _assert(labels(d) == '목표' && val(d, '목표') == '아직 없음', '이전 상담 목표 전');
      final both = gi.describe(lumpsum: s, lumpsumState: 'INTRO', asset: mk('INVEST', bank));
      _assert(both.flow == 'lumpsum', '둘 다 있으면 목돈이 먼저');
    });
  });

  _t('시연 패널: 페르소나 요약과 정리된 카드', () => _with(null, (e) async {
        var r = personaSummary(const DemoProfile(income: 3500000, expense: 2100000, debtOn: false, debt: 0));
        _assert(r.lines.join('|') == '수입 350만원|지출 210만원|부채 없음|월 여유 140만원' && r.preset == '기본', '기본 요약 ${r.lines.join('|')}');
        r = personaSummary(const DemoProfile(income: 3500000, expense: 2100000, debtOn: true, debt: 30000000));
        _assert(r.lines[2] == '부채 3천만원 · 월 상환 ${formatMan(la.debtPayment(30000000))}' && r.preset == '부채 있음', '부채 요약 ${r.lines[2]}');
        _assert(personaSummary(const DemoProfile(income: 3500000, expense: 3600000)).preset == '여유 없음', '여유 없음 이름');
        _assert(personaSummary(const DemoProfile(income: 3600000, expense: 2100000)).preset == '', '값이 다르면 이름 없음');
        // 지운 카드가 남았는지(DOM)와 버튼 클릭은 위젯 영역이라, 버튼이 하는 프로필 변경만 DemoProfileStore로 확인한다
        final p = DemoProfileStore(store: e.s.store, storage: MemoryStorage());
        p.set(const DemoProfile(personaDone: false, income: 3500000, expense: 2100000, debtOn: false, debt: 0));
        p.set(p.profile.copyWith(personaDone: true));
        _assert(p.profile.personaDone == true && p.profile.income == 3500000 && p.profile.expense == 2100000, '이 설정으로 할게요');
        p.set(p.profile.copyWith(personaDone: false));
        _assert(p.profile.personaDone == false, '바꾸기');
        p.set(p.profile.copyWith(personaDone: true));
        p.set(presetProfile('base', p.profile));
        _assert(p.profile.personaDone == true, '기본값은 접힘 상태를 바꾸지 않음');
        p.set(p.profile.copyWith(personaDone: false));
        _assert(p.profile.personaDone == false && p.profile.income == 3500000, '처음부터는 값을 두고 편집기를 다시 엶');
        _assert(e.s.store.state.finance.items['monthlyIncome']?.value == 3500000, '프로필이 계좌 정보에 반영되지 않음');
      }));

  _t('통합 시나리오 가입: 이미 있는 계좌 → 외환·외화계좌·투자성향 → 승인 → 개설', () => _with(null, (e) async {
        await e.startJoin({}, DemoScenario.productId);
        _assert(e.js.questionsAsked == 0, '질문 ${e.js.questionsAsked}');
        final order = <String>[];
        for (var i = 0; i < 6 && (e.jf.state == 'OPTIONS_READY' || e.jf.state == 'REMAINING'); i++) {
          final next = e.js.route!.steps.first.actionId;
          order.add(next);
          await e.doTask(next, true);
        }
        const expected = ['FX_REGISTER', 'OPEN_FX_ACCOUNT', 'INVESTOR_PROFILE'];
        _assert(order.join(',') == expected.join(','), '업무 순서 ${order.join(',')}');
        _assert(e.jf.state == 'READY_TO_APPLY', '준비 상태 ${e.jf.state}');
        await e.j.approve(const ApplyTerms(market: '미국', account: 'WON 통장', fxAccount: 'WON 외화통장(USD)'));
        _assert(e.jf.state == 'COMPLETED', '결과 ${e.jf.state}');
        _assert(approvalWaitMs == 5000, '은행 승인 대기 시간 $approvalWaitMs');
        // JS는 결과 화면(joinResult)의 제목·버튼을 본다. Flutter 결과 화면은 위젯이라, 그 화면이 "개설 완료"를 고르는 상태 조건을 대신 본다
        final appId = e.js.appId;
        _assert(getProduct(e.js.productId)!.isBrokerage && appId != null && e.s.store.state.applications.containsKey(appId), '개설 완료 화면 조건');
        e.j.newCase();
        final notice = e.app.session.openedNotice;
        _assert(notice != null && notice.productId == DemoScenario.productId, '홈 완료 안내 ${notice?.toJson()}');
        e.app.dismissOpenedNotice();
        _assert(e.app.session.openedNotice == null, '완료 안내 닫기');
        final s = e.s.store.state;
        _assert(DemoScenario.stages.every((st) => st.facts.every((k) => s.facts[k] == true)), '진행 단계 사실 미충족');
      }));

  _t('시연용 요약 진행: 외환거래 이후 재조회로 이어지고 승인 전에 멈춤', () => _with(null, (e) async {
        await e.startJoin({}, DemoScenario.productId);
        final first = e.js.route!.steps.first.actionId;
        _assert(first == 'FX_REGISTER', '첫 업무 $first');
        await e.doTask(first, true);
        _assert(e.s.store.state.facts['fxRegistered'] == true, '외환거래 미반영');
        _assert(e.jf.state != 'READY_TO_APPLY', '승인 전에 요약 없이 준비됨');
        await e.j.summarizeRemaining();
        _assert(e.jf.state == 'READY_TO_APPLY', '요약 후 ${e.jf.state}');
        final f = e.s.store.state.facts;
        _assert(f['hasFxAccount'] == true && f['investorProfiled'] == true, '요약 업무 미반영');
        _assert(e.s.store.state.applications.isEmpty, '승인 전에 가입 요청됨');
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
        _assert(h != null && h.correction && h.fromSource == 'BANK' && h.toSource == 'STATED', '정정 이력 없음');
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
        final prop = chat.where((m) => m.kind == 'proposal').lastOrNull;
        _assert(prop != null && (prop.figures?.length ?? 0) >= 2, '제안 큰 숫자 없음');
        _assert(!prop!.text.contains('실제와 다를 수 있어요'), '같은 단서를 문장에 반복: ${prop.text}');
      }));

  _t('목표로 말한 결혼 자금을 예정 지출로 다시 묻지 않는다', () => _with(null, (e) async {
        final f = e.app.asset;
        f.start();
        f.agree();
        await f.setGoal('지금 예금 8482400원이면, 결혼 자금 3천만원을 모으는 데 얼마나 부족한가요?');
        _assert(e.as.pendingQuestion == 'goalMonths', '질문 ${e.as.pendingQuestion}');
        await f.answerChip('24', '2년 안에');
        _assert(e.as.pendingQuestion == 'plannedLumpSum', '다음 질문 ${e.as.pendingQuestion}');
        final asked = e.as.chat.where((m) => m.role == 'ai').lastOrNull;
        _assert(asked != null && asked.text.contains('그 외에 또 나갈 목돈이 있나요'), '질문: ${asked?.text}');
        _assert(!asked!.text.contains('결혼·이사·경조사처럼 목돈이 나갈'), '같은 일을 다시 물음');
      }));

  _t('생활비 개월치는 모으는 기간이 아니고, 비상자금은 충분한지 답한다', () => _with(null, (e) async {
        final f = e.app.asset;
        f.start();
        f.agree();
        await f.setGoal('예금이 생활비 4개월치예요. 비상자금으로 충분한지 알고 싶어요.');
        final a = e.as;
        _assert(a.purpose == 'EMERGENCY', '목적 ${a.purpose}');
        _assert(a.info!.items['goalMonths']?.value == null, '기간 ${a.info!.items['goalMonths']?.value}');
        _assert(e.af.state == 'REVIEW', '상태 ${e.af.state}');
        final prop = a.chat.where((m) => m.kind == 'proposal').lastOrNull;
        _assert(prop != null && prop.text.contains('충분') && !prop.text.contains('4개월 동안'), '제안: ${prop?.text}');
      }));

  _t('월급과 지출 금액은 목표 금액이 아니다', () => _with(null, (e) async {
        final f = e.app.asset;
        f.start();
        f.agree();
        await f.setGoal('월급 350만원에서 지출 210만원을 빼고, 해외주식을 시작해도 부담 없을까요?');
        final a = e.as;
        _assert(a.purpose == 'INVEST', '목적 ${a.purpose}');
        _assert(a.info!.items['goalAmount']?.value == null, '목표 ${a.info!.items['goalAmount']?.value}');
        _assert(!a.chat.any((m) => m.text.contains('목표 금액은 350만원')), '월급을 목표로 읽음');
        _assert(a.pendingQuestion == 'investPace', '질문 ${a.pendingQuestion}');
        await f.answerChip('UNKNOWN', '잘 모르겠어요');
        _assert(a.pendingQuestion == 'investAssets', '모름 다음 질문 ${a.pendingQuestion}');
        _assert(a.info!.declined.contains('investPace'), '투자 속도를 넘기지 않음');
        await f.answerChip('UNKNOWN', '잘 모르겠어요');
        _assert(a.pendingQuestion == 'plannedLumpSum', '모름 다음 질문 ${a.pendingQuestion}');
        _assert(a.info!.declined.contains('investAssets'), '증권 투자금을 넘기지 않음');
      }));

  _t('공격적 투자 속도는 남는 돈의 90%를 투자 금액으로 쓴다', () => _with(null, (e) async {
        final info = aa.createInfo(e.s.store.state.finance.items);
        final unknown = aa.computeMetrics(info);
        _assert(unknown['investMonthly'].value == 420000, '미확인 ${unknown['investMonthly'].value}');
        _assert(unknown['investMonthly'].formula.contains('아직 모름'), '근거 ${unknown['investMonthly'].formula}');
        aa.setItem(info, 'investPace', 50, 'STATED', '보통');
        _assert(aa.computeMetrics(info)['investMonthly'].value == 700000, '보통');
        aa.setItem(info, 'investPace', 90, 'STATED', '공격');
        final agg = aa.computeMetrics(info);
        _assert(agg['investMonthly'].value == 1260000, '공격 ${agg['investMonthly'].value}');
        _assert(agg['investMonthly'].formula.contains('90%') && agg['investMonthly'].formula.contains('고객이 고른'), '근거 ${agg['investMonthly'].formula}');
        final f = e.app.asset;
        f.start();
        f.agree();
        await f.setGoal('해외주식 투자를 처음 시작해 보고 싶어요');
        final a = e.as;
        _assert(a.pendingQuestion == 'investPace', '첫 질문 ${a.pendingQuestion}');
        await f.answerChip('90', '공격적으로');
        var n = 0;
        while (e.af.state == 'ASKING' && n < 4) {
          final q = aa.questions[a.pendingQuestion]!;
          await f.answerChip('${q.options[0].$2}', q.options[0].$1);
          n += 1;
        }
        _assert(a.proposal != null && a.proposal!.basis.monthly == 1260000, '제안 ${a.proposal?.basis.monthly}');
        final prop = a.chat.where((m) => m.kind == 'proposal').lastOrNull;
        final note = prop?.figures?.map((f) => f.note).join(' ') ?? '';
        _assert(note.contains('공격적') && note.contains('90%') && note.contains('140만원'), '카드 근거 $note');
        _assert(prop != null && prop.text.contains('원금 손실'), '투자 위험 안내 없음');
      }));

  _t('다시 분석은 투자 속도를 금액으로 곱하지 않는다', () => _with(null, (e) async {
        final info = aa.createInfo(e.s.store.state.finance.items);
        aa.setItem(info, 'investPace', 10000, 'STATED', '잘못된 정정');
        final capped = aa.computeMetrics(info);
        _assert(capped['investMonthly'].value == 1400000, '상한 ${capped['investMonthly'].value}');
        _assert(capped['investMonthly'].share == 100, '비율 ${capped['investMonthly'].share}');
        final f = e.app.asset;
        f.start();
        f.agree();
        await f.setGoal('해외주식 투자를 처음 시작해 보고 싶어요');
        final a = e.as;
        await f.answerChip('90', '공격적으로');
        var n = 0;
        while (e.af.state == 'ASKING' && n < 4) {
          final q = aa.questions[a.pendingQuestion]!;
          await f.answerChip('${q.options[0].$2}', q.options[0].$1);
          n += 1;
        }
        await f.accept();
        f.nextAction('recheck');
        _assert(e.af.state == 'RECONSULT', '상태 ${e.af.state}');
        await f.resumeAnalysis();
        _assert(a.proposal?.basis.monthly == 1260000, '그대로 다시 분석 ${a.proposal?.basis.monthly}');
        await f.accept();
        f.nextAction('recheck');
        aa.setItem(a.info!, 'investPace', 10000, 'STATED', '잘못된 정정');
        f.savePace('investPace', 90);
        _assert(a.info!.items['investPace']?.value == 90, '고친 값 ${a.info!.items['investPace']?.value}');
        await f.resumeAnalysis();
        _assert(a.proposal?.basis.monthly == 1260000, '고친 뒤 ${a.proposal?.basis.monthly}');
        final again = a.chat.where((m) => m.kind == 'proposal').lastOrNull;
        final note = again?.figures?.map((f) => f.note).join(' ') ?? '';
        _assert(note.contains('90%') && !note.contains('10000%'), '카드 $note');
      }));

  _t('계좌 정보만으로 어디부터는 목표 금액을 묻지 않는다', () => _with(null, (e) async {
        final f = e.app.asset;
        f.start();
        f.agree();
        await f.setGoal('계좌에 있는 정보만으로, 자산관리를 어디부터 보면 좋을까요?');
        final a = e.as;
        _assert(a.purpose == 'ORIENT', '목적 ${a.purpose}');
        _assert(e.af.state == 'REVIEW', '상태 ${e.af.state}');
        _assert(!a.chat.any((m) => m.text.contains('목표 금액이 어느 정도')), '목표 금액을 물음');
      }));

  _t('잘 모르겠어요는 그 질문만 넘기고 재계산하지 않는다', () => _with((d) {
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
        _assert(after.isNotEmpty && after.first == 'GAP_CHECK', '다음 상태 ${after.firstOrNull}');
        _assert(!after.contains('RECALC_ANSWER'), '재계산을 거침');
        _assert(e.as.pendingQuestion == 'goalAmount', '다음 질문 ${e.as.pendingQuestion}');
        _assert(e.af.state == 'ASKING', '상태 ${e.af.state}');
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
    final src = RegExp(r'^(P[1-9]|S)$');
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
