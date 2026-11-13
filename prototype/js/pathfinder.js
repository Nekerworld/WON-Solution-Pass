/**
 * pathfinder.js
 * 현재 은행 사실(facts)에서 상품 조건(goal)까지 도달하는 업무 경로를 계산한다.
 * 1) 상태 그래프: 업무(TASKS)의 선행 조건과 효과로 도달 가능한 상태를 펼친다.
 *    고객 제약(constraints)이 false인 업무는 제외하고, 모르는 제약(null)은
 *    낙관 모드에서만 허용한다.
 * 2) 다익스트라: 업무 가중치 합이 가장 작은 경로를 고른다.
 * 3) 다음 단계의 대체 수단 목록, 필요한 질문, 경로가 없을 때의 순환 원인을 함께 돌려준다.
 * 업무와 대체 수단은 은행 데이터에서만 온다. 경로를 만들어 내지 않는다.
 */
(function () {
  'use strict';

  const WSP = window.WSP;
  const SC = WSP.scenario;

  const MAX_DEPTH = 10;
  const FACT_KEYS = Object.keys(SC.FACTS);

  const ACTIONS = SC.TASKS;

  function getAction(id) {
    return SC.getTask(id);
  }

  /** 'OK' | 'UNKNOWN' | 'BLOCKED' */
  function availability(action, constraints) {
    const c = constraints || {};
    let result = 'OK';
    Object.keys(action.needs || {}).forEach((k) => {
      const v = c[k];
      if (v === false) result = 'BLOCKED';
      else if ((v === null || v === undefined) && result !== 'BLOCKED') result = 'UNKNOWN';
    });
    return result;
  }

  function unknownNeeds(action, constraints) {
    const c = constraints || {};
    return Object.keys(action.needs || {}).filter((k) => c[k] === null || c[k] === undefined);
  }

  function preOk(action, facts) {
    return Object.keys(action.pre).every((f) => facts[f] === action.pre[f]);
  }

  function useful(action, facts) {
    return Object.keys(action.effects).some((f) => facts[f] !== action.effects[f]);
  }

  function allowed(action, constraints, mode) {
    const a = availability(action, constraints);
    return a === 'OK' || (mode === 'optimistic' && a === 'UNKNOWN');
  }

  function sameEffect(a, b) {
    return Object.keys(b.effects).some((f) => a.effects[f] === b.effects[f]);
  }

  function isGoal(facts, goal) {
    return Object.keys(goal).every((k) => facts[k] === goal[k]);
  }

  function keyOf(facts) {
    return FACT_KEYS.map((k) => k + ':' + (facts[k] ? 1 : 0)).join('|');
  }

  function applyEffects(action, facts) {
    const next = Object.assign({}, facts);
    Object.keys(action.effects).forEach((f) => (next[f] = action.effects[f]));
    return next;
  }

  function buildStateGraph(startFacts, goal, constraints, mode) {
    const startKey = keyOf(startFacts);
    const nodes = new Map([[startKey, { key: startKey, facts: startFacts, depth: 0, goal: isGoal(startFacts, goal) }]]);
    const edges = [];
    const adjacency = new Map();
    const queue = [startKey];
    while (queue.length) {
      const key = queue.shift();
      const node = nodes.get(key);
      adjacency.set(key, []);
      if (node.goal || node.depth >= MAX_DEPTH) continue;
      ACTIONS.forEach((action) => {
        if (!allowed(action, constraints, mode) || !preOk(action, node.facts) || !useful(action, node.facts)) return;
        const next = applyEffects(action, node.facts);
        const nk = keyOf(next);
        if (!nodes.has(nk)) {
          nodes.set(nk, { key: nk, facts: next, depth: node.depth + 1, goal: isGoal(next, goal) });
          queue.push(nk);
        }
        const edge = { from: key, to: nk, actionId: action.id, weight: action.weight || 1, unknown: availability(action, constraints) === 'UNKNOWN' };
        edges.push(edge);
        adjacency.get(key).push(edge);
      });
    }
    return { startKey: startKey, nodes: nodes, edges: edges, adjacency: adjacency };
  }

  function createMinHeap() {
    const a = [];
    let seq = 0;
    const less = (x, y) => x.cost < y.cost || (x.cost === y.cost && x.seq < y.seq);
    return {
      get size() {
        return a.length;
      },
      push(cost, key) {
        a.push({ cost: cost, key: key, seq: seq++ });
        let i = a.length - 1;
        while (i > 0) {
          const p = (i - 1) >> 1;
          if (!less(a[i], a[p])) break;
          [a[i], a[p]] = [a[p], a[i]];
          i = p;
        }
      },
      pop() {
        const top = a[0];
        const last = a.pop();
        if (a.length) {
          a[0] = last;
          let i = 0;
          for (;;) {
            const l = i * 2 + 1;
            const r = l + 1;
            let m = i;
            if (l < a.length && less(a[l], a[m])) m = l;
            if (r < a.length && less(a[r], a[m])) m = r;
            if (m === i) break;
            [a[i], a[m]] = [a[m], a[i]];
            i = m;
          }
        }
        return top;
      },
    };
  }

  function dijkstra(graph) {
    const dist = new Map([[graph.startKey, 0]]);
    const prev = new Map();
    const settled = new Set();
    const heap = createMinHeap();
    heap.push(0, graph.startKey);
    let explored = 0;
    while (heap.size) {
      const { cost, key } = heap.pop();
      if (settled.has(key)) continue;
      settled.add(key);
      explored += 1;
      if (graph.nodes.get(key).goal) return { found: true, goalKey: key, cost: cost, dist: dist, prev: prev, explored: explored };
      graph.adjacency.get(key).forEach((e) => {
        const nd = cost + e.weight;
        if (!dist.has(e.to) || nd < dist.get(e.to)) {
          dist.set(e.to, nd);
          prev.set(e.to, e);
          heap.push(nd, e.to);
        }
      });
    }
    return { found: false, goalKey: null, cost: Infinity, dist: dist, prev: prev, explored: explored };
  }

  function serializeGraph(graph, search, pathEdges) {
    const onPath = new Set(pathEdges);
    return {
      startKey: graph.startKey,
      goalKey: search.goalKey,
      nodes: Array.from(graph.nodes.values()).map((n) => ({
        key: n.key,
        facts: n.facts,
        depth: n.depth,
        goal: n.goal,
        dist: search.dist.has(n.key) ? search.dist.get(n.key) : null,
      })),
      edges: graph.edges.map((e) => ({ from: e.from, to: e.to, actionId: e.actionId, weight: e.weight, unknown: e.unknown, onPath: onPath.has(e) })),
    };
  }

  function findPath(startFacts, goal, constraints, mode) {
    const graph = buildStateGraph(startFacts, goal, constraints, mode || 'optimistic');
    const search = dijkstra(graph);
    const pathEdges = [];
    if (search.found) {
      let k = search.goalKey;
      while (k !== graph.startKey) {
        const e = search.prev.get(k);
        pathEdges.unshift(e);
        k = e.from;
      }
    }
    return {
      found: search.found,
      cost: search.found ? search.cost : null,
      steps: pathEdges.map((e) => ({ actionId: e.actionId, label: getAction(e.actionId).label, weight: e.weight, unknown: e.unknown })),
      explored: search.explored,
      visited: graph.nodes.size,
      graph: serializeGraph(graph, search, pathEdges),
    };
  }

  /**
   * 경로가 없을 때 원인을 찾는다.
   * - NO_METHOD: 조건을 채울 업무가 고객 제약으로 모두 막힘
   * - CYCLE: A를 하려면 B, B를 하려면 A가 필요한 순환
   */
  function detectCycle(facts, goal, constraints) {
    const unmet = Object.keys(goal).filter((f) => facts[f] !== goal[f]);
    const deps = {};
    const stuck = new Set();
    for (let i = 0; i < unmet.length; i++) {
      const f = unmet[i];
      const all = ACTIONS.filter((a) => a.effects[f] === true);
      const producers = all.filter((a) => availability(a, constraints) !== 'BLOCKED');
      if (!producers.length) {
        return {
          type: all.length ? 'NO_METHOD' : 'NO_TASK',
          fact: f,
          blocked: all.map((a) => ({ actionId: a.id, needs: Object.keys(a.needs).filter((k) => constraints[k] === false) })),
        };
      }
      const needSets = producers.map((a) => Object.keys(a.pre).filter((p) => facts[p] !== a.pre[p]));
      if (needSets.every((s) => s.length > 0)) stuck.add(f);
      deps[f] = [];
      needSets.forEach((s) => s.forEach((p) => deps[f].indexOf(p) === -1 && deps[f].push(p)));
    }
    const color = {};
    let found = null;
    function dfs(f, path) {
      if (found) return;
      color[f] = 1;
      path.push(f);
      (deps[f] || []).forEach((g) => {
        if (found || !stuck.has(g)) return;
        if (color[g] === 1) found = path.slice(path.indexOf(g)).concat([g]);
        else if (!color[g]) dfs(g, path);
      });
      path.pop();
      color[f] = 2;
    }
    Array.from(stuck).forEach((f) => !color[f] && dfs(f, []));
    if (!found) return null;
    const via = [];
    for (let i = 0; i < found.length - 1; i++) {
      const a = ACTIONS.find((x) => x.effects[found[i]] === true && x.pre[found[i + 1]] === true && availability(x, constraints) !== 'BLOCKED');
      via.push(a ? a.id : null);
    }
    return { type: 'CYCLE', chain: found, via: via };
  }

  let lastResult = null;

  /**
   * 조건 판정 결과(evaluation)와 고객 제약으로 해결 경로를 계산한다.
   * status: READY | PLAN | NO_PATH | BLOCKED | UNKNOWN
   */
  function computeRoute(evaluation, constraints) {
    const c = constraints || {};
    let result;
    if (!evaluation.ok) result = { status: 'UNKNOWN', steps: [], options: [], questions: [] };
    else if (evaluation.blockers.length) result = { status: 'BLOCKED', blockers: evaluation.blockers, steps: [], options: [], questions: [] };
    else if (evaluation.allMet) result = { status: 'READY', steps: [], options: [], questions: [], cost: 0 };
    else {
      const facts = evaluation.facts;
      const goal = evaluation.goal;
      const opt = findPath(facts, goal, c, 'optimistic');
      if (!opt.found) {
        result = { status: 'NO_PATH', steps: [], options: [], questions: [], cause: detectCycle(facts, goal, c), graph: opt.graph, visited: opt.visited, explored: opt.explored };
      } else {
        // 확인된 제약만으로 갈 수 있는 경로가 있으면 묻지 않고 그 경로를 기본으로 쓴다.
        const known = findPath(facts, goal, c, 'known');
        const base = known.found ? known : opt;
        const questions = [];
        if (!known.found) {
          opt.steps.forEach((s) => {
            const a = getAction(s.actionId);
            if (!unknownNeeds(a, c).length) return;
            ACTIONS.filter((x) => sameEffect(x, a)).forEach((x) => unknownNeeds(x, c).forEach((k) => questions.indexOf(k) === -1 && questions.push(k)));
          });
        }
        result = {
          status: 'PLAN',
          steps: base.steps,
          cost: base.cost,
          questions: questions,
          options: alternativesFor(facts, goal, c, base.steps[0]),
          graph: base.graph,
          visited: base.visited,
          explored: base.explored,
        };
      }
    }
    result.computedAt = Date.now();
    lastResult = result;
    WSP.events.add(
      'PATH',
      '경로 계산 [' + result.status + '] ' + (result.steps.map((s) => s.actionId).join(' → ') || '-') + (result.cost != null ? ' (비용 ' + result.cost + ')' : '')
    );
    return result;
  }

  /** 다음 단계와 같은 효과를 내는, 지금 시작할 수 있는 대체 수단 */
  function alternativesFor(facts, goal, constraints, firstStep) {
    if (!firstStep) return [];
    const target = Object.keys(getAction(firstStep.actionId).effects);
    return ACTIONS.filter((a) => target.some((f) => a.effects[f] === true) && preOk(a, facts) && useful(a, facts))
      .map((a) => {
        const av = availability(a, constraints);
        const rest = av === 'BLOCKED' ? null : findPath(applyEffects(a, facts), goal, constraints, 'optimistic');
        return {
          actionId: a.id,
          label: a.label,
          availability: av,
          reachable: !!(rest && rest.found),
          cost: rest && rest.found ? a.weight + rest.cost : null,
          recommended: a.id === firstStep.actionId,
          unknownNeeds: unknownNeeds(a, constraints),
          blockedNeeds: Object.keys(a.needs).filter((k) => constraints[k] === false),
        };
      })
      .sort((x, y) => (y.recommended ? 1 : 0) - (x.recommended ? 1 : 0) || (x.cost == null) - (y.cost == null) || x.cost - y.cost);
  }

  WSP.pathfinder = {
    MAX_DEPTH: MAX_DEPTH,
    FACT_KEYS: FACT_KEYS,
    getAction: getAction,
    availability: availability,
    buildStateGraph: buildStateGraph,
    dijkstra: dijkstra,
    findPath: findPath,
    detectCycle: detectCycle,
    computeRoute: computeRoute,
    alternativesFor: alternativesFor,
    getLastResult: () => lastResult,
    setLastResult: (r) => (lastResult = r),
  };
})();
