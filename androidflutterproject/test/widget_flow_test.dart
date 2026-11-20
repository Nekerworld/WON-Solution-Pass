// 실제 화면을 눌러 가며 통합 시나리오(해외주식 계좌 AI 가입 지원)와 목돈·자산관리 상담, 시연 제어를 확인한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:won_solution_pass/app/router.dart';
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

  testWidgets('해외주식 계좌: 상품 → AI 가입 지원 → 외환·외화계좌·투자성향 → 승인 → 개설', (tester) async {
    await boot(tester);
    final app = services.controller;
    app.openProduct(DemoScenario.productId);
    await settle(tester);
    await tap(tester, 'AI와 함께 가입');
    await tap(tester, '가입 조건 확인');
    expect(app.session.join!.questionsAsked, 0, reason: '이미 있는 계좌 고객에게는 질문하지 않음');

    final order = <String>[];
    for (var i = 0; i < 6 && (app.joinFsm.state == 'OPTIONS_READY' || app.joinFsm.state == 'REMAINING'); i++) {
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
    expect(order, ['FX_REGISTER', 'OPEN_FX_ACCOUNT', 'INVESTOR_PROFILE']);
    expect(app.joinFsm.state, 'READY_TO_APPLY');
    expect(services.store.state.applications, isEmpty, reason: '승인 전에는 가입 요청이 없어야 함');

    await tap(tester, '가입 정보 확인하기');
    await tap(tester, '가입 승인');
    see('가입을 승인할까요?');
    await tap(tester, '승인하고 가입 요청');
    expect(app.joinFsm.state, 'COMPLETED');
    expect(services.store.state.applications.values.single.status, 'SUCCESS');
    see('해외주식 계좌 개설이 완료됐어요');
  });

  testWidgets('직접 가입(진입점 없음): 단계 진행 → 부족 조건 안내 → 메뉴로 이동', (tester) async {
    await boot(tester);
    final app = services.controller;
    services.store.update((d) => d.facts['identityVerified'] = false, '[테스트] 실명확인 없음');
    await app.direct.startAction('SAVINGS_GOAL');
    await settle(tester);
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
    await tap(tester, '상담 시작');
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

  testWidgets('홈 AI 상담과 포춘쿠키는 목돈 상담 채팅으로 이어짐', (tester) async {
    await boot(tester);
    final app = services.controller;
    await app.startConsult();
    await settle(tester);
    expect(app.router.current?.id, ScreenId.lumpsum);
    see('어떤 목표로 상담받고 싶으세요');

    await app.goHome();
    await settle(tester);
    await tapFinder(tester, find.bySemanticsLabel('추천 질문'), '포춘쿠키가 보여야 함');
    await tap(tester, '물어보기');
    expect(app.router.current?.id, ScreenId.lumpsum);
    expect(app.session.lumpsum!.chat.where((m) => m.role == 'user'), isNotEmpty, reason: '쿠키 문장이 전송되어야 함');
  });

  testWidgets('시연 패널: 열기 → 처음부터 → 닫기', (tester) async {
    await boot(tester);
    await tapFinder(tester, find.bySemanticsLabel('시연 제어'), '시연 제어 버튼이 보여야 함');
    see('처음부터');
    await tap(tester, '처음부터');
    expect(services.controller.joinFsm.state, 'IDLE');
    await tapFinder(tester, find.bySemanticsLabel('닫기'), '닫기 버튼이 보여야 함');
    expect(find.text('처음부터'), findsNothing);
  });
}

void see(String text) => expect(find.textContaining(text, findRichText: true), findsWidgets, reason: '"$text" 문구가 보여야 함');

/// 화면 전환·지연 타이머가 끝날 때까지 프레임을 진행한다.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
