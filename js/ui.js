/**
 * ui.js
 * - 화면 ID 허용목록 기반 라우터 (history stack, 전환 애니메이션)
 * - 하단 시트 / 확인 모달 / 토스트
 * - 각 화면 템플릿. 화면은 저장소를 직접 읽지 않고 Mock Bank 조회 결과로 그린다.
 * 사용자 동작은 data-action 속성으로 app.js에 위임한다.
 */
(function () {
  'use strict';

  const WSP = window.WSP;
  const bank = WSP.mockBank;
  const PF = WSP.pathfinder;
  const P = WSP.DEMO_POLICY;
  const fmt = WSP.utils.formatWon;
  const man = WSP.utils.formatMan;

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
  }

  const svg = (d, extra) =>
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"' +
    (extra || '') +
    '>' +
    d +
    '</svg>';

  const I = {
    back: svg('<path d="M15 5l-7 7 7 7"/>'),
    bell: svg('<path d="M6 16V11a6 6 0 1 1 12 0v5l1.5 2h-15L6 16z"/><path d="M10 20a2 2 0 0 0 4 0"/>'),
    menu: svg('<path d="M4 7h16M4 12h16M4 17h16"/>'),
    refresh: svg('<path d="M20 11a8 8 0 1 0-2.3 5.7"/><path d="M20 5v6h-6"/>'),
    send: svg('<path d="M4 12l16-8-6 16-2.5-6.5L4 12z"/>'),
    transfer: svg('<path d="M4 8h13l-3-3"/><path d="M20 16H7l3 3"/>'),
    key: svg('<circle cx="8" cy="15" r="4"/><path d="M11 12l8-8M16 7l2 2M14 9l2 2"/>'),
    gauge: svg('<path d="M4 17a8 8 0 1 1 16 0"/><path d="M12 17l4-6"/>'),
    user: svg('<circle cx="12" cy="8" r="4"/><path d="M4 21c1-4 4-6 8-6s7 2 8 6"/>'),
    idcard: svg('<rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="9" cy="12" r="2.2"/><path d="M14 10h4M14 14h4M6 16c.6-1.2 1.7-1.8 3-1.8s2.4.6 3 1.8"/>'),
    list: svg('<path d="M8 6h12M8 12h12M8 18h12"/><circle cx="4" cy="6" r="1"/><circle cx="4" cy="12" r="1"/><circle cx="4" cy="18" r="1"/>'),
    card: svg('<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3 10h18M7 15h3"/>'),
    coin: svg('<circle cx="12" cy="12" r="8"/><path d="M9.5 9.5h4a1.5 1.5 0 0 1 0 3h-3a1.5 1.5 0 0 0 0 3h4M12 8v1.5M12 15v1.5"/>'),
    chart: svg('<path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/>'),
    globe: svg('<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c3 3.5 3 14.5 0 18M12 3c-3 3.5-3 14.5 0 18"/>'),
    home: svg('<path d="M4 11l8-7 8 7v9h-5v-6H9v6H4z"/>'),
    gift: svg('<rect x="4" y="9" width="16" height="11" rx="1"/><path d="M3 9h18v-3H3zM12 6v14M12 6c-2-3-5-3-5-1s3 1 5 1zm0 0c2-3 5-3 5-1s-3 1-5 1z"/>'),
    grid: svg('<rect x="4" y="4" width="6" height="6" rx="1"/><rect x="14" y="4" width="6" height="6" rx="1"/><rect x="4" y="14" width="6" height="6" rx="1"/><rect x="14" y="14" width="6" height="6" rx="1"/>'),
    product: svg('<path d="M4 8l8-4 8 4-8 4-8-4z"/><path d="M4 12l8 4 8-4M4 16l8 4 8-4"/>'),
    spark: svg('<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"/><path d="M19 16l.8 2.2L22 19l-2.2.8L19 22l-.8-2.2L16 19l2.2-.8z"/>'),
    check: svg('<path d="M5 12.5l4.5 4.5L19 7.5"/>', ' stroke-width="2.6"'),
    clock: svg('<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>'),
    alert: svg('<path d="M12 3l10 18H2z"/><path d="M12 10v5M12 18v.5"/>'),
    question: svg('<circle cx="12" cy="12" r="9"/><path d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.7.3-1 .9-1 1.7M12 17v.5"/>'),
    x: svg('<path d="M6 6l12 12M18 6L6 18"/>', ' stroke-width="2.4"'),
    lock: svg('<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>'),
    shield: svg('<path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/><path d="M9 12l2 2 4-4"/>'),
    info: svg('<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5v.5"/>'),
    chat: svg('<path d="M4 5h16v11H9l-5 4z"/><path d="M8 10h8M8 13h5"/>'),
    headset: svg('<path d="M4 14v-2a8 8 0 1 1 16 0v2"/><rect x="3" y="14" width="4" height="6" rx="1.5"/><rect x="17" y="14" width="4" height="6" rx="1.5"/><path d="M19 20c0 1-1.5 2-4 2h-2"/>'),
    phone: svg('<rect x="7" y="2.5" width="10" height="19" rx="2.5"/><path d="M11 18.5h2"/>'),
    chevron: svg('<path d="M9 6l6 6-6 6"/>'),
    eye: svg('<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>'),
    eyeOff: svg('<path d="M3 3l18 18"/><path d="M10.6 5.1A10.6 10.6 0 0 1 12 5c6.5 0 10 7 10 7a17 17 0 0 1-3 3.9M6.6 6.6C3.8 8.4 2 12 2 12s3.5 7 10 7c1.8 0 3.3-.5 4.6-1.2"/>'),
    wallet: svg('<path d="M4 7h14a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z"/><path d="M4 7l11-3v3"/><path d="M15 13.5h2"/>'),
    copy: svg('<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V5a1 1 0 0 0-1-1H5a1 1 0 0 0-1 1v10a1 1 0 0 0 1 1h3"/>'),
    more: svg('<circle cx="12" cy="5" r="1.4" style="fill:currentColor;stroke:none"/><circle cx="12" cy="12" r="1.4" style="fill:currentColor;stroke:none"/><circle cx="12" cy="19" r="1.4" style="fill:currentColor;stroke:none"/>'),
    gear: svg('<circle cx="12" cy="12" r="3"/><path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M5.3 18.7l2.1-2.1M16.6 7.4l2.1-2.1"/>'),
    pie: svg('<path d="M12 3a9 9 0 1 0 9 9h-9z"/><path d="M15 3.5A9 9 0 0 1 20.5 9H15z"/>'),
    stock: svg('<path d="M3 17l5-5 4 3 8-8"/><path d="M15 7h5v5"/>'),
    plus: svg('<path d="M12 5v14M5 12h14"/>'),
    homeFill:
      '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3.5 10.6L12 3.5l8.5 7.1V20a1 1 0 0 1-1 1H15v-6H9v6H4.5a1 1 0 0 1-1-1z" fill="currentColor"/></svg>',
    ai:
      '<svg viewBox="0 0 28 28" aria-hidden="true"><circle cx="13" cy="15" r="10" fill="none" stroke="currentColor" stroke-width="1.9"/><text x="13" y="18.6" text-anchor="middle" font-size="10" font-weight="800" fill="currentColor" font-family="Arial, sans-serif">AI</text><path d="M23 1.5l.9 2.4 2.4.9-2.4.9-.9 2.4-.9-2.4-2.4-.9 2.4-.9z" fill="#2488f3"/></svg>',
    robot:
      '<svg viewBox="0 0 40 40" aria-hidden="true"><rect x="9" y="13" width="22" height="17" rx="7" fill="#fff"/><circle cx="16" cy="21.5" r="2" fill="#2488f3"/><circle cx="24" cy="21.5" r="2" fill="#2488f3"/><path d="M20 13V9" stroke="#fff" stroke-width="2" stroke-linecap="round"/><circle cx="20" cy="8" r="2" fill="#fff"/></svg>',
  };

  /** 홈 상단 일러스트(자체 제작 장식) */
  const HOME_ART =
    '<svg class="home-hero__art" viewBox="0 0 360 120" aria-hidden="true">' +
    '<rect x="34" y="14" width="78" height="70" rx="10" fill="#fff" stroke="#cfe3f7" stroke-width="2"/>' +
    '<rect x="42" y="22" width="28" height="54" rx="4" fill="#d6ecff"/><rect x="76" y="22" width="28" height="54" rx="4" fill="#d6ecff"/>' +
    '<circle cx="94" cy="36" r="6" fill="#fff4c7"/>' +
    '<rect x="150" y="26" width="52" height="38" rx="6" fill="#fff" stroke="#cfe3f7" stroke-width="2"/>' +
    '<path d="M156 58l12-14 9 9 7-6 12 11z" fill="#bfe3c9"/>' +
    '<path d="M262 0v26" stroke="#b9c7d6" stroke-width="2"/><path d="M246 40a16 14 0 0 1 32 0z" fill="#ffd66b"/>' +
    '<rect x="292" y="78" width="26" height="24" rx="5" fill="#f2c9a5"/>' +
    '<ellipse cx="298" cy="66" rx="8" ry="15" fill="#86d1a6" transform="rotate(-18 298 66)"/>' +
    '<ellipse cx="312" cy="64" rx="8" ry="16" fill="#6cc497" transform="rotate(16 312 64)"/>' +
    '<ellipse cx="226" cy="98" rx="14" ry="4" fill="#ffd66b"/><ellipse cx="226" cy="93" rx="14" ry="4" fill="#ffe08a"/><ellipse cx="226" cy="88" rx="14" ry="4" fill="#ffe9a8"/>' +
    '</svg>';

  /** 가로 스크롤 카드에 점 표시를 연결한다 */
  function bindCarousels(root) {
    root.querySelectorAll('[data-carousel]').forEach((track) => {
      const dots = track.parentElement.querySelector('[data-dots]');
      if (!dots) return;
      const items = Array.prototype.slice.call(track.children);
      track.addEventListener(
        'scroll',
        () => {
          let idx = 0;
          let best = Infinity;
          items.forEach((it, i) => {
            const d = Math.abs(it.offsetLeft - items[0].offsetLeft - track.scrollLeft);
            if (d < best) {
              best = d;
              idx = i;
            }
          });
          Array.prototype.forEach.call(dots.children, (dot, i) => dot.classList.toggle('is-on', i === idx));
        },
        { passive: true }
      );
    });
  }

  function dotsHtml(n) {
    if (n < 2) return '';
    let h = '<div class="dots" data-dots>';
    for (let i = 0; i < n; i++) h += '<i' + (i === 0 ? ' class="is-on"' : '') + '></i>';
    return h + '</div>';
  }

  /* ==================================================================
   * 공용 템플릿 조각
   * ================================================================== */

  function appbar(title, opts) {
    const o = opts || {};
    const left = o.noBack ? '<span></span>' : '<button class="icon-btn" data-action="back" aria-label="뒤로 가기">' + I.back + '</button>';
    return '<header class="appbar">' + left + '<div class="appbar__title">' + esc(title) + '</div>' + (o.right || '<span></span>') + '</header>';
  }

  function badge(text, tone) {
    return '<span class="badge' + (tone ? ' badge--' + tone : '') + '">' + esc(text) + '</span>';
  }

  function notice(html, tone, icon) {
    return '<div class="notice' + (tone ? ' notice--' + tone : '') + '">' + (icon || I.info) + '<div>' + html + '</div></div>';
  }

  function kvRows(rows) {
    return (
      '<div class="kv">' +
      rows
        .map((r) => '<div class="kv__row"><span class="kv__key">' + esc(r[0]) + '</span><span class="kv__val">' + r[1] + '</span></div>')
        .join('') +
      '</div>'
    );
  }

  function queryErrorCard(title, error) {
    return (
      appbar(title) +
      '<div class="screen-body">' +
      '<div class="result"><div class="result__icon result__icon--neutral">' +
      I.alert +
      '</div><h2 class="result__title">정보를 불러오지 못했어요</h2><p class="result__desc">' +
      esc(error ? error.message : '') +
      '<br>확인되지 않은 정보로 진행하지 않아요. 잠시 후 다시 시도해 주세요.</p></div></div>' +
      '<div class="screen-footer"><div class="btn-row"><button class="btn btn--ghost" data-action="go-home">홈으로</button><button class="btn btn--primary" data-action="reload-screen">다시 시도</button></div></div>'
    );
  }

  function app() {
    return WSP.app;
  }

  function passLinkedNotice(actionId) {
    const a = app();
    if (a.fsm.state !== 'WAITING_USER') return '';
    const label = PF.getAction(actionId).label;
    return notice('<strong>WON 해결패스에서 연결된 화면이에요.</strong><br>' + esc(label) + '을 마치면 해결패스가 은행 상태를 다시 확인해요.', 'info', I.spark);
  }

  /* ==================================================================
   * 화면 정의
   * ================================================================== */

  const SCREENS = {};

  /* ---------- Home ---------- */
  SCREENS.home = {
    title: '홈',
    async render() {
      const cs = await bank.getCustomerState();
      const a = app();
      const s = a.session;
      const st = a.fsm.state;
      const hideBal = !!s.hideBalance;

      let balanceHtml;
      if (!cs.ok) balanceHtml = '<span class="acct__err">잔액을 불러오지 못했어요</span>';
      else if (hideBal) balanceHtml = '<span class="acct__hidden">잔액 숨김</span>';
      else balanceHtml = Number(cs.data.balance).toLocaleString('ko-KR') + '<small>원</small>';

      const resumeMap = {
        PLAN_READY: ['진행 중인 해결 계획이 있어요', '남은 절차를 이어서 진행해 주세요'],
        WAITING_USER: ['해결 절차를 진행하던 중이에요', '돌아가면 은행 상태를 다시 확인해요'],
        READY_TO_RETRY: ['이체 준비가 끝났어요', '원래 이체를 확인하고 직접 승인해 주세요'],
        VERIFYING: ['이체 결과를 확인하고 있어요', '결과가 확정될 때까지 다시 보내지 마세요'],
        ESCALATED: ['상담 확인이 필요한 건이 있어요', '확인된 내용을 볼 수 있어요'],
        RESULT_UNCERTAIN: ['결과 확인이 필요한 이체가 있어요', '결과가 확정될 때까지 다시 보내지 마세요'],
      };
      const hasCase = !!resumeMap[st];

      const notices = [];
      if (hasCase) notices.push({ action: 'open-pass', isCase: true, title: resumeMap[st][0], desc: resumeMap[st][1] });
      if (!s.hideNotice) {
        notices.push({ action: 'go-chat', title: '이체가 막혔다면 AI챗봇에게', desc: '해결패스가 막힌 이유부터 확인해요' });
        notices.push({ action: 'noop', title: '시연용 가상 데이터예요', desc: '실제 은행·계좌와 연결되어 있지 않아요' });
      }
      const noticeHtml = notices.length
        ? '<div class="home-notice"><div class="home-notice__track" data-carousel>' +
          notices
            .map(
              (n) =>
                '<div class="home-notice__item' +
                (n.isCase ? ' is-case' : '') +
                '"><button class="home-notice__main" data-action="' +
                n.action +
                '"><span class="home-notice__icon">' +
                (n.isCase ? I.spark : I.bell) +
                '</span><span class="home-notice__text"><strong>' +
                esc(n.title) +
                '</strong><span>' +
                esc(n.desc) +
                '</span></span>' +
                (n.isCase ? '<span class="home-notice__go">' + I.chevron + '</span>' : '') +
                '</button>' +
                (n.isCase ? '' : '<button class="home-notice__close" data-action="notice-close" aria-label="알림 닫기">' + I.x + '</button>') +
                '</div>'
            )
            .join('') +
          '</div>' +
          dotsHtml(notices.length) +
          '</div>'
        : '';

      const iconBtn = (icon, label) => '<button class="icon-btn" data-action="noop" aria-label="' + label + '">' + icon + '</button>';

      return (
        '<div class="home-top">' +
        '<div class="home-mode"><button class="is-on" data-action="noop">일반홈</button><button data-action="noop">쉬운</button></div>' +
        '<div class="home-top__actions">' +
        iconBtn(I.wallet, '지갑') +
        '<button class="icon-btn ai-btn' +
        (hasCase ? ' has-dot' : '') +
        '" data-action="go-chat" aria-label="AI챗봇 해결패스">' +
        I.ai +
        '</button>' +
        iconBtn(I.bell, '알림') +
        iconBtn(I.menu, '전체 메뉴') +
        '<span class="ai-tip">AI챗봇 해결패스</span>' +
        '</div></div>' +
        '<div class="screen-body home-body">' +
        noticeHtml +
        '<div class="home-hero">' +
        HOME_ART +
        '<div class="home-hero__bar"><button class="pill-btn" data-action="noop">' +
        I.gear +
        '홈계좌설정</button><button class="toggle-pill' +
        (hideBal ? ' is-on' : '') +
        '" data-action="toggle-balance" role="switch" aria-checked="' +
        hideBal +
        '">잔액숨김<span class="toggle-pill__track"><span class="toggle-pill__knob"></span></span></button></div></div>' +
        (cs.ok ? '' : notice('일시적으로 은행 시스템에 연결할 수 없어요. 잠시 후 다시 시도해 주세요.', 'warning', I.alert)) +
        '<div class="acct" data-action="account-detail" role="button" tabindex="0">' +
        '<div class="acct__head"><span class="acct__logo">' +
        I.wallet +
        '</span><div class="acct__info"><div class="acct__name">' +
        esc(cs.ok ? cs.data.accountName : '우리 주거래 통장') +
        '</div><div class="acct__num">우리 ' +
        esc(cs.ok ? cs.data.accountNumber : '1002-***-******') +
        '<button class="acct__copy" data-action="noop" aria-label="계좌번호 복사">' +
        I.copy +
        '</button></div></div><button class="acct__more" data-action="noop" aria-label="계좌 메뉴">' +
        I.more +
        '</button></div>' +
        '<div class="acct__tags"><span class="tag">가상 계좌</span></div>' +
        '<div class="acct__foot"><div class="acct__bal">' +
        balanceHtml +
        '</div><button class="acct__btn" data-action="go-transfer">이체</button></div></div>' +
        '<button class="home-all" data-action="account-detail">전체계좌보기</button>' +
        '<button class="promo" data-action="go-chat"><span class="promo__text"><strong>막힌 업무, 이유부터 확인해요</strong><span>AI챗봇 해결패스가 은행 상태를 보고<br>필요한 절차만 순서대로 안내해요</span></span><span class="promo__art">' +
        I.robot +
        '</span></button>' +
        '<p class="fineprint">본 앱 화면은 경진대회 시연용 프로토타입입니다. 실제 은행과 연결되어 있지 않으며 모든 계좌·금액·거래는 가상 데이터입니다.</p>' +
        '</div>' +
        '<nav class="bottom-nav">' +
        '<button class="bottom-nav__item" data-action="noop">' +
        I.product +
        '상품</button>' +
        '<button class="bottom-nav__item" data-action="noop">' +
        I.pie +
        '자산·소비</button>' +
        '<button class="bottom-nav__item is-active" data-action="go-home">' +
        I.homeFill +
        '홈</button>' +
        '<button class="bottom-nav__item" data-action="noop">' +
        I.stock +
        '주식</button>' +
        '<button class="bottom-nav__item" data-action="noop">' +
        I.gift +
        '혜택</button>' +
        '</nav>'
      );
    },
    mount(el) {
      bindCarousels(el);
    },
  };

  /* ---------- Transfer ---------- */
  SCREENS.transfer = {
    title: '이체',
    white: true,
    async render(params) {
      const a = app();
      const s = a.session;
      const res = await Promise.all([bank.getTransferDraft(), bank.getCustomerState()]);
      const dr = res[0];
      const cs = res[1];
      if (dr.ok) s.lastDraft = dr.data.draft;
      const draft = dr.ok ? dr.data.draft : s.lastDraft || WSP.initialBankState.transfer;
      const tx = dr.ok ? dr.data.transaction : null;
      const st = a.fsm.state;
      const returned = (params && params.returned) || (s.returnedFromPass && st === 'READY_TO_RETRY');
      const editable = (st === 'IDLE' || st === 'COMPLETED') && ['PENDING', 'UNKNOWN', 'SUCCESS'].indexOf(draft.status) === -1;
      const unresolved = tx && (tx.status === 'PENDING' || tx.status === 'UNKNOWN');
      const done = tx && tx.status === 'SUCCESS';

      let top = '';
      if (!dr.ok) top += notice('일시적으로 은행 시스템에 연결할 수 없어요. 잠시 후 다시 시도해 주세요.', 'warning', I.alert);
      if (returned && !done && !unresolved) {
        top += notice(
          '<strong>WON 해결패스에서 돌아왔어요.</strong><br>확인한 이체 정보를 그대로 유지했어요. 받는 분과 금액을 확인한 뒤 직접 이체해 주세요. 자동으로 이체되지 않아요.',
          'success',
          I.shield
        );
      }
      if (unresolved) {
        top += notice(
          '<strong>이전 이체 요청의 결과가 확정되지 않았어요.</strong><br>중복 출금을 막기 위해 새로 이체하지 말고 결과를 먼저 조회해 주세요.',
          'warning',
          I.clock
        );
      }
      if (done) top += notice('이 이체는 은행 처리 결과 <strong>성공</strong>으로 확인되었어요. (' + esc(tx.id) + ')', 'success', I.check);

      const balance = cs.ok ? fmt(cs.data.balance) : '확인 불가';

      let footer;
      if (unresolved) footer = '<button class="btn btn--primary btn--lg btn--block" data-action="open-result">거래 결과 조회</button>';
      else if (done) footer = '<button class="btn btn--secondary btn--lg btn--block" data-action="open-result">결과 보기</button>';
      else footer = '<button class="btn btn--primary btn--lg btn--block" data-action="transfer-submit" id="transfer-submit">이체하기</button>';

      const chips = editable
        ? '<div class="chip-row mt-12">' +
          [
            ['+1만', 10000],
            ['+10만', 100000],
            ['+50만', 500000],
            ['+100만', 1000000],
          ]
            .map((c) => '<button class="chip" data-action="amount-add" data-v="' + c[1] + '">' + c[0] + '</button>')
            .join('') +
          '<button class="chip" data-action="amount-clear">정정</button></div>'
        : '';

      return (
        appbar('이체') +
        '<div class="screen-body">' +
        top +
        (top ? '<div class="mt-12"></div>' : '') +
        '<div class="card card--outline">' +
        '<div class="field"><div class="field__label">출금 계좌</div><div class="field__value">' +
        esc(cs.ok ? cs.data.accountName : '우리 주거래 통장') +
        '</div><div class="field__sub">우리은행 ' +
        esc(draft.fromAccount) +
        ' · 출금가능 ' +
        balance +
        '</div></div>' +
        '<div class="field"><div class="field__label">받는 분</div><div class="field__value"><span class="avatar">' +
        esc(draft.recipient.charAt(0)) +
        '</span><span>' +
        esc(draft.recipient) +
        '<div class="field__sub" style="font-weight:500">' +
        esc(draft.recipientBank) +
        ' ' +
        esc(draft.recipientAccount) +
        '</div></span></div></div>' +
        '</div>' +
        '<div class="card card--outline mt-12"><div class="field__label">보낼 금액</div>' +
        '<label class="amount-input' +
        (editable ? '' : ' is-locked') +
        '"><input id="amount-input" data-input="amount" inputmode="numeric" autocomplete="off" aria-label="보낼 금액" value="' +
        Number(draft.amount).toLocaleString('ko-KR') +
        '"' +
        (editable ? '' : ' disabled') +
        ' /><span>원</span></label>' +
        '<div class="amount-hint" id="amount-hint">' +
        man(draft.amount) +
        (editable ? '' : ' · 해결패스에서 확인한 금액을 유지하고 있어요') +
        '</div>' +
        chips +
        '</div>' +
        '<p class="fineprint">가상 계좌·가상 금액이며 실제 거래는 발생하지 않습니다. 이체 버튼을 누르면 은행이 현재 상태를 먼저 검사합니다.</p>' +
        '</div>' +
        '<div class="screen-footer">' +
        footer +
        '</div>'
      );
    },
  };

  /* ---------- Solution plan ---------- */
  function countWord(n) {
    return WSP.chatbot.countWord(n);
  }

  function stepCard(item, idx) {
    const a = PF.getAction(item.actionId);
    const d = PF.describeStep(item.actionId, item.ctx);
    const cls = item.mode === 'done' ? 'is-done' : item.mode === 'current' ? 'is-current' : 'is-locked';
    const num = item.mode === 'done' ? I.check : String(idx + 1);
    let statusBadge;
    if (item.mode === 'done') statusBadge = badge('완료', 'success');
    else if (item.mode === 'current') statusBadge = badge('지금 할 일', 'info');
    else statusBadge = badge('대기', 'neutral');

    let body = '';
    if (item.mode === 'current') {
      const btn =
        item.actionId === 'RETURN_TO_TRANSFER'
          ? '<button class="btn btn--primary btn--block" data-action="return-to-transfer">' + esc(a.cta) + '</button>'
          : '<button class="btn btn--primary btn--block" data-action="open-flow" data-flow="' + a.flowId + '">' + esc(a.cta) + '</button>';
      body =
        '<div class="step__body"><dl class="step__grid">' +
        '<dt>해결할 문제</dt><dd>' +
        esc(d.problem) +
        '</dd><dt>현재 상태</dt><dd>' +
        esc(d.current) +
        '</dd><dt>필요한 행동</dt><dd>' +
        esc(d.action) +
        '</dd><dt>예상 결과</dt><dd>' +
        esc(d.expected) +
        '</dd></dl>' +
        btn +
        (d.ruleIds.length ? '<div class="step__note mt-8">근거 규칙 ' + d.ruleIds.join(' · ') + ' (데모용 가상 정책)</div>' : '') +
        '</div>';
    } else if (item.mode === 'done') {
      body = '<div class="step__body"><div class="step__note">' + esc(d.current) + ' · 은행 상태 재조회로 확인됨 (상태 v' + item.ctx.stateVersion + ')</div></div>';
    } else {
      body = '<div class="step__body"><div class="step__note">' + esc(item.lockReason || '이전 단계를 마치면 진행할 수 있어요.') + '</div></div>';
    }
    return (
      '<div class="step ' +
      cls +
      '" style="animation-delay:' +
      idx * 60 +
      'ms"><div class="step__head"><span class="step__num">' +
      num +
      '</span><span class="step__title">' +
      esc(a.label) +
      '</span>' +
      statusBadge +
      '</div>' +
      body +
      '</div>'
    );
  }

  SCREENS.plan = {
    title: 'WON 해결패스',
    async render(params) {
      const a = app();
      const s = a.session;
      const plan = s.plan;
      const right = '<button class="icon-btn" data-action="plan-recheck" aria-label="상태 다시 확인">' + I.refresh + '</button>';

      if (!plan || !s.caseCtx) {
        return (
          appbar('WON 해결패스') +
          '<div class="screen-body"><div class="result"><div class="result__icon result__icon--neutral">' +
          I.spark +
          '</div><h2 class="result__title">진행 중인 해결 계획이 없어요</h2><p class="result__desc">현재 이체 요청과 은행 상태를 확인해 필요한 절차가 있는지 알려드릴게요.</p></div></div>' +
          '<div class="screen-footer"><button class="btn btn--primary btn--lg btn--block" data-action="open-pass">현재 상태 확인하기</button></div>'
        );
      }

      const ev = plan.evaluation;
      const ctx = ev.ctx;
      const caseCtx = s.caseCtx;
      const currentIds = plan.actionSteps.map((x) => x.actionId);

      const doneIds = (caseCtx.timeline || []).filter((id) => {
        const act = PF.getAction(id);
        return currentIds.indexOf(id) === -1 && act && act.resolves && ev.facts[act.resolves] === true;
      });

      const items = [];
      doneIds.forEach((id) => items.push({ actionId: id, mode: 'done', ctx: ctx }));
      plan.actionSteps.forEach((st, i) => {
        let lockReason = '';
        if (i > 0) lockReason = PF.getAction(plan.actionSteps[i - 1].actionId).label + '을 마친 뒤 진행할 수 있어요. (사전 조건)';
        items.push({ actionId: st.actionId, mode: i === 0 ? 'current' : 'locked', ctx: ctx, lockReason: lockReason });
      });
      items.push({
        actionId: 'RETURN_TO_TRANSFER',
        mode: plan.status === 'READY' ? 'current' : 'locked',
        ctx: ctx,
        lockReason: '모든 사전 조건이 확인되면 원래 이체로 돌아갈 수 있어요.',
      });

      const n = plan.actionSteps.length;
      let heroTitle;
      let heroCls = '';
      let heroEyebrow = '해결 계획';
      if (plan.status === 'READY') {
        heroCls = ' is-ready';
        heroEyebrow = '사전 조건 확인 완료';
        heroTitle = doneIds.length
          ? '이체 사전 조건을 모두 확인했어요.<br>원래 이체로 돌아가 직접 승인해 주세요.'
          : '추가 절차 없이 이체할 수 있어요.<br>원래 이체에서 직접 승인해 주세요.';
      } else if (doneIds.length) {
        heroTitle = man(ctx.amount) + ' 이체까지<br>남은 설정은 ' + countWord(n) + ' 가지예요.';
      } else {
        heroTitle = man(ctx.amount) + ' 이체를 진행하려면<br>다음 ' + countWord(n) + ' 가지 설정이 필요합니다.';
      }

      const pills = ev.requirements.map((r) => '<span class="plan-hero__pill">' + esc(r.title) + '</span>').join('');

      const recheckBar = params && params.rechecking ? '<div class="recheck-bar" id="recheck-bar"><span class="spinner"></span>변경된 상태를 은행에서 다시 확인하고 있어요</div>' : '';

      const checkedAt = ctx.checkedAt ? new Date(ctx.checkedAt).toLocaleTimeString('ko-KR', { hour12: false }) : '-';

      return (
        appbar('WON 해결패스', { right: right }) +
        '<div class="screen-body">' +
        '<div class="plan-hero' +
        heroCls +
        '"><div class="plan-hero__eyebrow">' +
        I.spark.replace('<svg', '<svg width="14" height="14"') +
        heroEyebrow +
        '</div><h2 class="plan-hero__title">' +
        heroTitle +
        '</h2>' +
        (pills ? '<div class="plan-hero__req">' + pills + '</div>' : '') +
        '</div>' +
        recheckBar +
        '<div class="card request-summary"><span class="avatar">' +
        esc((ctx.recipient || '?').charAt(0)) +
        '</span><div class="request-summary__text"><strong>' +
        esc(ctx.recipient) +
        '님에게 ' +
        fmt(ctx.amount) +
        '</strong>' +
        esc(ctx.recipientBank) +
        ' · 원래 이체 정보는 그대로 유지돼요</div></div>' +
        '<div class="steps">' +
        items.map((it, i) => stepCard(it, i)).join('') +
        '</div>' +
        '<div class="mt-16">' +
        notice('AI는 OTP 번호나 비밀번호를 묻지 않아요. 인증과 이체 승인은 은행 화면에서 직접 진행해요.', '', I.lock) +
        '</div>' +
        '<div class="plan-meta">근거 규칙 ' +
        (ev.firedRules.length ? ev.firedRules.map((r) => '<code>' + r + '</code>').join(' ') : '<code>없음</code>') +
        '<br>정책 <code>' +
        esc(ev.policyVersion) +
        '</code> 데모용 가상 정책 · 실제 은행 정책 아님<br>상태 버전 <code>v' +
        ctx.stateVersion +
        '</code> · ' +
        checkedAt +
        ' 조회 · 상태 그래프 ' +
        plan.visited +
        '개 상태' +
        (plan.cost != null ? ' · 최소 비용 경로 ' + plan.cost : '') +
        '<br>사건 번호 <code>' +
        esc(caseCtx.caseId) +
        '</code></div>' +
        '<div class="text-center mt-12"><button class="link-btn" data-action="go-chat">궁금한 점이 있나요? 질문하기</button></div>' +
        '</div>'
      );
    },
    onBack() {
      app().goHome();
      return true;
    },
  };

  /* ---------- OTP registration ---------- */
  SCREENS.otp = {
    title: '디지털 OTP',
    white: true,
    async render(params) {
      const p = params || {};
      const a = app();
      const waiting = a.fsm.state === 'WAITING_USER';
      if (p.phase === 'processing') {
        return (
          appbar('디지털 OTP 등록', { noBack: true }) +
          '<div class="screen-body"><div class="flow-hero"><div class="flow-hero__icon">' +
          I.phone +
          '</div><h2 class="flow-hero__title">디지털 OTP를 등록하고 있어요</h2><p class="flow-hero__desc">잠시만 기다려 주세요.</p></div>' +
          '<div class="card card--outline mt-16"><div class="flow-progress" id="flow-progress">' +
          ['이 기기 정보 확인', '보안 매체 등록 요청', '은행 등록 결과 확인']
            .map((t, i) => '<div class="flow-progress__row" data-step="' + i + '"><span class="dot"><span class="spinner"></span></span>' + t + '</div>')
            .join('') +
          '</div></div>' +
          '<p class="fineprint">시뮬레이션: 실제 OTP 번호, 인증 비밀번호, 신분증 정보는 요구하지 않습니다.</p></div>'
        );
      }
      if (p.phase === 'done') {
        return (
          appbar('디지털 OTP 등록', { noBack: true }) +
          '<div class="screen-body"><div class="result"><div class="result__icon result__icon--success">' +
          I.check +
          '</div><h2 class="result__title">디지털 OTP 등록이 완료되었어요</h2><p class="result__desc">은행 상태에 반영되었어요. (상태 v' +
          esc(p.stateVersion) +
          ')</p></div>' +
          (waiting ? notice('해결패스로 돌아가면 은행 상태를 다시 조회하고 남은 경로를 다시 계산해요.', 'info', I.spark) : '') +
          '</div><div class="screen-footer">' +
          (waiting
            ? '<button class="btn btn--primary btn--lg btn--block" data-action="flow-return">해결패스로 돌아가기</button>'
            : '<button class="btn btn--primary btn--lg btn--block" data-action="back">확인</button>') +
          '</div>'
        );
      }

      const res = await Promise.all([bank.getOtpStatus(), bank.checkOtpEligibility()]);
      const failed = res.find((r) => !r.ok);
      if (failed) return queryErrorCard('디지털 OTP', failed.error);
      const registered = res[0].data.registered;
      const elig = res[1].data;

      let footer;
      if (registered) footer = '<button class="btn btn--secondary btn--lg btn--block" data-action="back">확인</button>';
      else if (elig.eligible) footer = '<button class="btn btn--primary btn--lg btn--block" data-action="otp-register">디지털 OTP 등록 진행</button>';
      else footer = '<button class="btn btn--primary btn--lg btn--block" disabled>등록할 수 없어요</button>';

      return (
        appbar('디지털 OTP') +
        '<div class="screen-body">' +
        passLinkedNotice('REGISTER_OTP') +
        '<div class="flow-hero"><div class="flow-hero__icon">' +
        I.key +
        '</div><h2 class="flow-hero__title">디지털 OTP</h2><p class="flow-hero__desc">이 휴대폰을 OTP 기기로 등록해<br>고액 이체 등의 보안 인증에 사용해요.</p></div>' +
        '<div class="card card--outline mt-12">' +
        kvRows([
          ['현재 등록 상태', registered ? badge('등록됨', 'success') : badge('미등록', 'warning')],
          ['등록 가능 여부', registered ? badge('이미 등록됨', 'neutral') : elig.eligible ? badge('가능', 'success') : badge('불가', 'danger')],
        ]) +
        '</div>' +
        (!registered && !elig.eligible ? '<div class="mt-12">' + notice(esc(elig.message), 'warning', I.alert) + '</div>' : '') +
        (p.error ? '<div class="mt-12">' + notice(esc(p.error), 'danger', I.alert) + '</div>' : '') +
        '<div class="mt-12">' +
        notice('시뮬레이션 화면이에요. 실제 OTP 번호, 인증 비밀번호, 신분증 정보는 요구하지 않습니다.', '', I.info) +
        '</div>' +
        '</div><div class="screen-footer">' +
        footer +
        '</div>'
      );
    },
    onBack() {
      return app().leaveFlow();
    },
  };

  /* ---------- Transfer limit ---------- */
  SCREENS.limit = {
    title: '이체한도 관리',
    white: true,
    async render(params) {
      const p = params || {};
      const a = app();
      const waiting = a.fsm.state === 'WAITING_USER';
      if (p.phase === 'done') {
        return (
          appbar('이체한도 관리', { noBack: true }) +
          '<div class="screen-body"><div class="result"><div class="result__icon result__icon--success">' +
          I.check +
          '</div><h2 class="result__title">1일 이체한도가 변경되었어요</h2><div class="result__amount">' +
          fmt(p.newLimit) +
          '</div><p class="result__desc">이전 한도 ' +
          fmt(p.previousLimit) +
          ' · 은행 상태에 반영됨 (상태 v' +
          esc(p.stateVersion) +
          ')</p></div>' +
          (waiting ? notice('해결패스로 돌아가면 은행 상태를 다시 조회하고 남은 경로를 다시 계산해요.', 'info', I.spark) : '') +
          '</div><div class="screen-footer">' +
          (waiting
            ? '<button class="btn btn--primary btn--lg btn--block" data-action="flow-return">해결패스로 돌아가기</button>'
            : '<button class="btn btn--primary btn--lg btn--block" data-action="back">확인</button>') +
          '</div>'
        );
      }

      const res = await Promise.all([bank.getTransferLimit(), bank.getOtpStatus(), bank.getTransferDraft()]);
      const failed = res.find((r) => !r.ok);
      if (failed) return queryErrorCard('이체한도 관리', failed.error);
      const lim = res[0].data;
      const otp = res[1].data.registered;
      const draftAmount = res[2].data.draft.amount;

      const recommended = Math.max(draftAmount, P.minTransferLimit);
      const options = [recommended, 2000000, 3000000, 5000000]
        .filter((v, i, arr) => arr.indexOf(v) === i && v > lim.transferLimit)
        .sort((x, y) => x - y)
        .slice(0, 4);
      const selected = p.selected != null ? p.selected : options.length ? options[0] : lim.transferLimit;
      a.session.limitSelection = selected;

      const chips = options
        .map(
          (v) =>
            '<button class="chip' +
            (v === selected ? ' is-selected' : '') +
            '" data-action="limit-select" data-v="' +
            v +
            '">' +
            man(v) +
            (v === recommended && draftAmount > lim.transferLimit ? '<span class="chip__tag">이체 금액 기준</span>' : '') +
            '</button>'
        )
        .join('');

      let checkHtml = '';
      if (p.check) {
        if (p.check.allowed) {
          checkHtml = notice('<strong>' + fmt(p.check.value) + '</strong>로 변경할 수 있어요. 아래 버튼을 눌러 변경을 확정해 주세요.', 'success', I.check);
        } else {
          checkHtml = notice(
            '<strong>' + fmt(p.check.value) + '</strong>로 변경할 수 없어요.<br>' + p.check.reasons.map((r) => '· ' + esc(r.message)).join('<br>'),
            'danger',
            I.alert
          );
        }
        checkHtml = '<div class="limit-check">' + checkHtml + '</div>';
      }

      const canApply = p.check && p.check.allowed && p.check.value === selected;
      const footer = canApply
        ? '<button class="btn btn--primary btn--lg btn--block" data-action="limit-apply" data-v="' + selected + '">이 한도로 변경</button>'
        : '<button class="btn btn--primary btn--lg btn--block" data-action="limit-check">변경 가능 여부 확인</button>';

      return (
        appbar('이체한도 관리') +
        '<div class="screen-body">' +
        passLinkedNotice('CHANGE_TRANSFER_LIMIT') +
        '<div class="card card--outline mt-12">' +
        kvRows([
          ['현재 1일 이체한도', fmt(lim.transferLimit)],
          ['디지털 OTP', otp ? badge('등록됨', 'success') : badge('미등록', 'warning')],
          ['비대면 한도 변경', lim.changeAllowed ? badge('가능', 'success') : badge('불가', 'danger')],
        ]) +
        '</div>' +
        '<div class="section"><div class="section-title">변경할 한도</div><div class="chip-row">' +
        (chips || '<span class="text-muted" style="font-size:13px">선택 가능한 추천 한도가 없어요</span>') +
        '</div>' +
        '<div class="mt-12"><input class="text-input" id="limit-custom" data-input="limit-custom" inputmode="numeric" placeholder="직접 입력 (원)" value="' +
        (p.custom ? Number(p.custom).toLocaleString('ko-KR') : '') +
        '" aria-label="변경할 한도 직접 입력" /></div></div>' +
        checkHtml +
        '<p class="fineprint">데모용 가상 정책: ' +
        fmt(P.maxLimitWithoutOtp) +
        '를 초과하는 한도는 디지털 OTP 등록 후 변경할 수 있어요. 실제 우리은행 정책이 아닙니다. 변경 가능 여부는 가상 은행이 판정합니다.</p>' +
        '</div><div class="screen-footer">' +
        footer +
        '</div>'
      );
    },
    onBack() {
      return app().leaveFlow();
    },
  };

  /* ---------- KYC ---------- */
  SCREENS.kyc = {
    title: '고객확인',
    white: true,
    async render(params) {
      const p = params || {};
      const a = app();
      const waiting = a.fsm.state === 'WAITING_USER';
      if (p.phase === 'processing') {
        return (
          appbar('고객확인', { noBack: true }) +
          '<div class="screen-body"><div class="flow-hero"><div class="flow-hero__icon">' +
          I.idcard +
          '</div><h2 class="flow-hero__title">고객확인을 진행하고 있어요</h2><p class="flow-hero__desc">잠시만 기다려 주세요.</p></div>' +
          '<div class="card card--outline mt-16"><div class="flow-progress" id="flow-progress">' +
          ['보유 정보 확인', '고객확인 처리 요청', '은행 처리 결과 확인']
            .map((t, i) => '<div class="flow-progress__row" data-step="' + i + '"><span class="dot"><span class="spinner"></span></span>' + t + '</div>')
            .join('') +
          '</div></div><p class="fineprint">시뮬레이션: 신분증 촬영 등 실제 개인정보는 요구하지 않습니다.</p></div>'
        );
      }
      if (p.phase === 'done') {
        return (
          appbar('고객확인', { noBack: true }) +
          '<div class="screen-body"><div class="result"><div class="result__icon result__icon--success">' +
          I.check +
          '</div><h2 class="result__title">고객확인이 완료되었어요</h2><p class="result__desc">은행 상태에 반영되었어요. (상태 v' +
          esc(p.stateVersion) +
          ')</p></div>' +
          (waiting ? notice('해결패스로 돌아가면 은행 상태를 다시 조회하고 남은 경로를 다시 계산해요.', 'info', I.spark) : '') +
          '</div><div class="screen-footer">' +
          (waiting
            ? '<button class="btn btn--primary btn--lg btn--block" data-action="flow-return">해결패스로 돌아가기</button>'
            : '<button class="btn btn--primary btn--lg btn--block" data-action="back">확인</button>') +
          '</div>'
        );
      }
      const res = await Promise.all([bank.getKycStatus(), bank.getCustomerState()]);
      const failed = res.find((r) => !r.ok);
      if (failed) return queryErrorCard('고객확인', failed.error);
      const completed = res[0].data.completed;
      const restricted = res[1].data.accountRestricted;
      let footer;
      if (completed) footer = '<button class="btn btn--secondary btn--lg btn--block" data-action="back">확인</button>';
      else if (restricted) footer = '<button class="btn btn--primary btn--lg btn--block" disabled>진행할 수 없어요</button>';
      else footer = '<button class="btn btn--primary btn--lg btn--block" data-action="kyc-complete">고객확인 진행</button>';
      return (
        appbar('고객확인') +
        '<div class="screen-body">' +
        passLinkedNotice('COMPLETE_KYC') +
        '<div class="flow-hero"><div class="flow-hero__icon">' +
        I.idcard +
        '</div><h2 class="flow-hero__title">고객확인</h2><p class="flow-hero__desc">안전한 금융거래를 위해<br>고객 정보를 확인하는 절차예요.</p></div>' +
        '<div class="card card--outline mt-12">' +
        kvRows([['고객확인 상태', completed ? badge('완료', 'success') : badge('미완료', 'warning')]]) +
        '</div>' +
        (restricted && !completed ? '<div class="mt-12">' + notice('계좌 이용 제한 상태에서는 진행할 수 없어요. 상담 창구에서 확인해 주세요.', 'danger', I.lock) + '</div>' : '') +
        (p.error ? '<div class="mt-12">' + notice(esc(p.error), 'danger', I.alert) + '</div>' : '') +
        '<div class="mt-12">' +
        notice('시뮬레이션 화면이에요. 신분증, 주민등록번호 등 실제 개인정보는 요구하지 않습니다.', '', I.info) +
        '</div></div><div class="screen-footer">' +
        footer +
        '</div>'
      );
    },
    onBack() {
      return app().leaveFlow();
    },
  };

  /* ---------- Transfer result ---------- */
  function verifyItem(text, sub, state) {
    const icon = state === 'pending' ? I.clock : state === 'fail' ? I.x : I.check;
    const cls = state === 'pending' ? ' is-pending' : state === 'fail' ? ' is-fail' : '';
    return (
      '<div class="verify-item"><span class="verify-item__icon' +
      cls +
      '">' +
      icon +
      '</span><span class="verify-item__text">' +
      esc(text) +
      (sub ? '<small>' + esc(sub) + '</small>' : '') +
      '</span></div>'
    );
  }

  SCREENS.result = {
    title: '처리 결과',
    white: true,
    async render(params) {
      const p = params || {};
      const a = app();
      const s = a.session;

      if (p.processing) {
        return (
          appbar('처리 결과', { noBack: true }) +
          '<div class="screen-body"><div class="result"><div class="result__icon result__icon--neutral"><span class="spinner" style="width:34px;height:34px;border-width:3.5px"></span></div><h2 class="result__title">이체 요청을 처리하고 있어요</h2><p class="result__desc">은행 처리 결과를 확인한 뒤 알려드릴게요.<br>화면을 닫거나 다시 이체하지 마세요.</p></div></div>'
        );
      }

      if (p.notSent) {
        return (
          appbar('처리 결과', { noBack: true }) +
          '<div class="screen-body"><div class="result"><div class="result__icon result__icon--neutral">' +
          I.alert +
          '</div><h2 class="result__title">이체 요청이 전송되지 않았어요</h2><p class="result__desc">' +
          esc(p.message || '') +
          '<br>출금되지 않았어요.</p></div></div>' +
          '<div class="screen-footer"><div class="btn-row"><button class="btn btn--ghost" data-action="go-home">홈으로</button><button class="btn btn--primary" data-action="diagnose">상태 다시 확인</button></div></div>'
        );
      }

      const id = p.transactionId || (s.resultCtx && s.resultCtx.transactionId);
      if (!id) {
        return (
          appbar('처리 결과') +
          '<div class="screen-body"><div class="result"><div class="result__icon result__icon--neutral">' +
          I.info +
          '</div><h2 class="result__title">확인할 이체 결과가 없어요</h2></div></div><div class="screen-footer"><button class="btn btn--primary btn--lg btn--block" data-action="go-home">홈으로</button></div>'
        );
      }

      const r = await bank.getTransferResult(id);
      if (!r.ok) {
        return (
          appbar('처리 결과') +
          '<div class="screen-body"><div class="result"><div class="result__icon result__icon--neutral">' +
          I.question +
          '</div><h2 class="result__title">지금은 결과를 조회할 수 없어요</h2><p class="result__desc">' +
          esc(r.error.message) +
          '<br>결과가 확인되기 전에는 완료로 표시하지 않아요.<br>다시 이체하지 말고 잠시 후 조회해 주세요.</p></div></div>' +
          '<div class="screen-footer"><div class="btn-row"><button class="btn btn--ghost" data-action="go-home">홈으로</button><button class="btn btn--primary" data-action="query-result">결과 다시 조회</button></div></div>'
        );
      }

      const tx = r.data.transaction;
      const viaPass = !!(s.resultCtx && s.resultCtx.viaPass && s.resultCtx.transactionId === tx.id);
      const completedPass = viaPass && a.fsm.state === 'COMPLETED';
      const timeline = (s.caseCtx && s.caseCtx.timeline) || [];
      const dup = p.duplicate ? notice('같은 요청이 이미 접수되어 있어 새 거래를 만들지 않고 기존 결과를 보여드려요.', 'info', I.shield) : '';

      if (tx.status === 'SUCCESS') {
        const checks = [];
        if (viaPass) {
          if (timeline.indexOf('COMPLETE_KYC') !== -1) checks.push(verifyItem('고객확인 · 은행 상태 확인', '', 'ok'));
          if (timeline.indexOf('REGISTER_OTP') !== -1) checks.push(verifyItem('디지털 OTP · 은행 등록 상태 확인', '', 'ok'));
          if (timeline.indexOf('CHANGE_TRANSFER_LIMIT') !== -1) checks.push(verifyItem('이체한도 · 은행 상태 확인', '', 'ok'));
        }
        checks.push(verifyItem('이체 · 은행 성공 응답 확인', '거래 확인번호 ' + tx.id, 'ok'));
        return (
          appbar('처리 결과', { noBack: true }) +
          '<div class="screen-body"><div class="result"><div class="result__icon result__icon--success">' +
          I.check +
          '</div><h2 class="result__title">이체 완료를 확인했어요</h2><div class="result__amount">' +
          fmt(tx.amount) +
          '</div><p class="result__desc">' +
          esc(tx.recipient) +
          '님(' +
          esc(tx.recipientBank) +
          ')에게 보냈어요</p>' +
          (completedPass ? '<div class="mt-12">' + badge('WON 해결패스 해결 완료', 'success') + '</div>' : '') +
          '</div>' +
          dup +
          '<div class="card card--outline mt-16"><div class="verify-list">' +
          checks.join('') +
          '</div></div>' +
          '<p class="fineprint">완료 표시는 가상 은행이 반환한 성공(SUCCESS) 응답을 확인한 뒤에만 보여드려요. 실제 거래가 아닌 시연용 결과입니다.</p>' +
          '</div><div class="screen-footer"><button class="btn btn--primary btn--lg btn--block" data-action="go-home">홈으로</button></div>'
        );
      }

      if (tx.status === 'PENDING') {
        return (
          appbar('처리 결과', { noBack: true }) +
          '<div class="screen-body"><div class="result"><div class="result__icon result__icon--warning">' +
          I.clock +
          '</div><h2 class="result__title">이체를 처리하고 있어요</h2><div class="result__amount">' +
          fmt(tx.amount) +
          '</div><p class="result__desc">은행 처리 결과가 아직 확정되지 않았어요.<br>중복 출금을 막기 위해 다시 이체하지 마세요.</p></div>' +
          dup +
          '<div class="card card--outline mt-16"><div class="verify-list">' +
          verifyItem('이체 요청 접수', '거래 확인번호 ' + tx.id, 'ok') +
          verifyItem('은행 처리 결과', '확인 중 · 완료로 표시하지 않아요', 'pending') +
          '</div></div></div>' +
          '<div class="screen-footer"><div class="btn-row"><button class="btn btn--ghost" data-action="go-home">홈으로</button><button class="btn btn--primary" data-action="query-result">결과 조회</button></div></div>'
        );
      }

      if (tx.status === 'UNKNOWN') {
        return (
          appbar('처리 결과', { noBack: true }) +
          '<div class="screen-body"><div class="result"><div class="result__icon result__icon--warning">' +
          I.question +
          '</div><h2 class="result__title">이체 결과를 확인하지 못했어요</h2><div class="result__amount">' +
          fmt(tx.amount) +
          '</div><p class="result__desc">성공 여부가 확정되지 않아 완료로 표시하지 않아요.<br>자동으로 다시 보내지 않아요.</p></div>' +
          dup +
          '<div class="card card--outline mt-16"><div class="verify-list">' +
          verifyItem('이체 요청 접수', '거래 확인번호 ' + tx.id, 'ok') +
          verifyItem('은행 처리 결과', '결과 불명 · 재이체 금지', 'pending') +
          '</div></div>' +
          '<div class="mt-12">' +
          notice('같은 이체를 다시 시도하면 중복 출금이 생길 수 있어요. 결과를 조회하거나 상담을 이용해 주세요.', 'warning', I.alert) +
          '</div></div>' +
          '<div class="screen-footer"><div class="btn-row"><button class="btn btn--ghost" data-action="go-support" data-code="TRANSFER_UNKNOWN">상담 연결</button><button class="btn btn--primary" data-action="query-result">결과 조회</button></div></div>'
        );
      }

      // FAILED
      return (
        appbar('처리 결과', { noBack: true }) +
        '<div class="screen-body"><div class="result"><div class="result__icon result__icon--danger">' +
        I.x +
        '</div><h2 class="result__title">이체가 실패했어요</h2><div class="result__amount">' +
        fmt(tx.amount) +
        '</div><p class="result__desc">은행 처리 결과 실패로 확인되었어요.<br>출금되지 않았어요.</p></div>' +
        '<div class="card card--outline mt-16"><div class="verify-list">' +
        verifyItem('은행 처리 결과 · 실패', tx.failureReason || '', 'fail') +
        '</div></div></div>' +
        '<div class="screen-footer"><div class="btn-row"><button class="btn btn--ghost" data-action="go-support" data-code="TRANSFER_FAILED">상담 연결</button><button class="btn btn--primary" data-action="diagnose">다시 진단하기</button></div></div>'
      );
    },
    onBack() {
      app().goHome();
      return true;
    },
  };

  /* ---------- Support / escalation ---------- */
  const SUPPORT_COPY = {
    BANK_UNAVAILABLE: {
      icon: 'alert',
      title: '지금은 은행 상태를 확인할 수 없어요',
      desc: '정상적으로 진단할 수 없어 안내를 멈췄어요. 확인되지 않은 상태로 해결 방법을 추측하지 않아요. 잠시 후 다시 확인해 주세요.',
      primary: ['diagnose', '다시 확인하기'],
    },
    QUERY_FAILURE: {
      icon: 'alert',
      title: '은행 상태 조회에 실패했어요',
      desc: '상태를 확인하지 못해 해결 경로를 계산하지 않았어요. 정상 진단을 가장하지 않아요. 잠시 후 다시 확인해 주세요.',
      primary: ['diagnose', '다시 확인하기'],
    },
    ACCOUNT_RESTRICTED: {
      icon: 'lock',
      title: '계좌 이용 제한이 확인되었어요',
      desc: '해결패스는 제한 해제 방법을 안내하지 않아요. 보호를 위해 상세 사유는 표시하지 않으며, 공식 상담 창구에서 본인 확인 후 안내받을 수 있어요.',
      primary: ['support-connect', '상담 연결하기'],
    },
    INSUFFICIENT_BALANCE: {
      icon: 'coin',
      title: '출금 가능 잔액이 부족해요',
      desc: '잔액 부족은 설정 변경으로 해결할 수 없어요. 잔액을 확인한 뒤 다시 시도해 주세요.',
      primary: ['go-home', '홈으로'],
    },
    NO_PATH: {
      icon: 'question',
      title: '안내할 수 있는 절차를 찾지 못했어요',
      desc: '현재 상태에서 정상 이체까지 이어지는 허용된 절차가 없어요. 상담을 통해 확인해 주세요.',
      primary: ['support-connect', '상담 연결하기'],
    },
    TRANSFER_UNKNOWN: {
      icon: 'question',
      title: '이체 결과 확인을 도와드릴게요',
      desc: '결과가 확정되지 않은 거래는 다시 보내지 않아요. 상담사가 은행 처리 결과를 확인해 드릴 수 있어요.',
      primary: ['support-connect', '상담 연결하기'],
    },
    TRANSFER_FAILED: {
      icon: 'headset',
      title: '실패 원인 확인을 도와드릴게요',
      desc: '은행 처리 결과 실패로 확인된 거래예요. 출금되지 않았으며, 원인 확인이 필요하면 상담을 이용해 주세요.',
      primary: ['support-connect', '상담 연결하기'],
    },
    GENERAL: {
      icon: 'headset',
      title: '상담 연결 안내',
      desc: '해결패스가 확인한 내용과 시도한 절차를 상담사에게 전달해 같은 설명을 반복하지 않도록 도와드려요.',
      primary: ['support-connect', '상담 연결하기'],
    },
  };

  SCREENS.support = {
    title: '상담 안내',
    white: true,
    async render(params) {
      const a = app();
      const s = a.session;
      const plan = s.plan;
      const caseCtx = s.caseCtx;
      let code = (params && params.code) || (caseCtx && caseCtx.escalation && caseCtx.escalation.code);
      if (!code && plan) code = plan.status === 'NO_PATH' ? 'NO_PATH' : plan.blocker ? plan.blocker.code : null;
      const copy = SUPPORT_COPY[code] || SUPPORT_COPY.GENERAL;

      let detail = '';
      if (code === 'NO_PATH' && plan && plan.evaluation && !plan.evaluation.ctx.limitChangeAllowed) {
        detail = notice('확인된 사유: 이 계좌는 비대면 이체한도 변경 대상이 아니에요. (가상)', 'warning', I.info);
      }

      const rows = [];
      if (plan && plan.evaluation) {
        const c = plan.evaluation.ctx;
        rows.push(['요청 이체', esc(c.recipient) + ' · ' + fmt(c.amount)]);
        rows.push(['1일 이체한도', fmt(c.transferLimit)]);
        rows.push(['디지털 OTP', c.otpRegistered ? '등록됨' : '미등록']);
        rows.push(['고객확인', c.kycCompleted ? '완료' : '미완료']);
        rows.push(['계좌 상태', c.accountRestricted ? '제한 (상세 사유 미전달)' : '정상']);
      } else {
        rows.push(['확인한 상태', '은행 상태 조회 실패 · 확인된 정보 없음']);
      }
      const tried = caseCtx && caseCtx.timeline && caseCtx.timeline.length ? caseCtx.timeline.map((id) => PF.getAction(id).label).join(', ') : '없음';
      rows.push(['안내된 절차', esc(tried)]);
      if (caseCtx) rows.push(['사건 번호', '<code style="font-size:12px">' + esc(caseCtx.caseId) + '</code>']);

      const primary = copy.primary;
      const secondary =
        primary[0] === 'support-connect'
          ? '<button class="btn btn--ghost" data-action="go-home">홈으로</button>'
          : '<button class="btn btn--ghost" data-action="support-connect">상담 연결</button>';

      return (
        appbar('상담 안내') +
        '<div class="screen-body"><div class="result"><div class="result__icon result__icon--' +
        (code === 'ACCOUNT_RESTRICTED' ? 'danger' : 'warning') +
        '">' +
        I[copy.icon] +
        '</div><h2 class="result__title">' +
        esc(copy.title) +
        '</h2><p class="result__desc">' +
        esc(copy.desc) +
        '</p></div>' +
        detail +
        '<div class="section"><div class="section-title">상담사에게 전달할 내용 <small>동의 시에만 전달</small></div><div class="card card--outline">' +
        kvRows(rows) +
        '</div></div>' +
        '<p class="fineprint">해결패스는 보호 제한·사고 통제를 우회하지 않으며, 확인되지 않은 해결 방법을 만들어내지 않습니다. 상담 연결은 시연용 시뮬레이션입니다.</p>' +
        '</div><div class="screen-footer"><div class="btn-row">' +
        secondary +
        '<button class="btn btn--primary" data-action="' +
        primary[0] +
        '">' +
        esc(primary[1]) +
        '</button></div></div>'
      );
    },
  };

  /* ---------- Chat ---------- */
  function renderMessage(m) {
    if (m.role === 'user') {
      return '<div class="msg msg--user"><div class="msg__bubble">' + esc(m.text) + '</div></div>';
    }
    const links = (m.links || [])
      .map(
        (l, i) =>
          '<button class="btn btn--sm ' +
          (i === 0 ? 'btn--primary' : 'btn--secondary') +
          '" data-action="open-flow" data-flow="' +
          esc(l.flowId) +
          '">' +
          esc(l.label) +
          '</button>'
      )
      .join('');
    let meta = '';
    if (m.analysis) {
      const intents = m.analysis.intents.map((i) => i.label).join(' · ');
      meta =
        '<div class="msg__meta">의도 ' +
        esc(intents) +
        (m.analysis.amount ? ' · 금액 ' + man(m.analysis.amount) : '') +
        (m.ruleIds && m.ruleIds.length ? ' · 근거 ' + m.ruleIds.map((r) => '<code>' + r + '</code>').join(' ') : '') +
        (m.stateVersion ? ' · 상태 <code>v' + m.stateVersion + '</code>' : '') +
        '</div>';
    }
    return (
      '<div class="msg msg--bot"><div class="bot-label">' +
      I.spark.replace('<svg', '<svg width="13" height="13"') +
      'WON 해결패스</div><div class="msg__bubble' +
      (m.tone === 'warning' ? ' is-warning' : '') +
      '">' +
      esc(m.text) +
      '</div>' +
      (links ? '<div class="msg__links">' + links + '</div>' : '') +
      meta +
      '</div>'
    );
  }

  const CHAT_CHIPS = [
    ['이체 안 됨', '이체가 왜 안 돼?'],
    ['이체한도', '이체한도 어디서 바꿔?'],
    ['디지털 OTP', 'OTP 등록했는데 아직 안 돼요.'],
    ['고객확인', '고객확인은 어떻게 해?'],
    ['이체 결과', '이체 결과 알려줘'],
  ];

  const CHAT_CARDS = [
    { kw: '이체', rest: '가 안 되나요?', desc: '은행 상태를 확인해 막힌 이유를 한 번에 찾아드려요', cta: '이체 상태 확인하기', action: 'diagnose', icon: I.transfer },
    { kw: '이체한도', rest: '가 궁금하신가요?', desc: '현재 한도와 변경에 필요한 절차를 알려드려요', cta: '이체한도 물어보기', q: '이체한도 어디서 바꿔?', icon: I.gauge },
    { kw: '이체 결과', rest: '를 확인하고 싶으신가요?', desc: '은행에서 완료로 확인된 거래만 완료라고 안내해요', cta: '이체 결과 물어보기', q: '이체 결과 알려줘', icon: I.clock },
  ];

  function pad2(n) {
    return (n < 10 ? '0' : '') + n;
  }

  SCREENS.chat = {
    title: '해결패스 질문하기',
    white: true,
    async render() {
      const s = app().session;
      const cs = await bank.getCustomerState();
      const name = cs.ok ? cs.data.customerName + ' 고객님' : '고객님';
      const now = new Date();
      const date = now.getFullYear() + '.' + pad2(now.getMonth() + 1) + '.' + pad2(now.getDate());
      const time = pad2(now.getHours()) + ':' + pad2(now.getMinutes());

      const welcome =
        '<div class="chat-day"><span>' +
        date +
        '</span></div>' +
        '<div class="chat-sys"><i></i>해결패스와 연결되었어요 · 규칙 기반 시뮬레이션</div>' +
        '<div class="chat-hello"><span class="chat-avatar">' +
        I.robot +
        '</span><h2>' +
        esc(name) +
        ', 안녕하세요.<br>WON 해결패스입니다.</h2>' +
        '<p>이체가 막혔을 때 은행에서 확인된 현재 상태로 이유와 해결 순서를 안내해 드려요. 생성형 AI가 아닌 규칙 기반 안내예요.</p>' +
        '<div class="chat-chips">' +
        CHAT_CHIPS.map((c) => '<button class="chat-chip" data-action="chat-suggest" data-q="' + esc(c[1]) + '">' + esc(c[0]) + '</button>').join('') +
        '</div></div>' +
        '<div class="chat-cards"><div class="chat-cards__track" data-carousel>' +
        CHAT_CARDS.map(
          (c) =>
            '<div class="chat-card"><span class="chat-card__icon">' +
            c.icon +
            '</span><h3><em>' +
            esc(c.kw) +
            '</em>' +
            esc(c.rest) +
            '</h3><p>' +
            esc(c.desc) +
            '</p><button class="chat-card__cta" data-action="' +
            (c.action || 'chat-suggest') +
            '"' +
            (c.q ? ' data-q="' + esc(c.q) + '"' : '') +
            '>' +
            esc(c.cta) +
            '</button></div>'
        ).join('') +
        '</div>' +
        dotsHtml(CHAT_CARDS.length) +
        '</div>' +
        '<div class="chat-time">' +
        time +
        '</div>';

      return (
        appbar('해결패스와 대화중', {
          right: '<span class="ai-badge" aria-label="규칙 기반 AI 시뮬레이션"><b>AI</b>규칙기반</span>',
        }) +
        '<div class="chat-tools"><button data-action="go-support">' +
        I.headset +
        '톡상담</button><button data-action="noop">' +
        I.eyeOff +
        '상담숨기기</button><button data-action="chat-reset">' +
        I.refresh +
        '처음으로</button></div>' +
        '<div class="screen-body chat-body" id="chat-body">' +
        welcome +
        '<div class="chat-log" id="chat-log">' +
        s.chat.map(renderMessage).join('') +
        '</div></div>' +
        '<div class="chat-input"><button class="icon-btn" data-action="noop" aria-label="더보기">' +
        I.plus +
        '</button><div class="chat-input__field"><input id="chat-input" data-enter="chat-send" maxlength="120" placeholder="메시지를 입력해 주세요" aria-label="질문 입력" autocomplete="off" /><button class="chat-input__send" data-action="chat-send" aria-label="전송">' +
        I.send +
        '</button></div></div>'
      );
    },
    mount(el) {
      bindCarousels(el);
      const body = el.querySelector('#chat-body');
      if (body && app().session.chat.length) body.scrollTop = body.scrollHeight;
    },
  };

  /* ==================================================================
   * 라우터
   * ================================================================== */

  const SCREEN_IDS = Object.freeze(Object.keys(SCREENS));
  let viewport = null;
  let overlay = null;
  let current = null;
  let currentEl = null;
  let stack = [];
  let navToken = 0;
  let rerenderToken = 0;
  const navListeners = new Set();

  function emitNav() {
    navListeners.forEach((fn) => {
      try {
        fn(current);
      } catch (e) {
        console.error(e);
      }
    });
  }

  async function renderScreen(def, params) {
    try {
      return await def.render(params || {});
    } catch (e) {
      console.error('[WSP UI] 화면 렌더링 오류', e);
      return queryErrorCard(def.title, { message: '화면을 표시하는 중 문제가 발생했어요.' });
    }
  }

  /**
   * @param {string} id 화면 ID (허용목록)
   * @param {object} params
   * @param {{replace?:boolean, back?:boolean, backTo?:boolean, resetHistory?:boolean, animate?:boolean}} opts
   */
  async function navigate(id, params, opts) {
    const o = opts || {};
    const def = SCREENS[id];
    if (!def || SCREEN_IDS.indexOf(id) === -1) {
      console.warn('[WSP UI] 허용되지 않은 화면 ID: ' + id);
      return false;
    }
    const token = ++navToken;
    const html = await renderScreen(def, params);
    if (token !== navToken) return false;

    let back = !!o.back;
    if (o.resetHistory) stack = [];
    else if (o.backTo) {
      let idx = -1;
      for (let i = stack.length - 1; i >= 0; i--) {
        if (stack[i].id === id) {
          idx = i;
          break;
        }
      }
      if (idx >= 0) stack = stack.slice(0, idx);
      back = true;
    } else if (!o.replace && current) stack.push({ id: current.id, params: current.params });
    if (stack.length > 20) stack = stack.slice(-20);

    const el = document.createElement('section');
    el.className = 'screen' + (def.white ? ' is-white' : '');
    el.dataset.screen = id;
    el.innerHTML = html;
    const old = currentEl;
    currentEl = el;
    current = { id: id, params: params || {} };
    viewport.appendChild(el);

    if (old) {
      if (o.animate === false) old.remove();
      else {
        el.classList.add(back ? 'enter-back' : 'enter');
        old.classList.add(back ? 'leave-back' : 'leave');
        old.style.pointerEvents = 'none';
        setTimeout(() => old.remove(), 360);
      }
    } else el.classList.add('enter-fade');

    if (def.mount) def.mount(el, current.params);
    emitNav();
    return true;
  }

  /** 현재 화면을 같은 자리에서 다시 그린다 (스크롤 유지) */
  async function rerender(paramsPatch) {
    if (!current) return;
    const id = current.id;
    const def = SCREENS[id];
    const params = Object.assign({}, current.params, paramsPatch || {});
    const nav = navToken;
    const token = ++rerenderToken;
    const html = await renderScreen(def, params);
    if (nav !== navToken || token !== rerenderToken || !current || current.id !== id) return;
    const body = currentEl.querySelector('.screen-body');
    const scroll = body ? body.scrollTop : 0;
    currentEl.innerHTML = html;
    current.params = params;
    const nb = currentEl.querySelector('.screen-body');
    if (nb) nb.scrollTop = scroll;
    if (def.mount) def.mount(currentEl, params);
    emitNav();
  }

  function back() {
    if (!current) return;
    const def = SCREENS[current.id];
    if (def.onBack && def.onBack(current.params) === true) return;
    goBack();
  }

  function goBack() {
    const prev = stack.pop();
    if (!prev) {
      navigate('home', {}, { resetHistory: true, back: true });
      return;
    }
    navigate(prev.id, prev.params, { replace: true, back: true });
  }

  /* ==================================================================
   * 오버레이: 시트 / 모달 / 토스트
   * ================================================================== */

  let sheetEls = null;

  function openSheet(html, opts) {
    closeSheet(true);
    const bd = document.createElement('div');
    bd.className = 'sheet-backdrop';
    const sh = document.createElement('div');
    sh.className = 'sheet';
    sh.setAttribute('role', 'dialog');
    sh.innerHTML = '<div class="sheet__handle"></div>' + html;
    overlay.appendChild(bd);
    overlay.appendChild(sh);
    requestAnimationFrame(() =>
      requestAnimationFrame(() => {
        bd.classList.add('is-open');
        sh.classList.add('is-open');
      })
    );
    const o = opts || {};
    sheetEls = { bd: bd, sh: sh, dismissible: !!o.dismissible, onClose: o.onClose || null };
    const own = sheetEls;
    bd.addEventListener('click', () => {
      if (sheetEls === own && own.dismissible) closeSheet();
    });
    return sh;
  }

  /** 열린 시트를 배경 클릭으로 닫을 수 있게 하거나 막는다. */
  function setSheetDismissible(value) {
    if (sheetEls) sheetEls.dismissible = !!value;
  }

  function closeSheet(immediate) {
    if (!sheetEls) return;
    const els = sheetEls;
    sheetEls = null;
    if (els.onClose) els.onClose();
    if (immediate) {
      els.bd.remove();
      els.sh.remove();
      return;
    }
    els.bd.classList.remove('is-open');
    els.sh.classList.remove('is-open');
    setTimeout(() => {
      els.bd.remove();
      els.sh.remove();
    }, 340);
  }

  function getSheet() {
    return sheetEls ? sheetEls.sh : null;
  }

  let modalResolve = null;

  function confirm(opts) {
    closeModal(false);
    const o = opts || {};
    return new Promise((resolve) => {
      const bd = document.createElement('div');
      bd.className = 'modal-backdrop';
      bd.innerHTML =
        '<div class="modal" role="dialog" aria-modal="true"><h3 class="modal__title">' +
        o.title +
        '</h3><div class="modal__body">' +
        (o.bodyHtml || '') +
        '</div><div class="btn-row"><button class="btn btn--ghost" data-modal="cancel">' +
        esc(o.cancelText || '취소') +
        '</button><button class="btn ' +
        (o.danger ? 'btn--danger' : 'btn--primary') +
        '" data-modal="ok">' +
        esc(o.confirmText || '확인') +
        '</button></div></div>';
      overlay.appendChild(bd);
      requestAnimationFrame(() => requestAnimationFrame(() => bd.classList.add('is-open')));
      modalResolve = (v) => {
        bd.classList.remove('is-open');
        setTimeout(() => bd.remove(), 260);
        modalResolve = null;
        resolve(v);
      };
      bd.addEventListener('click', (e) => {
        const b = e.target.closest('[data-modal]');
        if (b) modalResolve && modalResolve(b.dataset.modal === 'ok');
        else if (e.target === bd) modalResolve && modalResolve(false);
      });
    });
  }

  function closeModal(value) {
    if (modalResolve) modalResolve(value);
  }

  let toastWrap = null;

  function toast(message, type, ms) {
    if (!toastWrap || !toastWrap.isConnected) {
      toastWrap = document.createElement('div');
      toastWrap.className = 'toast-wrap';
      overlay.appendChild(toastWrap);
    }
    const t = document.createElement('div');
    t.className = 'toast' + (type ? ' toast--' + type : '');
    t.textContent = message;
    toastWrap.appendChild(t);
    while (toastWrap.children.length > 2) toastWrap.firstChild.remove();
    setTimeout(() => {
      t.classList.add('is-leaving');
      setTimeout(() => t.remove(), 220);
    }, ms || 2600);
  }

  function closeAllOverlays() {
    closeSheet(true);
    closeModal(false);
    overlay.querySelectorAll('.modal-backdrop').forEach((n) => n.remove());
  }

  /* ---------- 채팅 DOM 갱신 (입력 포커스 유지) ---------- */
  function chatAppend(message) {
    if (!current || current.id !== 'chat') return;
    const log = currentEl.querySelector('#chat-log');
    const body = currentEl.querySelector('#chat-body');
    if (!log) return;
    log.insertAdjacentHTML('beforeend', renderMessage(message));
    body.scrollTop = body.scrollHeight;
  }

  function chatTyping(show) {
    if (!current || current.id !== 'chat') return;
    const log = currentEl.querySelector('#chat-log');
    const body = currentEl.querySelector('#chat-body');
    if (!log) return;
    const existing = log.querySelector('.typing');
    if (show && !existing) {
      log.insertAdjacentHTML('beforeend', '<div class="typing" aria-label="답변 준비 중"><span></span><span></span><span></span></div>');
      body.scrollTop = body.scrollHeight;
    } else if (!show && existing) existing.remove();
  }

  /* ==================================================================
   * 초기화 / 이벤트 위임
   * ================================================================== */

  function init() {
    viewport = document.getElementById('viewport');
    overlay = document.getElementById('overlay-root');

    function onClick(e) {
      const t = e.target.closest('[data-action]');
      if (!t) return;
      if (t.disabled || t.getAttribute('aria-disabled') === 'true') return;
      e.preventDefault();
      WSP.app.dispatch(t.dataset.action, t.dataset, t, e);
    }
    viewport.addEventListener('click', onClick);
    overlay.addEventListener('click', onClick);

    viewport.addEventListener('input', (e) => {
      const t = e.target.closest('[data-input]');
      if (t) WSP.app.onInput(t.dataset.input, t, e);
    });
    viewport.addEventListener(
      'blur',
      (e) => {
        const t = e.target.closest && e.target.closest('[data-input]');
        if (t) WSP.app.onCommit(t.dataset.input, t, e);
      },
      true
    );
    viewport.addEventListener('keydown', (e) => {
      if (e.key !== 'Enter' || e.isComposing) return;
      const t = e.target.closest('[data-enter]');
      if (t) {
        e.preventDefault();
        WSP.app.dispatch(t.dataset.enter, t.dataset, t, e);
      }
    });
  }

  function setLoading(el, loading) {
    if (!el) return;
    el.classList.toggle('is-loading', !!loading);
    el.disabled = !!loading;
  }

  WSP.ui = {
    SCREEN_IDS: SCREEN_IDS,
    I: I,
    esc: esc,
    kvRows: kvRows,
    badge: badge,
    init: init,
    navigate: navigate,
    rerender: rerender,
    back: back,
    goBack: goBack,
    current: () => current,
    currentEl: () => currentEl,
    onNavigate: (fn) => {
      navListeners.add(fn);
      return () => navListeners.delete(fn);
    },
    openSheet: openSheet,
    closeSheet: closeSheet,
    setSheetDismissible: setSheetDismissible,
    getSheet: getSheet,
    confirm: confirm,
    toast: toast,
    closeAllOverlays: closeAllOverlays,
    chatAppend: chatAppend,
    chatTyping: chatTyping,
    setLoading: setLoading,
    resetHistory: () => {
      stack = [];
    },
  };
})();
