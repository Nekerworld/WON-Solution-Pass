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
    if (b.dataset.dp === 'preset') applyPreset(b.dataset.id);
    if (b.dataset.dp === 'debt-toggle') setProfile({ debtOn: !profile.debtOn, debt: profile.debtOn ? 0 : profile.debt || 30000000 });
    if (b.dataset.dp === 'profile-reset') setProfile({ income: 3500000, expense: 2100000, debtOn: false, debt: 0 });
    if (b.dataset.dp === 'scene') {
      if (b.dataset.go === 'products') WSP.ui.navigate('products');
      if (b.dataset.go === 'home') WSP.ui.navigate('home', {}, { resetHistory: true });
      if (b.dataset.go === 'lumpsum') WSP.lumpsumFlow.open();
    }
  });

  root.addEventListener('change', (e) => {
    const t = e.target;
    if (t.dataset.dpField === 'income') setProfile({ income: Number(t.value) * 10000 });
    if (t.dataset.dpField === 'expense') setProfile({ expense: Number(t.value) * 10000 });
    if (t.dataset.dpField === 'debt') setProfile({ debt: Number(t.value) * 10000, debtOn: true });
  });

  const PROFILE_KEY = 'wsp.demoProfile.v1';
  let profile = loadProfile();

  function loadProfile() {
    try {
      const raw = sessionStorage.getItem(PROFILE_KEY);
      if (!raw) return { income: 3500000, expense: 2100000, debtOn: false, debt: 0 };
      return Object.assign({ income: 3500000, expense: 2100000, debtOn: false, debt: 0 }, JSON.parse(raw));
    } catch (e) {
      return { income: 3500000, expense: 2100000, debtOn: false, debt: 0 };
    }
  }

  function setProfile(patch) {
    profile = Object.assign({}, profile, patch);
    if (!profile.debtOn) profile.debt = 0;
    sessionStorage.setItem(PROFILE_KEY, JSON.stringify(profile));
    applyProfile(profile);
  }

  function applyProfile(p) {
    const debt = p.debtOn ? p.debt : 0;
    const pay = WSP.lumpsumAdvisor.debtPayment(debt);
    store.update((d) => {
      d.finance.items.monthlyIncome = { value: p.income, source: 'BANK', basis: '보유 입출금 계좌의 급여 내역' };
      d.finance.items.monthlyExpense = { value: p.expense, source: 'BANK', basis: '보유 입출금 계좌의 지출 내역' };
      d.finance.items.debt = { value: debt, source: 'BANK', basis: debt ? '보유 계좌 기준 대출 잔액' : '보유 계좌 기준 대출 없음' };
      d.finance.items.debtPayment = { value: pay, source: 'BANK', basis: debt ? '원리금 균등, 연 5.5%, 60개월' : '보유 계좌 기준 상환 내역 없음' };
    }, '시연 프로필');
  }

  function applyPreset(id) {
    if (id === 'spend') setProfile({ income: 3500000, expense: 3600000, debtOn: false, debt: 0 });
    else if (id === 'debt') setProfile({ income: 3500000, expense: 2100000, debtOn: true, debt: 30000000 });
    else setProfile({ income: 3500000, expense: 2100000, debtOn: false, debt: 0 });
  }

  WSP.demoProfile = {
    reapply() {
      profile = loadProfile();
      applyProfile(profile);
    },
  };

  function slider(field, label, value, min, max, step, off) {
    const man = WSP.utils.formatMan(value);
    return (
      '<label class="dp-slide' +
      (off ? ' is-off' : '') +
      '"><span>' +
      esc(label) +
      '</span><strong>' +
      esc(man) +
      '</strong><input type="range" data-dp-field="' +
      field +
      '" min="' +
      min +
      '" max="' +
      max +
      '" step="' +
      step +
      '" value="' +
      Math.round(value / 10000) +
      '"' +
      (off ? ' disabled' : '') +
      ' /></label>'
    );
  }

  function customerCard(s) {
    const c = s.customer;
    const debt = profile.debtOn ? profile.debt : 0;
    const spare = profile.income - profile.expense - WSP.lumpsumAdvisor.debtPayment(debt);
    const hint = WSP.lumpsumFlow && WSP.lumpsumFlow.hint ? WSP.lumpsumFlow.hint() : { active: false, line: '', spoken: '', snapshot: '' };
    return (
      '<section class="dp-card dp-card--who"><p class="dp-kicker">고객 정보</p><h2>' +
      esc(c.name) +
      ' · ' +
      c.age +
      '세</h2><div class="dp-slides">' +
      slider('income', '월급', profile.income, 150, 800, 10, false) +
      slider('expense', '지출', profile.expense, 50, 700, 10, false) +
      '<button type="button" class="dp-btn' +
      (profile.debtOn ? ' dp-btn--primary' : '') +
      '" data-dp="debt-toggle">부채 있음</button>' +
      slider('debt', '부채 잔액', debt, 0, 10000, 100, !profile.debtOn) +
      '<p class="dp-spare">월 여유 ' +
      esc(WSP.utils.formatMan(spare)) +
      '</p><div class="dp-presets"><button type="button" data-dp="preset" data-id="base">기본</button><button type="button" data-dp="preset" data-id="spend">여유 없음</button><button type="button" data-dp="preset" data-id="debt">부채 있음</button><button type="button" data-dp="profile-reset">기본값</button></div>' +
      (hint.active ? '<p class="dp-hint">' + esc(hint.line) + '</p>' : '') +
      (hint.spoken ? '<p class="dp-spoken">' + esc(hint.spoken) + '</p>' : '') +
      (hint.decision ? '<p class="dp-snap">' + esc(hint.decision) + '<br />새 채팅부터 반영돼요</p>' : hint.active ? '<p class="dp-snap">새 채팅부터 반영돼요</p>' : '') +
      '<div class="dp-scenes"><button type="button" data-dp="scene" data-go="products">상품 페이지</button><button type="button" data-dp="scene" data-go="home">홈 복귀</button><button type="button" data-dp="scene" data-go="lumpsum">AI 상담 진입</button></div><p class="dp-acct">해외계좌 ' +
      (s.facts.hasFxAccount === true ? '있음' : '없음') +
      '</p></section>'
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
      (next ? '<p class="dp-next">다음: ' + esc(next.label) + '</p>' : '<p class="dp-next">해외주식 계좌 개설 신청이 접수됐어요.</p>') +
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
  window.addEventListener('DOMContentLoaded', () => {
    WSP.demoProfile.reapply();
    sync();
  });
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
