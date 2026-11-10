import '../domain/bank_state.dart';
import '../domain/bank_types.dart';

/// 화면은 저장소를 직접 읽지 않고 Mock Bank 조회 결과로 그린다.
/// 아래 클래스는 각 화면이 표시되기 전에 미리 조회한 결과다.

class HomeData {
  const HomeData({required this.customer});

  final BankResult<CustomerSnapshot> customer;
}

class TransferData {
  const TransferData({required this.draft, required this.customer});

  final BankResult<DraftInfo> draft;
  final BankResult<CustomerSnapshot> customer;
}

class OtpData {
  const OtpData({required this.status, required this.eligibility});

  final BankResult<bool> status;
  final BankResult<Eligibility> eligibility;

  BankError? get error => status.error ?? eligibility.error;
}

class LimitData {
  const LimitData({
    required this.limit,
    required this.otp,
    required this.draft,
    required this.options,
    required this.selected,
    required this.recommended,
  });

  final BankResult<LimitInfo> limit;
  final BankResult<bool> otp;
  final BankResult<DraftInfo> draft;
  final List<int> options;
  final int? selected;
  final int recommended;

  BankError? get error => limit.error ?? otp.error ?? draft.error;
}

class KycData {
  const KycData({required this.kyc, required this.customer});

  final BankResult<bool> kyc;
  final BankResult<CustomerSnapshot> customer;

  BankError? get error => kyc.error ?? customer.error;
}

class ResultData {
  const ResultData({required this.transactionId, required this.result});

  final String? transactionId;
  final BankResult<Transaction>? result;
}

class ChatData {
  const ChatData({required this.customer});

  final BankResult<CustomerSnapshot> customer;
}

/// 이체한도 화면에서 확인한 변경 가능 여부
class LimitCheckView {
  const LimitCheckView({required this.allowed, required this.reasons, required this.value});

  final bool allowed;
  final List<RejectReason> reasons;
  final int value;
}
