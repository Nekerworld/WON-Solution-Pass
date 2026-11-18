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

  root.innerHTML =
    '<div class="dp-head"><div><div class="dp-head__title">시연</div></div>' +
    '<button class="dp-btn dp-btn--primary" data-dp="reset">처음부터</button></div>' +
    '<div class="dp-body"><div class="dp-col" id="dp-left"></div><div class="dp-col" id="dp-right"></div></div>';

  const $ = (sel) => root.querySelector(sel);

  root.addEventListener('click', (e) => {
    const b = e.target.closest('[data-dp]');
    if (!b) return;
    if (b.dataset.dp === 'reset') {
      setProfile({ personaDone: false });
      WSP.app.resetDemo();
    }
    if (b.dataset.dp === 'preset') applyPreset(b.dataset.id);
    if (b.dataset.dp === 'debt-toggle') setProfile({ debtOn: !profile.debtOn, debt: profile.debtOn ? 0 : profile.debt || 30000000 });
    if (b.dataset.dp === 'profile-reset') setProfile({ income: 3500000, expense: 2100000, debtOn: false, debt: 0 });
    if (b.dataset.dp === 'persona-ok') setProfile({ personaDone: true });
    if (b.dataset.dp === 'persona-edit') setProfile({ personaDone: false });
  });

  /** 슬라이더를 끄는 동안: 패널을 다시 그리지 않고 값 글자와 월 여유만 바꾼다 */
  root.addEventListener('input', (e) => {
    const t = e.target;
    const field = t.dataset && t.dataset.dpField;
    if (!field) return;
    const v = Number(t.value) * 10000;
    const strong = t.parentElement && t.parentElement.querySelector('strong');
    if (strong) strong.textContent = WSP.utils.formatMan(v);
    const live = Object.assign({}, profile);
    live[field] = v;
    const spare = root.querySelector('.dp-spare');
    if (spare) spare.textContent = personaSummary(live).lines[3];
  });

  /** 슬라이더를 놓았을 때: 값을 저장하고 앱에 반영한다 */
  root.addEventListener('change', (e) => {
    const t = e.target;
    if (t.dataset.dpField === 'income') setProfile({ income: Number(t.value) * 10000 });
    if (t.dataset.dpField === 'expense') setProfile({ expense: Number(t.value) * 10000 });
    if (t.dataset.dpField === 'debt') setProfile({ debt: Number(t.value) * 10000, debtOn: true });
  });

  const PROFILE_KEY = 'wsp.demoProfile.v1';
  const BASE = { income: 3500000, expense: 2100000, debtOn: false, debt: 0, personaDone: false };
  let profile = loadProfile();

  function loadProfile() {
    try {
      const raw = sessionStorage.getItem(PROFILE_KEY);
      if (!raw) return Object.assign({}, BASE);
      return Object.assign({}, BASE, JSON.parse(raw));
    } catch (e) {
      return Object.assign({}, BASE);
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
    summary: personaSummary,
    set: setProfile,
    get: () => Object.assign({}, profile),
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

  /** 천만원 단위로 딱 떨어지면 "3천만원"처럼 읽기 쉽게 쓴다 */
  function manText(n) {
    const man = Number(n || 0) / 10000;
    if (man >= 1000 && man % 1000 === 0 && man < 10000) return man / 1000 + '천만원';
    return WSP.utils.formatMan(n);
  }

  /** 페르소나 요약 줄과 프리셋 이름. 값이 프리셋과 똑같을 때만 이름을 붙인다 */
  function personaSummary(p) {
    const debt = p.debtOn ? p.debt : 0;
    const pay = WSP.lumpsumAdvisor.debtPayment(debt);
    const f = WSP.utils.formatMan;
    let preset = '';
    if (p.income === 3500000 && p.expense === 2100000 && !p.debtOn) preset = '기본';
    else if (p.income === 3500000 && p.expense === 3600000 && !p.debtOn) preset = '여유 없음';
    else if (p.income === 3500000 && p.expense === 2100000 && p.debtOn && p.debt === 30000000) preset = '부채 있음';
    return {
      preset: preset,
      lines: ['수입 ' + f(p.income), '지출 ' + f(p.expense), debt > 0 ? '부채 ' + manText(debt) + ' · 월 상환 ' + f(pay) : '부채 없음', '월 여유 ' + WSP.lumpsumAdvisor.manSigned(p.income - p.expense - pay)],
    };
  }

  function hintLines() {
    const hint = WSP.lumpsumFlow && WSP.lumpsumFlow.hint ? WSP.lumpsumFlow.hint() : { active: false, line: '', spoken: '', decision: '' };
    return (
      (hint.active ? '<p class="dp-hint">' + esc(hint.line) + '</p>' : '') +
      (hint.spoken ? '<p class="dp-spoken">' + esc(hint.spoken) + '</p>' : '') +
      (hint.decision ? '<p class="dp-snap">' + esc(hint.decision) + '<br />새 채팅부터 반영돼요</p>' : hint.active ? '<p class="dp-snap">새 채팅부터 반영돼요</p>' : '')
    );
  }

  function customerCard(s) {
    const c = s.customer;
    const debt = profile.debtOn ? profile.debt : 0;
    const sum = personaSummary(profile);
    const who = esc(c.name) + ' · ' + c.age + '세';
    if (profile.personaDone) {
      return (
        '<section class="dp-card dp-card--who is-done"><p class="dp-kicker">고객 정보' +
        (sum.preset ? ' <span class="dp-tag">' + esc(sum.preset) + '</span>' : '') +
        '</p><h2>' +
        who +
        '</h2><ul class="dp-sum">' +
        sum.lines.map((l) => '<li>' + esc(l) + '</li>').join('') +
        '</ul><button type="button" class="dp-edit" data-dp="persona-edit" aria-expanded="false">바꾸기<i class="dp-edit__chev" aria-hidden="true"></i></button>' +
        hintLines() +
        '</section>'
      );
    }
    return (
      '<section class="dp-card dp-card--who"><p class="dp-kicker">페르소나 만들기</p><h2>' +
      who +
      '</h2><div class="dp-slides"><div class="dp-persona-grid">' +
      slider('income', '수입', profile.income, 150, 800, 10, false) +
      '<button type="button" class="dp-btn' +
      (profile.debtOn ? ' dp-btn--primary' : '') +
      '" data-dp="debt-toggle">부채 있음</button>' +
      slider('expense', '지출', profile.expense, 50, 700, 10, false) +
      slider('debt', '부채 잔액', debt, 0, 10000, 100, !profile.debtOn) +
      '</div><p class="dp-spare">' +
      esc(sum.lines[3]) +
      '</p><div class="dp-presets"><button type="button" data-dp="preset" data-id="base">기본</button><button type="button" data-dp="preset" data-id="spend">여유 없음</button><button type="button" data-dp="preset" data-id="debt">부채 있음</button><button type="button" data-dp="profile-reset">기본값</button></div>' +
      '<button type="button" class="dp-btn dp-btn--primary dp-confirm" data-dp="persona-ok">이 설정으로 할게요</button>' +
      hintLines() +
      '</section>'
    );
  }

  function situation(s) {
    const sess = WSP.app.session;
    const apps = Object.keys(s.applications)
      .map((k) => s.applications[k])
      .filter((a) => a.productId === SC.DEMO.productId);
    const info = WSP.goalInfo.describe({
      lumpsum: sess.lumpsum,
      lumpsumState: WSP.app.fsms.lumpsum.state,
      asset: sess.asset,
      assetState: WSP.app.fsms.asset.state,
      applied: apps.some((a) => a.status === 'PENDING' || a.status === 'UNKNOWN' || a.status === 'SUCCESS'),
      hasFxAccount: s.facts.hasFxAccount,
    });
    return (
      '<section class="dp-card"><h2>해결패스가 알고 있는 정보</h2><div class="dp-nums dp-nums--lines">' +
      info.rows
        .map((c) => '<div class="dp-num"><span>' + esc(c.label) + '</span><strong>' + esc(c.value) + '</strong></div>' + (c.note ? '<p class="dp-note">“' + esc(c.note) + '”</p>' : ''))
        .join('') +
      '</div></section>'
    );
  }

  function sync() {
    const s = store.getState();
    $('#dp-left').innerHTML = customerCard(s) + situation(s);
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
