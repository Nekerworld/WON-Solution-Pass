/**
 * data/lumpsumScript.js
 * 목돈 불리기 고정 대본. 숫자는 lumpsumAdvisor 결과만 넣는다.
 * 실제 LLM 호출은 없다. "우리 상황에 맞는 게 없네요?"는 여기 넣지 않는다.
 */
(function () {
  'use strict';

  const WSP = window.WSP;
  const LA = WSP.lumpsumAdvisor;

  const OPENING = '목돈 마련하고 싶어요';

  const MISMATCH = Object.freeze([
    { id: 'mis-save', text: '3년 적금 상품을 보여 주세요' },
    { id: 'mis-lower', text: '목표를 5천만 원으로 낮춰 볼까요?' },
    { id: 'mis-more', text: '매달 넣는 돈을 늘려 볼까요?' },
  ]);

  const ANALYSIS_STEPS = Object.freeze(['입출금 내역 불러오는 중', '카드 소비 분류 중', '고정지출/변동지출 계산 중']);

  const BANNED = /종목|매수|매도|수익률|추천주|사세요|가입이 완료|가입 완료됐|승인됐습니다|가입해 드렸/;

  function pick(list, seed) {
    const i = Math.abs(Number(seed) || 0) % list.length;
    return list[i];
  }

  function man(n) {
    return WSP.utils.formatMan(n);
  }

  function pct(rate) {
    return (Math.round(rate * 1000) / 10).toFixed(1).replace(/\.0$/, '') + '%';
  }

  function situationText(debt) {
    return debt > 0 ? '대출이 좀 있어요. 이 상황에서 할 수 있는 방법을 알려 주세요' : '대출은 없어요. 적금 말고 이 숫자로 할 수 있는 방법을 알려 주세요';
  }

  function goalChoices() {
    return Object.keys(LA.GOALS).map((id) => ({ id: id, text: LA.GOALS[id].text }));
  }

  function experienceChoices() {
    return Object.keys(LA.EXPERIENCE).map((id) => ({ id: id, text: LA.EXPERIENCE[id].text }));
  }

  function lossChoices() {
    return Object.keys(LA.LOSS).map((id) => ({ id: id, text: LA.LOSS[id].text }));
  }

  function productChoices(showLeverage) {
    const list = [
      { id: 'prod-dom', text: '국내주식' },
      { id: 'prod-os', text: '해외주식' },
    ];
    if (showLeverage) list.push({ id: 'prod-lev', text: '레버리지 상품' });
    return list;
  }

  function openChoices() {
    return [
      { id: 'open-yes', text: '응, 개설해 주세요' },
      { id: 'open-no', text: '다음에 할게요' },
    ];
  }

  function decisionSentence(a) {
    if (a.decisionId === 'SPEND_CHECK') return '월 여유가 0원 이하라 투자나 저축은 제안하지 않고, 지출부터 같이 볼게요.';
    if (a.decisionId === 'DEBT_FIRST') return '갚는 이자 연 5.5%가 적금 연 3.2%보다 높아서, 투자보다 대출 상환을 먼저 권해요. 이후 금액은 갚고 남는 ' + man(Math.max(0, a.surplus)) + ' 기준이에요.';
    if (a.decisionId === 'EMERGENCY_FIRST') return '비상자금이 ' + a.emergencyMonths + '개월로 3개월보다 짧아서, 예금을 먼저 채우고 투자 비중은 줄일게요.';
    if (a.decisionId === 'SAVINGS_ENOUGH') return '적금만으로도 기간 안에 목표가 모여요. 더 빨리 모으고 싶다면 투자를 곁들일 수 있어요.';
    return '적금으로 모이는 돈과 목표 사이에 ' + man(a.gap) + ' 차이가 있어요. 연 ' + pct(a.yieldRate) + ' 수준이 더 필요해서 적금과 투자를 같이 제안해요.';
  }

  function profileSentence(a, expText, lossText) {
    const name = { STABLE: '안정', NEUTRAL: '중립', ACTIVE: '적극' }[a.profile.id] || '중립';
    let read = '경험과 버티는 기간이 중간인 쪽으로 봤어요.';
    if (a.profile.id === 'STABLE') read = '떨어지면 정리하고 싶어 하시거나, 경험이 적은 쪽으로 봤어요.';
    if (a.profile.id === 'ACTIVE') read = '경험도 있고, 떨어질 때 더 살 수 있다고 하신 쪽으로 봤어요.';
    if (a.profile.id === 'NEUTRAL') read = '경험은 적지만 손실을 어느 정도 감수하고 장기로 볼 수 있는 쪽이네요.';
    return '“' + expText + '”, “' + lossText + '”에서 ' + read + ' 성향은 ' + name + '으로 볼게요.';
  }

  function analysisMessage(a, seed) {
    const lead = pick(
      [
        '계좌 내역을 읽어 봤어요.',
        '입출금이랑 카드 내역을 나눠 봤어요.',
        '월급과 지출부터 맞춰 봤어요.',
      ],
      seed
    );
    const text = lead + '\n\n매달 남는 돈은 ' + man(Math.max(0, a.surplusBeforeDebt)) + '이에요.\n\n**목표가 얼마인가요?**';
    return { text: text, steps: ANALYSIS_STEPS.slice(), figures: a.figures.analysis, figures2: a.figures.reserve, categories: a.categories };
  }

  function decisionMessage(a, goalText, seed) {
    const echo = pick(['“' + goalText + '”라고 하셨군요.', '목표는 그 문장 기준으로 계산했어요.', '말씀하신 기간과 금액으로 맞춰 봤어요.'], seed + 1);
    return { text: echo, figures: a.figures.decision, decisionLine: decisionSentence(a), stop: a.decisionId === 'SPEND_CHECK' };
  }

  function afterSituation(a, userText, seed) {
    const echo = pick(['“' + userText + '”', '방금 말씀은 이렇게 들었어요. ' + userText], seed + 2);
    let body = '대출 권유는 하지 않고, 지금 숫자로 이어갈게요.';
    if (a.decisionId === 'DEBT_FIRST') body = '대출이 있으면 투자보다 상환을 먼저 권해요. 추가 대출은 제안하지 않아요.';
    const text = echo + '\n\n' + body + '\n\n**주식이나 펀드는 해보신 적 있어요?**';
    return { text: text };
  }

  function mismatchReply() {
    return { text: '그 질문은 방금 계산한 여유·부채와는 조금 달라요.\n\n**주식이나 펀드는 해보신 적 있어요?**' };
  }

  function lossAsk() {
    return { text: '**투자한 돈이 한 달 새 20% 떨어지면 어떻게 하실 것 같아요?**' };
  }

  function recommendMessage(a, expText, lossText, seed) {
    const head = profileSentence(a, expText, lossText);
    const mix = pick(
      [
        '국내주식과 해외주식을 같이 제안해요. 어느 쪽을 볼까요?',
        '국내와 해외, 두 가지를 후보로 둘게요. 보고 싶은 쪽을 골라 주세요.',
      ],
      seed + 3
    );
    let text = head + '\n\n매달 투자 참고 금액은 ' + man(a.monthlyInvest) + '이고, 국내 ' + a.domesticShare + '% · 해외 ' + a.overseasShare + '%예요.\n\n' + mix;
    if (a.leverage) {
      text += '\n\n레버리지 상품은 가격이 움직일 때 손실이 커지고, **넣은 돈보다 더 잃을 수 있어요.** 개별 이름은 말하지 않을게요.';
    }
    return { text: text, figures: a.figures.recommend };
  }

  function sideStop(kind) {
    if (kind === 'prod-lev') return { text: '레버리지 상품은 가격이 움직일 때 손실이 커지고, 넣은 돈보다 더 잃을 수 있어요. 이번 상담의 개설 절차는 해외주식만 이어가요.' };
    return { text: '국내주식은 상품군으로만 소개해요. 개설 절차는 해외주식을 고를 때 이어가요.' };
  }

  function noAccount() {
    return { text: '해외주식은 외화 계좌가 필요한데 아직 없네요. **개설 도와드릴까요?**' };
  }

  function thoughtSteps(kind) {
    if (kind === 'analysis') return ['계좌 내역 확인하는 중', '소비를 나누는 중'];
    if (kind === 'decision') return ['여러 방법 비교하는 중', '부족분을 계산하는 중'];
    return ['말씀하신 내용을 읽는 중', '다음 질문을 고르는 중'];
  }

  function allFixedLines() {
    const lines = [OPENING, situationText(0), situationText(1), noAccount().text, sideStop('prod-dom').text, sideStop('prod-lev').text, mismatchReply().text, lossAsk().text];
    MISMATCH.forEach((c) => lines.push(c.text));
    goalChoices().forEach((c) => lines.push(c.text));
    experienceChoices().forEach((c) => lines.push(c.text));
    lossChoices().forEach((c) => lines.push(c.text));
    productChoices(true).forEach((c) => lines.push(c.text));
    openChoices().forEach((c) => lines.push(c.text));
    return lines;
  }

  WSP.lumpsumScript = {
    OPENING: OPENING,
    MISMATCH: MISMATCH,
    ANALYSIS_STEPS: ANALYSIS_STEPS,
    BANNED: BANNED,
    pick: pick,
    situationText: situationText,
    goalChoices: goalChoices,
    experienceChoices: experienceChoices,
    lossChoices: lossChoices,
    productChoices: productChoices,
    openChoices: openChoices,
    decisionSentence: decisionSentence,
    analysisMessage: analysisMessage,
    decisionMessage: decisionMessage,
    afterSituation: afterSituation,
    mismatchReply: mismatchReply,
    lossAsk: lossAsk,
    recommendMessage: recommendMessage,
    sideStop: sideStop,
    noAccount: noAccount,
    thoughtSteps: thoughtSteps,
    allFixedLines: allFixedLines,
  };
})();
