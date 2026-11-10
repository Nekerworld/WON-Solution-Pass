/// 실제 서버/금융 API 없이 앱 안에서 동작하는 가상 은행 API.
/// - 모든 함수는 Future를 반환한다 (지연 시간 포함).
/// - 응답 형식: BankResult.success(data) | BankResult.failure(BankError)
///   kind: QUERY_FAILURE   조회 실패/시스템 이용 불가 (업무 판단 불가)
///         BUSINESS_REJECT 업무 조건 미충족으로 은행이 거절
/// - 거래 성공 여부는 오직 이 모듈이 결정한다.
library;

import 'dart:math';

import '../domain/bank_state.dart';
import '../domain/bank_types.dart';
import '../domain/formatters.dart';
import '../domain/policy.dart';
import 'bank_store.dart';

/// 허용 플로우 ID → 내부 화면 ID. 외부 URL은 생성하지 않는다.
const Map<String, String> allowedFlows = {
  'otp-registration': 'otp',
  'limit-management': 'limit',
  'kyc-flow': 'kyc',
  'transfer': 'transfer',
  'solution-plan': 'plan',
  'support': 'support',
  'transfer-result': 'result',
  'chat': 'chat',
  'home': 'home',
};

enum _Latency {
  query(220),
  mutate(520),
  transfer(760);

  const _Latency(this.ms);
  final int ms;
}

class MockBank {
  MockBank({required this.store, Random? random, double latencyScale = 1})
      : _random = random ?? Random(),
        _latencyScale = max(0, latencyScale);

  final BankStore store;
  final Random _random;
  double _latencyScale;
  int _requestSeq = 0;

  double get latencyScale => _latencyScale;
  set latencyScale(double v) => _latencyScale = max(0, v);

  Future<void> _wait(_Latency kind) {
    final ms = (kind.ms * _latencyScale * (0.85 + _random.nextDouble() * 0.3)).round();
    return ms > 0 ? Future.delayed(Duration(milliseconds: ms)) : Future.value();
  }

  static BankResult<T> _ok<T>(T data) => BankResult.success(data);

  static BankResult<T> _err<T>(String code, ErrorKind kind, String message, {List<RejectReason>? reasons, bool? submitted}) =>
      BankResult.failure(BankError(code: code, kind: kind, message: message, reasons: reasons, submitted: submitted));

  BankError? _systemGuard(BankState s, {required bool isQuery}) {
    if (!s.system.bankAvailable) {
      return const BankError(code: 'BANK_UNAVAILABLE', kind: ErrorKind.queryFailure, message: '은행 시스템에 일시적으로 연결할 수 없습니다.');
    }
    if (isQuery && s.simulation.queryFailure) {
      return const BankError(code: 'QUERY_TIMEOUT', kind: ErrorKind.queryFailure, message: '상태 조회 응답을 받지 못했습니다.');
    }
    return null;
  }

  /// 은행 자체의 이체 사전 검사 (가상 정책 기반)
  List<RejectReason> _transferRejectReasons(BankState s, TransferDraft t) {
    final reasons = <RejectReason>[];
    if (s.customer.accountRestricted) {
      reasons.add(const RejectReason(code: 'ACCOUNT_RESTRICTED', message: '계좌 이용 제한 상태입니다.'));
    }
    if (!s.customer.kycCompleted) {
      reasons.add(const RejectReason(code: 'KYC_REQUIRED', message: '고객확인이 완료되지 않았습니다.'));
    }
    if (t.amount > DemoPolicy.otpRequiredAbove && !s.customer.digitalOtpRegistered) {
      reasons.add(RejectReason(
        code: 'OTP_REQUIRED',
        message: '${formatWon(DemoPolicy.otpRequiredAbove)} 초과 이체는 디지털 OTP 등록이 필요합니다. (가상 정책)',
      ));
    }
    if (t.amount > s.customer.transferLimit) {
      reasons.add(RejectReason(
        code: 'LIMIT_EXCEEDED',
        message: '이체 금액이 1일 이체한도(${formatWon(s.customer.transferLimit)})를 초과합니다.',
      ));
    }
    if (t.amount > s.account.balance) {
      reasons.add(const RejectReason(code: 'INSUFFICIENT_BALANCE', message: '출금 가능 잔액이 부족합니다.'));
    }
    return reasons;
  }

  List<RejectReason> _limitChangeRejectReasons(BankState s, int newLimit) {
    final reasons = <RejectReason>[];
    if (s.customer.accountRestricted) {
      reasons.add(const RejectReason(code: 'ACCOUNT_RESTRICTED', message: '계좌 이용 제한 상태에서는 한도를 변경할 수 없습니다.'));
    }
    if (!s.customer.transferLimitChangeAllowed) {
      reasons.add(const RejectReason(code: 'LIMIT_CHANGE_NOT_ALLOWED', message: '현재 이 계좌는 비대면 한도 변경 대상이 아닙니다. (가상)'));
    }
    if (newLimit < DemoPolicy.minTransferLimit || newLimit > DemoPolicy.maxTransferLimit) {
      reasons.add(RejectReason(
        code: 'INVALID_LIMIT',
        message: '변경 가능한 한도 범위는 ${formatWon(DemoPolicy.minTransferLimit)} ~ ${formatWon(DemoPolicy.maxTransferLimit)}입니다.',
      ));
    }
    if (newLimit > DemoPolicy.maxLimitWithoutOtp && !s.customer.digitalOtpRegistered) {
      reasons.add(RejectReason(
        code: 'OTP_REQUIRED_FOR_LIMIT',
        message: '${formatWon(DemoPolicy.maxLimitWithoutOtp)}을 초과하는 한도는 디지털 OTP 등록 후 변경할 수 있습니다. (가상 정책)',
      ));
    }
    return reasons;
  }

  Transaction? _findTransactionByRequest(BankState s, String requestId) {
    for (final t in s.transactions.values) {
      if (t.requestId == requestId) return t;
    }
    return null;
  }

  /* ---------------- 조회 ---------------- */

  Future<BankResult<CustomerSnapshot>> getCustomerState() async {
    await _wait(_Latency.query);
    final s = store.state;
    final g = _systemGuard(s, isQuery: true);
    if (g != null) return BankResult.failure(g);
    return _ok(CustomerSnapshot(
      customerName: s.customer.name,
      accountName: s.account.name,
      accountNumber: s.account.number,
      balance: s.account.balance,
      kycCompleted: s.customer.kycCompleted,
      digitalOtpRegistered: s.customer.digitalOtpRegistered,
      transferLimit: s.customer.transferLimit,
      transferLimitChangeAllowed: s.customer.transferLimitChangeAllowed,
      accountRestricted: s.customer.accountRestricted,
      bankAvailable: s.system.bankAvailable,
      stateVersion: s.system.stateVersion,
      policyVersion: DemoPolicy.version,
      checkedAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  Future<BankResult<LimitInfo>> getTransferLimit() async {
    await _wait(_Latency.query);
    final s = store.state;
    final g = _systemGuard(s, isQuery: true);
    if (g != null) return BankResult.failure(g);
    return _ok(LimitInfo(
      transferLimit: s.customer.transferLimit,
      changeAllowed: s.customer.transferLimitChangeAllowed,
      maxWithoutOtp: DemoPolicy.maxLimitWithoutOtp,
      stateVersion: s.system.stateVersion,
    ));
  }

  /// 디지털 OTP 등록 여부
  Future<BankResult<bool>> getOtpStatus() async {
    await _wait(_Latency.query);
    final s = store.state;
    final g = _systemGuard(s, isQuery: true);
    if (g != null) return BankResult.failure(g);
    return _ok(s.customer.digitalOtpRegistered);
  }

  /// 고객확인 완료 여부
  Future<BankResult<bool>> getKycStatus() async {
    await _wait(_Latency.query);
    final s = store.state;
    final g = _systemGuard(s, isQuery: true);
    if (g != null) return BankResult.failure(g);
    return _ok(s.customer.kycCompleted);
  }

  /// 현재 진행 중인 이체 초안(받는 분·금액 등). 해결 절차 중에도 유지된다.
  Future<BankResult<DraftInfo>> getTransferDraft() async {
    await _wait(_Latency.query);
    final s = store.state;
    final g = _systemGuard(s, isQuery: true);
    if (g != null) return BankResult.failure(g);
    final txId = s.transfer.transactionId;
    final tx = txId != null ? s.transactions[txId] : null;
    return _ok(DraftInfo(draft: s.transfer, transaction: tx, balance: s.account.balance));
  }

  Future<BankResult<List<Transaction>>> getTransactions() async {
    await _wait(_Latency.query);
    final s = store.state;
    final g = _systemGuard(s, isQuery: true);
    if (g != null) return BankResult.failure(g);
    final list = s.transactions.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return _ok(list);
  }

  Future<BankResult<Eligibility>> checkOtpEligibility() async {
    await _wait(_Latency.query);
    final s = store.state;
    final g = _systemGuard(s, isQuery: true);
    if (g != null) return BankResult.failure(g);
    if (s.customer.digitalOtpRegistered) {
      return _ok(const Eligibility(eligible: false, code: 'ALREADY_REGISTERED', message: '이미 디지털 OTP가 등록되어 있습니다.'));
    }
    if (s.customer.accountRestricted) {
      return _ok(const Eligibility(eligible: false, code: 'ACCOUNT_RESTRICTED', message: '계좌 이용 제한 상태에서는 등록할 수 없습니다.'));
    }
    if (DemoPolicy.otpRegistrationRequiresKyc && !s.customer.kycCompleted) {
      return _ok(const Eligibility(eligible: false, code: 'KYC_REQUIRED', message: '고객확인을 먼저 완료해야 합니다. (가상 정책)'));
    }
    return _ok(const Eligibility(eligible: true, code: 'ELIGIBLE', message: '이 기기에서 디지털 OTP를 등록할 수 있습니다.'));
  }

  Future<BankResult<LimitCheck>> checkLimitChange(int newLimit) async {
    await _wait(_Latency.query);
    final s = store.state;
    final g = _systemGuard(s, isQuery: true);
    if (g != null) return BankResult.failure(g);
    final reasons = _limitChangeRejectReasons(s, newLimit);
    return _ok(LimitCheck(allowed: reasons.isEmpty, reasons: reasons, currentLimit: s.customer.transferLimit));
  }

  /* ---------------- 변경 ---------------- */

  /// 성공 시 반영된 stateVersion
  Future<BankResult<int>> registerDigitalOtp() async {
    await _wait(_Latency.mutate);
    final s = store.state;
    final g = _systemGuard(s, isQuery: false);
    if (g != null) return BankResult.failure(g);
    if (s.customer.digitalOtpRegistered) {
      return _err('ALREADY_REGISTERED', ErrorKind.businessReject, '이미 디지털 OTP가 등록되어 있습니다.');
    }
    if (s.customer.accountRestricted) {
      return _err('ACCOUNT_RESTRICTED', ErrorKind.businessReject, '계좌 이용 제한 상태에서는 등록할 수 없습니다.');
    }
    if (DemoPolicy.otpRegistrationRequiresKyc && !s.customer.kycCompleted) {
      return _err('KYC_REQUIRED', ErrorKind.businessReject, '고객확인을 먼저 완료해야 합니다. (가상 정책)');
    }
    final next = store.update((d) => d.customer.digitalOtpRegistered = true, '디지털 OTP 등록 완료');
    return _ok(next.system.stateVersion);
  }

  Future<BankResult<LimitChanged>> changeTransferLimit(int newLimit) async {
    await _wait(_Latency.mutate);
    final s = store.state;
    final g = _systemGuard(s, isQuery: false);
    if (g != null) return BankResult.failure(g);
    final reasons = _limitChangeRejectReasons(s, newLimit);
    if (reasons.isNotEmpty) {
      return _err(reasons.first.code, ErrorKind.businessReject, reasons.first.message, reasons: reasons);
    }
    final before = s.customer.transferLimit;
    final next = store.update(
      (d) => d.customer.transferLimit = newLimit,
      '1일 이체한도 변경 ${formatWon(before)} → ${formatWon(newLimit)}',
    );
    return _ok(LimitChanged(transferLimit: newLimit, previousLimit: before, stateVersion: next.system.stateVersion));
  }

  /// 성공 시 반영된 stateVersion
  Future<BankResult<int>> completeKyc() async {
    await _wait(_Latency.mutate);
    final s = store.state;
    final g = _systemGuard(s, isQuery: false);
    if (g != null) return BankResult.failure(g);
    if (s.customer.kycCompleted) {
      return _err('ALREADY_COMPLETED', ErrorKind.businessReject, '고객확인이 이미 완료되어 있습니다.');
    }
    if (s.customer.accountRestricted) {
      return _err('ACCOUNT_RESTRICTED', ErrorKind.businessReject, '계좌 이용 제한 상태에서는 진행할 수 없습니다.');
    }
    final next = store.update((d) => d.customer.kycCompleted = true, '고객확인 완료');
    return _ok(next.system.stateVersion);
  }

  /// 이체 금액 변경 (진행 중이거나 결과 불명인 거래가 있으면 거절)
  Future<BankResult<AmountUpdate>> updateTransferAmount(int amount) async {
    await _wait(_Latency.query);
    final s = store.state;
    final g = _systemGuard(s, isQuery: false);
    if (g != null) return BankResult.failure(g);
    final status = s.transfer.status;
    if (status == TransferStatus.pending || status == TransferStatus.unknown || status == TransferStatus.success) {
      return _err('TRANSFER_LOCKED', ErrorKind.businessReject, '처리 중이거나 완료된 이체는 금액을 바꿀 수 없습니다.');
    }
    if (amount <= 0) {
      return _err('INVALID_AMOUNT', ErrorKind.businessReject, '이체 금액을 확인해 주세요.');
    }
    if (amount == s.transfer.amount) return _ok(AmountUpdate(amount: amount, changed: false));
    store.update((d) {
      d.transfer.amount = amount;
      d.transfer.requestId = null;
      d.transfer.transactionId = null;
      d.transfer.status = TransferStatus.idle;
    }, '이체 금액 변경 → ${formatWon(amount)}');
    return _ok(AmountUpdate(amount: amount, changed: true));
  }

  /* ---------------- 이체 ---------------- */

  /// 이체 사전 검사. 실패 사유를 한 번에 모두 반환한다. 거래는 발생하지 않는다.
  Future<BankResult<TransferValidation>> validateTransfer([TransferDraft? transfer]) async {
    await _wait(_Latency.query);
    final s = store.state;
    final g = _systemGuard(s, isQuery: true);
    if (g != null) return BankResult.failure(g);
    final reasons = _transferRejectReasons(s, transfer ?? s.transfer);
    return _ok(TransferValidation(
      valid: reasons.isEmpty,
      reasons: reasons,
      stateVersion: s.system.stateVersion,
      checkedAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  String newRequestId() {
    _requestSeq += 1;
    return 'REQ-${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase()}-$_requestSeq';
  }

  /// 이체 실행 요청. 사용자가 승인했을 때만 호출되어야 한다.
  /// - 같은 requestId 재요청은 새 거래를 만들지 않고 기존 거래를 반환한다(중복 실행 방지).
  /// - 결과(SUCCESS/FAILED/PENDING/UNKNOWN)는 가상 은행이 결정한다.
  Future<BankResult<SubmitResult>> submitTransfer(TransferDraft transfer) async {
    await _wait(_Latency.transfer);
    final s = store.state;
    final g = _systemGuard(s, isQuery: false);
    if (g != null) {
      return _err(g.code, g.kind, '${g.message} 이체 요청은 전송되지 않았습니다.', submitted: false);
    }
    final requestId = transfer.requestId;
    if (requestId == null || requestId.isEmpty) {
      return _err('REQUEST_ID_REQUIRED', ErrorKind.businessReject, '거래 요청 식별값이 없습니다.', submitted: false);
    }

    final existing = _findTransactionByRequest(s, requestId);
    if (existing != null) {
      store.events.add('BANK', '중복 요청 차단: $requestId → 기존 거래 ${existing.id} 반환');
      return _ok(SubmitResult(transaction: existing, duplicate: true));
    }

    final draft = s.transfer;
    if (transfer.amount != draft.amount ||
        transfer.recipient != draft.recipient ||
        transfer.recipientBank != draft.recipientBank ||
        transfer.fromAccount != draft.fromAccount) {
      return _err('DRAFT_MISMATCH', ErrorKind.businessReject, '확인한 이체 정보와 요청 정보가 다릅니다.', submitted: false);
    }

    final reasons = _transferRejectReasons(s, transfer);
    if (reasons.isNotEmpty) {
      return _err('TRANSFER_REJECTED', ErrorKind.businessReject, '이체 조건을 충족하지 않아 거래가 실행되지 않았습니다.',
          reasons: reasons, submitted: false);
    }

    final outcome = s.simulation.nextTransferOutcome == TransferStatus.idle ? TransferStatus.success : s.simulation.nextTransferOutcome;
    final id = 'DEMO-${1023 + s.transactions.length}';
    final now = DateTime.now().millisecondsSinceEpoch;
    final tx = Transaction(
      id: id,
      requestId: requestId,
      amount: transfer.amount,
      recipient: transfer.recipient,
      recipientBank: transfer.recipientBank,
      fromAccount: transfer.fromAccount,
      status: outcome,
      createdAt: now,
      updatedAt: now,
      failureReason: outcome == TransferStatus.failed ? '수취 은행 처리 거절 (가상 응답)' : null,
    );
    store.update((d) {
      d.transactions[id] = Transaction.fromJson(tx.toJson());
      d.transfer.requestId = requestId;
      d.transfer.transactionId = id;
      d.transfer.status = outcome;
      if (outcome == TransferStatus.success) d.account.balance -= transfer.amount;
    }, '이체 요청 $id 처리 결과: ${outcome.code}');
    return _ok(SubmitResult(transaction: tx, duplicate: false));
  }

  /// 거래 결과 조회 전용. 어떤 경우에도 재전송하지 않는다.
  Future<BankResult<Transaction>> getTransferResult(String transactionId) async {
    await _wait(_Latency.query);
    final s = store.state;
    final g = _systemGuard(s, isQuery: true);
    if (g != null) return BankResult.failure(g);
    final tx = s.transactions[transactionId];
    if (tx == null) return _err('TX_NOT_FOUND', ErrorKind.businessReject, '해당 거래를 찾을 수 없습니다.');
    return _ok(tx);
  }

  /* ---------------- 화면 연결 ---------------- */

  /// 은행이 승인한 내부 화면 ID만 반환한다. 외부 URL은 생성하지 않는다.
  String? resolveFlow(String flowId) => allowedFlows[flowId];

  /* ---------------- 시연 전용 ---------------- */

  /// 시연 제어 화면 전용: 보류/불명 거래를 은행 측에서 확정 처리한 것으로 시뮬레이션
  bool demoResolveTransaction(String transactionId, TransferStatus status) {
    final s = store.state;
    final tx = s.transactions[transactionId];
    if (tx == null || (status != TransferStatus.success && status != TransferStatus.failed)) return false;
    if (tx.status == TransferStatus.success || tx.status == TransferStatus.failed) return false;
    store.update((d) {
      final t = d.transactions[transactionId]!;
      t.status = status;
      t.updatedAt = DateTime.now().millisecondsSinceEpoch;
      if (status == TransferStatus.failed) t.failureReason = '은행 처리 결과 실패 (가상 응답)';
      if (status == TransferStatus.success) d.account.balance -= t.amount;
      if (d.transfer.transactionId == transactionId) d.transfer.status = status;
    }, '[시연] 거래 $transactionId 은행 측 확정: ${status.code}');
    return true;
  }
}
