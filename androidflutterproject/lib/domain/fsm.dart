/// 상태머신 3종 (가입 지원 AI, 직접 가입, 자산관리).
/// 간선은 (from, event, to, src)이고 src는 출처다: D 기본 설계, P1~P8 보강 원칙, S 시스템 보조.
/// 전이표에 없는 전이는 거부하고 이벤트 로그에 남긴다.
library;

import 'package:flutter/foundation.dart';

import 'event_log.dart';

typedef FsmEdge = (String from, String event, String to, String src);

enum FsmKind { join, direct, asset }

class FsmDef {
  const FsmDef({required this.name, required this.initial, required this.edges});
  final String name;
  final String initial;
  final List<FsmEdge> edges;
}

List<FsmEdge> _exitP8(List<String> states, String to) => [for (final s in states) (s, 'EXIT', to, 'P8')];

final Map<FsmKind, FsmDef> fsmDefs = {
  FsmKind.join: FsmDef(
    name: '가입 지원 (AI)',
    initial: 'IDLE',
    edges: [
      ('IDLE', 'START', 'CONSENT', 'D'),
      ('CONSENT', 'AGREE', 'CHECKING', 'D'),
      ('CHECKING', 'NONE_MISSING', 'READY_TO_APPLY', 'D'),
      ('CHECKING', 'MISSING', 'CLARIFYING', 'D'),
      ('CHECKING', 'QUERY_FAILED', 'CHECK_FAILED', 'P3'),
      ('CHECK_FAILED', 'RETRY', 'CHECKING', 'P3'),
      ('CHECK_FAILED', 'ESCALATE', 'ESCALATED', 'P3'),
      ('CLARIFYING', 'CLARIFIED', 'ROUTE_CHECK', 'D'),
      ('CLARIFYING', 'ESCALATE', 'ESCALATED', 'P8'),
      ('ROUTE_CHECK', 'ROUTE_FOUND', 'OPTIONS_READY', 'D'),
      ('ROUTE_CHECK', 'NO_ROUTE', 'ESCALATED', 'D'),
      ('OPTIONS_READY', 'TASK_OPENED', 'TASK_OPEN', 'D'),
      ('OPTIONS_READY', 'CONSTRAINT_CHANGED', 'CLARIFYING', 'P4'),
      ('OPTIONS_READY', 'ESCALATE', 'ESCALATED', 'P8'),
      ('TASK_OPEN', 'MODAL_CLOSED', 'RECHECKING', 'D'),
      ('RECHECKING', 'ALL_MET', 'READY_TO_APPLY', 'D'),
      ('RECHECKING', 'REMAINING', 'REMAINING', 'D'),
      ('RECHECKING', 'EXCEPTION', 'INVESTIGATING', 'D'),
      ('REMAINING', 'TASK_OPENED', 'TASK_OPEN', 'D'),
      ('REMAINING', 'NO_ROUTE', 'ESCALATED', 'P1'),
      ('REMAINING', 'ESCALATE', 'ESCALATED', 'P8'),
      ('INVESTIGATING', 'RESOLVED', 'RECHECKING', 'P2'),
      ('INVESTIGATING', 'RETRY', 'REMAINING', 'P2'),
      ('INVESTIGATING', 'UNRESOLVABLE', 'ESCALATED', 'D'),
      ('READY_TO_APPLY', 'APPROVED', 'APPLYING', 'D'),
      ('APPLYING', 'SUBMITTED', 'VERIFYING', 'D'),
      ('APPLYING', 'NOT_SENT', 'READY_TO_APPLY', 'S'),
      ('APPLYING', 'REJECTED', 'RECHECKING', 'S'),
      ('VERIFYING', 'RESULT_SUCCESS', 'COMPLETED', 'D'),
      ('VERIFYING', 'RESULT_FAILED', 'FAILED', 'D'),
      ('VERIFYING', 'RESULT_UNKNOWN', 'RESULT_UNCERTAIN', 'D'),
      ('RESULT_UNCERTAIN', 'RESULT_QUERY', 'VERIFYING', 'S'),
      ('COMPLETED', 'NEW_CASE', 'IDLE', 'S'),
      ('FAILED', 'NEW_CASE', 'IDLE', 'S'),
      ('FAILED', 'ESCALATE', 'ESCALATED', 'P7'),
      ('ESCALATED', 'RECHECK', 'CHECKING', 'P7'),
      ('ESCALATED', 'NEW_CASE', 'IDLE', 'P7'),
      ..._exitP8(['CONSENT', 'CHECK_FAILED', 'CLARIFYING', 'OPTIONS_READY', 'REMAINING', 'INVESTIGATING', 'READY_TO_APPLY'], 'IDLE'),
    ],
  ),
  FsmKind.direct: FsmDef(
    name: '직접 가입',
    initial: 'IDLE',
    edges: [
      ('IDLE', 'START', 'D_START', 'D'),
      ('D_START', 'BEGIN', 'D_STEP', 'D'),
      ('D_STEP', 'STEP_DONE', 'D_CHECK', 'D'),
      ('D_CHECK', 'PASS', 'D_STEP', 'D'),
      ('D_CHECK', 'UNMET', 'D_NOTICE', 'D'),
      ('D_CHECK', 'ALL_PASSED', 'D_APPROVE', 'P5'),
      ('D_CHECK', 'QUERY_FAILED', 'D_STEP', 'S'),
      ('D_NOTICE', 'GO_FIX', 'D_SELF_FIX', 'D'),
      ('D_SELF_FIX', 'RESTART', 'D_STEP', 'P6'),
      ('D_APPROVE', 'APPROVED', 'D_VERIFYING', 'P5'),
      ('D_APPROVE', 'REJECTED', 'D_NOTICE', 'S'),
      ('D_VERIFYING', 'RESULT_SUCCESS', 'D_DONE', 'D'),
      ('D_VERIFYING', 'RESULT_FAILED', 'D_FAILED', 'S'),
      ('D_VERIFYING', 'RESULT_UNKNOWN', 'D_UNCERTAIN', 'S'),
      ('D_UNCERTAIN', 'RESULT_QUERY', 'D_VERIFYING', 'S'),
      ('D_DONE', 'NEW_CASE', 'IDLE', 'S'),
      ('D_FAILED', 'NEW_CASE', 'IDLE', 'S'),
      ..._exitP8(['D_START', 'D_STEP', 'D_NOTICE', 'D_SELF_FIX', 'D_APPROVE'], 'IDLE'),
    ],
  ),
  FsmKind.asset: FsmDef(
    name: '자산관리',
    initial: 'IDLE',
    edges: [
      ('IDLE', 'START', 'CONSENT', 'D'),
      ('CONSENT', 'AGREE', 'GOAL', 'D'),
      ('GOAL', 'GOAL_SET', 'COLLECTING', 'D'),
      ('COLLECTING', 'COLLECTED', 'TAGGING', 'D'),
      ('COLLECTING', 'QUERY_FAILED', 'HOLD', 'P3'),
      ('TAGGING', 'TAGGED', 'CALCULATING', 'D'),
      ('CALCULATING', 'CALCULATED', 'INTERPRETING', 'D'),
      ('INTERPRETING', 'INTERPRETED', 'GAP_CHECK', 'D'),
      ('GAP_CHECK', 'NO_GAP', 'PROPOSED_FULL', 'D'),
      ('GAP_CHECK', 'ASK', 'ASKING', 'D'),
      ('GAP_CHECK', 'LIMIT_OR_STOP', 'PROPOSABLE_CHECK', 'D'),
      ('ASKING', 'ANSWERED', 'RECALC_ANSWER', 'D'),
      ('ASKING', 'UNKNOWN_OR_REFUSED', 'PROPOSABLE_CHECK', 'D'),
      ('ASKING', 'STOP_REQUEST', 'PROPOSABLE_CHECK', 'D'),
      ('RECALC_ANSWER', 'RECALCULATED', 'INTERPRETING', 'D'),
      ('PROPOSABLE_CHECK', 'PROPOSABLE', 'PROPOSED_LIMITED', 'D'),
      ('PROPOSABLE_CHECK', 'NOT_PROPOSABLE', 'HOLD', 'D'),
      ('PROPOSED_FULL', 'SHOWN', 'REVIEW', 'D'),
      ('PROPOSED_LIMITED', 'SHOWN', 'REVIEW', 'D'),
      ('REVIEW', 'ACCEPT', 'NEXT_ACTION', 'D'),
      ('REVIEW', 'MODIFY', 'RECALC_CHANGE', 'D'),
      ('REVIEW', 'END', 'CLOSED', 'D'),
      ('RECALC_CHANGE', 'RECALCULATED', 'INTERPRETING', 'D'),
      ('NEXT_ACTION', 'CONSULT', 'HANDOFF', 'D'),
      ('NEXT_ACTION', 'KEEP', 'CLOSED', 'D'),
      ('NEXT_ACTION', 'RECHECK_INFO', 'RECONSULT', 'D'),
      ('NEXT_ACTION', 'EXPLORE', 'EXPLORE', 'D'),
      ('EXPLORE', 'PRODUCT_SELECTED', 'TO_JOIN', 'D'),
      ('EXPLORE', 'BACK', 'NEXT_ACTION', 'S'),
      ('HOLD', 'CONSULT', 'HANDOFF', 'P7'),
      ('HOLD', 'RECHECK_INFO', 'RECONSULT', 'P7'),
      ('HOLD', 'END', 'CLOSED', 'P7'),
      ('RECONSULT', 'RESUME', 'INTERPRETING', 'P7'),
      ('RECONSULT', 'END', 'CLOSED', 'P7'),
      ('HANDOFF', 'END', 'CLOSED', 'P7'),
      ('CLOSED', 'NEW_CASE', 'IDLE', 'S'),
      ('TO_JOIN', 'NEW_CASE', 'IDLE', 'S'),
      ..._exitP8(['CONSENT', 'GOAL', 'ASKING', 'GAP_CHECK', 'REVIEW', 'NEXT_ACTION', 'EXPLORE', 'HOLD'], 'CLOSED'),
    ],
  ),
};

class FsmTable {
  FsmTable._(this.table, this.src, this.states);

  final Map<String, Map<String, String>> table;
  final Map<String, String> src;

  /// 처음 등장한 순서
  final List<String> states;

  factory FsmTable.build(FsmDef def) {
    final table = <String, Map<String, String>>{};
    final src = <String, String>{};
    final states = <String>[def.initial];
    void add(String s) {
      if (!states.contains(s)) states.add(s);
    }

    for (final (from, ev, to, s) in def.edges) {
      add(from);
      add(to);
      (table[from] ??= {})[ev] = to;
      src['$from|$ev'] = s;
    }
    return FsmTable._(table, src, states);
  }
}

final Map<FsmKind, FsmTable> fsmTables = {for (final e in fsmDefs.entries) e.key: FsmTable.build(e.value)};

class TransitionRecord {
  const TransitionRecord({required this.from, required this.to, required this.event, required this.src, required this.at, this.meta});

  final String from;
  final String to;
  final String event;
  final String src;
  final DateTime at;
  final Map<String, Object?>? meta;

  Map<String, Object?> toJson() => {
        'from': from,
        'to': to,
        'event': event,
        'src': src,
        'at': at.toIso8601String(),
        if (meta != null) 'meta': meta,
      };

  static TransitionRecord? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = v.cast<String, Object?>();
    final from = j['from'], to = j['to'], ev = j['event'];
    if (from is! String || to is! String || ev is! String) return null;
    return TransitionRecord(
      from: from,
      to: to,
      event: ev,
      src: j['src'] as String? ?? 'D',
      at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
      meta: (j['meta'] as Map?)?.cast<String, Object?>(),
    );
  }
}

class TransitionResult {
  const TransitionResult({required this.ok, required this.from, required this.event, this.to});
  final bool ok;
  final String from;
  final String? to;
  final String event;
}

class Fsm extends ChangeNotifier {
  Fsm(this.kind, {this.events, this.log = true}) : _current = fsmDefs[kind]!.initial;

  final FsmKind kind;
  final EventLog? events;
  final bool log;
  String _current;
  List<TransitionRecord> _history = [];

  FsmDef get def => fsmDefs[kind]!;
  FsmTable get table => fsmTables[kind]!;
  String get state => _current;

  bool can(String event) => table.table[_current]?[event] != null;

  TransitionResult transition(String event, [Map<String, Object?>? meta]) {
    final next = table.table[_current]?[event];
    if (next == null) {
      if (log) {
        debugPrint('[WSP FSM:${kind.name}] 거부된 전이: $_current --$event-->');
        events?.add('FSM', '[${kind.name}] 거부된 전이 $_current --$event-->', {'rejected': true});
      }
      return TransitionResult(ok: false, from: _current, event: event);
    }
    final record = TransitionRecord(
      from: _current,
      to: next,
      event: event,
      src: table.src['$_current|$event'] ?? 'D',
      at: DateTime.now(),
      meta: meta,
    );
    _current = next;
    _history.add(record);
    if (_history.length > 120) _history = _history.sublist(_history.length - 120);
    if (log) events?.add('FSM', '[${kind.name}] ${record.from} --$event--> $next${record.src != 'D' ? ' (${record.src})' : ''}');
    notifyListeners();
    return TransitionResult(ok: true, from: record.from, to: next, event: event);
  }

  void reset() {
    _current = def.initial;
    _history = [];
    notifyListeners();
  }

  void restore(String state, [List<TransitionRecord>? saved]) {
    if (!table.states.contains(state)) return;
    _current = state;
    final h = saved ?? const [];
    _history = h.length > 120 ? h.sublist(h.length - 120) : List.of(h);
    notifyListeners();
  }

  List<TransitionRecord> history() => List.unmodifiable(_history);
}
