import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/overlays.dart';
import '../../app/router.dart';
import '../../app/screen_data.dart';
import '../../domain/formatters.dart';
import '../../domain/fsm.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets.dart';

const Map<FsmState, (String, String)> _resumeMap = {
  FsmState.planReady: ('진행 중인 해결 계획이 있어요', '남은 절차를 이어서 진행해 주세요'),
  FsmState.waitingUser: ('해결 절차를 진행하던 중이에요', '돌아가면 은행 상태를 다시 확인해요'),
  FsmState.readyToRetry: ('이체 준비가 끝났어요', '원래 이체를 확인하고 직접 승인해 주세요'),
  FsmState.verifying: ('이체 결과를 확인하고 있어요', '결과가 확정될 때까지 다시 보내지 마세요'),
  FsmState.escalated: ('상담 확인이 필요한 건이 있어요', '확인된 내용을 볼 수 있어요'),
  FsmState.resultUncertain: ('결과 확인이 필요한 이체가 있어요', '결과가 확정될 때까지 다시 보내지 마세요'),
};

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.entry, this.onOpenDemo});

  final RouteEntry entry;

  /// 개발자 도구. 홈 상단 </> 버튼으로 연다.
  final VoidCallback? onOpenDemo;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    final data = entry.data is HomeData ? entry.data as HomeData : null;
    final cs = data?.customer;
    final customer = cs?.data;
    final s = app.session;
    final resume = _resumeMap[app.fsm.state];
    final hasCase = resume != null;
    final hideBal = s.hideBalance;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    final notices = <_NoticeData>[
      if (hasCase) _NoticeData(isCase: true, title: resume.$1, desc: resume.$2, onTap: app.openPass),
      if (!s.hideNotice) ...[
        _NoticeData(title: '이체가 막혔다면 AI챗봇에게', desc: '해결패스가 막힌 이유부터 확인해요', onTap: app.goChat),
        _NoticeData(title: '시연용 가상 데이터예요', desc: '실제 은행·계좌와 연결되어 있지 않아요', onTap: app.noop),
      ],
    ];

    Widget balance;
    if (customer == null) {
      balance = Text('잔액을 불러오지 못했어요', style: ts(14, weight: FontWeight.w700, color: AppColors.text2));
    } else if (hideBal) {
      balance = Text('잔액 숨김', style: ts(18, color: AppColors.text3));
    } else {
      balance = Text(
        '${groupDigits(customer.balance)}원',
        style: ts(21, weight: FontWeight.w700, letterSpacing: -0.02),
      );
    }

    return Material(
      color: AppColors.bg,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _HomeTop(hasCase: hasCase, onChat: app.goChat, onNoop: app.noop, onDemo: onOpenDemo),
            Expanded(
              child: CustomPaint(
                painter: const _HomeBandPainter(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
                  children: [
                    if (notices.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Carousel(
                        height: 72,
                        children: [for (final n in notices) _NoticeItem(n, onClose: app.noticeClose)],
                      ),
                    ],
                    const SizedBox(height: 6),
                    _HomeHero(hideBalance: hideBal, onToggle: app.toggleBalance, onNoop: app.noop),
                    if (cs != null && !cs.ok) ...[
                      const SizedBox(height: 12),
                      NoticeBox(
                        body: '일시적으로 은행 시스템에 연결할 수 없어요. 잠시 후 다시 시도해 주세요.',
                        tone: UiTone.warning,
                        icon: AppIcons.alert,
                      ),
                    ],
                    const SizedBox(height: 12),
                    _AccountCard(
                      name: customer?.accountName ?? '우리 주거래 통장',
                      number: customer?.accountNumber ?? '1002-***-******',
                      balance: balance,
                      onDetail: app.showAccountDetail,
                      onTransfer: app.goTransfer,
                      onNoop: app.noop,
                    ),
                    const SizedBox(height: 10),
                    _OutlineButton(label: '전체계좌보기', onTap: app.showAccountDetail),
                    const SizedBox(height: 14),
                    _Promo(onTap: app.goChat),
                    const Fineprint(
                      '본 앱 화면은 경진대회 시연용 프로토타입입니다. 실제 은행과 연결되어 있지 않으며 모든 계좌·금액·거래는 가상 데이터입니다.',
                      top: 18,
                    ),
                  ],
                ),
              ),
            ),
            _BottomNav(bottomInset: bottomInset, onHome: app.goHome, onNoop: app.noop),
          ],
        ),
      ),
    );
  }
}

/// 홈 배경: 위 130px에서 하늘색으로, 520~700px에서 흰색으로 바뀐다 (스크롤과 함께 이동)
class _HomeBandPainter extends CustomPainter {
  const _HomeBandPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, 130),
      Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AppColors.bg, AppColors.homeBand]).createShader(Rect.fromLTWH(0, 0, w, 130)),
    );
    canvas.drawRect(Rect.fromLTWH(0, 130, w, 390), Paint()..color = AppColors.homeBand);
    canvas.drawRect(
      Rect.fromLTWH(0, 520, w, 180),
      Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AppColors.homeBand, Colors.white]).createShader(Rect.fromLTWH(0, 520, w, 180)),
    );
  }

  @override
  bool shouldRepaint(_HomeBandPainter oldDelegate) => false;
}

class _HomeTop extends StatelessWidget {
  const _HomeTop({required this.hasCase, required this.onChat, required this.onNoop, required this.onDemo});

  final bool hasCase;
  final VoidCallback onChat;
  final VoidCallback onNoop;
  final VoidCallback? onDemo;

  @override
  Widget build(BuildContext context) {
    Widget mode(String label, bool on) => GestureDetector(
          onTap: onNoop,
          child: Container(
            height: 28,
            padding: EdgeInsets.symmetric(horizontal: on ? 9 : 7),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(label, style: ts(14, color: on ? AppColors.text : Colors.white)),
          ),
        );

    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.fromLTRB(20, 6, 8, 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(color: AppColors.modeToggleBg, borderRadius: BorderRadius.circular(AppRadius.pill)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [mode('일반홈', true), mode('쉬운', false)]),
          ),
          const Spacer(),
          AppIconButton(icon: AppIcons.wallet, label: '지갑', size: 40, color: AppColors.iconDark, onTap: onNoop),
          _AiButton(hasDot: hasCase, onTap: onChat),
          AppIconButton(icon: AppIcons.bell, label: '알림', size: 40, color: AppColors.iconDark, onTap: onNoop),
          AppIconButton(icon: AppIcons.code, label: '개발자 도구', size: 40, color: AppColors.iconDark, onTap: onDemo),
        ],
      ),
    );
  }
}

/// AI챗봇 버튼: 해결 건이 진행 중이면 빨간 점, 처음 몇 초간 말풍선 안내
class _AiButton extends StatefulWidget {
  const _AiButton({required this.hasDot, required this.onTap});

  final bool hasDot;
  final VoidCallback onTap;

  @override
  State<_AiButton> createState() => _AiButtonState();
}

class _AiButtonState extends State<_AiButton> with SingleTickerProviderStateMixin {
  late final AnimationController _tip = AnimationController(vsync: this, duration: const Duration(milliseconds: 4500));
  final _portal = OverlayPortalController();
  final _link = LayerLink();

  @override
  void initState() {
    super.initState();
    _portal.show();
    _tip
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && _portal.isShowing) _portal.hide();
      })
      ..forward();
  }

  @override
  void dispose() {
    _tip.dispose();
    super.dispose();
  }

  Widget _tipBubble(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: CompositedTransformFollower(
        link: _link,
        targetAnchor: Alignment.bottomCenter,
        followerAnchor: Alignment.topCenter,
        offset: const Offset(0, 2),
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: _tip,
            builder: (context, child) {
              final t = _tip.value;
              final opacity = t < 0.08 ? t / 0.08 : (t < 0.8 ? 1.0 : (1 - (t - 0.8) / 0.2));
              final dy = t < 0.08 ? 4 * (1 - t / 0.08) : 0.0;
              return Opacity(opacity: opacity.clamp(0, 1), child: Transform.translate(offset: Offset(0, dy), child: child));
            },
            child: const _Tip('AI챗봇 해결패스'),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        OverlayPortal(
          controller: _portal,
          overlayChildBuilder: _tipBubble,
          child: CompositedTransformTarget(
            link: _link,
            child: AppIconButton(icon: AppIcons.ai, label: 'AI챗봇 해결패스', size: 40, iconSize: 28, color: AppColors.iconDark, onTap: widget.onTap),
          ),
        ),
        if (widget.hasDot)
          Positioned(
            top: 7,
            right: 5,
            child: IgnorePointer(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF4D4F),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.bg, width: 1.5),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Transform.rotate(
          angle: 0.785398,
          child: Container(width: 8, height: 8, color: const Color(0xFF1F2428)),
        ),
        Transform.translate(
          offset: const Offset(0, -4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xFF1F2428), borderRadius: BorderRadius.circular(8)),
            child: Text(text, softWrap: false, style: ts(11.5, weight: FontWeight.w700, color: Colors.white)),
          ),
        ),
      ],
    );
  }
}

class _NoticeData {
  const _NoticeData({this.isCase = false, required this.title, required this.desc, required this.onTap});

  final bool isCase;
  final String title;
  final String desc;
  final VoidCallback onTap;
}

class _NoticeItem extends StatelessWidget {
  const _NoticeItem(this.n, {required this.onClose});

  final _NoticeData n;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final line = ts(14.5, color: AppColors.text, height: 1.45);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.card)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.card),
                onTap: n.onTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: n.isCase ? AppColors.blueLight : AppColors.noticeIconBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SvgIcon(n.isCase ? AppIcons.spark : AppIcons.bellFill, size: 24, color: n.isCase ? AppColors.blue : AppColors.noticeIcon),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(n.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: line),
                            Text(n.desc, maxLines: 1, overflow: TextOverflow.ellipsis, style: line),
                          ],
                        ),
                      ),
                      if (n.isCase) SvgIcon(AppIcons.chevron, size: 18, color: AppColors.muted),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (!n.isCase)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 4),
              child: AppIconButton(icon: AppIcons.x, label: '알림 닫기', size: 36, iconSize: 15, color: AppColors.muted, onTap: onClose),
            ),
        ],
      ),
    );
  }
}

class _HomeHero extends StatelessWidget {
  const _HomeHero({required this.hideBalance, required this.onToggle, required this.onNoop});

  final bool hideBalance;
  final VoidCallback onToggle;
  final VoidCallback onNoop;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, c) => SvgIcon(AppIcons.homeArt, width: c.maxWidth, height: c.maxWidth / 3, size: c.maxWidth),
        ),
        Transform.translate(
          offset: const Offset(0, -4),
          child: Row(
            children: [
              GestureDetector(
                onTap: onNoop,
                child: _HeroPill(
                  children: [
                    SvgIcon(AppIcons.gear, size: 16, color: AppColors.iconDark),
                    const SizedBox(width: 4),
                    Text('홈계좌설정', style: ts(13.5, color: AppColors.iconDark)),
                  ],
                ),
              ),
              const Spacer(),
              Semantics(
                toggled: hideBalance,
                label: '잔액숨김',
                child: GestureDetector(
                  onTap: onToggle,
                  behavior: HitTestBehavior.opaque,
                  child: _HeroPill(
                    children: [
                      Text('잔액숨김', style: ts(13.5, color: AppColors.iconDark)),
                      const SizedBox(width: 6),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 30,
                        height: 18,
                        padding: const EdgeInsets.all(2.5),
                        alignment: hideBalance ? Alignment.centerRight : Alignment.centerLeft,
                        decoration: BoxDecoration(
                          color: hideBalance ? AppColors.blue : AppColors.toggleOff,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Container(
                          width: 13,
                          height: 13,
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.name,
    required this.number,
    required this.balance,
    required this.onDetail,
    required this.onTransfer,
    required this.onNoop,
  });

  final String name;
  final String number;
  final Widget balance;
  final VoidCallback onDetail;
  final VoidCallback onTransfer;
  final VoidCallback onNoop;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.cardMd),
      child: InkWell(
        onTap: onDetail,
        borderRadius: BorderRadius.circular(AppRadius.cardMd),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: AppColors.avatarBg, shape: BoxShape.circle),
                    child: SvgIcon(AppIcons.wallet, size: 22, color: AppColors.blueDeep),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: ts(16, weight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Flexible(
                              child: Text('우리 $number', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(14, color: AppColors.text3)),
                            ),
                            const SizedBox(width: 4),
                            Semantics(
                              button: true,
                              label: '계좌번호 복사',
                              child: GestureDetector(
                                onTap: onNoop,
                                child: Padding(padding: const EdgeInsets.all(2), child: SvgIcon(AppIcons.copy, size: 15, color: AppColors.text3)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(8, -4),
                    child: AppIconButton(icon: AppIcons.more, label: '계좌 메뉴', size: 30, iconSize: 20, color: AppColors.muted, onTap: onNoop),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(58, 10, 0, 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.tagBg, borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: Text('가상 계좌', style: ts(12, color: AppColors.tagText, height: 1.2)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(58, 14, 0, 0),
                child: Row(
                  children: [
                    Expanded(child: balance),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: onTransfer,
                      child: Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 13),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          border: Border.all(color: AppColors.outline),
                        ),
                        child: Text('이체', style: ts(14, color: AppColors.text)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.button),
        side: const BorderSide(color: AppColors.outline),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.button)),
        child: SizedBox(
          height: 52,
          child: Center(child: Text(label, style: ts(16, color: AppColors.text))),
        ),
      ),
    );
  }
}

class _PromoPage {
  const _PromoPage(this.title, this.desc, this.art);

  final String title;
  final String desc;
  final Widget art;
}

final _promoPages = <_PromoPage>[
  _PromoPage(
    '막힌 이체, 이유부터 확인해요',
    'AI챗봇 해결패스가\n필요한 절차만 안내해요',
    Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.sky, AppColors.blue]),
      ),
      child: SvgIcon(AppIcons.robot, size: 48),
    ),
  ),
  _PromoPage('이체한도가 궁금하다면', '현재 한도와 변경 절차를\n챗봇에게 물어보세요', const _PromoBadge(icon: _PromoIcon.gauge)),
  _PromoPage('결과가 확인될 때까지', '같은 이체를 다시 보내지 않게\n해결패스가 지켜드려요', const _PromoBadge(icon: _PromoIcon.shield)),
];

enum _PromoIcon { gauge, shield }

class _PromoBadge extends StatelessWidget {
  const _PromoBadge({required this.icon});

  final _PromoIcon icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      child: SvgIcon(icon == _PromoIcon.gauge ? AppIcons.gauge : AppIcons.shield, size: 34, color: AppColors.blue),
    );
  }
}

/// 홈 하단 안내 배너: 일정 시간마다 넘어가고, 일시정지할 수 있다
class _Promo extends StatefulWidget {
  const _Promo({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_Promo> createState() => _PromoState();
}

class _PromoState extends State<_Promo> {
  static const _interval = Duration(seconds: 4);

  final _pc = PageController();
  Timer? _timer;
  int _index = 0;
  bool _paused = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pc.dispose();
    super.dispose();
  }

  void _schedule() {
    _timer?.cancel();
    if (_paused || MediaQuery.disableAnimationsOf(context)) return;
    _timer = Timer.periodic(_interval, (_) => _go(_index + 1));
  }

  void _go(int i) {
    if (!_pc.hasClients) return;
    final n = _promoPages.length;
    _pc.animateToPage((i % n + n) % n, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final n = _promoPages.length;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Material(
        color: AppColors.promoBg,
        child: SizedBox(
          height: 132,
          child: Stack(
            children: [
              PageView(
                controller: _pc,
                onPageChanged: (i) => setState(() => _index = i),
                children: [
                  for (final p in _promoPages)
                    InkWell(
                      onTap: widget.onTap,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 22, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(16.5, weight: FontWeight.w700, color: AppColors.promoTitle)),
                                  const SizedBox(height: 6),
                                  Text(p.desc, style: ts(13.5, color: AppColors.promoBody, height: 1.5)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Padding(padding: const EdgeInsets.only(bottom: 14), child: p.art),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              Positioned(
                right: 12,
                bottom: 10,
                child: Row(
                  children: [
                    Container(
                      height: 24,
                      decoration: BoxDecoration(color: AppColors.promoCounter, borderRadius: BorderRadius.circular(AppRadius.pill)),
                      child: Row(
                        children: [
                          _CounterArrow(label: '이전 배너', flip: true, onTap: () => _go(_index - 1)),
                          Text('${_index + 1} / $n', style: ts(12, color: Colors.white, height: 1.2)),
                          _CounterArrow(label: '다음 배너', onTap: () => _go(_index + 1)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Semantics(
                      button: true,
                      label: _paused ? '배너 자동 넘김 재생' : '배너 자동 넘김 일시정지',
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _paused = !_paused);
                          _schedule();
                        },
                        child: Container(
                          width: 24,
                          height: 24,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(color: AppColors.promoCounter, shape: BoxShape.circle),
                          child: _paused
                              ? Padding(padding: const EdgeInsets.only(left: 1.5), child: SvgIcon(AppIcons.play, size: 12, color: Colors.white))
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (var i = 0; i < 2; i++)
                                      Container(width: 2.2, height: 8, margin: const EdgeInsets.symmetric(horizontal: 1), color: Colors.white),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CounterArrow extends StatelessWidget {
  const _CounterArrow({required this.label, required this.onTap, this.flip = false});

  final String label;
  final VoidCallback onTap;
  final bool flip;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Transform.flip(flipX: flip, child: SvgIcon(AppIcons.chevron, size: 12, color: Colors.white)),
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.bottomInset, required this.onHome, required this.onNoop});

  final double bottomInset;
  final VoidCallback onHome;
  final VoidCallback onNoop;

  @override
  Widget build(BuildContext context) {
    Widget item(SvgArt icon, String label, {bool active = false, VoidCallback? onTap}) {
      final color = active ? AppColors.blue : AppColors.iconDark;
      return Expanded(
        child: InkWell(
          onTap: onTap ?? onNoop,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                SvgIcon(icon, size: 26, color: color),
                const SizedBox(height: 4),
                Text(label, style: ts(12, color: color)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.fromLTRB(4, 6, 4, bottomInset > 0 ? bottomInset : 10),
      color: AppColors.bottomNavBg,
      child: Row(
        children: [
          item(AppIcons.bag, '상품'),
          item(AppIcons.pie, '자산·소비'),
          item(AppIcons.homeFill, '홈', active: true, onTap: onHome),
          item(AppIcons.stockBox, '주식'),
          item(AppIcons.gift, '혜택'),
        ],
      ),
    );
  }
}
