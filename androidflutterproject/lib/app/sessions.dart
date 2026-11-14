/// 화면 세션: 가입 지원(AI) / 직접 가입 / 자산관리. 앱을 다시 열면 복원한다.
library;

import '../domain/asset_advisor.dart' as aa;
import '../domain/bank_state.dart';
import '../domain/pathfinder.dart';
import '../domain/rule_engine.dart';

int nowMs() => DateTime.now().millisecondsSinceEpoch;

class ChatMsg {
  ChatMsg({
    required this.id,
    required this.at,
    required this.role,
    required this.text,
    this.tone,
    this.kind,
    this.fallback = false,
    this.why,
    this.key,
    this.plan,
    this.figures,
    this.level,
  });

  final int id;
  final int at;

  /// ai | user | system
  final String role;
  final String text;
  final String? tone;
  final String? kind;
  final bool fallback;
  final String? why;
  final String? key;
  final List<String>? plan;
  final List<aa.Figure>? figures;
  final String? level;

  Json toJson() => {
        'id': id,
        'at': at,
        'role': role,
        'text': text,
        if (tone != null) 'tone': tone,
        if (kind != null) 'kind': kind,
        if (fallback) 'fallback': true,
        if (why != null) 'why': why,
        if (key != null) 'key': key,
        if (plan != null) 'plan': plan,
        if (figures != null) 'figures': figures!.map((f) => f.toJson()).toList(),
        if (level != null) 'level': level,
      };

  factory ChatMsg.fromJson(Json j) => ChatMsg(
        id: asInt(j['id']) ?? 0,
        at: asInt(j['at']) ?? 0,
        role: j['role'] as String? ?? 'ai',
        text: j['text'] as String? ?? '',
        tone: j['tone'] as String?,
        kind: j['kind'] as String?,
        fallback: j['fallback'] == true,
        why: j['why'] as String?,
        key: j['key'] as String?,
        plan: j['plan'] is List ? asStrings(j['plan']) : null,
        figures: j['figures'] is List ? asList(j['figures']).map((f) => aa.Figure.fromJson(asJson(f))).toList() : null,
        level: j['level'] as String?,
      );
}

class Escalation {
  Escalation({required this.reason, required this.text, this.cause, int? at}) : at = at ?? nowMs();
  final String reason;
  final String text;
  final RouteCause? cause;
  final int at;

  Json toJson() => {'reason': reason, 'text': text, 'cause': cause?.toJson(), 'at': at};
  static Escalation? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = asJson(v);
    return Escalation(reason: j['reason'] as String? ?? 'CUSTOMER_REQUEST', text: j['text'] as String? ?? '', cause: RouteCause.fromJson(j['cause']), at: asInt(j['at']));
  }
}

class ConsultState {
  const ConsultState({required this.status, this.ticket});

  /// ACCEPTED | FAILED
  final String status;
  final ConsultTicket? ticket;

  Json toJson() => {'status': status, 'ticket': ticket?.toJson()};
  static ConsultState? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = asJson(v);
    return ConsultState(status: j['status'] as String? ?? 'FAILED', ticket: ConsultTicket.fromJson(j['ticket']));
  }
}

class Handoff {
  Handoff({required this.lines, required this.fallback, int? at}) : at = at ?? nowMs();
  final List<String> lines;
  final bool fallback;
  final int at;

  Json toJson() => {'lines': lines, 'fallback': fallback, 'at': at};
  static Handoff? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = asJson(v);
    return Handoff(lines: asStrings(j['lines']), fallback: j['fallback'] == true, at: asInt(j['at']));
  }
}

/// 상담 연결 화면이 공통으로 쓰는 필드
mixin SupportCase {
  Escalation? escalation;
  ConsultState? consult;
  Handoff? handoff;
  bool handoffConsent = false;

  void readSupport(Json j) {
    escalation = Escalation.fromJson(j['escalation']);
    consult = ConsultState.fromJson(j['consult']);
    handoff = Handoff.fromJson(j['handoff']);
    handoffConsent = j['handoffConsent'] == true;
  }

  Json supportJson() => {
        'escalation': escalation?.toJson(),
        'consult': consult?.toJson(),
        'handoff': handoff?.toJson(),
        'handoffConsent': handoffConsent,
      };
}

/// 자산관리 상담에서 정한 방향 (가입 지원으로 넘긴다)
class HandoffTerms {
  const HandoffTerms({required this.purpose, required this.tags, required this.monthly, required this.months, required this.goalText});
  final String purpose;
  final List<String> tags;
  final int? monthly;
  final int? months;
  final String goalText;

  Json toJson() => {'purpose': purpose, 'tags': tags, 'monthly': monthly, 'months': months, 'goalText': goalText};
  static HandoffTerms? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = asJson(v);
    return HandoffTerms(
      purpose: j['purpose'] as String? ?? '',
      tags: asStrings(j['tags']),
      monthly: asInt(j['monthly']),
      months: asInt(j['months']),
      goalText: j['goalText'] as String? ?? '',
    );
  }
}

class ApplyNotice {
  const ApplyNotice(this.tone, this.text);
  final String tone;
  final String text;
  Json toJson() => {'tone': tone, 'text': text};
  static ApplyNotice? fromJson(Object? v) => v is Map ? ApplyNotice(v['tone'] as String? ?? 'warning', v['text'] as String? ?? '') : null;
}

class CurrentTask {
  const CurrentTask({required this.taskId, required this.sessionId, required this.facts});
  final String taskId;
  final String sessionId;
  final List<String> facts;
  Json toJson() => {'taskId': taskId, 'sessionId': sessionId, 'facts': facts};
  static CurrentTask? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = asJson(v);
    return CurrentTask(taskId: j['taskId'] as String? ?? '', sessionId: j['sessionId'] as String? ?? '', facts: asStrings(j['facts']));
  }
}

class TaskRecord {
  const TaskRecord({required this.taskId, required this.sessionId, required this.status, required this.reflected, required this.at});
  final String taskId;
  final String sessionId;
  final String? status;
  final bool reflected;
  final int at;
  Json toJson() => {'taskId': taskId, 'sessionId': sessionId, 'status': status, 'reflected': reflected, 'at': at};
  factory TaskRecord.fromJson(Json j) => TaskRecord(
        taskId: j['taskId'] as String? ?? '',
        sessionId: j['sessionId'] as String? ?? '',
        status: j['status'] as String?,
        reflected: j['reflected'] == true,
        at: asInt(j['at']) ?? 0,
      );
}

class JoinException {
  JoinException({required this.cause, this.taskId, this.sessionId, this.facts = const [], int? at, this.explained = false}) : at = at ?? nowMs();

  /// QUERY_FAILED | IN_PROGRESS | ERROR | MISMATCH
  final String cause;
  final String? taskId;
  final String? sessionId;
  final List<String> facts;
  final int at;
  bool explained;

  Json toJson() => {'cause': cause, 'taskId': taskId, 'sessionId': sessionId, 'facts': facts, 'at': at, 'explained': explained};
  static JoinException? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = asJson(v);
    return JoinException(
      cause: j['cause'] as String? ?? 'QUERY_FAILED',
      taskId: j['taskId'] as String?,
      sessionId: j['sessionId'] as String?,
      facts: asStrings(j['facts']),
      at: asInt(j['at']),
      explained: j['explained'] == true,
    );
  }
}

class JoinMetrics {
  JoinMetrics({int? startedAt, this.endedAt, this.questions = 0, this.tasks = 0, this.screens = 1}) : startedAt = startedAt ?? nowMs();
  final int startedAt;
  int? endedAt;
  int questions;
  int tasks;
  int screens;

  Json toJson() => {'startedAt': startedAt, 'endedAt': endedAt, 'questions': questions, 'tasks': tasks, 'screens': screens};
  static JoinMetrics? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = asJson(v);
    return JoinMetrics(
      startedAt: asInt(j['startedAt']),
      endedAt: asInt(j['endedAt']),
      questions: asInt(j['questions']) ?? 0,
      tasks: asInt(j['tasks']) ?? 0,
      screens: asInt(j['screens']) ?? 1,
    );
  }
}

class JoinSession with SupportCase {
  JoinSession({required this.caseId, required this.productId, this.assetContext, JoinMetrics? metrics}) : metrics = metrics ?? JoinMetrics();

  final String caseId;
  final String productId;
  final HandoffTerms? assetContext;
  Map<String, bool?> constraints = {'hasIdCard': null, 'hasMobileId': null, 'hasOtherBankAccount': null};

  /// key -> (source, note)
  Map<String, (String, String)> constraintSource = {};

  /// (질문 라벨, 묻지 않은 이유)
  List<(String, String)> skipped = [];
  List<ChatMsg> chat = [];
  bool thinking = false;
  Evaluation? evaluation;
  RouteResult? route;
  List<RouteOption> options = [];
  String? presentedKey;
  String? pendingKey;
  int questionsAsked = 0;
  CurrentTask? currentTask;
  (String taskId, String sessionId, String? status)? lastTask;
  List<TaskRecord> tasks = [];
  Map<String, int> repeat = {};
  JoinException? exception;
  ApplyTerms? terms;
  String? requestId;
  String? appId;
  Application? application;
  ApplyNotice? applyNotice;
  final JoinMetrics metrics;

  Json toJson() => {
        'caseId': caseId,
        'productId': productId,
        'assetContext': assetContext?.toJson(),
        'constraints': constraints,
        'constraintSource': constraintSource.map((k, v) => MapEntry(k, {'source': v.$1, 'note': v.$2})),
        'skipped': [for (final (l, r) in skipped) {'label': l, 'reason': r}],
        'chat': chat.map((m) => m.toJson()).toList(),
        'thinking': thinking,
        'evaluation': evaluation?.toJson(),
        'route': route?.toJson(),
        'options': options.map((o) => o.toJson()).toList(),
        'presentedKey': presentedKey,
        'pendingKey': pendingKey,
        'questionsAsked': questionsAsked,
        'currentTask': currentTask?.toJson(),
        'lastTask': lastTask == null ? null : {'taskId': lastTask!.$1, 'sessionId': lastTask!.$2, 'status': lastTask!.$3},
        'tasks': tasks.map((t) => t.toJson()).toList(),
        'repeat': repeat,
        'exception': exception?.toJson(),
        'terms': terms?.toJson(),
        'requestId': requestId,
        'appId': appId,
        'application': application?.toJson(),
        'applyNotice': applyNotice?.toJson(),
        'metrics': metrics.toJson(),
        ...supportJson(),
      };

  static JoinSession? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = asJson(v);
    final s = JoinSession(
      caseId: j['caseId'] as String? ?? '',
      productId: j['productId'] as String? ?? 'OVERSEAS_STOCK',
      assetContext: HandoffTerms.fromJson(j['assetContext']),
      metrics: JoinMetrics.fromJson(j['metrics']),
    );
    s.constraints = {...s.constraints, ...asJson(j['constraints']).map((k, v) => MapEntry(k, v as bool?))};
    s.constraintSource = asJson(j['constraintSource']).map((k, v) => MapEntry(k, (asJson(v)['source'] as String? ?? '', asJson(v)['note'] as String? ?? '')));
    s.skipped = [for (final x in asList(j['skipped'])) (asJson(x)['label'] as String? ?? '', asJson(x)['reason'] as String? ?? '')];
    s.chat = asList(j['chat']).map((m) => ChatMsg.fromJson(asJson(m))).toList();
    s.thinking = false;
    s.evaluation = Evaluation.fromJson(j['evaluation']);
    s.route = RouteResult.fromJson(j['route']);
    s.options = asList(j['options']).map((o) => RouteOption.fromJson(asJson(o))).toList();
    s.presentedKey = j['presentedKey'] as String?;
    s.pendingKey = j['pendingKey'] as String?;
    s.questionsAsked = asInt(j['questionsAsked']) ?? 0;
    s.currentTask = CurrentTask.fromJson(j['currentTask']);
    final lt = j['lastTask'];
    if (lt is Map) s.lastTask = (lt['taskId'] as String? ?? '', lt['sessionId'] as String? ?? '', lt['status'] as String?);
    s.tasks = asList(j['tasks']).map((t) => TaskRecord.fromJson(asJson(t))).toList();
    s.repeat = asJson(j['repeat']).map((k, v) => MapEntry(k, asInt(v) ?? 0));
    s.exception = JoinException.fromJson(j['exception']);
    s.terms = ApplyTerms.fromJson(j['terms']);
    s.requestId = j['requestId'] as String?;
    s.appId = j['appId'] as String?;
    s.application = Application.fromJson(j['application']);
    s.applyNotice = ApplyNotice.fromJson(j['applyNotice']);
    s.readSupport(j);
    return s;
  }
}

class DirectInput {
  DirectInput({this.agreed = false, this.monthly = 300000, this.months = 0});
  bool agreed;
  int monthly;
  int months;

  Json toJson() => {'agreed': agreed, 'monthly': monthly, 'months': months};
  factory DirectInput.fromJson(Json j) => DirectInput(agreed: j['agreed'] == true, monthly: asInt(j['monthly']) ?? 300000, months: asInt(j['months']) ?? 0);
}

class NoticeCondition {
  const NoticeCondition({this.id, required this.label, this.menu});
  final String? id;
  final String label;
  final String? menu;
  Json toJson() => {'id': id, 'label': label, 'menu': menu};
  factory NoticeCondition.fromJson(Json j) => NoticeCondition(id: j['id'] as String?, label: j['label'] as String? ?? '', menu: j['menu'] as String?);
}

class DirectNotice {
  const DirectNotice({required this.stepId, required this.stepLabel, required this.conditions});
  final String stepId;
  final String stepLabel;
  final List<NoticeCondition> conditions;
  Json toJson() => {'stepId': stepId, 'stepLabel': stepLabel, 'conditions': conditions.map((c) => c.toJson()).toList()};
  static DirectNotice? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = asJson(v);
    return DirectNotice(
      stepId: j['stepId'] as String? ?? '',
      stepLabel: j['stepLabel'] as String? ?? '',
      conditions: asList(j['conditions']).map((c) => NoticeCondition.fromJson(asJson(c))).toList(),
    );
  }
}

class DirectMetrics {
  DirectMetrics({int? startedAt, this.endedAt, this.steps = 0, this.restarts = 0, this.menuVisits = 0, this.notices = 0}) : startedAt = startedAt ?? nowMs();
  final int startedAt;
  int? endedAt;
  int steps;
  int restarts;
  int menuVisits;
  int notices;

  Json toJson() => {'startedAt': startedAt, 'endedAt': endedAt, 'steps': steps, 'restarts': restarts, 'menuVisits': menuVisits, 'notices': notices};
  static DirectMetrics? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = asJson(v);
    return DirectMetrics(
      startedAt: asInt(j['startedAt']),
      endedAt: asInt(j['endedAt']),
      steps: asInt(j['steps']) ?? 0,
      restarts: asInt(j['restarts']) ?? 0,
      menuVisits: asInt(j['menuVisits']) ?? 0,
      notices: asInt(j['notices']) ?? 0,
    );
  }
}

class DirectSession {
  DirectSession({required this.productId, DirectInput? input, DirectMetrics? metrics})
      : input = input ?? DirectInput(),
        metrics = metrics ?? DirectMetrics();

  final String productId;
  int stepIndex = 0;
  final DirectInput input;
  bool checking = false;
  DirectNotice? notice;
  String? requestId;
  String? appId;
  Application? application;
  String? applyNotice;
  final DirectMetrics metrics;

  Json toJson() => {
        'productId': productId,
        'stepIndex': stepIndex,
        'input': input.toJson(),
        'notice': notice?.toJson(),
        'requestId': requestId,
        'appId': appId,
        'application': application?.toJson(),
        'applyNotice': applyNotice,
        'metrics': metrics.toJson(),
      };

  static DirectSession? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = asJson(v);
    final s = DirectSession(
      productId: j['productId'] as String? ?? 'OVERSEAS_STOCK',
      input: DirectInput.fromJson(asJson(j['input'])),
      metrics: DirectMetrics.fromJson(j['metrics']),
    );
    s.stepIndex = asInt(j['stepIndex']) ?? 0;
    s.notice = DirectNotice.fromJson(j['notice']);
    s.requestId = j['requestId'] as String?;
    s.appId = j['appId'] as String?;
    s.application = Application.fromJson(j['application']);
    s.applyNotice = j['applyNotice'] as String?;
    return s;
  }
}

class Proposal {
  Proposal({required this.level, required this.basis, required this.text, int? at}) : at = at ?? nowMs();
  final String level;
  final aa.ProposalBasis basis;
  final String text;
  final int at;

  Json toJson() => {'level': level, 'basis': basis.toJson(), 'text': text, 'at': at};
  static Proposal? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = asJson(v);
    final b = aa.ProposalBasis.fromJson(j['basis']);
    if (b == null) return null;
    return Proposal(level: j['level'] as String? ?? 'FULL', basis: b, text: j['text'] as String? ?? '', at: asInt(j['at']));
  }
}

class AssetHold {
  const AssetHold({required this.reason, required this.text, this.missing = const []});

  /// QUERY_FAILED | INSUFFICIENT
  final String reason;
  final String text;
  final List<String> missing;

  Json toJson() => {'reason': reason, 'text': text, 'missing': missing};
  static AssetHold? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = asJson(v);
    return AssetHold(reason: j['reason'] as String? ?? '', text: j['text'] as String? ?? '', missing: asStrings(j['missing']));
  }
}

class AssetSession with SupportCase {
  AssetSession({required this.caseId});

  final String caseId;
  String purpose = 'GOAL_SAVING';
  String goalText = '';
  Map<String, int> stated = {};
  aa.AssetInfo? info;
  (List<String> linked, List<String> notLinked)? coverage;
  aa.Metrics? metrics;
  List<aa.Gap> gaps = [];
  int questionsAsked = 0;
  bool stopRequested = false;
  String? pendingQuestion;
  List<ChatMsg> chat = [];
  bool thinking = false;
  Proposal? proposal;
  AssetHold? hold;
  HandoffTerms? handoffTerms;
  String? closedReason;

  Json toJson() => {
        'caseId': caseId,
        'purpose': purpose,
        'goalText': goalText,
        'stated': stated,
        'info': info?.toJson(),
        'coverage': coverage == null ? null : {'linked': coverage!.$1, 'notLinked': coverage!.$2},
        'questionsAsked': questionsAsked,
        'stopRequested': stopRequested,
        'pendingQuestion': pendingQuestion,
        'chat': chat.map((m) => m.toJson()).toList(),
        'proposal': proposal?.toJson(),
        'hold': hold?.toJson(),
        'handoffTerms': handoffTerms?.toJson(),
        'closedReason': closedReason,
        ...supportJson(),
      };

  static AssetSession? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = asJson(v);
    final s = AssetSession(caseId: j['caseId'] as String? ?? '');
    s.purpose = j['purpose'] as String? ?? 'GOAL_SAVING';
    s.goalText = j['goalText'] as String? ?? '';
    s.stated = asJson(j['stated']).map((k, v) => MapEntry(k, asInt(v) ?? 0));
    s.info = aa.AssetInfo.fromJson(j['info']);
    final cov = j['coverage'];
    if (cov is Map) s.coverage = (asStrings(cov['linked']), asStrings(cov['notLinked']));
    if (s.info != null) s.metrics = aa.computeMetrics(s.info!);
    s.questionsAsked = asInt(j['questionsAsked']) ?? 0;
    s.stopRequested = j['stopRequested'] == true;
    s.pendingQuestion = j['pendingQuestion'] as String?;
    s.chat = asList(j['chat']).map((m) => ChatMsg.fromJson(asJson(m))).toList();
    s.proposal = Proposal.fromJson(j['proposal']);
    s.hold = AssetHold.fromJson(j['hold']);
    s.handoffTerms = HandoffTerms.fromJson(j['handoffTerms']);
    s.closedReason = j['closedReason'] as String?;
    s.readSupport(j);
    return s;
  }
}

class UiPrefs {
  bool hideBalance = false;
  bool disclaimerClosed = false;
  String? lastProduct;
  Json toJson() => {'hideBalance': hideBalance, 'disclaimerClosed': disclaimerClosed, 'lastProduct': lastProduct};
}

class AppSession {
  AppSession();

  UiPrefs ui = UiPrefs();
  JoinSession? join;
  DirectSession? direct;
  AssetSession? asset;

  /// 직전 완료 건의 지표 (시연 화면 비교용)
  JoinMetrics? lastJoinMetrics;
  DirectMetrics? lastDirectMetrics;

  Json toJson() => {
        'ui': ui.toJson(),
        'join': join?.toJson(),
        'direct': direct?.toJson(),
        'asset': asset?.toJson(),
        'lastMetrics': {'join': lastJoinMetrics?.toJson(), 'direct': lastDirectMetrics?.toJson()},
      };

  factory AppSession.fromJson(Json j) {
    final s = AppSession();
    final ui = asJson(j['ui']);
    s.ui.hideBalance = ui['hideBalance'] == true;
    s.ui.disclaimerClosed = ui['disclaimerClosed'] == true;
    s.ui.lastProduct = ui['lastProduct'] as String?;
    s.join = JoinSession.fromJson(j['join']);
    s.direct = DirectSession.fromJson(j['direct']);
    s.asset = AssetSession.fromJson(j['asset']);
    final lm = asJson(j['lastMetrics']);
    s.lastJoinMetrics = JoinMetrics.fromJson(lm['join']);
    s.lastDirectMetrics = DirectMetrics.fromJson(lm['direct']);
    return s;
  }
}
