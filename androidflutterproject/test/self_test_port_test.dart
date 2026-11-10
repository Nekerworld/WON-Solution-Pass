// prototype/js/selfTest.js의 자가 테스트(명세 14장 1~12번 + 보조 항목)를 그대로 옮긴 단위 테스트.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:won_solution_pass/app/chatbot_service.dart';
import 'package:won_solution_pass/app/diagnosis.dart';
import 'package:won_solution_pass/data/bank_store.dart';
import 'package:won_solution_pass/data/mock_bank.dart';
import 'package:won_solution_pass/domain/bank_state.dart';
import 'package:won_solution_pass/domain/bank_types.dart';
import 'package:won_solution_pass/domain/chatbot_nlu.dart';
import 'package:won_solution_pass/domain/event_log.dart';
import 'package:won_solution_pass/domain/fsm.dart';
import 'package:won_solution_pass/domain/pathfinder.dart';
import 'package:won_solution_pass/domain/policy.dart';

void main() {
  late EventLog events;
  late BankStore store;
  late MockBank bank;
  late Pathfinder pathfinder;
  late ChatbotService bot;

  setUp(() {
    events = EventLog();
    store = BankStore(events: events);
    bank = MockBank(store: store, latencyScale: 0);
    pathfinder = Pathfinder(events: events);
    bot = ChatbotService(bank: bank, pathfinder: pathfinder, events: events);
  });

  void resetTo([void Function(BankState d)? mutator]) {
    store.replace(BankState.initial());
    if (mutator != null) store.update(mutator, '[TEST] 상태 설정');
  }

  Future<ComputeResult> planNow() => computeFromBank(bank, pathfinder);

  String ids(Plan plan) => plan.steps.map((s) => s.actionId).join(',');

  int txCount() => store.state.transactions.length;

  CaseFsm testFsm() => CaseFsm();

  void runEvents(CaseFsm f, List<FsmEvent> list) {
    for (final e in list) {
      f.transition(e);
    }
  }

  TransferDraft draftWithNewRequest() => store.state.transfer.copyWith(requestId: bank.newRequestId());

  test('1. 초기 이체 시도에서 복합 오류 감지', () async {
    resetTo();
    final v = await bank.validateTransfer();
    final codes = v.data!.reasons.map((r) => r.code).toList();
    expect(v.data!.valid, isFalse, reason: '검사 통과되면 안 됨');
    expect(codes, containsAll(['LIMIT_EXCEEDED', 'OTP_REQUIRED']));
    final r = await planNow();
    expect(ids(r.plan), 'REGISTER_OTP,CHANGE_TRANSFER_LIMIT,RETURN_TO_TRANSFER');
  });

  test('2. OTP 등록 후 남은 해결 경로 자동 갱신', () async {
    resetTo();
    final reg = await bank.registerDigitalOtp();
    expect(reg.ok, isTrue, reason: 'OTP 등록 실패');
    final r = await planNow();
    expect(ids(r.plan), 'CHANGE_TRANSFER_LIMIT,RETURN_TO_TRANSFER');
  });

  test('3. 이체한도 변경 후 원래 이체 복귀 (이체 정보 유지)', () async {
    resetTo();
    await bank.registerDigitalOtp();
    final ch = await bank.changeTransferLimit(1500000);
    expect(ch.ok, isTrue, reason: '한도 변경 실패');
    final r = await planNow();
    expect(r.plan.status, PlanStatus.ready);
    expect(ids(r.plan), 'RETURN_TO_TRANSFER');
    final init = BankState.initial().transfer;
    expect(r.draft!.amount, init.amount);
    expect(r.draft!.recipient, init.recipient);
    expect(r.draft!.recipientBank, init.recipientBank);
    expect(r.draft!.fromAccount, init.fromAccount);
  });

  test('4. 사용자의 직접 승인 없이 거래가 실행되지 않음', () async {
    resetTo();
    await bank.registerDigitalOtp();
    await bank.changeTransferLimit(1500000);
    expect(txCount(), 0, reason: '해결 절차만으로 거래가 생성됨');
    final f = testFsm();
    for (final ev in [
      FsmEvent.transferFailed,
      FsmEvent.pathFound,
      FsmEvent.stepSelected,
      FsmEvent.userReturned,
      FsmEvent.pathFound,
      FsmEvent.stepSelected,
      FsmEvent.userReturned,
      FsmEvent.allMet,
    ]) {
      expect(f.transition(ev).ok, isTrue, reason: '전이 실패: ${ev.code}');
    }
    expect(f.state, FsmState.readyToRetry);
    expect(txCount(), 0, reason: '준비 완료 상태에서 자동 거래 발생');
    final noId = await bank.submitTransfer(store.state.transfer.withoutRequestId());
    expect(noId.ok, isFalse);
    expect(txCount(), 0, reason: '요청 식별값 없는 거래가 실행됨');
  });

  test('5. 이체 성공(SUCCESS) 응답 후에만 해결 완료', () async {
    resetTo((d) {
      d.customer.digitalOtpRegistered = true;
      d.customer.transferLimit = 1500000;
    });
    final f = testFsm();
    runEvents(f, [FsmEvent.transferFailed, FsmEvent.noActionNeeded]);
    expect(f.transition(FsmEvent.resultSuccess).ok, isFalse, reason: 'VERIFYING 이전에 완료 전이 허용됨');
    f.transition(FsmEvent.userApproved);
    store.update((d) => d.simulation.nextTransferOutcome = TransferStatus.pending, '[TEST]');
    final p = await bank.submitTransfer(draftWithNewRequest());
    expect(p.ok, isTrue);
    expect(p.data!.transaction.status, TransferStatus.pending);
    expect(f.state, FsmState.verifying, reason: 'PENDING에서 상태가 바뀜');
    bank.demoResolveTransaction(p.data!.transaction.id, TransferStatus.success);
    final q = await bank.getTransferResult(p.data!.transaction.id);
    expect(q.data!.status, TransferStatus.success);
    expect(f.transition(FsmEvent.resultSuccess).ok, isTrue);
    expect(f.state, FsmState.completed);
  });

  test('6. OTP가 이미 등록된 경우 중복 등록 안내 없음', () async {
    resetTo((d) => d.customer.digitalOtpRegistered = true);
    final r = await planNow();
    expect(ids(r.plan).contains('REGISTER_OTP'), isFalse, reason: '경로: ${ids(r.plan)}');
    final reply = await bot.respond('이체가 왜 안 돼?');
    expect(reply.links.every((l) => l.flowId != 'otp-registration'), isTrue, reason: 'OTP 등록 링크 제공됨');
    expect(reply.text.contains('OTP 등록을 진행'), isFalse, reason: '응답: ${reply.text}');
    final dup = await bank.registerDigitalOtp();
    expect(dup.ok, isFalse);
    expect(dup.error!.code, 'ALREADY_REGISTERED');
  });

  test('7. 한도가 충분한 경우 불필요한 변경 안내 없음', () async {
    resetTo((d) => d.customer.transferLimit = 2000000);
    final r = await planNow();
    expect(ids(r.plan), 'REGISTER_OTP,RETURN_TO_TRANSFER');
    final reply = await bot.respond('이체한도 어디서 바꿔?');
    expect(reply.text.contains('변경하지 않아도'), isTrue, reason: '응답: ${reply.text}');
  });

  test('8. 계좌 제한 상태에서 해결 경로 생성 없음', () async {
    resetTo((d) => d.customer.accountRestricted = true);
    final r = await planNow();
    expect(r.plan.status, PlanStatus.blocked);
    expect(r.plan.steps, isEmpty);
    expect(r.plan.blocker!.ruleId, 'R05');
    final reply = await bot.respond('이체가 왜 안 돼?');
    expect(reply.links.every((l) => l.flowId == 'support'), isTrue, reason: '상담 외 링크 제공됨');
    final otp = await bank.registerDigitalOtp();
    expect(otp.ok, isFalse, reason: '제한 상태에서 OTP 등록 허용됨');
  });

  test('9. 은행 장애 시 정상 처리로 표시하지 않음', () async {
    resetTo((d) => d.system.bankAvailable = false);
    final r = await planNow();
    expect(r.ok, isFalse);
    expect(r.plan.status, PlanStatus.blocked);
    expect(r.plan.blocker!.ruleId, 'R06');
    final v = await bank.validateTransfer();
    expect(v.ok, isFalse);
    expect(v.error!.kind, ErrorKind.queryFailure, reason: '조회 실패 구분 안 됨');
    final s = await bank.submitTransfer(draftWithNewRequest());
    expect(s.ok, isFalse);
    expect(s.error!.submitted, isFalse);
    expect(txCount(), 0, reason: '장애 중 거래 실행됨');
    resetTo((d) => d.simulation.queryFailure = true);
    final q = await bank.getCustomerState();
    expect(q.ok, isFalse);
    expect(q.error!.kind, ErrorKind.queryFailure, reason: '조회 실패 주입 미동작');
  });

  test('10. 자연어 질문이 현재 은행 상태에 따라 다르게 응답', () async {
    resetTo();
    const q = 'OTP 등록했는데 150만원 이체가 안 돼요.';
    final a = await bot.respond(q);
    final intents = a.analysis!.intentIds;
    expect(intents, containsAll(['OTP_REGISTRATION', 'TRANSFER_FAILURE']));
    expect(a.text.contains('아직 등록되지 않은'), isTrue, reason: '은행 상태 우선 실패: ${a.text}');
    final first = await bot.respond('이체가 왜 안 돼?');
    expect(first.text.contains('먼저 OTP 등록을 진행한 뒤 한도를 변경해 주세요'), isTrue, reason: '초기 응답: ${first.text}');
    await bank.registerDigitalOtp();
    final b = await bot.respond(q);
    expect(b.text.contains('디지털 OTP 등록이 확인되었습니다') && b.text.contains('한도 변경이 필요'), isTrue,
        reason: 'OTP 후 응답: ${b.text}');
    expect(a.text, isNot(b.text), reason: '상태 변화에도 응답 동일');
    await bank.changeTransferLimit(1500000);
    final c = await bot.respond('이체가 왜 안 돼?');
    expect(c.text.contains('사전 조건을 충족'), isTrue, reason: '충족 후 응답: ${c.text}');
  });

  test('11. UNKNOWN 거래를 성공으로 표시하지 않음 (중복 요청 차단)', () async {
    resetTo((d) {
      d.customer.digitalOtpRegistered = true;
      d.customer.transferLimit = 2000000;
      d.simulation.nextTransferOutcome = TransferStatus.unknown;
    });
    final f = testFsm();
    runEvents(f, [FsmEvent.manualDiagnose, FsmEvent.noActionNeeded, FsmEvent.userApproved]);
    final req = draftWithNewRequest();
    final first = await bank.submitTransfer(req);
    expect(first.ok, isTrue);
    expect(first.data!.transaction.status, TransferStatus.unknown);
    f.transition(FsmEvent.resultUnknown);
    expect(f.state, FsmState.resultUncertain);
    final again = await bank.submitTransfer(req);
    expect(again.ok, isTrue);
    expect(again.data!.duplicate, isTrue);
    expect(txCount(), 1, reason: '중복 거래 생성됨');
    expect(store.state.account.balance, BankState.initial().account.balance, reason: 'UNKNOWN인데 잔액 차감됨');
  });

  test('12. 데모 초기화 후 모든 상태 정상 복원', () async {
    store.update((d) {
      d.customer.digitalOtpRegistered = true;
      d.customer.transferLimit = 9000000;
      d.system.bankAvailable = false;
    }, '[TEST] 임의 변경');
    store.reset('[TEST] 초기화');
    expect(jsonEncode(store.state.toJson()), jsonEncode(BankState.initial().toJson()));
  });

  test('FSM: 정의되지 않은 상태 전이 거부', () {
    final f = testFsm();
    expect(f.transition(FsmEvent.userApproved).ok, isFalse);
    expect(f.state, FsmState.idle, reason: 'IDLE에서 승인 전이 허용됨');
    expect(f.transition(FsmEvent.resultSuccess).ok, isFalse, reason: 'IDLE에서 완료 전이 허용됨');
  });

  test('FSM: 결과 불명 거래는 새 건·재진단으로 갈 수 없고 결과 조회만 허용', () {
    final f = testFsm();
    runEvents(f, [FsmEvent.manualDiagnose, FsmEvent.noActionNeeded, FsmEvent.userApproved, FsmEvent.resultUnknown]);
    expect(f.state, FsmState.resultUncertain);
    expect(f.can(FsmEvent.newCase) || f.can(FsmEvent.recheck) || f.can(FsmEvent.userApproved), isFalse,
        reason: '결과 불명 상태에서 출구 허용됨');
    expect(f.transition(FsmEvent.resultQuery).ok, isTrue);
    expect(f.state, FsmState.verifying);
  });

  test('FSM: 완료·상담 인계 건은 NEW_CASE로 IDLE 복귀', () {
    final done = testFsm();
    runEvents(done, [
      FsmEvent.manualDiagnose,
      FsmEvent.noActionNeeded,
      FsmEvent.userApproved,
      FsmEvent.resultSuccess,
      FsmEvent.newCase,
    ]);
    expect(done.state, FsmState.idle, reason: 'COMPLETED 이후: ${done.state}');
    final failed = testFsm();
    runEvents(failed, [FsmEvent.manualDiagnose, FsmEvent.noActionNeeded, FsmEvent.userApproved, FsmEvent.resultFailed]);
    expect(failed.state, FsmState.escalated);
    expect(failed.transition(FsmEvent.newCase).ok, isTrue);
    expect(failed.state, FsmState.idle);
  });

  test('경로 탐색: 기본 시나리오는 정책 가중치 합이 최소인 경로(비용 6)', () async {
    resetTo();
    final r = await planNow();
    final w = DemoPolicy.actionWeights;
    final expected = w['REGISTER_OTP']! + w['CHANGE_TRANSFER_LIMIT']! + w['RETURN_TO_TRANSFER']!;
    expect(r.plan.cost, expected);
    expect(r.plan.graph != null && r.plan.graph!.edges.any((e) => e.onPath), isTrue, reason: '그래프/경로 표시 정보 없음');
  });

  test('다익스트라: 단계 수가 적어도 비용이 큰 경로는 고르지 않음', () {
    GraphNode node(String key, [bool goal = false]) => GraphNode(key: key, facts: const {}, depth: 0, goal: goal);
    GraphEdge edge(String from, String to, int weight) => GraphEdge(from: from, to: to, actionId: '$from$to', weight: weight);
    final g = StateGraph(
      startKey: 'S',
      nodes: {'S': node('S'), 'A': node('A'), 'G': node('G', true)},
      adjacency: {
        'S': [edge('S', 'G', 10), edge('S', 'A', 1)],
        'A': [edge('A', 'G', 1)],
        'G': [],
      },
    );
    final r = dijkstra(g);
    expect(r.found, isTrue);
    expect(r.cost, 2);
    expect(r.prev['G']!.from, 'A');
  });

  test('경로 탐색: 고객확인 미완료 시 고객확인 → OTP → 한도 순서 계산', () async {
    resetTo((d) => d.customer.kycCompleted = false);
    final r = await planNow();
    expect(ids(r.plan), 'COMPLETE_KYC,REGISTER_OTP,CHANGE_TRANSFER_LIMIT,RETURN_TO_TRANSFER');
  });

  test('경로 탐색: OTP 기준 이하 금액은 OTP를 요구하지 않음', () async {
    resetTo((d) {
      d.transfer.amount = 800000;
      d.customer.transferLimit = 500000;
    });
    final r = await planNow();
    expect(ids(r.plan), 'CHANGE_TRANSFER_LIMIT,RETURN_TO_TRANSFER');
  });

  test('경로 탐색: 유효 경로가 없으면 상담 안내 (한도 변경 불가)', () async {
    resetTo((d) => d.customer.transferLimitChangeAllowed = false);
    final r = await planNow();
    expect(r.plan.status, PlanStatus.noPath);
    expect(r.plan.fallback!.id, 'ESCALATE_TO_SUPPORT');
  });

  test('NLU: 해석할 수 없는 질문은 임의 답변 없이 상담 안내', () async {
    final reply = await bot.respond('오늘 날씨 어때?');
    expect(reply.analysis!.intents.first.id, 'UNKNOWN');
    expect(reply.links.length, 1);
    expect(reply.links.first.flowId, 'support');
  });

  test('NLU: 금액·진술 추출', () {
    final a = analyze('OTP 등록했는데 150만원 이체가 안 돼요.');
    expect(a.amount, 1500000);
    expect(a.claims['otpRegistered'], isTrue);
    expect(analyze('1,500,000원 보내고 싶어').amount, 1500000, reason: '숫자 금액 추출 실패');
    expect(analyze('백오십만원 보내고 싶어').amount, 1500000, reason: '한글 금액 추출 실패');
  });

  test('NLU: 이체 결과 문의 의도 인식', () {
    List<String> intentsOf(String q) => analyze(q).intentIds;
    expect(intentsOf('방금 보낸 이체 처리됐어?'), contains('TRANSFER_STATUS'), reason: '처리 여부 문의 미인식');
    expect(intentsOf('송금 결과 알려줘'), contains('TRANSFER_STATUS'), reason: '결과 문의 미인식');
  });

  test('화면 연결: 허용목록 외 flowId 차단', () {
    expect(bank.resolveFlow('https://example.com'), isNull, reason: '외부 URL 허용됨');
    expect(bank.resolveFlow('otp-registration'), 'otp', reason: '허용 화면 매핑 실패');
  });

  test('Mock Bank: 정책 위반 한도 변경 거절', () async {
    resetTo();
    final r = await bank.changeTransferLimit(1500000);
    expect(r.ok, isFalse);
    expect(r.error!.code, 'OTP_REQUIRED_FOR_LIMIT');
    expect(r.error!.kind, ErrorKind.businessReject);
  });

  test('계획 저장/복원: 입력에서 같은 계획을 다시 계산', () async {
    resetTo();
    final r = await planNow();
    final restored = Plan.fromJson(jsonDecode(jsonEncode(r.plan.toJson())) as Map<String, Object?>)!;
    expect(ids(restored), ids(r.plan));
    expect(restored.cost, r.plan.cost);
    resetTo((d) => d.system.bankAvailable = false);
    final failed = await planNow();
    final restoredFailure = Plan.fromJson(jsonDecode(jsonEncode(failed.plan.toJson())) as Map<String, Object?>)!;
    expect(restoredFailure.status, PlanStatus.blocked);
    expect(restoredFailure.blocker!.code, failed.plan.blocker!.code);
  });
}
