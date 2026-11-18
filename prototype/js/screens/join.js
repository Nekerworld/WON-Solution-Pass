/**
 * screens/join.js
 * 가입 지원(AI) 화면: 동의, 대화+체크리스트, 가입 정보 확인·승인, 가입 결과(직접 가입 공용), 상담 연결(자산관리 공용).
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
  const jf = () => app().fsms.join;

  /* ---------- 동의 ---------- */
  UI.registerScreen('join-consent', {
    title: '가입 지원 동의',
    white: true,
    render() {
      const j = app().session.join;
      if (!j || jf().state !== 'CONSENT') return UI.appbar('가입 지원') + '<div class="screen-body"><p class="lead">진행 중인 동의 요청이 없어요.</p></div>';
      const p = SC.getProduct(j.productId);
      return (
        UI.appbar('AI 가입 지원') +
        '<div class="screen-body"><div class="consent-hero"><span>' +
        I.spark +
        '</span><h2>' +
        esc(p.name) +
        '<br>가입을 도와드릴게요</h2></div>' +
        '<div class="card"><h3 class="card__title">' +
        I.shield +
        '조회·분석 동의 (필수)</h3><ul class="consent-list">' +
        '<li>실명확인·계좌·인증서·고객정보 등록 기록</li>' +
        '<li>마이데이터로 연결된 다른 은행 계좌 목록</li>' +
        '<li>로그인 때 확인된 휴대폰 본인 명의 여부</li></ul></div>' +
        '<div class="card card--outline"><h3 class="card__title">' +
        I.lock +
        '이 동의로 하지 않는 것</h3><ul class="consent-list consent-list--no">' +
        '<li>상품 가입 자동 신청</li></ul></div>' +
        '</div><div class="screen-footer"><div class="btn-row"><button class="btn btn--ghost" data-action="join-exit">다음에 할게요</button><button class="btn btn--primary" data-action="join-agree">가입 조건 확인</button></div></div>'
      );
    },
  });

  /* ---------- 대화 + 체크리스트 ---------- */
  function checklist(j) {
    const ev = j.evaluation;
    const ids = ev ? ev.conditions.map((c) => c.id) : SC.getProduct(j.productId).conditions;
    const byId = {};
    if (ev) ev.conditions.forEach((c) => (byId[c.id] = c));
    const checking = Array.isArray(j.checkPending);
    const done = j.checkDone || [];
    const freshId = j.checkFresh;
    const entered = !!j.listSeen;
    j.listSeen = true;
    j.checkFresh = null;
    const met = ev
      ? ev.conditions.filter((c) => c.status === 'MET' && (!checking || done.indexOf(c.id) !== -1)).length
      : 0;
    const rows = ids
      .map((id, i) => {
        const c = byId[id];
        const cond = SC.CONDITIONS[id];
        const fact = cond && SC.FACTS[cond.fact];
        const label = fact ? fact.short : cond ? cond.label : id;
        const revealed = !checking || done.indexOf(id) !== -1;
        const isMet = revealed && !!(c && c.status === 'MET');
        const loading = checking && !revealed;
        return (
          '<li class="ck__row' +
          (isMet ? ' is-met' : '') +
          (loading ? ' is-loading' : '') +
          (freshId === id ? ' is-new' : '') +
          (entered ? '' : ' is-in') +
          '"' +
          (entered ? '' : ' style="animation-delay:' + i * 80 + 'ms"') +
          '><i class="ck__tick" aria-hidden="true"></i><span>' +
          esc(label) +
          '</span></li>'
        );
      })
      .join('');
    return (
      '<div class="ck' +
      (jf().state === 'READY_TO_APPLY' ? ' is-ready' : '') +
      '"><div class="ck__head"><strong>가입 조건 ' +
      met +
      '/' +
      ids.length +
      '</strong><span class="ck__product">' +
      esc(SC.getProduct(j.productId).name) +
      '</span></div><ul>' +
      rows +
      '</ul></div>'
    );
  }

  function freshReply(chat) {
    const last = chat && chat[chat.length - 1];
    if (!last || last.role !== 'ai' || last.chipsShown) return false;
    last.chipsShown = true;
    return !!(last.at && Date.now() - last.at < 1600);
  }

  function optionCards(j) {
    const shown = j.options.filter((o) => o.shown);
    const blocked = j.options.filter((o) => !o.shown);
    const rise = freshReply(j.chat) ? ' is-in' : '';
    return (
      '<div class="opt-list' +
      rise +
      '">' +
      shown
        .map((o, i) => {
          const t = SC.getTask(o.actionId);
          return (
            '<button class="opt" style="--i:' +
            i +
            '" data-action="join-option" data-task="' +
            o.actionId +
            '"><span class="opt__icon">' +
            (UI.TASK_ICON[t.icon] || I.doc) +
            '</span><span class="opt__text"><strong>' +
            esc(t.label) +
            (o.recommended ? ' <em class="opt__rec">추천</em>' : '') +
            '</strong><span>' +
            esc(t.desc) +
            '</span><span class="opt__meta">' +
            I.clock +
            '약 ' +
            t.minutes +
            '분' +
            (t.prep.length ? ' · 준비물: ' + esc(t.prep.join(', ')) : '') +
            '</span>' +
            (o.unknownNeeds.length ? '<span class="opt__need">이 방법을 고르면 ' + esc(WSP.utils.josa(o.unknownNeeds.map((k) => SC.CONSTRAINTS[k].label).join(', '), '이')) + ' 있는 것으로 볼게요</span>' : '') +
            '</span>' +
            I.chevron +
            '</button>'
          );
        })
        .join('') +
      blocked
        .map((o, i) => {
          const t = SC.getTask(o.actionId);
          const why = o.blockedNeeds.length ? esc(o.blockedNeeds.map((k) => SC.CONSTRAINTS[k].label).join(', ')) + ' 없음' : '이후 단계로 이어지지 않음';
          return (
            '<div class="opt is-off" style="--i:' +
            (shown.length + i) +
            '"><span class="opt__icon">' +
            (UI.TASK_ICON[t.icon] || I.doc) +
            '</span><span class="opt__text"><strong>' +
            esc(t.label) +
            '</strong><span>이용 불가: ' +
            why +
            '</span></span></div>'
          );
        })
        .join('') +
      '</div>'
    );
  }

  function actionPanel(j) {
    const st = jf().state;
    if (j.thinking) return '';
    const q = j.pendingKey;
    if (q && (st === 'CLARIFYING' || st === 'REMAINING')) {
      const rise = freshReply(j.chat) ? ' is-in' : '';
      return (
        '<div class="act"><div class="chip-row' +
        rise +
        '">' +
        '<button class="chip chip--lg" style="--i:0" data-action="join-answer" data-key="' +
        q +
        '" data-value="true">네, 있어요</button><button class="chip chip--lg" style="--i:1" data-action="join-answer" data-key="' +
        q +
        '" data-value="false">아니요, 없어요</button></div></div>'
      );
    }
    if ((st === 'OPTIONS_READY' || st === 'REMAINING') && j.options.length) return '<div class="act">' + optionCards(j) + '</div>';
    if (st === 'TASK_OPEN') return '<div class="act">' + UI.notice('업무 화면이 열려 있어요. 화면을 닫으면 은행 기록을 다시 확인해요.', 'info', I.doc) + '</div>';
    if (st === 'CHECK_FAILED')
      return '<div class="act"><div class="btn-row"><button class="btn btn--secondary" data-action="join-consult">상담 연결</button><button class="btn btn--primary" data-action="join-retry-check">다시 확인</button></div></div>';
    if (st === 'INVESTIGATING' && j.exception) {
      const ex = j.exception;
      const fact = ex.facts[0];
      const rep = fact ? j.repeat[fact] || 0 : 0;
      const main =
        ex.cause === 'IN_PROGRESS' || ex.cause === 'QUERY_FAILED'
          ? '<button class="btn btn--primary" data-action="join-investigate" data-kind="requery">처리 결과 다시 확인</button>'
          : '<button class="btn btn--primary" data-action="join-investigate" data-kind="retry">다시 진행</button>';
      return (
        '<div class="act"><div class="exc"><strong>' +
        I.alert +
        { QUERY_FAILED: '은행 기록 조회 실패', IN_PROGRESS: '은행 처리 중', ERROR: '업무 처리 오류', MISMATCH: '완료 표시와 은행 기록 불일치' }[ex.cause] +
        '</strong>' +
        (rep ? '<span class="exc__rep">같은 문제 ' + rep + '/' + SC.POLICY.repeatLimit + '회</span>' : '') +
        '</div><div class="btn-row"><button class="btn btn--secondary" data-action="join-investigate" data-kind="consult">상담 연결</button>' +
        main +
        '</div></div>'
      );
    }
    if (st === 'READY_TO_APPLY')
      return (
        '<div class="act"><div class="ready-card"><strong>' +
        I.check +
        '가입 준비가 끝났어요</strong><p>가입 정보를 확인하고 직접 승인해 주세요.</p>' +
        (j.applyNotice ? '<p class="ready-card__warn">' + esc(j.applyNotice.text) + '</p>' : '') +
        '<button class="btn btn--primary btn--block" data-action="join-open-apply">가입 정보 확인하기</button></div></div>'
      );
    if (st === 'ESCALATED')
      return '<div class="act"><button class="btn btn--primary btn--block" data-action="join-open">' + I.headset + '상담 연결 화면으로</button></div>';
    if (['APPLYING', 'VERIFYING', 'RESULT_UNCERTAIN', 'COMPLETED', 'FAILED'].indexOf(st) !== -1)
      return '<div class="act"><button class="btn btn--primary btn--block" data-action="join-open">가입 결과 보기</button></div>';
    return '';
  }

  const TALK_STATES = ['CLARIFYING', 'OPTIONS_READY', 'REMAINING'];

  UI.registerScreen('join', {
    title: 'AI 가입 지원',
    white: true,
    render() {
      const j = app().session.join;
      if (!j) return UI.appbar('AI 가입 지원') + '<div class="screen-body"><p class="lead">진행 중인 가입 지원이 없어요.</p><button class="btn btn--primary" data-action="go-products">상품 보기</button></div>';
      const st = jf().state;
      const p = SC.getProduct(j.productId);
      const canTalk = TALK_STATES.indexOf(st) !== -1 && !j.thinking;
      const chips = canTalk
        ? '<div class="quick">' +
          ['상담 연결해 주세요', '완료했다고 떴는데 다시 하래요', '그만할래요'].map((q) => '<button class="quick__chip" data-action="join-send" data-q="' + esc(q) + '">' + esc(q) + '</button>').join('') +
          '</div>'
        : '';
      const presentHint =
        document.documentElement.classList.contains('is-present') &&
        WSP.store.getState().facts.fxRegistered &&
        (st === 'OPTIONS_READY' || st === 'REMAINING')
          ? '<p class="present-hint">다음은 오른쪽 남은 절차 확인입니다.</p>'
          : '';
      return (
        UI.chatHeader(jf().can('EXIT') ? { action: 'join-exit', label: '그만하기' } : null) +
        '<div class="screen-body join-body chat-body" id="join-body">' +
        UI.chatIntro('AI 가입 지원', j.chat[0] && j.chat[0].at) +
        checklist(j) +
        '<div class="chat-log">' +
        UI.chatLog(j.chat, j.thinking) +
        '</div>' +
        presentHint +
        actionPanel(j) +
        '</div>' +
        chips +
        UI.chatInput('join-input', 'join-send', '', false, true)
      );
    },
    mount(el, params, ctx) {
      UI.scrollToLatest(el.querySelector('#join-body'));
      if (ctx && ctx.first) WSP.joinFlow.resume();
    },
  });

  /* ---------- 가입 정보 확인·승인 ---------- */
  UI.registerScreen('apply', {
    title: '가입 정보 확인',
    white: true,
    async render(params) {
      const j = app().session.join;
      if (!j || jf().state !== 'READY_TO_APPLY')
        return UI.appbar('가입 정보 확인') + '<div class="screen-body"><p class="lead">가입 준비가 끝난 건이 없어요.</p><button class="btn btn--primary" data-action="join-open">진행 상황 보기</button></div>';
      const p = SC.getProduct(j.productId);
      const acc = await bank.getAccountSummary();
      if (!acc.ok) return UI.queryErrorCard('가입 정보 확인', acc.error);
      const ctx = j.assetContext;
      const account = acc.data.account ? acc.data.account.name + ' ' + acc.data.account.number : '계좌 없음';
      const ev = j.evaluation;
      const head =
        UI.appbar('가입 정보 확인') +
        '<div class="screen-body">' +
        (j.applyNotice ? UI.notice(esc(j.applyNotice.text), j.applyNotice.tone || 'warning', I.alert) : '');
      const tail =
        '<div class="card card--outline"><h3 class="card__title">' +
        I.shield +
        '은행 기록으로 확인한 가입 조건</h3><ul class="cond-list">' +
        (ev ? ev.conditions.map((c) => '<li>' + I.check + esc(c.label) + '</li>').join('') : '') +
        '</ul>' +
        '<p class="fineprint">승인하면 은행이 조건을 한 번 더 확인해요.</p>' +
        '</div></div>' +
        '<div class="screen-footer"><button class="btn btn--primary btn--block btn--lg" data-action="join-approve">가입 승인</button></div>';
      const staticField = (label, field, value) =>
        '<div class="field"><span class="field__label">' + label + '</span><div class="text-input is-static" data-field="' + field + '" data-value="' + esc(value) + '">' + esc(value) + '</div></div>';

      if (p.kind === 'BROKERAGE') {
        const market = params.market || (j.terms && j.terms.market) || p.markets[0];
        return (
          head +
          '<div class="card"><h3 class="card__title">' +
          esc(p.name) +
          '</h3>' +
          UI.kvRows([[p.rateLabel, esc(p.rateValue)]]) +
          '</div>' +
          '<div class="card"><div class="field"><span class="field__label">거래 시장</span><div class="chip-row" data-field="market">' +
          p.markets.map((m) => '<button class="chip' + (m === market ? ' is-on' : '') + '" data-action="apply-market" data-value="' + esc(m) + '">' + esc(m) + '</button>').join('') +
          '</div></div>' +
          staticField('연결 원화 계좌', 'account', account) +
          staticField('연결 외화 계좌', 'fxAccount', 'WON 외화통장(USD) 1002-***-552190') +
          '</div>' +
          tail
        );
      }

      const months = Number(params.months) || (ctx && p.periods.indexOf(ctx.months) !== -1 ? ctx.months : p.periods.indexOf(24) !== -1 ? 24 : p.periods[0]);
      const monthly = (j.terms && j.terms.monthly) || (ctx && ctx.monthly) || 300000;
      return (
        head +
        '<div class="card"><h3 class="card__title">' +
        esc(p.name) +
        '</h3>' +
        UI.kvRows([['금리', esc(p.rate)]]) +
        '</div>' +
        '<div class="card"><label class="field"><span class="field__label">월 납입액</span><input class="text-input" id="apply-monthly" data-field="monthly" inputmode="numeric" value="' +
        monthly +
        '" /><span class="field__hint">' +
        man(p.minMonthly) +
        ' ~ ' +
        man(p.maxMonthly) +
        '</span></label>' +
        '<div class="field"><span class="field__label">가입 기간</span><div class="chip-row" data-field="months">' +
        p.periods.map((m) => '<button class="chip' + (m === months ? ' is-on' : '') + '" data-action="apply-months" data-value="' + m + '">' + m + '개월</button>').join('') +
        '</div></div>' +
        staticField('출금 계좌', 'account', account) +
        '</div>' +
        tail
      );
    },
  });

  /* ---------- 가입 결과 (AI·직접 공용) ---------- */
  function approvalTimeline(done) {
    const steps = ['신청 접수', '본인/조건 재확인', '은행 심사 등록', '승인 대기'];
    return (
      '<ol class="approve-tl">' +
      steps
        .map((label, i) => '<li class="approve-tl__item" style="animation-delay:' + i * 0.55 + 's"><span>' + esc(label) + '</span></li>')
        .join('') +
      '</ol>' +
      (done ? '<div class="approve-stamp" aria-hidden="true">접수</div>' : '')
    );
  }

  function resultView(track) {
    const s = app().session;
    const isJoin = track !== 'direct';
    const d = isJoin ? s.join : s.direct;
    const st = isJoin ? jf().state : app().fsms.direct.state;
    if (!d) return null;
    const p = SC.getProduct(d.productId);
    const appRec = d.application;
    const newAction = isJoin ? 'join-new' : 'direct-new';
    const terms = appRec && appRec.terms ? appRec.terms : null;
    const rows = [['상품', esc(p.name)]];
    if (terms && terms.monthly) rows.push(['월 납입액', man(terms.monthly)]);
    if (terms && terms.months) rows.push(['가입 기간', terms.months + '개월']);
    if (terms && terms.market) rows.push(['거래 시장', esc(terms.market)]);
    if (d.requestId) rows.push(['요청 번호', '<code>' + esc(d.requestId) + '</code>']);

    if (['APPLYING', 'VERIFYING', 'D_VERIFYING'].indexOf(st) !== -1) {
      return {
        icon: '<div class="spinner spinner--lg"></div>',
        tone: 'neutral',
        title: '은행 심사에 등록하고 있어요',
        desc: '신청 접수부터 승인 대기까지 순서대로 확인해요. 다시 신청하지 마세요.',
        extra: approvalTimeline(false),
        rows: rows,
        foot: '',
      };
    }
    if (st === 'COMPLETED' || st === 'D_DONE') {
      rows.unshift(['접수 번호', '<strong>' + esc(appRec.id) + '</strong>']);
      return {
        icon: I.check,
        tone: 'success',
        title: p.kind === 'BROKERAGE' ? '해외주식 계좌 개설 신청이 접수됐어요' : '가입 신청이 접수됐어요',
        desc: '은행 심사에 등록되었어요.',
        extra: approvalTimeline(true),
        rows: rows,
        foot: '<button class="btn btn--primary btn--block" data-action="' + newAction + '">홈으로</button>',
      };
    }
    if (st === 'FAILED' || st === 'D_FAILED') {
      return {
        icon: I.x,
        tone: 'danger',
        title: '가입이 처리되지 않았어요',
        desc: (appRec && appRec.failureReason) || '은행이 가입 요청을 처리하지 못했어요.',
        rows: rows,
        foot:
          '<div class="btn-row">' +
          (isJoin ? '<button class="btn btn--secondary" data-action="join-escalate-failed">상담 연결</button>' : '<button class="btn btn--secondary" data-action="noop">고객센터 1588-0000</button>') +
          '<button class="btn btn--primary" data-action="' +
          newAction +
          '">처음으로</button></div>',
      };
    }
    if (st === 'RESULT_UNCERTAIN' || st === 'D_UNCERTAIN') {
      return {
        icon: I.clock,
        tone: 'warning',
        title: '가입 결과를 아직 확인하지 못했어요',
        desc: '요청이 은행에 접수됐을 수 있어요. 다시 신청하면 중복 가입될 수 있어서, 결과 조회만 해요.',
        rows: rows,
        foot: '<button class="btn btn--primary btn--block" data-action="' + (isJoin ? 'join-query-result' : 'direct-query-result') + '">결과 다시 조회</button>',
      };
    }
    return {
      icon: I.info,
      tone: 'neutral',
      title: '진행 중인 가입 요청이 없어요',
      desc: '',
      rows: [],
      foot: '<button class="btn btn--primary btn--block" data-action="' + (isJoin ? 'join-open' : 'direct-open') + '">진행 상황 보기</button>',
    };
  }

  UI.registerScreen('apply-result', {
    title: '가입 결과',
    white: true,
    render(params) {
      const v = resultView(params.track);
      if (!v) return UI.appbar('가입 결과', { noBack: true }) + '<div class="screen-body"><p class="lead">진행 중인 가입이 없어요.</p><button class="btn btn--primary" data-action="go-home">홈으로</button></div>';
      return (
        UI.appbar('가입 결과', { noBack: true }) +
        '<div class="screen-body"><div class="result"><div class="result__icon result__icon--' +
        v.tone +
        '">' +
        v.icon +
        '</div><h2 class="result__title">' +
        esc(v.title) +
        '</h2>' +
        (v.desc ? '<p class="result__desc">' + esc(v.desc) + '</p>' : '') +
        (v.extra || '') +
        '</div>' +
        (v.rows.length ? '<div class="card">' + UI.kvRows(v.rows) + '</div>' : '') +
        '</div>' +
        (v.foot ? '<div class="screen-footer">' + v.foot + '</div>' : '')
      );
    },
    mount(el, params, ctx) {
      if (!ctx || !ctx.first) return;
      if (params.track === 'direct') WSP.directFlow.resume();
      else WSP.joinFlow.resume();
    },
  });

  /* ---------- 상담 연결 (가입 지원·자산관리 공용) ---------- */
  const REASON_TITLE = {
    CUSTOMER_REQUEST: '고객님이 상담을 요청했어요',
    BLOCKER: '앱에서 해결할 수 없는 조건이 있어요',
    CYCLE: '앱 안에서는 순서가 막혀요',
    NO_ROUTE: '앱 안에서 해결할 방법을 찾지 못했어요',
    REPEAT: '같은 문제가 반복됐어요',
    EXCEPTION: '업무 처리 결과를 확인하지 못했어요',
    APPLY_FAILED: '가입이 처리되지 않았어요',
    HOLD: '지금 정보로는 제안하기 어려워요',
    QUERY_FAILED: '은행 기록을 확인하지 못했어요',
  };

  const summarizing = new Set();

  function supportCtx(track) {
    const s = app().session;
    if (track === 'asset') return { data: s.asset, ok: app().fsms.asset.state === 'HANDOFF' };
    return { data: s.join, ok: jf().state === 'ESCALATED' };
  }

  function cycleHtml(cause) {
    if (!cause || cause.type !== 'CYCLE') return '';
    const names = cause.chain.map((f) => SC.FACTS[f].short);
    return '<div class="cycle">' + names.map((n) => '<span>' + esc(n) + '</span>').join('<i>' + I.chevron + '</i>') + '</div>';
  }

  UI.registerScreen('support', {
    title: '상담 연결',
    white: true,
    render(params) {
      const track = params.track === 'asset' ? 'asset' : 'join';
      const c = supportCtx(track);
      if (!c.data || !c.ok) return UI.appbar('상담 연결') + '<div class="screen-body"><p class="lead">상담 연결이 필요한 건이 없어요.</p><button class="btn btn--primary" data-action="go-home">홈으로</button></div>';
      const d = c.data;
      const esc8 = d.escalation || { reason: 'CUSTOMER_REQUEST', text: '' };
      const h = d.handoff;
      const consult = d.consult;
      let summary;
      if (!h) summary = '<div class="summary is-loading"><div class="spinner"></div>상담 요약을 정리하고 있어요</div>';
      else
        summary =
          '<div class="summary"><div class="summary__head"><strong>' +
          I.doc +
          '상담 요약</strong>' +
          UI.badge(consult && consult.status === 'ACCEPTED' ? '전달됨' : '아직 접수 전', consult && consult.status === 'ACCEPTED' ? 'success' : 'neutral') +
          '</div><ul>' +
          h.lines.map((l) => '<li>' + esc(l) + '</li>').join('') +
          '</ul></div>';
      let result = '';
      if (consult && consult.status === 'ACCEPTED') {
        result =
          '<div class="card card--success"><h3 class="card__title">' +
          I.check +
          '상담이 접수됐어요</h3>' +
          UI.kvRows([
            ['접수 번호', '<strong>' + esc(consult.ticket.id) + '</strong>'],
            ['안내', esc(consult.ticket.eta)],
          ]) +
          '</div>';
      } else if (consult && consult.status === 'FAILED') {
        result =
          '<div class="card card--warning"><h3 class="card__title">' +
          I.alert +
          '상담 접수가 완료되지 않았어요</h3><p>요약은 만들었지만 접수는 되지 않았어요. 아래 방법으로 다시 연결해 주세요.</p><ul class="consent-list"><li>잠시 후 다시 접수하기</li><li>고객센터 1588-0000</li><li>가까운 영업점 방문 (신분증 지참)</li></ul></div>';
      }
      const accepted = consult && consult.status === 'ACCEPTED';
      const canSubmit = !!h && !accepted && !!d.handoffConsent;
      const secondary =
        track === 'join'
          ? '<div class="btn-row"><button class="btn btn--ghost" data-action="join-new">처음으로</button><button class="btn btn--secondary" data-action="join-recheck">은행 기록 다시 확인</button></div>'
          : '<button class="btn btn--ghost btn--block" data-action="support-asset-end">상담 종료</button>';
      return (
        UI.appbar('상담 연결') +
        '<div class="screen-body"><div class="reason"><span class="reason__icon">' +
        I.headset +
        '</span><div><strong>' +
        esc(REASON_TITLE[esc8.reason] || '상담이 필요해요') +
        '</strong><p>' +
        esc(esc8.text) +
        '</p></div></div>' +
        cycleHtml(esc8.cause) +
        summary +
        (accepted
          ? ''
          : '<label class="check-row"><input type="checkbox" data-action="support-consent" data-track="' +
            track +
            '"' +
            (d.handoffConsent ? ' checked' : '') +
            ' /><span>위 요약을 상담사에게 전달하는 데 동의해요.</span></label>') +
        result +
        '</div><div class="screen-footer">' +
        (accepted
          ? ''
          : '<button class="btn btn--primary btn--block" data-action="support-submit" data-track="' +
            track +
            '"' +
            (canSubmit ? '' : ' disabled') +
            '>' +
            (consult && consult.status === 'FAILED' ? '다시 접수하기' : '상담 접수하기') +
            '</button>') +
        secondary +
        '</div>'
      );
    },
    mount(el, params) {
      const track = params.track === 'asset' ? 'asset' : 'join';
      const c = supportCtx(track);
      if (!c.data || !c.ok || c.data.handoff || summarizing.has(track)) return;
      const ctx = track === 'asset' ? WSP.assetFlow.handoffContext() : WSP.joinFlow.handoffContext();
      if (!ctx) return;
      summarizing.add(track);
      const ep = app().epoch();
      WSP.aiAgent.handoffSummary(ctx).then((res) => {
        summarizing.delete(track);
        if (ep !== app().epoch()) return;
        c.data.handoff = { lines: res.output.summary || ctx.lines || [], fallback: res.fallback, at: Date.now() };
        if (res.fallback) c.data.handoff.lines = (ctx.lines || []).concat(ctx.reasonText ? ['연결 사유: ' + ctx.reasonText] : []);
        app().refresh(['support']);
      });
    },
  });

  WSP.registerActions({
    'apply-months'(d) {
      UI.rerender({ months: Number(d.value) });
    },
    'apply-market'(d) {
      UI.rerender({ market: d.value });
    },
    'support-consent'(d, el, e) {
      const c = supportCtx(d.track);
      if (!c.data) return;
      c.data.handoffConsent = !c.data.handoffConsent;
      app().refresh(['support']);
    },
    'support-submit'(d) {
      return app().guard('support-submit', async () => {
        const c = supportCtx(d.track);
        if (!c.data || !c.ok || !c.data.handoff || !c.data.handoffConsent) return;
        const ep = app().epoch();
        const btn = UI.currentEl().querySelector('[data-action="support-submit"]');
        UI.setLoading(btn, true);
        const r = await bank.createConsultation({ track: d.track, lines: c.data.handoff.lines });
        if (ep !== app().epoch()) return;
        c.data.consult = r.ok ? { status: 'ACCEPTED', ticket: r.data.ticket } : { status: 'FAILED', error: r.error };
        WSP.events.add('APP', r.ok ? '상담 접수 완료 ' + r.data.ticket.id : '상담 접수 실패 — 후속 안내 표시');
        app().refresh(['support']);
      });
    },
    'support-asset-end'() {
      WSP.assetFlow.end();
      UI.navigate('asset', {}, { replace: true });
    },
  });
})();