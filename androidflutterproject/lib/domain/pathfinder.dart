/// 현재 추상 상태(facts)에서 목표 상태(goal)까지의 해결 경로를 계산한다.
/// 1) 상태 그래프 생성: 현재 상태에서 출발해 사전 조건을 만족하는 행동으로 도달 가능한
///    모든 상태(노드)와 행동(간선)을 만든다. 간선 weight는 DemoPolicy.actionWeights.
/// 2) 다익스트라: 간선 weight 합이 최소인 목표 상태까지의 경로를 고른다.
/// - 방문한 상태는 직렬화 키로 식별하여 같은 상태를 중복 생성하지 않는다.
/// - 경로가 없거나 차단 사유가 있으면 상담 연결(ESCALATE_TO_SUPPORT)로 대체한다.
/// 고정된 순서 배열을 출력하지 않는다. 순서는 사전 조건, 현재 상태, 정책 가중치에서 결정된다.
library;

import 'bank_types.dart';
import 'event_log.dart';
import 'formatters.dart';
import 'policy.dart';
import 'rule_engine.dart';

const int maxDepth = 6;

/// precondition 형식
///  { fact, equals }                 : facts[fact] == equals
///  { fact, equals, constraint: id } : 규칙 엔진이 해당 제약(id)을 활성화했을 때만 적용
///  { goalSatisfied: true }          : 목표 상태의 모든 조건 충족
class Precondition {
  const Precondition.fact(this.fact, this.equals, {this.constraint}) : goalSatisfied = false;
  const Precondition.goal()
      : fact = null,
        equals = null,
        constraint = null,
        goalSatisfied = true;

  final String? fact;
  final bool? equals;
  final String? constraint;
  final bool goalSatisfied;
}

class Effect {
  const Effect(this.fact, this.value);

  final String fact;
  final bool value;
}

class StepPhrase {
  const StepPhrase({required this.first, required this.mid, required this.last});

  final String first;
  final String mid;
  final String last;
}

class ResolveAction {
  const ResolveAction({
    required this.id,
    required this.label,
    required this.flowId,
    required this.preconditions,
    required this.effects,
    required this.cta,
    this.resolves,
    this.terminal = false,
    this.fallbackOnly = false,
    this.phrase,
  });

  final String id;
  final String label;
  final String flowId;
  final String? resolves;
  final bool terminal;
  final bool fallbackOnly;
  final List<Precondition> preconditions;
  final List<Effect> effects;
  final StepPhrase? phrase;
  final String cta;
}

const List<ResolveAction> actions = [
  ResolveAction(
    id: 'COMPLETE_KYC',
    label: '고객확인 완료',
    flowId: 'kyc-flow',
    resolves: 'kycCompleted',
    preconditions: [
      Precondition.fact('kycCompleted', false),
      Precondition.fact('accountRestricted', false),
      Precondition.fact('bankAvailable', true),
    ],
    effects: [Effect('kycCompleted', true)],
    phrase: StepPhrase(first: '고객확인을 완료한', mid: '고객확인을 완료하고', last: '고객확인을 완료해 주세요'),
    cta: '고객확인 하러 가기',
  ),
  ResolveAction(
    id: 'REGISTER_OTP',
    label: '디지털 OTP 등록',
    flowId: 'otp-registration',
    resolves: 'otpRegistered',
    preconditions: [
      Precondition.fact('otpRegistered', false),
      Precondition.fact('kycCompleted', true, constraint: 'R08'),
      Precondition.fact('accountRestricted', false),
      Precondition.fact('bankAvailable', true),
    ],
    effects: [Effect('otpRegistered', true)],
    phrase: StepPhrase(first: 'OTP 등록을 진행한', mid: 'OTP 등록을 진행하고', last: 'OTP 등록을 진행해 주세요'),
    cta: '디지털 OTP 등록하러 가기',
  ),
  ResolveAction(
    id: 'CHANGE_TRANSFER_LIMIT',
    label: '이체한도 변경',
    flowId: 'limit-management',
    resolves: 'limitSufficient',
    preconditions: [
      Precondition.fact('limitSufficient', false),
      Precondition.fact('limitChangeAllowed', true),
      Precondition.fact('otpRegistered', true, constraint: 'R03'),
      Precondition.fact('accountRestricted', false),
      Precondition.fact('bankAvailable', true),
    ],
    effects: [Effect('limitSufficient', true)],
    phrase: StepPhrase(first: '한도를 변경한', mid: '한도를 변경하고', last: '한도를 변경해 주세요'),
    cta: '이체한도 변경하러 가기',
  ),
  ResolveAction(
    id: 'RETURN_TO_TRANSFER',
    label: '원래 이체로 돌아가기',
    flowId: 'transfer',
    terminal: true,
    preconditions: [Precondition.goal(), Precondition.fact('returnedToTransfer', false)],
    effects: [Effect('returnedToTransfer', true)],
    cta: '원래 이체로 돌아가기',
  ),
  ResolveAction(
    id: 'ESCALATE_TO_SUPPORT',
    label: '상담 연결',
    flowId: 'support',
    fallbackOnly: true,
    preconditions: [],
    effects: [],
    cta: '상담 연결 안내 보기',
  ),
];

ResolveAction? getAction(String id) {
  for (final a in actions) {
    if (a.id == id) return a;
  }
  return null;
}

bool goalSatisfied(Facts facts, Facts goal) => goal.keys.every((k) => facts[k] == goal[k]);

bool isGoal(Facts facts, Facts goal) => goalSatisfied(facts, goal) && facts['returnedToTransfer'] == true;

bool isApplicable(ResolveAction action, Facts facts, Facts goal, Set<String> activeConstraints) {
  if (action.fallbackOnly) return false;
  return action.preconditions.every((pre) {
    if (pre.goalSatisfied) return goalSatisfied(facts, goal);
    if (pre.constraint != null && !activeConstraints.contains(pre.constraint)) return true;
    return facts[pre.fact] == pre.equals;
  });
}

Facts applyEffects(ResolveAction action, Facts facts) {
  final next = Map<String, bool>.of(facts);
  for (final e in action.effects) {
    next[e.fact] = e.value;
  }
  return next;
}

String keyOf(Facts facts) {
  final keys = facts.keys.toList()..sort();
  return keys.map((k) => '$k:${facts[k] == true ? 1 : 0}').join('|');
}

int weightOf(ResolveAction action) {
  final w = DemoPolicy.actionWeights[action.id];
  return (w != null && w > 0) ? w : 1;
}

class GraphNode {
  const GraphNode({required this.key, required this.facts, required this.depth, required this.goal});

  final String key;
  final Facts facts;
  final int depth;
  final bool goal;
}

class GraphEdge {
  const GraphEdge({required this.from, required this.to, required this.actionId, required this.weight});

  final String from;
  final String to;
  final String actionId;
  final int weight;
}

class StateGraph {
  StateGraph({required this.startKey, required this.nodes, required this.adjacency, List<GraphEdge>? edges})
      : edges = edges ?? [];

  final String startKey;
  final Map<String, GraphNode> nodes;
  final List<GraphEdge> edges;
  final Map<String, List<GraphEdge>> adjacency;
}

/// 현재 상태에서 도달 가능한 상태 그래프를 만든다.
/// 목표 상태와 깊이 제한(maxDepth)에 닿은 노드는 더 확장하지 않는다.
StateGraph buildStateGraph(Facts startFacts, Facts goal, List<ConstraintInfo> constraints) {
  final active = constraints.map((c) => c.ruleId).toSet();
  final startKey = keyOf(startFacts);
  final nodes = <String, GraphNode>{
    startKey: GraphNode(key: startKey, facts: startFacts, depth: 0, goal: isGoal(startFacts, goal)),
  };
  final edges = <GraphEdge>[];
  final adjacency = <String, List<GraphEdge>>{};
  final queue = <String>[startKey];
  var head = 0;

  while (head < queue.length) {
    final key = queue[head++];
    final node = nodes[key]!;
    adjacency[key] = [];
    if (node.goal || node.depth >= maxDepth) continue;
    for (final action in actions) {
      if (!isApplicable(action, node.facts, goal, active)) continue;
      final next = applyEffects(action, node.facts);
      final nk = keyOf(next);
      if (!nodes.containsKey(nk)) {
        nodes[nk] = GraphNode(key: nk, facts: next, depth: node.depth + 1, goal: isGoal(next, goal));
        queue.add(nk);
      }
      final edge = GraphEdge(from: key, to: nk, actionId: action.id, weight: weightOf(action));
      edges.add(edge);
      adjacency[key]!.add(edge);
    }
  }
  return StateGraph(startKey: startKey, nodes: nodes, edges: edges, adjacency: adjacency);
}

class _HeapItem {
  _HeapItem(this.cost, this.key, this.seq);

  final int cost;
  final String key;
  final int seq;
}

/// 다익스트라용 최소 힙. 비용이 같으면 먼저 넣은 항목이 먼저 나온다.
class MinHeap {
  final List<_HeapItem> _a = [];
  int _seq = 0;

  int get size => _a.length;

  bool _less(_HeapItem x, _HeapItem y) => x.cost < y.cost || (x.cost == y.cost && x.seq < y.seq);

  void push(int cost, String key) {
    _a.add(_HeapItem(cost, key, _seq++));
    var i = _a.length - 1;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (!_less(_a[i], _a[p])) break;
      final t = _a[i];
      _a[i] = _a[p];
      _a[p] = t;
      i = p;
    }
  }

  ({int cost, String key}) pop() {
    final top = _a.first;
    final last = _a.removeLast();
    if (_a.isNotEmpty) {
      _a[0] = last;
      var i = 0;
      for (;;) {
        final l = i * 2 + 1;
        final r = l + 1;
        var m = i;
        if (l < _a.length && _less(_a[l], _a[m])) m = l;
        if (r < _a.length && _less(_a[r], _a[m])) m = r;
        if (m == i) break;
        final t = _a[i];
        _a[i] = _a[m];
        _a[m] = t;
        i = m;
      }
    }
    return (cost: top.cost, key: top.key);
  }
}

class DijkstraResult {
  const DijkstraResult({
    required this.found,
    required this.goalKey,
    required this.cost,
    required this.dist,
    required this.prev,
    required this.explored,
  });

  final bool found;
  final String? goalKey;

  /// 경로가 없으면 null (무한대)
  final int? cost;
  final Map<String, int> dist;
  final Map<String, GraphEdge> prev;
  final int explored;
}

/// 상태 그래프에서 목표 노드까지 weight 합이 최소인 경로를 찾는다.
DijkstraResult dijkstra(StateGraph graph) {
  final dist = <String, int>{graph.startKey: 0};
  final prev = <String, GraphEdge>{};
  final settled = <String>{};
  final heap = MinHeap()..push(0, graph.startKey);
  var explored = 0;

  while (heap.size > 0) {
    final (:cost, :key) = heap.pop();
    if (settled.contains(key)) continue;
    settled.add(key);
    explored += 1;
    if (graph.nodes[key]!.goal) {
      return DijkstraResult(found: true, goalKey: key, cost: cost, dist: dist, prev: prev, explored: explored);
    }
    for (final e in graph.adjacency[key] ?? const <GraphEdge>[]) {
      final nd = cost + e.weight;
      final cur = dist[e.to];
      if (cur == null || nd < cur) {
        dist[e.to] = nd;
        prev[e.to] = e;
        heap.push(nd, e.to);
      }
    }
  }
  return DijkstraResult(found: false, goalKey: null, cost: null, dist: dist, prev: prev, explored: explored);
}

class SerializedNode {
  const SerializedNode({required this.key, required this.facts, required this.depth, required this.goal, required this.dist});

  final String key;
  final Facts facts;
  final int depth;
  final bool goal;
  final int? dist;
}

class SerializedEdge {
  const SerializedEdge({
    required this.from,
    required this.to,
    required this.actionId,
    required this.weight,
    required this.onPath,
  });

  final String from;
  final String to;
  final String actionId;
  final int weight;
  final bool onPath;
}

/// 시연 제어 화면 시각화용 직렬화 그래프
class SerializedGraph {
  const SerializedGraph({required this.startKey, required this.goalKey, required this.nodes, required this.edges});

  final String startKey;
  final String? goalKey;
  final List<SerializedNode> nodes;
  final List<SerializedEdge> edges;
}

SerializedGraph _serializeGraph(StateGraph graph, DijkstraResult search, List<GraphEdge> pathEdges) {
  final onPath = pathEdges.toSet();
  return SerializedGraph(
    startKey: graph.startKey,
    goalKey: search.goalKey,
    nodes: graph.nodes.values
        .map((n) => SerializedNode(key: n.key, facts: n.facts, depth: n.depth, goal: n.goal, dist: search.dist[n.key]))
        .toList(),
    edges: graph.edges
        .map((e) => SerializedEdge(from: e.from, to: e.to, actionId: e.actionId, weight: e.weight, onPath: onPath.contains(e)))
        .toList(),
  );
}

class PlanStep {
  const PlanStep({
    required this.actionId,
    required this.label,
    required this.flowId,
    required this.weight,
    required this.before,
    required this.after,
  });

  final String actionId;
  final String label;
  final String flowId;
  final int weight;
  final Facts before;
  final Facts after;
}

class PathResult {
  const PathResult({
    required this.found,
    required this.steps,
    required this.cost,
    required this.explored,
    required this.visited,
    required this.graph,
  });

  final bool found;
  final List<PlanStep> steps;
  final int? cost;
  final int explored;
  final int visited;
  final SerializedGraph graph;
}

/// 상태 그래프 + 다익스트라 경로 탐색
PathResult findPath(Facts startFacts, Facts goal, List<ConstraintInfo> constraints) {
  final graph = buildStateGraph(startFacts, goal, constraints);
  final search = dijkstra(graph);
  final pathEdges = <GraphEdge>[];
  if (search.found) {
    var k = search.goalKey!;
    while (k != graph.startKey) {
      final e = search.prev[k]!;
      pathEdges.insert(0, e);
      k = e.from;
    }
  }
  final steps = pathEdges.map((e) {
    final action = getAction(e.actionId)!;
    return PlanStep(
      actionId: action.id,
      label: action.label,
      flowId: action.flowId,
      weight: e.weight,
      before: graph.nodes[e.from]!.facts,
      after: graph.nodes[e.to]!.facts,
    );
  }).toList();
  return PathResult(
    found: search.found,
    steps: steps,
    cost: search.found ? search.cost : null,
    explored: search.explored,
    visited: graph.nodes.length,
    graph: _serializeGraph(graph, search, pathEdges),
  );
}

/// 'PLAN'    사용자 행동이 필요한 경로가 있음
/// 'READY'   추가 절차 없이 원래 이체로 돌아갈 수 있음
/// 'BLOCKED' 자동 해결 경로 생성 금지 (계좌 제한, 시스템 장애 등)
/// 'NO_PATH' 목표에 도달하는 유효 경로 없음 -> 상담 안내
enum PlanStatus {
  plan('PLAN'),
  ready('READY'),
  blocked('BLOCKED'),
  noPath('NO_PATH');

  const PlanStatus(this.code);
  final String code;
}

class Plan {
  Plan({
    required this.status,
    required this.evaluation,
    required this.steps,
    required this.actionSteps,
    required this.explored,
    required this.visited,
    required this.computedAt,
    this.blocker,
    this.fallback,
    this.cost,
    this.graph,
    this.queryError,
  });

  final PlanStatus status;
  final Evaluation? evaluation;
  final List<PlanStep> steps;
  final List<PlanStep> actionSteps;
  final Blocker? blocker;
  final ResolveAction? fallback;
  final int? cost;
  final int explored;
  final int visited;
  final SerializedGraph? graph;
  final BankError? queryError;
  final int computedAt;

  /// 계획은 입력(규칙 컨텍스트 또는 조회 오류)에서 결정적으로 다시 계산되므로 입력만 저장한다.
  Map<String, Object?> toJson() => {
        if (evaluation != null) 'ctx': evaluation!.ctx.toJson(),
        if (evaluation == null) 'queryError': (queryError ?? blocker?.error)?.toJson(),
        'computedAt': computedAt,
      };

  static Plan? fromJson(Map<String, Object?> j) {
    final computedAt = (j['computedAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    final ctx = j['ctx'];
    if (ctx is Map) {
      return buildPlan(evaluate(RuleContext.fromJson(ctx.cast())), computedAt: computedAt);
    }
    final err = j['queryError'];
    return buildPlanFromQueryFailure(err is Map ? BankError.fromJson(err.cast()) : null, computedAt: computedAt);
  }
}

/// 규칙 평가 결과로 해결 계획을 만든다 (순수 함수).
Plan buildPlan(Evaluation evaluation, {int? computedAt}) {
  final at = computedAt ?? DateTime.now().millisecondsSinceEpoch;
  if (evaluation.blockers.isNotEmpty) {
    return Plan(
      status: PlanStatus.blocked,
      evaluation: evaluation,
      steps: const [],
      actionSteps: const [],
      blocker: evaluation.blockers.first,
      fallback: getAction('ESCALATE_TO_SUPPORT'),
      explored: 0,
      visited: 0,
      computedAt: at,
    );
  }
  final search = findPath(evaluation.facts, evaluation.goal, evaluation.constraints);
  if (!search.found) {
    return Plan(
      status: PlanStatus.noPath,
      evaluation: evaluation,
      steps: const [],
      actionSteps: const [],
      fallback: getAction('ESCALATE_TO_SUPPORT'),
      explored: search.explored,
      visited: search.visited,
      graph: search.graph,
      computedAt: at,
    );
  }
  final actionSteps = search.steps.where((s) => !getAction(s.actionId)!.terminal).toList();
  return Plan(
    status: actionSteps.isNotEmpty ? PlanStatus.plan : PlanStatus.ready,
    evaluation: evaluation,
    steps: search.steps,
    actionSteps: actionSteps,
    cost: search.cost,
    explored: search.explored,
    visited: search.visited,
    graph: search.graph,
    computedAt: at,
  );
}

/// 조회 실패 시: 정상 진단을 가장하지 않는다
Plan buildPlanFromQueryFailure(BankError? error, {int? computedAt}) => Plan(
      status: PlanStatus.blocked,
      evaluation: null,
      steps: const [],
      actionSteps: const [],
      blocker: blockerFromQueryFailure(error),
      fallback: getAction('ESCALATE_TO_SUPPORT'),
      explored: 0,
      visited: 0,
      queryError: error,
      computedAt: computedAt ?? DateTime.now().millisecondsSinceEpoch,
    );

/// 계획 계산 + 이벤트 기록 + 마지막 결과 보관 (시연 제어 화면 시각화용)
class Pathfinder {
  Pathfinder({this.events});

  final EventLog? events;
  Plan? lastResult;

  Plan computePlan(Evaluation evaluation) {
    final result = buildPlan(evaluation);
    lastResult = result;
    final chain = result.steps.map((s) => s.actionId).join(' → ');
    events?.add(
      'PATH',
      '경로 계산 [${result.status.code}] ${chain.isEmpty ? '-' : chain}'
          '${result.cost != null ? ' (비용 ${result.cost})' : ''}'
          ' · 상태 ${result.visited}개 / 확정 ${result.explored}개',
    );
    return result;
  }

  Plan planFromQueryFailure(BankError? error) {
    final result = buildPlanFromQueryFailure(error);
    lastResult = result;
    events?.add('PATH', '상태 조회 실패로 경로 계산 중단 (${error?.code})');
    return result;
  }
}

class StepDescription {
  const StepDescription({
    required this.problem,
    required this.current,
    required this.action,
    required this.expected,
    required this.ruleIds,
  });

  final String problem;
  final String current;
  final String action;
  final String expected;
  final List<String> ruleIds;
}

/// 단계 카드 표시용 설명
StepDescription describeStep(String actionId, RuleContext ctx) {
  switch (actionId) {
    case 'COMPLETE_KYC':
      return StepDescription(
        problem: '고객확인이 완료되지 않았어요.',
        current: ctx.kycCompleted ? '완료' : '미완료',
        action: '고객확인 화면에서 절차를 진행해요.',
        expected: '디지털 OTP 등록과 이체가 가능한 상태가 돼요.',
        ruleIds: const ['R04'],
      );
    case 'REGISTER_OTP':
      final needForTransfer = ctx.amount > DemoPolicy.otpRequiredAbove;
      return StepDescription(
        problem: needForTransfer
            ? '${formatWon(DemoPolicy.otpRequiredAbove)}을 넘는 이체에는 디지털 OTP가 필요해요.'
            : '한도를 올리려면 디지털 OTP가 먼저 필요해요.',
        current: ctx.otpRegistered ? '등록됨' : '미등록',
        action: '디지털 OTP 등록 화면에서 이 기기를 등록해요.',
        expected: '고액 이체 인증과 한도 상향이 가능해져요.',
        ruleIds: needForTransfer ? const ['R02', 'R03'] : const ['R03'],
      );
    case 'CHANGE_TRANSFER_LIMIT':
      return StepDescription(
        problem: '요청 금액 ${formatWon(ctx.amount)}이 1일 이체한도를 넘어요.',
        current: '1일 이체한도 ${formatWon(ctx.transferLimit)}',
        action: '이체한도를 ${formatWon(ctx.amount)} 이상으로 변경해요.',
        expected: '요청 금액을 보낼 수 있는 한도가 확보돼요.',
        ruleIds: const ['R01'],
      );
    case 'RETURN_TO_TRANSFER':
      return const StepDescription(
        problem: '원래 이체는 아직 실행되지 않았어요.',
        current: '이체 정보 유지 중',
        action: '받는 분과 금액을 확인한 뒤 직접 이체를 승인해요.',
        expected: '은행이 처리 결과를 확인해 알려드려요.',
        ruleIds: [],
      );
    default:
      return const StepDescription(problem: '', current: '', action: '', expected: '', ruleIds: []);
  }
}
