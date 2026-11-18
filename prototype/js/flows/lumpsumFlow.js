/**
 * flows/lumpsumFlow.js
 * 목돈 불리기 대본 진행. 월급·지출·부채는 채팅 시작 스냅샷만 쓰고,
 * 목표와 성향은 그 채팅에서 보낸 문장으로 정한다.
 */
(function () {
  'use strict';

  const WSP = window.WSP;
  const LA = WSP.lumpsumAdvisor;
  const LS = WSP.lumpsumScript;
  const A = () => WSP.app;
  const UI = () => WSP.ui;
  const fsm = () => WSP.app.fsms.lumpsum;
  const S = () => WSP.app.session.lumpsum;
  const SCREENS = ['lumpsum', 'home'];

  let tail = Promise.resolve();
  let typeTimer = 0;
  let streamTimer = 0;

  function enqueue(fn) {
    const run = tail.then(fn, fn);
    tail = run.then(
      () => {},
      () => {}
    );
    return run;
  }

  function scale() {
    return WSP.mockBank.getLatencyScale();
  }

  function sleep(ms) {
    const wait = ms * scale();
    if (wait <= 0) return Promise.resolve();
    return WSP.utils.sleep(wait);
  }

  function stale(ep) {
    return ep !== A().epoch() || !S();
  }

  function hash(str) {
    let h = 0;
    const s = String(str || '');
    for (let i = 0; i < s.length; i++) h = (h * 33 + s.charCodeAt(i)) >>> 0;
    return h;
  }

  function man(n) {
    return WSP.utils.formatMan(n);
  }

  const DECISION_LABEL = {
    SPEND_CHECK: '지출 점검',
    DEBT_FIRST: '상환 우선',
    EMERGENCY_FIRST: '비상자금',
    SAVINGS_ENOUGH: '적금으로 달성',
    MIX: '적금+투자',
  };

  function fresh(snap) {
    const caseId = WSP.utils.newId('LUMP');
    return {
      caseId: caseId,
      seed: hash(caseId),
      snap: snap,
      goal: null,
      expText: '',
      lossText: '',
      advice: null,
      chat: [],
      thinking: false,
      thinkLabel: '',
      thoughtMs: 0,
      draft: '',
      typing: false,
      lock: false,
      awaiting: '',
      prompt: null,
    };
  }

  function readSnap() {
    const items = WSP.store.getState().finance.items;
    const debt = items.debt && items.debt.value ? items.debt.value : 0;
    return {
      income: items.monthlyIncome && items.monthlyIncome.value ? items.monthlyIncome.value : 0,
      expense: items.monthlyExpense && items.monthlyExpense.value ? items.monthlyExpense.value : 0,
      debt: debt,
      debtPayment: LA.debtPayment(debt),
      deposit: items.liquidAssets && items.liquidAssets.value != null ? items.liquidAssets.value : LA.DEPOSIT_DEFAULT,
    };
  }

  function push(msg) {
    const s = S();
    if (!s) return null;
    const row = Object.assign({ id: s.caseId + '-' + (s.chat.length + 1), at: Date.now(), liked: false }, msg);
    s.chat.push(row);
    return row;
  }

  function paintDraft() {
    const inp = document.getElementById('lumpsum-input');
    if (!inp || !S()) return;
    inp.value = S().draft || '';
    const send = document.querySelector('[data-action="lumpsum-send"]');
    if (send) send.classList.toggle('is-hot', !!S().typing || !!(S().draft && S().draft.length));
  }

  function refresh() {
    A().refresh(SCREENS);
  }

  function syncPrompt() {
    const s = S();
    if (!s) return;
    const st = fsm().state;
    const mainGoal = LA.GOALS['goal-100'].text;
    const mainExp = LA.EXPERIENCE['exp-1'].text;
    const mainLoss = LA.LOSS['loss-1'].text;
    let prompt = { mode: 'wait', typeText: '', choices: [], spoken: false, demoChoice: '' };
    if (st === 'INTRO') prompt = { mode: 'type', typeText: LS.OPENING, choices: [], spoken: false, demoChoice: '' };
    else if (st === 'GOAL') prompt = { mode: 'choice', typeText: mainGoal, choices: LS.goalChoices(), spoken: false, demoChoice: '3년 안에 1억' };
    else if (st === 'DEBT_CHECK')
      prompt = {
        mode: 'type',
        typeText: LS.situationText(s.snap.debt),
        choices: LS.MISMATCH.map((c) => ({ id: c.id, text: c.text })),
        spoken: true,
        demoChoice: '',
      };
    else if (st === 'PROFILING') prompt = { mode: 'choice', typeText: mainExp, choices: LS.experienceChoices(), spoken: false, demoChoice: '소액으로 ETF' };
    else if (st === 'LOSS') prompt = { mode: 'type', typeText: mainLoss, choices: LS.lossChoices(), spoken: false, demoChoice: '' };
    else if (st === 'RECOMMEND') {
      const showLev = !!(s.advice && s.advice.leverage);
      prompt = { mode: 'choice', typeText: '해외주식', choices: LS.productChoices(showLev), spoken: false, demoChoice: '해외주식' };
    } else if (st === 'NO_ACCOUNT') prompt = { mode: 'choice', typeText: '응, 개설해 주세요', choices: LS.openChoices(), spoken: false, demoChoice: '응, 개설해 주세요' };
    s.prompt = prompt;
  }

  function currentAdvice(extra) {
    const s = S();
    const snap = s.snap;
    const goal = s.goal || LA.GOALS['goal-100'];
    return LA.advise(
      Object.assign(
        {
          income: snap.income,
          expense: snap.expense,
          debt: snap.debt,
          deposit: snap.deposit,
          goalAmount: goal.amount,
          goalMonths: goal.months,
          expText: s.expText,
          lossText: s.lossText,
        },
        extra || {}
      )
    );
  }

  function goalFrom(text, choiceId) {
    if (choiceId && LA.GOALS[choiceId]) return LA.GOALS[choiceId];
    const keys = Object.keys(LA.GOALS);
    for (let i = 0; i < keys.length; i++) {
      if (LA.GOALS[keys[i]].text === text) return LA.GOALS[keys[i]];
    }
    return LA.GOALS['goal-100'];
  }

  function textOf(choiceId, fallback) {
    const maps = [LA.GOALS, LA.EXPERIENCE, LA.LOSS, LS.MISMATCH];
    for (let i = 0; i < maps.length; i++) {
      const bag = maps[i];
      if (bag[choiceId] && bag[choiceId].text) return bag[choiceId].text;
      if (Array.isArray(bag)) {
        const hit = bag.find((c) => c.id === choiceId);
        if (hit) return hit.text;
      }
    }
    const choices = (S() && S().prompt && S().prompt.choices) || [];
    const found = choices.find((c) => c.id === choiceId);
    return found ? found.text : fallback || '';
  }

  async function think(kind, ep) {
    const s = S();
    const steps = LS.thoughtSteps(kind);
    const started = Date.now();
    s.thinking = true;
    s.lock = true;
    for (let i = 0; i < steps.length; i++) {
      if (stale(ep)) return false;
      s.thinkLabel = steps[i];
      refresh();
      await sleep(700 + (i % 2) * 400);
    }
    if (stale(ep)) return false;
    s.thinking = false;
    s.thoughtMs = Math.max(1, Math.round((Date.now() - started) / 100) / 10);
    if (scale() === 0) s.thoughtMs = 0;
    refresh();
    return true;
  }

  function tokensOf(text) {
    const parts = String(text || '').split(/(\s+)/);
    return parts.filter((p) => p.length);
  }

  async function streamInto(row, ep) {
    const full = row.full || row.text || '';
    row.full = full;
    row.text = '';
    row.streaming = true;
    refresh();
    const bits = tokensOf(full);
    if (scale() === 0) {
      row.text = full;
      row.streaming = false;
      refresh();
      return !stale(ep);
    }
    for (let i = 0; i < bits.length; i++) {
      if (stale(ep)) return false;
      if (S().stopStream) {
        row.text = full;
        break;
      }
      row.text += bits[i];
      const el = document.querySelector('[data-mid="' + row.id + '"] .msg__text');
      if (el) {
        el.innerHTML = formatRich(row.text) + '<i class="stream-caret"></i>';
        const body = document.getElementById('lumpsum-body');
        if (body && body.dataset.pin !== '0') UI().scrollToLatest(body);
      } else refresh();
      const pause = /[.!?。]|요$|다$/.test(bits[i]) ? 180 : 40 + (i % 4) * 18;
      await sleep(pause);
    }
    row.text = full;
    row.streaming = false;
    if (S()) S().stopStream = false;
    refresh();
    return !stale(ep);
  }

  function formatRich(text) {
    return UI()
      .esc(text)
      .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
      .replace(/\n/g, '<br>');
  }

  async function say(partial, kind, ep) {
    if (!(await think(kind, ep))) return false;
    if (stale(ep)) return false;
    const row = push(Object.assign({ role: 'ai', thoughtMs: S().thoughtMs }, partial));
    row.full = partial.text;
    const ok = await streamInto(row, ep);
    if (S()) S().awaiting = '';
    return ok;
  }

  async function replyAnalysis(ep) {
    const s = S();
    s.awaiting = 'analysis';
    s.lock = true;
    const advice = currentAdvice();
    const msg = LS.analysisMessage(advice, s.seed);
    if (fsm().state === 'INTRO' && fsm().can('SENT')) fsm().transition('SENT');
    const ok = await say(msg, 'analysis', ep);
    if (!ok) return;
    if (fsm().can('SHOWN')) fsm().transition('SHOWN');
    s.lock = false;
    syncPrompt();
    refresh();
  }

  async function replyDecision(ep) {
    const s = S();
    s.awaiting = 'decision';
    s.lock = true;
    const advice = currentAdvice();
    s.advice = advice;
    const msg = LS.decisionMessage(advice, s.goal.text, s.seed);
    if (fsm().state === 'GOAL' && fsm().can('SENT')) fsm().transition('SENT');
    const ok = await say(msg, 'decision', ep);
    if (!ok) return;
    if (advice.decisionId === 'SPEND_CHECK') {
      if (fsm().can('STOP')) fsm().transition('STOP');
      s.prompt = { mode: 'wait', typeText: '', choices: [], spoken: false, demoChoice: '' };
    }
    s.lock = false;
    syncPrompt();
    refresh();
  }

  async function replyAfterUser3(ep, mismatch) {
    const s = S();
    s.awaiting = 'profile';
    s.lock = true;
    const last = s.chat.filter((m) => m.role === 'user').pop();
    const msg = mismatch ? LS.mismatchReply() : LS.afterSituation(s.advice || currentAdvice(), last ? last.text : '', s.seed);
    if (fsm().state === 'DEBT_CHECK' && fsm().can('SENT')) fsm().transition('SENT');
    const ok = await say(msg, 'talk', ep);
    if (!ok) return;
    s.lock = false;
    syncPrompt();
    refresh();
  }

  async function replyLoss(ep) {
    const s = S();
    s.awaiting = 'loss';
    s.lock = true;
    if (fsm().state === 'PROFILING' && fsm().can('SENT')) fsm().transition('SENT');
    const ok = await say(LS.lossAsk(), 'talk', ep);
    if (!ok) return;
    s.lock = false;
    syncPrompt();
    refresh();
  }

  async function replyRecommend(ep) {
    const s = S();
    s.awaiting = 'recommend';
    s.lock = true;
    s.advice = currentAdvice();
    const msg = LS.recommendMessage(s.advice, s.expText, s.lossText, s.seed);
    if (fsm().state === 'LOSS' && fsm().can('SENT')) fsm().transition('SENT');
    const ok = await say(msg, 'talk', ep);
    if (!ok) return;
    s.lock = false;
    syncPrompt();
    refresh();
  }

  async function replySide(ep, choiceId) {
    const s = S();
    s.lock = true;
    if (fsm().can('OTHER')) fsm().transition('OTHER');
    const ok = await say(LS.sideStop(choiceId), 'talk', ep);
    if (!ok) return;
    s.prompt = { mode: 'wait', typeText: '', choices: [], spoken: false, demoChoice: '' };
    s.lock = false;
    refresh();
  }

  async function replyNoAccount(ep) {
    const s = S();
    s.awaiting = 'noaccount';
    s.lock = true;
    if (fsm().can('OVERSEAS')) fsm().transition('OVERSEAS');
    const ok = await say(LS.noAccount(), 'talk', ep);
    if (!ok) return;
    s.lock = false;
    syncPrompt();
    refresh();
  }

  function handoff() {
    const s = S();
    const advice = s.advice || currentAdvice();
    const goalText = s.goal ? s.goal.text : '';
    A().publishContext({
      goal: goalText,
      decisionId: advice.decisionId,
      financialSummary: { monthly: advice.monthlyInvest, source: '계좌 정보 기준', adjustable: true },
      knownFromAccount: [
        { label: '월급', text: man(s.snap.income), source: '조회' },
        { label: '지출', text: man(s.snap.expense), source: '조회' },
        { label: '부채', text: s.snap.debt > 0 ? man(s.snap.debt) : '없음', source: '조회' },
      ],
    });
    const started = WSP.joinFlow.start('OVERSEAS_STOCK', { goalText: goalText, monthly: advice.monthlyInvest });
    if (fsm().can('OPEN')) fsm().transition('OPEN');
    s.prompt = { mode: 'wait', typeText: '', choices: [], spoken: false, demoChoice: '' };
    s.lock = false;
    if (started) UI().navigate('join-consent');
    else refresh();
  }

  function continueAwaiting(ep) {
    const s = S();
    const kind = s.awaiting;
    if (kind === 'analysis') return replyAnalysis(ep);
    if (kind === 'decision') return replyDecision(ep);
    if (kind === 'profile') return replyAfterUser3(ep, false);
    if (kind === 'loss') return replyLoss(ep);
    if (kind === 'recommend') return replyRecommend(ep);
    if (kind === 'noaccount') return replyNoAccount(ep);
    s.awaiting = '';
    s.lock = false;
    return Promise.resolve();
  }

  function accept(text, choiceId) {
    const s = S();
    if (!s || s.lock) return Promise.resolve();
    const spoken = (text || '').trim();
    if (!spoken) return Promise.resolve();
    clearType();
    s.typing = false;
    s.draft = '';
    push({ role: 'user', text: spoken });
    const ep = A().epoch();
    const st = fsm().state;
    s.lock = true;
    refresh();
    return enqueue(async () => {
      if (stale(ep)) return;
      if (st === 'INTRO') return replyAnalysis(ep);
      if (st === 'GOAL') {
        s.goal = goalFrom(spoken, choiceId);
        return replyDecision(ep);
      }
      if (st === 'DEBT_CHECK') {
        const mismatch = choiceId && String(choiceId).indexOf('mis-') === 0;
        return replyAfterUser3(ep, mismatch);
      }
      if (st === 'PROFILING') {
        s.expText = spoken;
        return replyLoss(ep);
      }
      if (st === 'LOSS') {
        s.lossText = spoken;
        return replyRecommend(ep);
      }
      if (st === 'RECOMMEND') {
        if (choiceId === 'prod-os' || spoken === '해외주식') return replyNoAccount(ep);
        return replySide(ep, choiceId || 'prod-dom');
      }
      if (st === 'NO_ACCOUNT') {
        if (choiceId === 'open-no' || /다음에/.test(spoken)) {
          if (fsm().can('LATER')) fsm().transition('LATER');
          s.lock = false;
          s.prompt = { mode: 'wait', typeText: '', choices: [], spoken: false, demoChoice: '' };
          refresh();
          return;
        }
        handoff();
      }
    });
  }

  function clearType() {
    if (typeTimer) clearTimeout(typeTimer);
    typeTimer = 0;
  }

  function onBlankClick() {
    const s = S();
    if (!s || s.lock || s.typing || !s.prompt || !s.prompt.typeText) return;
    if (scale() === 0) {
      accept(s.prompt.typeText, null);
      return;
    }
    s.typing = true;
    s.draft = '';
    const full = s.prompt.typeText;
    let i = 0;
    let typoAt = Math.min(full.length - 2, 4 + (s.seed % 6));
    let fixing = false;
    let typoDone = false;
    const started = Date.now();
    const kick = 300 + (s.seed % 300);
    function step() {
      if (!S() || !S().typing) return;
      if (Date.now() - started < kick) {
        typeTimer = setTimeout(step, 40);
        return;
      }
      if (!typoDone && !fixing && i === typoAt) {
        S().draft = full.slice(0, i) + 'ㄱ';
        paintDraft();
        fixing = true;
        typeTimer = setTimeout(step, 140);
        return;
      }
      if (fixing) {
        fixing = false;
        typoDone = true;
        S().draft = full.slice(0, i);
        paintDraft();
        typeTimer = setTimeout(step, 80);
        return;
      }
      i += 1;
      S().draft = full.slice(0, i);
      paintDraft();
      if (i >= full.length) {
        S().typing = false;
        typeTimer = setTimeout(() => accept(full, null), 280);
        return;
      }
      const ch = full.charAt(i - 1);
      const gap = ch === ' ' || ch === ',' || ch === '.' ? 160 : 50 + ((i * 17) % 40);
      typeTimer = setTimeout(step, gap);
    }
    paintDraft();
    typeTimer = setTimeout(step, 30);
  }

  function finishTypeNow() {
    const s = S();
    if (!s || !s.prompt || !s.prompt.typeText) return;
    clearType();
    s.typing = false;
    accept(s.prompt.typeText, null);
  }

  function startNew() {
    const f = fsm();
    if (f.state !== 'IDLE' && f.can('NEW_CASE')) f.transition('NEW_CASE');
    if (f.state !== 'IDLE') return false;
    clearType();
    const snap = readSnap();
    A().session.lumpsum = fresh(snap);
    f.transition('START');
    syncPrompt();
    A().refresh(SCREENS);
    UI().navigate('lumpsum');
    return true;
  }

  function open() {
    const f = fsm();
    if (f.state === 'IDLE' || !S()) return startNew();
    syncPrompt();
    UI().navigate('lumpsum');
    return true;
  }

  function resume() {
    const s = S();
    if (!s) return;
    s.typing = false;
    s.thinking = false;
    if (s.awaiting) {
      const ep = A().epoch();
      s.lock = false;
      enqueue(() => continueAwaiting(ep));
      return;
    }
    s.lock = false;
    syncPrompt();
  }

  function hint() {
    const s = S();
    const f = fsm();
    if (!s || f.state === 'IDLE') return { active: false, line: '', spoken: '', decision: '' };
    const p = s.prompt || {};
    let line = '';
    if (p.mode === 'type' && p.typeText) line = '빈 곳을 눌러 타이핑: ' + p.typeText;
    else if (p.mode === 'choice') line = '선택지를 누르세요: ' + (p.demoChoice || '');
    const decision = s.advice ? '이번 채팅: ' + (DECISION_LABEL[s.advice.decisionId] || s.advice.decisionId) + ' · 월 여유 ' + man(Math.max(0, s.advice.surplus)) : '';
    const active = ['IDLE', 'CLOSED', 'TO_JOIN'].indexOf(f.state) === -1;
    return { active: active, line: line, spoken: p.spoken ? '우리 상황에 맞는 게 없네요?' : '', decision: decision };
  }

  function regenerate(id) {
    const s = S();
    if (!s || s.lock) return;
    const row = s.chat.filter((m) => m.id === id && m.role === 'ai').pop();
    if (!row || !row.full) return;
    const ep = A().epoch();
    s.lock = true;
    enqueue(() => streamInto(row, ep).then(() => {
      if (S()) S().lock = false;
    }));
  }

  WSP.lumpsumFlow = {
    open: open,
    startNew: startNew,
    resume: resume,
    accept: accept,
    onBlankClick: onBlankClick,
    finishTypeNow: finishTypeNow,
    hint: hint,
    regenerate: regenerate,
    formatRich: formatRich,
    decisionLabel: DECISION_LABEL,
  };

  document.addEventListener('click', (e) => {
    const screen = document.querySelector('[data-screen="lumpsum"]');
    if (!screen || !screen.contains(e.target)) return;
    if (e.target.closest('[data-action], button, a, .bottom-nav, .appbar, .msg-tools')) return;
    onBlankClick();
  });

  document.addEventListener('keydown', (e) => {
    const screen = document.querySelector('[data-screen="lumpsum"]');
    if (!screen) return;
    if (e.key !== 'Enter' && e.key !== ' ') return;
    if (e.target && e.target.closest && e.target.closest('input, textarea, button')) return;
    e.preventDefault();
    onBlankClick();
  });

  WSP.registerActions({
    'lumpsum-send'() {
      const s = S();
      if (!s) return;
      if (s.streamingStop) return;
      if (s.chat.some((m) => m.streaming)) {
        s.stopStream = true;
        return;
      }
      if (s.typing) return finishTypeNow();
      if (s.prompt && s.prompt.typeText) return accept(s.prompt.typeText, null);
    },
    'lumpsum-choice'(d) {
      const text = textOf(d.id, d.label);
      return accept(text, d.id);
    },
    'lumpsum-new'() {
      return startNew();
    },
    'lumpsum-open'() {
      return open();
    },
    'lumpsum-end'() {
      const f = fsm();
      if (f.can('EXIT')) f.transition('EXIT');
      if (f.can('NEW_CASE')) f.transition('NEW_CASE');
      A().session.lumpsum = null;
      UI().navigate('home', {}, { resetHistory: true, back: true });
    },
    'lumpsum-like'(d) {
      const s = S();
      if (!s) return;
      const row = s.chat.filter((m) => m.id === d.id).pop();
      if (row) row.liked = !row.liked;
      refresh();
    },
    'lumpsum-copy'(d) {
      const s = S();
      if (!s) return;
      const row = s.chat.filter((m) => m.id === d.id).pop();
      const text = row ? row.full || row.text : '';
      if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text);
      UI().toast('복사했어요.');
    },
    'lumpsum-again'(d) {
      regenerate(d.id);
    },
  });
})();
