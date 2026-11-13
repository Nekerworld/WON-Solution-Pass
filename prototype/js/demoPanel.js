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
  const SC = WSP.scenario;
  const bank = WSP.mockBank;
  const events = WSP.events;
  const esc = WSP.ui.esc;
  const AA = WSP.assetAdvisor;

  const root = document.getElementById('demo-panel');
  if (!root) return;

  const PRESETS = [
    { id: 'base', label: '기본 첫 거래', desc: '우리은행 첫 거래 고객. AI 대화에서 "신분증이 없어요"라고 답해 보세요.', apply: () => {} },
    {
      id: 'allmet',
      label: '모두 충족',
      desc: '가입 조건을 모두 갖춘 고객 → 바로 가입 준비 완료',
      apply: (d) => Object.keys(d.facts).forEach((k) => (d.facts[k] = true)),
    },
    { id: 'cycle', label: '순환', desc: '다른 은행 계좌 없음. "없어요"라고 답하면 계좌↔인증서 순환 → 상담 연결', apply: (d) => (d.finance.otherBankAccounts = []) },
    { id: 'delay', label: '처리 지연', desc: '다음 업무가 은행에서 처리 중 상태로 남음 → 결과 다시 확인', apply: (d) => (d.simulation.nextTaskOutcome = 'IN_PROGRESS') },
    { id: 'mismatch', label: '완료 불일치 반복', desc: '업무 화면은 완료인데 은행 기록 미반영이 반복 → 2회 후 상담', apply: (d) => (d.simulation.nextTaskOutcome = 'MISMATCH_ALWAYS') },
    { id: 'unknown', label: '결과 불명', desc: '가입 요청 결과가 확인되지 않음 → 재신청 없이 결과 조회만', apply: (d) => (d.simulation.nextApplicationOutcome = 'UNKNOWN') },
    {
      id: 'lowinfo',
      label: '정보 부족',
      desc: '소득·지출 미확인. 질문에 "잘 모르겠어요" → 제안 보류',
      apply: (d) => {
        d.finance.linked = ['가상 B카드'];
        d.finance.notLinked = ['가상 A은행(급여)', '증권사', '보험사', '부동산·현금'];
        d.finance.items.monthlyIncome = { value: null, source: 'UNKNOWN', basis: '급여 계좌 미연결' };
        d.finance.items.monthlyExpense = { value: null, source: 'UNKNOWN', basis: '주 사용 계좌 미연결' };
      },
    },
    { id: 'consultfail', label: '상담 접수 실패', desc: '상담 접수가 실패 → 요약 생성과 접수 완료 구분, 후속 안내', apply: (d) => (d.simulation.nextConsultOutcome = 'FAILED') },
  ];

  const FACT_SWITCHES = Object.keys(SC.FACTS).map((k) => [k, SC.FACTS[k].label, (s) => s.facts[k], (d, v) => (d.facts[k] = v)]);
  const SYS_SWITCHES = [
    ['bank', '은행 시스템 정상', (s) => s.system.bankAvailable, (d, v) => (d.system.bankAvailable = v)],
    ['queryFailure', '조회 실패 주입', (s) => s.simulation.queryFailure, (d, v) => (d.simulation.queryFailure = v)],
  ];
  const SWITCHES = FACT_SWITCHES.concat(SYS_SWITCHES);

  const TASK_OUTCOMES = [
    ['NORMAL', '정상'],
    ['ERROR', '오류'],
    ['IN_PROGRESS', '처리 중'],
    ['PARTIAL', '일부만'],
    ['MISMATCH', '불일치 1회'],
    ['MISMATCH_ALWAYS', '불일치 반복'],
  ];
  const APP_OUTCOMES = ['SUCCESS', 'FAILED', 'PENDING', 'UNKNOWN'];
  const CONSULT_OUTCOMES = ['ACCEPTED', 'FAILED'];
  const SPEEDS = [
    [0.3, '빠르게'],
    [1, '보통'],
    [1.8, '느리게'],
  ];

  const TRACKS = [
    ['join', '가입 지원(AI)'],
    ['direct', '직접 가입'],
    ['asset', '자산관리'],
  ];
  let track = 'join';
  /** 탭을 직접 고르기 전까지는 방금 상태가 바뀐 트랙을 따라간다 */
  let trackPinned = false;
  let showExit = false;

  const ACTION_SHORT = {
    ID_CARD_VERIFY: '신분증',
    MOBILE_ID_VERIFY: '모바일신분증',
    OPEN_ACCOUNT_OTHERBANK: '계좌(타행)',
    OPEN_ACCOUNT_CERT: '계좌(인증서)',
    ISSUE_CERT: '인증서',
    KYC_UPDATE: '고객정보',
  };

  root.innerHTML =
    '<div class="dp-head"><div><div class="dp-head__title">DEMO CONTROL</div><div class="dp-head__sub">시연용 도구 · 실제 앱 기능 아님 · Shift+D</div></div>' +
    '<button class="dp-btn dp-btn--danger" data-dp="reset">데모 초기화</button></div>' +
    '<div class="dp-body">' +
    '<div class="dp-col dp-col--controls">' +
    '<div class="dp-section"><div class="dp-section__title">시나리오 프리셋 <span class="dp-tag">' +
    esc(SC.POLICY.version) +
    '</span></div><div class="dp-grid dp-grid--4">' +
    PRESETS.map((p) => '<button class="dp-btn" data-dp="preset" data-id="' + p.id + '" title="' + esc(p.desc) + '">' + esc(p.label) + '</button>').join('') +
    '</div><div class="dp-note" id="dp-preset-desc">프리셋은 데모를 초기화한 뒤 가상 은행 상태를 설정합니다.</div></div>' +
    '<div class="dp-section"><div class="dp-section__title">은행 사실 (가입 조건)</div>' +
    SWITCHES.map(
      (s) =>
        '<div class="dp-row"><label for="dp-sw-' +
        s[0] +
        '">' +
        esc(s[1]) +
        '</label><span class="dp-switch"><input type="checkbox" id="dp-sw-' +
        s[0] +
        '" data-dp-switch="' +
        s[0] +
        '"><span></span></span></div>'
    ).join('') +
    '</div>' +
    '<div class="dp-section"><div class="dp-section__title">다음 결과 주입 (가상 은행 응답)</div>' +
    '<div class="dp-sub">업무 화면</div><div class="dp-grid">' +
    TASK_OUTCOMES.map((o) => '<button class="dp-btn" data-dp="task-outcome" data-v="' + o[0] + '">' + esc(o[1]) + '</button>').join('') +
    '</div><div class="dp-sub">가입 요청</div><div class="dp-grid dp-grid--4">' +
    APP_OUTCOMES.map((o) => '<button class="dp-btn" data-dp="app-outcome" data-v="' + o + '">' + o + '</button>').join('') +
    '</div><div id="dp-pending"></div><div class="dp-sub">상담 접수</div><div class="dp-grid dp-grid--2">' +
    CONSULT_OUTCOMES.map((o) => '<button class="dp-btn" data-dp="consult-outcome" data-v="' + o + '">' + o + '</button>').join('') +
    '</div><div class="dp-sub">AI 출력</div><button class="dp-btn" data-dp="ai-invalid" style="width:100%">다음 AI 출력에 규칙 위반 주입 (검증 → 기본 선택지)</button></div>' +
    '<div class="dp-section"><div class="dp-section__title">응답 속도</div><div class="dp-grid">' +
    SPEEDS.map((s) => '<button class="dp-btn" data-dp="speed" data-v="' + s[0] + '">' + s[1] + '</button>').join('') +
    '</div></div>' +
    '<div class="dp-section"><div class="dp-section__title">AI vs 직접 가입 비교</div><div id="dp-compare"></div></div>' +
    '<div class="dp-section"><div class="dp-section__title">자가 테스트 <button class="dp-btn dp-btn--primary" data-dp="selftest">실행</button></div><div class="dp-tests" id="dp-tests"><span class="dp-note">계획 7장 검증 항목을 브라우저 안에서 실행합니다. 실행 전 상태는 자동 복원됩니다.</span></div></div>' +
    '</div>' +
    '<div class="dp-col dp-col--observe">' +
    '<div class="dp-section"><div class="dp-section__title">상태머신 <span id="dp-fsm-cur"></span></div>' +
    '<div class="dp-tabs">' +
    TRACKS.map((t) => '<button class="dp-btn" data-dp="track" data-v="' + t[0] + '">' + t[1] + '</button>').join('') +
    '<button class="dp-btn" data-dp="exit-toggle" title="공통 종료(P8) 간선 표시">종료 간선</button></div>' +
    '<div class="dp-graph" id="dp-fsm"></div><div class="dp-legend"><span><i class="lg-d"></i>워크플로우</span><span><i class="lg-p"></i>제안 전이(P1~P8)</span><span><i class="lg-s"></i>안전 전이</span></div>' +
    '<div class="dp-log mt-8" id="dp-fsm-hist" style="max-height:96px"></div></div>' +
    '<div class="dp-section"><div class="dp-section__title">가입 조건 판정 · 고객 제약</div><div id="dp-cond"></div></div>' +
    '<div class="dp-section"><div class="dp-section__title">해결 경로 · 상태 그래프 (다익스트라)</div><div class="dp-graph" id="dp-sg"></div><div class="dp-path mt-8" id="dp-path"></div></div>' +
    '<div class="dp-section"><div class="dp-section__title">AI 구조화 출력 · 검증 <span id="dp-ai-count" class="dp-tag"></span></div><div id="dp-ai"></div></div>' +
    '<div class="dp-section"><div class="dp-section__title">자산 정보 저장소 · 지표</div><div id="dp-info"></div></div>' +
    '<div class="dp-section"><div class="dp-section__title">은행 상태 JSON <span id="dp-ver"></span></div><pre class="dp-pre" id="dp-json"></pre></div>' +
    '<div class="dp-section"><div class="dp-section__title">이벤트 로그</div><div class="dp-log" id="dp-log"></div></div>' +
    '</div></div>';

  const $ = (sel) => root.querySelector(sel);

  /* ---------- 동작 ---------- */
  function applyPreset(id) {
    const p = PRESETS.find((x) => x.id === id);
    if (!p) return;
    WSP.app.resetDemo();
    store.update((d) => p.apply(d), '[시연] 프리셋 ' + p.label + ' - ' + p.desc);
    WSP.ui.rerender();
    $('#dp-preset-desc').textContent = p.label + ': ' + p.desc;
    WSP.ui.toast('시연 프리셋: ' + p.label);
  }

  root.addEventListener('click', async (e) => {
    const b = e.target.closest('[data-dp]');
    if (!b) return;
    const kind = b.dataset.dp;
    const v = b.dataset.v;
    if (kind === 'reset') {
      WSP.app.resetDemo();
      $('#dp-preset-desc').textContent = '데모를 초기화했어요.';
    } else if (kind === 'preset') applyPreset(b.dataset.id);
    else if (kind === 'task-outcome') store.update((d) => (d.simulation.nextTaskOutcome = v), '[시연] 다음 업무 결과 → ' + v);
    else if (kind === 'app-outcome') store.update((d) => (d.simulation.nextApplicationOutcome = v), '[시연] 다음 가입 결과 → ' + v);
    else if (kind === 'consult-outcome') store.update((d) => (d.simulation.nextConsultOutcome = v), '[시연] 다음 상담 접수 결과 → ' + v);
    else if (kind === 'ai-invalid') {
      WSP.aiAgent.injectInvalidNext();
      events.add('DEMO', '다음 AI 출력에 규칙 위반(가입 실행 도구·완료 단정) 주입');
    } else if (kind === 'resolve') bank.demoResolveApplication(b.dataset.id, v);
    else if (kind === 'speed') {
      bank.setLatencyScale(Number(v));
      events.add('DEMO', '응답 속도 배율 → ' + v);
    } else if (kind === 'track') {
      track = v;
      trackPinned = true;
    }
    else if (kind === 'exit-toggle') showExit = !showExit;
    else if (kind === 'selftest') {
      if (!WSP.selfTest) return;
      b.disabled = true;
      $('#dp-tests').innerHTML = '<span class="dp-note">실행 중...</span>';
      try {
        renderTests(await WSP.selfTest.run());
      } finally {
        b.disabled = false;
      }
    }
    scheduleSync();
  });

  root.addEventListener('change', (e) => {
    const sw = e.target.closest('[data-dp-switch]');
    if (!sw) return;
    const def = SWITCHES.find((s) => s[0] === sw.dataset.dpSwitch);
    const v = sw.checked;
    store.update((d) => def[3](d, v), '[시연] ' + def[1] + ' → ' + (v ? 'ON' : 'OFF'));
  });

  function renderTests(report) {
    $('#dp-tests').innerHTML =
      '<div class="' +
      (report.failed ? 'fail' : 'pass') +
      '" style="font-weight:700;margin-bottom:4px">' +
      report.passed +
      ' / ' +
      report.total +
      ' 통과' +
      (report.failed ? ' · ' + report.failed + ' 실패' : '') +
      '</div>' +
      report.results.map((r) => '<div class="' + (r.ok ? 'pass' : 'fail') + '">' + (r.ok ? '✔ ' : '✘ ') + esc(r.name) + (r.ok ? '' : ' — ' + esc(r.detail || '')) + '</div>').join('');
  }

  /* ---------- 그래프 (SVG) ---------- */
  const SVG_DEFS =
    '<defs>' +
    '<marker id="dp-arr" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M0 0L8 4L0 8z" fill="#3a4a60"/></marker>' +
    '<marker id="dp-arr-p" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="6" markerHeight="6" orient="auto-start-reverse"><path d="M0 0L8 4L0 8z" fill="#d69a2d"/></marker>' +
    '<marker id="dp-arr-hl" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0 0L8 4L0 8z" fill="#3fa2e8"/></marker>' +
    '</defs>';

  function rectExit(dx, dy, w, h) {
    const ax = Math.abs(dx) || 1e-9;
    const ay = Math.abs(dy) || 1e-9;
    return Math.min(w / 2 / ax, h / 2 / ay);
  }

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

  /** 전이 테이블에서 BFS 깊이로 층을 나눠 위→아래로 배치한다 */
  const layoutCache = {};
  function layout(kind) {
    if (layoutCache[kind]) return layoutCache[kind];
    const def = WSP.FSM_DEFS[kind];
    const tbl = WSP.FSM_TABLES[kind];
    const depth = { [def.initial]: 0 };
    const q = [def.initial];
    while (q.length) {
      const s = q.shift();
      const row = tbl.table[s] || {};
      Object.keys(row).forEach((ev) => {
        if (ev === 'EXIT' || ev === 'NEW_CASE') return;
        const t = row[ev];
        if (depth[t] == null) {
          depth[t] = depth[s] + 1;
          q.push(t);
        }
      });
    }
    const layers = [];
    tbl.states.forEach((s) => {
      const d = depth[s] != null ? depth[s] : 0;
      (layers[d] = layers[d] || []).push(s);
    });
    const W = 112;
    const H = 24;
    const maxCols = Math.max.apply(null, layers.map((l) => l.length));
    const VW = Math.max(560, maxCols * (W + 16) + 16);
    const rowGap = 46;
    const pos = {};
    layers.forEach((l, d) => {
      l.forEach((s, i) => {
        pos[s] = { x: ((i + 0.5) * VW) / l.length, y: 20 + d * rowGap };
      });
    });
    layoutCache[kind] = { pos: pos, W: W, H: H, VW: VW, VH: 20 + (layers.length - 1) * rowGap + 22 };
    return layoutCache[kind];
  }

  function renderFsmGraph(kind, cur, history) {
    const L = layout(kind);
    const def = WSP.FSM_DEFS[kind];
    const last = history.length ? history[history.length - 1] : null;
    const visited = new Set();
    history.forEach((h) => {
      visited.add(h.from);
      visited.add(h.to);
    });
    const pairs = new Map();
    let hidden = 0;
    def.edges.forEach((e) => {
      if (!showExit && e[1] === 'EXIT') {
        hidden += 1;
        return;
      }
      const k = e[0] + '>' + e[2];
      if (!pairs.has(k)) pairs.set(k, { from: e[0], to: e[2], events: [], src: e[3] });
      const p = pairs.get(k);
      p.events.push(e[1]);
      if (e[3] !== 'D') p.src = e[3];
    });
    let edges = '';
    let hl = '';
    pairs.forEach((p) => {
      const a = L.pos[p.from];
      const b = L.pos[p.to];
      const back = b.y <= a.y;
      const c = curve(a, b, L.W, L.H, back ? 40 : 10);
      const isLast = last && last.from === p.from && last.to === p.to;
      const cls = p.src === 'D' ? '' : p.src === 'S' ? ' is-safety' : ' is-proposal';
      const title = '<title>' + p.from + ' → ' + p.to + ' : ' + p.events.join(', ') + ' [' + p.src + ']</title>';
      if (isLast) {
        hl +=
          '<path d="' +
          c.d +
          '" class="g-edge is-hl" marker-end="url(#dp-arr-hl)">' +
          title +
          '</path><text x="' +
          c.lx.toFixed(1) +
          '" y="' +
          (c.ly - 4).toFixed(1) +
          '" class="g-elabel is-hl">' +
          esc(last.event + (last.src && last.src !== 'D' ? ' (' + last.src + ')' : '')) +
          '</text>';
      } else edges += '<path d="' + c.d + '" class="g-edge' + cls + '" marker-end="url(#' + (cls === ' is-proposal' ? 'dp-arr-p' : 'dp-arr') + ')">' + title + '</path>';
    });
    const nodes = WSP.FSM_TABLES[kind].states
      .map((st) => {
        const p = L.pos[st];
        const cls = st === cur ? ' is-current' : visited.has(st) ? ' is-visited' : '';
        return (
          '<g class="g-node' +
          cls +
          '"><rect x="' +
          (p.x - L.W / 2) +
          '" y="' +
          (p.y - L.H / 2) +
          '" width="' +
          L.W +
          '" height="' +
          L.H +
          '" rx="6"/><text x="' +
          p.x +
          '" y="' +
          (p.y + 3.5) +
          '">' +
          st +
          '</text></g>'
        );
      })
      .join('');
    return (
      '<svg viewBox="0 0 ' +
      L.VW +
      ' ' +
      L.VH +
      '" class="dp-svg" role="img" aria-label="상태머신 그래프">' +
      SVG_DEFS +
      edges +
      hl +
      nodes +
      '</svg>' +
      (hidden ? '<div class="dp-note">공통 종료(P8) 간선 ' + hidden + '개 생략 · "종료 간선"으로 표시</div>' : '')
    );
  }

  function renderStateGraph(last) {
    if (!last) return '<span class="dp-note">아직 계산된 경로가 없어요. AI 가입 지원을 시작하세요.</span>';
    if (!last.graph) return '<span class="dp-note">' + esc(last.status) + ': 상태 그래프를 만들지 않았어요.</span>';
    const g = last.graph;
    const keys = Object.keys(SC.FACTS).filter((k) => new Set(g.nodes.map((n) => !!n.facts[k])).size > 1);
    const byDepth = [];
    g.nodes.forEach((n) => (byDepth[n.depth] = byDepth[n.depth] || []).push(n));
    const cols = byDepth.length;
    const rows = Math.max.apply(null, byDepth.map((c) => c.length));
    const NW = Math.max(96, keys.length * 34 + 12);
    const NH = 40;
    const colGap = NW + 64;
    const VW = Math.max(560, NW + colGap * (cols - 1) + 24);
    const VH = rows * 60 + 30;
    const pos = {};
    byDepth.forEach((col, d) => col.forEach((n, i) => (pos[n.key] = { x: 12 + NW / 2 + d * colGap, y: 18 + ((i + 0.5) * (VH - 30)) / col.length })));
    const onPath = new Set([g.startKey]);
    g.edges.forEach((e) => e.onPath && onPath.add(e.to));
    let edges = '';
    let hl = '';
    g.edges.forEach((e) => {
      const c = curve(pos[e.from], pos[e.to], NW, NH, e.onPath ? 0 : 10);
      const svg =
        '<path d="' +
        c.d +
        '" class="g-edge' +
        (e.onPath ? ' is-hl' : e.unknown ? ' is-dashed' : '') +
        '" marker-end="url(#' +
        (e.onPath ? 'dp-arr-hl' : 'dp-arr') +
        ')"><title>' +
        e.actionId +
        ' (weight ' +
        e.weight +
        (e.unknown ? ', 고객 제약 미확인' : '') +
        ')</title></path><text x="' +
        c.lx.toFixed(1) +
        '" y="' +
        (c.ly - 5).toFixed(1) +
        '" class="g-elabel' +
        (e.onPath ? ' is-hl' : '') +
        '">' +
        esc((ACTION_SHORT[e.actionId] || e.actionId) + '·' + e.weight) +
        '</text>';
      if (e.onPath) hl += svg;
      else edges += svg;
    });
    const nodes = g.nodes
      .map((n) => {
        const p = pos[n.key];
        const facts = keys.map((k) => SC.FACTS[k].short + (n.facts[k] ? '✓' : '✗')).join(' ');
        const cls = n.key === g.startKey ? ' is-start' : n.goal ? ' is-goal' : onPath.has(n.key) ? ' is-visited' : '';
        const sub = n.key === g.startKey ? '현재 · d=0' : (n.goal ? '목표 · ' : '') + (n.dist == null ? '미탐색' : 'd=' + n.dist);
        return (
          '<g class="g-node' +
          cls +
          '"><rect x="' +
          (p.x - NW / 2) +
          '" y="' +
          (p.y - NH / 2) +
          '" width="' +
          NW +
          '" height="' +
          NH +
          '" rx="8"/><text x="' +
          p.x +
          '" y="' +
          (p.y - 3) +
          '">' +
          esc(facts) +
          '</text><text x="' +
          p.x +
          '" y="' +
          (p.y + 11) +
          '" class="g-sub">' +
          esc(sub) +
          '</text></g>'
        );
      })
      .join('');
    return '<svg viewBox="0 0 ' + VW + ' ' + VH + '" class="dp-svg" role="img" aria-label="해결 경로 상태 그래프">' + SVG_DEFS + edges + hl + nodes + '</svg>';
  }

  /* ---------- 관찰 영역 ---------- */
  const STATUS_COLOR = { MET: '#4ade80', UNMET: '#f87171', UNKNOWN: '#9aa5b4', IN_PROGRESS: '#fbbf24' };

  function condHtml(s) {
    const j = WSP.app.session.join;
    const ev = j && j.evaluation ? j.evaluation : null;
    const product = SC.getProduct(j ? j.productId : SC.PRODUCTS[0].id);
    const rows = product.conditions
      .map((id) => {
        const c = SC.CONDITIONS[id];
        const fromEv = ev ? ev.conditions.find((x) => x.id === id) : null;
        const st = fromEv ? fromEv.status : null;
        return (
          '<tr><td>' +
          esc(c.label) +
          '</td><td class="mono">' +
          c.fact +
          '</td><td class="mono">' +
          (s.facts[c.fact] ? 'true' : 'false') +
          (s.pending[c.fact] ? ' (처리 중)' : '') +
          '</td><td>' +
          (st ? '<b style="color:' + STATUS_COLOR[st] + '">' + st + '</b>' : '<span class="dp-dim">-</span>') +
          '</td></tr>'
        );
      })
      .join('');
    const cons = j
      ? Object.keys(SC.CONSTRAINTS)
          .map((k) => {
            const v = j.constraints[k];
            const src = j.constraintSource[k];
            return '<tr><td>' + esc(SC.CONSTRAINTS[k].label) + '</td><td class="mono">' + (v === null ? 'null' : v) + '</td><td colspan="2" class="dp-dim">' + esc(src ? src.source + ' · ' + src.note : '미확인') + '</td></tr>';
          })
          .join('')
      : '';
    return (
      '<table class="dp-table"><thead><tr><th>조건 · ' +
      esc(product.name) +
      '</th><th>fact</th><th>은행 값</th><th>판정</th></tr></thead><tbody>' +
      rows +
      '</tbody></table>' +
      (j
        ? '<table class="dp-table mt-8"><thead><tr><th>고객 제약</th><th>값</th><th colspan="2">출처</th></tr></thead><tbody>' +
          cons +
          '</tbody></table><div class="dp-note">질문 ' +
          j.questionsAsked +
          '/' +
          SC.POLICY.joinQuestionLimit +
          ' · 반복 ' +
          (Object.keys(j.repeat)
            .map((k) => SC.FACTS[k].short + ' ' + j.repeat[k])
            .join(', ') || '없음') +
          ' (한도 ' +
          SC.POLICY.repeatLimit +
          ')</div>'
        : '<div class="dp-note">판정은 AI 가입 지원이 은행 기록을 조회할 때 계산돼요.</div>')
    );
  }

  function pathHtml(last) {
    if (!last) return '';
    const chain = last.steps.length ? last.steps.map((st) => esc(ACTION_SHORT[st.actionId] || st.actionId)).join(' <span class="arrow">→</span> ') : '-';
    let cause = '';
    if (last.cause && last.cause.type === 'CYCLE') cause = '<div style="color:#fbbf24">순환 감지: ' + last.cause.chain.map((f) => SC.FACTS[f].short).join(' → ') + '</div>';
    else if (last.cause) cause = '<div style="color:#fbbf24">원인: ' + esc(last.cause.type + ' ' + (last.cause.fact || '')) + '</div>';
    const opts = (last.options || [])
      .map((o) => (o.recommended ? '<b>' : '') + esc(ACTION_SHORT[o.actionId] || o.actionId) + '(' + o.availability + (o.cost != null ? ',' + o.cost : '') + ')' + (o.recommended ? '</b>' : ''))
      .join(' · ');
    return (
      '<div>상태: <b>' +
      last.status +
      '</b>' +
      (last.cost != null ? ' · 최소 비용 <b>' + last.cost + '</b>' : '') +
      '</div><div>' +
      chain +
      '</div>' +
      cause +
      (opts ? '<div class="dp-note">다음 단계 대체 수단: ' + opts + '</div>' : '') +
      (last.questions && last.questions.length ? '<div class="dp-note">필요한 질문(P4): ' + esc(last.questions.join(', ')) + '</div>' : '') +
      (last.visited ? '<div class="dp-note">상태 ' + last.visited + '개 · 다익스트라 확정 ' + last.explored + '개</div>' : '')
    );
  }

  function aiHtml() {
    const tr = WSP.aiAgent.trace();
    $('#dp-ai-count').textContent = tr.length + '건' + (WSP.aiAgent.isInjecting() ? ' · 위반 주입 대기' : '');
    if (!tr.length) return '<span class="dp-note">아직 AI 호출이 없어요.</span>';
    const list = tr
      .slice(-6)
      .reverse()
      .map(
        (t) =>
          '<div class="dp-ai-row' +
          (t.valid ? '' : ' is-bad') +
          '"><span class="t">' +
          t.id +
          '</span> ' +
          esc(t.task) +
          ' → <b>' +
          esc(t.output.intent) +
          '</b> ' +
          (t.valid ? '<span class="ok">검증 통과</span>' : '<span class="bad">검증 실패 → 기본 선택지</span>') +
          '</div>'
      )
      .join('');
    const lastT = tr[tr.length - 1];
    const json = JSON.stringify({ task: lastT.task, input: lastT.input, output: lastT.output, valid: lastT.valid, errors: lastT.errors }, null, 2);
    return list + '<pre class="dp-pre mt-8">' + esc(json) + '</pre>';
  }

  function infoHtml() {
    const a = WSP.app.session.asset;
    if (!a || !a.info) return '<span class="dp-note">자산관리 상담에서 정보를 수집하면 표시돼요.</span>';
    const rows = Object.keys(a.info.items)
      .map((k) => {
        const it = a.info.items[k];
        return '<tr><td>' + esc(AA.ITEMS[k].label) + '</td><td class="mono">' + (it.value == null ? 'null' : it.value) + '</td><td>' + esc(SC.SOURCE_LABEL[it.source]) + '</td></tr>';
      })
      .join('');
    const hist = a.info.history
      .slice(-6)
      .reverse()
      .map((h) => '<div><span class="s">' + esc(h.key) + '</span> ' + esc(String(h.from)) + ' → ' + esc(String(h.to)) + ' <span class="t">' + esc(h.reason) + (h.correction ? ' · 정정' : '') + '</span></div>')
      .join('');
    const metrics = a.metrics
      ? a.metrics.list.map((m) => '<div><span class="s">' + m.key + '</span> = ' + esc(m.text) + ' <span class="t">' + esc(m.formula) + '</span></div>').join('')
      : '';
    return (
      '<table class="dp-table"><thead><tr><th>항목</th><th>값</th><th>출처</th></tr></thead><tbody>' +
      rows +
      '</tbody></table><div class="dp-note">목적 ' +
      esc(a.purpose) +
      ' · 질문 ' +
      a.questionsAsked +
      '/' +
      SC.POLICY.assetQuestionLimit +
      (a.stopRequested ? ' · 질문 중단 요청' : '') +
      (a.info.declined.length ? ' · 답변 안 함: ' + esc(a.info.declined.join(', ')) : '') +
      '</div>' +
      (hist ? '<div class="dp-log mt-8" style="max-height:110px">' + hist + '</div>' : '') +
      (metrics ? '<div class="dp-log mt-8" style="max-height:140px">' + metrics + '</div>' : '')
    );
  }

  function compareHtml() {
    const s = WSP.app.session;
    const j = s.join && s.join.metrics.endedAt ? s.join.metrics : s.lastMetrics.join;
    const d = s.direct && s.direct.metrics.endedAt ? s.direct.metrics : s.lastMetrics.direct;
    const curJ = s.join ? s.join.metrics : null;
    const curD = s.direct ? s.direct.metrics : null;
    const jm = j || curJ;
    const dm = d || curD;
    const sec = (m) => (m && m.endedAt ? Math.round((m.endedAt - m.startedAt) / 1000) + '초' : m ? '진행 중' : '-');
    return (
      '<table class="dp-table"><thead><tr><th></th><th>AI와 함께</th><th>직접 가입</th></tr></thead><tbody>' +
      '<tr><td>고객 질문/입력 단계</td><td class="mono">' +
      (jm ? jm.questions + '회 질문' : '-') +
      '</td><td class="mono">' +
      (dm ? dm.steps + '단계' : '-') +
      '</td></tr><tr><td>업무 화면 이동</td><td class="mono">' +
      (jm ? jm.tasks + '회(모달)' : '-') +
      '</td><td class="mono">' +
      (dm ? dm.menuVisits + '회(메뉴 탐색)' : '-') +
      '</td></tr><tr><td>처음부터 다시</td><td class="mono">0</td><td class="mono">' +
      (dm ? dm.restarts + '회' : '-') +
      '</td></tr><tr><td>걸린 시간</td><td class="mono">' +
      sec(jm) +
      '</td><td class="mono">' +
      sec(dm) +
      '</td></tr></tbody></table><div class="dp-note">같은 고객 상태에서 두 방법을 각각 진행해 비교하세요. 시연 속도 기준이며 실제 소요 시간이 아니에요.</div>'
    );
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
    root.querySelectorAll('[data-dp="task-outcome"]').forEach((b) => b.classList.toggle('is-active', b.dataset.v === s.simulation.nextTaskOutcome));
    root.querySelectorAll('[data-dp="app-outcome"]').forEach((b) => b.classList.toggle('is-active', b.dataset.v === s.simulation.nextApplicationOutcome));
    root.querySelectorAll('[data-dp="consult-outcome"]').forEach((b) => b.classList.toggle('is-active', b.dataset.v === s.simulation.nextConsultOutcome));
    root.querySelectorAll('[data-dp="speed"]').forEach((b) => b.classList.toggle('is-active', Number(b.dataset.v) === bank.getLatencyScale()));
    root.querySelectorAll('[data-dp="track"]').forEach((b) => b.classList.toggle('is-active', b.dataset.v === track));
    root.querySelector('[data-dp="exit-toggle"]').classList.toggle('is-active', showExit);
    root.querySelector('[data-dp="ai-invalid"]').classList.toggle('is-active', WSP.aiAgent.isInjecting());

    const open = Object.keys(s.applications)
      .map((k) => s.applications[k])
      .filter((a) => a.status === 'PENDING' || a.status === 'UNKNOWN');
    $('#dp-pending').innerHTML = open.length
      ? open
          .map(
            (a) =>
              '<div class="dp-row"><span>' +
              esc(a.id) +
              ' · ' +
              a.status +
              '</span><span><button class="dp-btn" data-dp="resolve" data-id="' +
              a.id +
              '" data-v="SUCCESS">은행 확정 SUCCESS</button> <button class="dp-btn" data-dp="resolve" data-id="' +
              a.id +
              '" data-v="FAILED">FAILED</button></span></div>'
          )
          .join('') + '<div class="dp-note">은행 측 처리 확정을 시뮬레이션합니다. 앱에서 "결과 다시 조회"를 눌러야 반영돼요.</div>'
      : '';

    const f = WSP.app.fsms[track];
    $('#dp-fsm-cur').innerHTML = '<span style="color:#7cc4ff;font-family:var(--mono)">' + f.state + '</span>';
    const hist = f.history();
    $('#dp-fsm').innerHTML = renderFsmGraph(track, f.state, hist);
    $('#dp-fsm-hist').innerHTML = hist.length
      ? hist
          .slice(-8)
          .reverse()
          .map((h) => '<div><span class="t">' + h.at.slice(11, 19) + '</span> ' + h.from + ' <span class="s">--' + h.event + '--></span> ' + h.to + (h.src !== 'D' ? ' <span class="p">' + h.src + '</span>' : '') + '</div>')
          .join('')
      : '<div class="t">전이 기록 없음</div>';

    $('#dp-cond').innerHTML = condHtml(s);
    const last = WSP.pathfinder.getLastResult();
    const key = last ? String(last.computedAt) : '0';
    if ($('#dp-sg').dataset.key !== key) {
      $('#dp-sg').dataset.key = key;
      $('#dp-sg').innerHTML = renderStateGraph(last);
    }
    $('#dp-path').innerHTML = pathHtml(last);
    $('#dp-ai').innerHTML = aiHtml();
    $('#dp-info').innerHTML = infoHtml();
    $('#dp-compare').innerHTML = compareHtml();
    $('#dp-ver').innerHTML = '<span style="font-family:var(--mono);color:#7cc4ff">v' + s.system.stateVersion + '</span>';
    $('#dp-json').textContent = JSON.stringify({ facts: s.facts, pending: s.pending, simulation: s.simulation, system: s.system, applications: s.applications, consultations: s.consultations }, null, 2);
    $('#dp-log').innerHTML = events
      .list()
      .slice(-60)
      .reverse()
      .map((l) => '<div title="' + esc(l.message) + '"><span class="t">' + l.at.slice(11, 19) + '</span> <span class="s">' + l.source + '</span> ' + esc(l.message) + '</div>')
      .join('');
  }

  store.subscribe(scheduleSync);
  events.subscribe(scheduleSync);
  WSP.aiAgent.subscribe(scheduleSync);
  Object.keys(WSP.app.fsms).forEach((k) =>
    WSP.app.fsms[k].subscribe((state, record) => {
      if (record && !trackPinned) track = k;
      scheduleSync();
    })
  );
  WSP.app.onChange(scheduleSync);
  window.addEventListener('DOMContentLoaded', () => sync());

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
    } else root.parentElement.classList.toggle('is-panel-hidden');
  }

  document.addEventListener('keydown', (e) => {
    if (e.shiftKey && (e.key === 'D' || e.key === 'd') && !/input|textarea|select/i.test(e.target.tagName)) {
      e.preventDefault();
      togglePanel();
    }
  });
})();
