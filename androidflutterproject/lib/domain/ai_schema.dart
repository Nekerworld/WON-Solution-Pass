/// AI 출력은 자유 문장이 아니라 아래 구조를 따라야 한다. 시스템은 검증을 통과한
/// 행동만 실행하고, 실패하면 기본 선택지(대체 응답)로 되돌린다.
///
/// { intent, message, actions: [{ type, ... }] }
///
/// - AI는 가입 신청을 직접 실행할 수 없다 (submitApplication 금지, 고객 승인 화면에서만).
/// - AI가 제시하는 업무는 경로 계산 결과(허용 목록)에 있는 것만 가능하다.
/// - AI 문장은 '가입 완료'를 단정할 수 없다. 완료는 은행 결과 조회로만 판단한다.
library;

import 'scenario.dart';

const Map<String, List<String>> aiTypes = {
  'ASK': ['questionId', 'text'],
  'SET_CONSTRAINT': ['key', 'value'],
  'SET_INFO': ['key', 'value'],
  'PRESENT_OPTIONS': ['options'],
  'CALL_TOOL': ['tool'],
  'PROPOSE': ['text'],
  'HOLD': ['reason'],
  'ESCALATE': ['reason'],
  'EXPLAIN': ['text'],
  'STOP_QUESTIONS': [],
  'END': [],
};

const List<String> aiTools = [
  'checkConditions',
  'getLinkedAccounts',
  'getFinancialSnapshot',
  'getTaskResult',
  'computeRoute',
  'computeMetrics',
  'getApplicationResult',
];
const List<String> aiForbiddenTools = ['submitApplication', 'runTask', 'demoResolveApplication'];
final List<RegExp> aiForbiddenPhrases = [RegExp('가입이 완료'), RegExp('가입 완료됐'), RegExp('승인됐습니다'), RegExp('가입해 드렸')];

class AiAction {
  const AiAction(this.type, [this.fields = const {}]);

  final String type;
  final Map<String, Object?> fields;

  Object? operator [](String k) => fields[k];

  Map<String, Object?> toJson() => {'type': type, ...fields};
}

class AiOutput {
  const AiOutput({required this.intent, required this.message, required this.actions, this.why, this.plan, this.purpose, this.summary});

  final String intent;
  final String message;
  final List<AiAction> actions;
  final String? why;
  final String? plan;
  final String? purpose;
  final List<String>? summary;

  AiOutput copyWith({String? message, List<AiAction>? actions}) => AiOutput(
        intent: intent,
        message: message ?? this.message,
        actions: actions ?? this.actions,
        why: why,
        plan: plan,
        purpose: purpose,
        summary: summary,
      );

  Map<String, Object?> toJson() => {
        'intent': intent,
        'message': message,
        if (why != null) 'why': why,
        if (plan != null) 'plan': plan,
        if (purpose != null) 'purpose': purpose,
        if (summary != null) 'summary': summary,
        'actions': actions.map((a) => a.toJson()).toList(),
      };
}

class AiContext {
  const AiContext({this.allowedActionIds, this.allowedQuestionIds, this.infoKeys});
  final List<String>? allowedActionIds;
  final List<String>? allowedQuestionIds;
  final List<String>? infoKeys;
}

({bool valid, List<String> errors}) validateAi(AiOutput out, AiContext ctx) {
  final errors = <String>[];
  if (out.intent.isEmpty) errors.add('intent 누락');
  for (var i = 0; i < out.actions.length; i++) {
    final a = out.actions[i];
    final tag = 'actions[$i]';
    final req = aiTypes[a.type];
    if (req == null) {
      errors.add('$tag: 알 수 없는 type ${a.type}');
      continue;
    }
    for (final f in req) {
      if (!a.fields.containsKey(f)) errors.add('$tag: $f 누락');
    }
    if (a.type == 'SET_CONSTRAINT') {
      if (!constraintLabels.containsKey(a['key'])) errors.add('$tag: 허용되지 않은 고객 제약 ${a['key']}');
      if (a['value'] is! bool) errors.add('$tag: value는 true/false');
    }
    if (a.type == 'SET_INFO') {
      if (ctx.infoKeys != null && !ctx.infoKeys!.contains(a['key'])) errors.add('$tag: 허용되지 않은 정보 항목 ${a['key']}');
      if (a['value'] != null && a['value'] is! num) errors.add('$tag: value는 숫자');
    }
    if (a.type == 'PRESENT_OPTIONS') {
      final opts = a['options'];
      if (opts is! List || opts.isEmpty) {
        errors.add('$tag: options 비어 있음');
      } else if (ctx.allowedActionIds != null) {
        for (final id in opts) {
          if (!ctx.allowedActionIds!.contains(id)) errors.add('$tag: 경로 계산에 없는 업무 $id');
        }
      }
    }
    if (a.type == 'ASK' && ctx.allowedQuestionIds != null && !ctx.allowedQuestionIds!.contains(a['questionId'])) {
      errors.add('$tag: 허용되지 않은 질문 ${a['questionId']}');
    }
    if (a.type == 'CALL_TOOL') {
      if (aiForbiddenTools.contains(a['tool'])) {
        errors.add('$tag: AI가 실행할 수 없는 도구 ${a['tool']}');
      } else if (!aiTools.contains(a['tool'])) {
        errors.add('$tag: 허용 목록에 없는 도구 ${a['tool']}');
      }
    }
  }
  if (aiForbiddenPhrases.any((re) => re.hasMatch(out.message))) errors.add('message: 은행 결과 없이 완료를 단정');
  return (valid: errors.isEmpty, errors: errors);
}
