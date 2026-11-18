/**
 * lumpsumAdvisor.js
 * 목돈 불리기 상담의 순수 계산. 화면 문장에 쓰는 숫자는 이 결과만 쓴다.
 * 대출 가능 여부는 계산하지 않는다. 있는 부채의 상환액만 뺀다.
 */
(function () {
  'use strict';

  const WSP = window.WSP;

  const SAVINGS_RATE = 0.032;
  /** 투자 몫의 기대 수익(가정). 화면에는 "연 6%로 가정"이라고 밝힌다 */
  const INVEST_ASSUMED_RATE = 0.06;
  const DEBT_RATE = 0.055;
  const DEBT_MONTHS = 60;
  const EMERGENCY_MIN = 3;
  const DEPOSIT_DEFAULT = 8482400;

  const GOALS = Object.freeze({
    'goal-100': { amount: 100000000, months: 36, text: '3년 안에 1억 정도 만들고 싶어요' },
    'goal-50': { amount: 50000000, months: 60, text: '5년 안에 5천만 원 만들고 싶어요' },
    'goal-20': { amount: 20000000, months: 12, text: '1년 안에 2천만 원 만들고 싶어요' },
  });

  /** 선택지에 없는 목표를 직접 입력할 때 쓰는 문장 */
  const GOAL_TYPED = Object.freeze({ amount: 80000000, months: 36, text: '3년 안에 8천만 원 정도 만들고 싶어요' });

  const EXPERIENCE = Object.freeze({
    'exp-0': { score: 0, text: '주식은 해본 적 없어요' },
    'exp-1': { score: 1, text: '소액으로 ETF 조금 해봤어요' },
    'exp-2': { score: 2, text: '국내주식은 자주 해요' },
  });

  const LOSS = Object.freeze({
    'loss-0': { score: 0, text: '떨어지면 바로 팔 것 같아요' },
    'loss-1': { score: 1, text: '불안하긴 한데 길게 보면 버틸 수 있을 것 같아요' },
    'loss-2': { score: 2, text: '더 떨어지면 더 살 수 있어요' },
  });

  function roundMan(n) {
    if (n == null || isNaN(n)) return 0;
    return Math.round(n / 10000) * 10000;
  }

  function clamp(n, lo, hi) {
    return Math.min(hi, Math.max(lo, n));
  }

  /** 원리금 균등. 잔액이 없으면 0. */
  function debtPayment(balance) {
    const p = Number(balance) || 0;
    if (p <= 0) return 0;
    const r = DEBT_RATE / 12;
    const g = Math.pow(1 + r, DEBT_MONTHS);
    return Math.round((p * r * g) / (g - 1));
  }

  function grow(amount, annual, months) {
    return (Number(amount) || 0) * Math.pow(1 + annual / 12, months);
  }

  function annuityFv(payment, annual, months) {
    const p = Number(payment) || 0;
    if (months <= 0 || p <= 0) return 0;
    const r = annual / 12;
    const g = Math.pow(1 + r, months);
    return (p * (g - 1)) / r;
  }

  function annuityPmt(target, annual, months) {
    if (months <= 0 || target <= 0) return 0;
    const r = annual / 12;
    const g = Math.pow(1 + r, months);
    return (target * r) / (g - 1);
  }

  /** 월 납입과 예금으로 목표에 닿는 최소 연 수익. 적금 금리로 되면 0. */
  function requiredYield(payment, deposit, months, goal) {
    const plain = payment * months + deposit;
    if (plain >= goal) return 0;
    let lo = 0;
    let hi = 1.2;
    for (let i = 0; i < 48; i++) {
      const mid = (lo + hi) / 2;
      const fv = annuityFv(payment, mid, months) + grow(deposit, mid, months);
      if (fv >= goal) hi = mid;
      else lo = mid;
    }
    return hi;
  }

  function experienceScore(text) {
    const t = text || '';
    if (/자주/.test(t)) return 2;
    if (/없어요|해본 적 없/.test(t)) return 0;
    if (/ETF|조금/.test(t)) return 1;
    return 1;
  }

  function lossScore(text) {
    const t = text || '';
    if (/바로 팔/.test(t)) return 0;
    if (/더 살/.test(t)) return 2;
    if (/버틸|길게/.test(t)) return 1;
    return 1;
  }

  /**
   * 안정: 손실을 바로 줄이거나, 경험이 없고 버티기만 하는 경우.
   * 적극: 경험이 많고 하락 때 더 사는 경우.
   * 그 외는 중립. 기본 문장 쌍(ETF 소액, 장기 보유)은 중립.
   */
  function inferRiskProfile(expText, lossText) {
    const experience = experienceScore(expText);
    const loss = lossScore(lossText);
    let id = 'NEUTRAL';
    if (loss === 0 || (experience === 0 && loss === 1)) id = 'STABLE';
    else if (experience === 2 && loss === 2) id = 'ACTIVE';
    return { id: id, experience: experience, loss: loss };
  }

  const PROFILE_SHARE = { STABLE: 0.25, NEUTRAL: 0.45, ACTIVE: 0.65 };
  const PROFILE_SPLIT = { STABLE: [70, 30], NEUTRAL: [55, 45], ACTIVE: [40, 60] };

  function categories(expense) {
    const weights = [
      ['식비', 0.28],
      ['주거·관리', 0.22],
      ['교통', 0.12],
      ['쇼핑', 0.15],
      ['문화·여가', 0.08],
      ['기타', 0.15],
    ];
    let used = 0;
    return weights.map((w, i) => {
      const amount = i === weights.length - 1 ? Math.max(0, expense - used) : Math.round(expense * w[1]);
      used += amount;
      return { label: w[0], ratio: w[1], amount: amount };
    });
  }

  function fig(label, value, note, tone) {
    return { label: label, value: value, note: note || '', tone: tone || '' };
  }

  /** 어림한 금액은 만원 단위로 맞추고 앞에 "약"을 붙인다. 0은 "0원", 음수는 "약 -10만원" */
  function about(n) {
    const v = roundMan(n);
    if (v === 0) return '0원';
    return '약 ' + (v < 0 ? '-' : '') + WSP.utils.formatMan(Math.abs(v));
  }

  /** 음수도 만원 단위로 쓴다. -100000 → "-10만원" */
  function manSigned(n) {
    const v = Number(n) || 0;
    return (v < 0 ? '-' : '') + WSP.utils.formatMan(Math.abs(v));
  }

  /**
   * 줄이기 후보. 노력이 적게 드는 순서(effort)로 담는다.
   * rate는 해당 항목 지출에서 줄일 수 있는 비율이다. 주거·관리와 교통은 고정비라 후보가 아니다.
   */
  const CUT_POOL = Object.freeze([
    { id: 'subs', category: '문화·여가', label: '구독 서비스 정리', rate: 0.3, effort: 1, reason: '자주 안 쓰는 구독부터 정리하면 생활 불편이 거의 없어요' },
    { id: 'impulse', category: '쇼핑', label: '충동구매 줄이기', rate: 0.3, effort: 2, reason: '월 후반에 몰려 있어서 줄이기 가장 쉬워요' },
    { id: 'delivery', category: '식비', label: '배달 횟수 줄이기', rate: 0.1, effort: 3, reason: '배달을 조금만 줄여도 금액이 커요' },
    { id: 'small', category: '기타', label: '소액 결제 정리', rate: 0.2, effort: 4, reason: '건별 금액은 작지만 모이면 커져요' },
  ]);
  const FIXED_CATEGORIES = Object.freeze(['주거·관리', '교통']);
  const SPARE_GOAL = 100000;

  /**
   * 지출 줄이기 계획. 부족한 금액에 여유 목표(10만원)를 더한 만큼만 줄인다.
   * 후보를 노력 순으로 담다가 필요한 금액에 닿으면 멈추고, 마지막 후보는 필요한 만큼으로 줄인다. 금액은 만원 단위다.
   * 반환: items[{id,category,label,reason,rate,amount,saved,trimmed}], target, total, after, enough
   */
  function spendPlan(a, targetOverride) {
    const cats = a.categories || [];
    const target = targetOverride != null ? roundMan(Math.max(0, targetOverride)) : roundMan(Math.max(0, -a.surplus) + SPARE_GOAL);
    const items = [];
    let total = 0;
    CUT_POOL.slice()
      .sort((x, y) => x.effort - y.effort)
      .forEach((p) => {
        if (total >= target) return;
        const c = cats.filter((x) => x.label === p.category)[0];
        if (!c) return;
        const full = roundMan(c.amount * p.rate);
        if (full <= 0) return;
        const need = roundMan(target - total);
        const saved = Math.min(full, need);
        if (saved <= 0) return;
        items.push({ id: p.id, category: p.category, label: p.label, reason: p.reason, rate: p.rate, amount: c.amount, saved: saved, trimmed: saved < full });
        total += saved;
      });
    const after = a.surplus + total;
    return { items: items, target: target, total: total, after: after, enough: after > 0 };
  }

  /**
   * 적금 + 투자 제안(MIX)에서 소비를 줄이면 필요한 연 수익이 얼마나 내려가는지 계산한다.
   * 줄일 목표는 적금만으로 목표를 메우는 데 부족한 월 저축액이고, 후보 풀이 담을 수 있는 만큼만 줄인다.
   * 반환: plan(spendPlan 결과), yieldBefore, yieldAfter(연 수익률 소수), 없으면 null
   */
  function cutForYield(a) {
    if (a.decisionId !== 'MIX') return null;
    const saveMonthly = Math.max(0, a.surplus);
    const extra = roundMan(Math.max(0, a.requiredMonthly - saveMonthly));
    if (extra <= 0) return null;
    const plan = spendPlan(a, extra);
    if (plan.total <= 0) return null;
    const yieldBefore = requiredYield(saveMonthly, a.deposit, a.goalMonths, a.goalAmount);
    const yieldAfter = requiredYield(saveMonthly + plan.total, a.deposit, a.goalMonths, a.goalAmount);
    return { plan: plan, extra: extra, yieldBefore: yieldBefore, yieldAfter: yieldAfter };
  }

  /** 지난달 대비 증감(%). 이번 달 지출 = 지난달 × (1 + 증감) */
  const MONTH_CHANGE = Object.freeze({ 식비: 4, '주거·관리': 1, 교통: -2, 쇼핑: 12, '문화·여가': 9, 기타: -3 });
  const INSIGHT_SOURCE = '최근 3개월 카드·계좌 거래 기준';

  /**
   * 소비 분석 화면과 같은 방식의 요약. 페르소나의 지출에서 고정 비율로 계산한다.
   * 반환: source, rows[{label,amount,prev,changePct}], tags[{id,text}], 패턴 숫자
   */
  function spendInsight(a) {
    const cats = a.categories || [];
    const rows = cats.map((c) => {
      const pct = MONTH_CHANGE[c.label] || 0;
      return { label: c.label, ratio: c.ratio, amount: c.amount, prev: Math.round(c.amount / (1 + pct / 100) / 1000) * 1000, changePct: pct };
    });
    const by = (label) => cats.filter((c) => c.label === label)[0] || { amount: 0 };
    const subsAmount = Math.max(10000, roundMan(by('문화·여가').amount * 0.5));
    const deliveryCount = Math.max(1, Math.round((by('식비').amount * 0.4) / 25000));
    const weekendShare = 41;
    const lateShopping = 62;
    const subsCount = 4;
    const tags = [
      { id: 'weekend', text: '주말 소비 비중 ' + weekendShare + '%' },
      { id: 'subs', text: '정기결제 ' + subsCount + '건 · 월 ' + WSP.utils.formatMan(subsAmount) },
      { id: 'late', text: '쇼핑 ' + lateShopping + '% 월 후반 집중' },
      { id: 'delivery', text: '배달·외식 월 ' + deliveryCount + '회' },
    ];
    return { source: INSIGHT_SOURCE, rows: rows, tags: tags, weekendShare: weekendShare, lateShopping: lateShopping, subsCount: subsCount, subsAmount: subsAmount, deliveryCount: deliveryCount };
  }

  /**
   * 목표 기간 말의 예상 금액. 여유 중 투자 몫은 연 6%(가정), 나머지 여유와 예금은 적금 금리로 본다.
   * share가 같으면 advise의 monthlyInvest와 같은 방식으로 나눈다.
   */
  function plannedFuture(a, share) {
    const months = a.goalMonths;
    const save = Math.max(0, a.surplus);
    const invest = roundMan(save * share);
    return Math.round(annuityFv(invest, INVEST_ASSUMED_RATE, months) + annuityFv(save - invest, SAVINGS_RATE, months) + grow(a.deposit, SAVINGS_RATE, months));
  }

  /**
   * 적금 + 투자(MIX)에서 여유 돈을 전부 투자해도(연 6% 가정) 목표에 못 닿는지 본다.
   * 못 닿으면 { planned: 전부 투자했을 때 예상 금액, short: 모자란 돈, yieldRate: 필요한 연 수익(소수), unrealistic: 연 12% 이상 }.
   * 닿거나 MIX가 아니면 null. 성향을 묻기 전에 "투자로도 어렵다"를 먼저 알리는 데 쓴다.
   */
  function infeasible(a) {
    if (!a || a.decisionId !== 'MIX' || a.surplus <= 0) return null;
    const planned = plannedFuture(a, 1);
    if (planned >= a.goalAmount) return null;
    return { planned: planned, short: a.goalAmount - planned, yieldRate: a.yieldRate, unrealistic: a.yieldRate >= 0.12 };
  }

  /** 부족하면 "약 24만원 부족", 아니면 about과 같다. 음수를 그대로 쓰지 않는다 */
  function aboutGap(n) {
    const v = roundMan(n);
    if (v < 0) return '약 ' + WSP.utils.formatMan(Math.abs(v)) + ' 부족';
    return about(v);
  }

  /**
   * 적금 + 투자(MIX)에서 투자 비중대로 해도 목표에 못 미치는지 본다.
   * 못 미치면 { shortfall: 부족한 돈, planned: 예상 금액, neededShare: 목표에 닿는 투자 비중(5% 단위, 없으면 null) }.
   * 닿는다면 neededShare가 그 비중이고, 여유를 전부 투자해도 닿지 않으면 null이다.
   */
  function shortfall(a) {
    if (!a || a.decisionId !== 'MIX' || a.surplus <= 0) return null;
    const planned = plannedFuture(a, a.investShare);
    if (planned >= a.goalAmount) return null;
    let needed = null;
    if (plannedFuture(a, 1) >= a.goalAmount) {
      let lo = a.investShare;
      let hi = 1;
      for (let i = 0; i < 40; i++) {
        const mid = (lo + hi) / 2;
        if (plannedFuture(a, mid) >= a.goalAmount) hi = mid;
        else lo = mid;
      }
      needed = Math.min(1, Math.ceil(hi * 20) / 20);
    }
    return {
      shortfall: a.goalAmount - planned,
      planned: planned,
      neededShare: needed,
      neededMonthly: needed == null ? null : roundMan(Math.max(0, a.surplus) * needed),
    };
  }

  /**
   * @param {{income:number,expense:number,debt:number,deposit:number,goalAmount:number,goalMonths:number,expText?:string,lossText?:string}} input
   */
  function advise(input) {
    const man = WSP.utils.formatMan;
    const income = Math.max(0, Number(input.income) || 0);
    const expense = Math.max(0, Number(input.expense) || 0);
    const debt = Math.max(0, Number(input.debt) || 0);
    const deposit = Math.max(0, input.deposit == null ? DEPOSIT_DEFAULT : Number(input.deposit) || 0);
    const goalAmount = Math.max(0, Number(input.goalAmount) || 0);
    const goalMonths = Math.max(1, Number(input.goalMonths) || 1);
    const payment = debtPayment(debt);
    const before = income - expense;
    const surplus = before - payment;
    const emergencyMonths = expense > 0 ? Math.round((deposit / expense) * 10) / 10 : 0;
    const saveMonthly = Math.max(0, surplus);
    const future = Math.round(annuityFv(saveMonthly, SAVINGS_RATE, goalMonths) + grow(deposit, SAVINGS_RATE, goalMonths));
    const gap = Math.max(0, goalAmount - future);
    const needRaw = annuityPmt(Math.max(0, goalAmount - grow(deposit, SAVINGS_RATE, goalMonths)), SAVINGS_RATE, goalMonths);
    const requiredMonthly = roundMan(Math.max(0, needRaw));
    const yieldRate = saveMonthly > 0 || deposit > 0 ? requiredYield(saveMonthly, deposit, goalMonths, goalAmount) : 1;
    const profile = inferRiskProfile(input.expText, input.lossText);

    let decisionId = 'MIX';
    if (surplus <= 0) decisionId = 'SPEND_CHECK';
    else if (debt > 0) decisionId = 'DEBT_FIRST';
    else if (emergencyMonths < EMERGENCY_MIN) decisionId = 'EMERGENCY_FIRST';
    else if (future >= goalAmount) decisionId = 'SAVINGS_ENOUGH';

    const gate = defaultRequiredYield() + 0.03;
    const leverage = decisionId === 'MIX' && profile.id === 'ACTIVE' && yieldRate >= gate;

    let share = PROFILE_SHARE[profile.id] || PROFILE_SHARE.NEUTRAL;
    if (decisionId === 'EMERGENCY_FIRST') share *= 0.5;
    if (decisionId === 'SAVINGS_ENOUGH') share *= 0.35;
    let focusApplied = false;
    if (input.investFocus && (decisionId === 'MIX' || decisionId === 'SAVINGS_ENOUGH' || decisionId === 'DEBT_FIRST')) {
      share = Math.min(0.85, share + 0.15);
      focusApplied = true;
    }
    /* 목표를 채우려고 고객이 과감한 비중을 고르면 그 비중을 쓴다 */
    let boldApplied = false;
    if (input.boldShare != null) {
      share = Math.min(1, Math.max(0, Number(input.boldShare) || 0));
      boldApplied = true;
    }
    const investBase = decisionId === 'SPEND_CHECK' ? 0 : Math.max(0, surplus);
    const monthlyInvest = roundMan(investBase * share);
    const split = PROFILE_SPLIT[profile.id] || PROFILE_SPLIT.NEUTRAL;
    /** 매달 투자할 돈의 근거 문장. 금액이 어디서 나왔는지 카드에서 바로 보이게 한다 */
    const investNote = (decisionId === 'DEBT_FIRST' ? '갚고 남는 돈 ' : '월 여유 ') + about(investBase) + '의 ' + Math.round(share * 100) + '%';

    const incomeFigs = [fig('평균 수입', about(income), ''), fig('평균 지출', about(expense), '')];
    const balanceFigs = [
      fig('월평균 여유 자금', about(Math.max(0, before)), before <= 0 ? '지출이 월급보다 많아요' : '', before <= 0 ? 'warning' : ''),
      fig('예적금 및 현금', about(deposit), '생활비 ' + emergencyMonths + '개월치', emergencyMonths < EMERGENCY_MIN ? 'warning' : ''),
    ];

    let decisionFigs = [];
    if (decisionId === 'SPEND_CHECK') {
      decisionFigs = [fig('월급', about(income), ''), fig('지출', about(expense), ''), fig('월 여유', surplus < 0 ? aboutGap(surplus) : '0원', payment > 0 ? '부채 상환 포함' : '', 'warning')];
    } else if (decisionId === 'DEBT_FIRST') {
      decisionFigs = [
        fig('갚기 전 월 여유', about(before), ''),
        fig('매달 갚을 돈', about(payment), '연 5.5% · 60개월'),
        fig('갚고 남는 여력', about(Math.max(0, surplus)), ''),
      ];
    } else if (decisionId === 'EMERGENCY_FIRST') {
      decisionFigs = [
        fig('비상자금', emergencyMonths + '개월', '기준 3개월'),
        fig('예금', about(deposit), ''),
        fig('월 여유', about(surplus), ''),
      ];
    } else if (decisionId === 'SAVINGS_ENOUGH') {
      decisionFigs = [fig('예금과 적금으로 모이는 돈', about(future), goalMonths + '개월'), fig('목표', man(goalAmount), ''), fig('월 여유', about(surplus), '')];
    } else {
      decisionFigs = [
        fig('예금과 적금으로 모이는 돈', about(future), ''),
        fig('목표까지 부족한 돈', about(gap), ''),
        fig('필요한 월 저축', about(requiredMonthly), '연 3.2% 적금 기준'),
      ];
    }

    /* 추천 카드는 금액만 보인다. 국내·해외 비중은 어느 시장을 볼지 고른 뒤에 말한다 */
    const recommendFigs = monthlyInvest > 0 ? [fig('매달 투자할 돈', '월 ' + about(monthlyInvest), investNote)] : [];

    return {
      income: income,
      expense: expense,
      debt: debt,
      debtPayment: payment,
      deposit: deposit,
      surplusBeforeDebt: before,
      surplus: surplus,
      emergencyMonths: emergencyMonths,
      future: future,
      gap: gap,
      requiredMonthly: requiredMonthly,
      yieldRate: yieldRate,
      leverageGate: gate,
      goalAmount: goalAmount,
      goalMonths: goalMonths,
      decisionId: decisionId,
      profile: profile,
      leverage: leverage,
      monthlyInvest: monthlyInvest,
      domesticShare: split[0],
      overseasShare: split[1],
      investFocus: !!input.investFocus,
      focusApplied: focusApplied,
      boldApplied: boldApplied,
      investBase: investBase,
      investShare: share,
      domesticAmount: roundMan((monthlyInvest * split[0]) / 100),
      overseasAmount: roundMan((monthlyInvest * split[1]) / 100),
      categories: categories(expense),
      figures: { income: incomeFigs, balance: balanceFigs, decision: decisionFigs.slice(0, 3), recommend: recommendFigs.slice(0, 3) },
    };
  }

  function defaultRequiredYield() {
    const payment = 0;
    const surplus = 3500000 - 2100000 - payment;
    return requiredYield(surplus, DEPOSIT_DEFAULT, 36, 100000000);
  }

  function goalById(id) {
    return GOALS[id] || GOALS['goal-100'];
  }

  function experienceById(id) {
    return EXPERIENCE[id] || EXPERIENCE['exp-1'];
  }

  function lossById(id) {
    return LOSS[id] || LOSS['loss-1'];
  }

  WSP.lumpsumAdvisor = {
    SAVINGS_RATE: SAVINGS_RATE,
    DEBT_RATE: DEBT_RATE,
    DEBT_MONTHS: DEBT_MONTHS,
    EMERGENCY_MIN: EMERGENCY_MIN,
    DEPOSIT_DEFAULT: DEPOSIT_DEFAULT,
    GOALS: GOALS,
    GOAL_TYPED: GOAL_TYPED,
    EXPERIENCE: EXPERIENCE,
    LOSS: LOSS,
    debtPayment: debtPayment,
    spendPlan: spendPlan,
    cutForYield: cutForYield,
    spendInsight: spendInsight,
    FIXED_CATEGORIES: FIXED_CATEGORIES,
    INSIGHT_SOURCE: INSIGHT_SOURCE,
    manSigned: manSigned,
    shortfall: shortfall,
    infeasible: infeasible,
    aboutGap: aboutGap,
    plannedFuture: plannedFuture,
    INVEST_ASSUMED_RATE: INVEST_ASSUMED_RATE,
    about: about,
    inferRiskProfile: inferRiskProfile,
    advise: advise,
    defaultRequiredYield: defaultRequiredYield,
    goalById: goalById,
    experienceById: experienceById,
    lossById: lossById,
    clampMan: clamp,
  };
})();
