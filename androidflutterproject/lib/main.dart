import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import 'data/key_value_storage.dart';
import 'demo/demo_screen.dart';
import 'ui/app_scope.dart';
import 'ui/responsive.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await PrefsStorage.open();
  runApp(WonSolutionPassApp(services: createServices(storage)));
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
      barrierLabel: '시연 제어 닫기',
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

/// 시연 제어 화면. 앱 위를 블러 처리하고 시연 컨트롤을 카드로 띄운다.
class _DemoModal extends StatelessWidget {
  const _DemoModal();

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final side = 12 + wideInset(MediaQuery.sizeOf(context).width, 744);
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
          left: side,
          right: side,
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
/// 태블릿 기기에서는 프레임 없이 전체 화면을 쓰고, 각 화면이 본문 폭을 제한한다.
class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    if (mq.size.width <= 600 || isMobileOS) return child;
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
