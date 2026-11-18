/**
 * screens/asset.js
 * 자산관리 상담: 동의, 상담(대화·큰 숫자·제안·다음 행동), 서비스 탐색.
 */
(function () {
  'use strict';

  const WSP = window.WSP;
  const SC = WSP.scenario;
  const AA = WSP.assetAdvisor;
  const UI = WSP.ui;
  const I = UI.I;
  const esc = UI.esc;
  const man = WSP.utils.formatMan;
  const app = () => WSP.app;
  const af = () => app().fsms.asset;

  UI.registerScreen('asset-consent', {
    title: 'AI 자산관리 상담',
    white: true,
    render() {
      if (af().state !== 'CONSENT') return UI.appbar('AI 자산관리 상담') + '<div class="screen-body"><p class="lead">진행 중인 동의 요청이 없어요.</p></div>';
      return (
        UI.appbar('AI 자산관리 상담') +
        '<div class="screen-body"><div class="consent-hero"><span>' +
        I.target +
        '</span><h2>목표에 맞춰<br>모을 돈과 투자할 돈을 정해요</h2></div>' +
        '<div class="card"><h3 class="card__title">' +
        I.shield +
        '조회·분석 동의 (필수)</h3><ul class="consent-list">' +
        '<li>마이데이터로 연결된 기관의 잔액·입출금·카드 내역</li><li>상담 중 고객님이 답한 정보</li></ul></div>' +
        '<div class="card card--outline"><h3 class="card__title">' +
        I.lock +
        '이 상담에서 하지 않는 것</h3><ul class="consent-list consent-list--no"><li>상품 가입·이체·해지</li></ul></div>' +
        '</div><div class="screen-footer"><div class="btn-row"><button class="btn btn--ghost" data-action="asset-decline">다음에 할게요</button><button class="btn btn--primary" data-action="asset-agree">상담 시작</button></div></div>'
      );
    },
  });

  const INFO_KEYS = ['monthlyIncome', 'monthlyExpense', 'liquidAssets', 'investPace', 'investAssets', 'debt', 'goalAmount', 'goalMonths', 'plannedLumpSum', 'monthlySavingPref'];

  /** 정보 다시 확인: 값과 고치기 버튼만 보여 준다 */
  function infoEditor(a) {
    if (!a.info) return '';
    const rows = INFO_KEYS.filter((k) => !(k === 'monthlySavingPref' && a.info.items[k].value == null))
      .map((k) => {
        const it = a.info.items[k];
        return (
          '<li class="info__row"><span class="info__label">' +
          esc(AA.ITEMS[k].label) +
          '</span><span class="info__val">' +
          esc(it.value == null ? '입력 전' : AA.display(k, it.value)) +
          '</span><button class="info__edit" data-action="asset-edit" data-key="' +
          k +
          '">고치기</button></li>'
        );
      })
      .join('');
    return '<div class="info"><div class="info__head"><strong>' + I.list + '고객님 정보</strong></div><ul>' + rows + '</ul></div>';
  }

  function alternativesCard(a) {
    const alts = a.proposal ? a.proposal.basis.alternatives : [];
    if (!alts.length) return '';
    return (
      '<div class="proposal__alts"><span>이렇게 바꿀 수도 있어요</span>' +
      alts.map((x) => '<button class="alt" data-action="asset-alt" data-alt="' + x.id + '"><strong>' + esc(x.label) + '</strong><small>' + esc(x.detail) + '</small></button>').join('') +
      '</div>'
    );
  }

  const GOAL_CHIPS = ['해외주식 투자를 처음 시작해 보고 싶어요', '결혼 자금 3천만원을 3년 안에 모으고 싶어요', '비상자금이 충분한지 알고 싶어요'];
  /* 목돈 상담 첫 화면도 같은 선택지를 쓴다 */
  WSP.assetGoalChips = GOAL_CHIPS.slice();

  function freshReply(chat) {
    const last = chat && chat[chat.length - 1];
    if (!last || last.role !== 'ai' || last.chipsShown) return false;
    last.chipsShown = true;
    return !!(last.at && Date.now() - last.at < 1600);
  }

  function chipButton(label, attrs, i, extra) {
    return '<button class="chip' + (extra || '') + '" style="--i:' + i + '" ' + attrs + '>' + esc(label) + '</button>';
  }

  function actionPanel(a) {
    const st = af().state;
    if (a.thinking || a.pendingAccept) return '';
    const rise = freshReply(a.chat) ? ' is-in' : '';
    if (st === 'GOAL')
      return (
        '<div class="act"><div class="chip-row' +
        rise +
        '">' +
        GOAL_CHIPS.map((q, i) => chipButton(q, 'data-action="asset-send" data-q="' + esc(q) + '"', i, ' chip--lg')).join('') +
        '</div></div>'
      );
    if (st === 'ASKING') {
      const q = AA.QUESTIONS[a.pendingQuestion];
      if (!q) return '';
      const sub = [
        ['UNKNOWN', '잘 모르겠어요', ''],
        ['REFUSED', '답하고 싶지 않아요', ''],
        ['STOP', '지금 정보로 알려주세요', ' chip--accent'],
      ];
      return (
        '<div class="act"><div class="chip-row' +
        rise +
        '">' +
        q.options.map((o, i) => chipButton(o[0], 'data-action="asset-chip" data-value="' + o[1] + '" data-label="' + esc(o[0]) + '"', i, ' chip--lg')).join('') +
        '</div><div class="chip-row chip-row--sub' +
        rise +
        '">' +
        sub.map((s, i) => chipButton(s[1], 'data-action="asset-chip" data-value="' + s[0] + '" data-label="' + esc(s[1]) + '"', q.options.length + i, s[2])).join('') +
        '</div></div>'
      );
    }
    if (st === 'REVIEW')
      return '<div class="act">' + alternativesCard(a) + '<button class="btn btn--primary btn--block" data-action="asset-accept">이 방향으로 할게요</button></div>';
    if (st === 'NEXT_ACTION')
      return (
        '<div class="act"><div class="next-grid">' +
        '<button class="next" data-action="asset-next" data-kind="explore">' +
        I.product +
        '<strong>상품 둘러보기</strong><span>정한 방향에 맞는 상품 보기</span></button>' +
        '<button class="next" data-action="asset-next" data-kind="consult">' +
        I.headset +
        '<strong>전문 상담 연결</strong><span>상담사에게 요약 전달</span></button>' +
        '<button class="next" data-action="asset-next" data-kind="recheck">' +
        I.list +
        '<strong>정보 다시 확인</strong><span>틀린 정보 고치기</span></button>' +
        '<button class="next" data-action="asset-next" data-kind="keep">' +
        I.check +
        '<strong>지금은 유지</strong><span>상담 마치기</span></button></div></div>'
      );
    if (st === 'HOLD')
      return (
        '<div class="act"><div class="hold"><strong>' +
        I.alert +
        '제안 보류</strong><p>' +
        esc(a.hold ? a.hold.text : '') +
        '</p></div><div class="btn-stack"><button class="btn btn--secondary" data-action="asset-next" data-kind="recheck">정보 다시 확인</button><button class="btn btn--secondary" data-action="asset-next" data-kind="consult">상담 연결</button><button class="btn btn--ghost" data-action="asset-end">상담 종료</button></div></div>'
      );
    if (st === 'RECONSULT')
      return (
        '<div class="act">' +
        (a.info ? infoEditor(a) : UI.notice('정보를 다시 불러온 뒤 분석해요.', 'info', I.info)) +
        '<div class="btn-row"><button class="btn btn--ghost" data-action="asset-end">상담 종료</button><button class="btn btn--primary" data-action="asset-resume">' +
        (a.info ? '다시 분석' : '다시 조회하고 분석') +
        '</button></div></div>'
      );
    if (st === 'EXPLORE') return '<div class="act"><button class="btn btn--primary btn--block" data-action="asset-open">상품 둘러보기 화면으로</button></div>';
    if (st === 'HANDOFF') return '<div class="act"><button class="btn btn--primary btn--block" data-action="asset-open">' + I.headset + '상담 연결 화면으로</button></div>';
    if (st === 'CLOSED' || st === 'TO_JOIN')
      return (
        '<div class="act"><div class="btn-row"><button class="btn btn--ghost" data-action="go-home">홈으로</button><button class="btn btn--primary" data-action="asset-start">새 상담 시작</button></div></div>'
      );
    return '';
  }

  UI.registerScreen('asset', {
    title: 'AI 자산관리 상담',
    white: true,
    render() {
      const a = app().session.asset;
      if (!a) return UI.appbar('AI 자산관리 상담') + '<div class="screen-body"><p class="lead">진행 중인 상담이 없어요.</p><button class="btn btn--primary" data-action="asset-start">상담 시작</button></div>';
      return (
        UI.chatHeader(af().can('END') || af().can('EXIT') ? { action: 'asset-end', label: '분석 종료' } : null) +
        '<div class="screen-body asset-body chat-body" id="asset-body">' +
        UI.chatIntro('AI 자산관리 상담', a.chat[0] && a.chat[0].at) +
        '<div class="chat-log">' +
        UI.chatLog(a.chat, a.thinking) +
        '</div>' +
        actionPanel(a) +
        '</div>' +
        UI.chatInput('asset-input', 'asset-send', '', false, true)
      );
    },
    mount(el, params, ctx) {
      UI.scrollToLatest(el.querySelector('#asset-body'));
      if (ctx && ctx.first) WSP.assetFlow.resume();
    },
  });

  UI.registerScreen('explore', {
    title: '상품 둘러보기',
    white: true,
    render() {
      const a = app().session.asset;
      if (!a || !a.handoffTerms || (af().state !== 'EXPLORE' && af().state !== 'TO_JOIN'))
        return UI.appbar('상품 둘러보기') + '<div class="screen-body"><p class="lead">상담에서 정한 방향이 없어요.</p><button class="btn btn--primary" data-action="go-products">전체 상품 보기</button></div>';
      const t = a.handoffTerms;
      return (
        UI.appbar('상품 둘러보기') +
        '<div class="screen-body">' +
        '<div class="ctx-card"><span>' +
        I.target +
        '상담에서 정한 방향</span><strong>' +
        esc(t.purpose) +
        (t.monthly ? ' · 월 ' + man(t.monthly) : '') +
        (t.months ? ' · ' + t.months + '개월' : '') +
        '</strong></div>' +
        SC.PRODUCTS.map((p) => {
            const pick = p.id === SC.DEMO.productId;
            return (
              '<div class="product-card is-static' +
              (pick ? ' is-pick' : '') +
              '"><div class="product-card__top">' +
              UI.badge(p.type, 'info') +
              '<span class="product-card__rate">' +
              esc(p.rate) +
              '</span></div><strong>' +
              esc(p.name) +
              '</strong><span>' +
              esc(p.summary) +
              '</span><button class="btn ' +
              (pick ? 'btn--primary' : 'btn--ghost btn--sm') +
              '" data-action="asset-select-product" data-product="' +
              p.id +
              '">' +
              (pick ? '이 계좌 보기' : '다른 상품') +
              '</button></div>'
            );
          })
          .join('') +
        '</div>'
      );
    },
    onBack() {
      WSP.assetFlow.backFromExplore();
      return true;
    },
  });
})();
