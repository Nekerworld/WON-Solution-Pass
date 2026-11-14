/// 가상 은행 API 응답 형식: { ok:true, data } | { ok:false, error }
/// kind: QUERY_FAILURE 조회 실패·시스템 이용 불가 (업무 판단 불가)
///       BUSINESS_REJECT 업무 조건 미충족으로 은행이 거절
library;

import 'bank_state.dart';

class BankError {
  const BankError({required this.code, required this.kind, required this.message, this.submitted, this.unmet, this.reasons});

  final String code;
  final String kind;
  final String message;
  final bool? submitted;

  /// CONDITION_UNMET일 때 충족하지 않은 조건 라벨
  final List<String>? unmet;
  final List<String>? reasons;

  bool get isQueryFailure => kind == 'QUERY_FAILURE';

  Json toJson() => {
        'code': code,
        'kind': kind,
        'message': message,
        if (submitted != null) 'submitted': submitted,
        if (unmet != null) 'unmet': unmet,
      };
}

class BankResult<T> {
  const BankResult.success(T this.data) : error = null;
  const BankResult.failure(BankError this.error) : data = null;

  final T? data;
  final BankError? error;

  bool get ok => error == null;
}

class ConditionFact {
  const ConditionFact({required this.id, required this.fact, required this.label, required this.value, required this.inProgress});
  final String id;
  final String fact;
  final String label;
  final bool value;
  final bool inProgress;
}

class ConditionsData {
  const ConditionsData({required this.productId, required this.conditions, required this.facts, required this.stateVersion});
  final String productId;
  final List<ConditionFact> conditions;
  final Map<String, bool> facts;
  final int stateVersion;
}

class LinkedAccounts {
  const LinkedAccounts({required this.mydataLinked, required this.linked, required this.otherBankAccounts, required this.mobileOwnerVerified});
  final bool mydataLinked;
  final List<String> linked;
  final List<OtherAccount> otherBankAccounts;
  final bool mobileOwnerVerified;
}

class FinancialSnapshot {
  const FinancialSnapshot({required this.linked, required this.notLinked, required this.items, required this.stateVersion});
  final List<String> linked;
  final List<String> notLinked;
  final Map<String, FinItem> items;
  final int stateVersion;
}

class AccountRef {
  const AccountRef(this.name, this.number);
  final String name;
  final String number;
}

class SavingRef {
  const SavingRef({required this.productId, required this.id, required this.terms});
  final String productId;
  final String id;
  final ApplyTerms? terms;
}

class AccountSummary {
  const AccountSummary({
    required this.customerName,
    required this.hasDepositAccount,
    required this.account,
    required this.fxAccount,
    required this.savings,
    required this.stateVersion,
  });

  final String customerName;
  final bool hasDepositAccount;
  final AccountRef? account;
  final AccountRef? fxAccount;
  final List<SavingRef> savings;
  final int stateVersion;
}

class TaskEligibility {
  const TaskEligibility({required this.taskId, required this.alreadyDone, required this.eligible, required this.reasons});
  final String taskId;
  final bool alreadyDone;
  final bool eligible;
  final List<String> reasons;
}

class TaskRunResult {
  const TaskRunResult({required this.sessionId, required this.status, this.message, this.stateVersion, this.duplicate = false});
  final String sessionId;
  final String status;
  final String? message;
  final int? stateVersion;
  final bool duplicate;
}

class TaskResult {
  const TaskResult({required this.sessionId, required this.taskId, required this.status, this.reflected});
  final String sessionId;
  final String taskId;
  final String status;

  /// 업무 화면의 완료가 은행 기록에 반영됐는지 (null이면 판단 대상 아님)
  final bool? reflected;
}

class SubmitResult {
  const SubmitResult({required this.application, required this.duplicate});
  final Application application;
  final bool duplicate;
}
