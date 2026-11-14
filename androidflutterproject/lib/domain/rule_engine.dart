/// 은행 조회 결과로 상품 가입 조건의 상태를 판정한다.
/// 상태: MET(충족) | UNMET(미충족) | UNKNOWN(미확인) | IN_PROGRESS(처리 중)
/// - 조회에 실패하면 모든 조건을 UNKNOWN으로 둔다. 미충족으로 단정하지 않는다.
/// - 조건 정의는 scenario.dart의 데이터에서 읽는다. 조건을 만들어 내지 않는다.
library;

import 'bank_state.dart';
import 'bank_types.dart';
import 'scenario.dart';

const Map<String, String> statusLabel = {'MET': '충족', 'UNMET': '미충족', 'UNKNOWN': '미확인', 'IN_PROGRESS': '처리 중'};

class CondEval {
  const CondEval({required this.id, required this.label, required this.fact, required this.status, required this.evidence, this.blocker = false});

  final String id;
  final String label;
  final String fact;
  final String status;
  final String evidence;
  final bool blocker;

  Json toJson() => {'id': id, 'label': label, 'fact': fact, 'status': status, 'evidence': evidence, 'blocker': blocker};
  factory CondEval.fromJson(Json j) => CondEval(
        id: j['id'] as String? ?? '',
        label: j['label'] as String? ?? '',
        fact: j['fact'] as String? ?? '',
        status: j['status'] as String? ?? 'UNKNOWN',
        evidence: j['evidence'] as String? ?? '',
        blocker: j['blocker'] == true,
      );
}

class Evaluation {
  const Evaluation({
    required this.productId,
    required this.ok,
    required this.conditions,
    required this.facts,
    required this.goal,
    required this.unmet,
    required this.unknown,
    required this.inProgress,
    required this.blockers,
    required this.allMet,
    required this.stateVersion,
    this.errorCode,
    this.errorMessage,
  });

  final String productId;
  final bool ok;
  final String? errorCode;
  final String? errorMessage;
  final List<CondEval> conditions;
  final Map<String, bool>? facts;
  final Map<String, bool> goal;
  final List<String> unmet;
  final List<String> unknown;
  final List<String> inProgress;
  final List<String> blockers;
  final bool allMet;
  final int? stateVersion;

  Json toJson() => {
        'productId': productId,
        'ok': ok,
        'errorCode': errorCode,
        'errorMessage': errorMessage,
        'conditions': conditions.map((c) => c.toJson()).toList(),
        'facts': facts,
        'goal': goal,
        'unmet': unmet,
        'unknown': unknown,
        'inProgress': inProgress,
        'blockers': blockers,
        'allMet': allMet,
        'stateVersion': stateVersion,
      };

  static Evaluation? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = asJson(v);
    return Evaluation(
      productId: j['productId'] as String? ?? '',
      ok: j['ok'] == true,
      errorCode: j['errorCode'] as String?,
      errorMessage: j['errorMessage'] as String?,
      conditions: asList(j['conditions']).map((c) => CondEval.fromJson(asJson(c))).toList(),
      facts: j['facts'] is Map ? asJson(j['facts']).map((k, v) => MapEntry(k, v == true)) : null,
      goal: asJson(j['goal']).map((k, v) => MapEntry(k, v == true)),
      unmet: asStrings(j['unmet']),
      unknown: asStrings(j['unknown']),
      inProgress: asStrings(j['inProgress']),
      blockers: asStrings(j['blockers']),
      allMet: j['allMet'] == true,
      stateVersion: asInt(j['stateVersion']),
    );
  }
}

Map<String, bool> _goalOf(List<String> ids) => {for (final id in ids) conditions[id]!.fact: true};

Evaluation evaluate(String productId, BankResult<ConditionsData>? resp) {
  final product = getProduct(productId);
  final ids = product?.conditions ?? const <String>[];
  if (resp == null || !resp.ok) {
    return Evaluation(
      productId: productId,
      ok: false,
      errorCode: resp?.error?.code ?? 'NO_RESPONSE',
      errorMessage: resp?.error?.message ?? '응답이 없어요.',
      conditions: [
        for (final id in ids)
          CondEval(id: id, label: conditions[id]!.label, fact: conditions[id]!.fact, status: 'UNKNOWN', evidence: '조회 실패'),
      ],
      facts: null,
      goal: _goalOf(ids),
      unmet: const [],
      unknown: List.of(ids),
      inProgress: const [],
      blockers: const [],
      allMet: false,
      stateVersion: null,
    );
  }
  final d = resp.data!;
  final list = [
    for (final c in d.conditions)
      CondEval(
        id: c.id,
        label: conditions[c.id]!.label,
        fact: conditions[c.id]!.fact,
        status: c.value ? 'MET' : (c.inProgress ? 'IN_PROGRESS' : 'UNMET'),
        evidence: conditions[c.id]!.evidence,
        blocker: conditions[c.id]!.blocker,
      ),
  ];
  List<String> pick(String st) => [for (final c in list) if (c.status == st) c.id];
  final unmet = pick('UNMET');
  return Evaluation(
    productId: productId,
    ok: true,
    conditions: list,
    facts: Map.of(d.facts),
    goal: _goalOf(ids),
    unmet: unmet,
    unknown: const [],
    inProgress: pick('IN_PROGRESS'),
    blockers: [for (final id in unmet) if (conditions[id]!.blocker) id],
    allMet: list.every((c) => c.status == 'MET'),
    stateVersion: d.stateVersion,
  );
}
