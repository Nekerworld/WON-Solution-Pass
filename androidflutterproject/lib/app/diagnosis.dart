import '../data/mock_bank.dart';
import '../domain/bank_state.dart';
import '../domain/bank_types.dart';
import '../domain/pathfinder.dart';
import '../domain/rule_engine.dart';

class ComputeResult {
  const ComputeResult({
    required this.ok,
    required this.plan,
    this.error,
    this.snapshot,
    this.draft,
    this.transaction,
    this.evaluation,
  });

  final bool ok;
  final Plan plan;
  final BankError? error;
  final CustomerSnapshot? snapshot;
  final TransferDraft? draft;
  final Transaction? transaction;
  final Evaluation? evaluation;
}

/// 상태 조회 → 규칙 평가 → 경로 탐색.
/// 조회가 하나라도 실패하면 정상 진단을 가장하지 않고 R06 차단 계획을 돌려준다.
Future<ComputeResult> computeFromBank(MockBank bank, Pathfinder pathfinder) async {
  final (cs, dr) = await (bank.getCustomerState(), bank.getTransferDraft()).wait;
  final error = cs.error ?? dr.error;
  if (error != null) {
    return ComputeResult(ok: false, error: error, plan: pathfinder.planFromQueryFailure(error));
  }
  final snapshot = cs.data!;
  final draft = dr.data!.draft;
  final evaluation = evaluate(buildContext(snapshot, draft));
  final plan = pathfinder.computePlan(evaluation);
  return ComputeResult(
    ok: true,
    plan: plan,
    snapshot: snapshot,
    draft: draft,
    transaction: dr.data!.transaction,
    evaluation: evaluation,
  );
}
