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

  /**
   * 입력창을 눌렀을 때 타이핑되는 문장. 선택지에 원하는 상황이 없을 때 쓰므로 어떤 선택지와도 같으면 안 된다.
   * (DEBT_CHECK는 부채 유무에 따라 situationText로 따로 만든다)
   */
  const TYPED = Object.freeze({
    INTRO: OPENING,
    GOAL: LA.GOAL_TYPED.text,
    PROFILING: '연금이랑 펀드를 조금 해봤어요',
    LOSS: '일단 지켜보다가 반등하면 정리할 것 같아요',
    RECOMMEND: '두 계좌 모두 보고 싶어요',
    NO_ACCOUNT: '네, 계좌 만들어 주세요',
  });

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

  /** 부채 상황 단계에서 선택지에 없는 답. 투자 쪽에 더 무게를 둔다는 뜻이다 */
  function situationText(debt) {
    return debt > 0 ? '대출이 좀 있는데, 투자에 더 집중하고 싶어요' : '투자에 더 집중하고 싶어요';
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
      { id: 'open-yes', text: '네, 개설해 주세요' },
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

  function T(text) {
    return { t: 'text', text: text };
  }

  /** 첫 질문. 이전 자산관리 상담과 같은 문장 계열이다 */
  function greeting() {
    const text = '어떤 목표로 상담받고 싶으세요? 편하게 말씀해 주세요.';
    return { text: text, blocks: [T(text)] };
  }

  /** 첫 질문 선택지는 이전 자산관리 상담의 3개 그대로다 */
  function introChoices() {
    const list = WSP.assetGoalChips || [];
    return list.map((text, i) => ({ id: 'intro-' + (i + 1), text: text }));
  }

  /** 분석 응답: 문장 → 진행 단계 → 소비 드롭다운 → 카드 2줄 → 마무리 → 질문 */
  function analysisMessage(a) {
    const before = man(Math.max(0, a.surplusBeforeDebt));
    let closing = '매달 남는 돈은 ' + before + '이에요.';
    if (a.debt > 0) closing = '매달 남는 돈은 ' + before + '이고, 부채 상환을 제외하면 매달 평균 ' + man(Math.max(0, a.surplus)) + ' 남아요.';
    return {
      blocks: [
        T('월급과 지출을 분석해볼게요.'),
        { t: 'steps', items: ANALYSIS_STEPS.slice() },
        { t: 'details', label: '내 소비 자세히 보기', categories: a.categories },
        { t: 'figures', figures: a.figures.income },
        { t: 'figures', figures: a.figures.balance },
        T(closing + '\n\n**목돈 목표가 얼마인가요?**'),
      ],
    };
  }

  /** 판단 응답: 확인 문장 → 카드 3장 → 판단 문장 */
  const SPEND_STEPS = Object.freeze(['소비 패턴 비교 중', '줄이기 쉬운 항목 고르는 중', '필요한 금액 계산하는 중']);

  /** 항목 하나를 대화 문장으로 쓴다. 소비 분석의 패턴 숫자를 근거로 붙인다 */
  function cutSentence(it, ins) {
    const s = man(it.saved);
    if (it.id === 'subs') return '정기결제가 ' + ins.subsCount + '건이라 자주 안 쓰는 구독을 정리하면 한 달에 ' + s + ' 정도 줄어요.';
    if (it.id === 'impulse') return '쇼핑은 ' + ins.lateShopping + '%가 월 후반에 몰려 있어서, 충동구매만 줄여도 한 달에 ' + s + ' 정도예요.';
    if (it.id === 'delivery') return '배달·외식이 월 ' + ins.deliveryCount + '회라, 조금만 줄여도 한 달에 ' + s + ' 정도 아낄 수 있어요.';
    return '소액 결제를 정리하면 한 달에 ' + s + ' 정도가 남아요.';
  }

  /** 줄이기 계획 문장. 부족분과 여유 목표, 항목별 이유, 고정비 설명, 결과를 이어서 쓴다 */
  function spendPlanText(a, plan, ins) {
    const deficit = Math.max(0, -a.surplus);
    const head = deficit > 0 ? '모자란 ' + man(deficit) + '에 여유 10만원을 더해, 한 달에 ' + man(plan.target) + ' 정도만 줄이면 돼요.' : '한 달에 ' + man(plan.target) + ' 정도 줄이는 걸 목표로 잡아 볼게요.';
    const lead = ['먼저', '다음으로', '그다음엔', '마지막으로'];
    const body = plan.items.map((it, i) => lead[Math.min(i, lead.length - 1)] + ' **' + it.label + '**. ' + cutSentence(it, ins)).join('\n\n');
    const fixed = '주거·관리와 교통은 고정비라 이번 계획에서는 건드리지 않았어요.';
    const tail = plan.after > 0
      ? '이렇게 하면 매달 ' + man(plan.total) + '을 아끼고, 월 여유는 ' + LA.manSigned(plan.after) + '이 돼요.'
      : '이 항목을 모두 줄여도 월 여유는 ' + LA.manSigned(plan.after) + '이에요. 주거·관리와 교통 같은 고정비도 같이 봐야 해요.';
    return [head, body, fixed, tail].filter(Boolean).join('\n\n');
  }

  /**
   * 월 여유가 0원 이하일 때: 소비 분석을 불러온 문장 → 진행 단계 → 소비 막대(출처·지난달 대비) →
   * 패턴 태그 → 대화체 줄이기 계획 → 전후 카드 → 안내. 이어서 칩 두 개가 나온다.
   */
  function spendPlanBlocks(a) {
    const plan = LA.spendPlan(a);
    const ins = LA.spendInsight(a);
    const before = LA.manSigned(a.surplus);
    return [
      T('지출을 줄이는 계획을 세워 볼게요. 자산·소비에서 분석한 최근 3개월 소비 내역을 가져왔어요.'),
      { t: 'steps', items: SPEND_STEPS.slice() },
      { t: 'details', label: '지출 항목 자세히 보기', categories: a.categories, insight: ins },
      { t: 'tags', items: ins.tags },
      T(spendPlanText(a, plan, ins)),
      { t: 'figures', figures: [{ label: '줄이기 전 월 여유', value: before, note: '', tone: a.surplus <= 0 ? 'warning' : '' }, { label: '줄인 뒤 월 여유', value: LA.manSigned(plan.after), note: '매달 ' + man(plan.total) + ' 절약', tone: plan.after > 0 ? '' : 'warning' }] },
      T('소비 분석에서 더 자세히 보거나, 이 계획을 줄이기 목표로 저장할 수 있어요.'),
    ];
  }

  /** 줄이기 계획 뒤 선택지. 첫 번째는 화면 이동만 하고 말풍선을 만들지 않는다 */
  function spendChoices() {
    return [
      { id: 'spend-view', text: '소비 분석에서 자세히 보기' },
      { id: 'spend-save', text: '줄이기 목표로 저장' },
    ];
  }

  function savedMessage(a) {
    const plan = LA.spendPlan(a);
    return { blocks: [T('줄이기 목표를 저장했어요. 매달 ' + man(plan.total) + ' 줄이는 걸 목표로 잡았고, 소비 분석에서 이번 달 진행 상황을 볼 수 있어요.')] };
  }

  /**
   * 적금 + 투자(MIX)에서 투자 몫이 남을 때: 소비를 줄이면 필요한 연 수익이 얼마나 내려가는지 같이 보여 준다.
   * 줄이기 계획과 같은 항목·문장을 쓰되, 결과는 "필요한 연 수익이 낮아진다"로 말한다.
   */
  function cutForYieldBlocks(a) {
    const cut = LA.cutForYield(a);
    if (!cut) return [];
    const ins = LA.spendInsight(a);
    const body = cut.plan.items.map((it, i) => leadWord(i) + ' **' + it.label + '**. ' + cutSentence(it, ins)).join('\n\n');
    const text = '적금으로 채우지 못하는 몫은 투자로 메워야 해서, 소비부터 같이 보면 좋아요. 매달 ' + man(cut.plan.total) + '을 줄이면 저축이 그만큼 늘어서, 목표에 필요한 연 수익이 ' + pct(cut.yieldBefore) + '에서 ' + pct(cut.yieldAfter) + ' 정도로 내려가요.';
    return [
      T(text),
      T(body),
      { t: 'figures', figures: [
        { label: '줄이기 전 필요한 연 수익', value: pct(cut.yieldBefore), note: '', tone: 'warning' },
        { label: '줄인 뒤 필요한 연 수익', value: pct(cut.yieldAfter), note: '매달 ' + man(cut.plan.total) + ' 더 저축', tone: '' },
      ] },
      { t: 'link', label: '소비 분석에서 자세히 보기', action: 'spend-open' },
    ];
  }

  function leadWord(i) {
    return ['먼저', '다음으로', '그다음엔', '마지막으로'][Math.min(i, 3)];
  }

  /** 판단 응답: 결론 문장 → 근거 카드. 사용자 문장을 되묻지 않는다 */
  function decisionMessage(a) {
    const blocks = [T(decisionSentence(a)), { t: 'figures', figures: a.figures.decision }];
    if (a.decisionId === 'SPEND_CHECK') blocks.push(...spendPlanBlocks(a));
    if (a.decisionId === 'MIX') blocks.push(...cutForYieldBlocks(a));
    return { blocks: blocks };
  }

  function afterSituation(a) {
    let body = '좋아요, 투자에 더 집중해서 볼게요. 투자 경험과 손실을 견디는 정도에 따라 맞는 비중이 달라져서, 두 가지만 여쭤볼게요.';
    if (a.decisionId === 'DEBT_FIRST') body = '대출이 있으면 투자보다 상환을 먼저 권해요. 그래도 투자에 더 집중하고 싶으시니, 갚고 남는 돈 기준으로 투자 비중을 높여서 볼게요. 추가 대출은 제안하지 않아요.';
    const text = body + '\n\n**주식이나 펀드는 해보신 적 있어요?**';
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
    const focus = a.investFocus ? '투자에 더 집중하고 싶다고 하셔서 월 투자금 비중을 기본보다 높여 잡았어요. ' : '';
    const blocks = [T(head), { t: 'figures', figures: a.figures.recommend }, T(focus + mix)];
    if (a.leverage) {
      blocks.push(T('레버리지 상품은 가격이 움직일 때 손실이 커지고, **넣은 돈보다 더 잃을 수 있어요.** 개별 이름은 말하지 않을게요.'));
    }
    return { blocks: blocks };
  }

  function sideStop(kind) {
    if (kind === 'prod-lev') return { text: '레버리지 상품은 가격이 움직일 때 손실이 커지고, 넣은 돈보다 더 잃을 수 있어요. 이번 상담의 개설 절차는 해외주식만 이어가요.' };
    return { text: '국내주식은 상품군으로만 소개해요. 개설 절차는 해외주식을 고를 때 이어가요.' };
  }

  function noAccount() {
    return { text: '해외주식은 외화 계좌가 필요한데 아직 없네요. **개설 도와드릴까요?**' };
  }

  /** 국내·해외 두 계좌를 모두 보고 싶다고 했을 때: 국내주식 설명 뒤에 해외 계좌 개설 질문으로 잇는다 */
  function bothMessage(a) {
    return {
      blocks: [
        T('국내주식은 지금 쓰시는 증권 계좌로 바로 시작할 수 있고, 권하는 비중은 ' + a.domesticShare + '%예요.'),
        T(noAccount().text),
      ],
    };
  }

  function thoughtSteps(kind) {
    if (kind === 'analysis') return ['계좌 내역 확인하는 중', '소비를 나누는 중'];
    if (kind === 'decision') return ['여러 방법 비교하는 중', '부족분을 계산하는 중'];
    if (kind === 'save') return ['줄이기 목표를 저장하는 중'];
    return ['말씀하신 내용을 읽는 중', '다음 질문을 고르는 중'];
  }

  function allFixedLines() {
    const lines = [OPENING, TYPED.GOAL, TYPED.PROFILING, TYPED.LOSS, TYPED.RECOMMEND, TYPED.NO_ACCOUNT, greeting().text, situationText(0), situationText(1), noAccount().text, sideStop('prod-dom').text, sideStop('prod-lev').text, mismatchReply().text, lossAsk().text];
    MISMATCH.forEach((c) => lines.push(c.text));
    introChoices().forEach((c) => lines.push(c.text));
    goalChoices().forEach((c) => lines.push(c.text));
    experienceChoices().forEach((c) => lines.push(c.text));
    lossChoices().forEach((c) => lines.push(c.text));
    productChoices(true).forEach((c) => lines.push(c.text));
    openChoices().forEach((c) => lines.push(c.text));
    spendChoices().forEach((c) => lines.push(c.text));
    SPEND_STEPS.forEach((t) => lines.push(t));
    return lines;
  }

  WSP.lumpsumScript = {
    OPENING: OPENING,
    TYPED: TYPED,
    MISMATCH: MISMATCH,
    ANALYSIS_STEPS: ANALYSIS_STEPS,
    BANNED: BANNED,
    pick: pick,
    situationText: situationText,
    greeting: greeting,
    introChoices: introChoices,
    goalChoices: goalChoices,
    experienceChoices: experienceChoices,
    lossChoices: lossChoices,
    productChoices: productChoices,
    openChoices: openChoices,
    decisionSentence: decisionSentence,
    analysisMessage: analysisMessage,
    decisionMessage: decisionMessage,
    spendPlanBlocks: spendPlanBlocks,
    spendChoices: spendChoices,
    savedMessage: savedMessage,
    SPEND_STEPS: SPEND_STEPS,
    afterSituation: afterSituation,
    mismatchReply: mismatchReply,
    lossAsk: lossAsk,
    recommendMessage: recommendMessage,
    sideStop: sideStop,
    noAccount: noAccount,
    bothMessage: bothMessage,
    thoughtSteps: thoughtSteps,
    allFixedLines: allFixedLines,
  };
})();
