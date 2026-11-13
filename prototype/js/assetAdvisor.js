/**
 * assetAdvisor.js
 * 자산관리 상담의 계산·판단 규칙 (AI가 아닌 코드).
 * - 현재 고객 정보 저장소: 항목별 값·출처·근거와 변경(정정) 이력을 대화 기록과 별도로 관리한다.
 * - 고정 공식 지표: 같은 입력이면 항상 같은 값을 낸다.
 * - 상담 목적별 필수 정보, 부족·모순 판단, 질문 한도, 제안 가능 여부.
 * 공식과 기준값은 시연용 가정이다.
 */
(function () {
  'use strict';

  const WSP = window.WSP;
  const SC = WSP.scenario;
  const man = WSP.utils.formatMan;

  const ITEMS = Object.freeze({
    monthlyIncome: { label: '월 소득(세후)', kind: 'won' },
    monthlyExpense: { label: '월 지출', kind: 'won' },
    liquidAssets: { label: '예금성 자산', kind: 'won' },
    investAssets: { label: '투자 자산', kind: 'won' },
    debt: { label: '부채 잔액', kind: 'won' },
    debtPayment: { label: '월 부채 상환액', kind: 'won' },
    goalAmount: { label: '목표 금액', kind: 'won' },
    goalMonths: { label: '목표 기간', kind: 'months' },
    plannedLumpSum: { label: '예정된 목돈 지출', kind: 'won' },
    monthlySavingPref: { label: '희망 월 적립액', kind: 'won' },
  });

  const PURPOSES = Object.freeze({
    INVEST: {
      label: '해외주식 투자 시작',
      critical: ['monthlyIncome', 'monthlyExpense', 'liquidAssets'],
      important: ['investAssets', 'plannedLumpSum'],
      minimum: ['monthlyIncome', 'monthlyExpense'],
      tags: ['해외주식'],
    },
    GOAL_SAVING: {
      label: '목돈 마련',
      critical: ['monthlyIncome', 'monthlyExpense', 'goalAmount', 'goalMonths'],
      important: ['plannedLumpSum', 'liquidAssets'],
      /** 이 값이 없으면 제한적 제안도 하지 않는다 */
      minimum: ['monthlyIncome', 'monthlyExpense', 'goalMonths'],
      tags: ['목돈 마련'],
    },
    EMERGENCY: {
      label: '비상자금 점검',
      critical: ['monthlyExpense', 'liquidAssets'],
      important: ['monthlyIncome'],
      minimum: ['monthlyExpense'],
      tags: ['비상자금'],
    },
  });

  /** 질문 목록. 생활 언어와 범위 답변을 허용한다. */
  const QUESTIONS = Object.freeze({
    goalAmount: {
      id: 'Q_GOAL_AMOUNT',
      key: 'goalAmount',
      text: '목표 금액이 어느 정도인가요? 정확하지 않아도, 대략적인 범위여도 괜찮아요.',
      why: '필요한 월 적립액을 계산하려면 목표 금액이 필요해요.',
      options: [
        ['2천만원 정도', 20000000],
        ['3천만원 정도', 30000000],
        ['5천만원 정도', 50000000],
      ],
    },
    goalMonths: {
      id: 'Q_GOAL_MONTHS',
      key: 'goalMonths',
      text: '언제까지 모으고 싶으세요?',
      why: '기간에 따라 매달 모아야 할 금액이 달라져요.',
      options: [
        ['1년 안에', 12],
        ['2년 안에', 24],
        ['3년 안에', 36],
      ],
    },
    plannedLumpSum: {
      id: 'Q_LUMP_SUM',
      key: 'plannedLumpSum',
      text: '앞으로 결혼·이사·경조사처럼 목돈이 나갈 일이 예정돼 있나요?',
      why: '부채가 없어도 큰 지출이 예정돼 있으면 모으거나 투자할 수 있는 금액이 달라져요.',
      options: [
        ['없어요', 0],
        ['경조사 300만원 정도', 3000000],
        ['1천만원 정도', 10000000],
      ],
    },
    monthlyIncome: {
      id: 'Q_INCOME',
      key: 'monthlyIncome',
      text: '한 달에 손에 쥐는 소득(세후)이 어느 정도인가요?',
      why: '연결된 기관에서 소득을 확인하지 못했어요. 매달 모을 수 있는 금액을 계산하는 데 필요해요.',
      options: [
        ['250만원 정도', 2500000],
        ['300만원 정도', 3000000],
        ['350만원 정도', 3500000],
      ],
    },
    monthlyExpense: {
      id: 'Q_EXPENSE',
      key: 'monthlyExpense',
      text: '한 달 생활비는 보통 얼마 정도 쓰세요?',
      why: '연결된 기관에서 지출을 확인하지 못했어요.',
      options: [
        ['150만원 정도', 1500000],
        ['200만원 정도', 2000000],
        ['250만원 정도', 2500000],
      ],
    },
    investAssets: {
      id: 'Q_INVEST',
      key: 'investAssets',
      text: '지금 다른 증권사에서 투자하고 있는 돈이 있나요?',
      why: '연결되지 않은 증권사 정보는 확인하지 못했어요. 이미 투자 중인 돈이 많으면 새로 투자할 금액을 줄여야 해요.',
      options: [
        ['없어요', 0],
        ['500만원 정도', 5000000],
        ['1천만원 이상', 10000000],
      ],
    },
    liquidAssets: {
      id: 'Q_LIQUID',
      key: 'liquidAssets',
      text: '바로 꺼내 쓸 수 있는 예금·현금은 어느 정도 있으세요?',
      why: '비상자금을 남겨 두고 목표에 쓸 수 있는 돈을 계산하는 데 필요해요.',
      options: [
        ['500만원 정도', 5000000],
        ['1천만원 정도', 10000000],
        ['2천만원 정도', 20000000],
      ],
    },
  });

  /* ------------------------------------------------------------------
   * 현재 고객 정보 저장소 (직렬화 가능한 순수 객체)
   * ------------------------------------------------------------------ */
  function createInfo(snapshotItems) {
    const items = {};
    Object.keys(ITEMS).forEach((k) => {
      const src = snapshotItems && snapshotItems[k];
      items[k] = src
        ? { value: src.value, source: src.source, basis: src.basis, updatedAt: Date.now() }
        : { value: null, source: 'UNKNOWN', basis: '아직 확인하지 않음', updatedAt: Date.now() };
    });
    return { items: items, history: [], declined: [] };
  }

  /** 값 갱신. 이전 값이 있으면 정정 이력으로 남긴다. */
  function setItem(info, key, value, source, reason) {
    const prev = info.items[key];
    info.history.push({
      at: Date.now(),
      key: key,
      from: prev ? prev.value : null,
      fromSource: prev ? prev.source : null,
      to: value,
      toSource: source,
      reason: reason || '',
      correction: !!(prev && prev.value != null && prev.value !== value),
    });
    info.items[key] = { value: value, source: source, basis: reason || '', updatedAt: Date.now() };
    const di = info.declined.indexOf(key);
    if (di !== -1) info.declined.splice(di, 1);
  }

  /** '모름·답변 거부'는 값을 지우지 않고 미확인으로 기록한다 */
  function markDeclined(info, key, kind) {
    if (info.declined.indexOf(key) === -1) info.declined.push(key);
    info.history.push({ at: Date.now(), key: key, from: info.items[key].value, to: info.items[key].value, toSource: info.items[key].source, reason: kind === 'REFUSED' ? '답변 거부' : '모름', correction: false });
  }

  function known(info, key) {
    const it = info.items[key];
    return !!it && it.value != null;
  }

  function val(info, key) {
    return known(info, key) ? Number(info.items[key].value) : null;
  }

  function display(key, value) {
    if (value == null) return '미확인';
    const def = ITEMS[key];
    if (def && def.kind === 'months') return value % 12 === 0 ? value / 12 + '년' : value + '개월';
    return man(value);
  }

  const withRo = (word) => WSP.utils.josa(word, '로');

  /* ------------------------------------------------------------------
   * 고정 공식 지표
   * ------------------------------------------------------------------ */
  // 부동소수 오차(1400000 × 0.7 = 979999.99…)로 만원 단위가 한 칸 밀리지 않도록 원 단위로 먼저 맞춘다
  const roundDown = (v) => Math.floor(Math.round(v) / 10000) * 10000;
  const roundUp = (v) => Math.ceil(Math.round(v) / 10000) * 10000;

  function computeMetrics(info) {
    const P = SC.POLICY;
    const inc = val(info, 'monthlyIncome');
    const exp = val(info, 'monthlyExpense');
    const dp = val(info, 'debtPayment') || 0;
    const liq = val(info, 'liquidAssets');
    const goal = val(info, 'goalAmount');
    const months = val(info, 'goalMonths');
    const lump = val(info, 'plannedLumpSum');
    const pref = val(info, 'monthlySavingPref');
    const uncertainOf = (keys) => keys.filter((k) => !known(info, k) || info.items[k].source === 'ESTIMATED' || info.items[k].source === 'UNKNOWN');
    const m = [];
    const add = (key, label, value, formula, inputs, fmt) =>
      m.push({ key: key, label: label, value: value, text: value == null ? '계산 불가' : fmt ? fmt(value) : man(value), formula: formula, inputs: inputs, uncertain: uncertainOf(inputs) });

    const surplus = inc != null && exp != null ? inc - exp - dp : null;
    add('surplus', '월 여유자금', surplus, '월 소득 − 월 지출 − 월 부채 상환액', ['monthlyIncome', 'monthlyExpense', 'debtPayment']);
    const emergency = liq != null && exp ? Math.round((liq / exp) * 10) / 10 : null;
    add('emergencyMonths', '비상자금 보유 개월', emergency, '예금성 자산 ÷ 월 지출', ['liquidAssets', 'monthlyExpense'], (v) => v + '개월');
    const reserve = exp != null ? exp * P.emergencyMonths : null;
    add('reserve', '남겨 둘 비상자금', reserve, '월 지출 × ' + P.emergencyMonths + '개월', ['monthlyExpense']);
    const usable = liq != null && reserve != null ? Math.max(0, liq - reserve) : liq != null ? null : 0;
    add('usableForGoal', '목표에 쓸 수 있는 예금', usable, 'max(0, 예금성 자산 − 남겨 둘 비상자금)', ['liquidAssets', 'monthlyExpense']);
    const target = goal != null ? goal + (lump || 0) : null;
    add('target', '모아야 할 총액', target, '목표 금액 + 예정된 목돈 지출', ['goalAmount', 'plannedLumpSum']);
    const need = target != null && months ? roundUp(Math.max(0, target - (usable || 0)) / months) : null;
    add('needMonthly', '필요 월 적립액', need, '(모아야 할 총액 − 목표에 쓸 예금) ÷ 목표 기간', ['goalAmount', 'plannedLumpSum', 'liquidAssets', 'goalMonths']);
    const capacity = surplus != null ? roundDown(Math.max(0, surplus) * 0.7) : null;
    add('capacity', '무리 없는 월 적립 여력', capacity, '월 여유자금 × 70%', ['monthlyIncome', 'monthlyExpense', 'debtPayment']);
    const invest = capacity != null ? roundDown(capacity * 0.5) : null;
    add('investMonthly', '월 투자 시작 금액', invest, '무리 없는 월 적립 여력 × 50%', ['monthlyIncome', 'monthlyExpense', 'debtPayment']);
    let rec = null;
    if (pref != null) rec = pref;
    else if (capacity != null) rec = need != null ? Math.min(need, capacity) : capacity;
    add('recommendedMonthly', '제안 월 적립액', rec, pref != null ? '고객 희망 월 적립액' : 'min(필요 월 적립액, 월 적립 여력)', pref != null ? ['monthlySavingPref'] : ['goalAmount', 'monthlyIncome', 'monthlyExpense']);
    const expected = rec != null && months ? rec * months + (usable || 0) : null;
    add('expectedAmount', '기간 종료 시 예상 금액', expected, '제안 월 적립액 × 목표 기간 + 목표에 쓸 예금 (이자 제외)', ['goalMonths', 'liquidAssets']);

    const byKey = {};
    m.forEach((x) => (byKey[x.key] = x));
    return { list: m, byKey: byKey, feasible: need != null && capacity != null ? need <= capacity : null };
  }

  /* ------------------------------------------------------------------
   * 부족·모순 판단, 질문, 제안 가능 여부
   * ------------------------------------------------------------------ */
  function findGaps(info, purposeId, metrics) {
    const p = PURPOSES[purposeId] || PURPOSES.GOAL_SAVING;
    const gaps = [];
    const skip = (k) => known(info, k) || info.declined.indexOf(k) !== -1;
    p.critical.forEach((k) => !skip(k) && gaps.push({ key: k, level: 'critical', question: QUESTIONS[k] ? QUESTIONS[k].id : null }));
    p.important.forEach((k) => !skip(k) && gaps.push({ key: k, level: 'important', question: QUESTIONS[k] ? QUESTIONS[k].id : null }));
    const sur = metrics && metrics.byKey.surplus.value;
    if (sur != null && sur <= 0 && info.items.monthlyExpense.source === 'ESTIMATED' && info.declined.indexOf('monthlyExpense') === -1) {
      gaps.unshift({ key: 'monthlyExpense', level: 'contradiction', question: QUESTIONS.monthlyExpense.id, note: '추정 지출이 소득보다 많아요. 일시적인 큰 지출이 포함됐을 수 있어요.' });
    }
    return gaps;
  }

  function questionFor(gap) {
    return QUESTIONS[gap.key] || null;
  }

  function canAsk(state, gaps) {
    return state.questionsAsked < SC.POLICY.assetQuestionLimit && !state.stopRequested && gaps.some((g) => !!questionFor(g));
  }

  /** 현재 정보로 제안할 수 있는가: 최소 정보가 있어야 제한적 제안이 가능하다 */
  function proposable(info, purposeId) {
    const p = PURPOSES[purposeId] || PURPOSES.GOAL_SAVING;
    const missing = p.minimum.filter((k) => !known(info, k));
    return { ok: missing.length === 0, missing: missing };
  }

  /** 제안 재료 (문장은 AI가 만든다) */
  function proposalBasis(info, purposeId, metrics) {
    const b = metrics.byKey;
    const months = val(info, 'goalMonths');
    const p = PURPOSES[purposeId] || PURPOSES.GOAL_SAVING;
    const alternatives = [];
    if (metrics.feasible === false && months) {
      const longer = months + 12;
      const usable = b.usableForGoal.value || 0;
      const needLonger = roundUp(Math.max(0, b.target.value - usable) / longer);
      const lowered = roundDown((b.capacity.value || 0) * months + usable - (val(info, 'plannedLumpSum') || 0));
      alternatives.push({ id: 'LONGER', label: '기간을 ' + withRo(display('goalMonths', longer)) + ' 늘릴게요', detail: '매달 ' + man(needLonger) + '씩 모으면 돼요', apply: { goalMonths: longer } });
      alternatives.push({ id: 'LOWER_GOAL', label: '목표 금액을 ' + withRo(man(lowered)) + ' 줄일게요', detail: '지금 여유로 기간 안에 모을 수 있는 금액이에요', apply: { goalAmount: lowered } });
    }
    if (b.emergencyMonths.value != null && b.emergencyMonths.value < SC.POLICY.emergencyMonths) {
      alternatives.push({ id: 'EMERGENCY_FIRST', label: '비상자금부터 채울게요', detail: '생활비 ' + SC.POLICY.emergencyMonths + '개월치가 기준인데, 지금은 ' + b.emergencyMonths.text + '치예요', apply: {} });
    }
    const uncertain = Object.keys(info.items).filter((k) => p.critical.concat(p.important).indexOf(k) !== -1 && (!known(info, k) || (info.items[k].source !== 'STATED' && info.items[k].source !== 'BANK')));
    const invest = purposeId === 'INVEST';
    return {
      purposeId: PURPOSES[purposeId] ? purposeId : 'GOAL_SAVING',
      purpose: p.label,
      tags: p.tags,
      monthly: invest ? b.investMonthly.value : b.recommendedMonthly.value,
      months: invest ? null : months,
      feasible: metrics.feasible,
      alternatives: alternatives,
      uncertain: uncertain,
      estimated: uncertain.filter((k) => known(info, k)),
      unconfirmed: uncertain.filter((k) => !known(info, k)),
    };
  }

  /* ------------------------------------------------------------------
   * 고객에게 보여 줄 큰 숫자 (한 번에 3개까지)
   * ------------------------------------------------------------------ */
  function interpretFigures(metrics, purposeId) {
    const b = metrics.byKey;
    const figs = [];
    const add = (label, m, value, note, tone) => m.value != null && figs.push({ label: label, value: value, note: note || '', tone: tone || '' });
    add('매달 남는 돈', b.surplus, '월 ' + b.surplus.text, '소득에서 생활비를 뺀 금액이에요');
    if (purposeId === 'EMERGENCY') {
      add('바로 쓸 수 있는 예금', b.emergencyMonths, '생활비 ' + b.emergencyMonths.text + '치', '생활비 ' + SC.POLICY.emergencyMonths + '개월치가 기준이에요');
      add('남겨 둘 비상자금', b.reserve, b.reserve.text, '생활비 ' + SC.POLICY.emergencyMonths + '개월치예요');
      return figs;
    }
    add('무리 없이 모을 수 있는 돈', b.capacity, '월 ' + b.capacity.text, '남는 돈의 70% 정도예요');
    if (purposeId === 'INVEST') {
      const low = b.emergencyMonths.value != null && b.emergencyMonths.value < SC.POLICY.emergencyMonths;
      add('바로 쓸 수 있는 예금', b.emergencyMonths, '생활비 ' + b.emergencyMonths.text + '치', '생활비 ' + SC.POLICY.emergencyMonths + '개월치가 기준이에요', low ? 'warning' : '');
      return figs;
    }
    const short = b.needMonthly.value != null && b.capacity.value != null ? b.needMonthly.value - b.capacity.value : null;
    add('목표까지 매달 필요한 돈', b.needMonthly, '월 ' + b.needMonthly.text, short > 0 ? '여유보다 매달 ' + man(short) + ' 더 필요해요' : '', short > 0 ? 'warning' : '');
    return figs;
  }

  function proposalFigures(basis, metrics) {
    if (basis.monthly == null) return [];
    const b = metrics.byKey;
    if (basis.purposeId === 'INVEST') {
      const inv = [{ label: '매달 투자할 돈', value: '월 ' + man(basis.monthly), note: '무리 없이 모을 수 있는 돈의 절반이에요', tone: '' }];
      if (b.reserve.value != null) inv.push({ label: '예금으로 남길 돈', value: b.reserve.text, note: '생활비 ' + SC.POLICY.emergencyMonths + '개월치예요', tone: '' });
      return inv;
    }
    const figs = [{ label: '매달 모을 돈', value: '월 ' + man(basis.monthly), note: '', tone: '' }];
    if (basis.months) figs.push({ label: '모으는 기간', value: display('goalMonths', basis.months), note: '', tone: '' });
    if (b.expectedAmount.value != null) {
      const short = b.target.value != null ? b.target.value - b.expectedAmount.value : null;
      figs.push({ label: '기간이 끝나면', value: '약 ' + man(b.expectedAmount.value), note: short > 0 ? '목표보다 ' + man(short) + ' 적어요 (이자 제외)' : '이자는 빼고 계산했어요', tone: short > 0 ? 'warning' : '' });
    }
    return figs;
  }

  /** 서비스 탐색: 상담 목적·기간에 맞는 상품. 선택은 고객이 한다. */
  function matchProducts(basis) {
    return SC.PRODUCTS.filter((p) => p.goalTags.some((t) => basis.tags.indexOf(t) !== -1)).map((p) => {
      if (p.kind === 'BROKERAGE') return { productId: p.id, notes: [p.markets.join('·') + ' 주식 거래', '원화·외화 계좌 연결'], fit: true };
      const periodFit = basis.months && p.periods.length ? p.periods.indexOf(basis.months) !== -1 || p.periods.some((x) => x >= basis.months) : false;
      const amountFit = basis.monthly != null && p.maxMonthly ? basis.monthly <= p.maxMonthly : false;
      const notes = [];
      if (p.periods.length) notes.push(periodFit ? '목표 기간(' + display('goalMonths', basis.months) + ')으로 가입 가능' : '가입 기간 ' + p.periods.map((x) => display('goalMonths', x)).join('·'));
      if (p.maxMonthly && basis.monthly != null) notes.push(amountFit ? '월 ' + man(basis.monthly) + ' 적립 가능' : '월 최대 ' + man(p.maxMonthly));
      if (!p.periods.length) notes.push('언제든 입출금 가능');
      return { productId: p.id, notes: notes, fit: periodFit && (amountFit || !p.maxMonthly) };
    });
  }

  WSP.assetAdvisor = {
    ITEMS: ITEMS,
    PURPOSES: PURPOSES,
    QUESTIONS: QUESTIONS,
    createInfo: createInfo,
    setItem: setItem,
    markDeclined: markDeclined,
    known: known,
    val: val,
    display: display,
    computeMetrics: computeMetrics,
    findGaps: findGaps,
    questionFor: questionFor,
    canAsk: canAsk,
    proposable: proposable,
    proposalBasis: proposalBasis,
    interpretFigures: interpretFigures,
    proposalFigures: proposalFigures,
    matchProducts: matchProducts,
  };
})();
