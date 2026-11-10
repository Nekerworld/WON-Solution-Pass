/// 시연용 가상 은행 상태. 실제 은행 시스템/계좌/고객과 무관하다.
library;

enum TransferStatus {
  idle('IDLE'),
  success('SUCCESS'),
  failed('FAILED'),
  pending('PENDING'),
  unknown('UNKNOWN');

  const TransferStatus(this.code);
  final String code;

  static TransferStatus fromCode(String? code) =>
      TransferStatus.values.firstWhere((s) => s.code == code, orElse: () => TransferStatus.idle);

  bool get isUnresolved => this == pending || this == unknown;
}

class Account {
  Account({required this.name, required this.number, required this.balance});

  String name;
  String number;
  int balance;

  Map<String, Object?> toJson() => {'name': name, 'number': number, 'balance': balance};

  factory Account.fromJson(Map<String, Object?> j) =>
      Account(name: j['name'] as String, number: j['number'] as String, balance: (j['balance'] as num).toInt());
}

class Customer {
  Customer({
    required this.name,
    required this.kycCompleted,
    required this.digitalOtpRegistered,
    required this.transferLimit,
    required this.transferLimitChangeAllowed,
    required this.accountRestricted,
  });

  String name;
  bool kycCompleted;
  bool digitalOtpRegistered;
  int transferLimit;
  bool transferLimitChangeAllowed;
  bool accountRestricted;

  Map<String, Object?> toJson() => {
        'name': name,
        'kycCompleted': kycCompleted,
        'digitalOtpRegistered': digitalOtpRegistered,
        'transferLimit': transferLimit,
        'transferLimitChangeAllowed': transferLimitChangeAllowed,
        'accountRestricted': accountRestricted,
      };

  factory Customer.fromJson(Map<String, Object?> j) => Customer(
        name: j['name'] as String,
        kycCompleted: j['kycCompleted'] as bool,
        digitalOtpRegistered: j['digitalOtpRegistered'] as bool,
        transferLimit: (j['transferLimit'] as num).toInt(),
        transferLimitChangeAllowed: j['transferLimitChangeAllowed'] as bool,
        accountRestricted: j['accountRestricted'] as bool,
      );
}

/// 진행 중인 이체 초안. 해결 절차 중에도 유지된다.
class TransferDraft {
  TransferDraft({
    required this.fromAccount,
    required this.amount,
    required this.recipient,
    required this.recipientBank,
    required this.recipientAccount,
    this.requestId,
    this.transactionId,
    this.status = TransferStatus.idle,
  });

  String fromAccount;
  int amount;
  String recipient;
  String recipientBank;
  String recipientAccount;
  String? requestId;
  String? transactionId;
  TransferStatus status;

  TransferDraft copyWith({String? requestId}) => TransferDraft(
        fromAccount: fromAccount,
        amount: amount,
        recipient: recipient,
        recipientBank: recipientBank,
        recipientAccount: recipientAccount,
        requestId: requestId ?? this.requestId,
        transactionId: transactionId,
        status: status,
      );

  /// requestId를 비운 사본 (요청 식별값 없는 거래 테스트용)
  TransferDraft withoutRequestId() => copyWith()..requestId = null;

  Map<String, Object?> toJson() => {
        'fromAccount': fromAccount,
        'amount': amount,
        'recipient': recipient,
        'recipientBank': recipientBank,
        'recipientAccount': recipientAccount,
        'requestId': requestId,
        'transactionId': transactionId,
        'status': status.code,
      };

  factory TransferDraft.fromJson(Map<String, Object?> j) => TransferDraft(
        fromAccount: j['fromAccount'] as String,
        amount: (j['amount'] as num).toInt(),
        recipient: j['recipient'] as String,
        recipientBank: j['recipientBank'] as String,
        recipientAccount: j['recipientAccount'] as String,
        requestId: j['requestId'] as String?,
        transactionId: j['transactionId'] as String?,
        status: TransferStatus.fromCode(j['status'] as String?),
      );
}

class Transaction {
  Transaction({
    required this.id,
    required this.requestId,
    required this.amount,
    required this.recipient,
    required this.recipientBank,
    required this.fromAccount,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.failureReason,
  });

  final String id;
  final String requestId;
  final int amount;
  final String recipient;
  final String recipientBank;
  final String fromAccount;
  TransferStatus status;
  final int createdAt;
  int updatedAt;
  String? failureReason;

  Map<String, Object?> toJson() => {
        'id': id,
        'requestId': requestId,
        'amount': amount,
        'recipient': recipient,
        'recipientBank': recipientBank,
        'fromAccount': fromAccount,
        'status': status.code,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'failureReason': failureReason,
      };

  factory Transaction.fromJson(Map<String, Object?> j) => Transaction(
        id: j['id'] as String,
        requestId: j['requestId'] as String,
        amount: (j['amount'] as num).toInt(),
        recipient: j['recipient'] as String,
        recipientBank: j['recipientBank'] as String,
        fromAccount: j['fromAccount'] as String,
        status: TransferStatus.fromCode(j['status'] as String?),
        createdAt: (j['createdAt'] as num).toInt(),
        updatedAt: (j['updatedAt'] as num).toInt(),
        failureReason: j['failureReason'] as String?,
      );
}

class Simulation {
  Simulation({this.nextTransferOutcome = TransferStatus.success, this.queryFailure = false});

  /// 다음 이체 요청에 대해 가상 은행이 반환할 결과 (시연 제어 화면에서만 변경)
  TransferStatus nextTransferOutcome;

  /// 상태 조회 실패 주입
  bool queryFailure;

  Map<String, Object?> toJson() => {'nextTransferOutcome': nextTransferOutcome.code, 'queryFailure': queryFailure};

  factory Simulation.fromJson(Map<String, Object?> j) => Simulation(
        nextTransferOutcome: TransferStatus.fromCode(j['nextTransferOutcome'] as String?),
        queryFailure: j['queryFailure'] as bool? ?? false,
      );
}

class SystemState {
  SystemState({this.bankAvailable = true, this.stateVersion = 1});

  bool bankAvailable;
  int stateVersion;

  Map<String, Object?> toJson() => {'bankAvailable': bankAvailable, 'stateVersion': stateVersion};

  factory SystemState.fromJson(Map<String, Object?> j) => SystemState(
        bankAvailable: j['bankAvailable'] as bool? ?? true,
        stateVersion: (j['stateVersion'] as num).toInt(),
      );
}

class BankState {
  BankState({
    required this.account,
    required this.customer,
    required this.transfer,
    required this.transactions,
    required this.simulation,
    required this.system,
  });

  Account account;
  Customer customer;
  TransferDraft transfer;

  /// 삽입 순서를 유지한다 (거래 번호 순).
  Map<String, Transaction> transactions;
  Simulation simulation;
  SystemState system;

  factory BankState.initial() => BankState(
        account: Account(name: '우리 주거래 통장', number: '1002-***-123456', balance: 5000000),
        customer: Customer(
          name: '김우리',
          kycCompleted: true,
          digitalOtpRegistered: false,
          transferLimit: 1000000,
          transferLimitChangeAllowed: true,
          accountRestricted: false,
        ),
        transfer: TransferDraft(
          fromAccount: '1002-***-123456',
          amount: 1500000,
          recipient: '홍길동',
          recipientBank: '우리은행',
          recipientAccount: '1002-***-987654',
        ),
        transactions: {},
        simulation: Simulation(),
        system: SystemState(),
      );

  Map<String, Object?> toJson() => {
        'account': account.toJson(),
        'customer': customer.toJson(),
        'transfer': transfer.toJson(),
        'transactions': {for (final e in transactions.entries) e.key: e.value.toJson()},
        'simulation': simulation.toJson(),
        'system': system.toJson(),
      };

  factory BankState.fromJson(Map<String, Object?> j) {
    final txs = (j['transactions'] as Map?)?.cast<String, Object?>() ?? {};
    return BankState(
      account: Account.fromJson((j['account'] as Map).cast()),
      customer: Customer.fromJson((j['customer'] as Map).cast()),
      transfer: TransferDraft.fromJson((j['transfer'] as Map).cast()),
      transactions: {for (final e in txs.entries) e.key: Transaction.fromJson((e.value as Map).cast())},
      simulation: Simulation.fromJson((j['simulation'] as Map).cast()),
      system: SystemState.fromJson((j['system'] as Map).cast()),
    );
  }

  BankState clone() => BankState.fromJson(toJson());
}
