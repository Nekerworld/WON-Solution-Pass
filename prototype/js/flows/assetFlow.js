/**
 * flows/assetFlow.js
 * 자산관리 상담 (상태머신 asset)
 * 목표 확인 → 정보 수집 → 출처 구분 → 지표 계산 → 해석 → 부족·모순 확인 → (질문) → 제안 → 검토 → 다음 행동
 * - 계산은 assetAdvisor의 고정 공식, 문장은 aiAgent.
 * - 질문은 한도(3회) 안에서만 하고, 모름·답변 거부·질문 중단 요청이면 현재 정보로 제안 가능 여부를 판단한다.
 * - 방향을 고르는 것은 가입이 아니다. 상품 가입은 고객이 상품을 고른 뒤 가입 지원 트랙에서 따로 진행한다.
 */
(function () {
  'use strict';

  const WSP = window.WSP;
  const bank = WSP.mockBank;
  const AA = WSP.assetAdvisor;
  const AI = WSP.aiAgent;
  const A = () => WSP.app;
  const UI = () => WSP.ui;
  const fsm = () => WSP.app.fsms.asset;
  const S = () => WSP.app.session.asset;
  const SCREENS = ['asset', 'explore', 'support', 'home'];
  const AUTO = ['COLLECTING', 'TAGGING', 'CALCULATING', 'INTERPRETING', 'GAP_CHECK', 'RECALC_ANSWER', 'RECALC_CHANGE', 'PROPOSABLE_CHECK', 'PROPOSED_FULL', 'PROPOSED_LIMITED'];

  function fresh() {
    return {
      caseId: WSP.utils.newId('ASSET'),
      purpose: 'GOAL_SAVING',
      goalText: '',
      stated: {},
      info: null,
      coverage: null,
      metrics: null,
      gaps: [],
      questionsAsked: 0,
      stopRequested: false,
      pendingQuestion: null,
      chat: [],
      thinking: false,
      proposal: null,
      hold: null,
      escalation: null,
      consult: null,
      handoffTerms: null,
      closedReason: null,
    };
  }

  function push(msg) {
    const a = S();
    if (!a) return;
    a.chat.push(Object.assign({ id: a.chat.length + 1, at: Date.now() }, msg));
    if (a.chat.length > 80) a.chat.shift();
  }
  const sayAI = (res, extra) => push(Object.assign({ role: 'ai', text: res.output.message, fallback: res.fallback }, extra || {}));
  const sayUser = (text) => push({ role: 'user', text: text });
  const saySystem = (text, tone) => push({ role: 'system', text: text, tone: tone || null });

  function think(on) {
    const a = S();
    if (a) a.thinking = !!on;
    A().refresh(SCREENS);
  }

  function stale(ep) {
    return ep !== A().epoch() || !S();
  }

  /* ---------------- 시작 ---------------- */
  function start() {
    const f = fsm();
    if (f.state === 'CLOSED' || f.state === 'TO_JOIN') f.transition('NEW_CASE');
    if (f.state !== 'IDLE') return false;
    WSP.app.session.asset = fresh();
    f.transition('START');
    return true;
  }

  function agree() {
    if (fsm().state !== 'CONSENT') return;
    fsm().transition('AGREE');
    push({ role: 'ai', text: '어떤 목표로 상담받고 싶으세요? 생활 언어로 편하게 말씀해 주세요. 예: "2년 뒤 결혼 자금 모으고 싶어요"' });
    UI().navigate('asset', {}, { replace: true });
  }

  async function setGoal(text) {
    const a = S();
    const t = String(text || '').trim();
    if (!a || !t || fsm().state !== 'GOAL') return;
    sayUser(t);
    const ep = A().epoch();
    think(true);
    const ai = await AI.asset.goal(t);
    if (stale(ep)) return;
    think(false);
    a.goalText = t;
    a.purpose = ai.valid && ai.output.purpose ? ai.output.purpose : 'GOAL_SAVING';
    ai.output.actions.filter((x) => x.type === 'SET_INFO').forEach((x) => (a.stated[x.key] = x.value));
    sayAI(ai);
    fsm().transition('GOAL_SET', { purpose: a.purpose });
    await advance();
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
    for (let i = 0; i < 30; i++) {
      if (stale(ep)) return;
      const st = fsm().state;
      if (AUTO.indexOf(st) === -1) return;
      await step(st, ep);
    }
  }

  async function step(st, ep) {
    const a = S();
    const f = fsm();
    if (st === 'COLLECTING') {
      think(true);
      const r = await bank.getFinancialSnapshot();
      if (stale(ep)) return;
      think(false);
      if (!r.ok) {
        a.hold = { reason: 'QUERY_FAILED', text: '연결된 기관의 정보를 불러오지 못했어요. 확인되지 않은 정보로 분석하지 않아요.' };
        saySystem(a.hold.text + ' (' + r.error.message + ')', 'warning');
        f.transition('QUERY_FAILED', { code: r.error.code });
        return;
      }
      collect(r.data);
      f.transition('COLLECTED', { stateVersion: r.data.stateVersion });
    } else if (st === 'TAGGING') {
      think(true);
      const ai = await AI.asset.tag(a.info, a.coverage);
      if (stale(ep)) return;
      think(false);
      sayAI(ai, { kind: 'sources' });
      f.transition('TAGGED');
    } else if (st === 'CALCULATING' || st === 'RECALC_ANSWER' || st === 'RECALC_CHANGE') {
      a.metrics = AA.computeMetrics(a.info);
      WSP.events.add('ASSET', '지표 계산: ' + a.metrics.list.map((m) => m.key + '=' + (m.value == null ? '-' : m.value)).join(', '));
      f.transition(st === 'CALCULATING' ? 'CALCULATED' : 'RECALCULATED');
    } else if (st === 'INTERPRETING') {
      think(true);
      const ai = await AI.asset.interpret(a.metrics);
      if (stale(ep)) return;
      think(false);
      sayAI(ai, { kind: 'interpret' });
      f.transition('INTERPRETED');
    } else if (st === 'GAP_CHECK') {
      a.gaps = AA.findGaps(a.info, a.purpose, a.metrics);
      if (!a.gaps.length) return void f.transition('NO_GAP');
      if (AA.canAsk(a, a.gaps)) {
        const gap = a.gaps.find((g) => !!AA.questionFor(g));
        const q = AA.questionFor(gap);
        think(true);
        const ai = await AI.asset.ask(q, gap);
        if (stale(ep)) return;
        think(false);
        a.pendingQuestion = q.key;
        a.questionsAsked += 1;
        sayAI(ai, { kind: 'question', key: q.key, why: q.why, level: gap.level });
        f.transition('ASK', { question: q.id, level: gap.level });
        return;
      }
      WSP.events.add('ASSET', a.stopRequested ? '질문 중단 요청 → 현재 정보로 판단' : '질문 한도 도달 → 현재 정보로 판단');
      f.transition('LIMIT_OR_STOP');
    } else if (st === 'PROPOSABLE_CHECK') {
      const p = AA.proposable(a.info, a.purpose);
      if (p.ok) return void f.transition('PROPOSABLE');
      a.hold = {
        reason: 'INSUFFICIENT',
        missing: p.missing,
        text: '지금 정보로는 제안하기 어려워요. ' + WSP.utils.josa(p.missing.map((k) => AA.ITEMS[k].label).join('·'), '이') + ' 확인되지 않았어요.',
      };
      saySystem(a.hold.text, 'warning');
      f.transition('NOT_PROPOSABLE', { missing: p.missing });
    } else if (st === 'PROPOSED_FULL' || st === 'PROPOSED_LIMITED') {
      const level = st === 'PROPOSED_FULL' ? 'FULL' : 'LIMITED';
      const basis = AA.proposalBasis(a.info, a.purpose, a.metrics);
      think(true);
      const ai = await AI.asset.propose(basis, level, a.metrics);
      if (stale(ep)) return;
      think(false);
      a.proposal = { level: level, basis: basis, text: ai.output.message, at: Date.now() };
      sayAI(ai, { kind: 'proposal' });
      f.transition('SHOWN', { level: level });
    }
  }

  function collect(data) {
    const a = S();
    const prev = a.info;
    a.coverage = data.coverage;
    a.info = AA.createInfo(data.items);
    if (prev) {
      // 고객이 답하거나 고친 값은 다시 조회해도 유지하고, 이력도 이어 간다
      a.info.history = prev.history.slice();
      a.info.declined = prev.declined.slice();
      Object.keys(prev.items).forEach((k) => {
        if (prev.items[k].source === 'STATED') a.info.items[k] = prev.items[k];
      });
    }
    Object.keys(a.stated).forEach((k) => {
      if (!a.info.items[k] || a.info.items[k].source !== 'STATED') AA.setItem(a.info, k, a.stated[k], 'STATED', '상담 목표에서 확인');
    });
  }

  /* ---------------- 질문 응답 ---------------- */
  async function answerText(text) {
    const a = S();
    const t = String(text || '').trim();
    if (!a || !t) return;
    const st = fsm().state;
    if (st === 'GOAL') return setGoal(t);
    if (st === 'REVIEW') return modifyText(t);
    if (st !== 'ASKING') {
      sayUser(t);
      push({ role: 'ai', text: '지금 단계에서는 아래 버튼으로 선택해 주세요.' });
      return A().refresh(SCREENS);
    }
    sayUser(t);
    const ep = A().epoch();
    const q = AA.QUESTIONS[a.pendingQuestion];
    think(true);
    const ai = await AI.asset.answer(t, q);
    if (stale(ep) || fsm().state !== 'ASKING') return;
    think(false);
    sayAI(ai);
    await applyAnswer(ai.output, q);
  }

  async function applyAnswer(out, q) {
    const a = S();
    const f = fsm();
    const types = out.actions.map((x) => x.type);
    if (types.indexOf('END') !== -1) return exit();
    if (types.indexOf('STOP_QUESTIONS') !== -1 || types.indexOf('ESCALATE') !== -1) {
      a.stopRequested = true;
      a.pendingQuestion = null;
      if (types.indexOf('ESCALATE') !== -1) push({ role: 'ai', text: '지금까지 확인한 내용으로 정리한 뒤 상담 연결을 도와드릴게요.' });
      f.transition('STOP_REQUEST');
      return advance();
    }
    const hold = out.actions.find((x) => x.type === 'HOLD');
    if (hold && q) {
      AA.markDeclined(a.info, q.key, hold.reason);
      a.pendingQuestion = null;
      f.transition('UNKNOWN_OR_REFUSED', { key: q.key, kind: hold.reason });
      return advance();
    }
    const sets = out.actions.filter((x) => x.type === 'SET_INFO');
    if (!sets.length) return A().refresh(SCREENS);
    sets.forEach((x) => AA.setItem(a.info, x.key, x.value, 'STATED', '질문 응답'));
    a.pendingQuestion = null;
    f.transition('ANSWERED', { keys: sets.map((x) => x.key) });
    await advance();
  }

  /** 답변 칩: 범위 답변 */
  async function answerChip(value, label) {
    const a = S();
    if (!a || fsm().state !== 'ASKING') return;
    const q = AA.QUESTIONS[a.pendingQuestion];
    sayUser(label);
    if (value === 'UNKNOWN' || value === 'REFUSED') {
      push({ role: 'ai', text: value === 'UNKNOWN' ? '괜찮아요. 모르는 정보는 미확인으로 두고 진행할게요.' : '알겠어요. 답하지 않으신 정보는 미확인으로 두고 진행할게요.' });
      return applyAnswer({ actions: [{ type: 'HOLD', reason: value }] }, q);
    }
    if (value === 'STOP') {
      push({ role: 'ai', text: '질문은 그만할게요. 지금까지 확인한 정보로 판단해 볼게요.' });
      return applyAnswer({ actions: [{ type: 'STOP_QUESTIONS' }] }, q);
    }
    push({ role: 'ai', text: WSP.utils.josa(AA.ITEMS[q.key].label, '을') + ' ' + WSP.utils.josa(AA.display(q.key, Number(value)), '로') + ' 반영했어요.' });
    return applyAnswer({ actions: [{ type: 'SET_INFO', key: q.key, value: Number(value) }] }, q);
  }

  /* ---------------- 검토 ---------------- */
  function accept() {
    const a = S();
    if (fsm().state !== 'REVIEW') return;
    sayUser('이 방향으로 할게요');
    a.handoffTerms = {
      purpose: AA.PURPOSES[a.purpose].label,
      tags: a.proposal.basis.tags,
      monthly: a.proposal.basis.monthly,
      months: a.proposal.basis.months,
      goalText: a.goalText,
    };
    push({ role: 'ai', text: '방향을 정했어요. 방향을 고른 것만으로 상품에 가입되지는 않아요. 다음에 할 일을 골라 주세요.' });
    fsm().transition('ACCEPT');
    A().refresh(SCREENS);
  }

  async function modifyText(text) {
    const a = S();
    if (fsm().state !== 'REVIEW') return;
    sayUser(text);
    const ep = A().epoch();
    think(true);
    const ai = await AI.asset.modify(text);
    if (stale(ep) || fsm().state !== 'REVIEW') return;
    think(false);
    sayAI(ai);
    const sets = ai.output.actions.filter((x) => x.type === 'SET_INFO');
    if (!sets.length) return A().refresh(SCREENS);
    sets.forEach((x) => AA.setItem(a.info, x.key, x.value, 'STATED', '조건 수정: ' + text));
    fsm().transition('MODIFY', { keys: sets.map((x) => x.key) });
    await advance();
  }

  async function applyAlternative(id) {
    const a = S();
    if (fsm().state !== 'REVIEW' || !a.proposal) return;
    const alt = a.proposal.basis.alternatives.find((x) => x.id === id);
    if (!alt) return;
    sayUser(alt.label);
    const keys = Object.keys(alt.apply);
    if (!keys.length) {
      push({ role: 'ai', text: '비상자금을 먼저 채우는 방향은 상담사와 함께 구체적으로 정하는 걸 권해요. 다음 행동에서 상담 연결을 고를 수 있어요.' });
      return A().refresh(SCREENS);
    }
    keys.forEach((k) => AA.setItem(a.info, k, alt.apply[k], 'STATED', '조정안 선택: ' + alt.label));
    fsm().transition('MODIFY', { alternative: id });
    await advance();
  }

  /* ---------------- 다음 행동 ---------------- */
  function nextAction(kind) {
    const a = S();
    const f = fsm();
    if (kind === 'explore' && f.state === 'NEXT_ACTION') {
      f.transition('EXPLORE');
      UI().navigate('explore');
    } else if (kind === 'consult' && (f.state === 'NEXT_ACTION' || f.state === 'HOLD')) {
      a.escalation = { reason: f.state === 'HOLD' ? 'HOLD' : 'CUSTOMER_REQUEST', text: f.state === 'HOLD' ? (a.hold ? a.hold.text : '') : '고객이 전문 상담을 원했어요.' };
      a.consult = null;
      a.handoff = null;
      a.handoffConsent = false;
      f.transition('CONSULT');
      UI().navigate('support', { track: 'asset' });
    } else if (kind === 'keep' && f.state === 'NEXT_ACTION') {
      a.closedReason = 'KEEP';
      push({ role: 'ai', text: '지금은 유지하기로 했어요. 상담 내용은 언제든 다시 볼 수 있어요.' });
      f.transition('KEEP');
    } else if (kind === 'recheck' && (f.state === 'NEXT_ACTION' || f.state === 'HOLD')) {
      push({ role: 'ai', text: '현재 정보를 확인하고 틀린 값이 있으면 고쳐 주세요. 고친 값은 출처가 "고객 답변"으로 바뀌고 이력이 남아요.' });
      f.transition('RECHECK_INFO');
    }
    A().refresh(SCREENS);
  }

  /** RECONSULT: 정보 정정 후 다시 분석 */
  async function resumeAnalysis() {
    const a = S();
    if (fsm().state !== 'RECONSULT') return;
    if (!a.info) {
      const ep = A().epoch();
      think(true);
      const r = await bank.getFinancialSnapshot();
      if (stale(ep)) return;
      think(false);
      if (!r.ok) {
        UI().toast('아직 정보를 불러올 수 없어요. 잠시 후 다시 시도해 주세요.', 'danger');
        return;
      }
      collect(r.data);
    }
    a.metrics = AA.computeMetrics(a.info);
    a.hold = null;
    sayUser('다시 분석해 주세요');
    fsm().transition('RESUME');
    await advance();
  }

  function editItem(key, value) {
    const a = S();
    if (!a || !a.info || !AA.ITEMS[key]) return;
    AA.setItem(a.info, key, value, 'STATED', '고객 정정');
    WSP.events.add('ASSET', '정보 정정 ' + key + ' → ' + value);
    A().refresh(SCREENS);
  }

  function selectProduct(productId) {
    const st = fsm().state;
    if (st !== 'EXPLORE' && st !== 'TO_JOIN') return;
    if (st === 'EXPLORE') fsm().transition('PRODUCT_SELECTED', { productId: productId });
    UI().navigate('product', { productId: productId, from: 'asset' });
  }

  function backFromExplore() {
    if (fsm().state === 'EXPLORE') fsm().transition('BACK');
    else if (fsm().state === 'TO_JOIN') return UI().goBack();
    UI().navigate('asset', {}, { backTo: true });
  }

  function end() {
    const f = fsm();
    const a = S();
    if (f.can('END')) {
      if (a) a.closedReason = 'END';
      f.transition('END');
    } else if (f.can('EXIT')) {
      if (a) a.closedReason = 'EXIT';
      f.transition('EXIT');
    } else return;
    if (a) push({ role: 'ai', text: '상담을 마쳤어요. 상품 가입이나 이체 같은 변경은 하지 않았어요.' });
    A().refresh(SCREENS);
  }

  async function exit() {
    end();
  }

  function newCase() {
    const f = fsm();
    if (!f.can('NEW_CASE')) return;
    f.transition('NEW_CASE');
    WSP.app.session.asset = null;
    UI().navigate('home', {}, { resetHistory: true, back: true });
  }

  function resume() {
    if (S() && AUTO.indexOf(fsm().state) !== -1 && !running) advance();
  }

  function handoffContext() {
    const a = S();
    if (!a) return null;
    const lines = ['상담 목적: ' + AA.PURPOSES[a.purpose].label + (a.goalText ? ' ("' + a.goalText + '")' : '')];
    if (a.info) {
      const known = [];
      const unknown = [];
      Object.keys(a.info.items).forEach((k) => {
        const it = a.info.items[k];
        if (k === 'monthlySavingPref' && it.value == null) return;
        if (it.value == null) unknown.push(AA.ITEMS[k].label);
        else known.push(AA.ITEMS[k].label + ' ' + AA.display(k, it.value) + '(' + WSP.scenario.SOURCE_LABEL[it.source] + ')');
      });
      lines.push('확인된 정보: ' + known.join(', '));
      if (unknown.length) lines.push('미확인: ' + unknown.join(', '));
    }
    if (a.proposal) lines.push('제안: ' + a.proposal.text);
    if (a.escalation && a.escalation.text) lines.push('연결 사유: ' + a.escalation.text);
    return { reason: a.escalation ? a.escalation.reason : 'HANDOFF', lines: lines };
  }

  WSP.assetFlow = {
    start: start,
    agree: agree,
    setGoal: setGoal,
    advance: advance,
    resume: resume,
    answerText: answerText,
    answerChip: answerChip,
    accept: accept,
    modifyText: modifyText,
    applyAlternative: applyAlternative,
    nextAction: nextAction,
    resumeAnalysis: resumeAnalysis,
    editItem: editItem,
    selectProduct: selectProduct,
    backFromExplore: backFromExplore,
    end: end,
    newCase: newCase,
    handoffContext: handoffContext,
  };

  WSP.registerActions({
    'asset-start'() {
      const st = fsm().state;
      if (st === 'IDLE' || st === 'CLOSED' || st === 'TO_JOIN') {
        if (start()) UI().navigate('asset-consent');
        return;
      }
      UI().navigate(st === 'CONSENT' ? 'asset-consent' : st === 'EXPLORE' ? 'explore' : st === 'HANDOFF' ? 'support' : 'asset', st === 'HANDOFF' ? { track: 'asset' } : {});
    },
    'asset-agree'() {
      agree();
    },
    'asset-decline'() {
      if (fsm().can('EXIT')) fsm().transition('EXIT');
      if (fsm().can('NEW_CASE')) fsm().transition('NEW_CASE');
      WSP.app.session.asset = null;
      UI().navigate('home', {}, { resetHistory: true, back: true });
    },
    'asset-send'(d) {
      const input = UI().currentEl().querySelector('#asset-input');
      const v = d.q || (input ? input.value : '');
      if (input) input.value = '';
      return A().guard('asset-send', () => answerText(v));
    },
    'asset-chip'(d) {
      return A().guard('asset-send', () => answerChip(d.value, d.label));
    },
    'asset-accept'() {
      accept();
    },
    'asset-alt'(d) {
      return A().guard('asset-alt', () => applyAlternative(d.alt));
    },
    'asset-next'(d) {
      nextAction(d.kind);
    },
    'asset-resume'() {
      return A().guard('asset-resume', resumeAnalysis);
    },
    'asset-edit'(d) {
      const a = S();
      if (!a || !a.info) return;
      const key = d.key;
      const it = a.info.items[key];
      const isMonths = AA.ITEMS[key].kind === 'months';
      const sh = UI().openSheet(
        '<h3 class="sheet__title">' +
          UI().esc(AA.ITEMS[key].label) +
          ' 고치기</h3><p class="sheet__desc">현재 ' +
          UI().esc(AA.display(key, it.value)) +
          ' · 출처 ' +
          UI().esc(WSP.scenario.SOURCE_LABEL[it.source]) +
          '</p><label class="field"><span class="field__label">' +
          (isMonths ? '개월 수' : '금액(만원)') +
          '</span><input class="text-input" id="asset-edit-value" inputmode="numeric" value="' +
          (it.value == null ? '' : isMonths ? it.value : Math.round(it.value / 10000)) +
          '" /></label><div class="btn-row"><button class="btn btn--ghost" data-action="sheet-close">취소</button><button class="btn btn--primary" data-action="asset-edit-save" data-key="' +
          key +
          '">저장</button></div>',
        { dismissible: true }
      );
      const inp = sh.querySelector('input');
      if (inp) setTimeout(() => inp.focus(), 250);
    },
    'asset-edit-save'(d) {
      const sh = UI().getSheet();
      const raw = sh ? sh.querySelector('#asset-edit-value').value : '';
      const v = Number(String(raw).replace(/[^\d]/g, ''));
      if (!raw || isNaN(v)) {
        UI().toast('숫자로 입력해 주세요.', 'warning');
        return;
      }
      UI().closeSheet();
      editItem(d.key, AA.ITEMS[d.key].kind === 'months' ? v : v * 10000);
    },
    'asset-select-product'(d) {
      selectProduct(d.product);
    },
    'asset-explore-back'() {
      backFromExplore();
    },
    'asset-end'() {
      end();
    },
    'asset-new'() {
      newCase();
    },
    'asset-open'() {
      const st = fsm().state;
      if (st === 'IDLE') return;
      UI().navigate(st === 'CONSENT' ? 'asset-consent' : st === 'EXPLORE' ? 'explore' : st === 'HANDOFF' ? 'support' : 'asset', st === 'HANDOFF' ? { track: 'asset' } : {});
    },
    'sheet-close'() {
      UI().closeSheet();
    },
  });
})();
