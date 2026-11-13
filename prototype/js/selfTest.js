/**
 * selfTest.js
 * 계획 7장 검증 항목을 브라우저 안에서 실행한다 (시연 패널 → 자가 테스트).
 * - 실행 전 은행 상태·세션·상태머신을 저장하고 끝나면 복원한다.
 * - 흐름 테스트는 화면 이동·모달을 대체(stub)하고 실제 흐름 코드를 그대로 돌린다.
 * 콘솔: await WSP.selfTest.run()
 */
(function () {
  'use strict';

  const WSP = window.WSP;
  const SC = WSP.scenario;
  const store = WSP.store;
  const bank = WSP.mockBank;
  const RE = WSP.ruleEngine;
  const PF = WSP.pathfinder;
  const AA = WSP.assetAdvisor;
  const PID = 'SAVINGS_GOAL';

  function assert(cond, msg) {
    if (!cond) throw new Error(msg || '조건 불일치');
  }

  /* ---------- 격리 ---------- */
  function snapshot() {
    const f = {};
    Object.keys(WSP.app.fsms).forEach((k) => (f[k] = { state: WSP.app.fsms[k].state, history: WSP.app.fsms[k].history() }));
    return {
      bank: store.getState(),
      session: JSON.parse(JSON.stringify(WSP.app.session)),
      fsm: f,
      latency: bank.getLatencyScale(),
      lastRoute: PF.getLastResult(),
    };
  }

  function restore(snap) {
    store.replace(snap.bank, '[자가 테스트] 상태 복원');
    WSP.app.replaceSession(snap.session);
    Object.keys(snap.fsm).forEach((k) => WSP.app.fsms[k].restore(snap.fsm[k].state, snap.fsm[k].history));
    bank.setLatencyScale(snap.latency);
    PF.setLastResult(snap.lastRoute);
  }

  const STUBBED = ['navigate', 'rerender', 'toast', 'confirm', 'openTaskModal', 'isTaskModalOpen', 'openSheet', 'closeSheet'];
  function stubUI() {
    const saved = {};
    STUBBED.forEach((k) => (saved[k] = WSP.ui[k]));
    WSP.ui.navigate = () => Promise.resolve(true);
    WSP.ui.rerender = () => Promise.resolve();
    WSP.ui.toast = () => {};
    WSP.ui.confirm = () => Promise.resolve(true);
    WSP.ui.openTaskModal = () => {};
    WSP.ui.isTaskModalOpen = () => false;
    WSP.ui.openSheet = () => null;
    WSP.ui.closeSheet = () => {};
    return () => STUBBED.forEach((k) => (WSP.ui[k] = saved[k]));
  }

  /** 깨끗한 상태에서 은행 상태를 설정한다 */
  function fresh(mutator) {
    store.reset('[자가 테스트] 초기화');
    if (mutator) store.update(mutator, '[자가 테스트] 상태 설정');
    WSP.app.replaceSession(null);
    Object.keys(WSP.app.fsms).forEach((k) => WSP.app.fsms[k].reset());
    bank.setLatencyScale(0);
  }

  const J = () => WSP.joinFlow;
  const jf = () => WSP.app.fsms.join;
  const af = () => WSP.app.fsms.asset;

  /** AI 가입 지원을 시작하고, 묻는 질문에는 answers(없으면 true)로 답한다 */
  async function startJoin(answers) {
    J().start(PID);
    await J().agree();
    const ans = answers || {};
    for (let i = 0; i < 5 && WSP.app.session.join && WSP.app.session.join.pendingKey; i++) {
      const key = WSP.app.session.join.pendingKey;
      await J().answer(key, ans[key] !== undefined ? ans[key] : true);
    }
  }

  /** 모달에서 업무를 진행한 것처럼 처리하고 닫는다. run=false면 진행 없이 닫기 */
  async function doTask(taskId, run) {
    await J().chooseOption(taskId);
    const ct = WSP.app.session.join.currentTask;
    let status = 'OPEN';
    if (run) {
      const r = await bank.runTask(ct.sessionId, { job: '회사원', purpose: '저축·자산 형성' });
      status = r.ok ? r.data.status : 'REJECTED';
    }
    await J().modalClosed({ status: status, sessionId: ct.sessionId });
  }

  const onlyIdentityMissing = (d) => {
    Object.keys(d.facts).forEach((k) => (d.facts[k] = true));
    d.facts.identityVerified = false;
  };

  /* ---------- 테스트 ---------- */
  const TESTS = [];
  const t = (name, fn) => TESTS.push({ name: name, fn: fn });

  t('조회 실패는 미충족이 아니라 UNKNOWN으로 판정', async () => {
    fresh((d) => (d.simulation.queryFailure = true));
    const ev = RE.evaluate(PID, await bank.checkConditions(PID));
    assert(!ev.ok, '조회 실패가 ok로 판정됨');
    assert(ev.conditions.every((c) => c.status === 'UNKNOWN'), 'UNKNOWN이 아닌 조건이 있음');
    assert(ev.unmet.length === 0 && !ev.allMet, '미충족·충족으로 단정함');
    assert(PF.computeRoute(ev, {}).status === 'UNKNOWN', '조회 실패로 경로를 만듦');
  });

  t('조회 실패 시 가입 지원은 CHECK_FAILED(P3)로 멈춤', async () => {
    fresh((d) => (d.simulation.queryFailure = true));
    await startJoin();
    assert(jf().state === 'CHECK_FAILED', '상태 ' + jf().state);
  });

  t('고객 제약에 따라 경로가 걸러짐 (신분증 없음 → 모바일 신분증)', async () => {
    fresh();
    const ev = RE.evaluate(PID, await bank.checkConditions(PID));
    const r1 = PF.computeRoute(ev, { hasIdCard: false, hasMobileId: true, hasOtherBankAccount: true });
    assert(r1.status === 'PLAN' && r1.steps[0].actionId === 'MOBILE_ID_VERIFY', '첫 단계 ' + (r1.steps[0] || {}).actionId);
    assert(r1.options.find((o) => o.actionId === 'ID_CARD_VERIFY').availability === 'BLOCKED', '신분증 수단이 막히지 않음');
    const r2 = PF.computeRoute(ev, { hasIdCard: true, hasMobileId: false, hasOtherBankAccount: true });
    assert(r2.steps[0].actionId === 'ID_CARD_VERIFY', '신분증 경로가 아님');
    const r3 = PF.computeRoute(ev, { hasIdCard: false, hasMobileId: false, hasOtherBankAccount: true });
    assert(r3.status === 'NO_PATH', '실명확인 수단이 없는데 경로가 있음');
  });

  t('필요한 경우에만 질문 (P4): 모르는 사정은 질문 목록, 확인된 경로가 있으면 질문 없음', async () => {
    fresh();
    const ev = RE.evaluate(PID, await bank.checkConditions(PID));
    const r1 = PF.computeRoute(ev, { hasIdCard: null, hasMobileId: null, hasOtherBankAccount: true });
    assert(r1.questions[0] === 'hasIdCard', '질문 ' + r1.questions.join(','));
    const r2 = PF.computeRoute(ev, { hasIdCard: true, hasMobileId: null, hasOtherBankAccount: true });
    assert(r2.questions.length === 0, '확인된 경로가 있는데 질문함');
  });

  t('순환(계좌↔인증서) 감지 → 상담 전환', async () => {
    fresh((d) => (d.finance.otherBankAccounts = []));
    await startJoin({ hasIdCard: false, hasMobileId: true, hasOtherBankAccount: false });
    assert(jf().state === 'ESCALATED', '상태 ' + jf().state);
    const e = WSP.app.session.join.escalation;
    assert(e && e.reason === 'CYCLE', '사유 ' + (e && e.reason));
    assert(e.cause.chain.indexOf('hasDepositAccount') !== -1 && e.cause.chain.indexOf('certRegistered') !== -1, '순환 구성 ' + e.cause.chain);
  });

  t('은행이 아는 정보(다른 은행 계좌·휴대폰 명의)는 다시 묻지 않음', async () => {
    fresh();
    await startJoin({ hasIdCard: false, hasMobileId: true });
    const j = WSP.app.session.join;
    assert(j.constraintSource.hasOtherBankAccount.source === 'BANK', '다른 은행 계좌 출처');
    assert(j.skipped.length >= 2, '생략 기록 없음');
    assert(j.questionsAsked === 2, '질문 수 ' + j.questionsAsked);
  });

  t('모달을 닫기만 하면 완료로 판정하지 않음', async () => {
    fresh();
    await startJoin();
    assert(jf().state === 'OPTIONS_READY', '시작 상태 ' + jf().state);
    await doTask('ID_CARD_VERIFY', false);
    assert(jf().state === 'REMAINING', '상태 ' + jf().state);
    assert(store.getState().facts.identityVerified === false, '은행 사실이 바뀜');
  });

  const MODAL_CASES = [
    ['성공', 'NORMAL', true, 'READY_TO_APPLY'],
    ['취소', 'NORMAL', false, 'REMAINING'],
    ['일부 완료', 'PARTIAL', true, 'REMAINING'],
    ['처리 중', 'IN_PROGRESS', true, 'INVESTIGATING'],
    ['확인 실패', 'QUERY_FAIL', true, 'INVESTIGATING'],
  ];
  t('모달 결과 5가지 → 조건 충족 / 남은 조건 / 예외 3분기 (P3)', async () => {
    const got = [];
    for (let i = 0; i < MODAL_CASES.length; i++) {
      const c = MODAL_CASES[i];
      fresh(onlyIdentityMissing);
      await startJoin();
      if (c[1] !== 'QUERY_FAIL') store.update((d) => (d.simulation.nextTaskOutcome = c[1]), '[자가 테스트] 업무 결과');
      await J().chooseOption('ID_CARD_VERIFY');
      const ct = WSP.app.session.join.currentTask;
      let status = 'OPEN';
      if (c[2]) {
        const r = await bank.runTask(ct.sessionId, {});
        status = r.data.status;
      }
      if (c[1] === 'QUERY_FAIL') store.update((d) => (d.simulation.queryFailure = true), '[자가 테스트] 조회 실패');
      await J().modalClosed({ status: status });
      got.push(c[0] + '→' + jf().state);
      assert(jf().state === c[3], c[0] + ': 기대 ' + c[3] + ', 실제 ' + jf().state);
    }
  });

  t('처리 중 업무는 결과 재조회 후 해결되면 재확인(P2)', async () => {
    fresh(onlyIdentityMissing);
    await startJoin();
    store.update((d) => (d.simulation.nextTaskOutcome = 'IN_PROGRESS'), '[자가 테스트]');
    await doTask('ID_CARD_VERIFY', true);
    assert(jf().state === 'INVESTIGATING', '상태 ' + jf().state);
    await J().investigate('requery');
    assert(jf().state === 'READY_TO_APPLY', '상태 ' + jf().state);
  });

  t('완료 불일치가 2회 반복되면 같은 업무를 반복시키지 않고 상담 전환', async () => {
    fresh((d) => {
      onlyIdentityMissing(d);
      d.simulation.nextTaskOutcome = 'MISMATCH_ALWAYS';
    });
    await startJoin();
    await doTask('ID_CARD_VERIFY', true);
    assert(jf().state === 'INVESTIGATING', '1회 후 ' + jf().state);
    await J().investigate('retry');
    assert(jf().state === 'REMAINING', '재시도 후 ' + jf().state);
    await doTask('ID_CARD_VERIFY', true);
    assert(jf().state === 'ESCALATED', '2회 후 ' + jf().state);
    assert(WSP.app.session.join.escalation.reason === 'REPEAT', '사유 ' + WSP.app.session.join.escalation.reason);
  });

  t('AI 가입 지원 주 경로: 신분증 없음 → 모바일 신분증 → 계좌 → 인증서·고객정보 → 승인 → 완료', async () => {
    fresh();
    await startJoin({ hasIdCard: false, hasMobileId: true });
    const order = [];
    for (let i = 0; i < 6 && (jf().state === 'OPTIONS_READY' || jf().state === 'REMAINING'); i++) {
      const next = WSP.app.session.join.route.steps[0].actionId;
      order.push(next);
      await doTask(next, true);
    }
    assert(order[0] === 'MOBILE_ID_VERIFY', '첫 업무 ' + order[0]);
    assert(order.indexOf('OPEN_ACCOUNT_OTHERBANK') !== -1 && order.indexOf('OPEN_ACCOUNT_OTHERBANK') < order.indexOf('ISSUE_CERT'), '계좌보다 인증서가 먼저: ' + order.join(','));
    assert(order.length === 4 && order.indexOf('KYC_UPDATE') !== -1, '업무 ' + order.join(','));
    assert(jf().state === 'READY_TO_APPLY', '준비 상태 ' + jf().state);
    assert(Object.keys(store.getState().applications).length === 0, '승인 전에 가입 요청됨');
    await J().approve({ monthly: 300000, months: 24, account: 'WON 통장' });
    assert(jf().state === 'COMPLETED', '결과 ' + jf().state);
  });

  t('가입 결과 조회는 요청을 다시 보내지 않고, 같은 requestId는 중복 가입을 만들지 않음', async () => {
    fresh((d) => {
      Object.keys(d.facts).forEach((k) => (d.facts[k] = true));
      d.simulation.nextApplicationOutcome = 'PENDING';
    });
    const req = bank.newRequestId();
    const r1 = await bank.submitApplication({ requestId: req, productId: PID, terms: {} });
    const r2 = await bank.submitApplication({ requestId: req, productId: PID, terms: {} });
    assert(r1.ok && r2.ok && r2.data.duplicate, '중복 차단 안 됨');
    for (let i = 0; i < 3; i++) await bank.getApplicationResult(r1.data.application.id);
    const apps = store.getState().applications;
    assert(Object.keys(apps).length === 1, '가입 요청 ' + Object.keys(apps).length + '건');
    assert(apps[r1.data.application.id].status === 'PENDING', '조회만으로 상태가 바뀜');
  });

  t('결과 불명 → 결과 조회만 허용, 은행 확정 후 완료', async () => {
    fresh((d) => {
      Object.keys(d.facts).forEach((k) => (d.facts[k] = true));
      d.simulation.nextApplicationOutcome = 'UNKNOWN';
    });
    await startJoin();
    assert(jf().state === 'READY_TO_APPLY', '시작 ' + jf().state);
    await J().approve({ monthly: 300000, months: 24, account: 'WON 통장' });
    assert(jf().state === 'RESULT_UNCERTAIN', '상태 ' + jf().state);
    assert(!jf().can('APPROVED'), '재신청 전이가 열려 있음');
    bank.demoResolveApplication(WSP.app.session.join.appId, 'SUCCESS');
    await J().queryResult();
    assert(jf().state === 'COMPLETED', '조회 후 ' + jf().state);
    assert(Object.keys(store.getState().applications).length === 1, '가입 요청이 추가됨');
  });

  t('늦게 도착한 응답과 연타는 무시됨', async () => {
    fresh();
    bank.setLatencyScale(1);
    J().start(PID);
    const p = J().agree();
    WSP.app.invalidate();
    await p;
    assert(WSP.app.session.join.evaluation === null, '무효화 이후 조회 결과가 반영됨');
    bank.setLatencyScale(0);
    let calls = 0;
    const slow = () => new Promise((r) => setTimeout(() => r(++calls), 30));
    await Promise.all([WSP.app.guard('t', slow), WSP.app.guard('t', slow)]);
    assert(calls === 1, '연타가 ' + calls + '회 실행됨');
  });

  t('정정된 정보로 지표를 다시 계산하고 이력을 남김', async () => {
    fresh();
    const info = AA.createInfo(store.getState().finance.items);
    AA.setItem(info, 'goalMonths', 24, 'STATED', '목표');
    const m1 = AA.computeMetrics(info);
    AA.setItem(info, 'monthlyExpense', 1500000, 'STATED', '고객 정정');
    const m2 = AA.computeMetrics(info);
    assert(m1.byKey.surplus.value === 1400000 && m2.byKey.surplus.value === 2000000, '여유자금 ' + m1.byKey.surplus.value + '→' + m2.byKey.surplus.value);
    const h = info.history.find((x) => x.key === 'monthlyExpense');
    assert(h && h.correction && h.fromSource === 'ESTIMATED' && h.toSource === 'STATED', '정정 이력 없음');
    assert(AA.computeMetrics(info).byKey.needMonthly.value === m2.byKey.needMonthly.value, '같은 입력에 다른 결과');
  });

  t('질문 중단 요청 → 제한적 제안 (PROPOSABLE_CHECK → PROPOSED_LIMITED)', async () => {
    fresh();
    const F = WSP.assetFlow;
    F.start();
    F.agree();
    await F.setGoal('2년 뒤 집 살 때 보탤 목돈');
    assert(af().state === 'ASKING', '질문 상태 아님 ' + af().state);
    await F.answerChip('STOP', '질문은 그만');
    assert(af().state === 'REVIEW', '상태 ' + af().state);
    assert(WSP.app.session.asset.proposal.level === 'LIMITED', '제안 수준 ' + WSP.app.session.asset.proposal.level);
  });

  t('질문 한도(3회)에 도달하면 더 묻지 않고 제안 가능 판단으로', async () => {
    fresh((d) => {
      d.finance.items.monthlyIncome = { value: null, source: 'UNKNOWN', basis: '' };
      d.finance.items.monthlyExpense = { value: null, source: 'UNKNOWN', basis: '' };
    });
    const F = WSP.assetFlow;
    F.start();
    F.agree();
    await F.setGoal('2년 뒤 목돈 마련');
    let n = 0;
    while (af().state === 'ASKING' && n < 6) {
      const q = AA.QUESTIONS[WSP.app.session.asset.pendingQuestion];
      await F.answerChip(String(q.options[1][1]), q.options[1][0]);
      n += 1;
    }
    assert(n === SC.POLICY.assetQuestionLimit, '질문 ' + n + '회');
    assert(af().history().some((h) => h.event === 'LIMIT_OR_STOP'), '한도 분기 없음');
    assert(af().state === 'REVIEW' && WSP.app.session.asset.proposal.level === 'LIMITED', '상태 ' + af().state);
    const chat = WSP.app.session.asset.chat;
    assert(!chat.some((m) => /반영했어요/.test(m.text)), '답변 확인 메시지가 남아 있음');
    const prop = chat.filter((m) => m.kind === 'proposal').pop();
    assert(prop && prop.figures && prop.figures.length >= 2, '제안 큰 숫자 없음');
    assert(/실제와 다를 수 있어요/.test(prop.text), '불확실성 안내 없음: ' + prop.text);
  });

  t('모름·답변 거부는 재계산 없이 제안 가능 판단으로 가고, 최소 정보가 없으면 보류', async () => {
    fresh((d) => {
      d.finance.items.monthlyIncome = { value: null, source: 'UNKNOWN', basis: '' };
    });
    const F = WSP.assetFlow;
    F.start();
    F.agree();
    await F.setGoal('2년 뒤 목돈 마련');
    assert(WSP.app.session.asset.pendingQuestion === 'monthlyIncome', '질문 ' + WSP.app.session.asset.pendingQuestion);
    const before = af().history().length;
    await F.answerChip('UNKNOWN', '잘 모르겠어요');
    const after = af().history().slice(before).map((h) => h.to);
    assert(after[0] === 'PROPOSABLE_CHECK', '다음 상태 ' + after[0]);
    assert(after.indexOf('RECALC_ANSWER') === -1, '재계산을 거침');
    assert(af().state === 'HOLD', '상태 ' + af().state);
  });

  t('AI 출력 검증기: 경로에 없는 업무·가입 실행·완료 단정을 거부', async () => {
    const V = WSP.aiSchema.validate;
    const ok = V({ intent: 'X', message: '방법을 골라 주세요', actions: [{ type: 'PRESENT_OPTIONS', options: ['ID_CARD_VERIFY'] }] }, { allowedActionIds: ['ID_CARD_VERIFY'] });
    assert(ok.valid, '정상 출력 거부: ' + ok.errors.join(','));
    assert(!V({ intent: 'X', message: '', actions: [{ type: 'PRESENT_OPTIONS', options: ['ISSUE_CERT'] }] }, { allowedActionIds: ['ID_CARD_VERIFY'] }).valid, '허용 안 된 업무 통과');
    assert(!V({ intent: 'X', message: '', actions: [{ type: 'CALL_TOOL', tool: 'submitApplication' }] }, {}).valid, '가입 실행 도구 통과');
    assert(!V({ intent: 'X', message: '가입이 완료됐어요', actions: [] }, {}).valid, '완료 단정 통과');
    assert(!V({ intent: 'X', message: '', actions: [{ type: 'SET_CONSTRAINT', key: 'hasCar', value: true }] }, {}).valid, '모르는 제약 통과');
    fresh();
    WSP.aiAgent.injectInvalidNext();
    const r = await WSP.aiAgent.join.ask('hasIdCard', []);
    assert(r.fallback && !r.valid, '주입한 위반이 통과됨');
  });

  t('같은 데이터로 AI 경로와 직접 가입의 조건 판정이 일치', async () => {
    const keys = ['identityVerified', 'hasDepositAccount', 'certRegistered', 'kycDone'];
    for (let mask = 0; mask < 16; mask++) {
      fresh((d) => keys.forEach((k, i) => (d.facts[k] = !!(mask & (1 << i)))));
      const c = await bank.checkConditions(PID);
      const aiUnmet = RE.evaluate(PID, c).unmet.slice().sort();
      const directUnmet = [];
      SC.getProduct(PID).directSteps.forEach((st) => st.checks.forEach((id) => !c.data.conditions.find((x) => x.id === id).value && directUnmet.push(id)));
      assert(aiUnmet.join() === directUnmet.sort().join(), 'mask ' + mask + ': ' + aiUnmet + ' / ' + directUnmet);
    }
  });

  t('직접 가입: 부족 조건 안내 → 메뉴에서 해결 → 1단계부터 다시 (P6)', async () => {
    fresh(onlyIdentityMissing);
    const D = WSP.directFlow;
    D.start(PID);
    D.begin();
    WSP.app.session.direct.input.agreed = true;
    await D.next();
    await D.next();
    await D.next();
    assert(WSP.app.fsms.direct.state === 'D_NOTICE', '상태 ' + WSP.app.fsms.direct.state);
    assert(WSP.app.session.direct.notice.conditions[0].id === 'IDENTITY', '안내 조건');
    D.goFix();
    store.update((d) => (d.facts.identityVerified = true), '[자가 테스트] 메뉴에서 실명확인');
    D.restart();
    assert(WSP.app.fsms.direct.state === 'D_STEP' && WSP.app.session.direct.stepIndex === 0, '1단계로 돌아가지 않음');
    assert(WSP.app.session.direct.metrics.restarts === 1, '다시 시작 횟수');
  });

  /** 0-1 원본 워크플로우 화살표 (트랙, from, event, to) */
  const DIAGRAM = {
    join: [
      ['IDLE', 'START', 'CONSENT'],
      ['CONSENT', 'AGREE', 'CHECKING'],
      ['CHECKING', 'NONE_MISSING', 'READY_TO_APPLY'],
      ['CHECKING', 'MISSING', 'CLARIFYING'],
      ['CLARIFYING', 'CLARIFIED', 'ROUTE_CHECK'],
      ['ROUTE_CHECK', 'ROUTE_FOUND', 'OPTIONS_READY'],
      ['ROUTE_CHECK', 'NO_ROUTE', 'ESCALATED'],
      ['OPTIONS_READY', 'TASK_OPENED', 'TASK_OPEN'],
      ['TASK_OPEN', 'MODAL_CLOSED', 'RECHECKING'],
      ['RECHECKING', 'ALL_MET', 'READY_TO_APPLY'],
      ['RECHECKING', 'REMAINING', 'REMAINING'],
      ['RECHECKING', 'EXCEPTION', 'INVESTIGATING'],
      ['REMAINING', 'TASK_OPENED', 'TASK_OPEN'],
      ['INVESTIGATING', 'UNRESOLVABLE', 'ESCALATED'],
      ['READY_TO_APPLY', 'APPROVED', 'APPLYING'],
      ['APPLYING', 'SUBMITTED', 'VERIFYING'],
      ['VERIFYING', 'RESULT_SUCCESS', 'COMPLETED'],
      ['VERIFYING', 'RESULT_FAILED', 'FAILED'],
      ['VERIFYING', 'RESULT_UNKNOWN', 'RESULT_UNCERTAIN'],
    ],
    asset: [
      ['IDLE', 'START', 'CONSENT'],
      ['CONSENT', 'AGREE', 'GOAL'],
      ['GOAL', 'GOAL_SET', 'COLLECTING'],
      ['COLLECTING', 'COLLECTED', 'TAGGING'],
      ['TAGGING', 'TAGGED', 'CALCULATING'],
      ['CALCULATING', 'CALCULATED', 'INTERPRETING'],
      ['INTERPRETING', 'INTERPRETED', 'GAP_CHECK'],
      ['GAP_CHECK', 'NO_GAP', 'PROPOSED_FULL'],
      ['GAP_CHECK', 'ASK', 'ASKING'],
      ['GAP_CHECK', 'LIMIT_OR_STOP', 'PROPOSABLE_CHECK'],
      ['ASKING', 'ANSWERED', 'RECALC_ANSWER'],
      ['ASKING', 'UNKNOWN_OR_REFUSED', 'PROPOSABLE_CHECK'],
      ['ASKING', 'STOP_REQUEST', 'PROPOSABLE_CHECK'],
      ['RECALC_ANSWER', 'RECALCULATED', 'INTERPRETING'],
      ['PROPOSABLE_CHECK', 'PROPOSABLE', 'PROPOSED_LIMITED'],
      ['PROPOSABLE_CHECK', 'NOT_PROPOSABLE', 'HOLD'],
      ['PROPOSED_FULL', 'SHOWN', 'REVIEW'],
      ['PROPOSED_LIMITED', 'SHOWN', 'REVIEW'],
      ['REVIEW', 'ACCEPT', 'NEXT_ACTION'],
      ['REVIEW', 'MODIFY', 'RECALC_CHANGE'],
      ['REVIEW', 'END', 'CLOSED'],
      ['RECALC_CHANGE', 'RECALCULATED', 'INTERPRETING'],
      ['NEXT_ACTION', 'CONSULT', 'HANDOFF'],
      ['NEXT_ACTION', 'KEEP', 'CLOSED'],
      ['NEXT_ACTION', 'RECHECK_INFO', 'RECONSULT'],
      ['NEXT_ACTION', 'EXPLORE', 'EXPLORE'],
      ['EXPLORE', 'PRODUCT_SELECTED', 'TO_JOIN'],
    ],
    direct: [
      ['IDLE', 'START', 'D_START'],
      ['D_START', 'BEGIN', 'D_STEP'],
      ['D_STEP', 'STEP_DONE', 'D_CHECK'],
      ['D_CHECK', 'PASS', 'D_STEP'],
      ['D_CHECK', 'UNMET', 'D_NOTICE'],
      ['D_NOTICE', 'GO_FIX', 'D_SELF_FIX'],
      ['D_VERIFYING', 'RESULT_SUCCESS', 'D_DONE'],
    ],
  };

  t('상태머신 전이표가 원본 화살표를 모두 포함하고, 추가 전이는 제안(P1~P8)·안전(S)뿐', async () => {
    Object.keys(DIAGRAM).forEach((kind) => {
      const tbl = WSP.FSM_TABLES[kind];
      DIAGRAM[kind].forEach((e) => {
        assert(tbl.table[e[0]] && tbl.table[e[0]][e[1]] === e[2], kind + ' 원본 화살표 누락: ' + e.join(' '));
      });
      const diagramKeys = new Set(DIAGRAM[kind].map((e) => e[0] + '|' + e[1]));
      WSP.FSM_DEFS[kind].edges.forEach((e) => {
        const k = e[0] + '|' + e[1];
        if (diagramKeys.has(k)) return;
        assert(/^(P[1-8]|S)$/.test(e[3]), kind + ' 원본에 없는데 제안·안전 전이로 표시되지 않음: ' + k + ' (' + e[3] + ')');
      });
    });
  });

  t('상담 접수 실패와 요약 생성을 구분', async () => {
    fresh((d) => (d.simulation.nextConsultOutcome = 'FAILED'));
    const r = await bank.createConsultation({ lines: ['요약'] });
    assert(!r.ok && r.error.code === 'CONSULT_FAILED', '실패가 접수로 처리됨');
    assert(Object.keys(store.getState().consultations).length === 0, '실패했는데 접수 기록 생성');
  });

  async function run() {
    const snap = snapshot();
    const unstub = stubUI();
    const results = [];
    WSP.events.add('TEST', '자가 테스트 시작 (' + TESTS.length + '개)');
    try {
      for (let i = 0; i < TESTS.length; i++) {
        const tc = TESTS[i];
        try {
          await tc.fn();
          results.push({ name: tc.name, ok: true });
        } catch (e) {
          results.push({ name: tc.name, ok: false, detail: e && e.message ? e.message : String(e) });
        }
      }
    } finally {
      WSP.app.invalidate();
      unstub();
      restore(snap);
      WSP.ui.rerender();
    }
    const passed = results.filter((r) => r.ok).length;
    const report = { total: results.length, passed: passed, failed: results.length - passed, results: results };
    WSP.events.add('TEST', '자가 테스트 완료: ' + passed + '/' + results.length + ' 통과', report.failed ? 'warn' : 'info');
    console.table(results);
    return report;
  }

  WSP.selfTest = { run: run };
})();
