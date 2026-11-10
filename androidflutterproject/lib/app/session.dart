import '../domain/bank_state.dart';
import '../domain/bank_types.dart';
import '../domain/chatbot_nlu.dart';
import '../domain/pathfinder.dart';
import 'chatbot_service.dart';

class Escalation {
  const Escalation({required this.code, required this.at});

  final String code;
  final int at;

  Map<String, Object?> toJson() => {'code': code, 'at': at};

  factory Escalation.fromJson(Map<String, Object?> j) => Escalation(code: j['code'] as String, at: (j['at'] as num).toInt());
}

/// 해결 건(사건) 정보
class CaseCtx {
  CaseCtx({
    required this.caseId,
    required this.trigger,
    required this.startedAt,
    required this.reasons,
    List<String>? timeline,
    this.escalation,
  }) : timeline = timeline ?? [];

  final String caseId;
  final String trigger;
  final int startedAt;
  List<RejectReason> reasons;

  /// 이번 건에서 안내된 해결 행동 ID (순서 유지)
  final List<String> timeline;
  Escalation? escalation;

  Map<String, Object?> toJson() => {
        'caseId': caseId,
        'trigger': trigger,
        'startedAt': startedAt,
        'reasons': reasons.map((r) => r.toJson()).toList(),
        'timeline': timeline,
        'escalation': escalation?.toJson(),
      };

  factory CaseCtx.fromJson(Map<String, Object?> j) => CaseCtx(
        caseId: j['caseId'] as String,
        trigger: j['trigger'] as String? ?? 'MANUAL',
        startedAt: (j['startedAt'] as num?)?.toInt() ?? 0,
        reasons: ((j['reasons'] as List?) ?? const []).map((r) => RejectReason.fromJson((r as Map).cast())).toList(),
        timeline: ((j['timeline'] as List?) ?? const []).cast<String>().toList(),
        escalation: j['escalation'] is Map ? Escalation.fromJson((j['escalation'] as Map).cast()) : null,
      );
}

class ResultCtx {
  const ResultCtx({required this.transactionId, required this.viaPass, required this.duplicate});

  final String transactionId;
  final bool viaPass;
  final bool duplicate;

  Map<String, Object?> toJson() => {'transactionId': transactionId, 'viaPass': viaPass, 'duplicate': duplicate};

  factory ResultCtx.fromJson(Map<String, Object?> j) => ResultCtx(
        transactionId: j['transactionId'] as String,
        viaPass: j['viaPass'] as bool? ?? false,
        duplicate: j['duplicate'] as bool? ?? false,
      );
}

class ChatMessage {
  const ChatMessage({
    required this.isUser,
    required this.text,
    this.links = const [],
    this.tone = Tone.normal,
    this.intents = const [],
    this.amount,
    this.ruleIds = const [],
    this.stateVersion,
  });

  final bool isUser;
  final String text;
  final List<FlowLink> links;
  final Tone tone;
  final List<Intent> intents;
  final int? amount;
  final List<String> ruleIds;
  final int? stateVersion;

  Map<String, Object?> toJson() => {
        'role': isUser ? 'user' : 'bot',
        'text': text,
        'links': links.map((l) => l.toJson()).toList(),
        'tone': tone.name,
        'intents': intents.map((i) => i.toJson()).toList(),
        'amount': amount,
        'ruleIds': ruleIds,
        'stateVersion': stateVersion,
      };

  factory ChatMessage.fromJson(Map<String, Object?> j) => ChatMessage(
        isUser: j['role'] == 'user',
        text: j['text'] as String? ?? '',
        links: ((j['links'] as List?) ?? const []).map((l) => FlowLink.fromJson((l as Map).cast())).toList(),
        tone: j['tone'] == 'warning' ? Tone.warning : Tone.normal,
        intents: ((j['intents'] as List?) ?? const []).map((i) => Intent.fromJson((i as Map).cast())).toList(),
        amount: (j['amount'] as num?)?.toInt(),
        ruleIds: ((j['ruleIds'] as List?) ?? const []).cast<String>().toList(),
        stateVersion: (j['stateVersion'] as num?)?.toInt(),
      );
}

/// 앱 재시작 후에도 이어서 진행할 수 있도록 저장되는 해결패스 세션
class Session {
  Session();

  CaseCtx? caseCtx;
  Plan? plan;
  ResultCtx? resultCtx;
  bool returnedFromPass = false;
  List<ChatMessage> chat = [];
  TransferDraft? lastDraft;
  int? limitSelection;
  bool hideBalance = false;
  bool hideNotice = false;

  Map<String, Object?> toJson() => {
        'caseCtx': caseCtx?.toJson(),
        'plan': plan?.toJson(),
        'resultCtx': resultCtx?.toJson(),
        'returnedFromPass': returnedFromPass,
        'chat': chat.map((m) => m.toJson()).toList(),
        'lastDraft': lastDraft?.toJson(),
        'limitSelection': limitSelection,
        'hideBalance': hideBalance,
        'hideNotice': hideNotice,
      };

  factory Session.fromJson(Map<String, Object?> j) {
    Map<String, Object?>? obj(String k) => j[k] is Map ? (j[k] as Map).cast<String, Object?>() : null;
    final s = Session();
    final caseCtx = obj('caseCtx');
    final plan = obj('plan');
    final resultCtx = obj('resultCtx');
    final lastDraft = obj('lastDraft');
    s.caseCtx = caseCtx != null ? CaseCtx.fromJson(caseCtx) : null;
    s.plan = plan != null ? Plan.fromJson(plan) : null;
    s.resultCtx = resultCtx != null ? ResultCtx.fromJson(resultCtx) : null;
    s.returnedFromPass = j['returnedFromPass'] as bool? ?? false;
    s.chat = ((j['chat'] as List?) ?? const []).map((m) => ChatMessage.fromJson((m as Map).cast())).toList();
    s.lastDraft = lastDraft != null ? TransferDraft.fromJson(lastDraft) : null;
    s.limitSelection = (j['limitSelection'] as num?)?.toInt();
    s.hideBalance = j['hideBalance'] as bool? ?? false;
    s.hideNotice = j['hideNotice'] as bool? ?? false;
    return s;
  }
}
