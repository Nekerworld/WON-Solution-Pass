import 'bank_state.dart';

/// 가상 은행 API 실패 종류
enum ErrorKind {
  /// 조회 실패/시스템 이용 불가 (업무 판단 불가)
  queryFailure('QUERY_FAILURE'),

  /// 업무 조건 미충족으로 은행이 거절
  businessReject('BUSINESS_REJECT');

  const ErrorKind(this.code);
  final String code;

  static ErrorKind fromCode(String? code) =>
      ErrorKind.values.firstWhere((k) => k.code == code, orElse: () => ErrorKind.queryFailure);
}

class RejectReason {
  const RejectReason({required this.code, required this.message});

  final String code;
  final String message;

  Map<String, Object?> toJson() => {'code': code, 'message': message};

  factory RejectReason.fromJson(Map<String, Object?> j) =>
      RejectReason(code: j['code'] as String, message: j['message'] as String? ?? '');
}

class BankError {
  const BankError({required this.code, required this.kind, required this.message, this.reasons, this.submitted});

  final String code;
  final ErrorKind kind;
  final String message;
  final List<RejectReason>? reasons;
  final bool? submitted;

  Map<String, Object?> toJson() => {
        'code': code,
        'kind': kind.code,
        'message': message,
        if (reasons != null) 'reasons': reasons!.map((r) => r.toJson()).toList(),
        if (submitted != null) 'submitted': submitted,
      };

  factory BankError.fromJson(Map<String, Object?> j) => BankError(
        code: j['code'] as String,
        kind: ErrorKind.fromCode(j['kind'] as String?),
        message: j['message'] as String? ?? '',
        reasons: (j['reasons'] as List?)?.map((r) => RejectReason.fromJson((r as Map).cast())).toList(),
        submitted: j['submitted'] as bool?,
      );
}

/// 응답 형식: { ok:true, data } | { ok:false, error }
class BankResult<T> {
  const BankResult.success(T this.data) : error = null;
  const BankResult.failure(BankError this.error) : data = null;

  final T? data;
  final BankError? error;

  bool get ok => error == null;
}

class CustomerSnapshot {
  const CustomerSnapshot({
    required this.customerName,
    required this.accountName,
    required this.accountNumber,
    required this.balance,
    required this.kycCompleted,
    required this.digitalOtpRegistered,
    required this.transferLimit,
    required this.transferLimitChangeAllowed,
    required this.accountRestricted,
    required this.bankAvailable,
    required this.stateVersion,
    required this.policyVersion,
    required this.checkedAt,
  });

  final String customerName;
  final String accountName;
  final String accountNumber;
  final int balance;
  final bool kycCompleted;
  final bool digitalOtpRegistered;
  final int transferLimit;
  final bool transferLimitChangeAllowed;
  final bool accountRestricted;
  final bool bankAvailable;
  final int stateVersion;
  final String policyVersion;
  final int checkedAt;
}

class LimitInfo {
  const LimitInfo({required this.transferLimit, required this.changeAllowed, required this.maxWithoutOtp, required this.stateVersion});

  final int transferLimit;
  final bool changeAllowed;
  final int maxWithoutOtp;
  final int stateVersion;
}

class DraftInfo {
  const DraftInfo({required this.draft, required this.transaction, required this.balance});

  final TransferDraft draft;
  final Transaction? transaction;
  final int balance;
}

class Eligibility {
  const Eligibility({required this.eligible, required this.code, required this.message});

  final bool eligible;
  final String code;
  final String message;
}

class LimitCheck {
  const LimitCheck({required this.allowed, required this.reasons, required this.currentLimit});

  final bool allowed;
  final List<RejectReason> reasons;
  final int currentLimit;
}

class LimitChanged {
  const LimitChanged({required this.transferLimit, required this.previousLimit, required this.stateVersion});

  final int transferLimit;
  final int previousLimit;
  final int stateVersion;
}

class AmountUpdate {
  const AmountUpdate({required this.amount, required this.changed});

  final int amount;
  final bool changed;
}

class TransferValidation {
  const TransferValidation({required this.valid, required this.reasons, required this.stateVersion, required this.checkedAt});

  final bool valid;
  final List<RejectReason> reasons;
  final int stateVersion;
  final int checkedAt;
}

class SubmitResult {
  const SubmitResult({required this.transaction, required this.duplicate});

  final Transaction transaction;
  final bool duplicate;
}
