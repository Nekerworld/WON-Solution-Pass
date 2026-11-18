/**
 * lumpsumAdvisor.js
 * 목돈 불리기 상담의 순수 계산. 화면 문장에 쓰는 숫자는 이 결과만 쓴다.
 * 대출 가능 여부는 계산하지 않는다. 있는 부채의 상환액만 뺀다.
 */
(function () {
  'use strict';

  const WSP = window.WSP;

  const SAVINGS_RATE = 0.032;
  const DEBT_RATE = 0.055;
  const DEBT_MONTHS = 60;
  const EMERGENCY_MIN = 3;
  const DEPOSIT_DEFAULT = 8482400;

  const GOALS = Object.freeze({
    'goal-100': { amount: 100000000, months: 36, text: '3년 안에 1억 정도 만들고 싶어요' },
    'goal-50': { amount: 50000000, months: 60, text: '5년 안에 5천만 원 만들고 싶어요' },
    'goal-20': { amount: 20000000, months: 12, text: '1년 안에 2천만 원 만들고 싶어요' },
  });

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
    const investBase = decisionId === 'SPEND_CHECK' ? 0 : Math.max(0, surplus);
    const monthlyInvest = roundMan(investBase * share);
    const split = PROFILE_SPLIT[profile.id] || PROFILE_SPLIT.NEUTRAL;

    const analysisFigs = [
      fig('월급', man(income), ''),
      fig('지출', man(expense), ''),
      fig('월 여유', man(Math.max(0, before)), surplus <= 0 ? '지출이 월급보다 많아요' : '', surplus <= 0 ? 'warning' : ''),
    ];
    const reserveFigs = [fig('비상자금', emergencyMonths + '개월', '예금 ' + man(deposit), emergencyMonths < EMERGENCY_MIN ? 'warning' : '')];

    let decisionFigs = [];
    if (decisionId === 'SPEND_CHECK') {
      decisionFigs = [fig('월급', man(income), ''), fig('지출', man(expense), ''), fig('월 여유', man(surplus), '0원 이하', 'warning')];
    } else if (decisionId === 'DEBT_FIRST') {
      decisionFigs = [
        fig('갚기 전 월 여유', man(before), ''),
        fig('매달 갚을 돈', man(payment), '연 5.5% · 60개월'),
        fig('갚고 남는 여력', man(Math.max(0, surplus)), ''),
      ];
    } else if (decisionId === 'EMERGENCY_FIRST') {
      decisionFigs = [
        fig('비상자금', emergencyMonths + '개월', '기준 3개월'),
        fig('예금', man(deposit), ''),
        fig('월 여유', man(surplus), ''),
      ];
    } else if (decisionId === 'SAVINGS_ENOUGH') {
      decisionFigs = [fig('적금으로 모이는 돈', '약 ' + man(future), goalMonths + '개월'), fig('목표', man(goalAmount), ''), fig('월 여유', man(surplus), '')];
    } else {
      decisionFigs = [
        fig('적금으로 모이는 돈', '약 ' + man(future), ''),
        fig('목표까지 부족한 돈', man(gap), ''),
        fig('필요한 월 저축', man(requiredMonthly), '연 3.2% 적금 기준'),
      ];
    }

    const recommendFigs =
      monthlyInvest > 0
        ? [fig('매달 투자할 돈', '월 ' + man(monthlyInvest), ''), fig('국내 비중', split[0] + '%', ''), fig('해외 비중', split[1] + '%', '')]
        : [];

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
      categories: categories(expense),
      figures: { analysis: analysisFigs, reserve: reserveFigs, decision: decisionFigs.slice(0, 3), recommend: recommendFigs.slice(0, 3) },
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
    EXPERIENCE: EXPERIENCE,
    LOSS: LOSS,
    debtPayment: debtPayment,
    inferRiskProfile: inferRiskProfile,
    advise: advise,
    defaultRequiredYield: defaultRequiredYield,
    goalById: goalById,
    experienceById: experienceById,
    lossById: lossById,
    clampMan: clamp,
  };
})();
