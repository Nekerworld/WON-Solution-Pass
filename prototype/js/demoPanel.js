/**
 * demoPanel.js
 * 발표자용 시연 패널 (PC 전용, 앱 화면 바깥).
 * 실제 금융 앱의 기능이 아니다. 고정된 통합 시나리오의 진행 과정과 내부 상태를 보여 준다.
 * 은행 상태·응답 결과는 바꾸지 않는다 (모두 기본값).
 * 단축키: Shift + D (표시/숨김)
 */
(function () {
  'use strict';

  const WSP = window.WSP;
  const store = WSP.store;
  const SC = WSP.scenario;
  const events = WSP.events;
  const esc = WSP.ui.esc;
  const AA = WSP.assetAdvisor;
  const DEMO = SC.DEMO;

  const root = document.getElementById('demo-panel');
  if (!root) return;

  const PHASES = ['자산관리 상담', '상품 선택', '가입 지원', '가입 완료'];

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
    FX_REGISTER: '외환신청',
    OPEN_FX_ACCOUNT: '외화계좌',
    INVESTOR_PROFILE: '투자성향',
  };

  root.innerHTML =
    '<div class="dp-head"><div><div class="dp-head__title">DEMO CONTROL</div><div class="dp-head__sub">시연용 도구 · 실제 앱 기능 아님 · Shift+D</div></div>' +
    '<button class="dp-btn dp-btn--danger" data-dp="reset">데모 초기화</button></div>' +
    '<div class="dp-body">' +
    '<div class="dp-col dp-col--controls">' +
    '<div class="dp-section"><div class="dp-section__title">시나리오 <span class="dp-tag">' +
    esc(SC.POLICY.version) +
    '</span></div><div class="dp-scn"><strong>' +
    esc(DEMO.title) +
    '</strong><div class="dp-scn__who">' +
    esc(SC.initialBankState.customer.name) +
    '(' +
    SC.initialBankState.customer.age +
    ') · ' +
    DEMO.givens.map(esc).join(' · ') +
    '</div><div class="dp-scn__ans">고객 답변: ' +
    DEMO.customerAnswers.map((a) => esc(a[0]) + ' <b>' + esc(a[1]) + '</b>').join(' · ') +
    '</div></div></div>' +
    '<div class="dp-section"><div class="dp-section__title">진행 과정 <span class="dp-tag" id="dp-prog-count"></span></div><div id="dp-progress"></div></div>' +
    '<div class="dp-section"><div class="dp-section__title">자가 테스트 <button class="dp-btn dp-btn--primary" data-dp="selftest">실행</button></div><div class="dp-tests" id="dp-tests"><span class="dp-note">검증 항목을 브라우저 안에서 실행합니다. 실행 전 상태는 자동 복원됩니다.</span></div></div>' +
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
  root.addEventListener('click', async (e) => {
    const b = e.target.closest('[data-dp]');
    if (!b) return;
    const kind = b.dataset.dp;
    const v = b.dataset.v;
    if (kind === 'reset') WSP.app.resetDemo();
    else if (kind === 'track') {
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
    const byDepth = [];
    g.nodes.forEach((n) => (byDepth[n.depth] = byDepth[n.depth] || []).push(n));
    // 노드는 그 상태로 들어온 업무 이름으로 표시한다 (경로 위 간선 우선)
    const inEdge = {};
    g.edges.forEach((e) => {
      if (!inEdge[e.to] || e.onPath) inEdge[e.to] = e;
    });
    const PER = 4;
    const NW = 96;
    const NH = 36;
    const CG = 40;
    const RG = 26;
    const rows = Math.max.apply(null, byDepth.map((c) => c.length));
    const blockH = rows * (NH + 14);
    const blocks = Math.ceil(byDepth.length / PER);
    const VW = PER * NW + (PER - 1) * CG + 24;
    const VH = blocks * blockH + (blocks - 1) * RG + 12;
    const pos = {};
    byDepth.forEach((col, d) =>
      col.forEach((n, i) => {
        const bi = Math.floor(d / PER);
        pos[n.key] = { x: 12 + NW / 2 + (d % PER) * (NW + CG), y: 6 + bi * (blockH + RG) + ((i + 0.5) * blockH) / col.length };
      })
    );
    const onPath = new Set([g.startKey]);
    g.edges.forEach((e) => e.onPath && onPath.add(e.to));
    let edges = '';
    let hl = '';
    g.edges.forEach((e) => {
      const wrap = pos[e.to].y - pos[e.from].y > blockH / 2;
      const c = curve(pos[e.from], pos[e.to], NW, NH, e.onPath ? (wrap ? -20 : 0) : 12);
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
        ')</title></path>';
      if (e.onPath) hl += svg;
      else edges += svg;
    });
    const nodes = g.nodes
      .map((n) => {
        const p = pos[n.key];
        const e = inEdge[n.key];
        const facts = n.key === g.startKey ? '현재' : e ? ACTION_SHORT[e.actionId] || e.actionId : '?';
        const cls = n.key === g.startKey ? ' is-start' : n.goal ? ' is-goal' : onPath.has(n.key) ? ' is-visited' : '';
        const sub = n.key === g.startKey ? 'd=0' : (n.goal ? '목표 · ' : '') + (n.dist == null ? '미탐색' : 'd=' + n.dist);
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
    $('#dp-ai-count').textContent = tr.length + '건';
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

  /* ---------- 진행 과정 ---------- */
  function progressHtml(s) {
    const f = WSP.app.fsms;
    const sess = WSP.app.session;
    const apps = Object.keys(s.applications)
      .map((k) => s.applications[k])
      .filter((a) => a.productId === DEMO.productId);
    const opened = apps.some((a) => a.status === 'SUCCESS');
    const joining =
      (f.join.state !== 'IDLE' && sess.join && sess.join.productId === DEMO.productId) || (f.direct.state !== 'IDLE' && sess.direct && sess.direct.productId === DEMO.productId);
    const phase = opened ? PHASES.length : joining ? 2 : ['EXPLORE', 'TO_JOIN', 'CLOSED'].indexOf(f.asset.state) !== -1 ? 1 : f.asset.state !== 'IDLE' ? 0 : -1;
    const phaseHtml =
      '<div class="dp-phase">' +
      PHASES.map((p, i) => '<span class="' + (i < phase ? 'is-done' : i === phase ? 'is-cur' : '') + '">' + esc(p) + '</span>').join('<i>›</i>') +
      '</div>';

    let curFound = false;
    let doneItems = 0;
    let totalItems = 0;
    const stages = DEMO.stages.map((st) => {
      const items = st.facts.map((k) => ({ label: SC.FACTS[k].label, ok: s.facts[k] === true, pending: !!s.pending[k] }));
      if (st.application) items.push({ label: SC.getProduct(st.application).name + ' 개설', ok: opened, pending: apps.some((a) => a.status === 'PENDING' || a.status === 'UNKNOWN') });
      items.forEach((it) => {
        totalItems += 1;
        if (it.ok) doneItems += 1;
      });
      const all = items.every((it) => it.ok);
      let cls = all ? 'is-done' : '';
      if (!all && !curFound) {
        curFound = true;
        cls = 'is-cur';
      }
      return { label: st.label, items: items, cls: cls };
    });
    $('#dp-prog-count').textContent = doneItems + ' / ' + totalItems;

    const stepper =
      '<ol class="dp-stages">' +
      stages.map((st, i) => '<li class="' + st.cls + '"><span>' + (st.cls === 'is-done' ? '✓' : i + 1) + '</span>' + esc(st.label) + '</li>').join('') +
      '</ol>';
    const detail =
      '<div class="dp-stage-items">' +
      stages
        .map(
          (st) =>
            '<div class="dp-stage-row ' +
            st.cls +
            '"><b>' +
            esc(st.label) +
            '</b>' +
            st.items.map((it) => '<span class="' + (it.ok ? 'ok' : it.pending ? 'wait' : '') + '">' + (it.ok ? '✓ ' : it.pending ? '… ' : '○ ') + esc(it.label) + '</span>').join('') +
            '</div>'
        )
        .join('') +
      '</div>';

    const last = WSP.pathfinder.getLastResult();
    let next = '';
    if (opened) next = '해외주식 계좌 개설 완료 (은행 처리 결과로 확인)';
    else if (f.join.state === 'READY_TO_APPLY') next = '고객 승인 대기: 가입 정보 확인 화면';
    else if (f.join.state === 'CLARIFYING') next = '고객 답변 대기';
    else if (joining && last && last.status === 'PLAN' && last.steps.length) next = '남은 업무 ' + last.steps.length + '개 · 다음: ' + last.steps[0].label;
    else if (phase === 1) next = '고객이 상품을 고르면 가입 지원이 시작돼요';
    else if (phase === 0) next = '자산관리 상담 진행 중';
    else if (phase === -1) next = '홈에서 AI 자산관리 상담으로 시작';

    return phaseHtml + stepper + detail + (next ? '<div class="dp-next">' + esc(next) + '</div>' : '');
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
    root.querySelectorAll('[data-dp="track"]').forEach((b) => b.classList.toggle('is-active', b.dataset.v === track));
    root.querySelector('[data-dp="exit-toggle"]').classList.toggle('is-active', showExit);
    $('#dp-progress').innerHTML = progressHtml(s);

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
