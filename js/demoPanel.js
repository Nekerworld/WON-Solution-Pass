/**
 * demoPanel.js
 * 발표자용 시연 제어 패널 (PC 전용, 앱 화면 바깥).
 * 실제 금융 앱의 기능이 아니며, 가상 은행 상태를 바꾸고 내부 상태를 관찰하는 도구다.
 * 단축키: Shift + D (표시/숨김)
 */
(function () {
  'use strict';

  const WSP = window.WSP;
  const store = WSP.store;
  const fsm = WSP.fsm;
  const bank = WSP.mockBank;
  const events = WSP.events;
  const fmt = WSP.utils.formatWon;
  const esc = WSP.ui.esc;

  const root = document.getElementById('demo-panel');
  if (!root) return;

  const PRESETS = [
    { id: 'A', label: 'A 정상 복구', desc: 'OTP 미등록 + 한도 부족 (기본 시나리오)', apply: () => {} },
    { id: 'B', label: 'B OTP만', desc: '한도 200만원, OTP 미등록', apply: (d) => (d.customer.transferLimit = 2000000) },
    { id: 'C', label: 'C 한도만', desc: 'OTP 등록, 한도 100만원', apply: (d) => (d.customer.digitalOtpRegistered = true) },
    {
      id: 'D',
      label: 'D 모두 충족',
      desc: 'OTP 등록, 한도 200만원',
      apply: (d) => {
        d.customer.digitalOtpRegistered = true;
        d.customer.transferLimit = 2000000;
      },
    },
    { id: 'E', label: 'E 계좌 제한', desc: '계좌 이용 제한 상태', apply: (d) => (d.customer.accountRestricted = true) },
    { id: 'F', label: 'F 은행 장애', desc: '은행 시스템 이용 불가', apply: (d) => (d.system.bankAvailable = false) },
    { id: 'K', label: 'KYC 미완료', desc: '고객확인 → OTP → 한도 순서 계산', apply: (d) => (d.customer.kycCompleted = false) },
    { id: 'N', label: '경로 없음', desc: '비대면 한도 변경 불가', apply: (d) => (d.customer.transferLimitChangeAllowed = false) },
  ];

  const SWITCHES = [
    ['otp', '디지털 OTP 등록', (s) => s.customer.digitalOtpRegistered, (d, v) => (d.customer.digitalOtpRegistered = v)],
    ['kyc', '고객확인 완료', (s) => s.customer.kycCompleted, (d, v) => (d.customer.kycCompleted = v)],
    ['restricted', '계좌 이용 제한', (s) => s.customer.accountRestricted, (d, v) => (d.customer.accountRestricted = v)],
    ['bank', '은행 시스템 정상', (s) => s.system.bankAvailable, (d, v) => (d.system.bankAvailable = v)],
    ['limitChange', '비대면 한도 변경 허용', (s) => s.customer.transferLimitChangeAllowed, (d, v) => (d.customer.transferLimitChangeAllowed = v)],
    ['queryFailure', '상태 조회 실패 주입', (s) => s.simulation.queryFailure, (d, v) => (d.simulation.queryFailure = v)],
  ];

  const LIMITS = [500000, 1000000, 1500000, 2000000, 5000000];
  const OUTCOMES = ['SUCCESS', 'FAILED', 'PENDING', 'UNKNOWN'];

  root.innerHTML =
    '<div class="dp-head"><div><div class="dp-head__title">DEMO CONTROL</div><div class="dp-head__sub">시연용 도구 · 실제 앱 기능 아님 · Shift+D</div></div>' +
    '<button class="dp-btn dp-btn--danger" data-dp="reset">데모 초기화</button></div>' +
    '<div class="dp-body">' +
    '<div class="dp-col dp-col--controls">' +
    '<div class="dp-section"><div class="dp-section__title">시나리오 프리셋</div><div class="dp-grid dp-grid--4">' +
    PRESETS.map((p) => '<button class="dp-btn" data-dp="preset" data-id="' + p.id + '" title="' + esc(p.desc) + '">' + esc(p.label) + '</button>').join('') +
    '</div><div class="dp-note">프리셋은 데모를 초기화한 뒤 가상 은행 상태를 설정합니다. 이후 앱에서 이체를 시도하세요.</div></div>' +
    '<div class="dp-section"><div class="dp-section__title">가상 은행 상태</div>' +
    SWITCHES.map(
      (s) =>
        '<div class="dp-row"><label for="dp-sw-' +
        s[0] +
        '">' +
        s[1] +
        '</label><span class="dp-switch"><input type="checkbox" id="dp-sw-' +
        s[0] +
        '" data-dp-switch="' +
        s[0] +
        '"><span data-dp-switch-ui="' +
        s[0] +
        '"></span></span></div>'
    ).join('') +
    '<div class="dp-row"><label for="dp-limit">1일 이체한도</label><select class="dp-select" id="dp-limit">' +
    LIMITS.map((v) => '<option value="' + v + '">' + fmt(v) + '</option>').join('') +
    '</select></div></div>' +
    '<div class="dp-section"><div class="dp-section__title">다음 거래 결과 (가상 은행 응답)</div><div class="dp-grid dp-grid--4">' +
    OUTCOMES.map((o) => '<button class="dp-btn" data-dp="outcome" data-v="' + o + '">' + o + '</button>').join('') +
    '</div><div id="dp-pending"></div></div>' +
    '<div class="dp-section"><div class="dp-section__title">정책 가중치 <span class="dp-tag">' +
    esc(WSP.DEMO_POLICY.version) +
    '</span></div><div class="dp-weights" id="dp-weights"></div><div class="dp-note">상태 그래프 간선의 비용입니다. 경로 탐색은 비용 합이 가장 작은 경로를 고릅니다. (가상 정책)</div></div>' +
    '<div class="dp-section"><div class="dp-section__title">자가 테스트 <button class="dp-btn dp-btn--primary" data-dp="selftest">실행</button></div><div class="dp-tests" id="dp-tests"><span class="dp-note">명세 14장 로직 테스트를 브라우저 안에서 실행합니다. 실행 전 상태는 자동 복원됩니다.</span></div></div>' +
    '</div>' +
    '<div class="dp-col dp-col--observe">' +
    '<div class="dp-section"><div class="dp-section__title">해결패스 상태머신 <span id="dp-fsm-cur"></span></div><div class="dp-graph" id="dp-fsm"></div><div class="dp-log mt-8" id="dp-fsm-hist" style="max-height:96px"></div></div>' +
    '<div class="dp-section"><div class="dp-section__title">해결 경로 · 상태 그래프 (다익스트라)</div><div class="dp-graph" id="dp-sg"></div><div class="dp-path mt-8" id="dp-path"></div></div>' +
    '<div class="dp-section"><div class="dp-section__title">현재 상태 JSON <span id="dp-ver"></span></div><pre class="dp-pre" id="dp-json"></pre></div>' +
    '<div class="dp-section"><div class="dp-section__title">이벤트 로그</div><div class="dp-log" id="dp-log"></div></div>' +
    '</div>' +
    '</div>';

  const ACTION_SHORT = {
    COMPLETE_KYC: '고객확인',
    REGISTER_OTP: 'OTP 등록',
    CHANGE_TRANSFER_LIMIT: '한도 변경',
    RETURN_TO_TRANSFER: '이체 복귀',
  };

  renderWeights();
  function renderWeights() {
    const w = WSP.DEMO_POLICY.actionWeights || {};
    root.querySelector('#dp-weights').innerHTML = Object.keys(w)
      .map((id) => '<div class="dp-row"><span>' + esc(ACTION_SHORT[id] || id) + ' <code>' + id + '</code></span><b>' + w[id] + '</b></div>')
      .join('');
  }

  const $ = (sel) => root.querySelector(sel);

  /* ---------- 동작 ---------- */

  function applyPreset(id) {
    const p = PRESETS.find((x) => x.id === id);
    if (!p) return;
    WSP.app.resetDemo({ silent: true, noNavigate: true });
    store.update((d) => p.apply(d), '[시연] 프리셋 ' + p.label + ' - ' + p.desc);
    WSP.ui.navigate('home', {}, { resetHistory: true, animate: false });
    WSP.ui.toast('시연 프리셋: ' + p.label);
  }

  root.addEventListener('click', async (e) => {
    const b = e.target.closest('[data-dp]');
    if (!b) return;
    const kind = b.dataset.dp;
    if (kind === 'reset') WSP.app.resetDemo();
    else if (kind === 'preset') applyPreset(b.dataset.id);
    else if (kind === 'outcome') {
      const v = b.dataset.v;
      store.update((d) => (d.simulation.nextTransferOutcome = v), '[시연] 다음 거래 결과 → ' + v);
    } else if (kind === 'resolve') {
      bank.demoResolveTransaction(b.dataset.id, b.dataset.v);
    } else if (kind === 'selftest') {
      if (!WSP.selfTest) return;
      b.disabled = true;
      $('#dp-tests').innerHTML = '<span class="dp-note">실행 중...</span>';
      try {
        const report = await WSP.selfTest.run();
        renderTests(report);
      } finally {
        b.disabled = false;
      }
    }
  });

  root.addEventListener('change', (e) => {
    const sw = e.target.closest('[data-dp-switch]');
    if (sw) {
      const def = SWITCHES.find((s) => s[0] === sw.dataset.dpSwitch);
      const v = sw.checked;
      store.update((d) => def[3](d, v), '[시연] ' + def[1] + ' → ' + (v ? 'ON' : 'OFF'));
      return;
    }
    if (e.target.id === 'dp-limit') {
      const v = Number(e.target.value);
      store.update((d) => (d.customer.transferLimit = v), '[시연] 1일 이체한도 → ' + fmt(v));
    }
  });

  function renderTests(report) {
    const el = $('#dp-tests');
    const head =
      '<div class="' +
      (report.failed ? 'fail' : 'pass') +
      '" style="font-weight:700;margin-bottom:4px">' +
      report.passed +
      ' / ' +
      report.total +
      ' 통과' +
      (report.failed ? ' · ' + report.failed + ' 실패' : '') +
      '</div>';
    el.innerHTML =
      head +
      report.results
        .map((r) => '<div class="' + (r.ok ? 'pass' : 'fail') + '">' + (r.ok ? '✔ ' : '✘ ') + esc(r.name) + (r.ok ? '' : ' — ' + esc(r.detail || '')) + '</div>')
        .join('');
  }

  /* ---------- 그래프 렌더링 (SVG) ---------- */

  const SVG_DEFS =
    '<defs>' +
    '<marker id="dp-arr" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L8 4L0 8z" fill="#3a4a60"/></marker>' +
    '<marker id="dp-arr-hl" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L8 4L0 8z" fill="#3fa2e8"/></marker>' +
    '</defs>';

  /** 중심 c에서 방향 (dx,dy)로 w×h 사각형 경계까지의 거리 */
  function rectExit(dx, dy, w, h) {
    const ax = Math.abs(dx) || 1e-9;
    const ay = Math.abs(dy) || 1e-9;
    return Math.min(w / 2 / ax, h / 2 / ay);
  }

  /** 두 사각형 노드를 잇는 곡선 간선. bend는 진행 방향 기준 오른쪽으로 휘는 정도 */
  function curve(a, b, w, h, bend) {
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const len = Math.hypot(dx, dy) || 1;
    const ux = dx / len;
    const uy = dy / len;
    const s = rectExit(ux, uy, w, h) + 2;
    const e = rectExit(ux, uy, w, h) + 4;
    const x1 = a.x + ux * s;
    const y1 = a.y + uy * s;
    const x2 = b.x - ux * e;
    const y2 = b.y - uy * e;
    const cx = (x1 + x2) / 2 - uy * bend;
    const cy = (y1 + y2) / 2 + ux * bend;
    return { d: 'M' + x1.toFixed(1) + ' ' + y1.toFixed(1) + ' Q' + cx.toFixed(1) + ' ' + cy.toFixed(1) + ' ' + x2.toFixed(1) + ' ' + y2.toFixed(1), lx: (x1 + 2 * cx + x2) / 4, ly: (y1 + 2 * cy + y2) / 4 };
  }

  const FSM_POS = {
    IDLE: { x: 70, y: 28 },
    DIAGNOSING: { x: 215, y: 28 },
    PLAN_READY: { x: 375, y: 28 },
    WAITING_USER: { x: 530, y: 28 },
    READY_TO_RETRY: { x: 215, y: 108 },
    RECHECKING: { x: 450, y: 108 },
    COMPLETED: { x: 70, y: 188 },
    VERIFYING: { x: 215, y: 188 },
    ESCALATED: { x: 450, y: 188 },
    RESULT_UNCERTAIN: { x: 215, y: 268 },
  };
  /** 다른 노드를 가로지르는 간선만 더 크게 휘게 한다 */
  const FSM_BEND = { 'ESCALATED>IDLE': 60 };

  /** 전이 테이블을 그대로 그래프로 그린다. 현재 상태와 마지막 전이를 강조한다. */
  function renderFsmGraph(cur, history) {
    const W = 118;
    const H = 28;
    const last = history.length ? history[history.length - 1] : null;
    const visited = new Set();
    history.forEach((h) => {
      visited.add(h.from);
      visited.add(h.to);
    });
    const pairs = new Map();
    Object.keys(WSP.FSM_TRANSITIONS).forEach((from) => {
      const t = WSP.FSM_TRANSITIONS[from];
      Object.keys(t).forEach((ev) => {
        const k = from + '>' + t[ev];
        if (!pairs.has(k)) pairs.set(k, { from: from, to: t[ev], events: [] });
        pairs.get(k).events.push(ev);
      });
    });
    let edgesSvg = '';
    let hlSvg = '';
    pairs.forEach((p) => {
      const k = p.from + '>' + p.to;
      const c = curve(FSM_POS[p.from], FSM_POS[p.to], W, H, FSM_BEND[k] != null ? FSM_BEND[k] : 14);
      const isLast = last && last.from === p.from && last.to === p.to;
      const isEsc = p.events.length === 1 && p.events[0] === 'ESCALATE';
      const title = '<title>' + p.from + ' → ' + p.to + ' : ' + p.events.join(', ') + '</title>';
      const label = (cls, text) => '<text x="' + c.lx.toFixed(1) + '" y="' + (c.ly - 4).toFixed(1) + '" class="g-elabel' + cls + '">' + esc(text) + '</text>';
      if (isLast) {
        hlSvg += '<path d="' + c.d + '" class="g-edge is-hl" marker-end="url(#dp-arr-hl)">' + title + '</path>' + label(' is-hl', last.event);
      } else {
        edgesSvg += '<path d="' + c.d + '" class="g-edge' + (isEsc ? ' is-dashed' : '') + '" marker-end="url(#dp-arr)">' + title + '</path>';
        if (p.events.indexOf('NEW_CASE') !== -1) edgesSvg += label('', 'NEW_CASE');
      }
    });
    const nodesSvg = WSP.FSM_STATES.map((st) => {
      const p = FSM_POS[st];
      const cls = st === cur ? ' is-current' : visited.has(st) ? ' is-visited' : '';
      return (
        '<g class="g-node' + cls + '"><rect x="' + (p.x - W / 2) + '" y="' + (p.y - H / 2) + '" width="' + W + '" height="' + H + '" rx="7"/>' +
        '<text x="' + p.x + '" y="' + (p.y + 3.5) + '">' + st + '</text></g>'
      );
    }).join('');
    return '<svg viewBox="0 0 600 296" class="dp-svg" role="img" aria-label="상태머신 그래프">' + SVG_DEFS + edgesSvg + hlSvg + nodesSvg + '</svg>';
  }

  const FACT_SHORT = [
    ['kycCompleted', 'KYC'],
    ['otpRegistered', 'OTP'],
    ['limitSufficient', '한도'],
    ['returnedToTransfer', '복귀'],
  ];

  /** 경로 탐색이 만든 상태 그래프와 다익스트라 최소 비용 경로를 그린다. */
  function renderStateGraph(last) {
    if (!last) return '<span class="dp-note">아직 계산된 경로가 없어요. 앱에서 이체를 시도하세요.</span>';
    if (!last.graph) {
      return '<span class="dp-note">차단 사유(' + esc(last.blocker ? last.blocker.code : last.status) + ')가 있어 상태 그래프를 만들지 않았어요. 자동 해결 경로 대신 상담으로 안내합니다.</span>';
    }
    const g = last.graph;
    const shown = FACT_SHORT.filter(([k]) => new Set(g.nodes.map((n) => n.facts[k])).size > 1 || k === 'returnedToTransfer');
    const byDepth = [];
    g.nodes.forEach((n) => {
      (byDepth[n.depth] = byDepth[n.depth] || []).push(n);
    });
    const cols = byDepth.length;
    const rows = Math.max.apply(null, byDepth.map((c) => c.length));
    const NW = Math.max(100, shown.length * 31 + 12);
    const NH = 44;
    const colGap = NW + 80;
    const VW = Math.max(600, NW + colGap * (cols - 1) + 24);
    const VH = rows * 66 + 34;
    const pos = {};
    byDepth.forEach((col, d) => {
      col.forEach((n, i) => {
        pos[n.key] = { x: 12 + NW / 2 + d * colGap, y: 22 + ((i + 0.5) * (VH - 34)) / col.length };
      });
    });
    const onPathNodes = new Set([g.startKey]);
    g.edges.forEach((e) => {
      if (e.onPath) onPathNodes.add(e.to);
    });
    let edgesSvg = '';
    let hlSvg = '';
    g.edges.forEach((e) => {
      const c = curve(pos[e.from], pos[e.to], NW, NH, e.onPath ? 0 : 10);
      const label = (ACTION_SHORT[e.actionId] || e.actionId) + ' · ' + e.weight;
      const svg =
        '<path d="' + c.d + '" class="g-edge' + (e.onPath ? ' is-hl' : '') + '" marker-end="url(#' + (e.onPath ? 'dp-arr-hl' : 'dp-arr') + ')"><title>' + e.actionId + ' (weight ' + e.weight + ')</title></path>' +
        '<text x="' + c.lx.toFixed(1) + '" y="' + (c.ly - 5).toFixed(1) + '" class="g-elabel' + (e.onPath ? ' is-hl' : '') + '">' + esc(label) + '</text>';
      if (e.onPath) hlSvg += svg;
      else edgesSvg += svg;
    });
    const nodesSvg = g.nodes
      .map((n) => {
        const p = pos[n.key];
        const facts = shown.map(([k, s]) => s + (n.facts[k] ? '✓' : '✗')).join(' ');
        const cls = n.key === g.startKey ? ' is-start' : n.goal ? ' is-goal' : onPathNodes.has(n.key) ? ' is-visited' : '';
        const sub = n.key === g.startKey ? '현재 · d=0' : (n.goal ? '목표 · ' : '') + (n.dist == null ? '미탐색' : 'd=' + n.dist);
        return (
          '<g class="g-node' + cls + '"><rect x="' + (p.x - NW / 2) + '" y="' + (p.y - NH / 2) + '" width="' + NW + '" height="' + NH + '" rx="8"/>' +
          '<text x="' + p.x + '" y="' + (p.y - 3) + '">' + esc(facts) + '</text>' +
          '<text x="' + p.x + '" y="' + (p.y + 12) + '" class="g-sub">' + esc(sub) + '</text></g>'
        );
      })
      .join('');
    return '<svg viewBox="0 0 ' + VW + ' ' + VH + '" class="dp-svg" role="img" aria-label="해결 경로 상태 그래프">' + SVG_DEFS + edgesSvg + hlSvg + nodesSvg + '</svg>';
  }

  /* ---------- 동기화 ---------- */

  let raf = 0;
  function scheduleSync() {
    if (raf) return;
    raf = requestAnimationFrame(() => {
      raf = 0;
      sync();
    });
  }

  function sync() {
    const s = store.getState();
    SWITCHES.forEach((def) => {
      const input = root.querySelector('[data-dp-switch="' + def[0] + '"]');
      if (input) input.checked = !!def[2](s);
    });
    const sel = $('#dp-limit');
    if (LIMITS.indexOf(s.customer.transferLimit) === -1) {
      if (!sel.querySelector('option[value="' + s.customer.transferLimit + '"]')) {
        sel.insertAdjacentHTML('beforeend', '<option value="' + s.customer.transferLimit + '">' + fmt(s.customer.transferLimit) + '</option>');
      }
    }
    sel.value = String(s.customer.transferLimit);

    root.querySelectorAll('[data-dp="outcome"]').forEach((b) => b.classList.toggle('is-active', b.dataset.v === s.simulation.nextTransferOutcome));

    const open = Object.keys(s.transactions)
      .map((k) => s.transactions[k])
      .filter((t) => t.status === 'PENDING' || t.status === 'UNKNOWN');
    $('#dp-pending').innerHTML = open.length
      ? open
          .map(
            (t) =>
              '<div class="dp-row"><span>' +
              esc(t.id) +
              ' · ' +
              t.status +
              '</span><span><button class="dp-btn" data-dp="resolve" data-id="' +
              t.id +
              '" data-v="SUCCESS">은행 확정 SUCCESS</button> <button class="dp-btn" data-dp="resolve" data-id="' +
              t.id +
              '" data-v="FAILED">FAILED</button></span></div>'
          )
          .join('') + '<div class="dp-note">은행 측 처리 확정을 시뮬레이션합니다. 앱에서는 사용자가 결과 조회를 눌러야 반영됩니다.</div>'
      : '';

    const cur = fsm.state;
    $('#dp-fsm-cur').innerHTML = '<span style="color:#7cc4ff;font-family:var(--mono)">' + cur + '</span>';
    const fullHist = fsm.history();
    $('#dp-fsm').innerHTML = renderFsmGraph(cur, fullHist);
    const hist = fullHist.slice(-8).reverse();
    $('#dp-fsm-hist').innerHTML = hist.length
      ? hist.map((h) => '<div><span class="t">' + h.at.slice(11, 19) + '</span> ' + h.from + ' <span class="s">--' + h.event + '--></span> ' + h.to + '</div>').join('')
      : '<div class="t">전이 기록 없음</div>';

    const last = WSP.pathfinder.getLastResult();
    const sgKey = last ? last.computedAt : 0;
    if ($('#dp-sg').dataset.key !== String(sgKey)) {
      $('#dp-sg').dataset.key = String(sgKey);
      $('#dp-sg').innerHTML = renderStateGraph(last);
    }
    if (!last) $('#dp-path').innerHTML = '';
    else {
      const chain = last.steps.length
        ? last.steps.map((st) => st.actionId).join(' <span class="arrow">→</span> ')
        : last.fallback
        ? '<span style="color:#fbbf24">' + last.fallback.id + '</span>'
        : '-';
      const ev = last.evaluation;
      $('#dp-path').innerHTML =
        '<div>상태: <b>' +
        last.status +
        '</b>' +
        (last.blocker ? ' (' + esc(last.blocker.code) + ')' : '') +
        (last.cost != null ? ' · 최소 비용 <b>' + last.cost + '</b>' : '') +
        '</div><div>' +
        chain +
        '</div><div class="dp-note">상태 그래프 ' +
        last.visited +
        '개 노드 · 다익스트라 확정 ' +
        last.explored +
        '개' +
        (ev ? ' · 발동 규칙 ' + (ev.firedRules.join(', ') || '없음') : '') +
        '</div>';
    }

    $('#dp-ver').innerHTML = '<span style="font-family:var(--mono);color:#7cc4ff">v' + s.system.stateVersion + '</span>';
    $('#dp-json').textContent = JSON.stringify(s, null, 2);

    const logs = events.list().slice(-60).reverse();
    $('#dp-log').innerHTML = logs
      .map((l) => '<div title="' + esc(l.message) + '"><span class="t">' + l.at.slice(11, 19) + '</span> <span class="s">' + l.source + '</span> ' + esc(l.message) + '</div>')
      .join('');
  }

  store.subscribe(scheduleSync);
  fsm.subscribe(scheduleSync);
  events.subscribe(scheduleSync);
  sync();

  /* ---------- 표시/숨김 ---------- */

  const fab = document.createElement('button');
  fab.className = 'dp-toggle-fab';
  fab.type = 'button';
  fab.textContent = 'DEMO';
  fab.addEventListener('click', togglePanel);
  document.body.appendChild(fab);
  if (/[?&]demo=1/.test(location.search)) fab.classList.add('is-visible');

  function togglePanel() {
    if (window.matchMedia('(max-width: 900px)').matches) {
      root.classList.toggle('is-open');
      fab.classList.add('is-visible');
    } else {
      root.parentElement.classList.toggle('is-panel-hidden');
    }
  }

  document.addEventListener('keydown', (e) => {
    if (e.shiftKey && (e.key === 'D' || e.key === 'd') && !/input|textarea|select/i.test(e.target.tagName)) {
      e.preventDefault();
      togglePanel();
    }
  });
})();
