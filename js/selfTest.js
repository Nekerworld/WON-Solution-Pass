/**
 * selfTest.js
 * 브라우저 안에서 실행되는 로직 자가 테스트 (명세 14장 1~12번 + 보조 항목).
 * - 실행 전 저장소/FSM/세션을 스냅샷하고 실행 후 그대로 복원한다.
 * - 시연 패널의 "자가 테스트 실행" 또는 URL ?selftest=1 로 실행한다.
 */
(function () {
  'use strict';

  const WSP = window.WSP;
  const store = WSP.store;
  const bank = WSP.mockBank;
  const PF = WSP.pathfinder;
  const bot = WSP.chatbot;
  const clone = WSP.utils.clone;

  function assert(cond, msg) {
    if (!cond) throw new Error(msg || '검증 실패');
  }

  function ids(plan) {
    return plan.steps.map((s) => s.actionId).join(',');
  }

  function resetTo(mutator) {
    store.replace(clone(WSP.initialBankState));
    if (mutator) store.update(mutator, '[TEST] 상태 설정');
  }

  async function planNow() {
    const r = await WSP.app.computeFromBank();
    return r;
  }

  function txCount() {
    return Object.keys(store.getState().transactions).length;
  }

  function testFsm() {
    return WSP.createFSM({ log: false });
  }

  async function run() {
    const snapshot = store.getState();
    const fsmState = WSP.fsm.state;
    const fsmHistory = WSP.fsm.history();
    const session = clone(WSP.app.session);
    const latency = bank.getLatencyScale();
    const lastPath = WSP.pathfinder.getLastResult();
    const results = [];

    async function t(name, fn) {
      try {
        await fn();
        results.push({ name: name, ok: true });
      } catch (e) {
        results.push({ name: name, ok: false, detail: e.message });
      }
    }

    bank.setLatencyScale(0);
    store.setSilent(true);

    try {
      await t('1. 초기 이체 시도에서 복합 오류 감지', async () => {
        resetTo();
        const v = await bank.validateTransfer();
        const codes = v.data.reasons.map((r) => r.code);
        assert(!v.data.valid, '검사 통과되면 안 됨');
        assert(codes.indexOf('LIMIT_EXCEEDED') !== -1 && codes.indexOf('OTP_REQUIRED') !== -1, '사유: ' + codes.join(','));
        const r = await planNow();
        assert(ids(r.plan) === 'REGISTER_OTP,CHANGE_TRANSFER_LIMIT,RETURN_TO_TRANSFER', '경로: ' + ids(r.plan));
      });

      await t('2. OTP 등록 후 남은 해결 경로 자동 갱신', async () => {
        const reg = await bank.registerDigitalOtp();
        assert(reg.ok, 'OTP 등록 실패');
        const r = await planNow();
        assert(ids(r.plan) === 'CHANGE_TRANSFER_LIMIT,RETURN_TO_TRANSFER', '경로: ' + ids(r.plan));
      });

      await t('3. 이체한도 변경 후 원래 이체 복귀 (이체 정보 유지)', async () => {
        const ch = await bank.changeTransferLimit(1500000);
        assert(ch.ok, '한도 변경 실패');
        const r = await planNow();
        assert(r.plan.status === 'READY', '상태: ' + r.plan.status);
        assert(ids(r.plan) === 'RETURN_TO_TRANSFER', '경로: ' + ids(r.plan));
        const init = WSP.initialBankState.transfer;
        assert(
          r.draft.amount === init.amount && r.draft.recipient === init.recipient && r.draft.recipientBank === init.recipientBank && r.draft.fromAccount === init.fromAccount,
          '이체 정보가 변경됨'
        );
      });

      await t('4. 사용자의 직접 승인 없이 거래가 실행되지 않음', async () => {
        assert(txCount() === 0, '해결 절차만으로 거래가 생성됨');
        const f = testFsm();
        ['TRANSFER_FAILED', 'PATH_FOUND', 'STEP_SELECTED', 'USER_RETURNED', 'PATH_FOUND', 'STEP_SELECTED', 'USER_RETURNED', 'ALL_MET'].forEach((ev) => {
          assert(f.transition(ev).ok, '전이 실패: ' + ev);
        });
        assert(f.state === 'READY_TO_RETRY', 'FSM: ' + f.state);
        assert(txCount() === 0, '준비 완료 상태에서 자동 거래 발생');
        const noId = await bank.submitTransfer(Object.assign({}, store.getState().transfer, { requestId: null }));
        assert(!noId.ok && txCount() === 0, '요청 식별값 없는 거래가 실행됨');
      });

      await t('5. 이체 성공(SUCCESS) 응답 후에만 해결 완료', async () => {
        const f = testFsm();
        ['TRANSFER_FAILED', 'NO_ACTION_NEEDED'].forEach((ev) => f.transition(ev));
        assert(!f.transition('RESULT_SUCCESS').ok, 'VERIFYING 이전에 완료 전이 허용됨');
        f.transition('USER_APPROVED');
        store.update((d) => (d.simulation.nextTransferOutcome = 'PENDING'), '[TEST]');
        const p = await bank.submitTransfer(Object.assign({}, store.getState().transfer, { requestId: bank.newRequestId() }));
        assert(p.ok && p.data.transaction.status === 'PENDING', 'PENDING 응답 아님');
        assert(f.state === 'VERIFYING', 'PENDING에서 상태가 바뀜');
        bank.demoResolveTransaction(p.data.transaction.id, 'SUCCESS');
        const q = await bank.getTransferResult(p.data.transaction.id);
        assert(q.data.transaction.status === 'SUCCESS', '조회 결과 SUCCESS 아님');
        assert(f.transition('RESULT_SUCCESS').ok && f.state === 'COMPLETED', 'COMPLETED 아님');
      });

      await t('6. OTP가 이미 등록된 경우 중복 등록 안내 없음', async () => {
        resetTo((d) => (d.customer.digitalOtpRegistered = true));
        const r = await planNow();
        assert(ids(r.plan).indexOf('REGISTER_OTP') === -1, '경로: ' + ids(r.plan));
        const reply = await bot.respond('이체가 왜 안 돼?');
        assert(reply.links.every((l) => l.flowId !== 'otp-registration'), 'OTP 등록 링크 제공됨');
        assert(reply.text.indexOf('OTP 등록을 진행') === -1, '응답: ' + reply.text);
        const dup = await bank.registerDigitalOtp();
        assert(!dup.ok && dup.error.code === 'ALREADY_REGISTERED', '중복 등록 허용됨');
      });

      await t('7. 한도가 충분한 경우 불필요한 변경 안내 없음', async () => {
        resetTo((d) => (d.customer.transferLimit = 2000000));
        const r = await planNow();
        assert(ids(r.plan) === 'REGISTER_OTP,RETURN_TO_TRANSFER', '경로: ' + ids(r.plan));
        const reply = await bot.respond('이체한도 어디서 바꿔?');
        assert(reply.text.indexOf('변경하지 않아도') !== -1, '응답: ' + reply.text);
      });

      await t('8. 계좌 제한 상태에서 해결 경로 생성 없음', async () => {
        resetTo((d) => (d.customer.accountRestricted = true));
        const r = await planNow();
        assert(r.plan.status === 'BLOCKED' && r.plan.steps.length === 0, '상태: ' + r.plan.status);
        assert(r.plan.blocker.ruleId === 'R05', '규칙: ' + r.plan.blocker.ruleId);
        const reply = await bot.respond('이체가 왜 안 돼?');
        assert(reply.links.every((l) => l.flowId === 'support'), '상담 외 링크 제공됨');
        const otp = await bank.registerDigitalOtp();
        assert(!otp.ok, '제한 상태에서 OTP 등록 허용됨');
      });

      await t('9. 은행 장애 시 정상 처리로 표시하지 않음', async () => {
        resetTo((d) => (d.system.bankAvailable = false));
        const r = await planNow();
        assert(!r.ok && r.plan.status === 'BLOCKED' && r.plan.blocker.ruleId === 'R06', '장애가 정상 진단으로 처리됨');
        const v = await bank.validateTransfer();
        assert(!v.ok && v.error.kind === 'QUERY_FAILURE', '조회 실패 구분 안 됨');
        const s = await bank.submitTransfer(Object.assign({}, store.getState().transfer, { requestId: bank.newRequestId() }));
        assert(!s.ok && s.error.submitted === false && txCount() === 0, '장애 중 거래 실행됨');
        resetTo((d) => (d.simulation.queryFailure = true));
        const q = await bank.getCustomerState();
        assert(!q.ok && q.error.kind === 'QUERY_FAILURE', '조회 실패 주입 미동작');
      });

      await t('10. 자연어 질문이 현재 은행 상태에 따라 다르게 응답', async () => {
        resetTo();
        const q = 'OTP 등록했는데 150만원 이체가 안 돼요.';
        const a = await bot.respond(q);
        const intents = a.analysis.intents.map((i) => i.id);
        assert(intents.indexOf('OTP_REGISTRATION') !== -1 && intents.indexOf('TRANSFER_FAILURE') !== -1, '복합 의도: ' + intents.join(','));
        assert(a.text.indexOf('아직 등록되지 않은') !== -1, '은행 상태 우선 실패: ' + a.text);
        const first = await bot.respond('이체가 왜 안 돼?');
        assert(first.text.indexOf('먼저 OTP 등록을 진행한 뒤 한도를 변경해 주세요') !== -1, '초기 응답: ' + first.text);
        await bank.registerDigitalOtp();
        const b = await bot.respond(q);
        assert(b.text.indexOf('디지털 OTP 등록이 확인되었습니다') !== -1 && b.text.indexOf('한도 변경이 필요') !== -1, 'OTP 후 응답: ' + b.text);
        assert(a.text !== b.text, '상태 변화에도 응답 동일');
        await bank.changeTransferLimit(1500000);
        const c = await bot.respond('이체가 왜 안 돼?');
        assert(c.text.indexOf('사전 조건을 충족') !== -1, '충족 후 응답: ' + c.text);
      });

      await t('11. UNKNOWN 거래를 성공으로 표시하지 않음 (중복 요청 차단)', async () => {
        resetTo((d) => {
          d.customer.digitalOtpRegistered = true;
          d.customer.transferLimit = 2000000;
          d.simulation.nextTransferOutcome = 'UNKNOWN';
        });
        const f = testFsm();
        ['MANUAL_DIAGNOSE', 'NO_ACTION_NEEDED', 'USER_APPROVED'].forEach((ev) => f.transition(ev));
        const req = Object.assign({}, store.getState().transfer, { requestId: bank.newRequestId() });
        const first = await bank.submitTransfer(req);
        assert(first.ok && first.data.transaction.status === 'UNKNOWN', 'UNKNOWN 응답 아님');
        f.transition('RESULT_UNKNOWN');
        assert(f.state === 'ESCALATED' && f.state !== 'COMPLETED', 'FSM: ' + f.state);
        const again = await bank.submitTransfer(req);
        assert(again.ok && again.data.duplicate === true && txCount() === 1, '중복 거래 생성됨');
        assert(store.getState().account.balance === WSP.initialBankState.account.balance, 'UNKNOWN인데 잔액 차감됨');
      });

      await t('12. 데모 초기화 후 모든 상태 정상 복원', async () => {
        store.update((d) => {
          d.customer.digitalOtpRegistered = true;
          d.customer.transferLimit = 9000000;
          d.system.bankAvailable = false;
        }, '[TEST] 임의 변경');
        store.reset('[TEST] 초기화');
        assert(JSON.stringify(store.getState()) === JSON.stringify(WSP.initialBankState), '초기 상태와 다름');
      });

      await t('FSM: 정의되지 않은 상태 전이 거부', async () => {
        const f = testFsm();
        assert(!f.transition('USER_APPROVED').ok && f.state === 'IDLE', 'IDLE에서 승인 전이 허용됨');
        assert(!f.transition('RESULT_SUCCESS').ok, 'IDLE에서 완료 전이 허용됨');
      });

      await t('경로 탐색: 기본 시나리오는 정책 가중치 합이 최소인 경로(비용 6)', async () => {
        resetTo(() => {});
        const r = await planNow();
        const w = WSP.DEMO_POLICY.actionWeights;
        const expected = w.REGISTER_OTP + w.CHANGE_TRANSFER_LIMIT + w.RETURN_TO_TRANSFER;
        assert(r.plan.cost === expected, '비용: ' + r.plan.cost + ' (기대 ' + expected + ')');
        assert(r.plan.graph && r.plan.graph.edges.some((e) => e.onPath), '그래프/경로 표시 정보 없음');
      });

      await t('다익스트라: 단계 수가 적어도 비용이 큰 경로는 고르지 않음', async () => {
        const node = (key, goal) => ({ key: key, facts: {}, depth: 0, goal: !!goal });
        const edge = (from, to, weight) => ({ from: from, to: to, actionId: from + to, weight: weight });
        const g = {
          startKey: 'S',
          nodes: new Map([['S', node('S')], ['A', node('A')], ['G', node('G', true)]]),
          adjacency: new Map([['S', [edge('S', 'G', 10), edge('S', 'A', 1)]], ['A', [edge('A', 'G', 1)]], ['G', []]]),
        };
        const r = PF.dijkstra(g);
        assert(r.found && r.cost === 2 && r.prev.get('G').from === 'A', '비용: ' + r.cost);
      });

      await t('경로 탐색: 고객확인 미완료 시 고객확인 → OTP → 한도 순서 계산', async () => {
        resetTo((d) => (d.customer.kycCompleted = false));
        const r = await planNow();
        assert(ids(r.plan) === 'COMPLETE_KYC,REGISTER_OTP,CHANGE_TRANSFER_LIMIT,RETURN_TO_TRANSFER', '경로: ' + ids(r.plan));
      });

      await t('경로 탐색: OTP 기준 이하 금액은 OTP를 요구하지 않음', async () => {
        resetTo((d) => {
          d.transfer.amount = 800000;
          d.customer.transferLimit = 500000;
        });
        const r = await planNow();
        assert(ids(r.plan) === 'CHANGE_TRANSFER_LIMIT,RETURN_TO_TRANSFER', '경로: ' + ids(r.plan));
      });

      await t('경로 탐색: 유효 경로가 없으면 상담 안내 (한도 변경 불가)', async () => {
        resetTo((d) => (d.customer.transferLimitChangeAllowed = false));
        const r = await planNow();
        assert(r.plan.status === 'NO_PATH' && r.plan.fallback.id === 'ESCALATE_TO_SUPPORT', '상태: ' + r.plan.status);
      });

      await t('NLU: 해석할 수 없는 질문은 임의 답변 없이 상담 안내', async () => {
        const reply = await bot.respond('오늘 날씨 어때?');
        assert(reply.analysis.intents[0].id === 'UNKNOWN', '의도: ' + reply.analysis.intents[0].id);
        assert(reply.links.length === 1 && reply.links[0].flowId === 'support', '링크 오류');
      });

      await t('NLU: 금액·진술 추출', async () => {
        const a = bot.analyze('OTP 등록했는데 150만원 이체가 안 돼요.');
        assert(a.amount === 1500000 && a.claims.otpRegistered === true, '추출 실패');
        assert(bot.analyze('1,500,000원 보내고 싶어').amount === 1500000, '숫자 금액 추출 실패');
        assert(bot.analyze('백오십만원 보내고 싶어').amount === 1500000, '한글 금액 추출 실패');
      });

      await t('NLU: 이체 결과 문의 의도 인식', async () => {
        const ids = (q) => bot.analyze(q).intents.map((i) => i.id);
        assert(ids('방금 보낸 이체 처리됐어?').indexOf('TRANSFER_STATUS') !== -1, '처리 여부 문의 미인식');
        assert(ids('송금 결과 알려줘').indexOf('TRANSFER_STATUS') !== -1, '결과 문의 미인식');
      });

      await t('화면 연결: 허용목록 외 flowId 차단', async () => {
        assert(bank.resolveFlow('https://example.com') === null, '외부 URL 허용됨');
        assert(bank.resolveFlow('otp-registration') === 'otp', '허용 화면 매핑 실패');
      });

      await t('Mock Bank: 정책 위반 한도 변경 거절', async () => {
        resetTo();
        const r = await bank.changeTransferLimit(1500000);
        assert(!r.ok && r.error.code === 'OTP_REQUIRED_FOR_LIMIT' && r.error.kind === 'BUSINESS_REJECT', '거절되지 않음');
      });
    } finally {
      store.setSilent(false);
      bank.setLatencyScale(latency);
      WSP.pathfinder.setLastResult(lastPath);
      WSP.fsm.restore(fsmState, fsmHistory);
      WSP.app.replaceSession(session);
      store.replace(snapshot, '[TEST] 자가 테스트 종료 · 실행 전 상태 복원');
    }

    const passed = results.filter((r) => r.ok).length;
    const report = { total: results.length, passed: passed, failed: results.length - passed, results: results };
    WSP.events.add('TEST', '자가 테스트 ' + passed + '/' + results.length + ' 통과');
    console.info('[WSP SelfTest] ' + passed + '/' + results.length + ' 통과');
    if (report.failed) console.table(results.filter((r) => !r.ok));
    window.__WSP_SELFTEST__ = report;
    return report;
  }

  WSP.selfTest = { run: run };

  if (/[?&]selftest=1/.test(location.search)) {
    setTimeout(() => run(), 300);
  }
})();
