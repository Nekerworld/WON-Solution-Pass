/**
 * screens/home.js
 * 홈(계좌·진행 중 건·추천서비스), 상품몰, 입출금/예금/적금 목록, 상품 상세(AI와 함께 / 직접 가입 선택), 전체 메뉴.
 * 실제 우리WON뱅킹 화면 배치를 따르되, 해결패스 기능이 없는 버튼은 data-action="noop" 으로 두어 눌러도 아무 일이 없다.
 */
(function () {
  'use strict';

  const WSP = window.WSP;
  const SC = WSP.scenario;
  const bank = WSP.mockBank;
  const UI = WSP.ui;
  const I = UI.I;
  const esc = UI.esc;
  const man = WSP.utils.formatMan;
  const app = () => WSP.app;
  const sz = (icon, n) => icon.replace('<svg', '<svg width="' + n + '" height="' + n + '"');

  /* ---------- 진행 중인 건 ---------- */
  const JOIN_RESUME = {
    CONSENT: '정보 이용 동의를 기다리고 있어요',
    CHECKING: '가입 조건을 확인하고 있어요',
    CHECK_FAILED: '은행 기록 확인이 필요해요',
    CLARIFYING: '답변을 기다리고 있어요',
    ROUTE_CHECK: '해결 순서를 계산하고 있어요',
    OPTIONS_READY: '해결 방법을 골라 주세요',
    TASK_OPEN: '업무 화면을 진행하던 중이에요',
    RECHECKING: '은행 기록을 다시 확인하고 있어요',
    REMAINING: '남은 조건을 이어서 해결해요',
    INVESTIGATING: '업무 결과 확인이 필요해요',
    READY_TO_APPLY: '가입 준비 완료 · 승인이 필요해요',
    APPLYING: '가입 요청 중이에요',
    VERIFYING: '가입 결과를 확인하고 있어요',
    RESULT_UNCERTAIN: '가입 결과 확인이 필요해요 · 다시 신청하지 마세요',
    COMPLETED: '가입이 완료됐어요',
    FAILED: '가입이 처리되지 않았어요',
    ESCALATED: '상담 연결이 필요해요',
  };

  function resumeCards() {
    const f = app().fsms;
    const s = app().session;
    const cards = [];
    if (f.join.state !== 'IDLE' && s.join) {
      cards.push({
        action: 'join-open',
        tag: 'AI 가입 지원',
        title: SC.getProduct(s.join.productId).name,
        desc: JOIN_RESUME[f.join.state] || f.join.state,
        tone: ['RESULT_UNCERTAIN', 'INVESTIGATING', 'CHECK_FAILED', 'ESCALATED', 'FAILED'].indexOf(f.join.state) !== -1 ? 'warning' : '',
      });
    }
    if (f.direct.state !== 'IDLE' && s.direct) {
      const d = { D_START: '가입을 시작하지 않았어요', D_STEP: '가입 정보를 입력하던 중이에요', D_NOTICE: '부족한 조건이 있어요', D_SELF_FIX: '부족한 조건을 해결한 뒤 처음부터 다시 해요', D_APPROVE: '가입 신청 전이에요', D_VERIFYING: '가입 결과 확인 중', D_UNCERTAIN: '가입 결과 확인이 필요해요', D_DONE: '가입이 완료됐어요', D_FAILED: '가입이 처리되지 않았어요' };
      cards.push({ action: 'direct-open', tag: '직접 가입', title: SC.getProduct(s.direct.productId).name, desc: d[f.direct.state] || f.direct.state, tone: '' });
    }
    if (['IDLE', 'CLOSED', 'TO_JOIN'].indexOf(f.asset.state) === -1 && s.asset) {
      const a = { CONSENT: '정보 이용 동의를 기다리고 있어요', GOAL: '상담 목표를 알려 주세요', ASKING: '질문에 답해 주세요', REVIEW: '제안을 검토해 주세요', NEXT_ACTION: '다음 행동을 골라 주세요', EXPLORE: '상품을 둘러보는 중', HOLD: '제안이 보류됐어요', RECONSULT: '정보를 다시 확인하는 중', HANDOFF: '상담 연결 중' };
      cards.push({ action: 'asset-open', tag: 'AI 자산관리', title: '자산관리 상담', desc: a[f.asset.state] || '분석하고 있어요', tone: '' });
    }
    return cards;
  }

  /* ---------- 홈 ---------- */
  const BANK_MARK =
    '<svg viewBox="0 0 32 32" aria-hidden="true"><circle cx="16" cy="16" r="15" fill="#e8f1fe"/><path d="M8 18.5c2.6-3.2 5.4-3.2 8 0s5.4 3.2 8 0" fill="none" stroke="#2488f3" stroke-width="2.4" stroke-linecap="round"/><path d="M8 13.5c2.6-3.2 5.4-3.2 8 0s5.4 3.2 8 0" fill="none" stroke="#5aa8f7" stroke-width="2.4" stroke-linecap="round"/></svg>';

  const HOME_SCENE =
    '<svg class="w-strip__art" viewBox="0 0 220 78" aria-hidden="true">' +
    '<rect x="70" y="2" width="44" height="34" rx="3" fill="#dfe9f8"/><path d="M92 2v34M70 19h44" stroke="#fff" stroke-width="2"/>' +
    '<rect x="44" y="30" width="12" height="16" rx="2" fill="#c98f62"/><path d="M50 30c-6-8-2-14 0-16 2 2 6 8 0 16z" fill="#7bbf8a"/><path d="M50 30c5-6 10-6 12-5-1 3-6 7-12 5z" fill="#95cf9f"/>' +
    '<ellipse cx="112" cy="66" rx="70" ry="8" fill="#e3ecf8"/>' +
    '<rect x="78" y="40" width="34" height="24" rx="6" fill="#f6c46c"/><rect x="84" y="46" width="22" height="4" rx="2" fill="#fff" opacity=".8"/>' +
    '<rect x="116" y="34" width="40" height="30" rx="7" fill="#9cc3f5"/><circle cx="136" cy="49" r="7" fill="#fff" opacity=".85"/><path d="M133 49l2.5 2.5 4-5" stroke="#2488f3" stroke-width="2" fill="none" stroke-linecap="round"/>' +
    '<circle cx="168" cy="56" r="8" fill="#f2a6b8"/><circle cx="168" cy="56" r="4" fill="#fff" opacity=".7"/>' +
    '<rect x="176" y="10" width="26" height="16" rx="3" fill="#cfe0f7"/><path d="M180 16h18M180 20h12" stroke="#fff" stroke-width="2"/>' +
    '</svg>';

  function accountCard(o) {
    return (
      '<div class="w-acct"><div class="w-acct__head"><span class="w-acct__mark">' +
      BANK_MARK +
      '</span><div class="w-acct__info"><strong>' +
      esc(o.name) +
      '</strong><span>' +
      esc(o.sub) +
      (o.copy ? '<button class="w-acct__copy" data-action="noop" aria-label="계좌번호 복사">' + I.copy + '</button>' : '') +
      '</span>' +
      (o.tag ? '<em class="w-acct__tag">' + esc(o.tag) + '</em>' : '') +
      '</div><button class="w-acct__more" data-action="noop" aria-label="계좌 메뉴">' +
      I.more +
      '</button></div><div class="w-acct__foot"><div class="w-acct__bal">' +
      o.balance +
      '</div>' +
      (o.transfer ? '<button class="w-acct__btn" data-action="noop">이체</button>' : '') +
      '</div></div>'
    );
  }

  function balanceHtml(hide, amount, unit) {
    return hide ? '<span class="w-acct__hidden">잔액숨김</span>' : esc(amount) + '<small>' + esc(unit) + '</small>';
  }

  UI.registerScreen('home', {
    title: '홈',
    async render() {
      const r = await bank.getAccountSummary();
      const s = app().session;
      const hide = s.ui.hideBalance;

      let accts = '';
      if (!r.ok) accts = '<div class="w-acct">' + UI.notice('계좌 정보를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.', 'warning', I.alert) + '</div>';
      else if (!r.data.hasDepositAccount)
        accts =
          '<div class="w-acct w-acct--empty"><div class="w-acct__head"><span class="w-acct__mark">' +
          BANK_MARK +
          '</span><div class="w-acct__info"><strong>우리은행 계좌가 아직 없어요</strong><span>처음 거래하시는 고객님</span></div></div>' +
          '<p class="w-acct__hint">상품에 가입하려면 입출금 계좌가 필요해요. 가입 지원에서 함께 만들 수 있어요.</p></div>';
      else {
        accts = accountCard({ name: r.data.account.name, sub: '우리 ' + r.data.account.number, copy: true, balance: balanceHtml(hide, '0', ' 원'), transfer: true });
        if (r.data.fxAccount) accts += accountCard({ name: r.data.fxAccount.name, sub: '우리 ' + r.data.fxAccount.number, copy: true, tag: '외화', balance: balanceHtml(hide, '0.00', ' USD'), transfer: true });
        r.data.savings.forEach((sv) => {
          const p = SC.getProduct(sv.productId);
          const t = sv.terms || {};
          accts += accountCard({
            name: p.name,
            sub: t.monthly ? '매월 ' + man(t.monthly) + (t.months ? ' · ' + t.months + '개월' : '') : t.market ? t.market + ' 주식 거래' : '가입 완료',
            tag: p.type,
            balance: balanceHtml(hide, '0', p.kind === 'BROKERAGE' ? ' 원 평가금액' : ' 원'),
            transfer: false,
          });
        });
      }

      const cards = resumeCards();
      const resume = cards.length
        ? '<div class="w-resume"><h3>진행 중인 업무</h3>' +
          cards
            .map(
              (c) =>
                '<button class="resume' +
                (c.tone ? ' is-' + c.tone : '') +
                '" data-action="' +
                c.action +
                '"><span class="resume__tag">' +
                esc(c.tag) +
                '</span><span class="resume__title">' +
                esc(c.title) +
                '</span><span class="resume__desc">' +
                esc(c.desc) +
                '</span><span class="resume__go">' +
                I.chevron +
                '</span></button>'
            )
            .join('') +
          '</div>'
        : '';

      const notice = s.ui.disclaimerClosed
        ? ''
        : '<div class="w-notice"><span class="w-notice__bell">' +
          I.bell +
          '</span><p>이 앱은 경진대회 시연용 목업이에요.<br>상품·조건·금액은 모두 가상의 값이에요.</p><button data-action="close-disclaimer" aria-label="안내 닫기">' +
          I.x +
          '</button></div>';

      const svcItem = (action, icon, tone, title, desc) =>
        '<button class="w-svc__item" data-action="' +
        action +
        '"><span class="w-svc__icon is-' +
        tone +
        '">' +
        icon +
        '</span><span><strong>' +
        esc(title) +
        '</strong><em>' +
        esc(desc) +
        '</em></span></button>';

      return (
        '<header class="w-top"><div class="w-mode"><button class="is-on" data-action="noop">일반홈</button><button data-action="noop">쉬운</button></div><div class="w-top__icons">' +
        '<button data-action="noop" aria-label="지갑">' +
        I.wallet +
        '</button><button class="w-top__ai" data-action="asset-start" aria-label="AI 자산관리 상담">' +
        I.ai +
        '</button><button data-action="noop" aria-label="알림">' +
        I.bell +
        '</button><button data-action="go-menu" aria-label="전체 메뉴">' +
        I.menu +
        '</button></div></header>' +
        '<div class="screen-body w-home">' +
        notice +
        '<div class="w-strip">' +
        HOME_SCENE +
        '<div class="w-strip__bar"><button data-action="noop">' +
        sz(I.gear, 14) +
        '홈계좌설정</button><button data-action="toggle-balance" role="switch" aria-checked="' +
        hide +
        '">잔액숨김<span class="w-switch' +
        (hide ? ' is-on' : '') +
        '"><i></i></span></button></div></div>' +
        accts +
        resume +
        '<button class="w-allacct" data-action="noop">전체계좌보기</button>' +
        '<button class="w-ad" data-action="open-product" data-product="OVERSEAS_STOCK"><span class="w-ad__text"><strong>해외주식, 처음이라도 괜찮아요<br>계좌 개설부터 AI가 함께해요</strong><em>WON 해외주식 계좌 · 시연용 배너</em></span><span class="w-ad__art">' +
        sz(I.globe, 46) +
        '</span><span class="w-pager" data-action="noop">&lsaquo; 1 / 4 &rsaquo;</span></button>' +
        '<h3 class="w-h3">추천서비스</h3><div class="w-hscroll">' +
        '<div class="w-svc is-pink">' +
        svcItem('asset-start', I.target, 'blue', 'AI 자산관리 상담', '모을 돈과 투자할 돈을 함께 정해요') +
        svcItem('go-products', I.product, 'violet', '상품 가입', 'AI와 함께 또는 직접 가입해요') +
        svcItem('noop', I.wallet, 'sky', '우리WON지갑', '모바일 신분증 등 생활 서비스') +
        '</div><div class="w-svc is-blue">' +
        svcItem('noop', I.phone, 'blue', '우리WON모바일', '은행이 만든 알뜰폰 통신') +
        svcItem('noop', I.globe, 'teal', '환전주머니', '여행 환전을 손쉽게 준비해요') +
        svcItem('noop', I.coin, 'sky', 'ATM 출금', '카드 없이 휴대폰으로 출금') +
        '</div></div>' +
        '<h3 class="w-h3">우리금융그룹 서비스</h3><div class="w-hscroll w-group">' +
        [
          ['보험', '#7b5cff', '나를 지켜주는\n든든한 보장', I.shield],
          ['캐피탈', '#11a37f', '내 자동차\n대출 한도', I.route],
          ['증권', '#2488f3', '새로운\n투자 정보', I.stock],
          ['카드', '#e2537a', '혜택 많은\n카드 찾기', I.wallet],
        ]
          .map(
            (g) =>
              '<button class="w-group__card" data-action="noop"><strong style="color:' +
              g[1] +
              '">' +
              g[0] +
              '</strong><span>' +
              esc(g[2]).replace('\n', '<br>') +
              '</span><i style="color:' +
              g[1] +
              '">' +
              g[3] +
              '</i></button>'
          )
          .join('') +
        '</div>' +
        '<button class="w-noticebar" data-action="noop"><em>공지</em><span>이 화면은 경진대회 시연용 모의 화면이에요</span>' +
        I.chevron +
        '</button>' +
        '</div>' +
        UI.bottomNav('home')
      );
    },
  });

  /* ---------- 상품몰 ---------- */
  const CATEGORIES = [
    ['입출금/예적금', 'go-product-list', '#ff8fa3', I.coin],
    ['청약', 'noop', '#9b7bff', I.homeFill],
    ['대출', 'noop', '#4b8df8', I.doc],
    ['펀드', 'noop', '#7c6cf2', I.stock],
    ['퇴직연금', 'noop', '#b0805c', I.clock],
    ['신탁', 'noop', '#6a62e6', I.list],
    ['ISA', 'noop', '#3d8bf2', I.pie],
    ['외환', 'noop', '#2e7ff0', I.globe],
    ['개인사업자', 'noop', '#29a3c2', I.product],
    ['보험', 'noop', '#2ebd85', I.shield],
    ['골드/실버', 'noop', '#e8a92c', I.gift],
    ['카드', 'noop', '#f06b9b', I.wallet],
  ];

  UI.registerScreen('products', {
    title: '상품몰',
    white: true,
    render() {
      const f = app().fsms;
      const ongoing = (f.join.state !== 'IDLE' ? 1 : 0) + (f.direct.state !== 'IDLE' ? 1 : 0);
      const viewed = app().session.ui.lastProduct ? 1 : 0;
      const pick = (action, product, tone, title, sub, icon) =>
        '<button class="w-pick is-' +
        tone +
        '" data-action="' +
        action +
        '"' +
        (product ? ' data-product="' + product + '"' : '') +
        '><span><strong>' +
        esc(title) +
        '</strong><em>' +
        esc(sub) +
        '</em></span><i>' +
        icon +
        '</i></button>';
      return (
        '<header class="w-mallbar"><h1>상품몰</h1><div class="w-top__icons"><button class="w-top__ai" data-action="asset-start" aria-label="AI 자산관리 상담">' +
        I.ai +
        '</button><button data-action="noop" aria-label="장바구니">' +
        I.cart +
        '</button><button data-action="go-menu" aria-label="전체 메뉴">' +
        I.menu +
        '</button></div></header>' +
        '<div class="screen-body w-mall">' +
        '<button class="w-mall__banner" data-action="open-product" data-product="OVERSEAS_STOCK"><span><strong>처음 거래 고객도 해외주식까지<br>가입 순서는 AI가 정리해 드려요</strong><em>WON 해외주식 계좌 · 시연용 배너</em></span><i>' +
        sz(I.globe, 52) +
        '</i><span class="w-pager">&lsaquo; 2 / 5 &rsaquo;</span></button>' +
        '<div class="w-mall__stats">' +
        [
          ['이어서 가입하기', ongoing],
          ['최근 본 상품', viewed],
          ['영업점 추천 상품', 0],
        ]
          .map((x) => '<button data-action="noop"><span>' + x[0] + '</span><strong>' + x[1] + '<small>개</small></strong></button>')
          .join('') +
        '</div>' +
        '<div class="w-cat">' +
        CATEGORIES.map((c) => '<button data-action="' + c[1] + '"><i style="background:' + c[2] + '1f;color:' + c[2] + '">' + c[3] + '</i><span>' + c[0] + '</span></button>').join('') +
        '</div>' +
        '<button class="w-mall__row" data-action="noop"><i>' +
        sz(I.route, 26) +
        '</i><span><strong>우리금융그룹 상품</strong><em>보험 · 증권 · 캐피탈 · 저축은행</em></span>' +
        I.chevron +
        '</button>' +
        '<div class="w-mall__ask"><strong>전문 <b>AI상담원</b>에게 물어보세요</strong><div>' +
        ['예적금상담', '대출상담', '청약상담'].map((x) => '<button data-action="noop">' + sz(I.spark, 12) + x + '</button>').join('') +
        '</div></div>' +
        '<h3 class="w-h3 w-h3--big">WON PICK 추천</h3>' +
        pick('open-product', 'OVERSEAS_STOCK', 'blue', '해외주식, 처음이라면?', 'WON 해외주식 계좌', I.stock) +
        pick('noop', '', 'violet', '외국 갈 땐 든든하게 외화 챙기기', '환전주머니', I.globe) +
        pick('noop', '', 'sky', '은행이 만든 알뜰한 요금제', '우리WON모바일', I.phone) +
        '<div class="w-mall__list">' +
        [
          ['금융 소외 없이 든든한 포용금융', '우리포용금융', I.shield],
          ['공항라운지 & 여행 카드 모음집', '우리카드', I.wallet],
          ['자동차로 할 수 있는 금융', '우리금융캐피탈', I.route],
        ]
          .map((x) => '<button data-action="noop"><i>' + x[2] + '</i><span><strong>' + x[0] + '</strong><em>' + x[1] + '</em></span>' + I.chevron + '</button>')
          .join('') +
        '</div></div>' +
        UI.bottomNav('products')
      );
    },
  });

  /* ---------- 입출금/예금/적금 목록 ---------- */
  function rateNum(p) {
    return parseFloat(String(p.rate).replace(/[^0-9.]/g, '')) || 0;
  }
  function periodText(p) {
    if (!p.periods.length) return '';
    return '(' + (p.periods.length > 1 ? p.periods[0] + '~' + p.periods[p.periods.length - 1] : p.periods[0]) + '개월) ';
  }
  const LIST_GROUPS = [
    ['saving', '적금', [{ id: 'SAVINGS_GOAL' }, { id: 'FREE_SAVINGS' }, { name: 'WON 주거래 우대적금', desc: '급여·자동이체 실적에 따라 우대금리를 더해 드려요', rate: '(12개월) 연 2.9% ~ 3.4%' }, { name: 'WON 여행 적금', desc: '여행 날짜에 맞춰 모으는 자유적립 적금', rate: '(6개월) 연 2.7%' }]],
    ['deposit', '예금', [{ name: 'WON 첫거래 정기예금', desc: '처음 거래하는 고객을 위한 정기예금', rate: '(12개월) 연 2.6% ~ 3.0%' }, { name: 'WON 회전 정기예금', desc: '정해진 주기마다 금리가 바뀌는 정기예금', rate: '(12~36개월) 연 2.5%' }]],
    ['demand', '입출금', [{ id: 'PARKING' }, { name: 'WON 생활비 통장', desc: '수수료 면제 혜택이 있는 입출금 통장', rate: '연 0.1%' }]],
  ];

  UI.registerScreen('product-list', {
    title: '입출금/예금/적금',
    white: true,
    render() {
      const row = (x) => {
        const p = x.id ? SC.getProduct(x.id) : null;
        return (
          '<button class="w-plist__row" data-action="' +
          (p ? 'open-product" data-product="' + p.id : 'noop') +
          '"><strong>' +
          esc(p ? p.name : x.name) +
          '</strong><span>' +
          esc(p ? p.summary : x.desc) +
          '</span><em>' +
          (p ? '<small>' + esc(periodText(p)) + '</small>' + esc(p.rate) : esc(x.rate).replace(/^(\(.+?\))/, '<small>$1</small>')) +
          '</em></button>'
        );
      };
      const g = SC.getProduct('SAVINGS_GOAL');
      return (
        UI.appbar('입출금/예금/적금', { right: '<button class="icon-btn" data-action="noop" aria-label="장바구니">' + I.cart + '</button>' }) +
        '<div class="screen-body w-plist">' +
        '<div class="w-plist__hero"><h2>저축의 시작은 안전하고 꾸준하게</h2><p>목돈 마련부터 생활비 관리까지 한눈에 비교해 보세요</p>' +
        '<div class="w-carousel"><span class="w-carousel__peek is-l"></span><button class="w-carousel__card" data-action="open-product" data-product="SAVINGS_GOAL"><em>매달 정해진 금액으로 목돈 만들기</em><strong>' +
        esc(g.name) +
        '</strong><i>' +
        sz(I.coin, 54) +
        '</i><span>' +
        esc(g.rate) +
        '<br>' +
        g.periods.join('·') +
        '개월 기준</span></button><span class="w-carousel__peek is-r"></span></div>' +
        '<div class="w-dots"><button data-action="noop">&lsaquo;</button>1 / 3<button data-action="noop">&rsaquo;</button></div></div>' +
        '<div class="w-tabs">' +
        LIST_GROUPS.map((x, i) => '<button class="' + (i === 0 ? 'is-on' : '') + '" data-action="plist-tab" data-tab="' + x[0] + '">' + x[1] + '</button>').join('') +
        '<button class="w-tabs__sort" data-action="noop">조회기준 ' +
        sz(I.down, 14) +
        '</button></div>' +
        LIST_GROUPS.map((x) => '<section class="w-plist__sec" id="pl-' + x[0] + '"><h3>' + x[1] + '</h3>' + x[2].map(row).join('') + '<button class="w-more" data-action="noop">더보기 ' + sz(I.down, 13) + '</button></section>').join('') +
        '<section class="w-plist__sec"><h3>기타서비스</h3><button class="w-plist__row" data-action="noop"><strong>상품 금리조회</strong><span>예적금 상품 금리를 한눈에 비교해 보세요</span></button></section>' +
        '<p class="w-fine">목록의 상품명과 금리는 시연용 가상 값이에요.</p>' +
        '</div>'
      );
    },
  });

  /* ---------- 상품 상세 ---------- */
  function savingsInterest(monthly, months, rate) {
    return Math.round((monthly * (rate / 100) * (months * (months + 1))) / 2 / 12);
  }
  const won = (n) => Number(n).toLocaleString('ko-KR');

  UI.registerScreen('product', {
    title: '상품 상세',
    white: true,
    render(params) {
      const p = SC.getProduct(params.productId);
      if (!p) return UI.queryErrorCard('상품', { message: '상품을 찾을 수 없어요.' });
      const s = app().session;
      s.ui.lastProduct = p.id;
      const ctx = params.from === 'asset' && s.asset && s.asset.handoffTerms ? s.asset.handoffTerms : null;
      const joinActive = app().fsms.join.state !== 'IDLE' && s.join && s.join.productId === p.id;
      const directActive = app().fsms.direct.state !== 'IDLE' && s.direct && s.direct.productId === p.id;
      const isSavings = p.maxMonthly > 0;
      const rate = rateNum(p);

      let title;
      let chips;
      let box;
      let slider = '';
      if (isSavings) {
        const months = ctx && ctx.months && p.periods.indexOf(ctx.months) !== -1 ? ctx.months : p.periods[0];
        const step = 10000;
        const max = Math.min(p.maxMonthly, 1000000);
        const monthly = Math.max(p.minMonthly, Math.min(max, ctx && ctx.monthly ? Math.round(ctx.monthly / step) * step : 500000));
        title = esc(p.name) + '<br>총 <b id="pd-interest">' + won(savingsInterest(monthly, months, rate)) + '</b>원의<br>이자를 드려요';
        chips = '<span class="w-chip" id="pd-principal">원금 · ' + won(monthly * months) + '원</span><span class="w-chip">예상금리 · ' + esc(p.rate) + '(세전) ' + sz(I.down, 13) + '</span>';
        box = '가입기간 <b>' + months + '개월</b> 상품이에요' + (p.periods.length > 1 ? '<small>' + p.periods.join('·') + '개월 중 가입할 때 고를 수 있어요</small>' : '');
        slider =
          '<div class="w-slider"><strong id="pd-monthly-label">한달에 ' +
          esc(man(monthly)) +
          '</strong><input type="range" min="' +
          p.minMonthly +
          '" max="' +
          max +
          '" step="' +
          step +
          '" value="' +
          monthly +
          '" data-input="pd-monthly" data-months="' +
          months +
          '" data-rate="' +
          rate +
          '" aria-label="월 납입액" /><div><span>' +
          esc(man(p.minMonthly)) +
          '</span><span>' +
          esc(man(max)) +
          '</span></div></div><button class="w-link" data-action="noop">조건 직접 입력하기</button>';
      } else if (p.kind === 'BROKERAGE') {
        title = esc(p.name) + '<br><b>' + esc(p.markets.join('·')) + '</b> 주식을<br>한 계좌로 거래해요';
        chips = '<span class="w-chip">' + esc(p.rateLabel) + ' · ' + esc(p.rateValue) + '</span><span class="w-chip">거래 시장 · ' + p.markets.length + '곳</span>';
        box = '<b>원화·외화 계좌</b>를 연결해서 쓰는 상품이에요<small>투자 상품이라 원금 손실이 날 수 있어요</small>';
      } else {
        title = esc(p.name) + '<br>언제든 꺼내 쓰는<br><b>' + esc(p.rate) + '</b> 통장이에요';
        chips = '<span class="w-chip">금리 · ' + esc(p.rate) + '(세전)</span>';
        box = '<b>가입기간 없이</b> 자유롭게 넣고 빼요';
      }

      const rows = [['상품 유형', esc(p.type)], [p.rateLabel || '금리', esc(p.rateValue || p.rate)]];
      if (p.periods.length) rows.push(['가입 기간', p.periods.map((m) => m + '개월').join(' · ')]);
      if (p.maxMonthly) rows.push(['월 납입', man(p.minMonthly) + ' ~ ' + man(p.maxMonthly)]);
      if (p.markets) rows.push(['거래 시장', esc(p.markets.join(' · '))]);

      const header = p.kind === 'BROKERAGE' ? '해외주식 계좌 개설' : p.type + ' 가입';
      return (
        UI.appbar(header, { right: '<button class="icon-btn" data-action="noop" aria-label="관심 상품">' + I.heart + '</button>' }) +
        '<div class="screen-body w-pd">' +
        '<h2 class="w-pd__title">' +
        title +
        '</h2><div class="w-pd__chips">' +
        chips +
        '</div>' +
        (ctx
          ? '<div class="w-pd__ctx">' +
            I.target +
            '<p><strong>자산관리 상담에서 정한 방향</strong><br>' +
            esc(ctx.purpose) +
            (ctx.monthly ? ' · 월 ' + man(ctx.monthly) + (p.kind === 'BROKERAGE' ? ' 투자' : '') : '') +
            (ctx.months ? ' · ' + ctx.months + '개월' : '') +
            '<br><span>상품을 고른 것은 가입이 아니에요. 아래 상품 가입에서 가입 방법을 고르면 가입 지원이 시작돼요.</span></p></div>'
          : '') +
        '<div class="w-pd__box">' +
        box +
        '</div>' +
        slider +
        '<hr class="w-sep" />' +
        '<h3 class="w-h3">자주하는 질문</h3>' +
        '<div class="w-faq"><strong>' +
        sz(I.chat, 16) +
        '이 상품은 어떤 상품인가요?</strong><div class="w-faq__a"><p>' +
        esc(p.summary) +
        '</p>' +
        UI.kvRows(rows) +
        '</div></div>' +
        '<div class="w-faq"><strong>' +
        sz(I.chat, 16) +
        '가입하려면 무엇이 필요한가요?</strong><div class="w-faq__a"><ul>' +
        p.conditions.map((id) => '<li>' + esc(SC.CONDITIONS[id].label) + '</li>').join('') +
        '</ul><p class="w-faq__note">＊ 부족한 조건은 AI와 함께 가입할 때 해결 순서를 안내해 드려요.</p></div></div>' +
        '<button class="w-more w-more--box" data-action="noop">더보기</button>' +
        '<hr class="w-sep" />' +
        '<div class="w-rows">' +
        ['상품설명', p.kind === 'BROKERAGE' ? '수수료안내' : '금리안내', '약관 및 상품설명서'].map((x) => '<button data-action="noop">' + x + I.chevron + '</button>').join('') +
        '</div><hr class="w-sep" />' +
        '<h3 class="w-h3">공유하기</h3><div class="w-share">' +
        [
          ['카카오톡', '#fee500', '#3c1e1e', I.chat],
          ['문자', '#e8f1fe', '#2488f3', I.msg],
          ['앱 선택', '#eef0f3', '#5a636c', I.grid],
        ]
          .map((x) => '<button data-action="noop"><i style="background:' + x[1] + ';color:' + x[2] + '">' + x[3] + '</i>' + x[0] + '</button>')
          .join('') +
        '</div>' +
        '<p class="w-pd__law"><strong>준법감시인 심의필</strong>경진대회 시연용 모의 화면으로 심의 번호가 없어요.</p>' +
        '</div>' +
        '<div class="w-pd__foot"><button class="w-btn w-btn--soft" data-action="noop">상담</button><button class="w-btn" data-action="pd-join" data-product="' +
        p.id +
        '" data-from="' +
        (ctx ? 'asset' : '') +
        '">' +
        (joinActive || directActive ? '이어서 가입' : '상품 가입') +
        '</button></div>'
      );
    },
  });

  WSP.registerActions({
    'go-product-list'() {
      UI.navigate('product-list');
    },
    'input:pd-monthly'(el) {
      const monthly = Number(el.value);
      const months = Number(el.dataset.months);
      const q = (id) => document.getElementById(id);
      if (q('pd-interest')) q('pd-interest').textContent = won(savingsInterest(monthly, months, Number(el.dataset.rate)));
      if (q('pd-principal')) q('pd-principal').textContent = '원금 · ' + won(monthly * months) + '원';
      if (q('pd-monthly-label')) q('pd-monthly-label').textContent = '한달에 ' + man(monthly);
    },
    'plist-tab'(d, el) {
      const sec = document.getElementById('pl-' + d.tab);
      if (sec) sec.scrollIntoView({ behavior: 'smooth', block: 'start' });
      el.parentNode.querySelectorAll('[data-tab]').forEach((b) => b.classList.toggle('is-on', b === el));
    },
    'pd-join'(d) {
      const s = app().session;
      const joinActive = app().fsms.join.state !== 'IDLE' && s.join && s.join.productId === d.product;
      const directActive = app().fsms.direct.state !== 'IDLE' && s.direct && s.direct.productId === d.product;
      const p = SC.getProduct(d.product);
      UI.openSheet(
        '<div class="w-sheet"><h3>' +
          esc(p.name) +
          '<br>가입 방법을 골라 주세요</h3>' +
          '<button class="join-choice__item is-ai" data-action="pd-choose" data-next="join-start" data-product="' +
          p.id +
          '" data-from="' +
          (d.from || '') +
          '"><span class="join-choice__icon">' +
          I.spark +
          '</span><strong>' +
          (joinActive ? 'AI 가입 지원 이어서 하기' : 'AI와 함께 가입') +
          '</strong><span>부족한 조건과 해결 순서를 확인하고, 필요한 업무 화면을 바로 열어 드려요</span></button>' +
          '<button class="join-choice__item" data-action="pd-choose" data-next="direct-start" data-product="' +
          p.id +
          '"><span class="join-choice__icon">' +
          I.doc +
          '</span><strong>' +
          (directActive ? '직접 가입 이어서 하기' : '직접 가입') +
          '</strong><span>기존 가입 화면을 단계별로 직접 진행해요</span></button></div>'
      );
    },
    'pd-choose'(d) {
      UI.closeSheet(true);
      app().dispatch(d.next, { product: d.product, from: d.from || '' });
    },
  });

  /* ---------- 전체 메뉴 (기존 업무 화면) ---------- */
  const MENU_ORDER = ['실명확인', '계좌 개설', '인증센터', '내 정보 관리', '외환', '투자'];

  UI.registerScreen('menu', {
    title: '전체 메뉴',
    white: true,
    async render(params) {
      const c = await bank.checkConditions(SC.PRODUCTS[0].id);
      const facts = c.ok ? c.data.facts : null;
      const d = app().session.direct;
      const selfFix = app().fsms.direct.state === 'D_SELF_FIX' && d;
      let banner = '';
      if (selfFix) {
        banner =
          '<div class="selffix">' +
          '<strong>직접 가입 중이에요</strong><p>' +
          esc(WSP.utils.josa(d.notice ? d.notice.conditions.map((x) => x.label).join(', ') : '부족한 조건', '을')) +
          ' 해결한 뒤, 가입을 처음부터 다시 진행해야 해요.</p>' +
          '<button class="btn btn--primary btn--sm" data-action="direct-restart">가입 처음부터 다시 하기</button></div>';
      }
      const groups = MENU_ORDER.map((menu) => {
        const tasks = SC.TASKS.filter((t) => t.menu === menu);
        return (
          '<div class="menu-group' +
          (params.highlight === menu ? ' is-highlight' : '') +
          '"><h3>' +
          esc(menu) +
          '</h3>' +
          tasks
            .map((t) => {
              const done = facts && Object.keys(t.effects).every((f) => facts[f] === t.effects[f]);
              return (
                '<button class="menu-item" data-action="menu-task" data-task="' +
                t.id +
                '"><span class="menu-item__icon">' +
                (UI.TASK_ICON[t.icon] || I.doc) +
                '</span><span class="menu-item__text"><strong>' +
                esc(t.label) +
                '</strong><span>' +
                esc(t.desc) +
                '</span></span>' +
                (done ? UI.badge('완료', 'success') : I.chevron) +
                '</button>'
              );
            })
            .join('') +
          '</div>'
        );
      }).join('');
      return UI.appbar('전체 메뉴') + '<div class="screen-body">' + banner + (c.ok ? '' : UI.notice('완료 여부를 불러오지 못했어요.', 'warning', I.alert)) + groups + '</div>';
    },
  });

  WSP.registerActions({
    'menu-task'(d) {
      const r = bank.openTask(d.task, { mode: 'menu' });
      if (!r.ok) return UI.toast(r.error.message, 'danger');
      const ds = app().session.direct;
      if (ds && app().fsms.direct.state === 'D_SELF_FIX') ds.metrics.menuVisits += 1;
      app().save();
      UI.openTaskModal(d.task, r.data.sessionId, {
        mode: 'menu',
        onClose: (res) => {
          if (res.status === 'OPEN') bank.cancelTask(res.sessionId);
          if (UI.current() && UI.current().id === 'menu') UI.rerender();
        },
      });
    },
  });
})();
