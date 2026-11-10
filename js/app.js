/**
 * app.js
 * 해결패스 오케스트레이터.
 * - 사용자 동작(data-action)을 받아 Mock Bank 조회 → 규칙 엔진 → 경로 탐색 → FSM 전이 → 화면 이동을 조율한다.
 * - 상태 전이는 반드시 fsm.transition()을 거친다. 테이블에 없는 전이는 거부된다.
 * - 이체는 사용자의 명시적 승인(확인 모달) 없이는 절대 요청하지 않는다.
 */
(function () {
  'use strict';

  const WSP = window.WSP;
  const store = WSP.store;
  const bank = WSP.mockBank;
  const RE = WSP.ruleEngine;
  const PF = WSP.pathfinder;
  const UI = WSP.ui;
  const events = WSP.events;
  const fmt = WSP.utils.formatWon;
  const man = WSP.utils.formatMan;

  const fsm = WSP.createFSM();
  const storage = WSP.utils.safeStorage();
  const SESSION_KEY = 'wsp.session.v1';

  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  function freshSession() {
    return {
      caseCtx: null,
      plan: null,
      resultCtx: null,
      returnedFromPass: false,
      chat: [],
      lastDraft: null,
      limitSelection: null,
      hideBalance: false,
      hideNotice: false,
    };
  }

  let session = freshSession();
  /** 데모 초기화 시 증가. 진행 중이던 비동기 흐름이 초기화 이후 상태를 건드리지 않게 한다. */
  let epoch = 0;

  function saveSession() {
    if (!storage) return;
    try {
      storage.setItem(SESSION_KEY, JSON.stringify({ fsm: fsm.state, history: fsm.history(), session: session }));
    } catch (e) {
      /* 무시 */
    }
  }

  function loadSession() {
    if (!storage) return;
    try {
      const raw = storage.getItem(SESSION_KEY);
      if (!raw) return;
      const d = JSON.parse(raw);
      session = Object.assign(freshSession(), d.session || {});
      fsm.restore(d.fsm || 'IDLE', d.history || []);
      // 진단/재확인 도중 새로고침된 경우: 일시 상태를 안정 상태로 복원한다.
      if (fsm.state === 'DIAGNOSING') {
        fsm.restore('IDLE', fsm.history());
        session.caseCtx = null;
        session.plan = null;
      } else if (fsm.state === 'RECHECKING') {
        fsm.restore(session.plan ? 'PLAN_READY' : 'IDLE', fsm.history());
      } else if (fsm.state === 'ESCALATED' && session.caseCtx && session.caseCtx.escalation && session.caseCtx.escalation.code === 'TRANSFER_UNKNOWN') {
        fsm.restore('RESULT_UNCERTAIN', fsm.history());
      }
      events.add('APP', '세션 복원 (FSM ' + fsm.state + ')');
    } catch (e) {
      session = freshSession();
    }
  }

  fsm.subscribe(() => saveSession());

  function isCaseActive() {
    return fsm.state !== 'IDLE';
  }

  function newCase(trigger, reasons) {
    const d = new Date();
    const ymd = d.getFullYear() + String(d.getMonth() + 1).padStart(2, '0') + String(d.getDate()).padStart(2, '0');
    session.caseCtx = {
      caseId: 'CASE-' + ymd + '-' + Math.random().toString(36).slice(2, 6).toUpperCase(),
      trigger: trigger,
      startedAt: Date.now(),
      reasons: reasons || [],
      timeline: [],
      escalation: null,
    };
    session.plan = null;
    session.resultCtx = null;
    session.returnedFromPass = false;
    events.add('APP', '새 해결 건 생성 ' + session.caseCtx.caseId + ' (' + trigger + ')');
  }

  function setEscalation(code) {
    if (session.caseCtx) session.caseCtx.escalation = { code: code, at: Date.now() };
  }

  function mergeTimeline(plan) {
    if (!session.caseCtx) return;
    plan.actionSteps.forEach((s) => {
      if (session.caseCtx.timeline.indexOf(s.actionId) === -1) session.caseCtx.timeline.push(s.actionId);
    });
  }

  /* ==================================================================
   * 상태 조회 → 규칙 평가 → 경로 탐색
   * ================================================================== */

  async function computeFromBank() {
    const res = await Promise.all([bank.getCustomerState(), bank.getTransferDraft()]);
    const failed = res.find((r) => !r.ok);
    if (failed) {
      return { ok: false, error: failed.error, plan: PF.planFromQueryFailure(failed.error) };
    }
    const snapshot = res[0].data;
    const draft = res[1].data.draft;
    session.lastDraft = draft;
    const ctx = RE.buildContext(snapshot, draft);
    const evaluation = RE.evaluate(ctx);
    const plan = PF.computePlan(evaluation);
    return { ok: true, snapshot: snapshot, draft: draft, transaction: res[1].data.transaction, evaluation: evaluation, plan: plan };
  }

  /** 계산된 계획을 FSM에 반영한다. @returns 'plan' | 'support' */
  function applyPlanToFsm(result) {
    const plan = result.plan;
    session.plan = plan;
    mergeTimeline(plan);
    if (plan.status === 'BLOCKED' || plan.status === 'NO_PATH') {
      const code = plan.status === 'NO_PATH' ? 'NO_PATH' : plan.blocker.code;
      setEscalation(code);
      fsm.transition('ESCALATE', { code: code });
      saveSession();
      return 'support';
    }
    if (session.caseCtx) session.caseCtx.escalation = null;
    if (plan.status === 'READY') fsm.transition(fsm.state === 'DIAGNOSING' ? 'NO_ACTION_NEEDED' : 'ALL_MET');
    else fsm.transition('PATH_FOUND', { steps: plan.steps.map((s) => s.actionId) });
    saveSession();
    return 'plan';
  }

  /* ==================================================================
   * 자동 진단 (하단 시트)
   * ================================================================== */

  const DIAG_ROWS = [
    ['request', '이체 요청 정보'],
    ['limit', '1일 이체한도'],
    ['otp', '디지털 OTP'],
    ['kyc', '고객확인'],
    ['account', '계좌 이용 상태'],
    ['balance', '출금 가능 잔액'],
  ];

  function diagnosisSheetHtml(isFailure) {
    return (
      '<h3 class="sheet__title">' +
      (isFailure ? '이체가 완료되지 않았어요' : '현재 상태를 확인하고 있어요') +
      '</h3><p class="sheet__desc">현재 설정을 확인하고 필요한 절차를 찾고 있습니다.</p>' +
      '<div class="check-list">' +
      DIAG_ROWS.map(
        (r) =>
          '<div class="check-row" data-row="' +
          r[0] +
          '"><span class="check-row__label">' +
          r[1] +
          '<small data-sub></small></span><span class="check-row__state"><span class="spinner"></span></span></div>'
      ).join('') +
      '</div><div id="diag-summary"></div>' +
      '<p class="fineprint">은행이 이미 보유한 정보로 확인해요. 따로 입력하실 내용은 없어요.</p>'
    );
  }

  function diagnosisRows(result) {
    if (!result.ok) {
      return DIAG_ROWS.map((r) => ({ key: r[0], sub: '', badge: ['확인 불가', 'neutral'] }));
    }
    const ev = result.evaluation;
    const c = ev.ctx;
    const f = ev.facts;
    const g = ev.goal;
    return [
      { key: 'request', sub: c.recipient + ' · ' + fmt(c.amount), badge: ['확인', 'info'] },
      { key: 'limit', sub: fmt(c.transferLimit), badge: f.limitSufficient ? ['충족', 'success'] : ['부족', 'warning'] },
      {
        key: 'otp',
        sub: c.otpRegistered ? '등록됨' : '미등록',
        badge: c.otpRegistered ? ['정상', 'success'] : g.otpRegistered ? ['등록 필요', 'warning'] : ['이번 이체엔 불필요', 'neutral'],
      },
      { key: 'kyc', sub: c.kycCompleted ? '완료' : '미완료', badge: c.kycCompleted ? ['정상', 'success'] : ['필요', 'warning'] },
      { key: 'account', sub: c.accountRestricted ? '제한 확인됨' : '정상', badge: c.accountRestricted ? ['제한', 'danger'] : ['정상', 'success'] },
      { key: 'balance', sub: fmt(c.balance), badge: c.balance >= c.amount ? ['충분', 'success'] : ['부족', 'danger'] },
    ];
  }

  async function revealDiagnosis(sheet, result) {
    const rows = diagnosisRows(result);
    for (let i = 0; i < rows.length; i++) {
      const r = rows[i];
      const row = sheet.querySelector('[data-row="' + r.key + '"]');
      if (!row) continue;
      row.querySelector('[data-sub]').textContent = r.sub;
      row.querySelector('.check-row__state').innerHTML = UI.badge(r.badge[0], r.badge[1]);
      await sleep(110);
    }
  }

  function diagnosisSummaryHtml(result, target) {
    const plan = result.plan;
    const reasons = (session.caseCtx && session.caseCtx.reasons) || [];
    const codes = reasons.map((r) => r.code).filter(Boolean);
    const codeLine = codes.length ? '<div class="step__note mt-8">은행 응답 사유: ' + codes.join(', ') + '</div>' : '';
    let html;
    let btn = '해결 계획 보기';
    if (!result.ok) {
      html =
        '<div class="notice notice--danger">' +
        UI.I.alert +
        '<div><strong>은행 상태를 확인할 수 없어 진단을 멈췄어요.</strong><br>정상 진단을 가장하지 않고 안내를 보류할게요.</div></div>';
      btn = '안내 보기';
    } else if (target === 'support') {
      const b = plan.blocker;
      const msg =
        plan.status === 'NO_PATH'
          ? '<strong>허용된 해결 경로를 찾지 못했어요.</strong><br>상담 절차로 안내할게요.'
          : b.code === 'ACCOUNT_RESTRICTED'
          ? '<strong>계좌 이용 제한이 확인되었어요.</strong><br>자동 해결 경로를 만들지 않고 공식 상담 절차로 안내할게요.'
          : '<strong>' + UI.esc(b.title) + '</strong><br>' + UI.esc(b.guidance);
      html = '<div class="notice notice--danger">' + UI.I.alert + '<div>' + msg + '</div></div>';
      btn = '안내 보기';
    } else if (plan.status === 'READY') {
      html = '<div class="notice notice--success">' + UI.I.check + '<div><strong>추가 조치 없이 이체할 수 있어요.</strong><br>원래 이체 정보를 그대로 유지했어요.</div></div>';
    } else {
      const n = plan.actionSteps.length;
      html =
        '<div class="notice notice--info">' +
        UI.I.spark +
        '<div><strong>확인 결과 ' +
        WSP.chatbot.countWord(n) +
        ' 가지 조치가 필요해요.</strong><br>' +
        plan.evaluation.requirements.map((r) => UI.esc(r.title)).join(' · ') +
        '</div></div>';
    }
    return '<div class="diag-summary">' + html + codeLine + '<button class="btn btn--primary btn--block mt-12" data-action="diag-continue">' + btn + '</button></div>';
  }

  /**
   * 진단 요약을 보여 준 뒤 사용자의 선택을 기다린다.
   * 'continue': 요약의 버튼을 눌러 다음 화면으로 진행
   * 'dismissed': 시트를 닫음(배경 클릭, 데모 초기화 등) → 현재 화면에 머문다
   */
  let continueResolver = null;
  function waitForContinue() {
    return new Promise((resolve) => {
      const done = (v) => {
        if (continueResolver !== done) return;
        continueResolver = null;
        resolve(v);
      };
      continueResolver = done;
      UI.setSheetDismissible(true);
    });
  }

  function resolveContinue(value) {
    if (continueResolver) continueResolver(value);
  }

  let diagnosing = false;

  /**
   * 오류 발생(TRANSFER_FAILED) 또는 수동 확인(MANUAL) 시 자동 진단을 실행한다.
   * 사용자에게 원인을 묻지 않고, 은행 상태를 조회해 모든 원인을 한 번에 찾는다.
   */
  async function startDiagnosis(trigger, reasons) {
    if (diagnosing) return;
    const st = fsm.state;
    if (st === 'VERIFYING' || st === 'RESULT_UNCERTAIN') {
      openResult();
      return;
    }
    if (st === 'DIAGNOSING' || st === 'RECHECKING') return;

    diagnosing = true;
    try {
      const d0 = await bank.getTransferDraft();
      const tx0 = d0.ok ? d0.data.transaction : null;
      if (tx0 && (tx0.status === 'PENDING' || tx0.status === 'UNKNOWN')) {
        UI.toast('처리 결과를 확인 중인 이체가 있어요. 중복 출금을 막기 위해 결과부터 확인할게요.', 'warning');
        await openResult();
        return;
      }
      if (fsm.state === 'COMPLETED') fsm.transition('NEW_CASE');
      if (fsm.state === 'IDLE') {
        newCase(trigger, reasons);
        fsm.transition(trigger === 'TRANSFER_FAILED' ? 'TRANSFER_FAILED' : 'MANUAL_DIAGNOSE', {
          reasons: (reasons || []).map((r) => r.code),
        });
      } else if (fsm.can('RECHECK')) {
        if (session.caseCtx && reasons) session.caseCtx.reasons = reasons;
        fsm.transition('RECHECK', { trigger: trigger });
      } else {
        return;
      }

      const myEpoch = epoch;
      const sheet = UI.openSheet(diagnosisSheetHtml(trigger === 'TRANSFER_FAILED'), {
        onClose: () => resolveContinue('dismissed'),
      });
      const started = Date.now();
      const result = await computeFromBank();
      const elapsed = Date.now() - started;
      if (elapsed < 650) await sleep(650 - elapsed);
      if (myEpoch !== epoch) return;
      await revealDiagnosis(sheet, result);
      if (myEpoch !== epoch) return;
      const target = applyPlanToFsm(result);
      const summary = sheet.querySelector('#diag-summary');
      if (summary) summary.innerHTML = diagnosisSummaryHtml(result, target);
      const choice = await waitForContinue();
      if (myEpoch !== epoch) return;
      if (choice !== 'continue') {
        events.add('APP', '진단 결과 확인 후 시트를 닫음 (해결패스에서 다시 볼 수 있음)');
        UI.toast('진단 결과는 홈의 해결패스에서 다시 볼 수 있어요.');
        return;
      }
      UI.closeSheet();
      if (target === 'support') await UI.navigate('support', {});
      else await UI.navigate('plan', {});
    } finally {
      diagnosing = false;
    }
  }

  /* ==================================================================
   * 해결 단계 화면 연결 / 복귀 / 재확인
   * ================================================================== */

  const STEP_FLOWS = { 'otp-registration': 'REGISTER_OTP', 'limit-management': 'CHANGE_TRANSFER_LIMIT', 'kyc-flow': 'COMPLETE_KYC' };

  /** 허용목록에 있는 내부 화면만 연다 (open_native 개념) */
  function openFlow(flowId) {
    const screenId = bank.resolveFlow(flowId);
    if (!screenId) {
      events.add('APP', '차단된 화면 연결 요청: ' + flowId);
      UI.toast('허용되지 않은 화면 연결이에요.', 'danger');
      return;
    }
    if (flowId === 'transfer') return returnToTransfer();
    if (flowId === 'transfer-result') return openResult();
    if (STEP_FLOWS[flowId] && fsm.state === 'PLAN_READY') {
      fsm.transition('STEP_SELECTED', { action: STEP_FLOWS[flowId] });
    }
    return UI.navigate(screenId, {});
  }

  async function runRecheck(prevPlan) {
    const myEpoch = epoch;
    const started = Date.now();
    const result = await computeFromBank();
    const elapsed = Date.now() - started;
    if (elapsed < 700) await sleep(700 - elapsed);
    if (myEpoch !== epoch || fsm.state !== 'RECHECKING') return;
    const target = applyPlanToFsm(result);
    if (target === 'support') {
      UI.toast('자동 안내를 멈추고 상담 절차로 안내할게요.', 'warning');
      await UI.navigate('support', {}, { replace: true });
      return;
    }
    const prevIds = prevPlan ? prevPlan.actionSteps.map((s) => s.actionId) : [];
    const nowIds = result.plan.actionSteps.map((s) => s.actionId);
    const resolved = prevIds.filter((id) => nowIds.indexOf(id) === -1).map((id) => PF.getAction(id).label);
    let msg;
    let tone;
    if (result.plan.status === 'READY') {
      msg = (resolved.length ? resolved.join(', ') + ' 완료를 확인했어요. ' : '') + '모든 사전 조건을 충족했어요.';
      tone = 'success';
    } else if (resolved.length) {
      msg = resolved.join(', ') + ' 완료를 은행에서 확인했어요. 남은 경로를 다시 계산했어요.';
      tone = 'success';
    } else {
      msg = '아직 바뀐 상태가 없어요. 남은 절차를 진행해 주세요.';
    }
    const cur = UI.current();
    if (cur && cur.id === 'plan') await UI.rerender({ rechecking: false });
    else await UI.navigate('plan', {}, { backTo: true });
    UI.toast(msg, tone);
  }

  /** 해결 단계 화면에서 해결패스로 돌아온다 → 이전 상태를 믿지 않고 재조회 */
  async function returnFromFlow() {
    if (fsm.state !== 'WAITING_USER') {
      UI.goBack();
      return;
    }
    const prev = session.plan;
    fsm.transition('USER_RETURNED');
    await UI.navigate('plan', { rechecking: true }, { backTo: true });
    await runRecheck(prev);
  }

  function leaveFlow() {
    if (fsm.state === 'WAITING_USER') {
      returnFromFlow();
      return true;
    }
    return false;
  }

  async function planRecheck() {
    if (!session.plan || !isCaseActive()) return startDiagnosis('MANUAL');
    if (fsm.state === 'WAITING_USER') return returnFromFlow();
    if (!fsm.can('RECHECK')) {
      UI.toast('지금은 다시 확인할 수 없는 단계예요.');
      return;
    }
    const prev = session.plan;
    fsm.transition('RECHECK', { trigger: 'PLAN_REFRESH' });
    await UI.rerender({ rechecking: true });
    await runRecheck(prev);
  }

  function openPass() {
    const st = fsm.state;
    if (st === 'PLAN_READY' || st === 'READY_TO_RETRY') return UI.navigate('plan', {});
    if (st === 'WAITING_USER') return returnFromFlow();
    if (st === 'VERIFYING' || st === 'RESULT_UNCERTAIN') return openResult();
    if (st === 'ESCALATED') {
      const code = session.caseCtx && session.caseCtx.escalation && session.caseCtx.escalation.code;
      if (code === 'TRANSFER_FAILED') return openResult();
      return UI.navigate('support', {});
    }
    return startDiagnosis('MANUAL');
  }

  /** RETURN_TO_TRANSFER: 실제 송금이 아니라 원래 이체 화면으로 복귀하는 행동 */
  async function returnToTransfer() {
    const st = fsm.state;
    if (st === 'READY_TO_RETRY') {
      session.returnedFromPass = true;
      saveSession();
      events.add('APP', 'RETURN_TO_TRANSFER: 원래 이체 화면으로 복귀 (자동 실행 없음)');
      return UI.navigate('transfer', { returned: true }, { backTo: true });
    }
    if (st === 'IDLE' || st === 'COMPLETED') return UI.navigate('transfer', {});
    if (st === 'VERIFYING' || st === 'RESULT_UNCERTAIN') return openResult();
    if (st === 'WAITING_USER' || fsm.can('RECHECK')) {
      fsm.transition(st === 'WAITING_USER' ? 'USER_RETURNED' : 'RECHECK');
      const result = await computeFromBank();
      const target = applyPlanToFsm(result);
      if (fsm.state === 'READY_TO_RETRY') return returnToTransfer();
      UI.toast('아직 남은 절차가 있어요. 해결 계획을 확인해 주세요.');
      return UI.navigate(target === 'support' ? 'support' : 'plan', {});
    }
  }

  /* ==================================================================
   * 해결 단계 실행 (기존 은행 업무 화면 시뮬레이션)
   * ================================================================== */

  function progressAnimator() {
    const rows = () => {
      const el = UI.currentEl();
      return el ? Array.from(el.querySelectorAll('#flow-progress [data-step]')) : [];
    };
    const mark = (row) => {
      row.classList.add('is-done');
      row.querySelector('.dot').innerHTML = '<span class="done-mark">' + UI.I.check + '</span>';
    };
    let i = 0;
    const timer = setInterval(() => {
      const rs = rows();
      if (i < rs.length - 1) {
        mark(rs[i]);
        i++;
      }
    }, 280);
    return {
      async finish(success) {
        clearInterval(timer);
        if (!success) return;
        const rs = rows();
        for (; i < rs.length; i++) {
          mark(rs[i]);
          await sleep(150);
        }
        await sleep(250);
      },
    };
  }

  let flowBusy = false;

  async function registerOtp(btn) {
    if (flowBusy) return;
    flowBusy = true;
    try {
      UI.setLoading(btn, true);
      await UI.navigate('otp', { phase: 'processing' }, { replace: true, animate: false });
      const anim = progressAnimator();
      const r = await bank.registerDigitalOtp();
      await anim.finish(r.ok);
      if (r.ok) await UI.navigate('otp', { phase: 'done', stateVersion: r.data.stateVersion }, { replace: true, animate: false });
      else await UI.navigate('otp', { error: r.error.message }, { replace: true, animate: false });
    } finally {
      flowBusy = false;
    }
  }

  async function completeKyc(btn) {
    if (flowBusy) return;
    flowBusy = true;
    try {
      UI.setLoading(btn, true);
      await UI.navigate('kyc', { phase: 'processing' }, { replace: true, animate: false });
      const anim = progressAnimator();
      const r = await bank.completeKyc();
      await anim.finish(r.ok);
      if (r.ok) await UI.navigate('kyc', { phase: 'done', stateVersion: r.data.stateVersion }, { replace: true, animate: false });
      else await UI.navigate('kyc', { error: r.error.message }, { replace: true, animate: false });
    } finally {
      flowBusy = false;
    }
  }

  function digitsOf(v) {
    return Number(String(v || '').replace(/[^\d]/g, '')) || 0;
  }

  async function limitCheck(btn) {
    const input = document.getElementById('limit-custom');
    const custom = input ? digitsOf(input.value) : 0;
    const value = custom || session.limitSelection;
    if (!value) {
      UI.toast('변경할 한도를 선택하거나 입력해 주세요.');
      return;
    }
    UI.setLoading(btn, true);
    const r = await bank.checkLimitChange(value);
    if (!r.ok) {
      UI.setLoading(btn, false);
      UI.toast(r.error.message, 'danger');
      return;
    }
    await UI.rerender({ selected: value, custom: custom || null, check: { allowed: r.data.allowed, reasons: r.data.reasons, value: value } });
  }

  async function limitApply(btn, value) {
    if (flowBusy) return;
    flowBusy = true;
    try {
      UI.setLoading(btn, true);
      const r = await bank.changeTransferLimit(Number(value));
      if (r.ok) {
        await UI.navigate(
          'limit',
          { phase: 'done', newLimit: r.data.transferLimit, previousLimit: r.data.previousLimit, stateVersion: r.data.stateVersion },
          { replace: true, animate: false }
        );
      } else {
        await UI.rerender({ check: { allowed: false, reasons: r.error.reasons || [r.error], value: Number(value) } });
      }
    } finally {
      flowBusy = false;
    }
  }

  /* ==================================================================
   * 이체 시도 / 사용자 승인 / 결과 검증
   * ================================================================== */

  let transferBusy = false;

  async function flushAmountInput() {
    const input = document.getElementById('amount-input');
    if (!input || input.disabled) return true;
    const n = digitsOf(input.value);
    if (!n) {
      UI.toast('보낼 금액을 입력해 주세요.');
      return false;
    }
    const r = await bank.updateTransferAmount(n);
    if (!r.ok && r.error.kind === 'BUSINESS_REJECT') {
      UI.toast(r.error.message, 'warning');
      return false;
    }
    return true;
  }

  async function attemptTransfer(btn) {
    if (transferBusy) return;
    transferBusy = true;
    UI.setLoading(btn, true);
    let diagnoseWith = null;
    try {
      if (!(await flushAmountInput())) return;
      const d = await bank.getTransferDraft();
      if (!d.ok) {
        diagnoseWith = [{ code: d.error.code, message: d.error.message }];
        return;
      }
      const draft = d.data.draft;
      const tx = d.data.transaction;
      if (tx && (tx.status === 'PENDING' || tx.status === 'UNKNOWN' || tx.status === 'SUCCESS')) {
        openResult();
        return;
      }
      const v = await bank.validateTransfer(draft);
      if (!v.ok) {
        diagnoseWith = [{ code: v.error.code, message: v.error.message }];
        return;
      }
      if (!v.data.valid) {
        events.add('BANK', '이체 사전 검사 실패: ' + v.data.reasons.map((r) => r.code).join(', '));
        diagnoseWith = v.data.reasons;
        return;
      }
      UI.setLoading(btn, false);
      const approved = await UI.confirm({
        title: UI.esc(draft.recipient) + '님에게<br>' + fmt(draft.amount) + '을 보낼까요?',
        bodyHtml:
          UI.kvRows([
            ['출금 계좌', UI.esc(draft.fromAccount)],
            ['받는 분', UI.esc(draft.recipient)],
            ['받는 은행', UI.esc(draft.recipientBank) + ' ' + UI.esc(draft.recipientAccount)],
            ['보낼 금액', '<strong>' + fmt(draft.amount) + '</strong>'],
          ]) + '<p class="fineprint">보내기를 누르기 전에는 이체가 실행되지 않아요. (가상 거래)</p>',
        confirmText: '보내기',
        cancelText: '취소',
      });
      if (!approved) {
        events.add('APP', '사용자가 이체 승인을 취소함 (거래 미실행)');
        return;
      }
      await approveAndSubmit(draft);
    } finally {
      transferBusy = false;
      if (btn && btn.isConnected) UI.setLoading(btn, false);
      if (diagnoseWith) await startDiagnosis('TRANSFER_FAILED', diagnoseWith);
    }
  }

  function applyTxToFsm(tx) {
    const rc = session.resultCtx;
    if (!rc || !rc.viaPass || rc.transactionId !== tx.id) return;
    if (fsm.state !== 'VERIFYING') return;
    if (tx.status === 'SUCCESS') fsm.transition('RESULT_SUCCESS', { transactionId: tx.id });
    else if (tx.status === 'FAILED') {
      setEscalation('TRANSFER_FAILED');
      fsm.transition('RESULT_FAILED', { transactionId: tx.id });
    } else if (tx.status === 'UNKNOWN') {
      setEscalation('TRANSFER_UNKNOWN');
      fsm.transition('RESULT_UNKNOWN', { transactionId: tx.id });
    }
    // PENDING: VERIFYING 유지, 결과 조회만 허용
    saveSession();
  }

  async function approveAndSubmit(draft) {
    let viaPass = fsm.state !== 'IDLE' && fsm.state !== 'COMPLETED';
    if (fsm.state === 'COMPLETED') fsm.transition('NEW_CASE');

    if (viaPass && fsm.state !== 'READY_TO_RETRY') {
      if (fsm.state === 'WAITING_USER') fsm.transition('USER_RETURNED');
      else if (fsm.can('RECHECK')) fsm.transition('RECHECK', { trigger: 'BEFORE_APPROVAL' });
      else {
        UI.toast('진행 중인 확인이 끝난 뒤 다시 시도해 주세요.');
        return;
      }
      const result = await computeFromBank();
      const target = applyPlanToFsm(result);
      if (fsm.state !== 'READY_TO_RETRY') {
        await UI.navigate(target === 'support' ? 'support' : 'plan', {});
        return;
      }
    }
    if (viaPass) fsm.transition('USER_APPROVED', { amount: draft.amount });

    const requestId = draft.requestId && draft.status !== 'FAILED' ? draft.requestId : bank.newRequestId();
    events.add('APP', '사용자 승인 → 이체 요청 ' + requestId);
    await UI.navigate('result', { processing: true });

    const res = await bank.submitTransfer(Object.assign({}, draft, { requestId: requestId }));
    session.returnedFromPass = false;

    if (!res.ok) {
      if (res.error.kind === 'BUSINESS_REJECT' && res.error.reasons) {
        if (viaPass && fsm.state === 'VERIFYING') {
          setEscalation('TRANSFER_REJECTED');
          fsm.transition('ESCALATE', { code: 'TRANSFER_REJECTED' });
        }
        UI.toast('이체 조건이 바뀌어 거래가 실행되지 않았어요. 상태를 다시 확인할게요.', 'warning');
        await UI.navigate('transfer', {}, { backTo: true });
        await startDiagnosis('TRANSFER_FAILED', res.error.reasons);
        return;
      }
      if (viaPass && fsm.state === 'VERIFYING') {
        setEscalation('BANK_UNAVAILABLE');
        fsm.transition('ESCALATE', { code: res.error.code });
      }
      await UI.navigate('result', { notSent: true, message: res.error.message }, { replace: true, animate: false });
      return;
    }

    const tx = res.data.transaction;
    session.resultCtx = { transactionId: tx.id, viaPass: viaPass, duplicate: res.data.duplicate };
    applyTxToFsm(tx);
    saveSession();
    await UI.navigate('result', { transactionId: tx.id, duplicate: res.data.duplicate }, { replace: true, animate: false });
  }

  function currentTxId() {
    if (session.resultCtx && session.resultCtx.transactionId) return session.resultCtx.transactionId;
    return session.lastDraft && session.lastDraft.transactionId;
  }

  async function openResult() {
    let id = currentTxId();
    if (!id) {
      const d = await bank.getTransferDraft();
      if (d.ok) id = d.data.draft.transactionId;
    }
    return UI.navigate('result', { transactionId: id });
  }

  /** 거래 결과 조회 전용. 재전송하지 않는다. */
  async function queryResult(btn) {
    const id = currentTxId();
    if (!id) return;
    UI.setLoading(btn, true);
    const rc = session.resultCtx;
    let movedFromUncertain = false;
    if (rc && rc.viaPass && rc.transactionId === id && fsm.state === 'RESULT_UNCERTAIN') {
      movedFromUncertain = fsm.transition('RESULT_QUERY', { transactionId: id }).ok;
    }
    const r = await bank.getTransferResult(id);
    if (!r.ok) {
      if (movedFromUncertain) fsm.transition('RESULT_UNKNOWN', { transactionId: id, reason: 'QUERY_FAILURE' });
      if (btn && btn.isConnected) UI.setLoading(btn, false);
      UI.toast('결과를 조회하지 못했어요. 다시 이체하지 말고 잠시 후 조회해 주세요.', 'warning');
      return;
    }
    const tx = r.data.transaction;
    applyTxToFsm(tx);
    await UI.navigate('result', { transactionId: id }, { replace: true, animate: false });
    const msg = {
      SUCCESS: ['은행 성공 응답을 확인했어요.', 'success'],
      PENDING: ['아직 처리 중이에요. 잠시 후 다시 조회해 주세요.', undefined],
      UNKNOWN: ['아직 결과가 확정되지 않았어요.', 'warning'],
      FAILED: ['실패로 확인되었어요. 출금되지 않았어요.', 'danger'],
    }[tx.status];
    UI.toast(msg[0], msg[1]);
  }

  /* ==================================================================
   * 기타 동작
   * ================================================================== */

  async function supportConnect() {
    const ok = await UI.confirm({
      title: '상담 연결에 동의하시겠어요?',
      bodyHtml:
        '해결패스가 확인한 상태와 안내된 절차만 상담사에게 전달돼요. 비밀번호·OTP 번호 같은 인증 정보는 전달되지 않아요.<p class="fineprint">시연용 시뮬레이션이며 실제 상담이 연결되지 않습니다.</p>',
      confirmText: '동의하고 연결',
      cancelText: '취소',
    });
    if (!ok) return;
    events.add('APP', '상담 연결 요청 (시뮬레이션) ' + (session.caseCtx ? session.caseCtx.caseId : ''));
    UI.toast('상담 연결을 요청했어요. (시연용 시뮬레이션)', 'success');
  }

  async function showAccountDetail() {
    const res = await Promise.all([bank.getCustomerState(), bank.getTransactions()]);
    if (!res[0].ok) {
      UI.toast(res[0].error.message, 'danger');
      return;
    }
    const c = res[0].data;
    const txs = res[1].ok ? res[1].data.transactions : [];
    const txHtml = txs.length
      ? txs
          .slice(0, 5)
          .map((t) => '<div class="tx-item"><div>' + UI.esc(t.recipient) + '<div class="tx-item__sub">' + UI.esc(t.id) + ' · ' + t.status + '</div></div><div class="tx-item__amount">' + fmt(t.amount) + '</div></div>')
          .join('')
      : '<div class="empty">최근 거래가 없어요</div>';
    UI.openSheet(
      '<h3 class="sheet__title">계좌 조회</h3><p class="sheet__desc">가상 계좌 정보예요.</p>' +
        '<div class="card card--outline mt-12">' +
        UI.kvRows([
          ['계좌', UI.esc(c.accountName)],
          ['계좌번호', UI.esc(c.accountNumber)],
          ['잔액', fmt(c.balance)],
        ]) +
        '</div><div class="section"><div class="section-title">최근 거래</div><div class="card card--outline card--tight"><div class="tx-list">' +
        txHtml +
        '</div></div></div><button class="btn btn--secondary btn--block mt-16" data-action="sheet-close">닫기</button>',
      { dismissible: true }
    );
  }

  let chatBusy = false;

  async function sendChat(text) {
    const q = String(text || '').trim();
    if (!q || chatBusy) return;
    chatBusy = true;
    try {
      const input = document.getElementById('chat-input');
      if (input) input.value = '';
      const userMsg = { role: 'user', text: q };
      session.chat.push(userMsg);
      UI.chatAppend(userMsg);
      UI.chatTyping(true);
      const started = Date.now();
      let reply;
      try {
        reply = await WSP.chatbot.respond(q);
      } catch (e) {
        console.error(e);
        reply = { text: '답변을 준비하는 중 문제가 발생했어요. 상담을 이용해 주세요.', links: [{ label: '상담 연결 안내', flowId: 'support' }], tone: 'warning' };
      }
      const el = Date.now() - started;
      if (el < 450) await sleep(450 - el);
      UI.chatTyping(false);
      const botMsg = {
        role: 'bot',
        text: reply.text,
        links: reply.links || [],
        tone: reply.tone,
        analysis: reply.analysis ? { intents: reply.analysis.intents, amount: reply.analysis.amount } : null,
        ruleIds: reply.ruleIds || [],
        stateVersion: reply.stateVersion,
      };
      session.chat.push(botMsg);
      if (session.chat.length > 40) session.chat = session.chat.slice(-40);
      UI.chatAppend(botMsg);
      saveSession();
    } finally {
      chatBusy = false;
    }
  }

  /**
   * 결과 화면을 떠나면 사건을 종료한다(NEW_CASE → IDLE).
   * 전이 테이블상 COMPLETED·ESCALATED에서만 가능하며, VERIFYING·RESULT_UNCERTAIN은 그대로 남는다.
   */
  function closeCaseOnLeaveResult() {
    const cur = UI.current();
    if (!cur || cur.id !== 'result' || !fsm.can('NEW_CASE')) return;
    const from = fsm.state;
    fsm.transition('NEW_CASE', { closedFrom: from });
    events.add('APP', '결과 확인 후 사건 종료 (' + from + ' → IDLE)');
    saveSession();
  }

  function goHome() {
    closeCaseOnLeaveResult();
    return UI.navigate('home', {}, { resetHistory: true, back: true });
  }

  function resetDemo(opts) {
    const o = opts || {};
    epoch += 1;
    resolveContinue('dismissed');
    UI.closeAllOverlays();
    store.reset('데모 초기화');
    fsm.reset();
    session = freshSession();
    saveSession();
    if (!o.noNavigate) UI.navigate('home', {}, { resetHistory: true, animate: false });
    if (!o.silent) UI.toast('데모가 초기 상태로 복원되었어요.');
  }

  /* ==================================================================
   * 입력 / 동작 위임
   * ================================================================== */

  function onInput(name, el) {
    if (name === 'amount') {
      const n = digitsOf(el.value.slice(0, 13));
      el.value = n ? n.toLocaleString('ko-KR') : '';
      const hint = document.getElementById('amount-hint');
      if (hint) hint.textContent = n ? man(n) : '보낼 금액을 입력해 주세요';
    } else if (name === 'limit-custom') {
      const n = digitsOf(el.value.slice(0, 13));
      el.value = n ? n.toLocaleString('ko-KR') : '';
    }
  }

  function onCommit(name, el) {
    if (name === 'amount' && !el.disabled) {
      const n = digitsOf(el.value);
      if (n) bank.updateTransferAmount(n);
    }
  }

  function amountAdd(v) {
    const input = document.getElementById('amount-input');
    if (!input || input.disabled) return;
    const n = digitsOf(input.value) + Number(v);
    input.value = n.toLocaleString('ko-KR');
    onInput('amount', input);
    bank.updateTransferAmount(n);
  }

  function amountClear() {
    const input = document.getElementById('amount-input');
    if (!input || input.disabled) return;
    input.value = '';
    onInput('amount', input);
    input.focus();
  }

  const ACTIONS = {
    back: () => UI.back(),
    'go-home': goHome,
    'go-transfer': () => UI.navigate('transfer', {}),
    'go-chat': () => UI.navigate('chat', {}),
    'open-pass': openPass,
    diagnose: () => startDiagnosis('MANUAL'),
    'diag-continue': () => resolveContinue('continue'),
    'open-flow': (d) => openFlow(d.flow),
    'flow-return': returnFromFlow,
    'return-to-transfer': returnToTransfer,
    'plan-recheck': planRecheck,
    'transfer-submit': (d, el) => attemptTransfer(el),
    'amount-add': (d) => amountAdd(d.v),
    'amount-clear': amountClear,
    'open-result': openResult,
    'query-result': (d, el) => queryResult(el),
    'otp-register': (d, el) => registerOtp(el),
    'kyc-complete': (d, el) => completeKyc(el),
    'limit-select': (d) => UI.rerender({ selected: Number(d.v), check: null, custom: null }),
    'limit-check': (d, el) => limitCheck(el),
    'limit-apply': (d, el) => limitApply(el, d.v),
    'go-support': (d) => UI.navigate('support', { code: d.code }),
    'support-connect': supportConnect,
    'chat-send': () => {
      const input = document.getElementById('chat-input');
      return sendChat(input ? input.value : '');
    },
    'chat-suggest': (d) => sendChat(d.q),
    'chat-reset': () => {
      session.chat = [];
      saveSession();
      return UI.rerender();
    },
    'toggle-balance': () => {
      session.hideBalance = !session.hideBalance;
      saveSession();
      return UI.rerender();
    },
    'notice-close': () => {
      session.hideNotice = true;
      saveSession();
      return UI.rerender();
    },
    'account-detail': showAccountDetail,
    'sheet-close': () => UI.closeSheet(),
    'reload-screen': () => UI.rerender(),
    noop: () => UI.toast('프로토타입 시연 범위 밖의 기능이에요.'),
  };

  function dispatch(name, data, el, e) {
    const fn = ACTIONS[name];
    if (!fn) {
      console.warn('[WSP] 알 수 없는 동작: ' + name);
      return;
    }
    try {
      const r = fn(data || {}, el, e);
      if (r && typeof r.catch === 'function') {
        r.catch((err) => {
          console.error(err);
          UI.toast('처리 중 문제가 발생했어요.', 'danger');
        });
      }
    } catch (err) {
      console.error(err);
      UI.toast('처리 중 문제가 발생했어요.', 'danger');
    }
  }

  /* 홈 화면은 상태 변경 시 다시 그린다 (잔액, 거래, 진행 배너) */
  let homeTimer = null;
  function refreshHomeSoon() {
    clearTimeout(homeTimer);
    homeTimer = setTimeout(() => {
      const cur = UI.current();
      if (cur && cur.id === 'home') UI.rerender();
    }, 120);
  }
  store.subscribe(refreshHomeSoon);
  fsm.subscribe(refreshHomeSoon);

  WSP.fsm = fsm;
  WSP.app = {
    fsm: fsm,
    get session() {
      return session;
    },
    dispatch: dispatch,
    onInput: onInput,
    onCommit: onCommit,
    isCaseActive: isCaseActive,
    computeFromBank: computeFromBank,
    applyPlanToFsm: applyPlanToFsm,
    startDiagnosis: startDiagnosis,
    openFlow: openFlow,
    returnFromFlow: returnFromFlow,
    returnToTransfer: returnToTransfer,
    leaveFlow: leaveFlow,
    goHome: goHome,
    openResult: openResult,
    resetDemo: resetDemo,
    saveSession: saveSession,
    replaceSession: (s) => {
      session = Object.assign(freshSession(), s);
      saveSession();
    },
  };

  loadSession();
  UI.init();
  UI.navigate('home', {}, { resetHistory: true });
})();
