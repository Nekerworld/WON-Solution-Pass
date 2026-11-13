/**
 * flows/joinFlow.js
 * 가입 지원 - AI와 함께 (상태머신 join)
 * - 자동 단계(CHECKING, CLARIFYING, ROUTE_CHECK, RECHECKING, APPLYING, VERIFYING)는 advance()가 은행 조회로 진행한다.
 *   새로고침 후에도 같은 단계를 은행 재조회로 이어 간다.
 * - 고객 응답이 필요한 단계에서는 멈추고 화면이 동작을 기다린다.
 * - 조건 판정은 ruleEngine, 경로는 pathfinder, 문장·질문은 aiAgent가 맡는다.
 * - 업무 모달을 닫으면 결과와 상관없이 은행 조건을 다시 조회한다.
 * - 가입 요청은 고객이 승인 화면에서 승인했을 때만 보낸다.
 */
(function () {
  'use strict';

  const WSP = window.WSP;
  const SC = WSP.scenario;
  const bank = WSP.mockBank;
  const RE = WSP.ruleEngine;
  const PF = WSP.pathfinder;
  const AI = WSP.aiAgent;
  const A = () => WSP.app;
  const UI = () => WSP.ui;
  const fsm = () => WSP.app.fsms.join;
  const S = () => WSP.app.session.join;

  const SCREENS = ['join', 'apply', 'apply-result', 'support', 'home'];
  const AUTO = ['CHECKING', 'CLARIFYING', 'ROUTE_CHECK', 'RECHECKING', 'APPLYING', 'VERIFYING', 'TASK_OPEN', 'OPTIONS_READY', 'REMAINING', 'INVESTIGATING'];

  function fresh(productId, ctx) {
    return {
      caseId: WSP.utils.newId('JOIN'),
      productId: productId,
      assetContext: ctx || null,
      constraints: { hasIdCard: null, hasMobileId: null, hasOtherBankAccount: null },
      constraintSource: {},
      skipped: [],
      chat: [],
      thinking: false,
      evaluation: null,
      route: null,
      options: [],
      presentedKey: null,
      pendingKey: null,
      questionsAsked: 0,
      currentTask: null,
      lastTask: null,
      tasks: [],
      repeat: {},
      exception: null,
      escalation: null,
      consult: null,
      terms: null,
      requestId: null,
      appId: null,
      application: null,
      applyNotice: null,
      metrics: { startedAt: Date.now(), endedAt: null, questions: 0, tasks: 0, screens: 1 },
    };
  }

  /* ---------------- 대화 ---------------- */
  function push(msg) {
    const j = S();
    if (!j) return;
    j.chat.push(Object.assign({ id: j.chat.length + 1, at: Date.now() }, msg));
    if (j.chat.length > 80) j.chat.shift();
  }

  function sayAI(res, extra) {
    push(Object.assign({ role: 'ai', text: res.output.message, fallback: res.fallback, errors: res.errors }, extra || {}));
  }

  function sayUser(text) {
    push({ role: 'user', text: text });
  }

  function saySystem(text, tone) {
    push({ role: 'system', text: text, tone: tone || null });
  }

  function think(on) {
    const j = S();
    if (j) j.thinking = !!on;
    A().refresh(SCREENS);
  }

  function stale(ep) {
    return ep !== A().epoch() || !S();
  }

  function product() {
    return SC.getProduct(S().productId);
  }

  function setConstraint(key, value, source, note) {
    const j = S();
    const prev = j.constraints[key];
    j.constraints[key] = value;
    j.constraintSource[key] = { source: source, note: note || '' };
    WSP.events.add('JOIN', '고객 제약 ' + key + ' = ' + value + ' (' + source + ')');
    return prev !== null && prev !== undefined && prev !== value;
  }

  /* ---------------- 시작 / 동의 / 종료 ---------------- */
  function start(productId, ctx) {
    const f = fsm();
    if (f.state !== 'IDLE') return false;
    WSP.app.session.join = fresh(productId, ctx);
    f.transition('START', { productId: productId });
    return true;
  }

  async function agree() {
    if (fsm().state !== 'CONSENT') return;
    fsm().transition('AGREE');
    S().metrics.screens += 1;
    UI().navigate('join', {}, { replace: true });
    await advance();
  }

  function doneTaskLabels() {
    const j = S();
    return j ? j.tasks.filter((t) => t.reflected).map((t) => SC.getTask(t.taskId).label) : [];
  }

  async function exit() {
    const f = fsm();
    if (!f.can('EXIT')) return;
    const done = doneTaskLabels();
    const ok = await UI().confirm({
      title: '가입 지원을 멈출까요?',
      bodyHtml:
        '<p>상품 가입은 진행되지 않아요.</p>' +
        (done.length
          ? '<p>지금까지 완료한 <strong>' + UI().esc(done.join(', ')) + '</strong>' + WSP.utils.josa(done.join(', '), '은').slice(done.join(', ').length) + ' 은행에 그대로 남아요. 다음에 다시 시작하면 남은 조건만 확인해요.</p>'
          : '<p>은행에 변경된 내용은 없어요.</p>'),
      confirmText: '멈추기',
      cancelText: '계속하기',
    });
    if (!ok || !f.can('EXIT')) return;
    f.transition('EXIT', { done: done });
    WSP.app.session.join = null;
    UI().navigate('home', {}, { resetHistory: true, back: true });
    UI().toast(done.length ? '완료한 업무는 유지돼요' : '가입 지원을 멈췄어요');
  }

  function newCase() {
    const f = fsm();
    if (!f.can('NEW_CASE')) return;
    const j = S();
    if (j && j.metrics.endedAt) WSP.app.session.lastMetrics.join = j.metrics;
    f.transition('NEW_CASE');
    WSP.app.session.join = null;
    UI().navigate('home', {}, { resetHistory: true, back: true });
  }

  /* ---------------- 자동 진행 ---------------- */
  let running = false;
  let again = false;

  async function advance() {
    if (running) {
      again = true;
      return;
    }
    running = true;
    try {
      do {
        again = false;
        await loop();
      } while (again);
    } finally {
      running = false;
      A().refresh(SCREENS);
    }
  }

  async function loop() {
    const ep = A().epoch();
    for (let i = 0; i < 24; i++) {
      if (stale(ep)) return;
      const st = fsm().state;
      if (st === 'CHECKING') await stepCheck(ep);
      else if (st === 'CLARIFYING') {
        if (await stepClarify(ep)) return;
      } else if (st === 'ROUTE_CHECK') await stepRoute(ep);
      else if (st === 'OPTIONS_READY' || st === 'REMAINING') {
        await stepPlanInPlace(ep);
        return;
      } else if (st === 'TASK_OPEN') {
        if (UI().isTaskModalOpen()) return;
        // 새로고침 등으로 모달이 사라진 경우: 닫힌 것으로 보고 재확인한다
        const ct = S().currentTask;
        if (ct) bank.cancelTask(ct.sessionId);
        fsm().transition('MODAL_CLOSED', { reason: 'RESUME' });
      } else if (st === 'RECHECKING') await stepRecheck(ep);
      else if (st === 'INVESTIGATING') {
        await stepInvestigate(ep);
        return;
      } else if (st === 'APPLYING') await stepApply(ep);
      else if (st === 'VERIFYING') await stepVerify(ep);
      else return;
    }
  }

  async function stepCheck(ep) {
    const j = S();
    think(true);
    const res = await Promise.all([bank.checkConditions(j.productId), bank.getLinkedAccounts()]);
    if (stale(ep)) return;
    const c = res[0];
    const l = res[1];
    j.evaluation = RE.evaluate(j.productId, c);
    if (!c.ok || !l.ok) {
      think(false);
      const e = (!c.ok ? c : l).error;
      WSP.events.add('JOIN', '은행 기록 조회 실패: ' + e.code, 'warn');
      saySystem('은행 기록을 확인하지 못했어요. 잠시 후 다시 확인해 주세요.', 'warning');
      fsm().transition('QUERY_FAILED', { code: e.code });
      return;
    }
    // 은행이 이미 아는 정보는 다시 묻지 않는다
    j.skipped = [];
    if (l.data.mobileOwnerVerified) j.skipped.push({ label: '휴대폰 본인 명의', reason: '로그인 시 확인됨' });
    if (l.data.otherBankAccounts.length) {
      const a = l.data.otherBankAccounts[0];
      setConstraint('hasOtherBankAccount', true, 'BANK', '마이데이터 연결 계좌 ' + a.bank + ' ' + a.masked);
      j.skipped.push({ label: '다른 은행 계좌', reason: '마이데이터로 확인됨 (' + a.bank + ')' });
    }
    if (j.skipped.length) WSP.events.add('AI', '묻지 않은 질문: ' + j.skipped.map((s) => s.label + '(' + s.reason + ')').join(', '));
    const ai = await AI.join.explainCheck(j.evaluation, { status: '-' });
    if (stale(ep)) return;
    think(false);
    sayAI(ai, { kind: 'check' });
    fsm().transition(j.evaluation.allMet ? 'NONE_MISSING' : 'MISSING', { unmet: j.evaluation.unmet });
  }

  /** @returns {boolean} 고객 답변을 기다려야 하면 true */
  async function stepClarify(ep) {
    const j = S();
    const route = PF.computeRoute(j.evaluation, j.constraints);
    j.route = route;
    if (route.status === 'BLOCKED') {
      escalate('BLOCKER', '앱 안에서 해결할 수 없는 가입 조건(' + route.blockers.map((id) => SC.CONDITIONS[id].label).join(', ') + ')이 있어요.');
      fsm().transition('ESCALATE', { reason: 'BLOCKER' });
      return false;
    }
    if (await askIfNeeded(ep, route)) return true;
    fsm().transition('CLARIFIED');
    return false;
  }

  /** P4: 경로 결정에 꼭 필요한 고객 사정만, 한도 안에서 묻는다 */
  async function askIfNeeded(ep, route) {
    const j = S();
    if (route.status !== 'PLAN' || !route.questions.length) {
      j.pendingKey = null;
      return false;
    }
    const key = route.questions[0];
    if (j.pendingKey === key) return true;
    if (j.questionsAsked >= SC.POLICY.joinQuestionLimit) {
      WSP.events.add('JOIN', '질문 한도 도달: 확인 안 된 사정은 선택지에서 고르게 함');
      j.pendingKey = null;
      return false;
    }
    think(true);
    const ai = await AI.join.ask(key, j.skipped);
    if (stale(ep)) return true;
    think(false);
    j.pendingKey = key;
    j.questionsAsked += 1;
    j.metrics.questions += 1;
    sayAI(ai, { kind: 'question', key: key, why: ai.output.why || AI.CONSTRAINT_WHY[key] });
    return true;
  }

  async function stepRoute(ep) {
    const j = S();
    const route = PF.computeRoute(j.evaluation, j.constraints);
    j.route = route;
    if (route.status === 'PLAN') {
      fsm().transition('ROUTE_FOUND', { steps: route.steps.map((s) => s.actionId) });
      return;
    }
    await noRoute(ep, route, 'NO_ROUTE');
  }

  async function noRoute(ep, route, event) {
    think(true);
    const ai = await AI.join.explainNoRoute(route.cause);
    if (stale(ep)) return;
    think(false);
    sayAI(ai, { kind: 'noroute', tone: 'warning' });
    escalate(route.cause && route.cause.type === 'CYCLE' ? 'CYCLE' : 'NO_ROUTE', ai.output.message, route.cause);
    fsm().transition(event, { cause: route.cause });
  }

  /** OPTIONS_READY / REMAINING: 경로를 다시 확인하고(P1) 필요한 질문 또는 선택지를 보여 준다 */
  async function stepPlanInPlace(ep) {
    const j = S();
    if (fsm().state === 'REMAINING' || !j.route || j.route.status !== 'PLAN') {
      j.route = PF.computeRoute(j.evaluation, j.constraints);
    }
    const route = j.route;
    if (route.status !== 'PLAN') {
      if (fsm().state === 'REMAINING') await noRoute(ep, route, 'NO_ROUTE');
      else await noRoute(ep, route, 'ESCALATE');
      return;
    }
    if (fsm().state === 'REMAINING' && (await askIfNeeded(ep, route))) return;
    const key = fsm().state + '|' + route.steps.map((s) => s.actionId).join('>') + '|' + route.options.map((o) => o.actionId + o.availability).join(',');
    if (j.presentedKey === key) return;
    think(true);
    const ai = await AI.join.present(route, j.evaluation);
    if (stale(ep)) return;
    think(false);
    const allowed = ai.valid ? ai.output.actions.find((a) => a.type === 'PRESENT_OPTIONS').options : null;
    j.options = route.options.map((o) => {
      const t = SC.getTask(o.actionId);
      return Object.assign({}, o, {
        minutes: t.minutes,
        prep: t.prep,
        desc: t.desc,
        shown: o.availability !== 'BLOCKED' && o.reachable && (!allowed || allowed.indexOf(o.actionId) !== -1),
      });
    });
    j.presentedKey = key;
    sayAI(ai, { kind: 'options', plan: route.steps.map((s) => s.label) });
  }

  /* ---------------- 고객 입력 ---------------- */
  async function sendText(text) {
    const t = String(text || '').trim();
    const j = S();
    if (!t || !j) return;
    const st = fsm().state;
    sayUser(t);
    A().refresh(SCREENS);
    const ep = A().epoch();
    think(true);
    const ai = await AI.join.interpret(t, { pendingKey: j.pendingKey });
    if (stale(ep)) return;
    think(false);
    const out = ai.output;
    const types = out.actions.map((a) => a.type);
    if (types.indexOf('ESCALATE') !== -1) {
      sayAI(ai);
      return requestConsult('CUSTOMER_REQUEST', '고객이 상담 연결을 요청했어요.');
    }
    if (types.indexOf('END') !== -1) {
      sayAI(ai);
      return exit();
    }
    if (out.intent === 'REPORT_MISMATCH') {
      sayAI(ai);
      return reportMismatch();
    }
    const sets = out.actions.filter((a) => a.type === 'SET_CONSTRAINT');
    if (!sets.length) {
      sayAI(ai);
      A().refresh(SCREENS);
      return;
    }
    let changed = false;
    sets.forEach((a) => {
      if (setConstraint(a.key, a.value, 'CUSTOMER', '"' + t + '"')) changed = true;
    });
    j.pendingKey = null;
    await afterConstraints(changed, st);
  }

  /** 질문 칩(예/아니오)으로 답한 경우 */
  async function answer(key, value) {
    const j = S();
    if (!j || !SC.CONSTRAINTS[key]) return;
    const st = fsm().state;
    sayUser(value ? '네, 있어요' : '아니요, 없어요');
    const changed = setConstraint(key, value, 'CUSTOMER', '질문 응답');
    j.pendingKey = null;
    await afterConstraints(changed, st);
  }

  async function afterConstraints(changed, st) {
    const j = S();
    if (st === 'OPTIONS_READY') {
      fsm().transition('CONSTRAINT_CHANGED', { changed: changed });
      j.presentedKey = null;
    } else if (st === 'REMAINING') {
      j.presentedKey = null;
      j.route = null;
    }
    await advance();
  }

  /** 고객이 "완료했다고 떴는데 다시 하래요"라고 말한 경우: 은행 기록으로 다시 확인한다 */
  async function reportMismatch() {
    const st = fsm().state;
    const j = S();
    if (st !== 'OPTIONS_READY' && st !== 'REMAINING') return;
    const ep = A().epoch();
    think(true);
    const c = await bank.checkConditions(j.productId);
    if (stale(ep)) return;
    think(false);
    j.evaluation = RE.evaluate(j.productId, c);
    const last = j.lastTask;
    if (last) {
      const t = SC.getTask(last.taskId);
      const f = Object.keys(t.effects)[0];
      if (c.ok && c.data.facts[f] !== true) {
        saySystem('은행 기록에서 ' + WSP.utils.josa(SC.FACTS[f].label, '이') + ' 아직 확인되지 않아요. 업무 화면 표시와 은행 기록이 달라요.', 'warning');
      }
    }
    j.presentedKey = null;
    j.route = null;
    await advance();
  }

  /** 선택지 선택 → 기존 업무 화면을 모달로 연다 */
  async function chooseOption(actionId) {
    const j = S();
    const st = fsm().state;
    if (!j || (st !== 'OPTIONS_READY' && st !== 'REMAINING')) return;
    const opt = j.options.find((o) => o.actionId === actionId);
    if (!opt || opt.availability === 'BLOCKED') {
      UI().toast('지금 선택할 수 없는 방법이에요.', 'warning');
      return;
    }
    const task = SC.getTask(actionId);
    // 이 방법을 고른 것은 필요한 준비물이 있다는 고객의 선택으로 기록한다
    opt.unknownNeeds.forEach((k) => setConstraint(k, true, 'CUSTOMER', '방법 선택: ' + task.label));
    const r = bank.openTask(actionId, { mode: 'modal' });
    if (!r.ok) {
      UI().toast(r.error.message, 'danger');
      return;
    }
    j.currentTask = { taskId: actionId, sessionId: r.data.sessionId, facts: Object.keys(task.effects) };
    j.metrics.tasks += 1;
    j.pendingKey = null;
    fsm().transition('TASK_OPENED', { taskId: actionId, sessionId: r.data.sessionId });
    UI().openTaskModal(actionId, r.data.sessionId, {
      mode: 'ai',
      onClose: (result) => modalClosed(result),
    });
  }

  async function modalClosed(result) {
    const j = S();
    if (!j || fsm().state !== 'TASK_OPEN') return;
    const ct = j.currentTask;
    if (ct && result && result.status === 'OPEN') bank.cancelTask(ct.sessionId);
    fsm().transition('MODAL_CLOSED', { status: result ? result.status : 'UNKNOWN' });
    await advance();
  }

  /* ---------------- 재확인 / 예외 ---------------- */
  async function stepRecheck(ep) {
    const j = S();
    think(true);
    const ct = j.currentTask;
    const tr = ct ? await bank.getTaskResult(ct.sessionId) : null;
    if (stale(ep)) return;
    const c = await bank.checkConditions(j.productId);
    if (stale(ep)) return;
    const ev = RE.evaluate(j.productId, c);
    j.evaluation = ev;
    const status = tr && tr.ok ? tr.data.status : null;

    let cause = null;
    if (!c.ok) cause = 'QUERY_FAILED';
    else if (ev.inProgress.length) cause = 'IN_PROGRESS';
    else if (status === 'ERROR') cause = 'ERROR';
    else if (ct && status === 'COMPLETED' && ct.facts.some((f) => ev.facts[f] !== true)) cause = 'MISMATCH';

    if (ct) {
      const reflected = c.ok && ct.facts.every((f) => ev.facts[f] === true);
      const rec = { taskId: ct.taskId, sessionId: ct.sessionId, status: status || 'UNKNOWN', reflected: reflected, at: Date.now() };
      const idx = j.tasks.findIndex((x) => x.sessionId === ct.sessionId);
      if (idx === -1) j.tasks.push(rec);
      else j.tasks[idx] = rec;
      j.lastTask = { taskId: ct.taskId, sessionId: ct.sessionId, status: status };
      if (cause === 'MISMATCH' || cause === 'ERROR') ct.facts.forEach((f) => (j.repeat[f] = (j.repeat[f] || 0) + 1));
    }
    j.presentedKey = null;
    j.route = null;

    if (cause) {
      j.exception = { cause: cause, taskId: ct ? ct.taskId : null, sessionId: ct ? ct.sessionId : null, facts: ct ? ct.facts : [], at: Date.now() };
      const ai = await AI.join.afterRecheck('EXCEPTION');
      if (stale(ep)) return;
      think(false);
      sayAI(ai, { tone: 'warning' });
      fsm().transition('EXCEPTION', { cause: cause });
      return;
    }
    j.currentTask = null;
    j.exception = null;
    if (ev.allMet) {
      const ai = await AI.join.afterRecheck('ALL_MET');
      if (stale(ep)) return;
      think(false);
      sayAI(ai, { kind: 'ready' });
      fsm().transition('ALL_MET');
      return;
    }
    let detail = '';
    if (status === 'CANCELLED') detail = '업무를 마치지 않고 닫으셨어요.';
    else if (status === 'PARTIAL') detail = '일부 단계만 저장돼서 아직 완료되지 않았어요.';
    else if (ct && status === 'COMPLETED') detail = WSP.utils.josa(SC.getTask(ct.taskId).label, '이') + ' 은행 기록에 반영됐어요.';
    const remain = ev.conditions.filter((x) => x.status !== 'MET').map((x) => x.label);
    const ai = await AI.join.afterRecheck('REMAINING', detail + ' 남은 조건은 ' + WSP.utils.josa(remain.join(', '), '이에요') + '.');
    if (stale(ep)) return;
    think(false);
    sayAI(ai);
    fsm().transition('REMAINING', { remain: ev.unmet });
  }

  async function stepInvestigate(ep) {
    const j = S();
    const ex = j.exception;
    if (!ex || ex.explained) return;
    const over = ex.facts.some((f) => (j.repeat[f] || 0) >= SC.POLICY.repeatLimit);
    if ((ex.cause === 'MISMATCH' || ex.cause === 'ERROR') && over) {
      const label = ex.taskId ? SC.getTask(ex.taskId).label : '업무';
      saySystem(WSP.utils.josa(label, '을') + ' ' + SC.POLICY.repeatLimit + '번 진행했지만 은행 기록에 반영되지 않았어요. 같은 업무를 계속 반복하지 않고 상담으로 연결할게요.', 'warning');
      escalate('REPEAT', label + ' 완료 후에도 은행 기록 미반영이 ' + SC.POLICY.repeatLimit + '회 반복됐어요.');
      fsm().transition('UNRESOLVABLE', { cause: ex.cause });
      return;
    }
    ex.explained = true;
    const text = {
      QUERY_FAILED: '은행 기록을 다시 조회하지 못했어요. 확인되지 않은 상태로 다음 단계로 넘어가지 않아요.',
      IN_PROGRESS: '업무가 은행에서 아직 처리 중이에요. 처리 결과를 조회해서 확인할게요.',
      ERROR: '업무 처리 중 오류가 났어요. 은행에 바뀐 내용은 없어요.',
      MISMATCH: '업무 화면에서는 완료로 표시됐지만 은행 기록에는 아직 반영되지 않았어요.',
    }[ex.cause];
    saySystem(text, 'warning');
    A().refresh(SCREENS);
  }

  /** 예외 화면의 버튼: requery | retry | consult */
  async function investigate(kind) {
    const j = S();
    if (!j || fsm().state !== 'INVESTIGATING') return;
    const ex = j.exception || {};
    const ep = A().epoch();
    if (kind === 'consult') {
      escalate('EXCEPTION', '업무 처리 결과를 확인하지 못했어요.');
      fsm().transition('UNRESOLVABLE', { cause: ex.cause, by: 'customer' });
      return A().refresh(SCREENS);
    }
    if (kind === 'retry') {
      sayUser('다시 진행할게요');
      j.currentTask = null;
      j.exception = null;
      fsm().transition('RETRY');
      return advance();
    }
    // requery: 처리 중이던 업무 결과를 조회하면 은행 처리가 끝났는지 알 수 있다
    sayUser('처리 결과 다시 확인해 주세요');
    if (ex.cause === 'IN_PROGRESS' && ex.sessionId) {
      think(true);
      const r = await bank.getTaskResult(ex.sessionId);
      if (stale(ep)) return;
      think(false);
      if (r.ok && r.data.status === 'IN_PROGRESS') {
        saySystem('아직 처리 중이에요. 잠시 후 다시 확인해 주세요.', 'warning');
        return A().refresh(SCREENS);
      }
    }
    j.exception = null;
    fsm().transition('RESOLVED');
    await advance();
  }

  /* ---------------- 상담 연결 ---------------- */
  function escalate(reason, text, cause) {
    const j = S();
    j.escalation = { reason: reason, text: text || '', cause: cause || null, at: Date.now() };
    j.consult = null;
    j.handoff = null;
    j.handoffConsent = false;
  }

  async function requestConsult(reason, text) {
    const f = fsm();
    if (f.state === 'INVESTIGATING') {
      await investigate('consult');
      UI().navigate('support', { track: 'join' });
      return;
    }
    if (!f.can('ESCALATE')) {
      UI().toast('지금 단계에서는 상담 연결 대신 진행 중인 처리를 먼저 확인해요.', 'warning');
      return;
    }
    escalate(reason, text);
    f.transition('ESCALATE', { reason: reason });
    A().refresh(SCREENS);
    UI().navigate('support', { track: 'join' });
  }

  async function recheckFromEscalated() {
    if (fsm().state !== 'ESCALATED') return;
    const j = S();
    j.escalation = null;
    j.presentedKey = null;
    fsm().transition('RECHECK');
    UI().navigate('join', {}, { backTo: true });
    await advance();
  }

  /* ---------------- 가입 신청 ---------------- */
  async function approve(terms) {
    const j = S();
    if (!j || fsm().state !== 'READY_TO_APPLY') return;
    const p = product();
    const ok = await UI().confirm({
      title: '가입을 승인할까요?',
      bodyHtml:
        UI().kvRows([
          ['상품', UI().esc(p.name)],
          ['월 납입액', WSP.utils.formatMan(terms.monthly)],
          ['가입 기간', terms.months + '개월'],
          ['출금 계좌', UI().esc(terms.account)],
        ]) + '<p class="fineprint">승인하시면 은행에 가입을 요청해요. 가입 완료는 은행 처리 결과로 확인해요.</p>',
      confirmText: '승인하고 가입 요청',
      cancelText: '취소',
    });
    if (!ok || fsm().state !== 'READY_TO_APPLY') return;
    j.terms = terms;
    if (!j.requestId) j.requestId = bank.newRequestId();
    j.applyNotice = null;
    fsm().transition('APPROVED', { requestId: j.requestId });
    UI().navigate('apply-result', { track: 'join' }, { replace: true });
    await advance();
  }

  async function stepApply(ep) {
    const j = S();
    const r = await bank.submitApplication({ requestId: j.requestId, productId: j.productId, terms: j.terms, channel: 'AI' });
    if (stale(ep)) return;
    if (!r.ok) {
      if (r.error.code === 'CONDITION_UNMET') {
        j.applyNotice = { tone: 'warning', text: '은행이 가입 조건을 다시 확인한 결과 충족하지 않은 조건이 있어요 (' + (r.error.unmet || []).join(', ') + '). 가입되지 않았어요.' };
        saySystem(j.applyNotice.text, 'warning');
        fsm().transition('REJECTED', { code: r.error.code });
        UI().navigate('join', {}, { replace: true });
        return;
      }
      j.applyNotice = { tone: 'warning', text: r.error.message + ' 같은 요청 번호로 다시 승인할 수 있어요.' };
      fsm().transition('NOT_SENT', { code: r.error.code });
      UI().navigate('apply', {}, { replace: true });
      return;
    }
    j.appId = r.data.application.id;
    j.application = r.data.application;
    fsm().transition('SUBMITTED', { appId: j.appId, duplicate: r.data.duplicate });
  }

  async function stepVerify(ep) {
    const j = S();
    const r = await bank.getApplicationResult(j.appId);
    if (stale(ep)) return;
    if (r.ok) j.application = r.data.application;
    const status = r.ok ? r.data.application.status : 'UNKNOWN';
    if (status === 'SUCCESS') {
      j.metrics.endedAt = Date.now();
      WSP.app.session.lastMetrics.join = j.metrics;
      fsm().transition('RESULT_SUCCESS', { appId: j.appId });
    } else if (status === 'FAILED') fsm().transition('RESULT_FAILED', { appId: j.appId });
    else fsm().transition('RESULT_UNKNOWN', { appId: j.appId, status: status });
  }

  async function queryResult() {
    if (fsm().state !== 'RESULT_UNCERTAIN') return;
    fsm().transition('RESULT_QUERY');
    await advance();
  }

  function escalateFailed() {
    if (fsm().state !== 'FAILED') return;
    escalate('APPLY_FAILED', (S().application && S().application.failureReason) || '은행이 가입 요청을 처리하지 못했어요.');
    fsm().transition('ESCALATE', { reason: 'APPLY_FAILED' });
    UI().navigate('support', { track: 'join' }, { replace: true });
  }

  /** 화면 진입 시: 처리 중이던 단계를 이어 간다 */
  function resume() {
    if (!S()) return;
    if (AUTO.indexOf(fsm().state) !== -1 && !running) advance();
  }

  /** 상담 인계 요약 재료 */
  function handoffContext() {
    const j = S();
    if (!j) return null;
    const ev = j.evaluation;
    const cons = Object.keys(j.constraints)
      .filter((k) => j.constraints[k] !== null)
      .map((k) => SC.CONSTRAINTS[k].label + ' ' + (j.constraints[k] ? '있음' : '없음'));
    return {
      reason: j.escalation ? j.escalation.reason : 'HANDOFF',
      reasonText: j.escalation ? j.escalation.text : '',
      productName: product().name,
      done: doneTaskLabels(),
      remaining: ev && ev.ok ? ev.conditions.filter((c) => c.status !== 'MET').map((c) => c.label) : ['은행 기록 미확인'],
      constraints: cons,
    };
  }

  WSP.joinFlow = {
    start: start,
    agree: agree,
    exit: exit,
    newCase: newCase,
    advance: advance,
    resume: resume,
    sendText: sendText,
    answer: answer,
    chooseOption: chooseOption,
    modalClosed: modalClosed,
    investigate: investigate,
    requestConsult: requestConsult,
    recheckFromEscalated: recheckFromEscalated,
    approve: approve,
    queryResult: queryResult,
    escalateFailed: escalateFailed,
    handoffContext: handoffContext,
    isRunning: () => running,
  };

  WSP.registerActions({
    'join-start'(d) {
      const f = fsm();
      const ctx = WSP.app.session.asset && WSP.app.session.asset.handoffTerms && d.from === 'asset' ? WSP.app.session.asset.handoffTerms : null;
      if (f.state !== 'IDLE') {
        if (S() && S().productId === d.product) {
          UI().navigate(f.state === 'CONSENT' ? 'join-consent' : 'join');
          return;
        }
        UI().toast('다른 상품의 가입 지원이 진행 중이에요. 홈에서 이어 가거나 멈춰 주세요.', 'warning');
        return;
      }
      if (start(d.product, ctx)) UI().navigate('join-consent');
    },
    'join-agree'() {
      return A().guard('join-agree', agree);
    },
    'join-exit'() {
      return exit();
    },
    'join-send'(d, el) {
      const input = UI().currentEl().querySelector('#join-input');
      const v = input ? input.value : '';
      if (input) input.value = '';
      return sendText(d.q || v);
    },
    'join-answer'(d) {
      return A().guard('join-answer', () => answer(d.key, d.value === 'true'));
    },
    'join-option'(d) {
      return A().guard('join-option', () => chooseOption(d.task));
    },
    'join-investigate'(d) {
      return A().guard('join-investigate', () => investigate(d.kind));
    },
    'join-retry-check'() {
      if (fsm().state !== 'CHECK_FAILED') return;
      fsm().transition('RETRY');
      return advance();
    },
    'join-consult'() {
      return requestConsult('CUSTOMER_REQUEST', '고객이 상담 연결을 요청했어요.');
    },
    'join-open-apply'() {
      if (fsm().state === 'READY_TO_APPLY') UI().navigate('apply');
    },
    'join-approve'() {
      const el = UI().currentEl();
      const monthly = Number(el.querySelector('[data-field="monthly"]').value.replace(/[^\d]/g, ''));
      const on = el.querySelector('[data-field="months"] .is-on');
      const months = on ? Number(on.dataset.value) : 0;
      const account = el.querySelector('[data-field="account"]').dataset.value;
      const p = product();
      if (!monthly || monthly < p.minMonthly || monthly > p.maxMonthly) {
        UI().toast('월 납입액은 ' + WSP.utils.formatMan(p.minMonthly) + '~' + WSP.utils.formatMan(p.maxMonthly) + ' 사이로 입력해 주세요.', 'warning');
        return;
      }
      if (!months) {
        UI().toast('가입 기간을 선택해 주세요.', 'warning');
        return;
      }
      return A().guard('join-approve', () => approve({ monthly: monthly, months: months, account: account }));
    },
    'join-query-result'() {
      return A().guard('join-query', queryResult);
    },
    'join-new'() {
      newCase();
    },
    'join-escalate-failed'() {
      escalateFailed();
    },
    'join-recheck'() {
      return A().guard('join-recheck', recheckFromEscalated);
    },
    'join-open'() {
      const st = fsm().state;
      if (st === 'IDLE') return;
      if (st === 'CONSENT') UI().navigate('join-consent');
      else if (st === 'ESCALATED') UI().navigate('support', { track: 'join' });
      else if (['APPLYING', 'VERIFYING', 'RESULT_UNCERTAIN', 'COMPLETED', 'FAILED'].indexOf(st) !== -1) UI().navigate('apply-result', { track: 'join' });
      else UI().navigate('join');
    },
  });
})();
