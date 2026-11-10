// 오케스트레이터(CaseController) 흐름 테스트: P0 흐름과 결과 분기, 세션 복원.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:won_solution_pass/app/case_controller.dart';
import 'package:won_solution_pass/app/chatbot_service.dart';
import 'package:won_solution_pass/app/overlays.dart';
import 'package:won_solution_pass/app/router.dart';
import 'package:won_solution_pass/data/bank_store.dart';
import 'package:won_solution_pass/data/key_value_storage.dart';
import 'package:won_solution_pass/data/mock_bank.dart';
import 'package:won_solution_pass/domain/bank_state.dart';
import 'package:won_solution_pass/domain/event_log.dart';
import 'package:won_solution_pass/domain/fsm.dart';
import 'package:won_solution_pass/domain/pathfinder.dart';

void main() {
  late MemoryStorage storage;
  late BankStore store;
  late CaseController app;

  CaseController build() {
    final events = EventLog();
    store = BankStore(events: events, storage: storage);
    final bank = MockBank(store: store, latencyScale: 0);
    final pathfinder = Pathfinder(events: events);
    return CaseController(
      store: store,
      bank: bank,
      events: events,
      pathfinder: pathfinder,
      chatbot: ChatbotService(bank: bank, pathfinder: pathfinder, events: events),
      storage: storage,
      timeScale: 0,
    );
  }

  setUp(() async {
    storage = MemoryStorage();
    app = build();
    await app.start();
  });

  Future<void> until(bool Function() cond, [String what = '조건']) async {
    for (var i = 0; i < 2000; i++) {
      if (cond()) return;
      await Future<void>.delayed(Duration.zero);
    }
    fail('$what 대기 시간 초과');
  }

  ScreenId? screen() => app.router.current?.id;

  /// 진단 시트 요약이 나타날 때까지 기다린 뒤 요약 버튼을 누른다.
  Future<void> continueDiagnosis() async {
    await until(() => (app.sheet as DiagnosisSheetState?)?.summary != null, '진단 요약');
    app.diagContinue();
  }

  /// 이체 확인 모달을 기다린 뒤 승인/취소한다.
  Future<void> answerModal(bool approve) async {
    await until(() => app.modal != null, '확인 모달');
    app.resolveModal(approve);
  }

  test('P0: 이체 실패 → 진단 → 계획 → OTP → 한도 → 원래 이체 → 승인 → 성공', () async {
    await app.goTransfer();
    expect(screen(), ScreenId.transfer);

    final attempt = app.attemptTransfer(null);
    await continueDiagnosis();
    await attempt;
    await until(() => screen() == ScreenId.plan, '계획 화면');
    expect(app.fsm.state, FsmState.planReady);
    expect(app.session.plan!.steps.map((s) => s.actionId).toList(), ['REGISTER_OTP', 'CHANGE_TRANSFER_LIMIT', 'RETURN_TO_TRANSFER']);
    expect(store.state.transactions, isEmpty, reason: '진단 중 거래가 생기면 안 됨');

    await app.openFlow('otp-registration');
    expect(screen(), ScreenId.otp);
    expect(app.fsm.state, FsmState.waitingUser);
    await app.registerOtp();
    expect(app.router.current!.params['phase'], 'done');
    expect(store.state.customer.digitalOtpRegistered, isTrue);

    await app.returnFromFlow();
    expect(screen(), ScreenId.plan);
    expect(app.fsm.state, FsmState.planReady);
    expect(app.session.plan!.steps.map((s) => s.actionId).toList(), ['CHANGE_TRANSFER_LIMIT', 'RETURN_TO_TRANSFER']);

    await app.openFlow('limit-management');
    expect(screen(), ScreenId.limit);
    expect(app.session.limitSelection, 1500000);
    await app.limitApply(app.session.limitSelection!);
    expect(store.state.customer.transferLimit, 1500000);

    await app.returnFromFlow();
    expect(app.fsm.state, FsmState.readyToRetry);
    expect(app.session.plan!.status, PlanStatus.ready);

    await app.returnToTransfer();
    expect(screen(), ScreenId.transfer);
    expect(app.router.current!.params['returned'], true);
    expect(store.state.transfer.amount, 1500000, reason: '원래 이체 금액 유지');
    expect(store.state.transactions, isEmpty, reason: '자동 실행 금지');

    final approve = app.attemptTransfer(null);
    await answerModal(true);
    await approve;
    expect(screen(), ScreenId.result);
    expect(app.fsm.state, FsmState.completed);
    expect(store.state.transactions.length, 1);
    expect(store.state.transactions.values.first.status, TransferStatus.success);

    await app.goHome();
    expect(screen(), ScreenId.home);
    expect(app.fsm.state, FsmState.idle);
  });

  test('확인 모달에서 취소하면 거래가 생기지 않는다', () async {
    store.update((d) => d.transfer.amount = 300000);
    await app.goTransfer();
    final attempt = app.attemptTransfer(null);
    await answerModal(false);
    await attempt;
    expect(store.state.transactions, isEmpty);
    expect(screen(), ScreenId.transfer);
  });

  test('계좌 제한이면 상담 화면으로 안내하고 자동 해결 경로를 만들지 않는다', () async {
    store.update((d) => d.customer.accountRestricted = true);
    await app.goTransfer();
    final attempt = app.attemptTransfer(null);
    await continueDiagnosis();
    await attempt;
    await until(() => screen() == ScreenId.support, '상담 화면');
    expect(app.fsm.state, FsmState.escalated);
    expect(app.session.caseCtx!.escalation!.code, 'ACCOUNT_RESTRICTED');
  });

  test('결과 UNKNOWN → 조회로 확정, 재전송하지 않음', () async {
    store.update((d) {
      d.customer.digitalOtpRegistered = true;
      d.customer.transferLimit = 2000000;
      d.simulation.nextTransferOutcome = TransferStatus.unknown;
    });
    // 해결패스 경유로 만들기 위해 수동 진단부터 시작
    final diag = app.openPass();
    await continueDiagnosis();
    await diag;
    expect(app.fsm.state, FsmState.readyToRetry);
    await app.returnToTransfer();
    final attempt = app.attemptTransfer(null);
    await answerModal(true);
    await attempt;
    expect(app.fsm.state, FsmState.resultUncertain);

    final txId = app.session.resultCtx!.transactionId;
    store.update((d) => d.transactions[txId]!.status = TransferStatus.success);
    await app.queryResult();
    expect(app.fsm.state, FsmState.completed);
    expect(store.state.transactions.length, 1, reason: '재전송 금지');
  });

  test('세션 복원: 진단 중 종료되면 IDLE, 계획 상태는 유지', () async {
    await app.goTransfer();
    final attempt = app.attemptTransfer(null);
    await continueDiagnosis();
    await attempt;
    expect(app.fsm.state, FsmState.planReady);

    final restored = build();
    expect(restored.fsm.state, FsmState.planReady);
    expect(restored.session.plan!.steps.length, 3);

    final raw = jsonDecode(storage.read('wsp.session.v1')!) as Map<String, Object?>;
    storage.write('wsp.session.v1', jsonEncode({...raw, 'fsm': 'DIAGNOSING'}));
    final fromDiagnosing = build();
    expect(fromDiagnosing.fsm.state, FsmState.idle);
    expect(fromDiagnosing.session.plan, isNull);
  });

  test('허용목록 밖의 화면 연결은 차단된다', () async {
    await app.openFlow('https://example.com');
    expect(screen(), ScreenId.home);
    expect(app.toasts.last.text, '허용되지 않은 화면 연결이에요.');
  });
}
