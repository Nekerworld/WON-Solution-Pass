/**
 * pathfinder.js
 * 현재 추상 상태(facts)에서 목표 상태(goal)까지의 해결 경로를 계산한다.
 * 1) 상태 그래프 생성: 현재 상태에서 출발해 사전 조건을 만족하는 행동으로 도달 가능한
 *    모든 상태(노드)와 행동(간선)을 만든다. 간선 weight는 DEMO_POLICY.actionWeights.
 * 2) 다익스트라: 간선 weight 합이 최소인 목표 상태까지의 경로를 고른다.
 * - 방문한 상태는 직렬화 키로 식별하여 같은 상태를 중복 생성하지 않는다.
 * - 경로가 없거나 차단 사유가 있으면 상담 연결(ESCALATE_TO_SUPPORT)로 대체한다.
 * 고정된 순서 배열을 출력하지 않는다. 순서는 사전 조건, 현재 상태, 정책 가중치에서 결정된다.
 */
(function () {
  'use strict';

  const WSP = window.WSP;
  const RE = WSP.ruleEngine;
  const fmt = WSP.utils.formatWon;
  const P = WSP.DEMO_POLICY;

  const MAX_DEPTH = 6;

  /**
   * precondition 형식
   *  { fact, equals }                 : facts[fact] === equals
   *  { fact, equals, constraint: id } : 규칙 엔진이 해당 제약(id)을 활성화했을 때만 적용
   *  { goalSatisfied: true }          : 목표 상태의 모든 조건 충족
   */
  const ACTIONS = Object.freeze([
    {
      id: 'COMPLETE_KYC',
      label: '고객확인 완료',
      flowId: 'kyc-flow',
      resolves: 'kycCompleted',
      preconditions: [
        { fact: 'kycCompleted', equals: false },
        { fact: 'accountRestricted', equals: false },
        { fact: 'bankAvailable', equals: true },
      ],
      effects: [{ fact: 'kycCompleted', value: true }],
      phrase: { first: '고객확인을 완료한', mid: '고객확인을 완료하고', last: '고객확인을 완료해 주세요' },
      cta: '고객확인 하러 가기',
    },
    {
      id: 'REGISTER_OTP',
      label: '디지털 OTP 등록',
      flowId: 'otp-registration',
      resolves: 'otpRegistered',
      preconditions: [
        { fact: 'otpRegistered', equals: false },
        { fact: 'kycCompleted', equals: true, constraint: 'R08' },
        { fact: 'accountRestricted', equals: false },
        { fact: 'bankAvailable', equals: true },
      ],
      effects: [{ fact: 'otpRegistered', value: true }],
      phrase: { first: 'OTP 등록을 진행한', mid: 'OTP 등록을 진행하고', last: 'OTP 등록을 진행해 주세요' },
      cta: '디지털 OTP 등록하러 가기',
    },
    {
      id: 'CHANGE_TRANSFER_LIMIT',
      label: '이체한도 변경',
      flowId: 'limit-management',
      resolves: 'limitSufficient',
      preconditions: [
        { fact: 'limitSufficient', equals: false },
        { fact: 'limitChangeAllowed', equals: true },
        { fact: 'otpRegistered', equals: true, constraint: 'R03' },
        { fact: 'accountRestricted', equals: false },
        { fact: 'bankAvailable', equals: true },
      ],
      effects: [{ fact: 'limitSufficient', value: true }],
      phrase: { first: '한도를 변경한', mid: '한도를 변경하고', last: '한도를 변경해 주세요' },
      cta: '이체한도 변경하러 가기',
    },
    {
      id: 'RETURN_TO_TRANSFER',
      label: '원래 이체로 돌아가기',
      flowId: 'transfer',
      terminal: true,
      preconditions: [{ goalSatisfied: true }, { fact: 'returnedToTransfer', equals: false }],
      effects: [{ fact: 'returnedToTransfer', value: true }],
      cta: '원래 이체로 돌아가기',
    },
    {
      id: 'ESCALATE_TO_SUPPORT',
      label: '상담 연결',
      flowId: 'support',
      fallbackOnly: true,
      preconditions: [],
      effects: [],
      cta: '상담 연결 안내 보기',
    },
  ]);

  function getAction(id) {
    return ACTIONS.find((a) => a.id === id) || null;
  }

  function goalSatisfied(facts, goal) {
    return Object.keys(goal).every((k) => facts[k] === goal[k]);
  }

  function isGoal(facts, goal) {
    return goalSatisfied(facts, goal) && facts.returnedToTransfer === true;
  }

  function isApplicable(action, facts, goal, activeConstraints) {
    if (action.fallbackOnly) return false;
    return action.preconditions.every((pre) => {
      if (pre.goalSatisfied) return goalSatisfied(facts, goal);
      if (pre.constraint && !activeConstraints.has(pre.constraint)) return true;
      return facts[pre.fact] === pre.equals;
    });
  }

  function applyEffects(action, facts) {
    const next = Object.assign({}, facts);
    action.effects.forEach((e) => {
      next[e.fact] = e.value;
    });
    return next;
  }

  function keyOf(facts) {
    return Object.keys(facts)
      .sort()
      .map((k) => k + ':' + (facts[k] ? 1 : 0))
      .join('|');
  }

  function weightOf(action) {
    const w = P.actionWeights && P.actionWeights[action.id];
    return typeof w === 'number' && w > 0 ? w : 1;
  }

  /**
   * 현재 상태에서 도달 가능한 상태 그래프를 만든다.
   * 목표 상태와 깊이 제한(MAX_DEPTH)에 닿은 노드는 더 확장하지 않는다.
   * @returns {{startKey:string, nodes:Map, edges:Array, adjacency:Map}}
   */
  function buildStateGraph(startFacts, goal, constraints) {
    const active = new Set((constraints || []).map((c) => c.ruleId));
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
      for (let i = 0; i < ACTIONS.length; i++) {
        const action = ACTIONS[i];
        if (!isApplicable(action, node.facts, goal, active)) continue;
        const next = applyEffects(action, node.facts);
        const nk = keyOf(next);
        if (!nodes.has(nk)) {
          nodes.set(nk, { key: nk, facts: next, depth: node.depth + 1, goal: isGoal(next, goal) });
          queue.push(nk);
        }
        const edge = { from: key, to: nk, actionId: action.id, weight: weightOf(action) };
        edges.push(edge);
        adjacency.get(key).push(edge);
      }
    }
    return { startKey: startKey, nodes: nodes, edges: edges, adjacency: adjacency };
  }

  /** 다익스트라용 최소 힙. 비용이 같으면 먼저 넣은 항목이 먼저 나온다. */
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

  /**
   * 상태 그래프에서 목표 노드까지 weight 합이 최소인 경로를 찾는다.
   * @returns {{found:boolean, goalKey:string|null, cost:number, dist:Map, prev:Map, explored:number}}
   */
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
      if (graph.nodes.get(key).goal) {
        return { found: true, goalKey: key, cost: cost, dist: dist, prev: prev, explored: explored };
      }
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

  /** 시연 패널 시각화용 직렬화 그래프 */
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
      edges: graph.edges.map((e) => ({ from: e.from, to: e.to, actionId: e.actionId, weight: e.weight, onPath: onPath.has(e) })),
    };
  }

  /**
   * 상태 그래프 + 다익스트라 경로 탐색
   * @returns {{found:boolean, steps:Array, cost:number, explored:number, visited:number, graph:Object}}
   */
  function findPath(startFacts, goal, constraints) {
    const graph = buildStateGraph(startFacts, goal, constraints);
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
    const steps = pathEdges.map((e) => {
      const action = getAction(e.actionId);
      return {
        actionId: action.id,
        label: action.label,
        flowId: action.flowId,
        weight: e.weight,
        before: graph.nodes.get(e.from).facts,
        after: graph.nodes.get(e.to).facts,
      };
    });
    return {
      found: search.found,
      steps: steps,
      cost: search.found ? search.cost : null,
      explored: search.explored,
      visited: graph.nodes.size,
      graph: serializeGraph(graph, search, pathEdges),
    };
  }

  let lastResult = null;

  /**
   * 규칙 평가 결과로 해결 계획을 만든다.
   * status: 'PLAN'    사용자 행동이 필요한 경로가 있음
   *         'READY'   추가 절차 없이 원래 이체로 돌아갈 수 있음
   *         'BLOCKED' 자동 해결 경로 생성 금지 (계좌 제한, 시스템 장애 등)
   *         'NO_PATH' 목표에 도달하는 유효 경로 없음 -> 상담 안내
   */
  function computePlan(evaluation) {
    let result;
    if (evaluation.blockers.length) {
      result = {
        status: 'BLOCKED',
        evaluation: evaluation,
        steps: [],
        actionSteps: [],
        blocker: evaluation.blockers[0],
        fallback: getAction('ESCALATE_TO_SUPPORT'),
        explored: 0,
        visited: 0,
      };
    } else {
      const search = findPath(evaluation.facts, evaluation.goal, evaluation.constraints);
      if (!search.found) {
        result = {
          status: 'NO_PATH',
          evaluation: evaluation,
          steps: [],
          actionSteps: [],
          fallback: getAction('ESCALATE_TO_SUPPORT'),
          explored: search.explored,
          visited: search.visited,
          graph: search.graph,
        };
      } else {
        const actionSteps = search.steps.filter((s) => !getAction(s.actionId).terminal);
        result = {
          status: actionSteps.length ? 'PLAN' : 'READY',
          evaluation: evaluation,
          steps: search.steps,
          actionSteps: actionSteps,
          cost: search.cost,
          explored: search.explored,
          visited: search.visited,
          graph: search.graph,
        };
      }
    }
    result.computedAt = Date.now();
    lastResult = result;
    WSP.events.add(
      'PATH',
      '경로 계산 [' +
        result.status +
        '] ' +
        (result.steps.map((s) => s.actionId).join(' → ') || '-') +
        (result.cost != null ? ' (비용 ' + result.cost + ')' : '') +
        ' · 상태 ' +
        result.visited +
        '개 / 확정 ' +
        result.explored +
        '개'
    );
    return result;
  }

  /** 조회 실패 시: 정상 진단을 가장하지 않는다 */
  function planFromQueryFailure(error) {
    const blocker = RE.blockerFromQueryFailure(error);
    const result = {
      status: 'BLOCKED',
      evaluation: null,
      steps: [],
      actionSteps: [],
      blocker: blocker,
      fallback: getAction('ESCALATE_TO_SUPPORT'),
      explored: 0,
      visited: 0,
      queryError: error,
      computedAt: Date.now(),
    };
    lastResult = result;
    WSP.events.add('PATH', '상태 조회 실패로 경로 계산 중단 (' + (error && error.code) + ')');
    return result;
  }

  /** 단계 카드 표시용 설명 */
  function describeStep(actionId, ctx) {
    switch (actionId) {
      case 'COMPLETE_KYC':
        return {
          problem: '고객확인이 완료되지 않았어요.',
          current: ctx.kycCompleted ? '완료' : '미완료',
          action: '고객확인 화면에서 절차를 진행해요.',
          expected: '디지털 OTP 등록과 이체가 가능한 상태가 돼요.',
          ruleIds: ['R04'],
        };
      case 'REGISTER_OTP': {
        const needForTransfer = ctx.amount > P.otpRequiredAbove;
        return {
          problem: needForTransfer
            ? fmt(P.otpRequiredAbove) + '을 넘는 이체에는 디지털 OTP가 필요해요.'
            : '한도를 올리려면 디지털 OTP가 먼저 필요해요.',
          current: ctx.otpRegistered ? '등록됨' : '미등록',
          action: '디지털 OTP 등록 화면에서 이 기기를 등록해요.',
          expected: '고액 이체 인증과 한도 상향이 가능해져요.',
          ruleIds: needForTransfer ? ['R02', 'R03'] : ['R03'],
        };
      }
      case 'CHANGE_TRANSFER_LIMIT':
        return {
          problem: '요청 금액 ' + fmt(ctx.amount) + '이 1일 이체한도를 넘어요.',
          current: '1일 이체한도 ' + fmt(ctx.transferLimit),
          action: '이체한도를 ' + fmt(ctx.amount) + ' 이상으로 변경해요.',
          expected: '요청 금액을 보낼 수 있는 한도가 확보돼요.',
          ruleIds: ['R01'],
        };
      case 'RETURN_TO_TRANSFER':
        return {
          problem: '원래 이체는 아직 실행되지 않았어요.',
          current: '이체 정보 유지 중',
          action: '받는 분과 금액을 확인한 뒤 직접 이체를 승인해요.',
          expected: '은행이 처리 결과를 확인해 알려드려요.',
          ruleIds: [],
        };
      default:
        return { problem: '', current: '', action: '', expected: '', ruleIds: [] };
    }
  }

  WSP.pathfinder = {
    ACTIONS: ACTIONS,
    MAX_DEPTH: MAX_DEPTH,
    getAction: getAction,
    weightOf: weightOf,
    buildStateGraph: buildStateGraph,
    dijkstra: dijkstra,
    findPath: findPath,
    computePlan: computePlan,
    planFromQueryFailure: planFromQueryFailure,
    describeStep: describeStep,
    getLastResult: () => lastResult,
    setLastResult: (r) => {
      lastResult = r;
    },
  };
})();
