// 실제 화면을 눌러 가며 통합 시나리오(해외주식 계좌 AI 가입 지원)와 자산관리 상담, 시연 제어를 확인한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:won_solution_pass/data/key_value_storage.dart';
import 'package:won_solution_pass/domain/asset_advisor.dart' as aa;
import 'package:won_solution_pass/domain/scenario.dart';
import 'package:won_solution_pass/main.dart';
import 'package:won_solution_pass/ui/app_scope.dart';

void main() {
  late AppServices services;

  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    services = createServices(MemoryStorage(), latencyScale: 0);
    await tester.pumpWidget(WonSolutionPassApp(services: services));
    await settle(tester);
  }

  Future<void> tapFinder(WidgetTester tester, Finder f, String reason) async {
    expect(f, findsWidgets, reason: reason);
    await tester.ensureVisible(f.last);
    await tester.pump();
    await tester.tap(f.last, warnIfMissed: false);
    await settle(tester);
  }

  Future<void> tap(WidgetTester tester, String text) => tapFinder(tester, find.text(text), '"$text" 버튼이 보여야 함');

  testWidgets('해외주식 계좌: 상품 → AI 가입 지원 → 숨은 선행조건 7단계 → 승인 → 개설', (tester) async {
    await boot(tester);
    see('시연용 목업');

    final app = services.controller;
    app.openProduct(DemoScenario.productId);
    await settle(tester);
    await tap(tester, '상품 가입');
    await tap(tester, 'AI와 함께 가입');
    await tap(tester, '동의하고 시작');

    // 실물 신분증 없음, 모바일 신분증 있음
    await tap(tester, '아니요, 없어요');
    await tap(tester, '네, 있어요');
    expect(app.joinFsm.state, 'OPTIONS_READY');

    final order = <String>[];
    for (var i = 0; i < 10 && (app.joinFsm.state == 'OPTIONS_READY' || app.joinFsm.state == 'REMAINING'); i++) {
      final id = app.session.join!.route!.steps.first.actionId;
      final task = getTask(id)!;
      order.add(id);
      await tapFinder(tester, find.widgetWithText(InkWell, task.label), '"${task.label}" 방법 카드가 보여야 함');
      expect(app.taskModal?.taskId, id);
      for (final f in task.fields) {
        app.taskModalField(f.id, f.options.first);
      }
      await tap(tester, '진행하기');
      await tap(tester, '닫고 은행 기록 확인');
    }
    expect(order, ['MOBILE_ID_VERIFY', 'OPEN_ACCOUNT_OTHERBANK', 'ISSUE_CERT', 'KYC_UPDATE', 'FX_REGISTER', 'OPEN_FX_ACCOUNT', 'INVESTOR_PROFILE']);
    expect(app.joinFsm.state, 'READY_TO_APPLY');
    expect(services.store.state.applications, isEmpty, reason: '승인 전에는 가입 요청이 없어야 함');

    await tap(tester, '가입 정보 확인하기');
    await tap(tester, '가입 승인');
    see('가입을 승인할까요?');
    await tap(tester, '승인하고 가입 요청');
    expect(app.joinFsm.state, 'COMPLETED');
    expect(services.store.state.applications.values.single.status, 'SUCCESS');
  });

  testWidgets('직접 가입: 단계 진행 → 부족 조건 안내 → 메뉴로 이동', (tester) async {
    await boot(tester);
    final app = services.controller;
    app.openProduct('SAVINGS_GOAL');
    await settle(tester);
    await tap(tester, '상품 가입');
    await tap(tester, '직접 가입');
    await tap(tester, '가입 시작');
    expect(app.directFsm.state, 'D_STEP');
    app.direct.toggleAgree();
    app.direct.setMonths(getProduct('SAVINGS_GOAL')!.periods.first);
    for (var i = 0; i < 6 && app.directFsm.state == 'D_STEP'; i++) {
      await tap(tester, '다음');
    }
    expect(app.directFsm.state, 'D_NOTICE');
    see('단계를 진행할 수 없어요');
    await tap(tester, '메뉴로 이동');
    expect(app.directFsm.state, 'D_SELF_FIX');
  });

  testWidgets('자산관리 상담: 목표 → 질문 → 제안', (tester) async {
    await boot(tester);
    final app = services.controller;
    await app.asset.startAction();
    await settle(tester);
    expect(app.assetFsm.state, 'CONSENT');
    await tap(tester, '동의하고 시작');
    expect(app.assetFsm.state, 'GOAL');

    await app.asset.setGoal('해외주식 투자를 처음 시작해 보고 싶어요');
    await settle(tester);
    for (var i = 0; i < 4 && app.assetFsm.state == 'ASKING'; i++) {
      final q = app.session.asset!.pendingQuestion!;
      await tap(tester, aa.questions[q]!.options.first.$1);
    }
    expect(app.assetFsm.state, 'REVIEW');
    see('원금 손실');
  });

  testWidgets('시연 제어: 진행 과정·상태머신·자가 테스트 섹션 표시', (tester) async {
    await boot(tester);
    await tapFinder(tester, find.bySemanticsLabel('시연 제어'), '시연 제어 버튼이 보여야 함');
    see('DEMO CONTROL');
    see('진행 과정');
    see('홈에서 AI 자산관리 상담으로 시작');
    expect(find.byType(CustomPaint), findsWidgets);
    await tap(tester, '데모 초기화');
    expect(find.text('DEMO CONTROL'), findsNothing);
  });
}

void see(String text) => expect(find.textContaining(text, findRichText: true), findsWidgets, reason: '"$text" 문구가 보여야 함');

/// 화면 전환·지연 타이머가 끝날 때까지 프레임을 진행한다.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
