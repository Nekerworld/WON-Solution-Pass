/// 현재 은행 사실(facts)에서 상품 조건(goal)까지 도달하는 업무 경로를 계산한다.
/// 1) 상태 그래프: 업무의 선행 조건과 효과로 도달 가능한 상태를 펼친다.
///    고객 제약이 false인 업무는 제외하고, 모르는 제약(null)은 낙관 모드에서만 허용한다.
/// 2) 다익스트라: 업무 가중치 합이 가장 작은 경로를 고른다.
/// 3) 다음 단계의 대체 수단 목록, 필요한 질문, 경로가 없을 때의 순환 원인을 함께 돌려준다.
/// 업무와 대체 수단은 은행 데이터에서만 온다. 경로를 만들어 내지 않는다.
library;

import 'package:flutter/foundation.dart';

import 'bank_state.dart';
import 'event_log.dart';
import 'rule_engine.dart';
import 'scenario.dart';

const int maxDepth = 10;
final List<String> factKeys = facts.keys.toList();

typedef Facts = Map<String, bool>;
typedef Constraints = Map<String, bool?>;

/// 'OK' | 'UNKNOWN' | 'BLOCKED'
String availability(TaskDef action, Constraints c) {
  var result = 'OK';
  for (final k in action.needs.keys) {
    final v = c[k];
    if (v == false) {
      result = 'BLOCKED';
    } else if (v == null && result != 'BLOCKED') {
      result = 'UNKNOWN';
    }
  }
  return result;
}

List<String> unknownNeeds(TaskDef action, Constraints c) => [for (final k in action.needs.keys) if (c[k] == null) k];

bool _preOk(TaskDef a, Facts f) => a.pre.entries.every((e) => (f[e.key] ?? false) == e.value);
bool _useful(TaskDef a, Facts f) => a.effects.entries.any((e) => (f[e.key] ?? false) != e.value);
bool _allowed(TaskDef a, Constraints c, String mode) {
  final av = availability(a, c);
  return av == 'OK' || (mode == 'optimistic' && av == 'UNKNOWN');
}

bool _sameEffect(TaskDef a, TaskDef b) => b.effects.entries.any((e) => a.effects[e.key] == e.value);
bool _isGoal(Facts f, Facts goal) => goal.entries.every((e) => (f[e.key] ?? false) == e.value);
String keyOf(Facts f) => factKeys.map((k) => '$k:${f[k] == true ? 1 : 0}').join('|');

Facts _applyEffects(TaskDef a, Facts f) => {...f, ...a.effects};

class _Node {
  _Node(this.key, this.facts, this.depth, this.goal);
  final String key;
  final Facts facts;
  final int depth;
  final bool goal;
}

class _Edge {
  _Edge(this.from, this.to, this.actionId, this.weight, this.unknown);
  final String from;
  final String to;
  final String actionId;
  final int weight;
  final bool unknown;
}

class _Graph {
  _Graph(this.startKey, this.nodes, this.edges, this.adjacency);
  final String startKey;
  final Map<String, _Node> nodes;
  final List<_Edge> edges;
  final Map<String, List<_Edge>> adjacency;
}

_Graph _buildStateGraph(Facts start, Facts goal, Constraints c, String mode) {
  final startKey = keyOf(start);
  final nodes = <String, _Node>{startKey: _Node(startKey, start, 0, _isGoal(start, goal))};
  final edges = <_Edge>[];
  final adjacency = <String, List<_Edge>>{};
  final queue = <String>[startKey];
  var head = 0;
  while (head < queue.length) {
    final key = queue[head++];
    final node = nodes[key]!;
    adjacency[key] = [];
    if (node.goal || node.depth >= maxDepth) continue;
    for (final action in tasks) {
      if (!_allowed(action, c, mode) || !_preOk(action, node.facts) || !_useful(action, node.facts)) continue;
      final next = _applyEffects(action, node.facts);
      final nk = keyOf(next);
      if (!nodes.containsKey(nk)) {
        nodes[nk] = _Node(nk, next, node.depth + 1, _isGoal(next, goal));
        queue.add(nk);
      }
      final e = _Edge(key, nk, action.id, action.weight, availability(action, c) == 'UNKNOWN');
      edges.add(e);
      adjacency[key]!.add(e);
    }
  }
  return _Graph(startKey, nodes, edges, adjacency);
}

class _HeapItem {
  _HeapItem(this.cost, this.key, this.seq);
  final int cost;
  final String key;
  final int seq;
}

/// 최소 힙. 비용이 같으면 먼저 들어온 순서
class _MinHeap {
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

  _HeapItem pop() {
    final top = _a.first;
    final last = _a.removeLast();
    if (_a.isNotEmpty) {
      _a[0] = last;
      var i = 0;
      for (;;) {
        final l = i * 2 + 1, r = l + 1;
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
    return top;
  }
}

class _Search {
  _Search(this.found, this.goalKey, this.cost, this.dist, this.prev, this.explored);
  final bool found;
  final String? goalKey;
  final int? cost;
  final Map<String, int> dist;
  final Map<String, _Edge> prev;
  final int explored;
}

_Search _dijkstra(_Graph g) {
  final dist = <String, int>{g.startKey: 0};
  final prev = <String, _Edge>{};
  final settled = <String>{};
  final heap = _MinHeap()..push(0, g.startKey);
  var explored = 0;
  while (heap.size > 0) {
    final it = heap.pop();
    if (settled.contains(it.key)) continue;
    settled.add(it.key);
    explored++;
    if (g.nodes[it.key]!.goal) return _Search(true, it.key, it.cost, dist, prev, explored);
    for (final e in g.adjacency[it.key]!) {
      final nd = it.cost + e.weight;
      final cur = dist[e.to];
      if (cur == null || nd < cur) {
        dist[e.to] = nd;
        prev[e.to] = e;
        heap.push(nd, e.to);
      }
    }
  }
  return _Search(false, null, null, dist, prev, explored);
}

class GraphNode {
  const GraphNode({required this.key, required this.facts, required this.depth, required this.goal, required this.dist});
  final String key;
  final Facts facts;
  final int depth;
  final bool goal;
  final int? dist;
}

class GraphEdge {
  const GraphEdge({required this.from, required this.to, required this.actionId, required this.weight, required this.unknown, required this.onPath});
  final String from;
  final String to;
  final String actionId;
  final int weight;
  final bool unknown;
  final bool onPath;
}

class SerializedGraph {
  const SerializedGraph({required this.startKey, required this.goalKey, required this.nodes, required this.edges});
  final String startKey;
  final String? goalKey;
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
}

class PathStep {
  const PathStep({required this.actionId, required this.label, required this.weight, required this.unknown});
  final String actionId;
  final String label;
  final int weight;
  final bool unknown;

  Json toJson() => {'actionId': actionId, 'label': label, 'weight': weight, 'unknown': unknown};
  factory PathStep.fromJson(Json j) => PathStep(
        actionId: j['actionId'] as String? ?? '',
        label: j['label'] as String? ?? '',
        weight: asInt(j['weight']) ?? 1,
        unknown: j['unknown'] == true,
      );
}

class PathResult {
  const PathResult({required this.found, required this.cost, required this.steps, required this.explored, required this.visited, required this.graph});
  final bool found;
  final int? cost;
  final List<PathStep> steps;
  final int explored;
  final int visited;
  final SerializedGraph graph;
}

PathResult findPath(Facts start, Facts goal, Constraints c, [String mode = 'optimistic']) {
  final g = _buildStateGraph(start, goal, c, mode);
  final s = _dijkstra(g);
  final pathEdges = <_Edge>[];
  if (s.found) {
    var k = s.goalKey!;
    while (k != g.startKey) {
      final e = s.prev[k]!;
      pathEdges.insert(0, e);
      k = e.from;
    }
  }
  final onPath = pathEdges.toSet();
  return PathResult(
    found: s.found,
    cost: s.found ? s.cost : null,
    steps: [for (final e in pathEdges) PathStep(actionId: e.actionId, label: getTask(e.actionId)!.label, weight: e.weight, unknown: e.unknown)],
    explored: s.explored,
    visited: g.nodes.length,
    graph: SerializedGraph(
      startKey: g.startKey,
      goalKey: s.goalKey,
      nodes: [for (final n in g.nodes.values) GraphNode(key: n.key, facts: n.facts, depth: n.depth, goal: n.goal, dist: s.dist[n.key])],
      edges: [
        for (final e in g.edges)
          GraphEdge(from: e.from, to: e.to, actionId: e.actionId, weight: e.weight, unknown: e.unknown, onPath: onPath.contains(e)),
      ],
    ),
  );
}

/// 경로가 없는 원인. type: NO_METHOD | NO_TASK | CYCLE
class RouteCause {
  const RouteCause({required this.type, this.fact, this.chain = const [], this.via = const [], this.blocked = const []});
  final String type;
  final String? fact;
  final List<String> chain;
  final List<String?> via;

  /// (actionId, 막힌 제약 키 목록)
  final List<(String, List<String>)> blocked;

  Json toJson() => {
        'type': type,
        'fact': fact,
        'chain': chain,
        'via': via,
        'blocked': [for (final (a, n) in blocked) {'actionId': a, 'needs': n}],
      };

  static RouteCause? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = asJson(v);
    return RouteCause(
      type: j['type'] as String? ?? '',
      fact: j['fact'] as String?,
      chain: asStrings(j['chain']),
      via: asList(j['via']).map((e) => e as String?).toList(),
      blocked: [
        for (final b in asList(j['blocked'])) (asJson(b)['actionId'] as String? ?? '', asStrings(asJson(b)['needs'])),
      ],
    );
  }
}

/// 경로가 없을 때 원인을 찾는다.
/// - NO_METHOD: 조건을 채울 업무가 고객 제약으로 모두 막힘
/// - CYCLE: A를 하려면 B, B를 하려면 A가 필요한 순환
RouteCause? detectCycle(Facts f, Facts goal, Constraints c) {
  final unmet = [for (final e in goal.entries) if ((f[e.key] ?? false) != e.value) e.key];
  final deps = <String, List<String>>{};
  final stuck = <String>{};
  for (final fact in unmet) {
    final all = tasks.where((a) => a.effects[fact] == true).toList();
    final producers = all.where((a) => availability(a, c) != 'BLOCKED').toList();
    if (producers.isEmpty) {
      return RouteCause(
        type: all.isNotEmpty ? 'NO_METHOD' : 'NO_TASK',
        fact: fact,
        blocked: [for (final a in all) (a.id, [for (final k in a.needs.keys) if (c[k] == false) k])],
      );
    }
    final needSets = [for (final a in producers) [for (final p in a.pre.entries) if ((f[p.key] ?? false) != p.value) p.key]];
    if (needSets.every((s) => s.isNotEmpty)) stuck.add(fact);
    final d = deps[fact] = <String>[];
    for (final s in needSets) {
      for (final p in s) {
        if (!d.contains(p)) d.add(p);
      }
    }
  }
  final color = <String, int>{};
  List<String>? found;
  void dfs(String fact, List<String> path) {
    if (found != null) return;
    color[fact] = 1;
    path.add(fact);
    for (final g in deps[fact] ?? const <String>[]) {
      if (found != null || !stuck.contains(g)) continue;
      if (color[g] == 1) {
        found = [...path.sublist(path.indexOf(g)), g];
      } else if (color[g] == null) {
        dfs(g, path);
      }
    }
    path.removeLast();
    color[fact] = 2;
  }

  for (final s in stuck.toList()) {
    if (color[s] == null) dfs(s, []);
  }
  final chain = found;
  if (chain == null) return null;
  final via = <String?>[];
  for (var i = 0; i < chain.length - 1; i++) {
    TaskDef? a;
    for (final x in tasks) {
      if (x.effects[chain[i]] == true && x.pre[chain[i + 1]] == true && availability(x, c) != 'BLOCKED') {
        a = x;
        break;
      }
    }
    via.add(a?.id);
  }
  return RouteCause(type: 'CYCLE', chain: chain, via: via);
}

class RouteOption {
  const RouteOption({
    required this.actionId,
    required this.label,
    required this.availability,
    required this.reachable,
    required this.cost,
    required this.recommended,
    required this.unknownNeeds,
    required this.blockedNeeds,
    this.shown = true,
  });

  final String actionId;
  final String label;
  final String availability;
  final bool reachable;
  final int? cost;
  final bool recommended;
  final List<String> unknownNeeds;
  final List<String> blockedNeeds;

  /// 화면에서 고를 수 있는 방법인지 (가입 흐름이 AI 검증 후 채운다)
  final bool shown;

  RouteOption withShown(bool v) => RouteOption(
        actionId: actionId,
        label: label,
        availability: availability,
        reachable: reachable,
        cost: cost,
        recommended: recommended,
        unknownNeeds: unknownNeeds,
        blockedNeeds: blockedNeeds,
        shown: v,
      );

  Json toJson() => {
        'actionId': actionId,
        'label': label,
        'availability': availability,
        'reachable': reachable,
        'cost': cost,
        'recommended': recommended,
        'unknownNeeds': unknownNeeds,
        'blockedNeeds': blockedNeeds,
        'shown': shown,
      };

  factory RouteOption.fromJson(Json j) => RouteOption(
        actionId: j['actionId'] as String? ?? '',
        label: j['label'] as String? ?? '',
        availability: j['availability'] as String? ?? 'OK',
        reachable: j['reachable'] == true,
        cost: asInt(j['cost']),
        recommended: j['recommended'] == true,
        unknownNeeds: asStrings(j['unknownNeeds']),
        blockedNeeds: asStrings(j['blockedNeeds']),
        shown: j['shown'] != false,
      );
}

/// status: READY | PLAN | NO_PATH | BLOCKED | UNKNOWN
class RouteResult {
  RouteResult({
    required this.status,
    this.steps = const [],
    this.options = const [],
    this.questions = const [],
    this.blockers = const [],
    this.cost,
    this.cause,
    this.graph,
    this.visited,
    this.explored,
    int? computedAt,
  }) : computedAt = computedAt ?? DateTime.now().millisecondsSinceEpoch;

  final String status;
  final List<PathStep> steps;
  final List<RouteOption> options;
  final List<String> questions;
  final List<String> blockers;
  final int? cost;
  final RouteCause? cause;

  /// 저장하지 않는다 (시연 화면 표시용)
  final SerializedGraph? graph;
  final int? visited;
  final int? explored;
  final int computedAt;

  Json toJson() => {
        'status': status,
        'steps': steps.map((s) => s.toJson()).toList(),
        'options': options.map((o) => o.toJson()).toList(),
        'questions': questions,
        'blockers': blockers,
        'cost': cost,
        'cause': cause?.toJson(),
        'visited': visited,
        'explored': explored,
        'computedAt': computedAt,
      };

  static RouteResult? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = asJson(v);
    return RouteResult(
      status: j['status'] as String? ?? 'UNKNOWN',
      steps: asList(j['steps']).map((s) => PathStep.fromJson(asJson(s))).toList(),
      options: asList(j['options']).map((o) => RouteOption.fromJson(asJson(o))).toList(),
      questions: asStrings(j['questions']),
      blockers: asStrings(j['blockers']),
      cost: asInt(j['cost']),
      cause: RouteCause.fromJson(j['cause']),
      visited: asInt(j['visited']),
      explored: asInt(j['explored']),
      computedAt: asInt(j['computedAt']),
    );
  }
}

/// 다음 단계와 같은 효과를 내는, 지금 시작할 수 있는 대체 수단
List<RouteOption> alternativesFor(Facts f, Facts goal, Constraints c, PathStep? firstStep) {
  if (firstStep == null) return [];
  final target = getTask(firstStep.actionId)!.effects.keys;
  final list = <RouteOption>[];
  for (final a in tasks) {
    if (!target.any((t) => a.effects[t] == true) || !_preOk(a, f) || !_useful(a, f)) continue;
    final av = availability(a, c);
    final rest = av == 'BLOCKED' ? null : findPath(_applyEffects(a, f), goal, c, 'optimistic');
    list.add(RouteOption(
      actionId: a.id,
      label: a.label,
      availability: av,
      reachable: rest?.found == true,
      cost: rest != null && rest.found ? a.weight + rest.cost! : null,
      recommended: a.id == firstStep.actionId,
      unknownNeeds: unknownNeeds(a, c),
      blockedNeeds: [for (final k in a.needs.keys) if (c[k] == false) k],
    ));
  }
  final indexed = list.asMap().entries.toList()
    ..sort((x, y) {
      final a = x.value, b = y.value;
      final r = (b.recommended ? 1 : 0) - (a.recommended ? 1 : 0);
      if (r != 0) return r;
      final n = (a.cost == null ? 1 : 0) - (b.cost == null ? 1 : 0);
      if (n != 0) return n;
      if (a.cost != null && b.cost != null && a.cost != b.cost) return a.cost! - b.cost!;
      return x.key - y.key;
    });
  return [for (final e in indexed) e.value];
}

class Pathfinder extends ChangeNotifier {
  Pathfinder({this.events});

  final EventLog? events;
  RouteResult? _last;

  RouteResult? get lastResult => _last;
  set lastResult(RouteResult? r) {
    _last = r;
    notifyListeners();
  }

  /// 조건 판정 결과(evaluation)와 고객 제약으로 해결 경로를 계산한다.
  RouteResult computeRoute(Evaluation ev, Constraints c) {
    RouteResult result;
    if (!ev.ok) {
      result = RouteResult(status: 'UNKNOWN');
    } else if (ev.blockers.isNotEmpty) {
      result = RouteResult(status: 'BLOCKED', blockers: ev.blockers);
    } else if (ev.allMet) {
      result = RouteResult(status: 'READY', cost: 0);
    } else {
      final f = ev.facts!;
      final goal = ev.goal;
      final opt = findPath(f, goal, c, 'optimistic');
      if (!opt.found) {
        result = RouteResult(
          status: 'NO_PATH',
          cause: detectCycle(f, goal, c),
          graph: opt.graph,
          visited: opt.visited,
          explored: opt.explored,
        );
      } else {
        // 확인된 제약만으로 갈 수 있는 경로가 있으면 묻지 않고 그 경로를 기본으로 쓴다.
        final known = findPath(f, goal, c, 'known');
        final base = known.found ? known : opt;
        final questions = <String>[];
        if (!known.found) {
          for (final s in opt.steps) {
            final a = getTask(s.actionId)!;
            if (unknownNeeds(a, c).isEmpty) continue;
            for (final x in tasks.where((x) => _sameEffect(x, a))) {
              for (final k in unknownNeeds(x, c)) {
                if (!questions.contains(k)) questions.add(k);
              }
            }
          }
        }
        result = RouteResult(
          status: 'PLAN',
          steps: base.steps,
          cost: base.cost,
          questions: questions,
          options: alternativesFor(f, goal, c, base.steps.isEmpty ? null : base.steps.first),
          graph: base.graph,
          visited: base.visited,
          explored: base.explored,
        );
      }
    }
    lastResult = result;
    final path = result.steps.map((s) => s.actionId).join(' → ');
    events?.add('PATH', '경로 계산 [${result.status}] ${path.isEmpty ? '-' : path}${result.cost != null ? ' (비용 ${result.cost})' : ''}');
    return result;
  }
}
