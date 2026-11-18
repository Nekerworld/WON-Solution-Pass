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

  // 화면에 나오는 말 사이는 5초. 자가 테스트는 지연 배율 0이라 기다리지 않는다.
  let pacing = 0;
  // 인사 말이 나가기 전에 목표 칩이 눌리면 말이 순서가 뒤집힌다. 고객 동작은 한 줄로 잇는다.
  let tail = Promise.resolve();
  function enqueue(fn) {
    const run = tail.then(fn, fn);
    tail = run.then(
      () => {},
      () => {}
    );
    return run;
  }

  function scaleMs(ms) {
    return ms * bank.getLatencyScale();
  }

  /** 사용자 말이 들어오는 동안에는 로딩을 켜지 않는다. */
  async function waitUserSlide(ep) {
    const chat = S() && S().chat;
    const last = chat && chat[chat.length - 1];
    if (!last || last.role !== 'user') return true;
    const left = scaleMs(1000) - (Date.now() - last.at);
    if (left > 0) {
      think(false);
      await WSP.utils.sleep(left);
      if (stale(ep)) return false;
    }
    return true;
  }

  /** @returns {Promise<boolean>} 기다리는 동안 데모가 초기화됐으면 false */
  async function say(msg) {
    const ep = A().epoch();
    if (!(await waitUserSlide(ep))) return false;
    const thinkMs = scaleMs(1500);
    const easeMs = scaleMs(1000);
    if (thinkMs > 0) {
      pacing += 1;
      think(true);
      await WSP.utils.sleep(thinkMs);
      pacing -= 1;
      if (stale(ep)) return false;
    }
    if (!S()) return false;
    S().thinking = false;
    push(msg);
    A().refresh(SCREENS);
    if (easeMs > 0) {
      pacing += 1;
      await WSP.utils.sleep(easeMs);
      pacing -= 1;
      if (stale(ep)) return false;
    }
    return true;
  }
  const sayAI = (res, extra) => say(Object.assign({ role: 'ai', text: res.output.message, fallback: res.fallback }, extra || {}));
  const sayBot = (text, extra) => say(Object.assign({ role: 'ai', text: text }, extra || {}));
  const saySystem = (text, tone) => say({ role: 'system', text: text, tone: tone || null });
  const sayUser = (text) => push({ role: 'user', text: text });

  function think(on) {
    const a = S();
    if (a) a.thinking = !!on;
    A().refresh(SCREENS);
  }

  function stale(ep) {
    return ep !== A().epoch() || !S();
  }

  /** 상담에서 확인한 목표·참고 금액·계좌 정보를 가입 화면과 같은 객체에 둔다. */
  function syncContext(extra) {
    const a = S();
    if (!a) return;
    const known = [];
    if (a.info && a.info.items) {
      ['monthlyIncome', 'monthlyExpense', 'liquidAssets'].forEach((k) => {
        const it = a.info.items[k];
        if (!it || it.value == null || (it.source !== 'BANK' && it.source !== 'STATED')) return;
        known.push({
          label: AA.ITEMS[k].label,
          text: AA.display(k, it.value),
          source: it.source === 'BANK' ? '계좌' : '고객 답변',
        });
      });
    }
    const monthly = a.proposal && a.proposal.basis ? a.proposal.basis.monthly : a.handoffTerms ? a.handoffTerms.monthly : null;
    const patch = {
      goal: a.goalText || '',
      knownFromAccount: known,
    };
    if (monthly != null) patch.financialSummary = { monthly: monthly, source: '계좌 정보 기준', adjustable: true };
    A().publishContext(Object.assign(patch, extra || {}));
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
    if (S()) S().thinking = true;
    return enqueue(async () => {
      await UI().navigate('asset', {}, { replace: true });
      await say({ role: 'ai', text: '어떤 목표로 상담받고 싶으세요? 편하게 말씀해 주세요. 예: "2년 뒤 결혼 자금 모으고 싶어요"' });
    });
  }

  const COOKIE_BANNED = /종목|매수|매도|수익률|추천주|사세요/;

  function cookieLines(s) {
    const lines = [
      '해외주식 투자를 처음 시작해 보고 싶어요.',
      '비상자금이 충분한지 알고 싶어요.',
      '3년 안에 목돈을 모으려면 매달 얼마를 모아야 할까요?',
      '계좌에 있는 정보만으로, 자산관리를 어디부터 보면 좋을까요?',
    ];
    const items = s && s.finance && s.finance.items;
    const income = items && items.monthlyIncome;
    const expense = items && items.monthlyExpense;
    const liquid = items && items.liquidAssets;
    if (income && income.value != null && expense && expense.value && liquid && liquid.value != null) {
      const months = Math.round((liquid.value / expense.value) * 10) / 10;
      lines.push('예금이 생활비 ' + months + '개월치예요. 비상자금으로 충분한지 알고 싶어요.');
      lines.push('해외주식을 시작해도 부담 없을까요?');
      lines.push('지금 예금 ' + WSP.utils.formatMan(Math.round(liquid.value / 10000) * 10000) + '이면, 결혼 자금 3천만원을 모으는 데 얼마나 부족한가요?');
      if (!(s.facts && s.facts.hasFxAccount === true)) lines.push('해외주식 계좌는 아직 없어요. 매달 얼마부터 보면 좋을지 알고 싶어요.');
    }
    return lines.filter((t) => !COOKIE_BANNED.test(t) && t.length <= 120);
  }

  function pickCookie(s) {
    const lines = cookieLines(s);
    if (!lines.length) return '';
    return lines[Math.floor(Math.random() * lines.length)];
  }

  /** 마지막 줄에 맺음말만 남지 않게, 문장 부호 뒤에서 줄을 나눈다. */
  function relaxCookieWrap(el, bubble) {
    const raw = el.textContent.replace(/\s+/g, ' ').trim();
    if (!raw || !bubble) return;
    el.textContent = raw;
    const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    const cut = Math.max(raw.lastIndexOf('. '), raw.lastIndexOf('? '), raw.lastIndexOf(', '));
    if (cut >= 8 && raw.length - (cut + 2) >= 6) {
      el.innerHTML = esc(raw.slice(0, cut + 2)) + '<span class="fortune__break">' + esc(raw.slice(cut + 2)) + '</span>';
    }
    const lines = cookieLineWidths(el);
    if (lines.length < 2) return;
    const widest = Math.max.apply(null, lines);
    if (lines[lines.length - 1] >= widest * 0.4) return;
    const host = el.querySelector('.fortune__break') || el;
    const source = host.textContent.replace(/\s+/g, ' ').trim();
    const parts = source.split(' ');
    if (parts.length < 2) return;
    const tail = parts.slice(-2).join(' ');
    const head = parts.slice(0, -2).join(' ');
    const html = (head ? esc(head) + ' ' : '') + '<span class="fortune__keep">' + esc(tail) + '</span>';
    const prev = host.innerHTML;
    host.innerHTML = html;
    const keep = host.querySelector('.fortune__keep');
    const pad = parseFloat(getComputedStyle(bubble).paddingLeft) + parseFloat(getComputedStyle(bubble).paddingRight);
    if (keep && keep.offsetWidth > bubble.clientWidth - pad + 1) host.innerHTML = prev;
  }

  function cookieLineWidths(el) {
    const range = document.createRange();
    range.selectNodeContents(el);
    const rects = range.getClientRects();
    const lines = [];
    for (let i = 0; i < rects.length; i++) {
      const r = rects[i];
      if (r.width < 1) continue;
      const last = lines[lines.length - 1];
      if (!last || Math.abs(r.top - last.top) > 2) lines.push({ top: r.top, width: r.width });
      else last.width = Math.max(last.width, r.width);
    }
    return lines.map((line) => line.width);
  }
  function nextCookie(s, current) {
    const lines = cookieLines(s);
    if (!lines.length) return '';
    const rest = lines.filter((t) => t !== current);
    const pool = rest.length ? rest : lines;
    return pool[Math.floor(Math.random() * pool.length)];
  }

  function freshConsult() {
    const st = fsm().state;
    return st === 'IDLE' || st === 'CLOSED' || st === 'TO_JOIN';
  }

  function openConsult() {
    const st = fsm().state;
    UI().navigate(st === 'CONSENT' ? 'asset-consent' : st === 'EXPLORE' ? 'explore' : st === 'HANDOFF' ? 'support' : 'asset', st === 'HANDOFF' ? { track: 'asset' } : {});
  }

  /** 쿠키 문장으로 상담을 연다. 목표를 다시 묻는 인사는 하지 않는다. */
  function sendCookie(text) {
    const t = String(text || '').trim();
    if (!t || COOKIE_BANNED.test(t)) return;
    if (!freshConsult()) return openConsult();
    if (!start()) return;
    if (!fsm().can('AGREE')) return;
    fsm().transition('AGREE');
    if (S()) S().thinking = true;
    return enqueue(async () => {
      sayUser(t);
      await UI().navigate('asset', {}, { replace: true });
      await applyGoal(t);
    });
  }

  async function setGoal(text) {
    return enqueue(() => setGoalNow(text));
  }

  async function applyGoal(t) {
    const a = S();
    if (!a || fsm().state !== 'GOAL') return;
    const ep = A().epoch();
    const ai = await AI.asset.goal(t);
    if (stale(ep)) return;
    a.goalText = t;
    syncContext();
    a.purpose = ai.valid && ai.output.purpose ? ai.output.purpose : 'GOAL_SAVING';
    ai.output.actions.filter((x) => x.type === 'SET_INFO').forEach((x) => (a.stated[x.key] = x.value));
    if (ai.output.message && !(await sayAI(ai))) return;
    fsm().transition('GOAL_SET', { purpose: a.purpose });
    await advance();
  }

  async function setGoalNow(text) {
    const a = S();
    const t = String(text || '').trim();
    if (!a || !t || fsm().state !== 'GOAL') return;
    sayUser(t);
    await applyGoal(t);
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
      if (!(await waitUserSlide(ep))) return;
      think(true);
      const r = await bank.getFinancialSnapshot();
      if (stale(ep)) return;
      think(false);
      if (!r.ok) {
        a.hold = { reason: 'QUERY_FAILED', text: '연결된 기관의 정보를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.' };
        WSP.events.add('ASSET', '재무 정보 조회 실패: ' + r.error.code, 'warn');
        if (!(await saySystem(a.hold.text, 'warning'))) return;
        f.transition('QUERY_FAILED', { code: r.error.code });
        return;
      }
      collect(r.data);
      syncContext();
      f.transition('COLLECTED', { stateVersion: r.data.stateVersion });
    } else if (st === 'TAGGING') {
      WSP.events.add('ASSET', '출처 구분: ' + Object.keys(a.info.items).map((k) => k + ':' + a.info.items[k].source).join(', '));
      f.transition('TAGGED');
    } else if (st === 'CALCULATING' || st === 'RECALC_ANSWER' || st === 'RECALC_CHANGE') {
      a.metrics = AA.computeMetrics(a.info);
      WSP.events.add('ASSET', '지표 계산: ' + a.metrics.list.map((m) => m.key + '=' + (m.value == null ? '-' : m.value)).join(', '));
      f.transition(st === 'CALCULATING' ? 'CALCULATED' : 'RECALCULATED');
    } else if (st === 'INTERPRETING') {
      if (a.chat.some((m) => m.kind === 'interpret')) {
        f.transition('INTERPRETED');
      } else {
        const ai = await AI.asset.interpret(a.metrics);
        if (stale(ep)) return;
        if (!(await sayAI(ai, { kind: 'interpret', figures: AA.interpretFigures(a.metrics, a.purpose, a.info) }))) return;
        f.transition('INTERPRETED');
      }
    } else if (st === 'GAP_CHECK') {
      a.gaps = AA.findGaps(a.info, a.purpose, a.metrics);
      if (!a.gaps.length) return void f.transition('NO_GAP');
      if (AA.canAsk(a, a.gaps)) {
        const gap = a.gaps.find((g) => !!AA.questionFor(g));
        const q = posedQuestion(AA.questionFor(gap), a.goalText);
        const ai = await AI.asset.ask(q, gap);
        if (stale(ep)) return;
        if (!(await sayAI(ai, { kind: 'question', key: q.key, why: q.why, level: gap.level }))) return;
        a.pendingQuestion = q.key;
        a.questionsAsked += 1;
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
      if (!(await saySystem(a.hold.text, 'warning'))) return;
      f.transition('NOT_PROPOSABLE', { missing: p.missing });
    } else if (st === 'PROPOSED_FULL' || st === 'PROPOSED_LIMITED') {
      const level = st === 'PROPOSED_FULL' ? 'FULL' : 'LIMITED';
      const basis = AA.proposalBasis(a.info, a.purpose, a.metrics);
      const ai = await AI.asset.propose(basis, level, a.metrics);
      if (stale(ep)) return;
      if (!(await sayAI(ai, { kind: 'proposal', figures: AA.proposalFigures(basis, a.metrics) }))) return;
      a.proposal = { level: level, basis: basis, text: ai.output.message, at: Date.now() };
      syncContext();
      f.transition('SHOWN', { level: level });
    }
  }

  /** 목표로 이미 말한 경조사·결혼·이사를, 아직 모르는 지출처럼 다시 묻지 않는다. */
  function posedQuestion(q, goalText) {
    if (!q || q.key !== 'plannedLumpSum') return q;
    const named = String(goalText || '').match(/결혼|이사|경조사/);
    if (!named) return q;
    return Object.assign({}, q, {
      text: '그 외에 또 나갈 목돈이 있나요?',
      why: '',
    });
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
      await sayBot('지금 단계에서는 아래 버튼으로 선택해 주세요.');
      return;
    }
    sayUser(t);
    const ep = A().epoch();
    const q = AA.QUESTIONS[a.pendingQuestion];
    think(true);
    const ai = await AI.asset.answer(t, q);
    if (stale(ep) || fsm().state !== 'ASKING') return;
    if (ai.output.intent === 'SET_INFO') a.thinking = false;
    else if (!(await sayAI(ai))) return;
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
      if (types.indexOf('ESCALATE') !== -1 && !(await sayBot('지금까지 확인한 내용으로 정리한 뒤 상담 연결을 도와드릴게요.'))) return;
      f.transition('STOP_REQUEST');
      return advance();
    }
    const hold = out.actions.find((x) => x.type === 'HOLD');
    if (hold && q) {
      AA.markDeclined(a.info, q.key, hold.reason);
      a.pendingQuestion = null;
      if (hold.reason === 'UNKNOWN') f.transition('SKIP_ONE', { key: q.key });
      else f.transition('UNKNOWN_OR_REFUSED', { key: q.key, kind: hold.reason });
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
    return enqueue(() => answerChipNow(value, label));
  }

  async function answerChipNow(value, label) {
    const a = S();
    if (!a || fsm().state !== 'ASKING') return;
    const q = AA.QUESTIONS[a.pendingQuestion];
    sayUser(label);
    const R = AI.REPLY;
    if (value === 'UNKNOWN' || value === 'REFUSED') {
      if (!(await sayBot(value === 'UNKNOWN' ? R.UNKNOWN : R.REFUSED))) return;
      return applyAnswer({ actions: [{ type: 'HOLD', reason: value }] }, q);
    }
    if (value === 'STOP') {
      if (!(await sayBot(R.STOP))) return;
      return applyAnswer({ actions: [{ type: 'STOP_QUESTIONS' }] }, q);
    }
    return applyAnswer({ actions: [{ type: 'SET_INFO', key: q.key, value: Number(value) }] }, q);
  }

  /* ---------------- 검토 ---------------- */
  async function accept() {
    return enqueue(() => acceptNow());
  }

  async function acceptNow() {
    const a = S();
    if (fsm().state !== 'REVIEW') return;
    a.pendingAccept = true;
    sayUser('이 방향으로 할게요');
    a.handoffTerms = {
      purpose: AA.PURPOSES[a.purpose].label,
      tags: a.proposal.basis.tags,
      monthly: a.proposal.basis.monthly,
      months: a.proposal.basis.months,
      goalText: a.goalText,
    };
    syncContext();
    const said = await sayBot('좋아요. 다음에 할 일을 골라 주세요.');
    a.pendingAccept = false;
    if (!said || fsm().state !== 'REVIEW') {
      A().refresh(SCREENS);
      return;
    }
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
    if (!(await sayAI(ai))) return;
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
      await sayBot(alt.message || '비상자금부터 채우는 건 상담 연결에서 이어서 정하면 돼요.');
      return;
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
      f.transition('KEEP');
      sayBot('지금은 유지하기로 했어요. 상담 내용은 언제든 다시 볼 수 있어요.');
    } else if (kind === 'recheck' && (f.state === 'NEXT_ACTION' || f.state === 'HOLD')) {
      f.transition('RECHECK_INFO');
      sayBot('틀린 정보가 있으면 아래에서 고쳐 주세요. 다 고치셨으면 "다시 분석"을 눌러 주세요.');
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
    if (a.proposal && a.proposal.basis && (key === 'monthlyIncome' || key === 'monthlyExpense' || key === 'monthlySavingPref')) {
      a.metrics = AA.computeMetrics(a.info);
      const basis = AA.proposalBasis(a.info, a.purpose, a.metrics);
      a.proposal.basis = basis;
      a.handoffTerms = a.handoffTerms || {};
      a.handoffTerms.monthly = basis.monthly;
    }
    syncContext();
    A().refresh(SCREENS);
  }

  function selectProduct(productId) {
    const st = fsm().state;
    if (st !== 'EXPLORE' && st !== 'TO_JOIN') return;
    if (st === 'EXPLORE') fsm().transition('PRODUCT_SELECTED', { productId: productId });
    syncContext({ selectedProductId: productId });
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
    A().refresh(SCREENS);
    if (a) sayBot('상담을 마쳤어요.');
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
    const a = S();
    if (!a || running) return;
    if (AUTO.indexOf(fsm().state) !== -1) advance();
    else if (a.thinking && !pacing) {
      a.thinking = false;
      A().refresh(SCREENS);
    }
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
    cookieLines: cookieLines,
    pickCookie: pickCookie,
  };

  WSP.registerActions({
    'asset-start'() {
      if (!/[?&]legacy=1(?:&|$)/.test(location.search) && WSP.lumpsumFlow) return WSP.lumpsumFlow.open();
      if (freshConsult()) {
        if (start()) UI().navigate('asset-consent');
        return;
      }
      openConsult();
    },
    'prompt-cookie'(_d, el) {
      const root = el && el.closest('.fortune');
      if (!root) return;
      const bubble = root.querySelector('.fortune__bubble');
      const text = root.querySelector('.fortune__text');
      const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      const clearBox = () => {
        if (!bubble) return;
        bubble.style.width = '';
        bubble.style.height = '';
        bubble.style.maxWidth = '';
        bubble.style.clipPath = '';
      };
      const stop = () => {
        if (root._fortuneOnEnd && bubble) bubble.removeEventListener('transitionend', root._fortuneOnEnd);
        if (root._fortuneTextEnd && text) text.removeEventListener('transitionend', root._fortuneTextEnd);
        root._fortuneOnEnd = null;
        root._fortuneTextEnd = null;
        clearTimeout(root._fortuneTimer);
        clearTimeout(root._fortuneTextTimer);
      };
      stop();
      if (root.classList.contains('is-open')) {
        root.classList.remove('is-ready', 'is-text');
        root.classList.add('is-closing');
        const finish = () => {
          root.classList.remove('is-open', 'is-text', 'is-closing');
          clearBox();
        };
        if (reduced || !bubble) {
          finish();
          return;
        }
        const top = Math.max(0, bubble.offsetHeight - 40);
        const left = Math.max(0, bubble.offsetWidth - 40);
        bubble.style.clipPath = 'inset(' + top + 'px 0px 0px ' + left + 'px round 20px)';
        const started = Date.now();
        const done = (ev) => {
          if (ev.target !== bubble || ev.propertyName !== 'clip-path') return;
          if (Date.now() - started < 400) return;
          bubble.removeEventListener('transitionend', done);
          if (root._fortuneOnEnd === done) root._fortuneOnEnd = null;
          clearTimeout(root._fortuneTimer);
          finish();
        };
        root._fortuneOnEnd = done;
        bubble.addEventListener('transitionend', done);
        root._fortuneTimer = setTimeout(finish, 560);
        return;
      }
      root.classList.remove('is-text', 'is-ready', 'is-closing');
      clearBox();
      if (text) text.textContent = nextCookie(WSP.store.getState(), text.textContent.trim());
      if (reduced || !bubble) {
        root.classList.add('is-open', 'is-text', 'is-ready');
        if (text) relaxCookieWrap(text, bubble);
        return;
      }
      root.classList.add('is-open', 'is-measure');
      if (text) relaxCookieWrap(text, bubble);
      const targetW = bubble.offsetWidth;
      const targetH = bubble.offsetHeight;
      bubble.style.width = targetW + 'px';
      bubble.style.height = targetH + 'px';
      bubble.style.maxWidth = targetW + 'px';
      const clipTop = Math.max(0, targetH - 40);
      const clipLeft = Math.max(0, targetW - 40);
      bubble.style.clipPath = 'inset(' + clipTop + 'px 0px 0px ' + clipLeft + 'px round 20px)';
      void bubble.offsetWidth;
      root.classList.remove('is-measure');
      const showButton = () => {
        if (!root.classList.contains('is-open') || root.classList.contains('is-ready')) return;
        root.classList.add('is-ready');
      };
      const showText = () => {
        if (!root.classList.contains('is-open') || root.classList.contains('is-text')) return;
        root.classList.add('is-text');
        if (!text) {
          showButton();
          return;
        }
        const onText = (ev) => {
          if (ev.target !== text || ev.propertyName !== 'opacity') return;
          text.removeEventListener('transitionend', onText);
          if (root._fortuneTextEnd === onText) root._fortuneTextEnd = null;
          clearTimeout(root._fortuneTextTimer);
          showButton();
        };
        root._fortuneTextEnd = onText;
        text.addEventListener('transitionend', onText);
        root._fortuneTextTimer = setTimeout(showButton, 400);
      };
      const onEnd = (ev) => {
        if (ev.target !== bubble || ev.propertyName !== 'clip-path') return;
        bubble.removeEventListener('transitionend', onEnd);
        if (root._fortuneOnEnd === onEnd) root._fortuneOnEnd = null;
        clearTimeout(root._fortuneTimer);
        showText();
      };
      root._fortuneOnEnd = onEnd;
      bubble.addEventListener('transitionend', onEnd);
      root._fortuneTimer = setTimeout(showText, 560);
      requestAnimationFrame(() => {
        if (!root.classList.contains('is-open')) return;
        bubble.style.clipPath = 'inset(0px round 16px)';
        showText();
      });
    },
    'prompt-cookie-send'(_d, el) {
      const root = el && el.closest('.fortune');
      if (!root || !root.classList.contains('is-ready')) return;
      const text = root.querySelector('.fortune__text');
      const line = text ? text.textContent.trim() : '';
      /* 쿠키의 물어보기는 항상 새 채팅을 연다. 진행 중이던 상담은 버린다 */
      if (!/[?&]legacy=1(?:&|$)/.test(location.search) && WSP.lumpsumFlow) return WSP.lumpsumFlow.startFresh(line);
      if (!freshConsult()) return openConsult();
      return sendCookie(line);
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
      if (!d.q) return;
      return A().guard('asset-send', () => answerText(d.q));
    },
    'asset-chip'(d) {
      return A().guard('asset-send', () => answerChip(d.value, d.label));
    },
    'asset-accept'() {
      return A().guard('asset-accept', accept);
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
      const kind = AA.ITEMS[key].kind;
      const now = UI().esc(it.value == null ? '입력 전' : AA.display(key, it.value));
      if (kind === 'pace') {
        const q = AA.QUESTIONS.investPace;
        UI().openSheet(
          '<h3 class="sheet__title">투자 속도 고치기</h3><p class="sheet__desc">지금 ' +
            now +
            '</p><div class="chip-row">' +
            q.options.map((o) => '<button class="chip chip--lg" data-action="asset-edit-pace" data-key="' + key + '" data-value="' + o[1] + '">' + UI().esc(o[0]) + '</button>').join('') +
            '</div>',
          { dismissible: true }
        );
        return;
      }
      const isMonths = kind === 'months';
      const sh = UI().openSheet(
        '<h3 class="sheet__title">' +
          UI().esc(AA.ITEMS[key].label) +
          ' 고치기</h3><p class="sheet__desc">지금 ' +
          now +
          '</p><label class="field"><span class="field__label">' +
          (isMonths ? '개월 수' : '금액(만원)') +
          '</span><input class="text-input" id="asset-edit-value" inputmode="numeric" value="' +
          (it.value == null ? '' : isMonths ? it.value : Math.round(it.value / 10000)) +
          '" /></label><div class="btn-row"><button class="btn btn--ghost" data-action="sheet-close">취소</button><button class="btn btn--primary" data-action="asset-edit-save" data-key="' +
          key +
          '">저장</button></div>',
        { dismissible: true }
      );
      const inp = sh && sh.querySelector('input');
      if (inp) setTimeout(() => inp.focus(), 250);
    },
    'asset-edit-pace'(d) {
      const v = AA.pacePercent(d.value);
      if (v == null) return;
      UI().closeSheet();
      editItem(d.key, v);
    },
    'asset-edit-save'(d) {
      const sh = UI().getSheet();
      const raw = sh ? sh.querySelector('#asset-edit-value').value : '';
      const v = Number(String(raw).replace(/[^\d]/g, ''));
      if (!raw || isNaN(v)) {
        UI().toast('숫자로 입력해 주세요.', 'warning');
        return;
      }
      const kind = AA.ITEMS[d.key].kind;
      UI().closeSheet();
      editItem(d.key, kind === 'months' ? v : kind === 'pace' ? AA.pacePercent(v) : v * 10000);
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
