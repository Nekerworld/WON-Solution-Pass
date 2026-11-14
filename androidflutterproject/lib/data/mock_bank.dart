/// 앱 안에서 동작하는 가상 은행 API.
/// - 응답: BankResult.success(data) | BankResult.failure(error)
/// - 업무 처리·가입 성공 여부는 오직 이 모듈이 결정한다.
/// - 업무 화면의 결과(getTaskResult)는 참고용이며, 완료 판정은 조건 재조회로 한다.
library;

import 'dart:math';

import '../domain/bank_state.dart';
import '../domain/bank_types.dart';
import '../domain/event_log.dart';
import '../domain/formatters.dart';
import '../domain/scenario.dart';
import 'bank_store.dart';

const Map<String, int> _latency = {'query': 220, 'mutate': 600, 'apply': 800};

class MockBank {
  MockBank({required this.store, required this.events, double latencyScale = 1, Random? random})
      : _latencyScale = max(0, latencyScale),
        _random = random ?? Random();

  final BankStore store;
  final EventLog events;
  final Random _random;
  double _latencyScale;

  double get latencyScale => _latencyScale;
  set latencyScale(double v) => _latencyScale = max(0, v);

  Future<void> _wait(String kind) {
    final base = _latency[kind] ?? 200;
    final ms = (base * _latencyScale * (0.85 + _random.nextDouble() * 0.3)).round();
    return ms > 0 ? Future.delayed(Duration(milliseconds: ms)) : Future.value();
  }

  BankResult<T> _err<T>(String code, String kind, String message, {bool? submitted, List<String>? unmet, List<String>? reasons}) =>
      BankResult.failure(BankError(code: code, kind: kind, message: message, submitted: submitted, unmet: unmet, reasons: reasons));

  BankError? _guard(BankState s, bool isQuery) {
    if (!s.system.bankAvailable) return const BankError(code: 'BANK_UNAVAILABLE', kind: 'QUERY_FAILURE', message: '은행 시스템에 일시적으로 연결할 수 없어요.');
    if (isQuery && s.simulation.queryFailure) return const BankError(code: 'QUERY_TIMEOUT', kind: 'QUERY_FAILURE', message: '상태 조회 응답을 받지 못했어요.');
    return null;
  }

  List<String> _preReasons(BankState s, TaskDef task) => [
        for (final e in task.pre.entries)
          if ((s.facts[e.key] ?? false) != e.value) '${josa(factLabel(e.key), '이')} 먼저 필요해요.',
      ];

  void _applyEffects(BankState d, TaskDef task) {
    for (final e in task.effects.entries) {
      d.facts[e.key] = e.value;
      d.pending.remove(e.key);
    }
  }

  /* ---------------- 조회 ---------------- */

  Future<BankResult<Customer>> getProfile() async {
    await _wait('query');
    final s = store.state;
    final g = _guard(s, true);
    if (g != null) return BankResult.failure(g);
    return BankResult.success(s.customer);
  }

  /// 홈 화면용: 우리은행 계좌 보유 여부
  Future<BankResult<AccountSummary>> getAccountSummary() async {
    await _wait('query');
    final s = store.state;
    final g = _guard(s, true);
    if (g != null) return BankResult.failure(g);
    return BankResult.success(AccountSummary(
      customerName: s.customer.name,
      hasDepositAccount: s.facts['hasDepositAccount'] == true,
      account: s.facts['hasDepositAccount'] == true ? const AccountRef('WON 통장', '1002-***-731024') : null,
      fxAccount: s.facts['hasFxAccount'] == true ? const AccountRef('WON 외화통장(USD)', '1002-***-552190') : null,
      savings: [
        for (final a in s.applications.values)
          if (a.status == 'SUCCESS') SavingRef(productId: a.productId, id: a.id, terms: a.terms),
      ],
      stateVersion: s.system.stateVersion,
    ));
  }

  /// 상품 조건 확인용 은행 사실 조회
  Future<BankResult<ConditionsData>> checkConditions(String productId) async {
    await _wait('query');
    final s = store.state;
    final g = _guard(s, true);
    if (g != null) return BankResult.failure(g);
    final product = getProduct(productId);
    if (product == null) return _err('PRODUCT_NOT_FOUND', 'BUSINESS_REJECT', '상품을 찾을 수 없어요.');
    return BankResult.success(ConditionsData(
      productId: productId,
      conditions: [
        for (final id in product.conditions)
          ConditionFact(
            id: id,
            fact: conditions[id]!.fact,
            label: conditions[id]!.label,
            value: s.facts[conditions[id]!.fact] == true,
            inProgress: s.pending.containsKey(conditions[id]!.fact),
          ),
      ],
      facts: Map.of(s.facts),
      stateVersion: s.system.stateVersion,
    ));
  }

  /// 정보 이용 동의 후: 연결된 마이데이터 기관의 다른 은행 계좌 보유 여부
  Future<BankResult<LinkedAccounts>> getLinkedAccounts() async {
    await _wait('query');
    final s = store.state;
    final g = _guard(s, true);
    if (g != null) return BankResult.failure(g);
    return BankResult.success(LinkedAccounts(
      mydataLinked: s.finance.mydataLinked,
      linked: List.of(s.finance.linked),
      otherBankAccounts: List.of(s.finance.otherBankAccounts),
      mobileOwnerVerified: s.customer.mobileOwnerVerified,
    ));
  }

  /// 자산관리용 재무 조회: 조회 범위와 미확인 항목을 함께 돌려준다
  Future<BankResult<FinancialSnapshot>> getFinancialSnapshot() async {
    await _wait('query');
    final s = store.state;
    final g = _guard(s, true);
    if (g != null) return BankResult.failure(g);
    return BankResult.success(FinancialSnapshot(
      linked: s.finance.mydataLinked ? List.of(s.finance.linked) : const [],
      notLinked: List.of(s.finance.notLinked),
      items: s.finance.items.map((k, v) => MapEntry(k, v.copy())),
      stateVersion: s.system.stateVersion,
    ));
  }

  List<ProductDef> listProducts() => List.of(products);

  Future<BankResult<TaskEligibility>> checkTaskEligibility(String taskId) async {
    await _wait('query');
    final s = store.state;
    final g = _guard(s, true);
    if (g != null) return BankResult.failure(g);
    final task = getTask(taskId);
    if (task == null) return _err('TASK_NOT_FOUND', 'BUSINESS_REJECT', '허용되지 않은 업무예요.');
    final done = task.effects.entries.every((e) => (s.facts[e.key] ?? false) == e.value);
    final reasons = _preReasons(s, task);
    return BankResult.success(TaskEligibility(taskId: taskId, alreadyDone: done, eligible: !done && reasons.isEmpty, reasons: reasons));
  }

  /* ---------------- 업무 (모달/메뉴) ---------------- */

  /// 은행이 허용한 업무 화면만 연다. 외부 URL은 만들지 않는다.
  BankResult<String> openTask(String taskId, {String mode = 'modal'}) {
    final task = getTask(taskId);
    if (task == null) return _err('TASK_NOT_FOUND', 'BUSINESS_REJECT', '허용되지 않은 업무예요.');
    final id = newId('TS');
    store.update((d) {
      d.taskSessions[id] = TaskSession(id: id, taskId: taskId, mode: mode, status: 'OPEN', openedAt: DateTime.now().millisecondsSinceEpoch);
    }, '업무 화면 열기 ${task.label} ($id)');
    return BankResult.success(id);
  }

  Future<BankResult<TaskRunResult>> runTask(String sessionId, [Map<String, String>? input]) async {
    await _wait('mutate');
    final s = store.state;
    final g = _guard(s, false);
    if (g != null) return BankResult.failure(g);
    final ts = s.taskSessions[sessionId];
    if (ts == null) return _err('SESSION_NOT_FOUND', 'BUSINESS_REJECT', '업무 세션을 찾을 수 없어요.');
    if (ts.status != 'OPEN') return BankResult.success(TaskRunResult(sessionId: sessionId, status: ts.status, duplicate: true));
    final task = getTask(ts.taskId)!;
    final reasons = _preReasons(s, task);
    if (reasons.isNotEmpty) return _err('PRECONDITION_UNMET', 'BUSINESS_REJECT', reasons.first, reasons: reasons);

    final outcome = s.simulation.nextTaskOutcome;
    var status = 'COMPLETED';
    var message = '${josa(task.label, '을')} 마쳤어요.';
    final next = store.update((d) {
      final t = d.taskSessions[sessionId]!;
      t.input = input;
      t.finishedAt = DateTime.now().millisecondsSinceEpoch;
      switch (outcome) {
        case 'NORMAL':
          _applyEffects(d, task);
        case 'ERROR':
          status = 'ERROR';
          message = '처리 중 오류가 발생했어요. 변경된 내용은 없어요.';
        case 'IN_PROGRESS':
          status = 'IN_PROGRESS';
          message = '은행에서 처리하고 있어요. 완료되면 상태에 반영돼요.';
          for (final f in task.effects.keys) {
            d.pending[f] = PendingFact(sessionId: sessionId, queriesLeft: 1);
          }
        case 'PARTIAL':
          status = 'PARTIAL';
          message = '일부 단계만 저장됐어요. 남은 단계를 마쳐야 완료돼요.';
        case 'MISMATCH' || 'MISMATCH_ALWAYS':
          // 업무 화면은 완료로 표시하지만 은행 기록에는 반영되지 않은 상황
          t.mismatch = true;
      }
      t.status = status;
      if (outcome != 'MISMATCH_ALWAYS') d.simulation.nextTaskOutcome = 'NORMAL';
    }, '업무 처리 ${task.label} → $status${outcome != 'NORMAL' ? ' [시뮬레이션 $outcome]' : ''}');
    return BankResult.success(TaskRunResult(sessionId: sessionId, status: status, message: message, stateVersion: next.system.stateVersion));
  }

  BankResult<String> cancelTask(String sessionId) {
    final ts = store.state.taskSessions[sessionId];
    if (ts == null || ts.status != 'OPEN') return BankResult.success(ts?.status ?? 'NONE');
    store.update((d) => d.taskSessions[sessionId]!.status = 'CANCELLED', '업무 화면 닫기(취소) $sessionId');
    return const BankResult.success('CANCELLED');
  }

  /// 업무 처리 결과 조회. 처리 중이던 업무는 조회 시점에 은행 처리가 끝날 수 있다.
  Future<BankResult<TaskResult>> getTaskResult(String sessionId) async {
    await _wait('query');
    final s = store.state;
    final g = _guard(s, true);
    if (g != null) return BankResult.failure(g);
    final ts = s.taskSessions[sessionId];
    if (ts == null) return _err('SESSION_NOT_FOUND', 'BUSINESS_REJECT', '업무 세션을 찾을 수 없어요.');
    if (ts.status == 'IN_PROGRESS') {
      final task = getTask(ts.taskId)!;
      final f0 = task.effects.keys.first;
      final p = s.pending[f0];
      if (p != null && p.sessionId == sessionId) {
        if (p.queriesLeft > 0) {
          store.update((d) => d.pending[f0]!.queriesLeft -= 1, '처리 중 업무 조회 $sessionId');
          return BankResult.success(TaskResult(sessionId: sessionId, taskId: ts.taskId, status: 'IN_PROGRESS'));
        }
        store.update((d) {
          _applyEffects(d, task);
          d.taskSessions[sessionId]!.status = 'COMPLETED';
        }, '처리 중이던 업무 완료 확인 ${task.label}');
        return BankResult.success(TaskResult(sessionId: sessionId, taskId: ts.taskId, status: 'COMPLETED'));
      }
    }
    return BankResult.success(TaskResult(sessionId: sessionId, taskId: ts.taskId, status: ts.status, reflected: !ts.mismatch));
  }

  /* ---------------- 가입 ---------------- */

  String newRequestId() => newId('REQ');

  /// 가입 요청. 고객이 승인했을 때만 호출되어야 한다.
  /// - 같은 requestId 재요청은 새 가입을 만들지 않는다.
  /// - 은행이 조건을 다시 검사한다.
  Future<BankResult<SubmitResult>> submitApplication({required String requestId, required String productId, ApplyTerms? terms, String channel = 'AI'}) async {
    await _wait('apply');
    final s = store.state;
    final g = _guard(s, false);
    if (g != null) return _err(g.code, g.kind, '${g.message} 가입 요청은 전송되지 않았어요.', submitted: false);
    if (requestId.isEmpty) return _err('REQUEST_ID_REQUIRED', 'BUSINESS_REJECT', '요청 식별값이 없어요.', submitted: false);
    for (final a in s.applications.values) {
      if (a.requestId == requestId) {
        events.add('BANK', '중복 가입 요청 차단: $requestId → 기존 ${a.id}');
        return BankResult.success(SubmitResult(application: a, duplicate: true));
      }
    }
    final product = getProduct(productId);
    if (product == null) return _err('PRODUCT_NOT_FOUND', 'BUSINESS_REJECT', '상품을 찾을 수 없어요.', submitted: false);
    final unmet = [for (final c in product.conditions) if (s.facts[conditions[c]!.fact] != true) conditions[c]!.label];
    if (unmet.isNotEmpty) {
      return _err('CONDITION_UNMET', 'BUSINESS_REJECT', '가입 조건을 충족하지 않아 가입되지 않았어요.', submitted: false, unmet: unmet);
    }
    final outcome = s.simulation.nextApplicationOutcome;
    final id = 'APP-${2001 + s.applications.length}';
    final app = Application(
      id: id,
      requestId: requestId,
      productId: productId,
      terms: terms,
      channel: channel,
      status: outcome,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      failureReason: outcome == 'FAILED' ? '은행에서 가입 요청을 처리하지 못했어요.' : null,
    );
    store.update((d) {
      d.applications[id] = Application.fromJson(app.toJson())!;
      d.simulation.nextApplicationOutcome = 'SUCCESS';
    }, '가입 요청 $id 처리 결과: $outcome');
    return BankResult.success(SubmitResult(application: app, duplicate: false));
  }

  /// 결과 조회 전용. 어떤 경우에도 가입 요청을 다시 보내지 않는다.
  Future<BankResult<Application>> getApplicationResult(String appId) async {
    await _wait('query');
    final s = store.state;
    final g = _guard(s, true);
    if (g != null) return BankResult.failure(g);
    final app = s.applications[appId];
    if (app == null) return _err('APP_NOT_FOUND', 'BUSINESS_REJECT', '가입 요청을 찾을 수 없어요.');
    return BankResult.success(app);
  }

  /* ---------------- 상담 ---------------- */

  /// 상담 접수. 요약을 만든 것과 실제 접수 완료를 구분한다.
  Future<BankResult<ConsultTicket>> createConsultation(List<String> summary) async {
    await _wait('mutate');
    final s = store.state;
    if (!s.system.bankAvailable || s.simulation.nextConsultOutcome == 'FAILED') {
      events.add('BANK', '상담 접수 실패 (가상 응답)');
      return _err('CONSULT_FAILED', 'QUERY_FAILURE', '상담 접수가 완료되지 않았어요.');
    }
    final id = 'CS-${5001 + s.consultations.length}';
    final ticket = ConsultTicket(id: id, summary: summary, status: 'ACCEPTED', eta: '영업일 기준 1일 이내 상담사 연락', createdAt: DateTime.now().millisecondsSinceEpoch);
    store.update((d) => d.consultations[id] = ConsultTicket.fromJson(ticket.toJson())!, '상담 접수 $id');
    return BankResult.success(ticket);
  }

  /* ---------------- 시연 전용 ---------------- */

  bool demoResolveApplication(String appId, String status) {
    final app = store.state.applications[appId];
    if (app == null || (status != 'SUCCESS' && status != 'FAILED')) return false;
    if (app.status == 'SUCCESS' || app.status == 'FAILED') return false;
    store.update((d) {
      d.applications[appId]!.status = status;
      if (status == 'FAILED') d.applications[appId]!.failureReason = '은행에서 가입 요청을 처리하지 못했어요.';
    }, '[시연] 가입 $appId 은행 측 확정: $status');
    return true;
  }
}
