/// 데모용 가상 정책(DemoPolicy)과 현재 고객 상태로부터
///  - 목표 상태(goal)
///  - 충족해야 할 요구사항(requirements)
///  - 자동 해결을 금지하는 차단 사유(blockers)
///  - 행동 간 선후 제약(constraints)
/// 을 계산한다. 규칙은 구조화된 데이터로 관리한다.
///
/// 실제 은행의 보안 정책·인증 규칙을 추측하여 구현하지 않는다.
library;

import 'bank_state.dart';
import 'bank_types.dart';
import 'formatters.dart';
import 'policy.dart';

typedef Facts = Map<String, bool>;

/// Mock Bank 조회 결과 + 이체 초안 -> 규칙 평가용 컨텍스트
class RuleContext {
  const RuleContext({
    required this.amount,
    required this.recipient,
    required this.recipientBank,
    required this.transferLimit,
    required this.otpRegistered,
    required this.kycCompleted,
    required this.accountRestricted,
    required this.bankAvailable,
    required this.limitChangeAllowed,
    required this.balance,
    required this.stateVersion,
    required this.checkedAt,
  });

  final int amount;
  final String? recipient;
  final String? recipientBank;
  final int transferLimit;
  final bool otpRegistered;
  final bool kycCompleted;
  final bool accountRestricted;
  final bool bankAvailable;
  final bool limitChangeAllowed;
  final int balance;
  final int stateVersion;
  final int? checkedAt;

  Map<String, Object?> toJson() => {
        'amount': amount,
        'recipient': recipient,
        'recipientBank': recipientBank,
        'transferLimit': transferLimit,
        'otpRegistered': otpRegistered,
        'kycCompleted': kycCompleted,
        'accountRestricted': accountRestricted,
        'bankAvailable': bankAvailable,
        'limitChangeAllowed': limitChangeAllowed,
        'balance': balance,
        'stateVersion': stateVersion,
        'checkedAt': checkedAt,
      };

  factory RuleContext.fromJson(Map<String, Object?> j) => RuleContext(
        amount: (j['amount'] as num).toInt(),
        recipient: j['recipient'] as String?,
        recipientBank: j['recipientBank'] as String?,
        transferLimit: (j['transferLimit'] as num).toInt(),
        otpRegistered: j['otpRegistered'] as bool,
        kycCompleted: j['kycCompleted'] as bool,
        accountRestricted: j['accountRestricted'] as bool,
        bankAvailable: j['bankAvailable'] as bool,
        limitChangeAllowed: j['limitChangeAllowed'] as bool,
        balance: (j['balance'] as num).toInt(),
        stateVersion: (j['stateVersion'] as num).toInt(),
        checkedAt: (j['checkedAt'] as num?)?.toInt(),
      );
}

enum RuleType { blocker, requirement, constraint }

class Rule {
  const Rule({
    required this.id,
    required this.type,
    required this.title,
    required this.when,
    this.code,
    this.guidance,
    this.fact,
    this.describe,
    this.action,
    this.requiresFact,
    this.relevant,
  });

  final String id;
  final RuleType type;
  final String title;
  final bool Function(RuleContext c) when;

  /// blocker
  final String? code;
  final String? guidance;

  /// requirement
  final String? fact;
  final String Function(RuleContext c)? describe;

  /// constraint
  final String? action;
  final String? requiresFact;
  final bool Function(RuleContext c, Facts f)? relevant;
}

class Requirement {
  const Requirement({required this.ruleId, required this.fact, required this.title, required this.description});

  final String ruleId;
  final String fact;
  final String title;
  final String description;
}

class Blocker {
  const Blocker({required this.ruleId, required this.code, required this.title, required this.guidance, this.error});

  final String ruleId;
  final String code;
  final String title;
  final String guidance;
  final BankError? error;
}

class ConstraintInfo {
  const ConstraintInfo({
    required this.ruleId,
    required this.action,
    required this.requiresFact,
    required this.title,
    required this.description,
    required this.binding,
  });

  final String ruleId;
  final String action;
  final String requiresFact;
  final String title;
  final String description;
  final bool binding;
}

class Evaluation {
  const Evaluation({
    required this.ctx,
    required this.facts,
    required this.goal,
    required this.requirements,
    required this.blockers,
    required this.constraints,
    required this.firedRules,
    required this.policyVersion,
  });

  final RuleContext ctx;
  final Facts facts;
  final Facts goal;
  final List<Requirement> requirements;
  final List<Blocker> blockers;
  final List<ConstraintInfo> constraints;
  final List<String> firedRules;
  final String policyVersion;
}

final List<Rule> rules = List.unmodifiable([
  Rule(
    id: 'R06',
    type: RuleType.blocker,
    code: 'BANK_UNAVAILABLE',
    title: '은행 시스템 이용 불가',
    when: (c) => !c.bankAvailable,
    guidance: '은행 상태를 확인할 수 없어 거래를 진행하지 않습니다. 잠시 후 다시 확인해 주세요.',
  ),
  Rule(
    id: 'R05',
    type: RuleType.blocker,
    code: 'ACCOUNT_RESTRICTED',
    title: '계좌 이용 제한',
    when: (c) => c.accountRestricted,
    guidance: '해결패스는 제한 해제 방법을 안내하지 않습니다. 공식 상담 창구에서 확인해 주세요.',
  ),
  Rule(
    id: 'R07',
    type: RuleType.blocker,
    code: 'INSUFFICIENT_BALANCE',
    title: '출금 가능 잔액 부족',
    when: (c) => c.amount > c.balance,
    guidance: '잔액 부족은 설정 변경으로 해결할 수 없습니다. 잔액을 확인한 뒤 다시 시도해 주세요.',
  ),
  Rule(
    id: 'R04',
    type: RuleType.requirement,
    fact: 'kycCompleted',
    title: '고객확인 필요',
    when: (c) => !c.kycCompleted,
    describe: (_) => '고객확인이 완료되지 않아 이체를 진행할 수 없습니다.',
  ),
  Rule(
    id: 'R02',
    type: RuleType.requirement,
    fact: 'otpRegistered',
    title: '디지털 OTP 등록 필요',
    when: (c) => c.amount > DemoPolicy.otpRequiredAbove && !c.otpRegistered,
    describe: (c) =>
        '${formatWon(DemoPolicy.otpRequiredAbove)}을 초과하는 ${formatWon(c.amount)} 이체에는 디지털 OTP가 필요합니다. (가상 정책)',
  ),
  Rule(
    id: 'R01',
    type: RuleType.requirement,
    fact: 'limitSufficient',
    title: '이체한도 충족 필요',
    when: (c) => c.amount > c.transferLimit,
    describe: (c) => '요청 금액 ${formatWon(c.amount)}이 1일 이체한도 ${formatWon(c.transferLimit)}을 초과합니다.',
  ),
  Rule(
    id: 'R03',
    type: RuleType.constraint,
    action: 'CHANGE_TRANSFER_LIMIT',
    requiresFact: 'otpRegistered',
    title: '한도 상향 전 디지털 OTP 등록 필요',
    when: (c) => c.amount > c.transferLimit && c.amount > DemoPolicy.maxLimitWithoutOtp,
    relevant: (c, f) => f['otpRegistered'] != true,
    describe: (_) =>
        '${formatWon(DemoPolicy.maxLimitWithoutOtp)}을 초과하는 한도로 변경하려면 디지털 OTP 등록이 먼저 필요합니다. (가상 정책)',
  ),
  Rule(
    id: 'R08',
    type: RuleType.constraint,
    action: 'REGISTER_OTP',
    requiresFact: 'kycCompleted',
    title: '디지털 OTP 등록 전 고객확인 필요',
    when: (_) => DemoPolicy.otpRegistrationRequiresKyc,
    relevant: (c, f) => f['otpRegistered'] != true && f['kycCompleted'] != true,
    describe: (_) => '디지털 OTP 등록은 고객확인 완료 후 진행할 수 있습니다. (가상 정책)',
  ),
]);

Rule? getRule(String id) {
  for (final r in rules) {
    if (r.id == id) return r;
  }
  return null;
}

RuleContext buildContext(CustomerSnapshot snapshot, TransferDraft? draft, [int? amountOverride]) {
  final amount = (amountOverride != null && amountOverride != 0) ? amountOverride : (draft?.amount ?? 0);
  return RuleContext(
    amount: amount,
    recipient: draft?.recipient,
    recipientBank: draft?.recipientBank,
    transferLimit: snapshot.transferLimit,
    otpRegistered: snapshot.digitalOtpRegistered,
    kycCompleted: snapshot.kycCompleted,
    accountRestricted: snapshot.accountRestricted,
    bankAvailable: snapshot.bankAvailable,
    limitChangeAllowed: snapshot.transferLimitChangeAllowed,
    balance: snapshot.balance,
    stateVersion: snapshot.stateVersion,
    checkedAt: snapshot.checkedAt,
  );
}

/// 경로 탐색에 쓰는 추상 상태(boolean facts)
Facts toFacts(RuleContext ctx) => {
      'otpRegistered': ctx.otpRegistered,
      'limitSufficient': ctx.amount <= ctx.transferLimit,
      'kycCompleted': ctx.kycCompleted,
      'accountRestricted': ctx.accountRestricted,
      'bankAvailable': ctx.bankAvailable,
      'limitChangeAllowed': ctx.limitChangeAllowed,
      'returnedToTransfer': false,
    };

/// 목표 상태: 이번 이체 요청과 가상 정책에서 도출한다.
/// OTP는 모든 이체에 무조건 필요한 것이 아니라 금액 기준을 넘을 때만 목표에 포함된다.
Facts buildGoal(RuleContext ctx) {
  final goal = <String, bool>{
    'kycCompleted': true,
    'limitSufficient': true,
    'accountRestricted': false,
    'bankAvailable': true,
  };
  if (ctx.amount > DemoPolicy.otpRequiredAbove) goal['otpRegistered'] = true;
  return goal;
}

Evaluation evaluate(RuleContext ctx) {
  final facts = toFacts(ctx);
  final goal = buildGoal(ctx);
  final requirements = <Requirement>[];
  final blockers = <Blocker>[];
  final constraints = <ConstraintInfo>[];
  final firedRules = <String>[];

  for (final rule in rules) {
    if (!rule.when(ctx)) continue;
    switch (rule.type) {
      case RuleType.blocker:
        blockers.add(Blocker(ruleId: rule.id, code: rule.code!, title: rule.title, guidance: rule.guidance!));
        firedRules.add(rule.id);
      case RuleType.requirement:
        requirements.add(
          Requirement(ruleId: rule.id, fact: rule.fact!, title: rule.title, description: rule.describe!(ctx)),
        );
        firedRules.add(rule.id);
      case RuleType.constraint:
        final binding = rule.relevant?.call(ctx, facts) ?? true;
        constraints.add(ConstraintInfo(
          ruleId: rule.id,
          action: rule.action!,
          requiresFact: rule.requiresFact!,
          title: rule.title,
          description: rule.describe!(ctx),
          binding: binding,
        ));
        if (binding) firedRules.add(rule.id);
    }
  }

  return Evaluation(
    ctx: ctx,
    facts: facts,
    goal: goal,
    requirements: requirements,
    blockers: blockers,
    constraints: constraints,
    firedRules: firedRules,
    policyVersion: DemoPolicy.version,
  );
}

/// 상태 조회 자체가 실패한 경우: 정상 진단을 가장하지 않고 R06 차단으로 처리
Blocker blockerFromQueryFailure(BankError? error) {
  final rule = getRule('R06')!;
  final timeout = error?.code == 'QUERY_TIMEOUT';
  return Blocker(
    ruleId: 'R06',
    code: timeout ? 'QUERY_FAILURE' : 'BANK_UNAVAILABLE',
    title: timeout ? '은행 상태 조회 실패' : rule.title,
    guidance: rule.guidance!,
    error: error,
  );
}
