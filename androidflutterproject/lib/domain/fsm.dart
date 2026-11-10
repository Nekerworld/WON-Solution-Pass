import 'package:flutter/foundation.dart';

import 'event_log.dart';

/// 해결패스 유한 상태머신 상태
enum FsmState {
  idle('IDLE'),
  diagnosing('DIAGNOSING'),
  planReady('PLAN_READY'),
  waitingUser('WAITING_USER'),
  rechecking('RECHECKING'),
  readyToRetry('READY_TO_RETRY'),
  verifying('VERIFYING'),
  completed('COMPLETED'),
  escalated('ESCALATED'),
  resultUncertain('RESULT_UNCERTAIN');

  const FsmState(this.code);
  final String code;

  static FsmState? fromCode(String? code) {
    for (final s in FsmState.values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

enum FsmEvent {
  transferFailed('TRANSFER_FAILED'),
  manualDiagnose('MANUAL_DIAGNOSE'),
  pathFound('PATH_FOUND'),
  noActionNeeded('NO_ACTION_NEEDED'),
  escalate('ESCALATE'),
  stepSelected('STEP_SELECTED'),
  recheck('RECHECK'),
  userReturned('USER_RETURNED'),
  allMet('ALL_MET'),
  userApproved('USER_APPROVED'),
  resultSuccess('RESULT_SUCCESS'),
  resultFailed('RESULT_FAILED'),
  resultUnknown('RESULT_UNKNOWN'),
  newCase('NEW_CASE'),
  resultQuery('RESULT_QUERY');

  const FsmEvent(this.code);
  final String code;

  static FsmEvent? fromCode(String? code) {
    for (final e in FsmEvent.values) {
      if (e.code == code) return e;
    }
    return null;
  }
}

/// 전이 테이블: state -> { event: nextState }
/// - PENDING 결과는 전이 없이 VERIFYING에 머물며 결과 조회만 허용한다.
/// - COMPLETED는 VERIFYING에서 RESULT_SUCCESS로만 도달 가능하다.
/// - ESCALATED: 앱 안에서 해결할 수 없어 상담·재확인으로 넘긴 상태. 출금이 확정되지 않은
///   거래가 없으므로 NEW_CASE로 IDLE에 돌아갈 수 있다. (차단 사유, 경로 없음, 실패 확정)
/// - RESULT_UNCERTAIN: 출금 여부를 알 수 없는 거래가 있는 상태. 중복 출금을 막기 위해
///   재진단·새 건(IDLE)으로 가는 간선이 없고, 결과 조회(RESULT_QUERY)로만 빠져나간다.
const Map<FsmState, Map<FsmEvent, FsmState>> fsmTransitions = {
  FsmState.idle: {
    FsmEvent.transferFailed: FsmState.diagnosing,
    FsmEvent.manualDiagnose: FsmState.diagnosing,
  },
  FsmState.diagnosing: {
    FsmEvent.pathFound: FsmState.planReady,
    FsmEvent.noActionNeeded: FsmState.readyToRetry,
    FsmEvent.escalate: FsmState.escalated,
  },
  FsmState.planReady: {
    FsmEvent.stepSelected: FsmState.waitingUser,
    FsmEvent.recheck: FsmState.rechecking,
    FsmEvent.escalate: FsmState.escalated,
  },
  FsmState.waitingUser: {
    FsmEvent.userReturned: FsmState.rechecking,
    FsmEvent.recheck: FsmState.rechecking,
    FsmEvent.escalate: FsmState.escalated,
  },
  FsmState.rechecking: {
    FsmEvent.pathFound: FsmState.planReady,
    FsmEvent.allMet: FsmState.readyToRetry,
    FsmEvent.escalate: FsmState.escalated,
  },
  FsmState.readyToRetry: {
    FsmEvent.userApproved: FsmState.verifying,
    FsmEvent.recheck: FsmState.rechecking,
    FsmEvent.escalate: FsmState.escalated,
  },
  FsmState.verifying: {
    FsmEvent.resultSuccess: FsmState.completed,
    FsmEvent.resultFailed: FsmState.escalated,
    FsmEvent.resultUnknown: FsmState.resultUncertain,
    FsmEvent.escalate: FsmState.escalated,
  },
  FsmState.completed: {FsmEvent.newCase: FsmState.idle},
  FsmState.escalated: {FsmEvent.recheck: FsmState.rechecking, FsmEvent.newCase: FsmState.idle},
  FsmState.resultUncertain: {FsmEvent.resultQuery: FsmState.verifying},
};

class TransitionRecord {
  const TransitionRecord({required this.from, required this.to, required this.event, required this.at, this.meta});

  final FsmState from;
  final FsmState to;
  final FsmEvent event;
  final DateTime at;
  final Map<String, Object?>? meta;

  Map<String, Object?> toJson() => {
        'from': from.code,
        'to': to.code,
        'event': event.code,
        'at': at.toIso8601String(),
        if (meta != null) 'meta': meta,
      };

  static TransitionRecord? fromJson(Map<String, Object?> j) {
    final from = FsmState.fromCode(j['from'] as String?);
    final to = FsmState.fromCode(j['to'] as String?);
    final event = FsmEvent.fromCode(j['event'] as String?);
    if (from == null || to == null || event == null) return null;
    return TransitionRecord(
      from: from,
      to: to,
      event: event,
      at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
      meta: (j['meta'] as Map?)?.cast<String, Object?>(),
    );
  }
}

class TransitionResult {
  const TransitionResult({required this.ok, required this.from, required this.event, this.to});

  final bool ok;
  final FsmState from;
  final FsmState? to;
  final FsmEvent event;
}

/// 해결패스 유한 상태머신: 전이 테이블에 없는 전이는 거부한다.
class CaseFsm extends ChangeNotifier {
  CaseFsm({FsmState initial = FsmState.idle, this.events}) : _current = initial;

  /// null이면 이벤트 로그를 남기지 않는다 (테스트용).
  final EventLog? events;
  FsmState _current;
  List<TransitionRecord> _history = [];

  FsmState get state => _current;

  bool can(FsmEvent event) => fsmTransitions[_current]?[event] != null;

  TransitionResult transition(FsmEvent event, [Map<String, Object?>? meta]) {
    final next = fsmTransitions[_current]?[event];
    if (next == null) {
      if (events != null) {
        debugPrint('[WSP FSM] 거부된 전이: ${_current.code} --${event.code}--> (정의되지 않음)');
        events!.add('FSM', '거부된 전이 ${_current.code} --${event.code}-->', {'rejected': true});
      }
      return TransitionResult(ok: false, from: _current, event: event);
    }
    final record = TransitionRecord(from: _current, to: next, event: event, at: DateTime.now(), meta: meta);
    _current = next;
    _history.add(record);
    if (_history.length > 100) _history = _history.sublist(_history.length - 100);
    events?.add('FSM', '${record.from.code} --${event.code}--> ${next.code}');
    notifyListeners();
    return TransitionResult(ok: true, from: record.from, to: next, event: event);
  }

  void reset() {
    _current = FsmState.idle;
    _history = [];
    events?.add('FSM', '상태머신 초기화 → IDLE');
    notifyListeners();
  }

  void restore(FsmState state, [List<TransitionRecord>? savedHistory]) {
    _current = state;
    final h = savedHistory ?? const [];
    _history = h.length > 100 ? h.sublist(h.length - 100) : List.of(h);
    notifyListeners();
  }

  List<TransitionRecord> history() => List.unmodifiable(_history);
}
