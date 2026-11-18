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
      purposeLabel: '',
      intent: '',
      fromEmergency: false,
      emAdvice: null,
      leverageDone: false,
      adjustChoice: '',
      keepAck: false,
      situationDone: false,
      investFocus: false,
      boldShare: null,
      shortfall: null,
      both: false,
      market: '',
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

  /** 외화 계좌를 이미 갖고 있는지 (해외주식 계좌 개설 안내 문구가 달라진다) */
  function hasFx() {
    const st = WSP.store.getState();
    return !!(st && st.facts && st.facts.hasFxAccount === true);
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
    else if (st === 'GOAL' && s.intent === 'EMERGENCY')
      prompt = { mode: 'choice', typeText: T.EMERGENCY, choices: LS.emergencyChoices(s.emAdvice), spoken: false, demoChoice: LS.emergencyChoices(s.emAdvice)[0].text };
    else if (st === 'GOAL') prompt = { mode: 'choice', typeText: T.GOAL, choices: LS.goalChoices(), spoken: false, demoChoice: '3년 안에 1억' };
    else if (st === 'DEBT_CHECK') {
      /* 판단에 따라 선택지가 다르다. 투자로도 어려우면 목표 조정과 "그래도 투자"를 함께 보여 준다 */
      const choices = LS.investChoices(s.advice, s.goal);
      const yes = choices.filter((c) => c.id === 'inv-yes')[0];
      prompt = { mode: 'choice', typeText: LS.situationText(), choices: choices, spoken: false, demoChoice: yes ? yes.text : choices[0].text };
    }
    else if (st === 'PROFILING') prompt = { mode: 'choice', typeText: T.PROFILING, choices: LS.experienceChoices(), spoken: false, demoChoice: '소액으로 ETF' };
    else if (st === 'LOSS') prompt = { mode: 'type', typeText: T.LOSS, choices: LS.lossChoices(), spoken: false, demoChoice: '' };
    else if (st === 'SHORTFALL')
      prompt = {
        mode: 'choice',
        typeText: '',
        choices: LS.shortfallChoices(s.shortfall, s.goal || LA.GOALS['goal-100']),
        spoken: false,
        demoChoice: LS.shortfallChoices(s.shortfall, s.goal || LA.GOALS['goal-100']).pop().text,
      };
    else if (st === 'RECOMMEND') {
      /* 레버리지는 한 번 안내하고 나면 다시 보여 주지 않는다 */
      const showLev = !!(s.advice && s.advice.leverage) && !s.leverageDone;
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
          boldShare: s.boldShare,
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
    /* 화면에 보인 선택지의 문장이 가장 정확하다. 판단에 따라 같은 id의 문장이 다르다 */
    const shown = (S() && S().prompt && S().prompt.choices) || [];
    const own = shown.find((c) => c.id === choiceId);
    if (own) return own.text;
    const maps = [LA.GOALS, LA.EXPERIENCE, LA.LOSS, LS.INVEST_CHOICES, LS.EMERGENCY_CHOICES];
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
    if (s.intent === 'EMERGENCY') s.emAdvice = advice;
    /* 남는 돈이 없으면 목표를 묻지 않고 바로 지출부터 본다. 묻고 나서 무시하지 않는다 */
    const skipGoal = !s.goal && advice.surplus <= 0;
    const msg = LS.analysisMessage(advice, s.seed, {
      goalKnown: !!s.goal,
      assumedMonths: !!(s.goal && s.goal.assumed),
      emergency: s.intent === 'EMERGENCY',
      skipGoal: skipGoal,
      purposeLabel: s.purposeLabel,
    });
    if (fsm().state === 'INTRO' && fsm().can('SENT')) fsm().transition('SENT');
    const ok = await say(msg, 'analysis', ep);
    if (!ok) return;
    if (fsm().can('SHOWN')) fsm().transition('SHOWN');
    /* 첫 말에서 목표를 이미 말했으면(결혼 자금 3천만원 3년 등) 목표를 묻지 않고 바로 판단으로 간다 */
    if (s.goal || skipGoal) return replyDecision(ep);
    s.lock = false;
    syncPrompt();
    refresh();
  }

  /**
   * 첫 말에서 목표를 읽는다. 금액과 기간이 함께 있으면 그대로 쓰고,
   * 금액만 있으면 기간을 3년으로 가정한다(화면에서 가정했다고 밝힌다). 금액이 없으면 null이라 목표를 따로 묻는다.
   */
  async function introGoal(text) {
    try {
      const ai = await WSP.aiAgent.asset.goal(text);
      const acts = ai && ai.valid && ai.output ? ai.output.actions || [] : [];
      const pick = (key) => {
        const hit = acts.find((x) => x.type === 'SET_INFO' && x.key === key);
        return hit ? hit.value : null;
      };
      const amount = pick('goalAmount');
      const months = pick('goalMonths');
      if (amount && months) return { amount: amount, months: months, text: text };
      if (amount) return { amount: amount, months: 36, text: text, assumed: true };
      return null;
    } catch (e) {
      return null;
    }
  }

  /** 비상자금만 보다가 목돈 마련도 보겠다고 했을 때: 목표를 묻는다 */
  async function replyGoalAsk(ep) {
    const s = S();
    s.awaiting = 'goalask';
    s.lock = true;
    const ok = await say(LS.goalAskMessage(s.emAdvice), 'talk', ep);
    if (!ok) return;
    s.lock = false;
    syncPrompt();
    refresh();
  }

  /** 비상자금만 보고 마칠 때: 안내 한 줄을 남기고 상담을 닫는다 */
  async function replyEmergencyStop(ep) {
    const s = S();
    s.lock = true;
    const ok = await say(LS.emergencyStop(s.emAdvice), 'talk', ep);
    if (!ok) return;
    if (fsm().can('EXIT')) fsm().transition('EXIT');
    s.prompt = { mode: 'wait', typeText: '', choices: [], spoken: false, demoChoice: '' };
    s.lock = false;
    refresh();
  }

  /** 해외주식 첫 시작: 외화 계좌 안내와 개설 질문. 목표는 묻지 않는다 */
  async function replyOverseasIntro(ep) {
    const s = S();
    s.awaiting = 'overseas';
    s.lock = true;
    refresh();
    if (fsm().state === 'INTRO' && fsm().can('OVERSEAS')) fsm().transition('OVERSEAS');
    const ok = await say(LS.overseasIntro(hasFx()), 'talk', ep);
    if (!ok) return;
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
    /* 비상자금 칩에서 이어졌으면 채우는 방법은 이미 말했으므로 다시 말하지 않는다 */
    const msg = LS.decisionMessage(advice, { skipFill: s.fromEmergency });
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

  /** 투자는 빼고 마칠 때: 안내 한 줄을 남기고 상담을 닫는다 */
  async function replyStop(ep) {
    const s = S();
    s.lock = true;
    const ok = await say(LS.stopMessage(s.advice), 'talk', ep);
    if (!ok) return;
    if (fsm().can('STOP')) fsm().transition('STOP');
    s.prompt = { mode: 'wait', typeText: '', choices: [], spoken: false, demoChoice: '' };
    s.lock = false;
    refresh();
  }

  async function replyAfterUser3(ep) {
    const s = S();
    s.awaiting = 'profile';
    s.lock = true;
    /* 목표를 바꿔 다시 판단한 경우처럼 성향을 이미 답했으면 다시 묻지 않고 바로 계산으로 간다 */
    const known = !!(s.expText && s.lossText);
    const msg = LS.afterSituation(s.advice || currentAdvice(), { focus: s.investFocus, profileKnown: known });
    if (!known && fsm().state === 'DEBT_CHECK' && fsm().can('SENT')) fsm().transition('SENT');
    const ok = await say(msg, 'talk', ep);
    if (!ok) return;
    if (known) return replyAfterLoss(ep);
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
    const msg = LS.recommendMessage(s.advice, s.expText, s.lossText, s.seed, { ack: s.keepAck ? LS.keepAck() : '' });
    s.keepAck = false;
    if ((fsm().state === 'LOSS' || fsm().state === 'SHORTFALL') && fsm().can('SENT')) fsm().transition('SENT');
    else if (fsm().state === 'DEBT_CHECK' && fsm().can('PROFILED')) fsm().transition('PROFILED');
    const ok = await say(msg, 'talk', ep);
    if (!ok) return;
    s.lock = false;
    syncPrompt();
    refresh();
  }

  /** 손실 답변 뒤: 투자 비중대로 목표에 못 미치면 부족분을 알리고 선택지를 낸다. 닿으면 바로 추천으로 간다 */
  async function replyAfterLoss(ep) {
    const s = S();
    s.advice = currentAdvice();
    const info = LA.shortfall(s.advice);
    if (!info) return replyRecommend(ep);
    s.shortfall = info;
    s.awaiting = 'shortfall';
    s.lock = true;
    if ((fsm().state === 'LOSS' || fsm().state === 'DEBT_CHECK') && fsm().can('GAP')) fsm().transition('GAP');
    const ok = await say(LS.shortfallMessage(s.advice, info), 'talk', ep);
    if (!ok) return;
    s.lock = false;
    syncPrompt();
    refresh();
  }

  /** 목표 조정은 새 목표로 다시 계산하고, 그래도 부족하면 같은 안내를 다시 낸다 */
  function adjustedGoal(choiceId) {
    const cur = S().goal || LA.GOALS['goal-100'];
    const base = choiceId === 'sf-amount' ? { amount: 50000000, months: 60 } : { amount: cur.amount, months: 60 };
    return Object.assign(base, { text: LS.goalText(base) });
  }

  /**
   * 목표를 바꿔 다시 판단한다. 바뀐 목표로 판단 문장·카드·질문을 다시 내고, 판단 단계(DEBT_CHECK)로 돌아간다.
   * 이미 성향을 답했으면 이어지는 "예"에서 성향을 다시 묻지 않는다.
   */
  async function replyAdjust(ep) {
    const s = S();
    s.awaiting = 'adjust';
    s.lock = true;
    s.goal = adjustedGoal(s.adjustChoice);
    s.shortfall = null;
    s.boldShare = null;
    s.advice = currentAdvice();
    if (fsm().state === 'SHORTFALL' && fsm().can('ADJUST')) fsm().transition('ADJUST');
    const ok = await say(LS.decisionMessage(s.advice, { adjusted: s.goal, skipFill: s.fromEmergency }), 'decision', ep);
    if (!ok) return;
    s.lock = false;
    syncPrompt();
    refresh();
  }

  async function handleShortfall(ep, choiceId) {
    const s = S();
    const info = s.shortfall;
    if (choiceId === 'sf-bold' && info && info.neededShare) {
      s.boldShare = info.neededShare;
      s.shortfall = null;
      return replyRecommend(ep);
    }
    if (choiceId === 'sf-amount' || choiceId === 'sf-period') {
      s.adjustChoice = choiceId;
      return replyAdjust(ep);
    }
    s.shortfall = null;
    s.keepAck = true;
    return replyRecommend(ep);
  }

  async function replySide(ep, choiceId) {
    const s = S();
    s.lock = true;
    if (fsm().can('OTHER')) fsm().transition('OTHER');
    const ok = await say(LS.sideStop(choiceId, s.advice || currentAdvice()), 'talk', ep);
    if (!ok) return;
    s.prompt = { mode: 'wait', typeText: '', choices: [], spoken: false, demoChoice: '' };
    s.lock = false;
    refresh();
  }

  /** 레버리지 상품: 이번 상담에서는 이어 가지 않는다고 말하고 국내·해외를 다시 묻는다. 이후는 이전 로직 그대로다 */
  async function replyLeverage(ep) {
    const s = S();
    s.awaiting = 'leverage';
    s.lock = true;
    s.leverageDone = true;
    const ok = await say(LS.leverageRetry(), 'talk', ep);
    if (!ok) return;
    s.lock = false;
    syncPrompt();
    refresh();
  }

  /** 계좌 개설을 다음으로 미룰 때: 마무리 말만 하고 상담을 닫는다 */
  async function replyLater(ep) {
    const s = S();
    s.awaiting = 'later';
    s.lock = true;
    const ok = await say(LS.laterMessage(), 'talk', ep);
    if (!ok) return;
    if (fsm().can('LATER')) fsm().transition('LATER');
    s.prompt = { mode: 'wait', typeText: '', choices: [], spoken: false, demoChoice: '' };
    s.lock = false;
    refresh();
  }

  async function replyNoAccount(ep) {
    const s = S();
    s.awaiting = 'noaccount';
    s.lock = true;
    if (fsm().can('OVERSEAS')) fsm().transition('OVERSEAS');
    const msg = s.both ? LS.bothMessage(s.advice || currentAdvice(), hasFx()) : LS.noAccount(s.advice || currentAdvice(), false, hasFx());
    const ok = await say(msg, 'talk', ep);
    if (!ok) return;
    s.both = false;
    s.lock = false;
    syncPrompt();
    refresh();
  }

  function handoff() {
    const s = S();
    /* 해외주식 첫 시작은 목돈 판단이 없으므로 월 투자 금액을 넘기지 않는다 */
    const advice = s.intent === 'OVERSEAS' ? null : s.advice || currentAdvice();
    const goalText = s.goal ? s.goal.text : '';
    const patch = {
      goal: goalText,
      knownFromAccount: [
        { label: '월급', text: man(s.snap.income), source: '조회' },
        { label: '지출', text: man(s.snap.expense), source: '조회' },
      ],
    };
    if (advice) {
      patch.decisionId = advice.decisionId;
      patch.financialSummary = { monthly: advice.monthlyInvest, source: '계좌 정보 기준', adjustable: true };
    }
    A().publishContext(patch);
    const started = WSP.joinFlow.start('OVERSEAS_STOCK', { goalText: goalText, monthly: advice ? advice.monthlyInvest : null });
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

  function continueAwaiting(ep) {
    const s = S();
    const kind = s.awaiting;
    if (kind === 'analysis') return replyAnalysis(ep);
    if (kind === 'decision') return replyDecision(ep);
    if (kind === 'profile') return replyAfterUser3(ep);
    if (kind === 'shortfall') return replyAfterLoss(ep);
    if (kind === 'overseas') return replyOverseasIntro(ep);
    if (kind === 'goalask') return replyGoalAsk(ep);
    if (kind === 'loss') return replyLoss(ep);
    if (kind === 'recommend') return replyRecommend(ep);
    if (kind === 'noaccount') return replyNoAccount(ep);
    if (kind === 'greeting') return replyGreeting(ep);
    if (kind === 'saved') return replySaved(ep);
    if (kind === 'adjust') return replyAdjust(ep);
    if (kind === 'leverage') return replyLeverage(ep);
    if (kind === 'later') return replyLater(ep);
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
    /* 답한 뒤에는 이전 질문의 선택지를 치운다. 응답이 끝나면 syncPrompt가 다음 선택지를 채운다 */
    s.prompt = { mode: 'wait', typeText: '', choices: [], spoken: false, demoChoice: '' };
    refresh();
    return enqueue(async () => {
      if (stale(ep)) return;
      if (st === 'INTRO') {
        /* 해외주식 첫 시작은 목돈 분석과 목표 질문 없이 계좌 개설로 바로 이어 간다 */
        if (LS.isOverseasIntro(spoken)) {
          s.goalKind = 'OVERSEAS_ACCOUNT';
          s.intent = 'OVERSEAS';
          s.market = 'os';
          return replyOverseasIntro(ep);
        }
        s.intent = '';
        s.purposeLabel = LS.purposeLabelOf(spoken);
        /* 비상자금: 같은 분석 카드로 점검 결과를 말하고, 목돈 마련도 볼지 묻는다 */
        if (LS.isEmergencyIntro(spoken)) {
          s.goalKind = 'EMERGENCY';
          s.intent = 'EMERGENCY';
          return replyAnalysis(ep);
        }
        /* 그 밖의 말은 목돈 마련. 금액과 기간을 함께 말했으면 그 목표로 바로 계산한다 */
        s.goalKind = 'LUMP_SUM';
        const goal = await introGoal(spoken);
        if (stale(ep)) return;
        if (goal) s.goal = goal;
        return replyAnalysis(ep);
      }
      if (st === 'GOAL' && s.intent === 'EMERGENCY') {
        /* 비상자금 점검 뒤 "목돈 마련도 같이 볼까요?"에 대한 답. 직접 쓴 말도 "아니요"면 마친다 */
        const no = choiceId === 'em-no' || (!choiceId && /아니|마칠|그만|괜찮|비상자금만/.test(spoken));
        if (no) return replyEmergencyStop(ep);
        s.intent = '';
        s.fromEmergency = true;
        s.goalKind = 'LUMP_SUM';
        return replyGoalAsk(ep);
      }
      if (st === 'GOAL') {
        s.goal = goalFrom(spoken, choiceId);
        return replyDecision(ep);
      }
      if (st === 'DEBT_CHECK') {
        /* 투자로도 어려울 때는 목표를 낮추거나 기간을 늘리는 선택지가 함께 나온다 */
        if (choiceId === 'sf-amount' || choiceId === 'sf-period') {
          s.adjustChoice = choiceId;
          return replyAdjust(ep);
        }
        /* 판단 뒤 "투자 비중도 같이 볼까요?"에 대한 답. 직접 쓴 말도 "아니요"면 마친다 */
        const no = choiceId === 'inv-no' || (!choiceId && /아니|마칠|그만|괜찮/.test(spoken));
        if (no) return replyStop(ep);
        s.situationDone = true;
        /* 선택지로 "예"라고 한 것과 "투자에 더 집중하고 싶어요"라고 직접 쓴 것은 다르다. 직접 쓴 말만 투자 비중을 높인다 */
        s.investFocus = !choiceId;
        return replyAfterUser3(ep);
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
        return replyAfterLoss(ep);
      }
      if (st === 'SHORTFALL') {
        return handleShortfall(ep, choiceId);
      }
      if (st === 'RECOMMEND') {
        if (!choiceId && /모두|둘 다|두 계좌|같이/.test(spoken)) {
          s.goalKind = 'OVERSEAS_ACCOUNT';
          s.both = true;
          s.market = 'both';
          return replyNoAccount(ep);
        }
        if (choiceId === 'prod-os' || (!choiceId && /해외|미국/.test(spoken))) {
          s.goalKind = 'OVERSEAS_ACCOUNT';
          s.market = 'os';
          return replyNoAccount(ep);
        }
        /* 레버리지는 이번 상담에서 이어 가지 않고, 국내·해외를 다시 묻는다 */
        if (choiceId === 'prod-lev') return replyLeverage(ep);
        s.market = 'dom';
        s.goalKind = 'DOMESTIC_STOCK';
        return replySide(ep, choiceId || 'prod-dom');
      }
      if (st === 'NO_ACCOUNT') {
        if (choiceId === 'open-no' || /다음에/.test(spoken)) return replyLater(ep);
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

  /**
   * 진행 중이던 상담이 있어도 버리고 새 채팅을 연다 (홈 프롬프트 쿠키의 물어보기).
   * 진행 중이던 비동기 응답은 epoch를 올려 이후 상태를 건드리지 못하게 한다.
   */
  function startFresh(text) {
    const f = fsm();
    if (f.state !== 'IDLE') {
      A().invalidate();
      if (f.can('EXIT')) f.transition('EXIT');
      if (f.can('NEW_CASE')) f.transition('NEW_CASE');
    }
    const ok = startNew();
    const line = (text || '').trim();
    if (ok && line) {
      /* 인사가 끝난 뒤 쿠키의 문장을 입력창에 타이핑하고 전송한다 */
      const ep = A().epoch();
      enqueue(async () => {
        if (stale(ep)) return;
        await sleep(500);
        if (stale(ep) || !S() || S().lock || fsm().state !== 'INTRO') return;
        S().prompt.typeText = line;
        startTyping();
      });
    }
    return ok;
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
    startFresh: startFresh,
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
