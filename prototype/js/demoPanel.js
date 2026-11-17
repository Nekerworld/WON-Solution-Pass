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

  const root = document.getElementById('demo-panel');
  if (!root) return;

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
    '<div class="dp-head"><div><div class="dp-head__title">시연</div></div>' +
    '<button class="dp-btn dp-btn--primary" data-dp="reset">처음부터</button></div>' +
    '<div class="dp-body"><div class="dp-col" id="dp-left"></div><div class="dp-col" id="dp-right"></div></div>';

  const $ = (sel) => root.querySelector(sel);

  root.addEventListener('click', (e) => {
    const b = e.target.closest('[data-dp]');
    if (!b) return;
    if (b.dataset.dp === 'reset') WSP.app.resetDemo();
    if (b.dataset.dp === 'summarize') WSP.joinFlow.summarizeRemaining();
  });

  function customerCard(s) {
    const c = s.customer;
    const won = WSP.utils.formatWon;
    const income = s.finance && s.finance.items && s.finance.items.monthlyIncome;
    const expense = s.finance && s.finance.items && s.finance.items.monthlyExpense;
    const row = (label, value) => '<div class="dp-num"><span>' + esc(label) + '</span><strong>' + esc(value) + '</strong></div>';
    return (
      '<section class="dp-card dp-card--who"><p class="dp-kicker">고객 정보</p><h2>' +
      esc(c.name) +
      ' · ' +
      c.age +
      '세</h2><div class="dp-nums">' +
      row('월급', won(income && income.value)) +
      row('지출', won(expense && expense.value)) +
      row('해외계좌', s.facts.hasFxAccount === true ? '있음' : '없음') +
      '</div></section>'
    );
  }

  function gapText(info, key) {
    if (!info || !info.items || !info.items[key]) return '아직 모름';
    if (info.declined && info.declined.indexOf(key) !== -1) return '답하지 않음';
    const value = info.items[key].value;
    if (value == null) return '아직 모름';
    if (Number(value) === 0) return '없음';
    if (Number(value) > 0) return WSP.utils.formatWon(value);
    return '아직 모름';
  }

  function paceText(info) {
    if (!info || !info.items || !info.items.investPace) return '아직 모름';
    if (info.declined && info.declined.indexOf('investPace') !== -1) return '답하지 않음';
    const value = info.items.investPace.value;
    if (value == null) return '아직 모름';
    return WSP.assetAdvisor.display('investPace', value);
  }

  function situation(a) {
    const info = a && a.info;
    const rows = [
      ['목표', a && a.goalText ? a.goalText : '아직 없음'],
      ['투자 속도', paceText(info)],
      ['다른 증권 투자금', gapText(info, 'investAssets')],
      ['목돈 지출 계획', gapText(info, 'plannedLumpSum')],
    ];
    return (
      '<section class="dp-card"><h2>해결패스가 알고 있는 정보</h2><div class="dp-nums dp-nums--lines">' +
      rows.map((c) => '<div class="dp-num"><span>' + esc(c[0]) + '</span><strong>' + esc(c[1]) + '</strong></div>').join('') +
      '</div></section>'
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
    const ready = remainReady(s);
    return (
      '<section class="dp-card"><h2>가입까지 남은 절차</h2><ul class="dp-proc">' +
      html +
      '</ul>' +
      (next ? '<p class="dp-next">다음: ' + esc(next.label) + '</p>' : '<p class="dp-next">해외주식 계좌 개설이 끝났어요.</p>') +
      '<button class="dp-btn dp-btn--primary" data-dp="summarize"' +
      (ready ? '' : ' disabled') +
      '>남은 절차 확인</button></section>'
    );
  }

  function remainReady(s) {
    const st = WSP.app.fsms.join.state;
    return s.facts.fxRegistered === true && (st === 'OPTIONS_READY' || st === 'REMAINING');
  }

  function sync() {
    const s = store.getState();
    $('#dp-left').innerHTML = customerCard(s) + situation(WSP.app.session.asset) + procedures(s);
    $('#dp-right').innerHTML = '';
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
