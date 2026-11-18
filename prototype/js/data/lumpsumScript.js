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

  /** 판단 뒤 "투자 비중도 같이 볼까요?"에 대한 두 답. 질문과 맞는 답만 둔다 */
  const INVEST_CHOICES = Object.freeze([
    { id: 'inv-yes', text: '네, 투자도 같이 볼게요' },
    { id: 'inv-no', text: '아니요, 여기서 마칠게요' },
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
    EMERGENCY: '지금은 비상자금만 볼게요',
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

  /** 선택지에 없는 답. 투자 쪽에 더 무게를 둔다는 뜻이다. 부채는 해결패스가 계좌에서 보므로 묻거나 말하지 않는다 */
  function situationText() {
    return '투자에 더 집중하고 싶어요';
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

  /** 목표를 "3년 안에 1억원"처럼 쓴다 */
  function goalOf(a) {
    return goalPhrase({ months: a.goalMonths, amount: a.goalAmount });
  }

  /** 비상자금을 채우는 방법 한 문장. 남는 돈의 70%를 만원 단위로 모은다고 본다 (이전 자산관리 상담과 같은 기준) */
  function emergencyFill(a) {
    const gap = Math.max(0, a.expense * LA.EMERGENCY_MIN - a.deposit);
    const save = Math.floor(Math.round(Math.max(0, a.surplus) * 0.7) / 10000) * 10000;
    if (a.surplus <= 0) return '지금은 남는 돈이 없어서 채우기 어려우니, 지출부터 같이 줄여 볼게요.';
    if (save < 10000) return '매달 모으기에는 남는 돈이 적어서, 지출부터 같이 줄여 보는 게 좋아요.';
    return '매달 ' + LA.about(save) + '씩 예금에 모으면 ' + Math.ceil(gap / save) + '개월이면 채워져요.';
  }

  /** 필요한 연 수익을 말로 쓴다. 너무 크면 구체 숫자 대신 "50% 이상"이라고 한다 */
  function yieldText(rate) {
    if (rate >= 0.5) return '연 50% 이상';
    return '연 약 ' + Math.round(rate * 100) + '%';
  }

  /**
   * 판단 문장. opts.skipFill이면 비상자금 채우는 방법은 이미 말했으므로 생략한다.
   * 비상자금·상환이 먼저인 경우에도 고른 목표를 한 번 언급한다.
   */
  function decisionSentence(a, opts) {
    const o = opts || {};
    if (a.decisionId === 'SPEND_CHECK') {
      if (a.surplusBeforeDebt <= 0) return '지출이 월급보다 많아서 투자나 저축은 제안하지 않고, 지출부터 같이 볼게요.';
      return '부채 상환으로 매달 ' + LA.about(a.debtPayment) + '이 나가면 월 여유가 없어서, 투자나 저축은 제안하지 않고 지출부터 같이 볼게요.';
    }
    if (a.decisionId === 'DEBT_FIRST') return '갚는 이자 연 5.5%가 적금 연 3.2%보다 높아서, 투자보다 대출 상환을 먼저 권해요. 이후 금액은 갚고 남는 ' + LA.about(Math.max(0, a.surplus)) + ' 기준이에요. ' + goalOf(a) + ' 목표는 상환을 이어 가면서 이 돈으로 보는 게 안전해요.';
    if (a.decisionId === 'EMERGENCY_FIRST') {
      const head = '비상자금이 ' + a.emergencyMonths + '개월로 3개월보다 짧아서, 목표보다 예금을 먼저 채우는 걸 권해요.';
      return [head, o.skipFill ? '' : emergencyFill(a), goalOf(a) + ' 목표는 그다음에 보는 게 안전해요.'].filter(Boolean).join(' ');
    }
    if (a.decisionId === 'SAVINGS_ENOUGH') return '예금과 적금만으로도 기간 안에 목표가 모여요. 투자하지 않아도 괜찮아요.';
    return '목표까지 월 ' + LA.about(a.requiredMonthly) + '을 모아야 하는데, 적금만으로는 부족해요.';
  }

  /** 투자 경험 답변을 한 문장으로 읽는다. 선택지 문장과 직접 쓴 문장 모두 다룬다 */
  function experienceRead(score, text) {
    if (/연금|펀드/.test(text || '')) return '투자 경험은 연금이나 펀드를 조금 해 본 정도예요.';
    if (score === 0) return '투자 경험은 아직 없는 편이에요.';
    if (score === 2) return '투자 경험은 꽤 있는 편이에요.';
    return '투자 경험은 소액으로 해 본 정도예요.';
  }

  /** 손실 반응 답변을 "~쪽이라"로 읽는다 */
  function lossRead(score, text) {
    if (/반등|정리/.test(text || '') && !/바로 팔/.test(text || '')) return '바로 팔지는 않지만 반등하면 정리하는 쪽이라';
    if (score === 0) return '떨어지면 바로 정리하는 쪽이라';
    if (score === 2) return '떨어질 때 더 살 수 있는 쪽이라';
    return '손실이 나도 길게 보고 버틸 수 있는 쪽이라';
  }

  /** 두 답변을 따로 읽어서, 답한 내용과 어긋나는 설명이 나오지 않게 한다 */
  function profileSentence(a, expText, lossText) {
    const name = { STABLE: '안정', NEUTRAL: '중립', ACTIVE: '적극' }[a.profile.id] || '중립';
    return '“' + expText + '”, “' + lossText + '”에서 ' + experienceRead(a.profile.experience, expText) + ' ' + lossRead(a.profile.loss, lossText) + ' 성향은 ' + name + '으로 볼게요.';
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

  /** 첫 질문 선택지 중 해외주식 칩(또는 그 뜻으로 직접 쓴 말)은 목돈 채팅 안에서 이어 간다 */
  function isOverseasIntro(text) {
    return /해외주식/.test(String(text || ''));
  }

  /**
   * 해외주식 칩의 첫 답. 목돈 목표는 묻지 않고, 외화 계좌가 없으니 개설할지 바로 묻는다.
   * 개설 선택지는 NO_ACCOUNT 단계의 기존 선택지(open-yes/open-no)를 쓴다.
   */
  function overseasIntro(hasFx) {
    return {
      blocks: [
        T('해외주식 투자를 처음 시작하시는군요. 해외주식은 달러를 넣어 두는 외화 계좌로 거래해요.'),
        T(hasFx ? '외화 계좌는 이미 있어요. 이어서 **해외주식 계좌 개설을 도와드릴까요?**' : '외화 계좌는 아직 없네요. **개설 도와드릴까요?**'),
      ],
    };
  }

  /** 비상자금을 묻는 첫 말(또는 그 뜻으로 직접 쓴 말) */
  function isEmergencyIntro(text) {
    return /비상|급할\s?때|예비/.test(String(text || ''));
  }

  /** 첫 말에 "결혼"이 들어 있으면 목표 이름을 결혼 자금으로 보인다. 없으면 빈 문자열 */
  function purposeLabelOf(text) {
    return /결혼/.test(String(text || '')) ? '결혼 자금 마련' : '';
  }

  /** 비상자금이 기준(3개월치)을 넘는지 */
  function emergencyEnough(a) {
    return !!a && a.emergencyMonths >= LA.EMERGENCY_MIN;
  }

  /** 비상자금 점검 뒤에 목돈 마련도 볼지 묻는 두 답. 기준에 못 미치면 "그래도"로 묻고, 마치는 답도 비상자금 쪽으로 쓴다 */
  const EMERGENCY_CHOICES = Object.freeze([
    { id: 'em-yes', text: '네, 목돈 마련도 같이 볼게요' },
    { id: 'em-no', text: '아니요, 여기서 마칠게요' },
  ]);
  const EMERGENCY_CHOICES_LOW = Object.freeze([
    { id: 'em-yes', text: '그래도 목돈 마련도 같이 볼게요' },
    { id: 'em-no', text: '아니요, 비상자금부터 채울게요' },
  ]);

  function emergencyChoices(a) {
    return (a && !emergencyEnough(a) ? EMERGENCY_CHOICES_LOW : EMERGENCY_CHOICES).map((c) => ({ id: c.id, text: c.text }));
  }

  /**
   * 비상자금 점검 문장: 예금이 생활비 몇 개월치인지 말하고, 기준(3개월)보다 적으면 채우는 기간을 계산해 준다.
   * 월 여유가 없으면 목돈은 묻지 않고 지출부터 본다고 말한다.
   */
  function emergencyLine(a) {
    const min = LA.EMERGENCY_MIN;
    const head = '예금이 생활비 ' + a.emergencyMonths + '개월치예요.';
    if (emergencyEnough(a)) {
      const ok = head + ' 기준인 ' + min + '개월치보다 많아서, 비상자금은 충분한 편이에요.';
      return a.surplus <= 0 ? ok + ' 다만 지금은 남는 돈이 없어서, 지출부터 같이 볼게요.' : ok;
    }
    return head + ' 기준인 ' + min + '개월치에 못 미쳐서 아직 부족해요. ' + emergencyFill(a);
  }

  /** 첫 말에 목적이 들어 있으면 먼저 받아 준다. 지금은 결혼 자금만 있다 */
  function purposeAck(label) {
    return label === '결혼 자금 마련' ? '결혼 자금을 준비하시는군요. ' : '';
  }

  /** 분석 마무리의 첫 문장: 남는 돈. 지출이 더 많거나 상환까지 빼면 모자란 경우는 그대로 말한다 */
  function surplusClosing(a) {
    const before = a.surplusBeforeDebt;
    if (before <= 0) return Math.round(-before / 10000) === 0 ? '월급과 지출이 거의 같아서 남는 돈이 없어요.' : '지출이 월급보다 ' + LA.about(-before) + ' 많아요.';
    const base = '매달 남는 돈은 ' + LA.about(before) + '이에요.';
    if (a.debt <= 0) return base;
    const head = '매달 남는 돈은 ' + LA.about(before) + '이고, 부채 상환(월 ' + LA.about(a.debtPayment) + ')을 빼면 ';
    if (a.surplus > 0) return head + '매달 평균 ' + LA.about(a.surplus) + ' 남아요.';
    if (Math.round(-a.surplus / 10000) === 0) return head + '남는 돈이 없어요.';
    return head + LA.about(-a.surplus) + '이 모자라요.';
  }

  /** 분석 응답: 문장 → 진행 단계 → 소비 드롭다운 → 카드 2줄 → 마무리 → 질문 */
  function analysisMessage(a, seed, opts) {
    const o = opts || {};
    const closing = surplusClosing(a);
    let last = closing + '\n\n**목돈 목표가 얼마인가요?**';
    /* 목표를 이미 말한 경우(결혼 자금 3천만원 3년 등)는 목표를 다시 묻지 않고 바로 계산으로 간다 */
    if (o.goalKnown) last = closing + '\n\n' + (o.assumedMonths ? '기간은 3년으로 보고 바로 계산해 볼게요.' : '말씀하신 목표로 바로 계산해 볼게요.');
    /* 남는 돈이 없으면 목표를 묻지 않고 바로 지출부터 본다. 묻고 나서 무시하지 않는다 */
    else if (o.skipGoal) last = closing + '\n\n목표는 지출을 정리한 뒤에 같이 볼게요.';
    /* 비상자금을 물은 경우는 점검 결과를 말하고, 목돈 마련도 볼지 묻는다 */
    if (o.emergency) {
      if (o.skipGoal) last = emergencyLine(a);
      else if (emergencyEnough(a)) last = emergencyLine(a) + '\n\n**남는 돈으로 목돈 마련도 같이 볼까요?**';
      else last = emergencyLine(a) + '\n\n비상자금을 채운 뒤에 목돈을 보는 게 안전하지만, 그래도 같이 볼 수 있어요. **목돈 마련도 같이 볼까요?**';
    }
    return {
      blocks: [
        T(purposeAck(o.purposeLabel) + '월급과 지출을 분석해볼게요.'),
        { t: 'steps', items: ANALYSIS_STEPS.slice() },
        { t: 'details', label: '내 소비 자세히 보기', categories: a.categories },
        { t: 'figures', figures: a.figures.income },
        { t: 'figures', figures: a.figures.balance },
        T(last),
      ],
    };
  }

  /** 비상자금만 보다가 목돈 마련도 보겠다고 했을 때: 목표를 묻는다 */
  function goalAskMessage(a) {
    const lead = a && !emergencyEnough(a) ? '좋아요. 비상자금을 채우는 것과 함께 목돈을 볼게요.' : '좋아요. 남는 돈으로 목돈을 만든다고 보고 계산해 볼게요.';
    return { blocks: [T(lead + '\n\n**목돈 목표가 얼마인가요?**')] };
  }

  /** 비상자금만 보고 마칠 때. 충분하다고 말한 뒤에 "먼저 챙겨 보세요"라고 하지 않는다 */
  function emergencyStop(a) {
    const tail = a && emergencyEnough(a) ? '지금 비상자금은 충분하니 그대로 유지하세요.' : '비상자금부터 채워 보세요.';
    const text = '좋아요, 목돈 마련은 빼고 여기서 마칠게요. ' + tail + ' 다시 보려면 새 상담을 시작하세요.';
    return { text: text, blocks: [T(text)] };
  }

  /** 계좌 개설을 다음으로 미룰 때: 마무리 말만 하고 상담을 닫는다 */
  function laterMessage() {
    const text = '알겠어요. 필요하실 때 언제든 다시 말씀해 주세요. 새 상담을 시작하면 처음부터 같이 볼 수 있어요.';
    return { text: text, blocks: [T(text)] };
  }

  /** 레버리지 상품을 골랐을 때: 이번 상담에서는 이어 가지 않는다고 말하고 국내·해외를 다시 묻는다 */
  function leverageRetry() {
    const text = '레버리지 상품은 이번 상담에서 가입 절차를 도와드리지 못해요. 일반 주식으로 먼저 볼게요.\n\n**국내주식과 해외주식 중 어느 쪽으로 볼까요?**';
    return { text: text, blocks: [T(text)] };
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
    const cover = a.debtPayment > 0 ? '상환까지 빼고 보면 모자란 ' : '모자란 ';
    const head = deficit > 0 ? cover + LA.about(deficit) + '에 여유 10만원을 더하려면, 한 달에 ' + man(plan.target) + ' 정도를 줄여야 해요.' : '한 달에 ' + man(plan.target) + ' 정도 줄이는 걸 목표로 잡아 볼게요.';
    const lead = ['먼저', '다음으로', '그다음엔', '마지막으로'];
    const body = plan.items.map((it, i) => lead[Math.min(i, lead.length - 1)] + ' **' + it.label + '**. ' + cutSentence(it, ins)).join('\n\n');
    const fixed = '주거·관리와 교통은 고정비라 이번 계획에서는 건드리지 않았어요.';
    const lack = Math.round(-plan.after / 10000) > 0;
    let tail = '이렇게 하면 매달 ' + man(plan.total) + '을 아끼고, 월 여유는 ' + LA.about(plan.after) + '이 돼요.';
    if (plan.after <= 0) {
      tail = lack
        ? '이 항목을 모두 줄이면 매달 ' + man(plan.total) + '을 아끼지만, 그래도 월 ' + LA.about(-plan.after) + '이 모자라요. 주거·관리와 교통 같은 고정비도 같이 봐야 해요.'
        : '이 항목을 모두 줄이면 매달 ' + man(plan.total) + '을 아끼지만, 월 여유는 0원 근처예요. 주거·관리와 교통 같은 고정비도 같이 봐야 해요.';
    }
    return [head, body, fixed, tail].filter(Boolean).join('\n\n');
  }

  /**
   * 월 여유가 0원 이하일 때: 소비 분석을 불러온 문장 → 진행 단계 → 소비 막대(출처·지난달 대비) →
   * 패턴 태그 → 대화체 줄이기 계획 → 전후 카드 → 안내. 이어서 칩 두 개가 나온다.
   */
  function spendPlanBlocks(a) {
    const plan = LA.spendPlan(a);
    const ins = LA.spendInsight(a);
    const before = LA.aboutGap(a.surplus);
    return [
      T('지출을 줄이는 계획을 세워 볼게요. 자산·소비에서 분석한 최근 3개월 소비 내역을 가져왔어요.'),
      { t: 'steps', items: SPEND_STEPS.slice() },
      { t: 'details', label: '지출 항목 자세히 보기', categories: a.categories, insight: ins },
      { t: 'tags', items: ins.tags },
      T(spendPlanText(a, plan, ins)),
      { t: 'figures', figures: [{ label: '줄이기 전 월 여유', value: before, note: '', tone: a.surplus <= 0 ? 'warning' : '' }, { label: '줄인 뒤 월 여유', value: LA.aboutGap(plan.after), note: '매달 ' + man(plan.total) + ' 절약', tone: plan.after > 0 ? '' : 'warning' }] },
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

  /** 드롭다운 안에서 항목마다 붙는 짧은 이유. 소비 분석의 패턴 숫자를 쓴다 */
  function cutReason(it, ins) {
    if (it.id === 'subs') return '정기결제 ' + ins.subsCount + '건 중 자주 안 쓰는 구독 정리';
    if (it.id === 'impulse') return '쇼핑의 ' + ins.lateShopping + '%가 월 후반에 몰려 있어요';
    if (it.id === 'delivery') return '배달·외식이 월 ' + ins.deliveryCount + '회예요';
    return '자잘한 카드 결제가 쌓이는 항목이에요';
  }

  /**
   * 적금 + 투자(MIX)에서 투자 몫이 남을 때: 소비를 줄이면 필요한 연 수익이 얼마나 내려가는지 한 줄로 말하고,
   * 줄일 항목은 "지출 줄이기 제안" 드롭다운 안에 둔다(항목, 줄이는 돈, 이유). 마지막에 소비 분석 버튼.
   */
  function cutForYieldBlocks(a) {
    const cut = LA.cutForYield(a);
    if (!cut) return [];
    const ins = LA.spendInsight(a);
    const text = '소비를 **매달 ' + man(cut.plan.total) + '** 줄이면 필요한 연 수익이 ' + pct(cut.yieldBefore) + '에서 ' + pct(cut.yieldAfter) + '로 내려가요.';
    return [
      T(text),
      { t: 'details', label: '지출 줄이기 제안', cuts: cut.plan.items.map((it) => ({ id: it.id, label: it.label, saved: it.saved, reason: cutReason(it, ins) })) },
      { t: 'link', label: '소비 분석에서 자세히 보기', action: 'spend-open' },
    ];
  }

  /** 판단 응답: 결론 문장 → 근거 카드. 사용자 문장을 되묻지 않는다 */
  function decisionMessage(a, opts) {
    const o = opts || {};
    const blocks = [];
    if (o.adjusted) blocks.push(T('목표를 **' + goalPhrase(o.adjusted) + '**으로 바꿔서 다시 계산했어요.'));
    blocks.push(T(decisionSentence(a, o)), { t: 'figures', figures: a.figures.decision });
    if (a.decisionId === 'SPEND_CHECK') blocks.push(...spendPlanBlocks(a));
    if (a.decisionId === 'MIX') blocks.push(...cutForYieldBlocks(a));
    /* 투자로도 어려우면 성향을 묻기 전에 먼저 알린다 */
    const hope = LA.infeasible(a);
    if (hope) blocks.push(T(infeasibleText(hope, LA.cutForYield(a))));
    /* 판단을 보여 준 뒤에는 반드시 질문을 던진다. 선택지는 이 질문에 대한 답이다 */
    if (a.decisionId !== 'SPEND_CHECK') blocks.push(T(investQuestion(a)));
    return { blocks: blocks };
  }

  /**
   * 투자로도 목표에 못 닿을 때, 성향을 묻기 전에 먼저 알린다.
   * 필요한 연 수익이 비현실적으로 크면 "현실적으로 어려워요"라고 분명히 말한다.
   */
  function infeasibleText(h, cut) {
    /* 소비를 줄이는 제안을 이미 보여 줬으면 줄인 뒤의 필요한 수익으로 말한다 */
    const useCut = !!cut && cut.yieldAfter >= LA.INVEST_ASSUMED_RATE;
    const rate = useCut ? cut.yieldAfter : h.yieldRate;
    const hard = (useCut ? '소비를 줄여도 ' : '') + '목표에 닿으려면 ' + yieldText(rate) + ' 수익이 필요해서 ' + (rate >= 0.12 ? '현실적으로 어려워요.' : '쉽지 않아요.');
    return '여유 돈을 전부 투자해도(연 6% 가정) 목표 기간 뒤 ' + LA.about(h.planned) + '이라 목표에 ' + LA.about(h.short) + ' 못 미쳐요. ' + hard;
  }

  /** 판단 뒤 질문. 판단에 따라 묻는 말이 다르다 */
  function investQuestion(a) {
    if (a && LA.infeasible(a)) return '**목표를 조정할까요, 아니면 그래도 투자도 알아볼까요?**';
    if (a && (a.decisionId === 'EMERGENCY_FIRST' || a.decisionId === 'DEBT_FIRST')) return '**그래도 투자도 알아볼까요?**';
    if (a && a.decisionId === 'SAVINGS_ENOUGH') return '**혹시 주식 투자도 해 보고 싶으세요?**';
    return '**투자 비중도 같이 볼까요?**';
  }

  /**
   * 판단 뒤 선택지. 투자로도 어려우면 목표 조정을 먼저 보여 주고 "그래도 투자"를 이어서 둔다.
   * 목표 조정은 목표가 이미 5천만 원 이하·5년 이상이면 해당 선택지를 뺀다.
   */
  function investChoices(a, goal) {
    const g = goal || LA.GOALS['goal-100'];
    const id = a && a.decisionId;
    const list = [];
    if (a && LA.infeasible(a)) {
      if (g.amount > 50000000) list.push({ id: 'sf-amount', text: '목표를 5천만 원·5년으로 낮출게요' });
      if (g.months < 60) list.push({ id: 'sf-period', text: '기간을 5년으로 늘릴게요' });
      list.push({ id: 'inv-yes', text: '그래도 투자도 알아볼게요' }, { id: 'inv-no', text: '아니요, 여기서 마칠게요' });
      return list;
    }
    if (id === 'EMERGENCY_FIRST') return [{ id: 'inv-yes', text: '그래도 투자도 알아볼게요' }, { id: 'inv-no', text: '아니요, 비상자금부터 채울게요' }];
    if (id === 'DEBT_FIRST') return [{ id: 'inv-yes', text: '그래도 투자도 알아볼게요' }, { id: 'inv-no', text: '아니요, 상환부터 할게요' }];
    if (id === 'SAVINGS_ENOUGH') return [{ id: 'inv-yes', text: '네, 투자도 해보고 싶어요' }, { id: 'inv-no', text: '아니요, 적금으로 갈게요' }];
    return INVEST_CHOICES.map((c) => ({ id: c.id, text: c.text }));
  }

  /** 투자는 빼고 마칠 때. 판단에 맞는 다음 행동을 말한다 */
  function stopMessage(a) {
    const id = a && a.decisionId;
    let tail = '위 금액을 기준으로 적금을 준비해 보세요.';
    if (id === 'DEBT_FIRST') tail = '대출 상환을 먼저 이어 가 보세요.';
    else if (id === 'EMERGENCY_FIRST') tail = '비상자금부터 채워 보세요.';
    else if (id === 'SAVINGS_ENOUGH') tail = '월 여유 안에서 적금을 이어 가면 기간 안에 목표가 모여요.';
    else if (id === 'MIX') tail = '적금만으로는 목표에 못 미치니, 목표나 기간을 조정해서 다시 상담해 보세요.';
    const head = id === 'SAVINGS_ENOUGH' ? '좋아요, 주식은 빼고 적금으로 가요.' : '좋아요, 투자는 빼고 여기서 마칠게요.';
    return { text: head + ' ' + tail + ' 다시 보려면 새 상담을 시작하세요.' };
  }

  /**
   * 투자 질문에 "예"라고 한 뒤의 첫 말. 사용자가 직접 쓴 말(opts.focus)일 때만 "투자에 더 집중"이라고 받는다.
   * 성향을 이미 답했으면(opts.profileKnown) 다시 묻지 않고 그대로 계산한다.
   */
  function afterSituation(a, opts) {
    const o = opts || {};
    const focus = !!o.focus;
    const hope = a && LA.infeasible(a);
    let body = focus ? '좋아요, 투자에 더 집중해서 볼게요.' : '좋아요, 투자도 같이 볼게요.';
    if (a && a.decisionId === 'DEBT_FIRST')
      body = focus
        ? '대출이 있으면 투자보다 상환을 먼저 권해요. 그래도 투자에 더 집중하고 싶으시니, 갚고 남는 돈 기준으로 투자 비중을 높여서 볼게요. 추가 대출은 제안하지 않아요.'
        : '대출 상환을 이어 가는 걸 전제로, 갚고 남는 돈 기준으로 투자를 알아볼게요. 추가 대출은 제안하지 않아요.';
    else if (a && a.decisionId === 'EMERGENCY_FIRST')
      body = focus
        ? '비상자금을 채우는 걸 먼저 두되, 투자에 더 집중하고 싶으시니 투자 비중을 조금 높여서 볼게요.'
        : '비상자금을 채우는 걸 먼저 두고, 투자는 일부만 알아볼게요.';
    else if (a && a.decisionId === 'SAVINGS_ENOUGH')
      body = focus ? '좋아요, 투자에 더 집중해서 볼게요. 목표는 적금으로 채워지니 남는 돈 일부로 볼게요.' : '좋아요, 목표는 적금으로 채우고 남는 돈 일부로 투자를 알아볼게요.';
    else if (hope) body = focus ? '좋아요, 투자에 더 집중해서 얼마나 가까워지는지 볼게요.' : '좋아요, 그래도 투자로 얼마나 가까워지는지 같이 볼게요.';
    if (o.profileKnown) return { text: body + ' 앞서 말씀해 주신 투자 성향대로 계산해 볼게요.' };
    const text = body + ' 투자 경험과 손실을 견디는 정도에 따라 맞는 비중이 달라져서, 두 가지만 여쭤볼게요.\n\n**주식이나 펀드는 해보신 적 있어요?**';
    return { text: text };
  }

  function lossAsk() {
    return { text: '**투자한 돈이 한 달 새 20% 떨어지면 어떻게 하실 것 같아요?**' };
  }

  /** 판단이 상환·비상자금 우선이거나 적금으로 충분할 때, 투자 금액이 어떤 몫인지 한 줄로 밝힌다 */
  function recommendNote(a) {
    if (a.decisionId === 'EMERGENCY_FIRST') return '나머지 돈은 비상자금을 채우는 데 쓰세요.';
    if (a.decisionId === 'DEBT_FIRST') return '대출 상환은 그대로 이어 가세요.';
    if (a.decisionId === 'SAVINGS_ENOUGH') return '목표는 적금으로 채워지니, 투자는 남는 돈 일부만 이 금액으로 봤어요.';
    return '';
  }

  /** opts.ack가 있으면 직전 선택(예: 그래도 이 비중으로)을 먼저 받아 준다 */
  function recommendMessage(a, expText, lossText, seed, opts) {
    const o = opts || {};
    const head = profileSentence(a, expText, lossText);
    const mix = pick(
      [
        '어느 시장을 볼지 골라 주세요. 그에 맞춰 비중을 같이 볼게요.',
        '국내와 해외 중 보고 싶은 쪽을 골라 주세요. 비중은 그다음에 볼게요.',
      ],
      seed + 3
    );
    const focus = a.boldApplied
      ? '목표를 채우려고 투자 비중을 ' + Math.round(a.investShare * 100) + '%로 올렸어요. '
      : a.focusApplied
        ? '투자에 더 집중하고 싶다고 하셔서 투자 비중에 15%p를 더했어요. '
        : '';
    const blocks = [];
    if (o.ack) blocks.push(T(o.ack));
    blocks.push(T(head), { t: 'figures', figures: a.figures.recommend }, T([focus.trim(), recommendNote(a), mix].filter(Boolean).join(' ')));
    if (a.leverage && !o.noLeverage) {
      blocks.push(T('레버리지 상품은 가격이 움직일 때 손실이 커지고, **넣은 돈보다 더 잃을 수 있어요.**'));
    }
    return { blocks: blocks };
  }

  /** 목표를 말하는 문장: "3년 안에 8천만 원" 같은 형태 */
  function goalPhrase(goal) {
    return (goal.months % 12 === 0 ? goal.months / 12 + '년' : goal.months + '개월') + ' 안에 ' + man(goal.amount);
  }

  function goalText(goal) {
    return goalPhrase(goal) + ' 만들고 싶어요';
  }

  /**
   * 목표에 못 미칠 때: 부족한 돈과 예상 금액을 카드로 보여 주고, 투자 비중을 올리면 닿는지 말한다.
   * 투자 수익은 연 6%로 가정한 계산이라는 점을 함께 밝힌다.
   */
  function shortfallMessage(a, info) {
    const blocks = [
      T(info.neededShare
        ? '이 비중으로는 목표에 못 미쳐요. 매달 **' + LA.about(a.monthlyInvest) + '** 투자하고 나머지는 적금에 넣어도, 목표 기간 뒤 ' + LA.about(info.planned) + '이라 목표보다 적어요.'
        : '말씀하신 투자 성향대로 계산해 보면, 매달 **' + LA.about(a.monthlyInvest) + '** 투자하고 나머지는 적금에 넣어도 목표 기간 뒤 ' + LA.about(info.planned) + '이에요. 목표에는 ' + LA.about(info.shortfall) + ' 못 미쳐요.'),
      { t: 'figures', figures: [
        { label: '목표 기간 뒤 예상', value: LA.about(info.planned), note: '투자 연 6% 가정', tone: 'warning' },
        { label: '부족한 돈', value: LA.about(info.shortfall), note: '', tone: 'warning' },
      ] },
      T('투자 수익은 연 6%로 가정한 계산이에요.'),
      T(info.neededShare
        ? '투자 비중을 **' + Math.round(info.neededShare * 100) + '%**(월 ' + LA.about(info.neededMonthly) + ')까지 올리면 목표에 닿아요. 과감하게 가시려면 이쪽이에요.'
        : '앞서 말씀드린 대로 투자만으로 채우기는 어려워요. 목표를 조정하는 편이 현실적이에요.'),
      T(info.neededShare ? '**어떻게 하실래요?**' : '**그래도 이 비중으로 갈까요, 목표를 조정할까요?**'),
    ];
    return { blocks: blocks };
  }

  /** 부족할 때 고르는 선택지. 닿는 비중이 있을 때만 과감한 투자를 보여 준다 */
  function shortfallChoices(info, goal) {
    const list = [];
    if (info && info.neededShare) list.push({ id: 'sf-bold', text: '과감하게 월 ' + LA.about(info.neededMonthly) + ' 투자할게요' });
    if (goal.amount > 50000000) list.push({ id: 'sf-amount', text: '목표를 5천만 원·5년으로 낮출게요' });
    if (goal.months < 60) list.push({ id: 'sf-period', text: '기간을 5년으로 늘릴게요' });
    list.push({ id: 'sf-keep', text: info && info.neededShare ? '지금 비중으로 갈게요' : '그래도 이 비중으로 갈게요' });
    return list;
  }

  /** 직전에 "이 비중으로 간다"고 답한 것을 받아 주는 첫 문장 */
  function keepAck() {
    return '알겠어요. 목표는 그대로 두고 이 비중으로 볼게요.';
  }

  /** 월 투자금을 어디에 넣는지 풀어 쓴다. 해외만이면 전액, 둘 다면 비중대로 나눈 금액이다 */
  function placeText(a, kind) {
    const all = LA.about(a.monthlyInvest);
    if (kind === 'dom') return '매달 투자할 ' + all + ' 전부를 국내주식에 넣는 거예요(국내 100%).';
    if (kind === 'os') return '매달 투자할 ' + all + ' 전부를 해외주식에 넣는 거예요(해외 100%).';
    return '매달 투자할 ' + all + ' 중 국내주식에 ' + a.domesticShare + '%(' + LA.about(a.domesticAmount) + '), 해외주식에 ' + a.overseasShare + '%(' + LA.about(a.overseasAmount) + ')를 넣는 거예요.';
  }

  /** 국내주식만 보면 거기서 상담을 끝낸다. 고르기 전에는 비중을 말하지 않는다 */
  function sideStop(kind, a) {
    if (a) return { text: '국내주식은 지금 쓰시는 증권 계좌로 바로 시작할 수 있어요. ' + placeText(a, 'dom') };
    return { text: '국내주식은 상품군으로만 소개해요. 개설 절차는 해외주식을 고를 때 이어가요.' };
  }

  /**
   * 해외 계좌 안내와 개설 질문. 외화 계좌가 이미 있으면(hasFx) 있다고 말하고 가입을 묻는다.
   * 해외주식만 보면 전액, 두 시장을 모두 보면(split) 해외 몫을 말한다.
   */
  function noAccount(a, split, hasFx) {
    let share = '';
    if (a) share = split ? '해외주식에는 ' + a.overseasShare + '%, ' + LA.about(a.overseasAmount) + '을 넣어요. ' : placeText(a, 'os') + ' ';
    return { text: share + accountTail(hasFx) };
  }

  /** 해외주식 계좌 질문 문장. 외화 계좌 유무에 따라 다르다 */
  function accountTail(hasFx) {
    return hasFx ? '해외주식은 외화 계좌로 거래하는데, 외화 계좌는 이미 있어요. **해외주식 계좌 개설을 도와드릴까요?**' : '해외주식은 외화 계좌가 필요한데 아직 없네요. **개설 도와드릴까요?**';
  }

  /** 국내·해외를 모두 보고 싶다고 했을 때: 월 투자금을 나눠 말하고, 해외 계좌 질문으로 잇는다 */
  function bothMessage(a, hasFx) {
    return {
      blocks: [
        T('국내주식은 지금 쓰시는 증권 계좌로 바로 시작할 수 있어요. ' + placeText(a, 'both')),
        T(accountTail(hasFx)),
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
    const lines = [OPENING, TYPED.GOAL, TYPED.PROFILING, TYPED.LOSS, TYPED.RECOMMEND, TYPED.NO_ACCOUNT, greeting().text, situationText(0), situationText(1), noAccount().text, sideStop('prod-dom').text, leverageRetry().text, laterMessage().text, investQuestion(), stopMessage().text, lossAsk().text, keepAck()];
    INVEST_CHOICES.forEach((c) => lines.push(c.text));
    ['EMERGENCY_FIRST', 'DEBT_FIRST', 'SAVINGS_ENOUGH'].forEach((id) => investChoices({ decisionId: id }).forEach((c) => lines.push(c.text)));
    EMERGENCY_CHOICES_LOW.forEach((c) => lines.push(c.text));
    introChoices().forEach((c) => lines.push(c.text));
    goalChoices().forEach((c) => lines.push(c.text));
    experienceChoices().forEach((c) => lines.push(c.text));
    lossChoices().forEach((c) => lines.push(c.text));
    productChoices(true).forEach((c) => lines.push(c.text));
    openChoices().forEach((c) => lines.push(c.text));
    spendChoices().forEach((c) => lines.push(c.text));
    SPEND_STEPS.forEach((t) => lines.push(t));
    overseasIntro().blocks.forEach((b) => lines.push(b.text));
    EMERGENCY_CHOICES.forEach((c) => lines.push(c.text));
    lines.push(TYPED.EMERGENCY, emergencyStop().text);
    goalAskMessage().blocks.forEach((b) => lines.push(b.text));
    return lines;
  }

  WSP.lumpsumScript = {
    OPENING: OPENING,
    TYPED: TYPED,
    INVEST_CHOICES: INVEST_CHOICES,
    ANALYSIS_STEPS: ANALYSIS_STEPS,
    BANNED: BANNED,
    pick: pick,
    situationText: situationText,
    greeting: greeting,
    introChoices: introChoices,
    isEmergencyIntro: isEmergencyIntro,
    purposeLabelOf: purposeLabelOf,
    EMERGENCY_CHOICES: EMERGENCY_CHOICES,
    emergencyChoices: emergencyChoices,
    emergencyEnough: emergencyEnough,
    emergencyLine: emergencyLine,
    emergencyFill: emergencyFill,
    investChoices: investChoices,
    infeasibleText: infeasibleText,
    keepAck: keepAck,
    laterMessage: laterMessage,
    leverageRetry: leverageRetry,
    placeText: placeText,
    accountTail: accountTail,
    goalAskMessage: goalAskMessage,
    emergencyStop: emergencyStop,
    isOverseasIntro: isOverseasIntro,
    overseasIntro: overseasIntro,
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
    investQuestion: investQuestion,
    stopMessage: stopMessage,
    lossAsk: lossAsk,
    recommendMessage: recommendMessage,
    goalText: goalText,
    shortfallMessage: shortfallMessage,
    shortfallChoices: shortfallChoices,
    sideStop: sideStop,
    noAccount: noAccount,
    bothMessage: bothMessage,
    thoughtSteps: thoughtSteps,
    allFixedLines: allFixedLines,
  };
})();
