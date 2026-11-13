/**
 * screens/direct.js
 * 직접 가입: 기존 가입 화면처럼 단계별로 입력하고, 단계마다 은행 조건을 확인한다.
 * 부족한 조건은 안내만 하고, 고객이 직접 메뉴를 찾아 해결한 뒤 처음부터 다시 시작한다.
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
  const df = () => app().fsms.direct;

  function stepper(p, idx, st) {
    return (
      '<ol class="stepper">' +
      p.directSteps
        .map((s, i) => {
          const cls = st === 'D_APPROVE' || i < idx ? 'is-done' : i === idx && st !== 'D_START' ? 'is-current' : '';
          return '<li class="' + cls + '"><span>' + (cls === 'is-done' ? I.check : i + 1) + '</span>' + esc(s.label) + '</li>';
        })
        .join('') +
      '</ol>'
    );
  }

  async function stepForm(p, d, step) {
    if (step.id === 'terms') {
      return (
        '<div class="card"><h3 class="card__title">' +
        esc(p.name) +
        '</h3><p>' +
        esc(p.summary) +
        '</p>' +
        UI.kvRows([['금리', esc(p.rate) + ' (가상)']]) +
        '</div><button class="check-btn' +
        (d.input.agreed ? ' is-on' : '') +
        '" data-action="direct-agree"><span class="check-btn__box">' +
        I.check +
        '</span>상품 설명서와 약관을 확인했어요</button>'
      );
    }
    if (step.id === 'amount') {
      let html = '<div class="card">';
      if (p.maxMonthly)
        html +=
          '<label class="field"><span class="field__label">월 납입액</span><input class="text-input" id="direct-monthly" data-input="direct-monthly" inputmode="numeric" value="' +
          (d.input.monthly || '') +
          '" /><span class="field__hint">' +
          man(p.minMonthly) +
          ' ~ ' +
          man(p.maxMonthly) +
          '</span></label>';
      if (p.periods.length)
        html +=
          '<div class="field"><span class="field__label">가입 기간</span><div class="chip-row">' +
          p.periods.map((m) => '<button class="chip' + (d.input.months === m ? ' is-on' : '') + '" data-action="direct-months" data-value="' + m + '">' + m + '개월</button>').join('') +
          '</div></div>';
      return html + '</div>';
    }
    if (step.id === 'account') {
      const r = await bank.getAccountSummary();
      const acc = r.ok && r.data.account ? r.data.account : null;
      return (
        '<div class="card"><span class="field__label">출금 계좌</span>' +
        (acc
          ? '<div class="acct-pick is-on">' + I.wallet + '<span>' + esc(acc.name) + '<small>' + esc(acc.number) + '</small></span>' + I.check + '</div>'
          : '<div class="acct-pick is-empty">' + I.wallet + '<span>선택할 수 있는 우리은행 계좌가 없어요</span></div>') +
        '</div>'
      );
    }
    if (step.id === 'info') return '<div class="card"><p>등록된 고객정보(직업·거래 목적)로 가입을 진행해요.</p></div>';
    if (step.id === 'identity') return '<div class="card"><p>실명확인된 정보로 본인을 확인해요.</p></div>';
    if (step.id === 'sign') return '<div class="card"><p>' + I.key + ' 우리 인증서로 가입 신청서에 전자서명해요.</p></div>';
    return '';
  }

  UI.registerScreen('direct', {
    title: '직접 가입',
    white: true,
    async render() {
      const d = app().session.direct;
      if (!d) return UI.appbar('직접 가입') + '<div class="screen-body"><p class="lead">진행 중인 직접 가입이 없어요.</p><button class="btn btn--primary" data-action="go-products">상품 보기</button></div>';
      const p = SC.getProduct(d.productId);
      const st = df().state;
      const right = df().can('EXIT') ? '<button class="appbar__text" data-action="direct-exit">그만하기</button>' : '<span></span>';
      let body = '';
      let foot = '';
      if (st === 'D_START') {
        body =
          '<div class="card"><h3 class="card__title">' +
          I.doc +
          '직접 가입 안내</h3><p>아래 단계를 차례로 입력해요. 각 단계에서 가입 조건을 확인하고, 부족하면 해당 메뉴에서 먼저 처리해야 해요.</p></div>';
        foot = '<button class="btn btn--primary btn--block" data-action="direct-begin">가입 시작</button>';
      } else if (st === 'D_STEP' || st === 'D_CHECK') {
        const step = p.directSteps[d.stepIndex];
        body = '<h2 class="step-title">' + (d.stepIndex + 1) + '. ' + esc(step.label) + '</h2>' + (await stepForm(p, d, step));
        foot = '<button class="btn btn--primary btn--block' + (d.checking ? ' is-loading" disabled' : '"') + ' data-action="direct-next">' + (d.checking ? '확인 중' : '다음') + '</button>';
      } else if (st === 'D_NOTICE') {
        const n = d.notice || { conditions: [] };
        body =
          '<div class="card card--warning"><h3 class="card__title">' +
          I.alert +
          esc(n.stepLabel || '') +
          ' 단계를 진행할 수 없어요</h3><ul class="cond-list cond-list--bad">' +
          n.conditions.map((c) => '<li>' + I.x + esc(c.label) + (c.menu ? '<small>전체 메뉴 &gt; ' + esc(c.menu) + '에서 처리</small>' : '') + '</li>').join('') +
          '</ul><p class="fineprint">해결한 뒤 가입을 처음부터 다시 진행해 주세요. 입력한 내용은 저장되지 않아요.</p></div>';
        foot = '<div class="btn-row"><button class="btn btn--ghost" data-action="direct-exit">그만하기</button><button class="btn btn--primary" data-action="direct-go-fix">메뉴로 이동</button></div>';
      } else if (st === 'D_SELF_FIX') {
        body = UI.notice('부족한 조건을 메뉴에서 해결한 뒤, 가입을 처음부터 다시 진행해 주세요.', 'info', I.info);
        foot = '<div class="btn-row"><button class="btn btn--secondary" data-action="go-menu">전체 메뉴</button><button class="btn btn--primary" data-action="direct-restart">처음부터 다시</button></div>';
      } else if (st === 'D_APPROVE') {
        const rows = [['상품', esc(p.name)]];
        if (p.maxMonthly) rows.push(['월 납입액', man(d.input.monthly)]);
        if (p.periods.length) rows.push(['가입 기간', d.input.months + '개월']);
        body =
          '<h2 class="step-title">가입 신청 확인</h2>' +
          (d.applyNotice ? UI.notice(esc(d.applyNotice), 'warning', I.alert) : '') +
          '<div class="card">' +
          UI.kvRows(rows) +
          '</div>';
        foot = '<button class="btn btn--primary btn--block' + (d.checking ? ' is-loading" disabled' : '"') + ' data-action="direct-approve">가입 신청</button>';
      } else {
        body = '<p class="lead">가입 요청 결과를 확인해 주세요.</p>';
        foot = '<button class="btn btn--primary btn--block" data-action="direct-open">가입 결과 보기</button>';
      }
      return (
        UI.appbar(p.name + ' 가입', { right: right }) +
        '<div class="screen-body">' +
        stepper(p, d.stepIndex, st) +
        body +
        '</div><div class="screen-footer">' +
        foot +
        '</div>'
      );
    },
    mount(el, params, ctx) {
      if (ctx && ctx.first) WSP.directFlow.resume();
    },
  });
})();
