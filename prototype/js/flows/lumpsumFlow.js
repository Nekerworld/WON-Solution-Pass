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

  let pending = 0;

  function enqueue(fn) {
    pending += 1;
    const run = tail.then(fn, fn);
    tail = run.then(
      () => {
        pending -= 1;
      },
      () => {
        pending -= 1;
      }
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
      goalKind: '',
      situationDone: false,
      investFocus: false,
      both: false,
      stopStream: false,
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
    const row = Object.assign({ id: s.caseId + '-' + (s.chat.length + 1), at: Date.now() }, msg);
    if (row.role === 'ai') {
      if (!row.blocks) row.blocks = [{ t: 'text', text: row.text || '' }];
      row.text = row.blocks
        .filter((b) => b.t === 'text')
        .map((b) => b.text)
        .join('\n\n');
      row.shown = 0;
      row.cur = -1;
      row.curText = '';
      row.open = false;
    }
    s.chat.push(row);
    return row;
  }

  function paintDraft() {
    const inp = document.getElementById('lumpsum-input');
    if (!inp || !S()) return;
    inp.value = S().draft || '';
    if (UI().autoGrow) UI().autoGrow(inp);
    const send = document.querySelector('[data-action="lumpsum-send"]');
    if (send) send.classList.toggle('is-hot', !!S().typing || !!(S().draft && S().draft.length));
    const bar = inp.closest('.chat-input');
    if (bar) {
      const typing = !!S().typing;
      bar.classList.toggle('is-typing', typing);
      let caret = bar.querySelector('.type-caret');
      if (typing && !caret && send) {
        caret = document.createElement('i');
        caret.className = 'type-caret';
        send.parentNode.insertBefore(caret, send);
      } else if (!typing && caret) caret.remove();
    }
  }

  function refresh() {
    A().refresh(SCREENS);
  }

  function syncPrompt() {
    const s = S();
    if (!s) return;
    const st = fsm().state;
    const T = LS.TYPED;
    let prompt = { mode: 'wait', typeText: '', choices: [], spoken: false, demoChoice: '' };
    if (st === 'INTRO') prompt = { mode: 'type', typeText: T.INTRO, choices: LS.introChoices(), spoken: false, demoChoice: '' };
    else if (st === 'GOAL') prompt = { mode: 'choice', typeText: T.GOAL, choices: LS.goalChoices(), spoken: false, demoChoice: '3년 안에 1억' };
    else if (st === 'DEBT_CHECK')
      prompt = {
        mode: 'type',
        typeText: LS.situationText(s.snap.debt),
        choices: LS.MISMATCH.map((c) => ({ id: c.id, text: c.text })),
        spoken: true,
        demoChoice: '',
      };
    else if (st === 'PROFILING') prompt = { mode: 'choice', typeText: T.PROFILING, choices: LS.experienceChoices(), spoken: false, demoChoice: '소액으로 ETF' };
    else if (st === 'LOSS') prompt = { mode: 'type', typeText: T.LOSS, choices: LS.lossChoices(), spoken: false, demoChoice: '' };
    else if (st === 'RECOMMEND') {
      const showLev = !!(s.advice && s.advice.leverage);
      prompt = { mode: 'choice', typeText: T.RECOMMEND, choices: LS.productChoices(showLev), spoken: false, demoChoice: '해외주식' };
    } else if (st === 'NO_ACCOUNT') prompt = { mode: 'choice', typeText: T.NO_ACCOUNT, choices: LS.openChoices(), spoken: false, demoChoice: '네, 개설해 주세요' };
    else if (st === 'SPEND_PLAN') prompt = { mode: 'choice', typeText: '', choices: LS.spendChoices(), spoken: false, demoChoice: '줄이기 목표로 저장' };
    /* 타이핑은 선택지에 원하는 상황이 없을 때 쓴다. 선택지와 같은 문장은 타이핑하지 않는다 */
    if (prompt.choices.some((c) => c.text === prompt.typeText)) prompt.typeText = '';
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
          investFocus: s.investFocus,
        },
        extra || {}
      )
    );
  }

  function goalFrom(text, choiceId) {
    if (choiceId && LA.GOALS[choiceId]) return LA.GOALS[choiceId];
    if (LA.GOAL_TYPED.text === text) return LA.GOAL_TYPED;
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

  /** 문장 블록 하나를 글자 흐름으로 보여 준다 */
  async function streamText(row, idx, ep) {
    const full = row.blocks[idx].text || '';
    const bits = tokensOf(full);
    row.cur = idx;
    row.curText = '';
    refresh();
    for (let i = 0; i < bits.length; i++) {
      if (stale(ep)) return false;
      if (S().stopStream) break;
      row.curText += bits[i];
      const el = document.querySelector('[data-mid="' + row.id + '"] [data-bi="' + idx + '"]');
      if (el) {
        el.innerHTML = formatRich(row.curText) + '<i class="stream-caret"></i>';
        const body = document.getElementById('lumpsum-body');
        if (body && body.dataset.pin !== '0') UI().scrollToLatest(body);
      } else refresh();
      const pause = /[.!?。]|요$|다$/.test(bits[i]) ? 180 : 40 + (i % 4) * 18;
      await sleep(pause);
    }
    row.cur = -1;
    row.curText = '';
    row.shown = idx + 1;
    refresh();
    return !stale(ep);
  }

  /** 블록을 순서대로 하나씩 보여 준다. 카드와 드롭다운은 앞 블록이 끝난 뒤에 나온다 */
  async function revealBlocks(row, ep) {
    row.streaming = true;
    row.shown = row.shown || 0;
    if (scale() !== 0) {
      for (let i = row.shown; i < row.blocks.length; i++) {
        if (stale(ep)) return false;
        const b = row.blocks[i];
        if (S().stopStream) break;
        if (b.t === 'text') {
          if (!(await streamText(row, i, ep))) return false;
        } else {
          if (i > 0) await sleep(260);
          if (stale(ep)) return false;
          row.shown = i + 1;
          refresh();
          await sleep(b.t === 'steps' ? 700 * b.items.length + 300 : 420);
        }
        await sleep(140);
      }
    }
    if (stale(ep)) return false;
    row.cur = -1;
    row.curText = '';
    row.shown = row.blocks.length;
    row.streaming = false;
    S().stopStream = false;
    refresh();
    return true;
  }

  function formatRich(text) {
    return UI()
      .esc(text)
      .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
      .replace(/\n/g, '<br>');
  }

  async function say(partial, kind, ep) {
    if (kind && !(await think(kind, ep))) return false;
    if (stale(ep)) return false;
    const row = push(Object.assign({ role: 'ai', thoughtMs: kind ? S().thoughtMs : 0 }, partial));
    const ok = await revealBlocks(row, ep);
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
    const msg = LS.decisionMessage(advice);
    if (fsm().state === 'GOAL' && fsm().can('SENT')) fsm().transition('SENT');
    const ok = await say(msg, 'decision', ep);
    if (!ok) return;
    if (advice.decisionId === 'SPEND_CHECK' && fsm().can('PLAN')) fsm().transition('PLAN');
    s.lock = false;
    syncPrompt();
    refresh();
  }

  /** 줄이기 목표를 저장하고 상담을 마친다. 저장값은 소비 분석 화면이 읽는다 */
  async function replySaved(ep) {
    const s = S();
    s.awaiting = 'saved';
    s.lock = true;
    const advice = s.advice || currentAdvice();
    const plan = LA.spendPlan(advice);
    A().session.spendGoal = {
      total: plan.total,
      target: plan.target,
      after: plan.after,
      items: plan.items.map((it) => ({ id: it.id, category: it.category, label: it.label, saved: it.saved })),
      savedAt: Date.now(),
    };
    const ok = await say(LS.savedMessage(advice), 'save', ep);
    if (!ok) return;
    if (fsm().can('DONE')) fsm().transition('DONE');
    s.prompt = { mode: 'wait', typeText: '', choices: [], spoken: false, demoChoice: '' };
    s.lock = false;
    refresh();
  }

  async function replyAfterUser3(ep, mismatch) {
    const s = S();
    s.awaiting = 'profile';
    s.lock = true;
    const msg = mismatch ? LS.mismatchReply() : LS.afterSituation(s.advice || currentAdvice());
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
    const msg = s.both ? LS.bothMessage(s.advice || currentAdvice()) : LS.noAccount();
    const ok = await say(msg, 'talk', ep);
    if (!ok) return;
    s.both = false;
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

  /** 채팅을 열면 AI가 먼저 목표를 묻는다. 생각 연출 없이 글자 흐름만 쓴다 */
  async function replyGreeting(ep) {
    const s = S();
    s.awaiting = 'greeting';
    s.lock = true;
    refresh();
    const ok = await say(LS.greeting(), null, ep);
    if (!ok) return;
    s.lock = false;
    syncPrompt();
    refresh();
  }

  /** 첫 질문 선택지는 이전 자산관리 상담으로 이어 간다 */
  function toLegacy(text) {
    const f = fsm();
    if (f.can('EXIT')) f.transition('EXIT');
    if (f.can('NEW_CASE')) f.transition('NEW_CASE');
    clearType();
    A().session.lumpsum = null;
    const AF = WSP.assetFlow;
    if (AF.start()) {
      AF.agree();
      AF.setGoal(text);
    } else {
      UI().navigate('asset', {}, { replace: true });
      A().refresh(SCREENS);
    }
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
    if (kind === 'greeting') return replyGreeting(ep);
    if (kind === 'saved') return replySaved(ep);
    s.awaiting = '';
    s.lock = false;
    return Promise.resolve();
  }

  function accept(text, choiceId) {
    const s = S();
    if (!s || s.lock) return Promise.resolve();
    const spoken = (text || '').trim();
    if (!spoken) return Promise.resolve();
    if (fsm().state === 'INTRO' && choiceId && String(choiceId).indexOf('intro-') === 0) {
      toLegacy(spoken);
      return Promise.resolve();
    }
    clearType();
    s.typing = false;
    s.draft = '';
    push({ role: 'user', text: spoken });
    const ep = A().epoch();
    const st = fsm().state;
    s.lock = true;
    /* 답한 뒤에는 이전 질문의 선택지를 치운다. 응답이 끝나면 syncPrompt가 다음 선택지를 채운다 */
    s.prompt = { mode: 'wait', typeText: '', choices: [], spoken: false, demoChoice: '' };
    refresh();
    return enqueue(async () => {
      if (stale(ep)) return;
      if (st === 'INTRO') {
        s.goalKind = 'LUMP_SUM';
        return replyAnalysis(ep);
      }
      if (st === 'GOAL') {
        s.goal = goalFrom(spoken, choiceId);
        return replyDecision(ep);
      }
      if (st === 'DEBT_CHECK') {
        s.situationDone = true;
        const mismatch = choiceId && String(choiceId).indexOf('mis-') === 0;
        if (!mismatch) s.investFocus = true;
        return replyAfterUser3(ep, mismatch);
      }
      if (st === 'SPEND_PLAN') {
        return replySaved(ep);
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
        if (!choiceId && /모두|둘 다|두 계좌|같이/.test(spoken)) {
          s.goalKind = 'OVERSEAS_ACCOUNT';
          s.both = true;
          return replyNoAccount(ep);
        }
        if (choiceId === 'prod-os' || (!choiceId && /해외|미국/.test(spoken))) {
          s.goalKind = 'OVERSEAS_ACCOUNT';
          return replyNoAccount(ep);
        }
        s.goalKind = choiceId === 'prod-lev' ? 'LEVERAGE' : 'DOMESTIC_STOCK';
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

  /** 입력창을 눌렀을 때만 호출한다. 선택지에 원하는 상황이 없을 때 보여 주는 타이핑이다 */
  function startTyping() {
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
    const s = S();
    if (scale() === 0) {
      push({ role: 'ai', blocks: LS.greeting().blocks, thoughtMs: 0 });
      s.chat[0].shown = s.chat[0].blocks.length;
      refresh();
    } else {
      const ep = A().epoch();
      s.awaiting = 'greeting';
      s.lock = true;
      enqueue(() => replyGreeting(ep));
    }
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
    if (pending > 0) return;
    s.typing = false;
    s.thinking = false;
    s.stopStream = false;
    s.chat = s.chat.filter((m) => !m.streaming);
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
    if (p.mode === 'type' && p.typeText) line = '입력창을 눌러 타이핑: ' + p.typeText;
    else if (p.mode === 'choice') line = '선택지를 누르세요: ' + (p.demoChoice || '') + (p.typeText ? ' · 맞는 게 없으면 입력창 타이핑: ' + p.typeText : '');
    const decision = s.advice ? '이번 채팅: ' + (DECISION_LABEL[s.advice.decisionId] || s.advice.decisionId) + ' · 월 여유 ' + man(Math.max(0, s.advice.surplus)) : '';
    const active = ['IDLE', 'CLOSED', 'TO_JOIN'].indexOf(f.state) === -1;
    return { active: active, line: line, spoken: p.spoken ? '우리 상황에 맞는 게 없네요?' : '', decision: decision };
  }

  WSP.lumpsumFlow = {
    open: open,
    startNew: startNew,
    resume: resume,
    accept: accept,
    startTyping: startTyping,
    finishTypeNow: finishTypeNow,
    hint: hint,
    formatRich: formatRich,
    decisionLabel: DECISION_LABEL,
  };

  /* 타이핑은 입력창을 눌렀을 때만 시작한다. 말풍선·빈 화면·다른 버튼을 눌러서는 시작하지 않는다 */
  document.addEventListener('click', (e) => {
    const field = e.target && e.target.closest ? e.target.closest('[data-screen="lumpsum"] .chat-input__field') : null;
    if (!field) return;
    if (e.target.closest('[data-action]')) return;
    startTyping();
  });

  document.addEventListener('keydown', (e) => {
    if (e.key !== 'Enter') return;
    const t = e.target;
    if (!t || t.id !== 'lumpsum-input') return;
    e.preventDefault();
    if (S() && S().typing) finishTypeNow();
    else startTyping();
  });

  WSP.registerActions({
    'lumpsum-send'() {
      const s = S();
      if (!s) return;
      if (s.chat.some((m) => m.streaming)) {
        s.stopStream = true;
        return;
      }
      if (s.typing) return finishTypeNow();
      startTyping();
    },
    'lumpsum-choice'(d) {
      if (d.id === 'spend-view') {
        if (fsm().state === 'SPEND_PLAN') UI().navigate('spend');
        return;
      }
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
    'lumpsum-toggle'(d) {
      const s = S();
      if (!s) return;
      const row = s.chat.filter((m) => m.id === d.id).pop();
      if (row) row.open = !row.open;
      refresh();
    },
  });
})();
