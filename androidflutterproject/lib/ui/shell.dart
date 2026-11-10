import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/case_controller.dart';
import '../app/router.dart';
import 'app_scope.dart';
import 'overlay_views.dart';
import 'screens/chat_screen.dart';
import 'screens/flow_screens.dart';
import 'screens/home_screen.dart';
import 'screens/plan_screen.dart';
import 'screens/result_screens.dart';
import 'screens/transfer_screen.dart';
import 'theme.dart';

/// 화면(내부 Navigator) + 시트 / 모달 / 토스트 오버레이
class AppShell extends StatelessWidget {
  const AppShell({super.key, this.onOpenDemo});

  final VoidCallback? onOpenDemo;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final handled = await app.back();
        if (!handled) await SystemNavigator.pop();
      },
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned.fill(
              child: ListenableBuilder(
                listenable: app.router,
                builder: (context, _) {
                  final pages = app.router.pages;
                  if (pages.isEmpty) {
                    return const ColoredBox(color: AppColors.bg);
                  }
                  return Navigator(
                    pages: [
                      for (final e in pages)
                        _AppPage(entryKey: e.key, onOpenDemo: onOpenDemo),
                    ],
                    onDidRemovePage: (_) {},
                  );
                },
              ),
            ),
            Positioned.fill(child: SheetLayer(app: app)),
            Positioned.fill(child: ModalLayer(app: app)),
            Positioned(
              left: 16,
              right: 16,
              top: MediaQuery.paddingOf(context).top + 10,
              child: ToastLayer(app: app),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppPage extends Page<void> {
  _AppPage({required this.entryKey, this.onOpenDemo})
    : super(key: ValueKey(entryKey));

  final int entryKey;
  final VoidCallback? onOpenDemo;

  @override
  Route<void> createRoute(BuildContext context) => _SlideRoute(this);
}

/// 진입: 오른쪽 36%에서 밀려 들어오며 나타남 / 이전 화면: 왼쪽 14%로 밀리며 사라짐 (340ms)
class _SlideRoute extends PageRoute<void> {
  _SlideRoute(_AppPage page) : super(settings: page);

  _AppPage get _page => settings as _AppPage;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 340);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 340);

  @override
  bool get opaque => true;

  @override
  bool get maintainState => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _RouteContent(
      entryKey: _page.entryKey,
      onOpenDemo: _page.onOpenDemo,
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final inT = CurvedAnimation(
      parent: animation,
      curve: appEase,
      reverseCurve: appEase.flipped,
    );
    final outT = CurvedAnimation(
      parent: secondaryAnimation,
      curve: appEase,
      reverseCurve: appEase.flipped,
    );
    return AnimatedBuilder(
      animation: Listenable.merge([inT, outT]),
      child: child,
      builder: (context, child) {
        final enter = 1 - inT.value;
        final leave = outT.value;
        final dx = 0.36 * enter - 0.14 * leave;
        final opacity = (inT.value * (1 - leave)).clamp(0.0, 1.0);
        return FractionalTranslation(
          translation: Offset(dx, 0),
          child: Opacity(opacity: opacity, child: child),
        );
      },
    );
  }
}

/// 라우트 key로 현재 RouteEntry를 찾아 화면을 그린다 (라우트가 사라지는 동안은 마지막 값 유지)
class _RouteContent extends StatefulWidget {
  const _RouteContent({required this.entryKey, this.onOpenDemo});

  final int entryKey;
  final VoidCallback? onOpenDemo;

  @override
  State<_RouteContent> createState() => _RouteContentState();
}

class _RouteContentState extends State<_RouteContent> {
  RouteEntry? _last;
  Widget? _frozen;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    return ListenableBuilder(
      listenable: Listenable.merge([app.router, app]),
      builder: (context, _) {
        var alive = false;
        for (final e in app.router.pages) {
          if (e.key == widget.entryKey) {
            _last = e;
            alive = true;
          }
        }
        // 스택에서 빠진 라우트는 퇴장 애니메이션 동안 마지막 모습 그대로 둔다.
        if (!alive && _frozen != null) return _frozen!;
        final entry = _last;
        if (entry == null) return const ColoredBox(color: AppColors.bg);
        return _frozen = KeyedSubtree(
          key: ValueKey((entry.id, entry.nav)),
          child: buildScreen(app, entry, widget.onOpenDemo),
        );
      },
    );
  }
}

Widget buildScreen(
  CaseController app,
  RouteEntry entry,
  VoidCallback? onOpenDemo,
) {
  return switch (entry.id) {
    ScreenId.home => HomeScreen(entry: entry, onOpenDemo: onOpenDemo),
    ScreenId.transfer => TransferScreen(entry: entry),
    ScreenId.plan => PlanScreen(entry: entry),
    ScreenId.otp => OtpScreen(entry: entry),
    ScreenId.limit => LimitScreen(entry: entry),
    ScreenId.kyc => KycScreen(entry: entry),
    ScreenId.result => ResultScreen(entry: entry),
    ScreenId.support => SupportScreen(entry: entry),
    ScreenId.chat => ChatScreen(entry: entry),
  };
}
