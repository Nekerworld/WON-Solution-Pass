import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'app/case_controller.dart';
import 'app/chatbot_service.dart';
import 'data/bank_store.dart';
import 'data/key_value_storage.dart';
import 'data/mock_bank.dart';
import 'demo/demo_screen.dart';
import 'domain/event_log.dart';
import 'domain/pathfinder.dart';
import 'ui/app_scope.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await PrefsStorage.open();
  runApp(WonSolutionPassApp(services: createServices(storage)));
}

/// 의존성 조립. 백엔드·외부 API 없이 기기 안의 가상 은행만 사용한다.
AppServices createServices(KeyValueStorage storage, {double latencyScale = 1, double timeScale = 1}) {
  final events = EventLog();
  final store = BankStore(events: events, storage: storage);
  final bank = MockBank(store: store, latencyScale: latencyScale);
  final pathfinder = Pathfinder(events: events);
  final chatbot = ChatbotService(bank: bank, pathfinder: pathfinder, events: events);
  final controller = CaseController(
    store: store,
    bank: bank,
    events: events,
    pathfinder: pathfinder,
    chatbot: chatbot,
    storage: storage,
    timeScale: timeScale,
  );
  return AppServices(controller: controller, store: store, bank: bank, events: events, pathfinder: pathfinder);
}

class WonSolutionPassApp extends StatefulWidget {
  const WonSolutionPassApp({super.key, required this.services});

  final AppServices services;

  @override
  State<WonSolutionPassApp> createState() => _WonSolutionPassAppState();
}

class _WonSolutionPassAppState extends State<WonSolutionPassApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    widget.services.controller.start();
  }

  void _openDemo() {
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '개발자 도구 닫기',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, _, _) => const _DemoModal(),
      transitionBuilder: (context, anim, _, child) => FadeTransition(opacity: anim, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: widget.services,
      child: MaterialApp(
        title: 'WON 해결패스',
        navigatorKey: _navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        builder: (context, child) => _PhoneFrame(child: child!),
        home: AppShell(onOpenDemo: _openDemo),
      ),
    );
  }
}

/// 개발자 도구. 앱 위를 블러 처리하고 시연 컨트롤을 카드로 띄운다.
class _DemoModal extends StatelessWidget {
  const _DemoModal();

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: const ColoredBox(color: Color(0x8A101820)),
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          top: padding.top + 28,
          bottom: padding.bottom + 12,
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            removeBottom: true,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: const DemoScreen(),
            ),
          ),
        ),
      ],
    );
  }
}

/// 넓은 화면(웹·데스크톱)에서는 휴대폰 크기 프레임 안에 그린다.
class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (mq.size.width <= 600) return child;
    final height = math.min(844.0, mq.size.height - 40);
    final width = height * 390 / 844;
    return ColoredBox(
      color: const Color(0xFFEEF2F7),
      child: Center(
        child: Container(
          width: width,
          height: height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(36),
            boxShadow: const [BoxShadow(color: Color(0x470A1E46), blurRadius: 80, offset: Offset(0, 30))],
          ),
          child: MediaQuery(
            data: mq.copyWith(size: Size(width, height), padding: EdgeInsets.zero, viewPadding: EdgeInsets.zero),
            child: child,
          ),
        ),
      ),
    );
  }
}
