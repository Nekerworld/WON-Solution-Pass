/**
 * aiAgent.js
 * 시연용 모의 AI. 실제 AI API를 호출하지 않는다.
 * - 고객 문장 이해: 키워드 규칙
 * - 출력: aiSchema 구조화 출력 → 검증 → 실패 시 기본 선택지로 대체
 * - 로딩 연출: 400~1200ms 지연 (시연 패널 지연 배율 적용)
 * - 추적: 입력·출력·검증 결과를 시연 패널에 보여 준다.
 * AI는 질문·이해·설명·요약만 한다. 계산·판정·전이는 규칙 코드가 한다.
 */
(function () {
  'use strict';

  const WSP = window.WSP;
  const SC = WSP.scenario;
  const man = WSP.utils.formatMan;
  const josa = WSP.utils.josa;

  const trace = [];
  const listeners = new Set();
  let injectInvalid = false;

  function notify() {
    listeners.forEach((fn) => {
      try {
        fn(trace);
      } catch (e) {
        console.error(e);
      }
    });
  }

  function delay() {
    const scale = WSP.mockBank ? WSP.mockBank.getLatencyScale() : 1;
    return WSP.utils.sleep((400 + Math.random() * 800) * scale);
  }

  const FALLBACK = Object.freeze({
    intent: 'FALLBACK',
    message: '제가 확실하게 판단하지 못했어요. 아래 선택지에서 직접 골라 주세요.',
    actions: [{ type: 'EXPLAIN', text: '기본 선택지 표시' }],
  });

  /**
   * AI 호출 1회. producer는 구조화 출력을 만드는 순수 함수.
   * @returns {Promise<{output:object, valid:boolean, errors:string[], fallback:boolean}>}
   */
  async function run(task, input, ctx, producer) {
    const t0 = Date.now();
    await delay();
    let output = producer();
    if (injectInvalid) {
      injectInvalid = false;
      output = Object.assign({}, output, {
        actions: (output.actions || []).concat([{ type: 'CALL_TOOL', tool: 'submitApplication' }]),
        message: output.message + ' 가입이 완료됐어요.',
      });
    }
    const v = WSP.aiSchema.validate(output, ctx);
    const entry = {
      id: 'AI-' + (trace.length + 1),
      at: Date.now(),
      ms: Date.now() - t0,
      task: task,
      input: input,
      output: output,
      valid: v.valid,
      errors: v.errors,
      fallback: !v.valid,
    };
    trace.push(entry);
    if (trace.length > 30) trace.shift();
    WSP.events.add('AI', task + (v.valid ? ' → ' + output.intent : ' → 검증 실패, 기본 선택지로 대체'), v.valid ? 'info' : 'warn');
    notify();
    return v.valid ? { output: output, valid: true, errors: [], fallback: false } : { output: FALLBACK, valid: false, errors: v.errors, fallback: true, rejected: output };
  }

  /* ------------------------------------------------------------------
   * 문장 파싱 도우미
   * ------------------------------------------------------------------ */
  const NEG = /(없|안\s?(돼|되|갖|가지|챙|해)|못|분실|잃어|두고|아니|놓고)/;
  const POS = /(있|가지고|갖고|챙겼|돼요|됩니다|가능|네|예|응)/;

  function clauses(text) {
    return String(text)
      .split(/[,.!?\n]|그리고|(?<=[없있])고\s+|지만\s*|[는은]데\s*/)
      .map((s) => s.trim())
      .filter(Boolean);
  }

  function polarity(s) {
    if (NEG.test(s)) return false;
    if (POS.test(s)) return true;
    return null;
  }

  /** 고객 문장 → 고객 제약 */
  function parseConstraints(text, pendingKey) {
    const found = {};
    clauses(text).forEach((s) => {
      const p = polarity(s);
      if (p === null) return;
      if (/모바일|휴대폰\s?신분증|폰으로|휴대폰으로/.test(s)) found.hasMobileId = p;
      else if (/신분증|주민등록증|운전면허/.test(s)) found.hasIdCard = p;
      else if (/다른\s?은행|타행|타\s?은행/.test(s)) found.hasOtherBankAccount = p;
    });
    if (!Object.keys(found).length && pendingKey) {
      const p = polarity(text);
      if (p !== null) found[pendingKey] = p;
    }
    return found;
  }

  function parseAmount(text) {
    const s = String(text).replace(/,/g, '');
    let m = s.match(/(\d+(?:\.\d+)?)\s*억(?:\s*(\d+)\s*천)?/);
    if (m) return Math.round(Number(m[1]) * 1e8 + (m[2] ? Number(m[2]) * 1e7 : 0));
    m = s.match(/(\d+(?:\.\d+)?)\s*천\s*만?/);
    if (m) return Math.round(Number(m[1]) * 1e7);
    m = s.match(/(\d+(?:\.\d+)?)\s*백\s*만/);
    if (m) return Math.round(Number(m[1]) * 1e6);
    m = s.match(/(\d+(?:\.\d+)?)\s*만/);
    if (m) return Math.round(Number(m[1]) * 1e4);
    m = s.match(/(\d{5,})/);
    if (m) return Number(m[1]);
    return null;
  }

  function parseMonths(text) {
    const s = String(text);
    let m = s.match(/(\d+(?:\.\d+)?)\s*년/);
    if (m) return Math.round(Number(m[1]) * 12);
    m = s.match(/(\d+)\s*개월/);
    if (m) return Number(m[1]);
    if (/반년/.test(s)) return 6;
    if (/내년/.test(s)) return 12;
    return null;
  }

  const isEscalate = (t) => /상담(원|사)?|직원|사람(이랑|과|하고)|연결해/.test(t);
  const isExit = (t) => /그만|종료|나중에|안 할래|취소할래/.test(t);
  const isMismatch = (t) => /(완료|끝났|했)[^]*?(다시|또)|다시\s?하래|안\s?넘어가/.test(t);
  const isStopQuestions = (t) => /질문은?\s?그만|지금\s?정보로|그냥\s?알려/.test(t);

  /* ------------------------------------------------------------------
   * 가입 지원
   * ------------------------------------------------------------------ */
  const CONSTRAINT_QUESTION = {
    hasIdCard: '지금 실물 신분증(주민등록증이나 운전면허증)을 갖고 계세요?',
    hasMobileId: '휴대폰에 모바일 신분증(모바일 운전면허·모바일 주민등록증)이 등록돼 있나요?',
    hasOtherBankAccount: '다른 은행에 본인 명의 계좌가 있으세요?',
  };
  const CONSTRAINT_WHY = {
    hasIdCard: '실명확인 방법이 신분증 유무에 따라 달라져요.',
    hasMobileId: '실물 신분증이 없어도 모바일 신분증으로 실명확인을 할 수 있어요.',
    hasOtherBankAccount: '다른 은행 계좌가 있으면 1원 입금으로 계좌를 바로 만들 수 있어요.',
  };

  function factLabel(f) {
    return SC.FACTS[f].label;
  }

  function joinExplainCheck(evaluation, route) {
    return run('가입 조건 설명', { conditions: evaluation.conditions.map((c) => c.id + ':' + c.status), route: route.status }, {}, () => {
      const unmet = evaluation.conditions.filter((c) => c.status !== 'MET');
      const met = evaluation.conditions.filter((c) => c.status === 'MET');
      let message;
      if (!unmet.length) message = '가입 조건을 모두 갖추셨어요. 가입 정보를 확인하고 승인만 하시면 돼요.';
      else
        message =
          '은행 기록을 확인해 보니 ' +
          (met.length ? josa(met.map((c) => c.label).join(', '), '은') + ' 이미 충족했고, ' : '') +
          '가입 전에 ' +
          unmet.length +
          '가지(' +
          unmet.map((c) => c.label).join(', ') +
          ')가 더 필요해요. 처음 거래하시는 분께 흔한 상황이에요.';
      return { intent: 'EXPLAIN_CONDITIONS', message: message, actions: [{ type: 'EXPLAIN', text: message }] };
    });
  }

  function joinAsk(key, skipped) {
    return run('고객 질문 생성', { constraint: key, skipped: skipped || [] }, { allowedQuestionIds: ['Q_' + key] }, () => ({
      intent: 'ASK_CONSTRAINT',
      message: CONSTRAINT_QUESTION[key],
      why: CONSTRAINT_WHY[key],
      actions: [{ type: 'ASK', questionId: 'Q_' + key, key: key, text: CONSTRAINT_QUESTION[key] }],
    }));
  }

  function joinInterpret(text, ctx) {
    return run('고객 답변 이해', { text: text, pending: ctx.pendingKey || null }, {}, () => {
      if (isEscalate(text)) return { intent: 'REQUEST_CONSULT', message: '상담 연결을 도와드릴게요.', actions: [{ type: 'ESCALATE', reason: 'CUSTOMER_REQUEST' }] };
      if (isExit(text)) return { intent: 'EXIT', message: '가입 지원을 멈출게요.', actions: [{ type: 'END' }] };
      if (isMismatch(text))
        return {
          intent: 'REPORT_MISMATCH',
          message: '업무를 마쳤는데 다시 하라고 나왔군요. 은행 기록을 다시 조회해서 원인을 확인할게요.',
          actions: [{ type: 'CALL_TOOL', tool: 'checkConditions' }],
        };
      const found = parseConstraints(text, ctx.pendingKey);
      const keys = Object.keys(found);
      if (!keys.length)
        return { intent: 'UNCLEAR', message: '말씀을 정확히 이해하지 못했어요. 아래 버튼으로 답해 주셔도 돼요.', actions: [{ type: 'EXPLAIN', text: 'unclear' }] };
      return {
        intent: 'SET_CONSTRAINTS',
        message: keys.map((k) => SC.CONSTRAINTS[k].label + ': ' + (found[k] ? '있음' : '없음')).join(', ') + '으로 이해했어요.',
        actions: keys.map((k) => ({ type: 'SET_CONSTRAINT', key: k, value: found[k] })),
      };
    });
  }

  function joinPresent(route, evaluation) {
    const allowed = route.options.map((o) => o.actionId);
    return run('해결 방법 안내', { steps: route.steps.map((s) => s.actionId), options: allowed }, { allowedActionIds: allowed }, () => {
      const first = WSP.pathfinder.getAction(route.steps[0].actionId);
      const fact = Object.keys(first.effects)[0];
      const order = route.steps.map((s, i) => i + 1 + '. ' + s.label).join('\n');
      const usable = route.options.filter((o) => o.availability !== 'BLOCKED' && o.reachable);
      let message = '지금 할 수 있는 순서는 아래와 같아요. 먼저 ' + factLabel(fact) + '부터 진행해요.';
      if (usable.length > 1) message += ' 방법이 ' + usable.length + '가지 있으니 편한 쪽을 고르세요.';
      return {
        intent: 'PRESENT_OPTIONS',
        message: message,
        plan: order,
        actions: [{ type: 'PRESENT_OPTIONS', options: usable.map((o) => o.actionId) }],
      };
    });
  }

  function joinExplainNoRoute(cause) {
    return run('경로 없음 설명', { cause: cause }, {}, () => {
      let message = '앱 안에서 이어서 진행할 방법을 찾지 못했어요.';
      if (cause && cause.type === 'CYCLE') {
        const names = cause.chain.map(factLabel);
        message =
          josa(names[0], '을') + ' 만들려면 ' + josa(names[1], '이') + ' 필요하고, ' + josa(names[1], '을') + ' 만들려면 다시 ' + josa(names[0], '이') + ' 필요해 앱 안에서는 순서가 막혀요. 상담 연결이나 영업점 방문으로 풀 수 있어요.';
      } else if (cause && (cause.type === 'NO_METHOD' || cause.type === 'NO_TASK')) {
        message = josa(factLabel(cause.fact), '을') + ' 해결할 수 있는 방법이 지금 상황에서는 모두 막혀 있어요. 상담 연결을 도와드릴게요.';
      }
      return { intent: 'NO_ROUTE', message: message, actions: [{ type: 'ESCALATE', reason: cause ? cause.type : 'NO_PATH' }] };
    });
  }

  function joinAfterRecheck(kind, detail) {
    return run('업무 후 재확인 설명', { result: kind, detail: detail || null }, {}, () => {
      const msg = {
        ALL_MET: '은행 기록으로 다시 확인했어요. 가입 조건을 모두 갖추셨어요. 이제 가입 정보를 확인하고 승인해 주세요.',
        REMAINING: '은행 기록으로 다시 확인했어요. ' + (detail || '') + ' 남은 조건을 이어서 해결해요.',
        EXCEPTION: '업무 결과가 은행 기록과 맞지 않거나 아직 확인되지 않았어요. 원인을 확인할게요.',
      }[kind];
      return { intent: 'RECHECK_' + kind, message: msg, actions: [{ type: 'EXPLAIN', text: msg }] };
    });
  }

  function handoffSummary(ctx) {
    return run('상담 인계 요약', { reason: ctx.reason }, {}, () => {
      const lines = ctx.lines ? ctx.lines.slice() : [];
      if (!ctx.lines) lines.push('목표: ' + (ctx.productName || '상품') + ' 가입');
      if (ctx.done && ctx.done.length) lines.push('완료한 업무: ' + ctx.done.join(', '));
      if (ctx.remaining && ctx.remaining.length) lines.push('남은 조건: ' + ctx.remaining.join(', '));
      if (ctx.constraints && ctx.constraints.length) lines.push('고객 상황: ' + ctx.constraints.join(', '));
      if (ctx.reasonText) lines.push('연결 사유: ' + ctx.reasonText);
      const message = '상담사가 처음부터 다시 묻지 않도록 지금까지의 상황을 정리했어요.';
      return { intent: 'HANDOFF_SUMMARY', message: message, summary: lines, actions: [{ type: 'ESCALATE', reason: ctx.reason || 'HANDOFF' }] };
    });
  }

  /* ------------------------------------------------------------------
   * 자산관리 상담
   * ------------------------------------------------------------------ */
  const AA = () => WSP.assetAdvisor;

  function assetGoal(text) {
    return run('상담 목적 이해', { text: text }, { infoKeys: ['goalMonths', 'goalAmount'] }, () => {
      const purpose = /비상|급할\s?때|예비/.test(text) ? 'EMERGENCY' : 'GOAL_SAVING';
      const actions = [];
      const months = parseMonths(text);
      const amount = parseAmount(text);
      if (months) actions.push({ type: 'SET_INFO', key: 'goalMonths', value: months, source: 'STATED' });
      if (amount) actions.push({ type: 'SET_INFO', key: 'goalAmount', value: amount, source: 'STATED' });
      const label = AA().PURPOSES[purpose].label;
      const message =
        "'" + label + "' 상담으로 이해했어요." + (months ? ' 기간은 ' + josa(AA().display('goalMonths', months), '로') + ' 볼게요.' : '') + (amount ? ' 목표 금액은 ' + man(amount) + '이에요.' : '');
      return { intent: 'SET_PURPOSE', purpose: purpose, message: message, actions: actions };
    });
  }

  function assetInterpret(metrics) {
    return run('지표 해석', { metrics: metrics.list.map((m) => m.key + '=' + m.value) }, {}, () => {
      const b = metrics.byKey;
      const parts = [];
      if (b.surplus.value != null) parts.push('매달 약 ' + josa(b.surplus.text, '이') + ' 남고, 그중 무리 없이 모을 수 있는 돈은 월 ' + b.capacity.text + ' 정도예요');
      if (b.emergencyMonths.value != null) parts.push('바로 쓸 수 있는 예금은 생활비 ' + b.emergencyMonths.text + '치예요');
      if (b.needMonthly.value != null)
        parts.push('목표를 채우려면 매달 ' + josa(b.needMonthly.text, '이') + ' 필요해요' + (metrics.feasible === false ? '. 지금 여유보다 많아서 조정이 필요해요' : ''));
      const message = parts.length ? parts.join('. ') + '.' : '지금 정보로는 계산할 수 있는 게 많지 않아요.';
      return { intent: 'INTERPRET', message: message, actions: [{ type: 'EXPLAIN', text: message }] };
    });
  }

  function assetAsk(q, gap) {
    return run('추가 질문 생성', { question: q.id, gap: gap.level }, { allowedQuestionIds: [q.id] }, () => ({
      intent: 'ASK_INFO',
      message: (gap.note ? gap.note + ' ' : '') + q.text,
      why: q.why,
      actions: [{ type: 'ASK', questionId: q.id, key: q.key, text: q.text }],
    }));
  }

  const UNKNOWN_REPLY = '괜찮아요. 아는 정보로 계속할게요.';
  const REFUSED_REPLY = '알겠어요. 그 부분은 빼고 계속할게요.';
  const STOP_REPLY = '알겠어요. 지금까지 들은 내용으로 알려 드릴게요.';

  function assetAnswer(text, q) {
    return run('답변 이해', { text: text, question: q ? q.id : null }, { infoKeys: Object.keys(AA().ITEMS) }, () => {
      if (isEscalate(text)) return { intent: 'REQUEST_CONSULT', message: '상담 연결을 도와드릴게요.', actions: [{ type: 'ESCALATE', reason: 'CUSTOMER_REQUEST' }] };
      if (isStopQuestions(text)) return { intent: 'STOP_QUESTIONS', message: STOP_REPLY, actions: [{ type: 'STOP_QUESTIONS' }] };
      if (isExit(text)) return { intent: 'EXIT', message: '상담을 마칠게요.', actions: [{ type: 'END' }] };
      if (/모르|글쎄|잘\s?몰/.test(text)) return { intent: 'UNKNOWN', message: UNKNOWN_REPLY, actions: [{ type: 'HOLD', reason: 'UNKNOWN' }] };
      if (/말하기\s?싫|답하고\s?싶지|비밀|안\s?알려/.test(text)) return { intent: 'REFUSED', message: REFUSED_REPLY, actions: [{ type: 'HOLD', reason: 'REFUSED' }] };
      if (!q) return { intent: 'UNCLEAR', message: '말씀을 정확히 이해하지 못했어요.', actions: [{ type: 'EXPLAIN', text: 'unclear' }] };
      let value = AA().ITEMS[q.key].kind === 'months' ? parseMonths(text) : parseAmount(text);
      if (value == null && q.key === 'plannedLumpSum' && /없/.test(text)) value = 0;
      if (value == null) return { intent: 'UNCLEAR', message: '금액이나 기간을 알아듣지 못했어요. 아래 버튼으로 골라 주셔도 돼요.', actions: [{ type: 'EXPLAIN', text: 'unclear' }] };
      return {
        intent: 'SET_INFO',
        message: josa(AA().ITEMS[q.key].label, '을') + ' ' + josa(AA().display(q.key, value), '로') + ' 반영했어요.',
        actions: [{ type: 'SET_INFO', key: q.key, value: value, source: 'STATED' }],
      };
    });
  }

  function assetModify(text) {
    return run('조건 수정 이해', { text: text }, { infoKeys: Object.keys(AA().ITEMS) }, () => {
      const actions = [];
      const months = parseMonths(text);
      const amount = parseAmount(text);
      if (months) actions.push({ type: 'SET_INFO', key: 'goalMonths', value: months, source: 'STATED' });
      if (amount != null) {
        let key = 'goalAmount';
        if (/월|매달|달마다|적립/.test(text)) key = 'monthlySavingPref';
        else if (/소득|월급|급여/.test(text)) key = 'monthlyIncome';
        else if (/지출|생활비/.test(text)) key = 'monthlyExpense';
        else if (/경조사|결혼|이사|목돈.*나가/.test(text)) key = 'plannedLumpSum';
        actions.push({ type: 'SET_INFO', key: key, value: amount, source: 'STATED' });
      }
      if (!actions.length) return { intent: 'UNCLEAR', message: '바꾸실 조건을 이해하지 못했어요. 예: "기간을 3년으로", "월 80만원씩"', actions: [{ type: 'EXPLAIN', text: 'unclear' }] };
      return {
        intent: 'MODIFY',
        message: josa(actions.map((a) => AA().ITEMS[a.key].label + ' ' + AA().display(a.key, a.value)).join(', '), '로') + ' 바꿔서 다시 계산할게요.',
        actions: actions,
      };
    });
  }

  function assetPropose(basis, level, metrics) {
    return run('방향 제안 문장', { level: level, basis: { monthly: basis.monthly, months: basis.months, feasible: basis.feasible } }, {}, () => {
      const b = metrics.byKey;
      let text;
      if (basis.monthly == null) text = '지금 정보로는 월 적립액을 계산하기 어려워요.';
      else {
        text = '매달 ' + man(basis.monthly) + '씩' + (basis.months ? ' ' + AA().display('goalMonths', basis.months) + ' 동안' : '') + ' 모아 보시는 걸 제안해요.';
        if (b.expectedAmount.value != null) text += ' 기간이 끝나면 약 ' + josa(man(b.expectedAmount.value), '이') + ' 모여요.';
        if (basis.feasible === false) text += ' 목표인 ' + b.target.text + '에는 못 미쳐서, 바꿀 수 있는 방법도 함께 보여 드릴게요.';
      }
      const label = (keys) => keys.map((k) => AA().ITEMS[k].label).join('·');
      const est = basis.estimated || [];
      const unc = basis.unconfirmed || [];
      if (est.length && unc.length) text += ' ' + josa(label(est), '은') + ' 입출금 내역으로 추정한 값이고 ' + josa(label(unc), '은') + ' 확인하지 못해서, 실제와 다를 수 있어요.';
      else if (est.length) text += ' ' + josa(label(est), '은') + ' 입출금 내역으로 추정한 값이라 실제와 다를 수 있어요.';
      else if (unc.length) text += ' ' + josa(label(unc), '은') + ' 확인하지 못해서 실제와 다를 수 있어요.';
      return { intent: 'PROPOSE', message: text, actions: [{ type: 'PROPOSE', text: text, level: level }] };
    });
  }

  WSP.aiAgent = {
    run: run,
    trace: () => trace.slice(),
    clearTrace: () => {
      trace.length = 0;
      notify();
    },
    subscribe: (fn) => {
      listeners.add(fn);
      return () => listeners.delete(fn);
    },
    injectInvalidNext: () => (injectInvalid = true),
    isInjecting: () => injectInvalid,
    REPLY: { UNKNOWN: UNKNOWN_REPLY, REFUSED: REFUSED_REPLY, STOP: STOP_REPLY },
    CONSTRAINT_QUESTION: CONSTRAINT_QUESTION,
    CONSTRAINT_WHY: CONSTRAINT_WHY,
    parse: { constraints: parseConstraints, amount: parseAmount, months: parseMonths, isEscalate: isEscalate, isExit: isExit, isMismatch: isMismatch, isStopQuestions: isStopQuestions },
    join: { explainCheck: joinExplainCheck, ask: joinAsk, interpret: joinInterpret, present: joinPresent, explainNoRoute: joinExplainNoRoute, afterRecheck: joinAfterRecheck },
    handoffSummary: handoffSummary,
    asset: { goal: assetGoal, interpret: assetInterpret, ask: assetAsk, answer: assetAnswer, modify: assetModify, propose: assetPropose },
  };
})();
