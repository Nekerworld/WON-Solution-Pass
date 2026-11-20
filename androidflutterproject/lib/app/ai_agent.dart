/// 시연용 모의 AI. 실제 AI API를 호출하지 않는다.
/// - 고객 문장 이해: 키워드 규칙
/// - 출력: ai_schema 구조화 출력 → 검증 → 실패 시 기본 선택지로 대체
/// - 말 사이 대기는 상담·가입 흐름에서 맞춘다. 여기서는 추가로 기다리지 않는다.
/// - 추적: 입력·출력·검증 결과를 시연 화면에 보여 준다.
/// AI는 질문·이해·설명·요약만 한다. 계산·판정·전이는 규칙 코드가 한다.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/ai_schema.dart';
import '../domain/asset_advisor.dart' as aa;
import '../domain/bank_state.dart';
import '../domain/event_log.dart';
import '../domain/formatters.dart';
import '../domain/pathfinder.dart';
import '../domain/rule_engine.dart';
import '../domain/scenario.dart';

class AiTraceEntry {
  const AiTraceEntry({
    required this.id,
    required this.at,
    required this.ms,
    required this.task,
    required this.input,
    required this.output,
    required this.valid,
    required this.errors,
  });

  final String id;
  final DateTime at;
  final int ms;
  final String task;
  final Map<String, Object?> input;
  final AiOutput output;
  final bool valid;
  final List<String> errors;
  bool get fallback => !valid;
}

class AiResult {
  const AiResult({required this.output, required this.valid, required this.errors, this.rejected});
  final AiOutput output;
  final bool valid;
  final List<String> errors;
  final AiOutput? rejected;
  bool get fallback => !valid;
}

const AiOutput aiFallback = AiOutput(
  intent: 'FALLBACK',
  message: '아래 선택지에서 골라 주세요.',
  actions: [AiAction('EXPLAIN', {'text': '기본 선택지 표시'})],
);

const String replyUnknown = '괜찮아요. 아는 정보로 계속할게요.';
const String replyRefused = '알겠어요. 그 부분은 빼고 계속할게요.';
const String replyStop = '알겠어요. 지금까지 들은 내용으로 알려 드릴게요.';

const Map<String, String> constraintQuestion = {
  'hasIdCard': '지금 실물 신분증(주민등록증이나 운전면허증)을 갖고 계세요?',
  'hasMobileId': '휴대폰에 모바일 신분증(모바일 운전면허·모바일 주민등록증)이 등록돼 있나요?',
  'hasOtherBankAccount': '다른 은행에 본인 명의 계좌가 있으세요?',
};
const Map<String, String> constraintWhy = {
  'hasIdCard': '실명확인 방법이 신분증 유무에 따라 달라져요.',
  'hasMobileId': '실물 신분증이 없어도 모바일 신분증으로 실명확인을 할 수 있어요.',
  'hasOtherBankAccount': '다른 은행 계좌가 있으면 1원 입금으로 계좌를 바로 만들 수 있어요.',
};

/* ------------------------------------------------------------------
 * 문장 파싱 도우미
 * ------------------------------------------------------------------ */
final _neg = RegExp(r'(없|안\s?(돼|되|갖|가지|챙|해)|못|분실|잃어|두고|아니|놓고)');
final _pos = RegExp(r'(있|가지고|갖고|챙겼|돼요|됩니다|가능|네|예|응)');
final _clauseSplit = RegExp(r'[,.!?\n]|그리고|(?<=[없있])고\s+|지만\s*|[는은]데\s*');

List<String> _clauses(String text) => text.split(_clauseSplit).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

bool? _polarity(String s) {
  if (_neg.hasMatch(s)) return false;
  if (_pos.hasMatch(s)) return true;
  return null;
}

/// 고객 문장 → 고객 제약
Map<String, bool> parseConstraints(String text, [String? pendingKey]) {
  final found = <String, bool>{};
  for (final s in _clauses(text)) {
    final p = _polarity(s);
    if (p == null) continue;
    if (RegExp(r'모바일|휴대폰\s?신분증|폰으로|휴대폰으로').hasMatch(s)) {
      found['hasMobileId'] = p;
    } else if (RegExp(r'신분증|주민등록증|운전면허').hasMatch(s)) {
      found['hasIdCard'] = p;
    } else if (RegExp(r'다른\s?은행|타행|타\s?은행').hasMatch(s)) {
      found['hasOtherBankAccount'] = p;
    }
  }
  if (found.isEmpty && pendingKey != null) {
    final p = _polarity(text);
    if (p != null) found[pendingKey] = p;
  }
  return found;
}

int? parseAmount(String text) {
  final s = text.replaceAll(',', '');
  var m = RegExp(r'(\d+(?:\.\d+)?)\s*억(?:\s*(\d+)\s*천)?').firstMatch(s);
  if (m != null) return (double.parse(m[1]!) * 1e8 + (m[2] != null ? double.parse(m[2]!) * 1e7 : 0)).round();
  m = RegExp(r'(\d+(?:\.\d+)?)\s*천\s*만?').firstMatch(s);
  if (m != null) return (double.parse(m[1]!) * 1e7).round();
  m = RegExp(r'(\d+(?:\.\d+)?)\s*백\s*만').firstMatch(s);
  if (m != null) return (double.parse(m[1]!) * 1e6).round();
  m = RegExp(r'(\d+(?:\.\d+)?)\s*만').firstMatch(s);
  if (m != null) return (double.parse(m[1]!) * 1e4).round();
  m = RegExp(r'(\d{5,})').firstMatch(s);
  if (m != null) return int.parse(m[1]!);
  return null;
}

/// 생활비 N개월치는 지금 예금이 버티는 기간이지, 모으려는 기간이 아니다.
int? goalMonthsFrom(String text) => parseMonths(text.replaceAll(RegExp(r'\d+\s*개월\s*치'), ''));

/// 월급·지출·예금 잔액은 목표가 아니다. 문장에 남은 금액만 목표로 읽는다.
int? goalAmountFrom(String text) =>
    parseAmount(text.replaceAll(RegExp(r'(?:월급|소득|급여|지출|생활비|예금)\s*[\d,]+(?:\.\d+)?\s*(?:억|천\s*만|백만|만)?\s*원?'), ' '));

/// 투자 속도 답. 공격적은 남는 돈의 90%다.
int? paceShare(String text) {
  if (RegExp(r'공격|적극|많이|대부분').hasMatch(text)) return 90;
  if (RegExp(r'보통|절반|중간').hasMatch(text)) return 50;
  if (RegExp(r'조금|천천히|안정|보수|작게').hasMatch(text)) return 30;
  return null;
}

int? parseMonths(String text) {
  var m = RegExp(r'(\d+(?:\.\d+)?)\s*년').firstMatch(text);
  if (m != null) return (double.parse(m[1]!) * 12).round();
  m = RegExp(r'(\d+)\s*개월').firstMatch(text);
  if (m != null) return int.parse(m[1]!);
  if (text.contains('반년')) return 6;
  if (text.contains('내년')) return 12;
  return null;
}

bool isEscalate(String t) => RegExp(r'상담(원|사)?|직원|사람(이랑|과|하고)|연결해').hasMatch(t);
bool isExit(String t) => RegExp(r'그만|종료|나중에|안 할래|취소할래').hasMatch(t);
bool isMismatch(String t) => RegExp(r'(완료|끝났|했)[\s\S]*?(다시|또)|다시\s?하래|안\s?넘어가').hasMatch(t);
bool isStopQuestions(String t) => RegExp(r'질문은?\s?그만|지금\s?정보로|그냥\s?알려').hasMatch(t);

class HandoffCtx {
  const HandoffCtx({this.reason, this.reasonText, this.productName, this.done = const [], this.remaining = const [], this.constraints = const [], this.lines});
  final String? reason;
  final String? reasonText;
  final String? productName;
  final List<String> done;
  final List<String> remaining;
  final List<String> constraints;
  final List<String>? lines;
}

class AiAgent extends ChangeNotifier {
  AiAgent({required this.events, BankState Function()? bankState}) : _bankState = bankState ?? BankState.initial;

  final EventLog events;

  /// 고객 이름·은행 사실·계좌 금액을 문장에 넣을 때만 읽는다 (판정은 하지 않는다)
  final BankState Function() _bankState;
  final List<AiTraceEntry> _trace = [];
  bool _injectInvalid = false;

  List<AiTraceEntry> get trace => List.unmodifiable(_trace);
  bool get isInjecting => _injectInvalid;

  void clearTrace() {
    _trace.clear();
    notifyListeners();
  }

  void injectInvalidNext() {
    _injectInvalid = true;
    notifyListeners();
  }

  /// AI 호출 1회. producer는 구조화 출력을 만드는 순수 함수.
  Future<AiResult> run(String task, Map<String, Object?> input, AiContext ctx, AiOutput Function() producer) async {
    final t0 = DateTime.now();
    var output = producer();
    if (_injectInvalid) {
      _injectInvalid = false;
      output = output.copyWith(
        actions: [...output.actions, const AiAction('CALL_TOOL', {'tool': 'submitApplication'})],
        message: '${output.message} 가입이 완료됐어요.',
      );
    }
    final v = validateAi(output, ctx);
    _trace.add(AiTraceEntry(
      id: 'AI-${_trace.length + 1}',
      at: DateTime.now(),
      ms: DateTime.now().difference(t0).inMilliseconds,
      task: task,
      input: input,
      output: output,
      valid: v.valid,
      errors: v.errors,
    ));
    if (_trace.length > 30) _trace.removeAt(0);
    events.add('AI', '$task${v.valid ? ' → ${output.intent}' : ' → 검증 실패, 기본 선택지로 대체'}', {'level': v.valid ? 'info' : 'warn'});
    notifyListeners();
    return v.valid
        ? AiResult(output: output, valid: true, errors: const [])
        : AiResult(output: aiFallback, valid: false, errors: v.errors, rejected: output);
  }

  /* ------------------------------------------------------------------
   * 가입 지원
   * ------------------------------------------------------------------ */

  Future<AiResult> joinExplainCheck(Evaluation ev, RouteResult route) {
    return run(
      '가입 조건 설명',
      {'conditions': ev.conditions.map((c) => '${c.id}:${c.status}').toList(), 'route': route.status},
      const AiContext(),
      () {
        final cust = _bankState();
        final name = cust.customer.name;
        final unmet = ev.conditions.where((c) => c.status != 'MET').toList();
        final met = ev.conditions.where((c) => c.status == 'MET').toList();
        final needsIdentity = unmet.any((c) => c.fact == 'identityVerified');
        final overseasLeft = unmet.any((c) => c.fact == 'fxRegistered' || c.fact == 'hasFxAccount' || c.fact == 'investorProfiled');
        final String message;
        if (unmet.isEmpty) {
          message = '$name 고객님은 가입 조건을 모두 갖추셨어요. 가입 정보를 확인하고 승인만 하시면 돼요.';
        } else if (_accountReady(cust) && overseasLeft) {
          message = '해외주식에 필요한 외환거래부터 할게요.';
        } else if (cust.facts['hasDepositAccount'] != true && needsIdentity) {
          message = '$name 고객님은 우리 계좌가 없어서 실명확인부터예요.';
        } else {
          message = '$name 고객님, '
              '${met.isNotEmpty ? '${josa(met.map((c) => c.label).join(', '), '은')} 이미 충족했고, ' : ''}'
              '가입 전에 ${unmet.length}가지(${unmet.map((c) => c.label).join(', ')})가 더 필요해요.';
        }
        return AiOutput(intent: 'EXPLAIN_CONDITIONS', message: message, actions: [AiAction('EXPLAIN', {'text': message})]);
      },
    );
  }

  static bool _accountReady(BankState s) =>
      s.facts['hasDepositAccount'] == true && s.facts['identityVerified'] == true && s.facts['certRegistered'] == true && s.facts['kycDone'] == true;

  Future<AiResult> joinAsk(String key, [List<String> skipped = const []]) {
    return run(
      '고객 질문 생성',
      {'constraint': key, 'skipped': skipped},
      AiContext(allowedQuestionIds: ['Q_$key']),
      () => AiOutput(
        intent: 'ASK_CONSTRAINT',
        message: constraintQuestion[key]!,
        why: constraintWhy[key],
        actions: [AiAction('ASK', {'questionId': 'Q_$key', 'key': key, 'text': constraintQuestion[key]})],
      ),
    );
  }

  Future<AiResult> joinInterpret(String text, {String? pendingKey}) {
    return run('고객 답변 이해', {'text': text, 'pending': pendingKey}, const AiContext(), () {
      if (isEscalate(text)) {
        return const AiOutput(intent: 'REQUEST_CONSULT', message: '상담 연결을 도와드릴게요.', actions: [AiAction('ESCALATE', {'reason': 'CUSTOMER_REQUEST'})]);
      }
      if (isExit(text)) return const AiOutput(intent: 'EXIT', message: '가입 지원을 멈출게요.', actions: [AiAction('END')]);
      if (isMismatch(text)) {
        return const AiOutput(
          intent: 'REPORT_MISMATCH',
          message: '업무를 마쳤는데 다시 하라고 나왔군요. 은행 기록을 다시 조회해서 원인을 확인할게요.',
          actions: [AiAction('CALL_TOOL', {'tool': 'checkConditions'})],
        );
      }
      final found = parseConstraints(text, pendingKey);
      if (found.isEmpty) {
        return const AiOutput(intent: 'UNCLEAR', message: '말씀을 정확히 이해하지 못했어요. 아래 버튼으로 답해 주셔도 돼요.', actions: [AiAction('EXPLAIN', {'text': 'unclear'})]);
      }
      return AiOutput(
        intent: 'SET_CONSTRAINTS',
        message: '${found.entries.map((e) => '${constraintLabels[e.key]}: ${e.value ? '있음' : '없음'}').join(', ')}으로 이해했어요.',
        actions: [for (final e in found.entries) AiAction('SET_CONSTRAINT', {'key': e.key, 'value': e.value})],
      );
    });
  }

  Future<AiResult> joinPresent(RouteResult route) {
    final allowed = route.options.map((o) => o.actionId).toList();
    return run(
      '해결 방법 안내',
      {'steps': route.steps.map((s) => s.actionId).toList(), 'options': allowed},
      AiContext(allowedActionIds: allowed),
      () {
        final order = [for (var i = 0; i < route.steps.length; i++) '${i + 1}. ${route.steps[i].label}'].join('\n');
        final usable = route.options.where((o) => o.availability != 'BLOCKED' && o.reachable).toList();
        final first = route.steps.isNotEmpty ? route.steps.first : null;
        var message = first != null ? '다음은 ${josa(first.label, '을')} 도와드릴게요.' : '';
        if (_accountReady(_bankState()) && first?.actionId == 'FX_REGISTER') {
          message = '해외주식에 필요한 외환거래부터 할게요.';
        } else if (usable.length > 1) {
          message += '\n편한 방법을 골라 주세요.';
        }
        return AiOutput(
          intent: 'PRESENT_OPTIONS',
          message: message,
          plan: order,
          actions: [AiAction('PRESENT_OPTIONS', {'options': usable.map((o) => o.actionId).toList()})],
        );
      },
    );
  }

  Future<AiResult> joinExplainNoRoute(RouteCause? cause) {
    return run('경로 없음 설명', {'cause': cause?.toJson()}, const AiContext(), () {
      var message = '앱 안에서 이어서 진행할 방법을 찾지 못했어요.';
      if (cause != null && cause.type == 'CYCLE') {
        final names = cause.chain.map(factLabel).toList();
        message = '${josa(names[0], '을')} 만들려면 ${josa(names[1], '이')} 필요하고, ${josa(names[1], '을')} 만들려면 다시 ${josa(names[0], '이')} 필요해 앱 안에서는 순서가 막혀요. 상담 연결이나 영업점 방문으로 풀 수 있어요.';
      } else if (cause != null && (cause.type == 'NO_METHOD' || cause.type == 'NO_TASK')) {
        message = '${josa(factLabel(cause.fact ?? ''), '을')} 해결할 수 있는 방법이 지금 상황에서는 모두 막혀 있어요. 상담 연결을 도와드릴게요.';
      }
      return AiOutput(intent: 'NO_ROUTE', message: message, actions: [AiAction('ESCALATE', {'reason': cause?.type ?? 'NO_PATH'})]);
    });
  }

  Future<AiResult> joinAfterRecheck(String kind, [String? detail]) {
    return run('업무 후 재확인 설명', {'result': kind, 'detail': detail}, const AiContext(), () {
      final msg = switch (kind) {
        'ALL_MET' => '은행 기록으로 다시 확인했어요. 가입 조건을 모두 갖추셨어요. 이제 가입 정보를 확인하고 승인해 주세요.',
        'REMAINING' => detail ?? '은행 기록으로 다시 확인했어요. 남은 조건을 이어서 해결해요.',
        _ => '업무 결과가 은행 기록과 맞지 않거나 아직 확인되지 않았어요. 원인을 확인할게요.',
      };
      return AiOutput(intent: 'RECHECK_$kind', message: msg, actions: [AiAction('EXPLAIN', {'text': msg})]);
    });
  }

  Future<AiResult> handoffSummary(HandoffCtx ctx) {
    return run('상담 인계 요약', {'reason': ctx.reason}, const AiContext(), () {
      final lines = ctx.lines != null ? List.of(ctx.lines!) : <String>[];
      if (ctx.lines == null) lines.add('목표: ${ctx.productName ?? '상품'} 가입');
      if (ctx.done.isNotEmpty) lines.add('완료한 업무: ${ctx.done.join(', ')}');
      if (ctx.remaining.isNotEmpty) lines.add('남은 조건: ${ctx.remaining.join(', ')}');
      if (ctx.constraints.isNotEmpty) lines.add('고객 상황: ${ctx.constraints.join(', ')}');
      if (ctx.reasonText != null && ctx.reasonText!.isNotEmpty) lines.add('연결 사유: ${ctx.reasonText}');
      return AiOutput(
        intent: 'HANDOFF_SUMMARY',
        message: '',
        summary: lines,
        actions: [AiAction('ESCALATE', {'reason': ctx.reason ?? 'HANDOFF'})],
      );
    });
  }

  /* ------------------------------------------------------------------
   * 자산관리 상담
   * ------------------------------------------------------------------ */

  Future<AiResult> assetGoal(String text) {
    return run('상담 목적 이해', {'text': text}, const AiContext(infoKeys: ['goalMonths', 'goalAmount']), () {
      final purpose = RegExp(r'주식|투자|해외|미국|증권').hasMatch(text)
          ? 'INVEST'
          : RegExp(r'비상|급할\s?때|예비').hasMatch(text)
              ? 'EMERGENCY'
              : (RegExp(r'정보만으로|어디부터').hasMatch(text) ? 'ORIENT' : 'GOAL_SAVING');
      final savings = purpose == 'GOAL_SAVING' || purpose == 'INVEST';
      final months = savings ? goalMonthsFrom(text) : null;
      final amount = savings ? goalAmountFrom(text) : null;
      final actions = <AiAction>[
        if (months != null && months != 0) AiAction('SET_INFO', {'key': 'goalMonths', 'value': months, 'source': 'STATED'}),
        if (amount != null && amount != 0) AiAction('SET_INFO', {'key': 'goalAmount', 'value': amount, 'source': 'STATED'}),
      ];
      return AiOutput(intent: 'SET_PURPOSE', purpose: purpose, message: '', actions: actions);
    });
  }

  Future<AiResult> assetInterpret(aa.Metrics metrics) {
    return run('지표 해석', {'metrics': metrics.list.map((m) => '${m.key}=${m.value}').toList()}, const AiContext(), () {
      final st = _bankState();
      final income = st.finance.items['monthlyIncome']?.value;
      final expense = st.finance.items['monthlyExpense']?.value;
      final String message;
      if (income != null && expense != null) {
        message = '${st.customer.name}님의 수입은 약 ${formatMan(income)}, 지출은 약 ${formatMan(expense)}이에요.';
      } else if (metrics['surplus'].value != null) {
        message = '매달 ${metrics['surplus'].text}이 남아요.';
      } else if (metrics['needMonthly'].value != null) {
        message = '목표를 채우려면 매달 ${josa(metrics['needMonthly'].text, '이')} 필요해요${metrics.feasible == false ? '. 지금 여유보다 많아서 조정이 필요해요' : ''}.';
      } else {
        message = '지금 정보로는 계산할 수 있는 게 많지 않아요.';
      }
      return AiOutput(intent: 'INTERPRET', message: message, actions: [AiAction('EXPLAIN', {'text': message})]);
    });
  }

  Future<AiResult> assetAsk(aa.AssetQuestion q, aa.Gap gap) {
    return run(
      '추가 질문 생성',
      {'question': q.id, 'gap': gap.level},
      AiContext(allowedQuestionIds: [q.id]),
      () => AiOutput(
        intent: 'ASK_INFO',
        message: '${gap.note != null ? '${gap.note} ' : ''}${q.text}',
        why: q.why,
        actions: [AiAction('ASK', {'questionId': q.id, 'key': q.key, 'text': q.text})],
      ),
    );
  }

  Future<AiResult> assetAnswer(String text, aa.AssetQuestion? q) {
    return run('답변 이해', {'text': text, 'question': q?.id}, AiContext(infoKeys: aa.items.keys.toList()), () {
      if (isEscalate(text)) {
        return const AiOutput(intent: 'REQUEST_CONSULT', message: '상담 연결을 도와드릴게요.', actions: [AiAction('ESCALATE', {'reason': 'CUSTOMER_REQUEST'})]);
      }
      if (isStopQuestions(text)) return const AiOutput(intent: 'STOP_QUESTIONS', message: replyStop, actions: [AiAction('STOP_QUESTIONS')]);
      if (isExit(text)) return const AiOutput(intent: 'EXIT', message: '상담을 마칠게요.', actions: [AiAction('END')]);
      if (RegExp(r'모르|글쎄|잘\s?몰').hasMatch(text)) {
        return const AiOutput(intent: 'UNKNOWN', message: replyUnknown, actions: [AiAction('HOLD', {'reason': 'UNKNOWN'})]);
      }
      if (RegExp(r'말하기\s?싫|답하고\s?싶지|비밀|안\s?알려').hasMatch(text)) {
        return const AiOutput(intent: 'REFUSED', message: replyRefused, actions: [AiAction('HOLD', {'reason': 'REFUSED'})]);
      }
      if (q == null) return const AiOutput(intent: 'UNCLEAR', message: '말씀을 정확히 이해하지 못했어요.', actions: [AiAction('EXPLAIN', {'text': 'unclear'})]);
      if (q.key == 'investPace') {
        final pace = paceShare(text);
        if (pace == null) {
          return const AiOutput(intent: 'UNCLEAR', message: '조금만, 보통, 공격적 중에서 골라 주세요.', actions: [AiAction('EXPLAIN', {'text': 'unclear'})]);
        }
        return AiOutput(
          intent: 'SET_INFO',
          message: '${josa(aa.items['investPace']!.label, '을')} ${josa(aa.display('investPace', pace), '로')} 반영했어요.',
          actions: [AiAction('SET_INFO', {'key': 'investPace', 'value': pace, 'source': 'STATED'})],
        );
      }
      var value = aa.items[q.key]!.kind == 'months' ? parseMonths(text) : parseAmount(text);
      if (value == null && (q.key == 'plannedLumpSum' || q.key == 'investAssets') && text.contains('없')) value = 0;
      if (value == null) {
        return const AiOutput(intent: 'UNCLEAR', message: '금액이나 기간을 알아듣지 못했어요. 아래 버튼으로 골라 주셔도 돼요.', actions: [AiAction('EXPLAIN', {'text': 'unclear'})]);
      }
      return AiOutput(
        intent: 'SET_INFO',
        message: '${josa(aa.items[q.key]!.label, '을')} ${josa(aa.display(q.key, value), '로')} 반영했어요.',
        actions: [AiAction('SET_INFO', {'key': q.key, 'value': value, 'source': 'STATED'})],
      );
    });
  }

  Future<AiResult> assetModify(String text) {
    return run('조건 수정 이해', {'text': text}, AiContext(infoKeys: aa.items.keys.toList()), () {
      final actions = <AiAction>[];
      final months = parseMonths(text);
      final amount = parseAmount(text);
      if (months != null && months != 0) actions.add(AiAction('SET_INFO', {'key': 'goalMonths', 'value': months, 'source': 'STATED'}));
      if (amount != null) {
        var key = 'goalAmount';
        if (RegExp(r'월|매달|달마다|적립').hasMatch(text)) {
          key = 'monthlySavingPref';
        } else if (RegExp(r'소득|월급|급여').hasMatch(text)) {
          key = 'monthlyIncome';
        } else if (RegExp(r'지출|생활비').hasMatch(text)) {
          key = 'monthlyExpense';
        } else if (RegExp(r'경조사|결혼|이사|목돈.*나가').hasMatch(text)) {
          key = 'plannedLumpSum';
        }
        actions.add(AiAction('SET_INFO', {'key': key, 'value': amount, 'source': 'STATED'}));
      }
      if (actions.isEmpty) {
        return const AiOutput(intent: 'UNCLEAR', message: '바꾸실 조건을 이해하지 못했어요. 예: "기간을 3년으로", "월 80만원씩"', actions: [AiAction('EXPLAIN', {'text': 'unclear'})]);
      }
      final desc = actions.map((a) => '${aa.itemLabel(a['key'] as String)} ${aa.display(a['key'] as String, a['value'] as num)}').join(', ');
      return AiOutput(intent: 'MODIFY', message: '${josa(desc, '로')} 바꿔서 다시 계산할게요.', actions: actions);
    });
  }

  /// 목돈 마련 제안 문장: 매달 얼마씩 모으면 기간 뒤 목표에 닿는지 한 줄로 말한다
  String _goalSavingText(aa.ProposalBasis basis, aa.Metrics metrics) {
    final monthly = formatMan(basis.monthly);
    final months = basis.months;
    if (months == null || months == 0) return '매달 $monthly씩 모으면 목표에 닿아요.';
    final period = months % 12 == 0 ? '${months ~/ 12}년' : '$months개월';
    final t = metrics['target'].value, e = metrics['expectedAmount'].value;
    final short = t != null && e != null ? t - e : 0;
    if (short > 0) return '매달 $monthly씩 $period 모아도 목표보다 ${formatMan((short / 10000).round() * 10000)} 적어요.';
    return '매달 $monthly씩 $period 모으면 목표를 채울 수 있어요.';
  }

  Future<AiResult> assetPropose(aa.ProposalBasis basis, String level, aa.Metrics metrics) {
    return run(
      '방향 제안 문장',
      {
        'level': level,
        'basis': {'monthly': basis.monthly, 'months': basis.months, 'feasible': basis.feasible},
      },
      const AiContext(),
      () {
        final String text;
        final held = metrics['emergencyMonths'].value;
        const needMonths = Policy.emergencyMonths;
        if (basis.purposeId == 'EMERGENCY') {
          if (held == null) {
            text = '생활비나 예금을 확인하지 못해 충분한지 계산하기 어려워요.';
          } else if (held >= needMonths) {
            text = '예금이 생활비 ${aa.numText(held)}개월치예요. 기준인 $needMonths개월치보다 많아서, 비상자금은 충분한 편이에요.';
          } else {
            text = '예금이 생활비 ${aa.numText(held)}개월치예요. 기준은 $needMonths개월치라 아직 부족해요.';
          }
        } else if (basis.purposeId == 'ORIENT') {
          text = held == null ? '비상자금 기준은 $needMonths개월치예요.' : '비상자금 기준은 $needMonths개월치예요. 지금은 그보다 ${held >= needMonths ? '많아요.' : '적어요.'}';
        } else if (basis.monthly == null) {
          text = '지금 정보로는 월 적립액을 계산하기 어려워요.';
        } else if (basis.purposeId == 'INVEST') {
          text = '투자는 원금 손실이 날 수 있어요.';
        } else if (basis.purposeId == 'GOAL_SAVING') {
          text = _goalSavingText(basis, metrics);
        } else {
          text = '';
        }
        return AiOutput(intent: 'PROPOSE', message: text, actions: [AiAction('PROPOSE', {'text': text, 'level': level})]);
      },
    );
  }
}
