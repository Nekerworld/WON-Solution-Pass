/// 가상 은행 상태. 모든 값은 시연용 가상 데이터다.
library;

import 'scenario.dart' as sc;

typedef Json = Map<String, Object?>;

Json asJson(Object? v) => v is Map ? v.cast<String, Object?>() : <String, Object?>{};
List<Object?> asList(Object? v) => v is List ? v : const [];
List<String> asStrings(Object? v) => asList(v).map((e) => '$e').toList();
int? asInt(Object? v) => v is num ? v.round() : null;

class Customer {
  Customer({required this.name, required this.age, required this.firstTimeCustomer, required this.mobileOwnerVerified});

  String name;
  int age;
  bool firstTimeCustomer;

  /// 로그인 시 확인된 정보: 다시 묻지 않는다
  bool mobileOwnerVerified;

  Json toJson() => {'name': name, 'age': age, 'firstTimeCustomer': firstTimeCustomer, 'mobileOwnerVerified': mobileOwnerVerified};

  factory Customer.fromJson(Json j) => Customer(
        name: j['name'] as String? ?? '김우리',
        age: asInt(j['age']) ?? 29,
        firstTimeCustomer: j['firstTimeCustomer'] == true,
        mobileOwnerVerified: j['mobileOwnerVerified'] == true,
      );
}

class PendingFact {
  PendingFact({required this.sessionId, required this.queriesLeft});
  String sessionId;
  int queriesLeft;

  Json toJson() => {'sessionId': sessionId, 'queriesLeft': queriesLeft};
  factory PendingFact.fromJson(Json j) => PendingFact(sessionId: j['sessionId'] as String? ?? '', queriesLeft: asInt(j['queriesLeft']) ?? 0);
}

class TaskSession {
  TaskSession({
    required this.id,
    required this.taskId,
    required this.mode,
    required this.status,
    required this.openedAt,
    this.input,
    this.finishedAt,
    this.mismatch = false,
  });

  final String id;
  final String taskId;
  final String mode;

  /// OPEN | COMPLETED | ERROR | IN_PROGRESS | PARTIAL | CANCELLED
  String status;
  final int openedAt;
  Map<String, String>? input;
  int? finishedAt;
  bool mismatch;

  Json toJson() => {
        'id': id,
        'taskId': taskId,
        'mode': mode,
        'status': status,
        'openedAt': openedAt,
        if (input != null) 'input': input,
        if (finishedAt != null) 'finishedAt': finishedAt,
        if (mismatch) 'mismatch': true,
      };

  factory TaskSession.fromJson(Json j) => TaskSession(
        id: j['id'] as String? ?? '',
        taskId: j['taskId'] as String? ?? '',
        mode: j['mode'] as String? ?? 'modal',
        status: j['status'] as String? ?? 'OPEN',
        openedAt: asInt(j['openedAt']) ?? 0,
        input: j['input'] is Map ? (j['input'] as Map).map((k, v) => MapEntry('$k', '$v')) : null,
        finishedAt: asInt(j['finishedAt']),
        mismatch: j['mismatch'] == true,
      );
}

/// 가입 조건. BROKERAGE는 market·account·fxAccount, 적금은 monthly·months·account를 쓴다.
class ApplyTerms {
  const ApplyTerms({this.market, this.account, this.fxAccount, this.monthly, this.months});

  final String? market;
  final String? account;
  final String? fxAccount;
  final int? monthly;
  final int? months;

  Json toJson() => {
        if (market != null) 'market': market,
        if (account != null) 'account': account,
        if (fxAccount != null) 'fxAccount': fxAccount,
        if (monthly != null) 'monthly': monthly,
        if (months != null) 'months': months,
      };

  static ApplyTerms? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = asJson(v);
    return ApplyTerms(
      market: j['market'] as String?,
      account: j['account'] as String?,
      fxAccount: j['fxAccount'] as String?,
      monthly: asInt(j['monthly']),
      months: asInt(j['months']),
    );
  }
}

class Application {
  Application({
    required this.id,
    required this.requestId,
    required this.productId,
    required this.terms,
    required this.channel,
    required this.status,
    required this.createdAt,
    this.failureReason,
  });

  final String id;
  final String requestId;
  final String productId;
  final ApplyTerms? terms;
  final String channel;

  /// SUCCESS | FAILED | PENDING | UNKNOWN
  String status;
  final int createdAt;
  String? failureReason;

  Json toJson() => {
        'id': id,
        'requestId': requestId,
        'productId': productId,
        'terms': terms?.toJson(),
        'channel': channel,
        'status': status,
        'createdAt': createdAt,
        'failureReason': failureReason,
      };

  static Application? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = asJson(v);
    return Application(
      id: j['id'] as String? ?? '',
      requestId: j['requestId'] as String? ?? '',
      productId: j['productId'] as String? ?? '',
      terms: ApplyTerms.fromJson(j['terms']),
      channel: j['channel'] as String? ?? 'AI',
      status: j['status'] as String? ?? 'UNKNOWN',
      createdAt: asInt(j['createdAt']) ?? 0,
      failureReason: j['failureReason'] as String?,
    );
  }
}

class ConsultTicket {
  ConsultTicket({required this.id, required this.summary, required this.status, required this.eta, required this.createdAt});

  final String id;
  final List<String> summary;
  final String status;
  final String eta;
  final int createdAt;

  Json toJson() => {'id': id, 'summary': summary, 'status': status, 'eta': eta, 'createdAt': createdAt};

  static ConsultTicket? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = asJson(v);
    return ConsultTicket(
      id: j['id'] as String? ?? '',
      summary: asStrings(j['summary']),
      status: j['status'] as String? ?? 'ACCEPTED',
      eta: j['eta'] as String? ?? '',
      createdAt: asInt(j['createdAt']) ?? 0,
    );
  }
}

class OtherAccount {
  const OtherAccount({required this.bank, required this.name, required this.masked});
  final String bank;
  final String name;
  final String masked;

  Json toJson() => {'bank': bank, 'name': name, 'masked': masked};
  factory OtherAccount.fromJson(Json j) =>
      OtherAccount(bank: j['bank'] as String? ?? '', name: j['name'] as String? ?? '', masked: j['masked'] as String? ?? '');
}

/// 재무 항목. source: BANK | STATED | ESTIMATED | UNKNOWN
class FinItem {
  FinItem({required this.value, required this.source, required this.basis});
  int? value;
  String source;
  String basis;

  Json toJson() => {'value': value, 'source': source, 'basis': basis};
  factory FinItem.fromJson(Json j) =>
      FinItem(value: asInt(j['value']), source: j['source'] as String? ?? 'UNKNOWN', basis: j['basis'] as String? ?? '');
  FinItem copy() => FinItem(value: value, source: source, basis: basis);
}

class Finance {
  Finance({required this.mydataLinked, required this.linked, required this.notLinked, required this.otherBankAccounts, required this.items});

  bool mydataLinked;
  List<String> linked;
  List<String> notLinked;
  List<OtherAccount> otherBankAccounts;
  Map<String, FinItem> items;

  Json toJson() => {
        'mydataLinked': mydataLinked,
        'linked': linked,
        'notLinked': notLinked,
        'otherBankAccounts': otherBankAccounts.map((a) => a.toJson()).toList(),
        'items': items.map((k, v) => MapEntry(k, v.toJson())),
      };

  factory Finance.fromJson(Json j) => Finance(
        mydataLinked: j['mydataLinked'] == true,
        linked: asStrings(j['linked']),
        notLinked: asStrings(j['notLinked']),
        otherBankAccounts: asList(j['otherBankAccounts']).map((a) => OtherAccount.fromJson(asJson(a))).toList(),
        items: asJson(j['items']).map((k, v) => MapEntry(k, FinItem.fromJson(asJson(v)))),
      );
}

class Simulation {
  Simulation({
    this.nextTaskOutcome = 'NORMAL',
    this.nextApplicationOutcome = 'SUCCESS',
    this.nextConsultOutcome = 'ACCEPTED',
    this.queryFailure = false,
  });

  /// NORMAL | ERROR | IN_PROGRESS | PARTIAL | MISMATCH | MISMATCH_ALWAYS
  String nextTaskOutcome;

  /// SUCCESS | FAILED | PENDING | UNKNOWN
  String nextApplicationOutcome;

  /// ACCEPTED | FAILED
  String nextConsultOutcome;
  bool queryFailure;

  Json toJson() => {
        'nextTaskOutcome': nextTaskOutcome,
        'nextApplicationOutcome': nextApplicationOutcome,
        'nextConsultOutcome': nextConsultOutcome,
        'queryFailure': queryFailure,
      };

  factory Simulation.fromJson(Json j) => Simulation(
        nextTaskOutcome: j['nextTaskOutcome'] as String? ?? 'NORMAL',
        nextApplicationOutcome: j['nextApplicationOutcome'] as String? ?? 'SUCCESS',
        nextConsultOutcome: j['nextConsultOutcome'] as String? ?? 'ACCEPTED',
        queryFailure: j['queryFailure'] == true,
      );
}

class SystemState {
  SystemState({this.bankAvailable = true, this.stateVersion = 1});
  bool bankAvailable;
  int stateVersion;

  Json toJson() => {'bankAvailable': bankAvailable, 'stateVersion': stateVersion};
  factory SystemState.fromJson(Json j) => SystemState(bankAvailable: j['bankAvailable'] != false, stateVersion: asInt(j['stateVersion']) ?? 1);
}

class BankState {
  BankState({
    required this.customer,
    required this.facts,
    required this.pending,
    required this.taskSessions,
    required this.applications,
    required this.consultations,
    required this.finance,
    required this.simulation,
    required this.system,
  });

  Customer customer;
  Map<String, bool> facts;

  /// 처리 중인 업무: fact -> { sessionId, queriesLeft }
  Map<String, PendingFact> pending;
  Map<String, TaskSession> taskSessions;
  Map<String, Application> applications;
  Map<String, ConsultTicket> consultations;
  Finance finance;
  Simulation simulation;
  SystemState system;

  factory BankState.initial() => BankState(
        customer: Customer(name: '김우리', age: 29, firstTimeCustomer: true, mobileOwnerVerified: true),
        facts: {for (final f in sc.facts.keys) f: f == 'adult'},
        pending: {},
        taskSessions: {},
        applications: {},
        consultations: {},
        finance: Finance(
          mydataLinked: true,
          linked: ['가상 A은행', '가상 B카드'],
          notLinked: ['증권사', '보험사', '부동산·현금'],
          otherBankAccounts: const [OtherAccount(bank: '가상 A은행', name: '입출금 통장', masked: '110-***-4421')],
          items: {
            'monthlyIncome': FinItem(value: 3500000, source: 'ESTIMATED', basis: '가상 A은행 급여성 입금 최근 6개월 평균'),
            'monthlyExpense': FinItem(value: 2100000, source: 'ESTIMATED', basis: '가상 A은행·B카드 출금 최근 6개월 평균'),
            'liquidAssets': FinItem(value: 8000000, source: 'BANK', basis: '가상 A은행 예금·적금 잔액'),
            'investAssets': FinItem(value: null, source: 'UNKNOWN', basis: '연결되지 않은 증권사'),
            'debt': FinItem(value: 0, source: 'BANK', basis: '연결 기관 대출 없음 (연결 안 된 기관은 미확인)'),
            'debtPayment': FinItem(value: 0, source: 'BANK', basis: '연결 기관 상환 내역 없음'),
          },
        ),
        simulation: Simulation(),
        system: SystemState(),
      );

  Json toJson() => {
        'customer': customer.toJson(),
        'facts': facts,
        'pending': pending.map((k, v) => MapEntry(k, v.toJson())),
        'taskSessions': taskSessions.map((k, v) => MapEntry(k, v.toJson())),
        'applications': applications.map((k, v) => MapEntry(k, v.toJson())),
        'consultations': consultations.map((k, v) => MapEntry(k, v.toJson())),
        'finance': finance.toJson(),
        'simulation': simulation.toJson(),
        'system': system.toJson(),
      };

  factory BankState.fromJson(Json j) => BankState(
        customer: Customer.fromJson(asJson(j['customer'])),
        facts: asJson(j['facts']).map((k, v) => MapEntry(k, v == true)),
        pending: asJson(j['pending']).map((k, v) => MapEntry(k, PendingFact.fromJson(asJson(v)))),
        taskSessions: asJson(j['taskSessions']).map((k, v) => MapEntry(k, TaskSession.fromJson(asJson(v)))),
        applications: {
          for (final e in asJson(j['applications']).entries) e.key: ?Application.fromJson(e.value),
        },
        consultations: {
          for (final e in asJson(j['consultations']).entries) e.key: ?ConsultTicket.fromJson(e.value),
        },
        finance: Finance.fromJson(asJson(j['finance'])),
        simulation: Simulation.fromJson(asJson(j['simulation'])),
        system: SystemState.fromJson(asJson(j['system'])),
      );

  BankState clone() => BankState.fromJson(toJson());
}
