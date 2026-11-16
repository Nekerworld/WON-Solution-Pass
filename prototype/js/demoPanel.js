/**
 * demoPanel.js
 * 발표자·청중용 시연 패널 (PC, 앱 화면 바깥).
 * 금융 청중이 읽는 말로, 지금 고객에게 무슨 일이 일어나는지만 보여 준다.
 * 상태머신·경로 그래프·JSON·이벤트 로그·자가 테스트는 이 화면에 올리지 않는다.
 * 단축키: Shift + D (표시/숨김)
 */
(function () {
  'use strict';

  const WSP = window.WSP;
  const store = WSP.store;
  const SC = WSP.scenario;
  const esc = WSP.ui.esc;
  const man = WSP.utils.formatMan;

  const root = document.getElementById('demo-panel');
  if (!root) return;

  const UNDERSTAND = [
    ['동의·목표', ['CONSENT', 'GOAL']],
    ['분석·질문', ['COLLECTING', 'TAGGING', 'CALCULATING', 'INTERPRETING', 'GAP_CHECK', 'ASKING', 'RECALC_ANSWER', 'RECALC_CHANGE', 'PROPOSABLE_CHECK', 'PROPOSED_FULL', 'PROPOSED_LIMITED']],
    ['방향·상품', ['REVIEW', 'NEXT_ACTION', 'EXPLORE', 'HOLD', 'RECONSULT', 'HANDOFF', 'CLOSED', 'TO_JOIN']],
  ];
  const JOIN_STEPS = [
    ['조건 비교', ['CONSENT', 'CHECKING', 'CHECK_FAILED', 'CLARIFYING']],
    ['필요한 절차', ['ROUTE_CHECK', 'OPTIONS_READY', 'TASK_OPEN', 'RECHECKING', 'REMAINING', 'INVESTIGATING']],
    ['결과 확인·승인', ['READY_TO_APPLY', 'APPLYING', 'VERIFYING', 'RESULT_UNCERTAIN', 'COMPLETED', 'FAILED', 'ESCALATED']],
  ];
  const PROC = [
    ['identityVerified', '실명확인'],
    ['hasDepositAccount', '입출금 계좌'],
    ['certRegistered', '인증서'],
    ['kycDone', '고객정보'],
    ['fxRegistered', '외환거래'],
    ['hasFxAccount', '외화 계좌'],
    ['investorProfiled', '투자성향'],
  ];

  root.innerHTML =
    '<div class="dp-head"><div><div class="dp-head__title">시연</div><div class="dp-head__sub">김우리 고객의 해결패스 · Shift+D</div></div>' +
    '<button class="dp-btn dp-btn--primary" data-dp="reset">처음부터</button></div>' +
    '<div class="dp-body"><div class="dp-col" id="dp-left"></div><div class="dp-col" id="dp-right"></div></div>';

  const $ = (sel) => root.querySelector(sel);

  root.addEventListener('click', (e) => {
    const b = e.target.closest('[data-dp]');
    if (!b) return;
    if (b.dataset.dp === 'reset') WSP.app.resetDemo();
  });

  function stepList(title, rows, activeIndex) {
    return (
      '<section class="dp-card"><h2>' +
      esc(title) +
      '</h2><ol class="dp-story">' +
      rows
        .map((row, i) => {
          const cls = activeIndex < 0 ? '' : i < activeIndex ? 'is-done' : i === activeIndex ? 'is-cur' : '';
          return '<li class="' + cls + '"><span>' + (cls === 'is-done' ? '✓' : i + 1) + '</span>' + esc(row[0]) + '</li>';
        })
        .join('') +
      '</ol></section>'
    );
  }

  function chapterIndex(state, rows) {
    if (!state || state === 'IDLE') return -1;
    const i = rows.findIndex((row) => row[1].indexOf(state) !== -1);
    return i;
  }

  function cue() {
    const screen = WSP.ui.current();
    const id = screen ? screen.id : 'home';
    const asset = WSP.app.fsms.asset.state;
    const join = WSP.app.fsms.join.state;
    const a = WSP.app.session.asset;
    const j = WSP.app.session.join;
    if (join === 'COMPLETED') return '해외주식 계좌 개설이 끝났어요';
    if (id === 'apply' || join === 'READY_TO_APPLY') return id === 'apply' ? '가입 승인' : '가입 정보 확인하기';
    if (join === 'TASK_OPEN') return '진행하기, 이어서 닫고 은행 기록 확인';
    if (j && j.pendingKey === 'hasIdCard') return '아니요, 없어요';
    if (j && j.pendingKey === 'hasMobileId') return '네, 있어요';
    if (join === 'OPTIONS_READY' || join === 'REMAINING') {
      const step = j && j.route && j.route.steps && j.route.steps[0];
      return step ? step.label : '추천 절차를 진행해요';
    }
    if (join === 'CONSENT' || id === 'join-consent') return '동의하고 시작';
    if (id === 'product') return 'AI와 함께 가입';
    if (asset === 'EXPLORE' || id === 'explore') return 'WON 해외주식 계좌 · 이 상품 보기';
    if (asset === 'NEXT_ACTION') return '상품 둘러보기';
    if (asset === 'REVIEW') return '이 방향으로 할게요';
    if (asset === 'ASKING' && a && a.pendingQuestion) {
      const q = WSP.assetAdvisor.QUESTIONS[a.pendingQuestion];
      return q && q.options.length ? q.options[0][0] : '아래 답변';
    }
    if (asset === 'GOAL') return '해외주식 투자를 처음 시작해 보고 싶어요';
    if (asset === 'CONSENT' || id === 'asset-consent') return '동의하고 시작';
    if (id === 'home' && asset === 'IDLE' && join === 'IDLE') return '해외주식, 시작 금액 보기';
    if (join !== 'IDLE') return '가입 지원을 이어서 진행해요';
    if (asset !== 'IDLE') return '자산 상담을 이어서 진행해요';
    return '홈에서 AI 자산관리 상담으로 시작해요';
  }

  function customerCard(s) {
    const c = s.customer;
    const linked = (s.finance.linked || []).join(' · ');
    return (
      '<section class="dp-card dp-card--who"><p class="dp-kicker">이 고객</p><h2>' +
      esc(c.name) +
      ' · ' +
      c.age +
      '세</h2><p>우리은행 계좌가 있는 고객. 연결된 기관은 ' +
      esc(linked) +
      '.</p><p class="dp-lead">실명확인, 계좌, 인증서, 고객정보는 이미 있어요. 해외주식에 필요한 외환거래와 외화 계좌, 투자성향만 남아요.</p></section>'
    );
  }

  function situation(a) {
    if (!a || !a.metrics) return '<section class="dp-card"><h2>지금 파악한 상황</h2><p class="dp-empty">상담이 시작되면 이 고객의 숫자와 출처가 나타나요.</p></section>';
    const b = a.metrics.byKey;
    const purpose = a.purpose && WSP.assetAdvisor.PURPOSES[a.purpose] ? WSP.assetAdvisor.PURPOSES[a.purpose].label : '';
    const cards = [];
    if (purpose || a.goalText) cards.push(['목표', purpose || '상담', a.goalText || '']);
    if (b.surplus && b.surplus.value != null) cards.push(['매달 남는 돈', '월 ' + b.surplus.text, '']);
    if (b.capacity && b.capacity.value != null) cards.push(['무리 없이 모을 수 있는 돈', '월 ' + b.capacity.text, '']);
    if (b.emergencyMonths && b.emergencyMonths.value != null) cards.push(['바로 쓸 수 있는 예금', '생활비 ' + b.emergencyMonths.text + '치', '']);
    const monthly = a.proposal && a.proposal.basis ? a.proposal.basis.monthly : null;
    if (monthly != null) cards.push(['제안', '월 ' + man(monthly), '']);
    return (
      '<section class="dp-card"><h2>지금 파악한 상황</h2><div class="dp-nums">' +
      cards
        .map(
          (c) =>
            '<div class="dp-num"><span>' +
            esc(c[0]) +
            '</span><strong>' +
            esc(c[1]) +
            '</strong>' +
            (c[2] ? '<em>' + esc(c[2]) + '</em>' : '') +
            '</div>'
        )
        .join('') +
      '</div></section>'
    );
  }

  function asking(s) {
    const known = [];
    const acct = s.finance.otherBankAccounts && s.finance.otherBankAccounts[0];
    if (acct) known.push('다른 은행 계좌 · ' + acct.bank + ' ' + acct.masked);
    if (s.customer.mobileOwnerVerified) known.push('휴대폰 명의 · 로그인 때 확인');
    const j = WSP.app.session.join;
    if (j) {
      Object.keys(j.constraints).forEach((k) => {
        if (j.constraints[k] === null || k === 'hasOtherBankAccount') return;
        known.push(SC.CONSTRAINTS[k].label + ' · ' + (j.constraints[k] ? '있음' : '없음'));
      });
    }
    const now = [];
    const a = WSP.app.session.asset;
    if (a && a.pendingQuestion && WSP.assetAdvisor.ITEMS[a.pendingQuestion]) now.push(WSP.assetAdvisor.ITEMS[a.pendingQuestion].label);
    if (j && j.pendingKey && SC.CONSTRAINTS[j.pendingKey]) now.push(SC.CONSTRAINTS[j.pendingKey].label);
    return (
      '<section class="dp-card"><h2>다시 묻지 않는 것</h2><ul class="dp-pills">' +
      known.map((t) => '<li class="is-known">' + esc(t) + '</li>').join('') +
      '</ul><h2 class="dp-subhead">지금 묻는 것</h2>' +
      (now.length ? '<ul class="dp-pills">' + now.map((t) => '<li class="is-now">' + esc(t) + '</li>').join('') + '</ul>' : '<p class="dp-empty">은행이 모르는 내용이 있을 때만 물어봐요.</p>') +
      '</section>'
    );
  }

  function procedures(s) {
    const apps = Object.keys(s.applications)
      .map((k) => s.applications[k])
      .filter((a) => a.productId === SC.DEMO.productId);
    const opened = apps.some((a) => a.status === 'SUCCESS');
    const items = PROC.map((p) => ({ label: p[1], ok: s.facts[p[0]] === true, pending: !!s.pending[p[0]] }));
    items.push({ label: '계좌 개설', ok: opened, pending: apps.some((a) => a.status === 'PENDING' || a.status === 'UNKNOWN') });
    let marked = false;
    const html = items
      .map((it) => {
        let cls = it.ok ? 'is-done' : '';
        if (!it.ok && !marked) {
          marked = true;
          cls = 'is-cur';
        }
        return '<li class="' + cls + '">' + (it.ok ? '✓' : it.pending ? '…' : '') + ' ' + esc(it.label) + '</li>';
      })
      .join('');
    const next = items.find((it) => !it.ok);
    return (
      '<section class="dp-card"><h2>가입까지 남은 절차</h2><ul class="dp-proc">' +
      html +
      '</ul>' +
      (next ? '<p class="dp-next">다음: ' + esc(next.label) + '</p>' : '<p class="dp-next">해외주식 계좌 개설이 끝났어요.</p>') +
      '<p class="dp-note">기존 은행 화면에서 처리하고, 기록을 다시 확인한 뒤 다음으로 넘어갑니다. 가입은 고객이 승인한 뒤에만 요청합니다.</p></section>'
    );
  }

  function sync() {
    const s = store.getState();
    const asset = WSP.app.fsms.asset.state;
    const join = WSP.app.fsms.join.state;
    const joinOn = join !== 'IDLE';
    const understandAt = joinOn ? UNDERSTAND.length : chapterIndex(asset, UNDERSTAND);
    const joinAt = chapterIndex(join, JOIN_STEPS);
    $('#dp-left').innerHTML =
      customerCard(s) +
      stepList('고객 이해', UNDERSTAND, understandAt) +
      stepList('가입 지원', JOIN_STEPS, joinAt) +
      '<section class="dp-cue"><p>다음에 누를 것</p><strong>' +
      esc(cue()) +
      '</strong></section>';
    $('#dp-right').innerHTML = situation(WSP.app.session.asset) + asking(s) + procedures(s);
  }

  let raf = 0;
  function scheduleSync() {
    if (raf) return;
    raf = requestAnimationFrame(() => {
      raf = 0;
      sync();
    });
  }

  store.subscribe(scheduleSync);
  WSP.app.onChange(scheduleSync);
  Object.keys(WSP.app.fsms).forEach((k) => WSP.app.fsms[k].subscribe(scheduleSync));
  window.addEventListener('DOMContentLoaded', sync);
  sync();

  const fab = document.createElement('button');
  fab.className = 'dp-toggle-fab';
  fab.type = 'button';
  fab.textContent = '시연';
  fab.addEventListener('click', togglePanel);
  document.body.appendChild(fab);
  if (/[?&]demo=1/.test(location.search)) fab.classList.add('is-visible');

  function togglePanel() {
    if (window.matchMedia('(max-width: 900px)').matches) {
      root.classList.toggle('is-open');
      fab.classList.add('is-visible');
    } else root.parentElement.classList.toggle('is-panel-hidden');
  }

  document.addEventListener('keydown', (e) => {
    if (e.shiftKey && (e.key === 'D' || e.key === 'd') && !/input|textarea|select/i.test(e.target.tagName)) {
      e.preventDefault();
      togglePanel();
    }
  });
})();
