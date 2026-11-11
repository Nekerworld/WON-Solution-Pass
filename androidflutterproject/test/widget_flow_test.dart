// 실제 화면을 눌러 가며 P0 흐름(홈 → 이체 → 진단 → 계획 → OTP → 한도 → 원래 이체 → 승인 → 결과)을 확인한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:won_solution_pass/data/key_value_storage.dart';
import 'package:won_solution_pass/demo/demo_screen.dart';
import 'package:won_solution_pass/domain/bank_state.dart';
import 'package:won_solution_pass/main.dart';
import 'package:won_solution_pass/ui/app_scope.dart';

void main() {
  late AppServices services;

  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    services = createServices(MemoryStorage(), latencyScale: 0, timeScale: 0);
    await tester.pumpWidget(WonSolutionPassApp(services: services));
    await settle(tester);
  }

  Future<void> tap(WidgetTester tester, String text) async {
    final f = find.text(text);
    expect(f, findsWidgets, reason: '"$text" 버튼이 보여야 함');
    await tester.ensureVisible(f.last);
    await tester.pump();
    await tester.tap(f.last);
    await settle(tester);
  }

  testWidgets('P0 흐름을 화면으로 끝까지 진행', (tester) async {
    await boot(tester);
    see('우리 주거래 통장');
    see('실제 은행과 연결되어 있지 않으며');

    await tap(tester, '이체');
    expect(find.text('홍길동'), findsWidgets);

    await tap(tester, '이체하기');
    see('150만원은 나가지 않았어요');
    see('디지털 OTP 등록과 이체한도 변경이 필요해요.');

    await tap(tester, '해결 방법 보기');
    see('150만원 이체를 진행하려면\n다음 두 가지 설정이 필요합니다.');

    await tap(tester, '디지털 OTP 등록하러 가기');
    await tap(tester, '디지털 OTP 등록 진행');
    see('디지털 OTP 등록이 완료되었어요');

    await tap(tester, '해결패스로 돌아가기');
    expect(services.store.state.customer.digitalOtpRegistered, isTrue);

    await tap(tester, '이체한도 변경하러 가기');
    await tap(tester, '변경 가능 여부 확인');
    await tap(tester, '이 한도로 변경');
    see('1일 이체한도가 변경되었어요');

    await tap(tester, '해결패스로 돌아가기');
    see('사전 조건 확인 완료');

    await tap(tester, '원래 이체로 돌아가기');
    expect(services.store.state.transactions, isEmpty, reason: '자동 이체 금지');

    await tap(tester, '이체하기');
    see('홍길동님에게\n1,500,000원을 보낼까요?');
    await tap(tester, '보내기');
    see('이체 완료를 확인했어요');
    see('WON 해결패스 해결 완료');
    expect(services.store.state.transactions.values.single.status, TransferStatus.success);

    await tap(tester, '홈으로');
    see('우리 주거래 통장');
  });

  testWidgets('해결 계획에서 뒤로 가기는 홈으로 간다', (tester) async {
    await boot(tester);
    await tap(tester, '이체');
    await tap(tester, '이체하기');
    await tap(tester, '해결 방법 보기');
    see('다음 두 가지 설정이 필요합니다.');
    await tester.tap(find.bySemanticsLabel('뒤로 가기'));
    await settle(tester);
    see('우리 주거래 통장');
    expect(services.controller.router.current?.id.name, 'home');
  });

  testWidgets('계좌 제한이면 해결 경로 없이 상담 안내로 간다', (tester) async {
    await boot(tester);
    services.store.update((d) => d.customer.accountRestricted = true, '테스트');
    await tap(tester, '이체');
    await tap(tester, '이체하기');
    see('150만원은 나가지 않았어요');
    see('계좌 이용 제한이 확인되었어요.');
    await tap(tester, '상담 안내 보기');
    see('해결패스는 제한 해제 방법을 안내하지 않아요.');
    expect(services.store.state.transactions, isEmpty);
  });

  testWidgets('시연 제어 화면: 그래프·로그 표시와 프리셋 적용', (tester) async {
    await boot(tester);
    await tap(tester, '이체');
    await tap(tester, '이체하기');
    await tap(tester, '해결 방법 보기');
    await services.controller.goHome();
    await settle(tester);

    await tester.tap(find.bySemanticsLabel('개발자 도구'));
    await settle(tester);
    see('DEMO CONTROL');
    final demoStates = tester
        .stateList<ScrollableState>(find.descendant(of: find.byType(DemoScreen), matching: find.byType(Scrollable)))
        .toList()
      ..sort((a, b) => b.position.viewportDimension.compareTo(a.position.viewportDimension));
    final demoList = demoStates.first.position;

    Future<void> reveal(String text) async {
      for (var i = 0; i < 40; i++) {
        if (find.text(text).evaluate().isNotEmpty) return;
        if (demoList.pixels >= demoList.maxScrollExtent) break;
        demoList.jumpTo((demoList.pixels + 240).clamp(0, demoList.maxScrollExtent));
        await tester.pump();
      }
      expect(find.text(text), findsWidgets, reason: '"$text" 문구가 보여야 함');
    }

    await reveal('이벤트 로그');
    see('상태 그래프');
    expect(find.byType(CustomPaint), findsWidgets);

    demoList.jumpTo(0);
    await tester.pump();
    await tap(tester, 'D 모두 충족');
    see('우리 주거래 통장');
    expect(find.text('DEMO CONTROL'), findsNothing);
    expect(services.store.state.customer.digitalOtpRegistered, isTrue);
    expect(services.store.state.customer.transferLimit, 2000000);
    expect(services.controller.session.caseCtx, isNull);
  });

  testWidgets('챗봇이 은행 상태를 근거로 답한다', (tester) async {
    await boot(tester);
    await services.controller.goChat();
    await settle(tester);
    final before = services.controller.session.chat.length;
    await tester.enterText(find.byType(TextField), '이체한도 얼마야?');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await settle(tester);
    expect(services.controller.session.chat.length, greaterThanOrEqualTo(before + 2));
    see('1,000,000원');
  });
}

void see(String text) => expect(find.textContaining(text, findRichText: true), findsWidgets, reason: '"$text" 문구가 보여야 함');

/// 화면 전환·지연 타이머가 끝날 때까지 프레임을 진행한다.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
