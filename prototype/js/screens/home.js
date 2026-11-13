/**
 * screens/home.js
 * 홈(두 트랙 진입점·진행 중 건·계좌), 상품 목록, 상품 상세(AI와 함께 / 직접 가입 선택), 전체 메뉴.
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

  UI.registerScreen('home', {
    title: '홈',
    async render() {
      const r = await bank.getAccountSummary();
      const s = app().session;
      const hide = s.ui.hideBalance;
      const name = r.ok ? r.data.customerName : '고객';

      let acct;
      if (!r.ok) acct = '<div class="acct acct--empty">' + UI.notice('계좌 정보를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.', 'warning', I.alert) + '</div>';
      else if (!r.data.hasDepositAccount)
        acct =
          '<div class="acct acct--empty"><div class="acct__head"><span class="acct__logo">' +
          I.wallet +
          '</span><div class="acct__info"><div class="acct__name">우리은행 계좌가 아직 없어요</div><div class="acct__num">처음 거래하시는 고객님</div></div></div>' +
          '<p class="acct__hint">상품에 가입하려면 입출금 계좌가 필요해요. 가입 지원에서 함께 만들 수 있어요.</p></div>';
      else {
        acct =
          '<div class="acct"><div class="acct__head"><span class="acct__logo">' +
          I.wallet +
          '</span><div class="acct__info"><div class="acct__name">' +
          esc(r.data.account.name) +
          '</div><div class="acct__num">우리 ' +
          esc(r.data.account.number) +
          '</div></div><button class="acct__more" data-action="noop" aria-label="계좌 메뉴">' +
          I.more +
          '</button></div><div class="acct__foot"><div class="acct__bal">' +
          (hide ? '<span class="acct__hidden">잔액 숨김</span>' : '0<small>원</small>') +
          '</div><button class="toggle-pill' +
          (hide ? ' is-on' : '') +
          '" data-action="toggle-balance" role="switch" aria-checked="' +
          hide +
          '">숨김<span class="toggle-pill__track"><span class="toggle-pill__knob"></span></span></button></div>' +
          (r.data.savings.length
            ? '<div class="acct__savings">' +
              r.data.savings
                .map(
                  (sv) =>
                    '<div><span>' +
                    esc(SC.getProduct(sv.productId).name) +
                    '</span><strong>' +
                    (sv.terms && sv.terms.monthly ? '월 ' + man(sv.terms.monthly) : sv.terms && sv.terms.market ? sv.terms.market + ' 거래' : '가입') +
                    '</strong></div>'
                )
                .join('') +
              '</div>'
            : '') +
          '</div>';
      }

      const cards = resumeCards();
      const resume = cards.length
        ? '<div class="section-title">진행 중</div><div class="resume-list">' +
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

      const disclaimer = s.ui.disclaimerClosed
        ? ''
        : '<div class="disclaimer">' +
          I.info +
          '<p>이 앱은 경진대회 시연용 목업이에요. 상품·가입 조건·금액은 모두 가상으로 만든 값이며 실제 우리은행 정책이 아니에요.</p><button data-action="close-disclaimer" aria-label="안내 닫기">' +
          I.x +
          '</button></div>';

      return (
        '<div class="home-top"><div class="home-top__hello"><strong>' +
        esc(name) +
        '</strong>님, 안녕하세요</div><div class="home-top__actions">' +
        '<button class="icon-btn" data-action="noop" aria-label="알림">' +
        I.bell +
        '</button><button class="icon-btn" data-action="go-menu" aria-label="전체 메뉴">' +
        I.menu +
        '</button></div></div>' +
        '<div class="screen-body home-body">' +
        disclaimer +
        acct +
        resume +
        '<div class="section-title">무엇을 도와드릴까요?</div>' +
        '<div class="entry-grid">' +
        '<button class="entry entry--asset" data-action="asset-start"><span class="entry__icon">' +
        I.target +
        '</span><strong>AI 자산관리 상담</strong><span>모을 돈과 투자할 돈을 함께 정해요</span><em>상품 가입은 고객이 고른 뒤 따로 해요</em></button>' +
        '<button class="entry entry--product" data-action="go-products"><span class="entry__icon">' +
        I.product +
        '</span><strong>상품 가입</strong><span>상품을 고르고 AI와 함께 또는 직접 가입해요</span><em>자산 분석 없이 바로 시작할 수 있어요</em></button>' +
        '</div>' +
        '</div>' +
        '<nav class="bottom-nav">' +
        '<button class="bottom-nav__item" data-action="go-products">' +
        I.product +
        '상품</button><button class="bottom-nav__item" data-action="asset-start">' +
        I.pie +
        '자산관리</button><button class="bottom-nav__item is-active" data-action="go-home">' +
        I.homeFill +
        '홈</button><button class="bottom-nav__item" data-action="noop">' +
        I.gift +
        '혜택</button><button class="bottom-nav__item" data-action="go-menu">' +
        I.grid +
        '전체</button></nav>'
      );
    },
  });

  /* ---------- 상품 목록 ---------- */
  UI.registerScreen('products', {
    title: '상품',
    white: true,
    render() {
      return (
        UI.appbar('상품') +
        '<div class="screen-body"><p class="lead">투자·예금·적금</p>' +
        SC.PRODUCTS.map(
          (p) =>
            '<button class="product-card" data-action="open-product" data-product="' +
            p.id +
            '"><div class="product-card__top">' +
            UI.badge(p.type, 'info') +
            '<span class="product-card__rate">' +
            esc(p.rate) +
            '</span></div><strong>' +
            esc(p.name) +
            '</strong><span>' +
            esc(p.summary) +
            '</span></button>'
        ).join('') +
        '</div>'
      );
    },
  });

  /* ---------- 상품 상세 ---------- */
  UI.registerScreen('product', {
    title: '상품 상세',
    white: true,
    render(params) {
      const p = SC.getProduct(params.productId);
      if (!p) return UI.queryErrorCard('상품', { message: '상품을 찾을 수 없어요.' });
      const s = app().session;
      const ctx = params.from === 'asset' && s.asset && s.asset.handoffTerms ? s.asset.handoffTerms : null;
      const joinActive = app().fsms.join.state !== 'IDLE' && s.join && s.join.productId === p.id;
      const directActive = app().fsms.direct.state !== 'IDLE' && s.direct && s.direct.productId === p.id;
      const rows = [['상품 유형', esc(p.type)], [p.rateLabel || '금리', esc(p.rateValue || p.rate)]];
      if (p.periods.length) rows.push(['가입 기간', p.periods.map((m) => m + '개월').join(' · ')]);
      if (p.maxMonthly) rows.push(['월 납입', man(p.minMonthly) + ' ~ ' + man(p.maxMonthly)]);
      if (p.markets) rows.push(['거래 시장', esc(p.markets.join(' · '))]);
      return (
        UI.appbar(p.name) +
        '<div class="screen-body">' +
        (ctx
          ? UI.notice(
              '<strong>자산관리 상담에서 정한 방향</strong><br>' +
                esc(ctx.purpose) +
                (ctx.monthly ? ' · 월 ' + man(ctx.monthly) + (p.kind === 'BROKERAGE' ? ' 투자' : '') : '') +
                (ctx.months ? ' · ' + ctx.months + '개월' : '') +
                '<br><span class="fineprint">상품을 고른 것은 가입이 아니에요. 아래에서 가입 방법을 고르면 가입 지원이 시작돼요.</span>',
              'info',
              I.target
            )
          : '') +
        '<div class="product-hero"><span class="product-hero__type">' +
        esc(p.type) +
        '</span><h2>' +
        esc(p.name) +
        '</h2><p>' +
        esc(p.summary) +
        '</p><div class="product-hero__rate">' +
        esc(p.rate) +
        '</div></div>' +
        '<div class="card">' +
        UI.kvRows(rows) +
        '</div>' +
        '<div class="section-title">가입 조건</div><div class="card"><ul class="cond-list">' +
        p.conditions.map((id) => '<li>' + I.check + esc(SC.CONDITIONS[id].label) + '</li>').join('') +
        '</ul></div>' +
        '<div class="section-title">가입 방법 선택</div>' +
        '<div class="join-choice">' +
        '<button class="join-choice__item is-ai" data-action="join-start" data-product="' +
        p.id +
        '" data-from="' +
        (ctx ? 'asset' : '') +
        '"><span class="join-choice__icon">' +
        I.spark +
        '</span><strong>' +
        (joinActive ? 'AI 가입 지원 이어서 하기' : 'AI와 함께 가입') +
        '</strong><span>부족한 조건과 해결 순서를 확인하고, 필요한 업무 화면을 바로 열어 드려요</span></button>' +
        '<button class="join-choice__item" data-action="direct-start" data-product="' +
        p.id +
        '"><span class="join-choice__icon">' +
        I.doc +
        '</span><strong>' +
        (directActive ? '직접 가입 이어서 하기' : '직접 가입') +
        '</strong><span>기존 가입 화면을 단계별로 직접 진행해요</span></button>' +
        '</div>' +
        '</div>'
      );
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
