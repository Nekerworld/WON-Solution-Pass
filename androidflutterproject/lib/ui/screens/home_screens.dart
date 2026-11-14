/// 홈(계좌·진행 중 건·추천서비스), 상품몰, 입출금/예금/적금 목록, 상품 상세, 전체 메뉴.
/// 실제 우리WON뱅킹 화면 배치를 따르되, 해결패스 기능이 없는 버튼은 눌러도 아무 일이 없다.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/overlays.dart';
import '../../app/router.dart';
import '../../domain/formatters.dart';
import '../../domain/scenario.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../responsive.dart';
import '../theme.dart';
import '../widgets.dart';

/* ==================================================================
 * 진행 중인 건
 * ================================================================== */

const Map<String, String> _joinResume = {
  'CONSENT': '정보 이용 동의를 기다리고 있어요',
  'CHECKING': '가입 조건을 확인하고 있어요',
  'CHECK_FAILED': '은행 기록 확인이 필요해요',
  'CLARIFYING': '답변을 기다리고 있어요',
  'ROUTE_CHECK': '해결 순서를 계산하고 있어요',
  'OPTIONS_READY': '해결 방법을 골라 주세요',
  'TASK_OPEN': '업무 화면을 진행하던 중이에요',
  'RECHECKING': '은행 기록을 다시 확인하고 있어요',
  'REMAINING': '남은 조건을 이어서 해결해요',
  'INVESTIGATING': '업무 결과 확인이 필요해요',
  'READY_TO_APPLY': '가입 준비 완료 · 승인이 필요해요',
  'APPLYING': '가입 요청 중이에요',
  'VERIFYING': '가입 결과를 확인하고 있어요',
  'RESULT_UNCERTAIN': '가입 결과 확인이 필요해요 · 다시 신청하지 마세요',
  'COMPLETED': '가입이 완료됐어요',
  'FAILED': '가입이 처리되지 않았어요',
  'ESCALATED': '상담 연결이 필요해요',
};

const Map<String, String> _directResume = {
  'D_START': '가입을 시작하지 않았어요',
  'D_STEP': '가입 정보를 입력하던 중이에요',
  'D_NOTICE': '부족한 조건이 있어요',
  'D_SELF_FIX': '부족한 조건을 해결한 뒤 처음부터 다시 해요',
  'D_APPROVE': '가입 신청 전이에요',
  'D_VERIFYING': '가입 결과 확인 중',
  'D_UNCERTAIN': '가입 결과 확인이 필요해요',
  'D_DONE': '가입이 완료됐어요',
  'D_FAILED': '가입이 처리되지 않았어요',
};

const Map<String, String> _assetResume = {
  'CONSENT': '정보 이용 동의를 기다리고 있어요',
  'GOAL': '상담 목표를 알려 주세요',
  'ASKING': '질문에 답해 주세요',
  'REVIEW': '제안을 검토해 주세요',
  'NEXT_ACTION': '다음 행동을 골라 주세요',
  'EXPLORE': '상품을 둘러보는 중',
  'HOLD': '제안이 보류됐어요',
  'RECONSULT': '정보를 다시 확인하는 중',
  'HANDOFF': '상담 연결 중',
};

class _ResumeCard {
  const _ResumeCard(this.tag, this.title, this.desc, this.warning, this.onTap);
  final String tag;
  final String title;
  final String desc;
  final bool warning;
  final VoidCallback onTap;
}

List<_ResumeCard> _resumeCards(AppController app) {
  final s = app.session;
  final out = <_ResumeCard>[];
  final js = app.joinFsm.state;
  if (js != 'IDLE' && s.join != null) {
    out.add(_ResumeCard(
      'AI 가입 지원',
      getProduct(s.join!.productId)?.name ?? '',
      _joinResume[js] ?? js,
      const ['RESULT_UNCERTAIN', 'INVESTIGATING', 'CHECK_FAILED', 'ESCALATED', 'FAILED'].contains(js),
      app.join.open,
    ));
  }
  final ds = app.directFsm.state;
  if (ds != 'IDLE' && s.direct != null) {
    out.add(_ResumeCard('직접 가입', getProduct(s.direct!.productId)?.name ?? '', _directResume[ds] ?? ds, false, app.direct.open));
  }
  final as = app.assetFsm.state;
  if (!const ['IDLE', 'CLOSED', 'TO_JOIN'].contains(as) && s.asset != null) {
    out.add(_ResumeCard('AI 자산관리', '자산관리 상담', _assetResume[as] ?? '분석하고 있어요', false, app.asset.open));
  }
  return out;
}

/* ==================================================================
 * 홈
 * ================================================================== */

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.entry, this.onOpenDemo});

  final RouteEntry entry;

  /// 시연 제어 화면. 홈 상단 </> 버튼으로 연다.
  final VoidCallback? onOpenDemo;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    final data = entry.data is HomeData ? entry.data as HomeData : null;
    final r = data?.summary;
    final s = app.session;
    final hide = s.ui.hideBalance;
    final side = wideInsetOf(context);
    final cards = _resumeCards(app);

    Widget bal(String amount, String unit) => hide
        ? Text('잔액숨김', style: ts(17, color: AppColors.text3))
        : Text.rich(TextSpan(children: [
            TextSpan(text: amount, style: ts(21, weight: FontWeight.w700, letterSpacing: -0.02)),
            TextSpan(text: unit, style: ts(15, color: AppColors.text2)),
          ]));

    final accts = <Widget>[];
    if (r == null || !r.ok) {
      accts.add(const _AcctBox(
        child: NoticeBox(body: '계좌 정보를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.', tone: UiTone.warning),
      ));
    } else if (!r.data!.hasDepositAccount) {
      accts.add(_AcctBox(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _AcctHead(name: '우리은행 계좌가 아직 없어요', sub: '처음 거래하시는 고객님'),
            const SizedBox(height: 12),
            Text('상품에 가입하려면 입출금 계좌가 필요해요. 가입 지원에서 함께 만들 수 있어요.', style: ts(13.5, color: AppColors.text2, height: 1.5)),
          ],
        ),
      ));
    } else {
      final d = r.data!;
      accts.add(_AccountCard(name: d.account!.name, sub: '우리 ${d.account!.number}', copy: true, balance: bal('0', ' 원'), transfer: true));
      if (d.fxAccount != null) {
        accts.add(_AccountCard(name: d.fxAccount!.name, sub: '우리 ${d.fxAccount!.number}', copy: true, tag: '외화', balance: bal('0.00', ' USD'), transfer: true));
      }
      for (final sv in d.savings) {
        final p = getProduct(sv.productId);
        if (p == null) continue;
        final t = sv.terms;
        final sub = t?.monthly != null
            ? '매월 ${formatMan(t!.monthly)}${t.months != null ? ' · ${t.months}개월' : ''}'
            : (t?.market != null ? '${t!.market} 주식 거래' : '가입 완료');
        accts.add(_AccountCard(name: p.name, sub: sub, tag: p.type, balance: bal('0', p.isBrokerage ? ' 원 평가금액' : ' 원')));
      }
    }

    return Material(
      color: AppColors.bg,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _HomeTop(onAi: app.asset.startAction, onMenu: () => app.goMenu(), onDemo: onOpenDemo),
            Expanded(
              child: CustomPaint(
                painter: const _HomeBandPainter(),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(16 + side, 2, 16 + side, 24),
                  children: [
                    if (!s.ui.disclaimerClosed) ...[
                      const SizedBox(height: 6),
                      _Disclaimer(onClose: app.closeDisclaimer),
                    ],
                    const SizedBox(height: 6),
                    _HomeHero(hideBalance: hide, onToggle: app.toggleBalance),
                    const SizedBox(height: 12),
                    for (final a in accts) Padding(padding: const EdgeInsets.only(bottom: 10), child: a),
                    if (cards.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                        child: Text('진행 중인 업무', style: ts(15, weight: FontWeight.w700)),
                      ),
                      for (final c in cards) Padding(padding: const EdgeInsets.only(bottom: 8), child: _ResumeTile(c)),
                      const SizedBox(height: 4),
                    ],
                    const _OutlineButton(label: '전체계좌보기'),
                    const SizedBox(height: 14),
                    _AdBanner(
                      title: '해외주식, 처음이라도 괜찮아요\n계좌 개설부터 AI가 함께해요',
                      sub: 'WON 해외주식 계좌 · 시연용 배너',
                      pager: '1 / 4',
                      onTap: () => app.openProduct('OVERSEAS_STOCK'),
                    ),
                    const _H3('추천서비스'),
                    SizedBox(
                      height: 222,
                      child: OverflowBox(
                        maxWidth: MediaQuery.sizeOf(context).width,
                        minWidth: MediaQuery.sizeOf(context).width,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: EdgeInsets.symmetric(horizontal: 16 + side),
                          children: [
                            _SvcPanel(color: const Color(0xFFFFF1F4), items: [
                              _SvcItem(AppIcons.target, const Color(0xFF2488F3), 'AI 자산관리 상담', '모을 돈과 투자할 돈을 함께 정해요', app.asset.startAction),
                              _SvcItem(AppIcons.product, const Color(0xFF7B5CFF), '상품 가입', 'AI와 함께 또는 직접 가입해요', app.goProducts),
                              _SvcItem(AppIcons.wallet, const Color(0xFF20C4F4), '우리WON지갑', '모바일 신분증 등 생활 서비스', null),
                            ]),
                            const SizedBox(width: 10),
                            _SvcPanel(color: const Color(0xFFEEF5FF), items: [
                              _SvcItem(AppIcons.phone, const Color(0xFF2488F3), '우리WON모바일', '은행이 만든 알뜰폰 통신', null),
                              _SvcItem(AppIcons.globe, const Color(0xFF11A3A3), '환전주머니', '여행 환전을 손쉽게 준비해요', null),
                              _SvcItem(AppIcons.coin, const Color(0xFF20C4F4), 'ATM 출금', '카드 없이 휴대폰으로 출금', null),
                            ]),
                          ],
                        ),
                      ),
                    ),
                    const _H3('우리금융그룹 서비스'),
                    SizedBox(
                      height: 128,
                      child: OverflowBox(
                        maxWidth: MediaQuery.sizeOf(context).width,
                        minWidth: MediaQuery.sizeOf(context).width,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: EdgeInsets.symmetric(horizontal: 16 + side),
                          children: [
                            for (final g in [
                              ('보험', const Color(0xFF7B5CFF), '나를 지켜주는\n든든한 보장', AppIcons.shield),
                              ('캐피탈', const Color(0xFF11A37F), '내 자동차\n대출 한도', AppIcons.route),
                              ('증권', const Color(0xFF2488F3), '새로운\n투자 정보', AppIcons.stock),
                              ('카드', const Color(0xFFE2537A), '혜택 많은\n카드 찾기', AppIcons.wallet),
                            ])
                              Container(
                                width: 128,
                                margin: const EdgeInsets.only(right: 10),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.card)),
                                child: Stack(
                                  children: [
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(g.$1, style: ts(14, weight: FontWeight.w700, color: g.$2)),
                                        const SizedBox(height: 4),
                                        Text(g.$3, style: ts(12.5, color: AppColors.text2, height: 1.45)),
                                      ],
                                    ),
                                    Positioned(right: 0, bottom: 0, child: SvgIcon(g.$4, size: 26, color: g.$2)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          Text('공지', style: ts(13, weight: FontWeight.w700, color: AppColors.blue)),
                          const SizedBox(width: 10),
                          Expanded(child: Text('이 화면은 경진대회 시연용 모의 화면이에요', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13, color: AppColors.text2))),
                          SvgIcon(AppIcons.chevron, size: 16, color: AppColors.muted),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const AppBottomNav(active: 'home'),
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
  const _HomeTop({required this.onAi, required this.onMenu, required this.onDemo});

  final VoidCallback onAi;
  final VoidCallback onMenu;
  final VoidCallback? onDemo;

  @override
  Widget build(BuildContext context) {
    Widget mode(String label, bool on) => Container(
          height: 28,
          padding: EdgeInsets.symmetric(horizontal: on ? 9 : 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: on ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(AppRadius.pill)),
          child: Text(label, style: ts(14, color: on ? AppColors.text : Colors.white)),
        );
    final side = wideInsetOf(context);
    return Container(
      color: AppColors.bg,
      padding: EdgeInsets.fromLTRB(20 + side, 6, 8 + side, 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(color: AppColors.modeToggleBg, borderRadius: BorderRadius.circular(AppRadius.pill)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [mode('일반홈', true), mode('쉬운', false)]),
          ),
          const Spacer(),
          AppIconButton(icon: AppIcons.wallet, label: '지갑', size: 40, color: AppColors.iconDark, onTap: () {}),
          AppIconButton(icon: AppIcons.ai, label: 'AI 자산관리 상담', size: 40, iconSize: 28, color: AppColors.iconDark, onTap: onAi),
          AppIconButton(icon: AppIcons.bell, label: '알림', size: 40, color: AppColors.iconDark, onTap: () {}),
          AppIconButton(icon: AppIcons.menu, label: '전체 메뉴', size: 40, color: AppColors.iconDark, onTap: onMenu),
          if (onDemo != null) AppIconButton(icon: AppIcons.code, label: '시연 제어', size: 40, color: AppColors.iconDark, onTap: onDemo),
        ],
      ),
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.card)),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.noticeIconBg, borderRadius: BorderRadius.circular(12)),
            child: SvgIcon(AppIcons.bellFill, size: 22, color: AppColors.noticeIcon),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text('이 앱은 경진대회 시연용 목업이에요.\n상품·조건·금액은 모두 가상의 값이에요.', style: ts(13.5, height: 1.5))),
          AppIconButton(icon: AppIcons.x, label: '안내 닫기', size: 36, iconSize: 15, color: AppColors.muted, onTap: onClose),
        ],
      ),
    );
  }
}

class _HomeHero extends StatelessWidget {
  const _HomeHero({required this.hideBalance, required this.onToggle});

  final bool hideBalance;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final w = math.min(c.maxWidth, 450.0);
            return SvgIcon(AppIcons.homeArt, width: w, height: w / 3, size: w);
          },
        ),
        Transform.translate(
          offset: const Offset(0, -4),
          child: Row(
            children: [
              _HeroPill(children: [
                SvgIcon(AppIcons.gear, size: 16, color: AppColors.iconDark),
                const SizedBox(width: 4),
                Text('홈계좌설정', style: ts(13.5, color: AppColors.iconDark)),
              ]),
              const Spacer(),
              Semantics(
                toggled: hideBalance,
                label: '잔액숨김',
                child: GestureDetector(
                  onTap: onToggle,
                  behavior: HitTestBehavior.opaque,
                  child: _HeroPill(children: [
                    Text('잔액숨김', style: ts(13.5, color: AppColors.iconDark)),
                    const SizedBox(width: 6),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 30,
                      height: 18,
                      padding: const EdgeInsets.all(2.5),
                      alignment: hideBalance ? Alignment.centerRight : Alignment.centerLeft,
                      decoration: BoxDecoration(color: hideBalance ? AppColors.blue : AppColors.toggleOff, borderRadius: BorderRadius.circular(AppRadius.pill)),
                      child: Container(width: 13, height: 13, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                    ),
                  ]),
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

class _AcctBox extends StatelessWidget {
  const _AcctBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.cardMd)),
      child: child,
    );
  }
}

class _AcctHead extends StatelessWidget {
  const _AcctHead({required this.name, required this.sub, this.copy = false, this.tag, this.more = false});

  final String name;
  final String sub;
  final bool copy;
  final String? tag;
  final bool more;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SvgIcon(AppIcons.bankMark, size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: ts(15.5, weight: FontWeight.w700)),
              const SizedBox(height: 3),
              Row(
                children: [
                  Flexible(child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13.5, color: AppColors.text3))),
                  if (copy) ...[const SizedBox(width: 4), SvgIcon(AppIcons.copy, size: 14, color: AppColors.text3)],
                ],
              ),
              if (tag != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.tagBg, borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: Text(tag!, style: ts(11.5, color: AppColors.tagText, height: 1.2)),
                ),
              ],
            ],
          ),
        ),
        if (more) SvgIcon(AppIcons.more, size: 20, color: AppColors.muted),
      ],
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.name, required this.sub, required this.balance, this.copy = false, this.tag, this.transfer = false});

  final String name;
  final String sub;
  final Widget balance;
  final bool copy;
  final String? tag;
  final bool transfer;

  @override
  Widget build(BuildContext context) {
    return _AcctBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AcctHead(name: name, sub: sub, copy: copy, tag: tag, more: true),
          Padding(
            padding: const EdgeInsets.fromLTRB(52, 12, 0, 0),
            child: Row(
              children: [
                Expanded(child: balance),
                if (transfer)
                  Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 13),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(color: AppColors.outline),
                    ),
                    child: Text('이체', style: ts(14)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResumeTile extends StatelessWidget {
  const _ResumeTile(this.c);

  final _ResumeCard c;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: c.warning ? AppColors.warningBg : Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: c.onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.tag, style: ts(11.5, weight: FontWeight.w700, color: c.warning ? AppColors.warningBadge : AppColors.blue)),
                    const SizedBox(height: 2),
                    Text(c.title, style: ts(15, weight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(c.desc, style: ts(13, color: c.warning ? AppColors.warningText : AppColors.text2, height: 1.4)),
                  ],
                ),
              ),
              SvgIcon(AppIcons.chevron, size: 18, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.button),
        border: Border.all(color: AppColors.outline),
      ),
      child: Text(label, style: ts(16)),
    );
  }
}

class _AdBanner extends StatelessWidget {
  const _AdBanner({required this.title, required this.sub, required this.pager, required this.onTap});

  final String title;
  final String sub;
  final String pager;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.promoBg,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: SizedBox(
          height: 124,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(title, style: ts(15.5, weight: FontWeight.w700, color: AppColors.promoTitle, height: 1.45)),
                          const SizedBox(height: 6),
                          Text(sub, style: ts(12.5, color: AppColors.promoBody)),
                        ],
                      ),
                    ),
                    Container(
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: SvgIcon(AppIcons.globe, size: 40, color: AppColors.blue),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 12,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.promoCounter, borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: Text('‹ $pager ›', style: ts(11.5, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _H3 extends StatelessWidget {
  const _H3(this.text, {this.big = false});

  final String text;
  final bool big;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
        child: Text(text, style: ts(big ? 19 : 17, weight: FontWeight.w700, letterSpacing: -0.02)),
      );
}

class _SvcItem {
  const _SvcItem(this.icon, this.color, this.title, this.desc, this.onTap);
  final SvgArt icon;
  final Color color;
  final String title;
  final String desc;
  final VoidCallback? onTap;
}

class _SvcPanel extends StatelessWidget {
  const _SvcPanel({required this.color, required this.items});

  final Color color;
  final List<_SvcItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 290,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppRadius.cardMd)),
      child: Column(
        children: [
          for (final it in items)
            InkWell(
              onTap: it.onTap ?? () {},
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                      child: SvgIcon(it.icon, size: 22, color: it.color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(it.title, style: ts(14.5, weight: FontWeight.w700)),
                          Text(it.desc, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12.5, color: AppColors.text2)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 하단 탭: 상품 / 자산·소비 / 홈 / 주식 / 혜택
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.active});

  final String active;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    Widget item(SvgArt icon, String label, String id, VoidCallback? onTap) {
      final color = active == id ? AppColors.blue : AppColors.iconDark;
      return Expanded(
        child: InkWell(
          onTap: onTap ?? () {},
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
      child: MaxWidth(
        child: Row(
          children: [
            item(AppIcons.bag, '상품', 'products', active == 'products' ? null : app.goProducts),
            item(AppIcons.pie, '자산·소비', 'asset', app.asset.startAction),
            item(AppIcons.homeFill, '홈', 'home', active == 'home' ? null : app.goHome),
            item(AppIcons.stockBox, '주식', 'stock', null),
            item(AppIcons.gift, '혜택', 'gift', null),
          ],
        ),
      ),
    );
  }
}

/* ==================================================================
 * 상품몰
 * ================================================================== */

final List<(String, bool, Color, SvgArt)> _categories = [
  ('입출금/예적금', true, const Color(0xFFFF8FA3), AppIcons.coin),
  ('청약', false, const Color(0xFF9B7BFF), AppIcons.homeFill),
  ('대출', false, const Color(0xFF4B8DF8), AppIcons.doc),
  ('펀드', false, const Color(0xFF7C6CF2), AppIcons.stock),
  ('퇴직연금', false, const Color(0xFFB0805C), AppIcons.clock),
  ('신탁', false, const Color(0xFF6A62E6), AppIcons.list),
  ('ISA', false, const Color(0xFF3D8BF2), AppIcons.pie),
  ('외환', false, const Color(0xFF2E7FF0), AppIcons.globe),
  ('개인사업자', false, const Color(0xFF29A3C2), AppIcons.product),
  ('보험', false, const Color(0xFF2EBD85), AppIcons.shield),
  ('골드/실버', false, const Color(0xFFE8A92C), AppIcons.gift),
  ('카드', false, const Color(0xFFF06B9B), AppIcons.wallet),
];

class ProductsScreen extends StatelessWidget {
  const ProductsScreen({super.key, required this.entry});

  final RouteEntry entry;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    final ongoing = (app.joinFsm.state != 'IDLE' ? 1 : 0) + (app.directFsm.state != 'IDLE' ? 1 : 0);
    final viewed = app.session.ui.lastProduct != null ? 1 : 0;
    final side = wideInsetOf(context);

    Widget row(SvgArt icon, String title, String sub, {Color? bg, Color? fg, VoidCallback? onTap}) => InkWell(
          onTap: onTap ?? () {},
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: bg ?? AppColors.bg, borderRadius: BorderRadius.circular(12)),
                  child: SvgIcon(icon, size: 24, color: fg ?? AppColors.blue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: ts(14.5, weight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(sub, style: ts(12.5, color: AppColors.text3)),
                    ],
                  ),
                ),
                SvgIcon(AppIcons.chevron, size: 16, color: AppColors.muted),
              ],
            ),
          ),
        );

    return Material(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              height: 56,
              padding: EdgeInsets.fromLTRB(20 + side, 0, 8 + side, 0),
              child: Row(
                children: [
                  Text('상품몰', style: ts(20, weight: FontWeight.w700, letterSpacing: -0.03)),
                  const Spacer(),
                  AppIconButton(icon: AppIcons.ai, label: 'AI 자산관리 상담', size: 40, iconSize: 28, color: AppColors.iconDark, onTap: app.asset.startAction),
                  AppIconButton(icon: AppIcons.cart, label: '장바구니', size: 40, color: AppColors.iconDark, onTap: () {}),
                  AppIconButton(icon: AppIcons.menu, label: '전체 메뉴', size: 40, color: AppColors.iconDark, onTap: () => app.goMenu()),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(20 + side, 4, 20 + side, 24),
                children: [
                  _AdBanner(
                    title: '처음 거래 고객도 해외주식까지\n가입 순서는 AI가 정리해 드려요',
                    sub: 'WON 해외주식 계좌 · 시연용 배너',
                    pager: '2 / 5',
                    onTap: () => app.openProduct('OVERSEAS_STOCK'),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(AppRadius.card)),
                    child: Row(
                      children: [
                        for (final x in [('이어서 가입하기', ongoing), ('최근 본 상품', viewed), ('영업점 추천 상품', 0)])
                          Expanded(
                            child: Column(
                              children: [
                                Text(x.$1, style: ts(12, color: AppColors.text2)),
                                const SizedBox(height: 4),
                                Text.rich(TextSpan(children: [
                                  TextSpan(text: '${x.$2}', style: ts(17, weight: FontWeight.w700)),
                                  TextSpan(text: '개', style: ts(12, color: AppColors.text2)),
                                ])),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  GridView.count(
                    crossAxisCount: 4,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    childAspectRatio: 0.95,
                    children: [
                      for (final c in _categories)
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: c.$2 ? app.goProductList : () {},
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(color: c.$3.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                                child: SvgIcon(c.$4, size: 24, color: c.$3),
                              ),
                              const SizedBox(height: 6),
                              Text(c.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12, color: AppColors.text)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  row(AppIcons.route, '우리금융그룹 상품', '보험 · 증권 · 캐피탈 · 저축은행'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: const Color(0xFFF4F1FF), borderRadius: BorderRadius.circular(AppRadius.card)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(children: [
                            const TextSpan(text: '전문 '),
                            TextSpan(text: 'AI상담원', style: weightStyle(FontWeight.w700).copyWith(color: const Color(0xFF7B5CFF))),
                            const TextSpan(text: '에게 물어보세요'),
                          ]),
                          style: ts(15, weight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final x in ['예적금상담', '대출상담', '청약상담'])
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.pill)),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  SvgIcon(AppIcons.spark, size: 12, color: const Color(0xFF7B5CFF)),
                                  const SizedBox(width: 4),
                                  Text(x, style: ts(12.5)),
                                ]),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const _H3('WON PICK 추천', big: true),
                  _Pick(color: const Color(0xFFE8F1FE), fg: AppColors.blue, title: '해외주식, 처음이라면?', sub: 'WON 해외주식 계좌', icon: AppIcons.stock, onTap: () => app.openProduct('OVERSEAS_STOCK')),
                  _Pick(color: const Color(0xFFF1EDFF), fg: const Color(0xFF7B5CFF), title: '외국 갈 땐 든든하게 외화 챙기기', sub: '환전주머니', icon: AppIcons.globe),
                  _Pick(color: const Color(0xFFE6F8FE), fg: AppColors.sky, title: '은행이 만든 알뜰한 요금제', sub: '우리WON모바일', icon: AppIcons.phone),
                  const SizedBox(height: 8),
                  row(AppIcons.shield, '금융 소외 없이 든든한 포용금융', '우리포용금융'),
                  row(AppIcons.wallet, '공항라운지 & 여행 카드 모음집', '우리카드'),
                  row(AppIcons.route, '자동차로 할 수 있는 금융', '우리금융캐피탈'),
                ],
              ),
            ),
            const AppBottomNav(active: 'products'),
          ],
        ),
      ),
    );
  }
}

class _Pick extends StatelessWidget {
  const _Pick({required this.color, required this.fg, required this.title, required this.sub, required this.icon, this.onTap});

  final Color color;
  final Color fg;
  final String title;
  final String sub;
  final SvgArt icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          onTap: onTap ?? () {},
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: ts(15, weight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(sub, style: ts(12.5, color: AppColors.text2)),
                    ],
                  ),
                ),
                SvgIcon(icon, size: 30, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* ==================================================================
 * 입출금/예금/적금 목록
 * ================================================================== */

double _rateNum(ProductDef p) => double.tryParse(p.rate.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;

String _periodText(ProductDef p) {
  if (p.periods.isEmpty) return '';
  return '(${p.periods.length > 1 ? '${p.periods.first}~${p.periods.last}' : '${p.periods.first}'}개월) ';
}

class _ListItem {
  const _ListItem({this.id, this.name, this.desc, this.rate});
  final String? id;
  final String? name;
  final String? desc;
  final String? rate;
}

const List<(String, String, List<_ListItem>)> _listGroups = [
  (
    'saving',
    '적금',
    [
      _ListItem(id: 'SAVINGS_GOAL'),
      _ListItem(id: 'FREE_SAVINGS'),
      _ListItem(name: 'WON 주거래 우대적금', desc: '급여·자동이체 실적에 따라 우대금리를 더해 드려요', rate: '(12개월) 연 2.9% ~ 3.4%'),
      _ListItem(name: 'WON 여행 적금', desc: '여행 날짜에 맞춰 모으는 자유적립 적금', rate: '(6개월) 연 2.7%'),
    ]
  ),
  (
    'deposit',
    '예금',
    [
      _ListItem(name: 'WON 첫거래 정기예금', desc: '처음 거래하는 고객을 위한 정기예금', rate: '(12개월) 연 2.6% ~ 3.0%'),
      _ListItem(name: 'WON 회전 정기예금', desc: '정해진 주기마다 금리가 바뀌는 정기예금', rate: '(12~36개월) 연 2.5%'),
    ]
  ),
  (
    'demand',
    '입출금',
    [
      _ListItem(id: 'PARKING'),
      _ListItem(name: 'WON 생활비 통장', desc: '수수료 면제 혜택이 있는 입출금 통장', rate: '연 0.1%'),
    ]
  ),
];

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key, required this.entry});

  final RouteEntry entry;

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  final Map<String, GlobalKey> _keys = {for (final g in _listGroups) g.$1: GlobalKey()};
  String _tab = 'saving';

  void _goTab(String id) {
    setState(() => _tab = id);
    final ctx = _keys[id]!.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), curve: appEase);
  }

  Widget _row(AppController app, _ListItem x) {
    final p = x.id != null ? getProduct(x.id) : null;
    final rate = p != null ? '${_periodText(p)}${p.rate}' : x.rate!;
    final m = RegExp(r'^(\(.+?\))\s*(.*)$').firstMatch(rate);
    return InkWell(
      onTap: p != null ? () => app.openProduct(p.id) : () {},
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p?.name ?? x.name!, style: ts(15, weight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(p?.summary ?? x.desc!, style: ts(13, color: AppColors.text2, height: 1.45)),
            const SizedBox(height: 5),
            Text.rich(TextSpan(children: [
              if (m != null) TextSpan(text: '${m.group(1)} ', style: ts(12, color: AppColors.text3)),
              TextSpan(text: m != null ? m.group(2) : rate, style: ts(14, weight: FontWeight.w700, color: AppColors.blue)),
            ])),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    final g = getProduct('SAVINGS_GOAL')!;
    return ScreenFrame(
      white: true,
      appBar: WspAppBar(
        title: '입출금/예금/적금',
        onBack: app.back,
        right: AppIconButton(icon: AppIcons.cart, label: '장바구니', onTap: () {}),
      ),
      children: [
        const SizedBox(height: 8),
        Text('저축의 시작은 안전하고 꾸준하게', style: ts(20, weight: FontWeight.w700, letterSpacing: -0.03)),
        const SizedBox(height: 4),
        Text('목돈 마련부터 생활비 관리까지 한눈에 비교해 보세요', style: ts(13.5, color: AppColors.text2)),
        const SizedBox(height: 16),
        Material(
          color: const Color(0xFFEEF5FF),
          borderRadius: BorderRadius.circular(AppRadius.cardMd),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.cardMd),
            onTap: () => app.openProduct('SAVINGS_GOAL'),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('매달 정해진 금액으로 목돈 만들기', style: ts(12.5, color: AppColors.text2)),
                        const SizedBox(height: 4),
                        Text(g.name, style: ts(18, weight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text('${g.rate}\n${g.periods.join('·')}개월 기준', style: ts(13, color: AppColors.blue, height: 1.5)),
                      ],
                    ),
                  ),
                  SvgIcon(AppIcons.coin, size: 54, color: AppColors.blue),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(child: Text('‹  1 / 3  ›', style: ts(12, color: AppColors.text3))),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final x in _listGroups)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: AnswerChip(x.$2, selected: _tab == x.$1, onTap: () => _goTab(x.$1)),
              ),
            const Spacer(),
            Text('조회기준', style: ts(12.5, color: AppColors.text2)),
            SvgIcon(AppIcons.down, size: 14, color: AppColors.text2),
          ],
        ),
        for (final x in _listGroups)
          Column(
            key: _keys[x.$1],
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: const EdgeInsets.only(top: 22, bottom: 2), child: Text(x.$2, style: ts(17, weight: FontWeight.w700))),
              for (final it in x.$3) _row(app, it),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(child: Text('더보기 ⌄', style: ts(13, color: AppColors.text2))),
              ),
            ],
          ),
        Padding(padding: const EdgeInsets.only(top: 12, bottom: 2), child: Text('기타서비스', style: ts(17, weight: FontWeight.w700))),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('상품 금리조회', style: ts(15, weight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text('예적금 상품 금리를 한눈에 비교해 보세요', style: ts(13, color: AppColors.text2)),
            ],
          ),
        ),
        const Fineprint('목록의 상품명과 금리는 시연용 가상 값이에요.'),
      ],
    );
  }
}

/* ==================================================================
 * 상품 상세
 * ================================================================== */

int savingsInterest(int monthly, int months, double rate) => (monthly * (rate / 100) * (months * (months + 1)) / 2 / 12).round();

class ProductScreen extends StatefulWidget {
  const ProductScreen({super.key, required this.entry});

  final RouteEntry entry;

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  int? _monthly;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    final p = getProduct(widget.entry.params['productId'] as String?);
    if (p == null) {
      return QueryErrorView(title: '상품', error: null, onBack: app.back, onHome: app.goHome, onRetry: app.back);
    }
    final s = app.session;
    if (s.ui.lastProduct != p.id) {
      s.ui.lastProduct = p.id;
      app.save();
    }
    final fromAsset = widget.entry.params['from'] == 'asset';
    final ctx = fromAsset ? s.asset?.handoffTerms : null;
    final joinActive = app.joinFsm.state != 'IDLE' && s.join?.productId == p.id;
    final directActive = app.directFsm.state != 'IDLE' && s.direct?.productId == p.id;
    final isSavings = p.maxMonthly > 0;
    final rate = _rateNum(p);
    final strong = ts(23, weight: FontWeight.w700, color: AppColors.blue, letterSpacing: -0.03);
    final titleStyle = ts(23, weight: FontWeight.w700, height: 1.4, letterSpacing: -0.03);

    Widget chip(String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(AppRadius.pill)),
          child: Text(text, style: ts(12.5, color: AppColors.text2)),
        );

    late final InlineSpan title;
    late final List<Widget> chips;
    late final Widget box;
    Widget? slider;
    if (isSavings) {
      final months = ctx?.months != null && p.periods.contains(ctx!.months) ? ctx.months! : p.periods.first;
      const step = 10000;
      final max = math.min(p.maxMonthly, 1000000);
      final initial = math.max(p.minMonthly, math.min(max, ctx?.monthly != null ? (ctx!.monthly! / step).round() * step : 500000));
      final monthly = _monthly ?? initial;
      title = TextSpan(children: [
        TextSpan(text: '${p.name}\n총 '),
        TextSpan(text: groupDigits(savingsInterest(monthly, months, rate)), style: strong),
        const TextSpan(text: '원의\n이자를 드려요'),
      ]);
      chips = [chip('원금 · ${groupDigits(monthly * months)}원'), chip('예상금리 · ${p.rate}(세전)')];
      box = Text.rich(TextSpan(children: [
        const TextSpan(text: '가입기간 '),
        bold('$months개월'),
        const TextSpan(text: ' 상품이에요'),
        if (p.periods.length > 1) TextSpan(text: '\n${p.periods.join('·')}개월 중 가입할 때 고를 수 있어요', style: ts(12.5, color: AppColors.text3)),
      ]));
      slider = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 18),
          Text('한달에 ${formatMan(monthly)}', style: ts(16, weight: FontWeight.w700)),
          Slider(
            value: monthly.toDouble(),
            min: p.minMonthly.toDouble(),
            max: max.toDouble(),
            divisions: math.max(1, (max - p.minMonthly) ~/ step),
            label: formatMan(monthly),
            onChanged: (v) => setState(() => _monthly = (v / step).round() * step),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text(formatMan(p.minMonthly), style: ts(12, color: AppColors.text3)), Text(formatMan(max), style: ts(12, color: AppColors.text3))],
          ),
          const SizedBox(height: 6),
          Text('조건 직접 입력하기', style: ts(13, color: AppColors.text2).copyWith(decoration: TextDecoration.underline)),
        ],
      );
    } else if (p.isBrokerage) {
      title = TextSpan(children: [
        TextSpan(text: '${p.name}\n'),
        TextSpan(text: p.markets.join('·'), style: strong),
        const TextSpan(text: ' 주식을\n한 계좌로 거래해요'),
      ]);
      chips = [chip('${p.rateLabel} · ${p.rateValue}'), chip('거래 시장 · ${p.markets.length}곳')];
      box = Text.rich(TextSpan(children: [
        bold('원화·외화 계좌'),
        const TextSpan(text: '를 연결해서 쓰는 상품이에요'),
        TextSpan(text: '\n투자 상품이라 원금 손실이 날 수 있어요', style: ts(12.5, color: AppColors.text3)),
      ]));
    } else {
      title = TextSpan(children: [
        TextSpan(text: '${p.name}\n언제든 꺼내 쓰는\n'),
        TextSpan(text: p.rate, style: strong),
        const TextSpan(text: ' 통장이에요'),
      ]);
      chips = [chip('금리 · ${p.rate}(세전)')];
      box = Text.rich(TextSpan(children: [bold('가입기간 없이'), const TextSpan(text: ' 자유롭게 넣고 빼요')]));
    }

    final rows = <KvRow>[
      KvRow.text('상품 유형', p.type),
      KvRow.text(p.rateLabel ?? '금리', p.rateValue ?? p.rate),
      if (p.periods.isNotEmpty) KvRow.text('가입 기간', p.periods.map((m) => '$m개월').join(' · ')),
      if (p.maxMonthly > 0) KvRow.text('월 납입', '${formatMan(p.minMonthly)} ~ ${formatMan(p.maxMonthly)}'),
      if (p.markets.isNotEmpty) KvRow.text('거래 시장', p.markets.join(' · ')),
    ];

    Widget faq(String q, List<Widget> a) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(AppRadius.card)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                SvgIcon(AppIcons.chat, size: 16, color: AppColors.blue),
                const SizedBox(width: 6),
                Expanded(child: Text(q, style: ts(14.5, weight: FontWeight.w700))),
              ]),
              const SizedBox(height: 8),
              ...a,
            ],
          ),
        );

    return ScreenFrame(
      white: true,
      appBar: WspAppBar(
        title: p.isBrokerage ? '해외주식 계좌 개설' : '${p.type} 가입',
        onBack: app.back,
        right: AppIconButton(icon: AppIcons.heart, label: '관심 상품', onTap: () {}),
      ),
      footer: Row(
        children: [
          SizedBox(width: 96, child: AppButton('상담', kind: BtnKind.secondary, onPressed: () {})),
          const SizedBox(width: 8),
          Expanded(
            child: AppButton(
              joinActive || directActive ? '이어서 가입' : '상품 가입',
              onPressed: () => app.openJoinMethod(p.id, from: ctx != null ? 'asset' : null),
            ),
          ),
        ],
      ),
      children: [
        const SizedBox(height: 10),
        Text.rich(title, style: titleStyle),
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: chips),
        if (ctx != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFEEF5FF), borderRadius: BorderRadius.circular(12)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SvgIcon(AppIcons.target, size: 20, color: AppColors.blue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      bold('자산관리 상담에서 정한 방향'),
                      TextSpan(
                        text: '\n${ctx.purpose}'
                            '${ctx.monthly != null ? ' · 월 ${formatMan(ctx.monthly)}${p.isBrokerage ? ' 투자' : ''}' : ''}'
                            '${ctx.months != null ? ' · ${ctx.months}개월' : ''}',
                      ),
                      TextSpan(
                        text: '\n상품을 고른 것은 가입이 아니에요. 아래 상품 가입에서 가입 방법을 고르면 가입 지원이 시작돼요.',
                        style: ts(12, color: AppColors.text3),
                      ),
                    ]),
                    style: ts(13.5, height: 1.55),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(12)),
          child: DefaultTextStyle.merge(style: ts(14.5, height: 1.55), child: box),
        ),
        ?slider,
        const Divider(height: 36, color: AppColors.line),
        const _H3('자주하는 질문'),
        faq('이 상품은 어떤 상품인가요?', [
          Text(p.summary, style: ts(13.5, color: AppColors.text2, height: 1.55)),
          KvRows(rows),
        ]),
        faq('가입하려면 무엇이 필요한가요?', [
          for (final id in p.conditions)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('· ${conditions[id]?.label ?? id}', style: ts(13.5, color: AppColors.text2, height: 1.5)),
            ),
          const SizedBox(height: 4),
          Text('＊ 부족한 조건은 AI와 함께 가입할 때 해결 순서를 안내해 드려요.', style: ts(12, color: AppColors.text3, height: 1.5)),
        ]),
        const Divider(height: 36, color: AppColors.line),
        for (final x in ['상품설명', p.isBrokerage ? '수수료안내' : '금리안내', '약관 및 상품설명서'])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(children: [Expanded(child: Text(x, style: ts(15))), SvgIcon(AppIcons.chevron, size: 16, color: AppColors.muted)]),
          ),
        const Divider(height: 36, color: AppColors.line),
        Text('준법감시인 심의필', style: ts(12, weight: FontWeight.w700, color: AppColors.text3)),
        const SizedBox(height: 2),
        Text('경진대회 시연용 모의 화면으로 심의 번호가 없어요.', style: ts(12, color: AppColors.text3)),
      ],
    );
  }
}

/// 상품 가입 방법 선택 시트 내용
class JoinMethodSheetView extends StatelessWidget {
  const JoinMethodSheetView({super.key, required this.sheet});

  final JoinMethodSheet sheet;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    final p = getProduct(sheet.productId)!;
    Widget choice({required bool ai, required String title, required String desc}) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: ai ? const Color(0xFFEEF5FF) : AppColors.bg,
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.card),
              onTap: () => app.chooseJoinMethod(ai, p.id, sheet.from),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: ai ? AppColors.blue : Colors.white, borderRadius: BorderRadius.circular(12)),
                      child: SvgIcon(ai ? AppIcons.spark : AppIcons.doc, size: 22, color: ai ? Colors.white : AppColors.text2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: ts(15.5, weight: FontWeight.w700)),
                          const SizedBox(height: 3),
                          Text(desc, style: ts(13, color: AppColors.text2, height: 1.5)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${p.name}\n가입 방법을 골라 주세요', style: ts(19, weight: FontWeight.w700, height: 1.45, letterSpacing: -0.03)),
        const SizedBox(height: 16),
        choice(
          ai: true,
          title: sheet.joinActive ? 'AI 가입 지원 이어서 하기' : 'AI와 함께 가입',
          desc: '부족한 조건과 해결 순서를 확인하고, 필요한 업무 화면을 바로 열어 드려요',
        ),
        choice(ai: false, title: sheet.directActive ? '직접 가입 이어서 하기' : '직접 가입', desc: '기존 가입 화면을 단계별로 직접 진행해요'),
      ],
    );
  }
}

/* ==================================================================
 * 전체 메뉴 (기존 업무 화면)
 * ================================================================== */

const List<String> _menuOrder = ['실명확인', '계좌 개설', '인증센터', '내 정보 관리', '외환', '투자'];

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key, required this.entry});

  final RouteEntry entry;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    final data = entry.data is MenuData ? entry.data as MenuData : null;
    final c = data?.conditions;
    final facts = c != null && c.ok ? c.data!.facts : null;
    final d = app.session.direct;
    final selfFix = app.directFsm.state == 'D_SELF_FIX' && d != null;
    final highlight = entry.params['highlight'] as String?;

    return ScreenFrame(
      white: true,
      appBar: WspAppBar(title: '전체 메뉴', onBack: app.back),
      children: [
        if (selfFix)
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 6),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.warningBg, borderRadius: BorderRadius.circular(AppRadius.card)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('직접 가입 중이에요', style: ts(15, weight: FontWeight.w700, color: AppColors.warningText)),
                const SizedBox(height: 4),
                Text(
                  '${josa(d.notice != null ? d.notice!.conditions.map((x) => x.label).join(', ') : '부족한 조건', '을')} 해결한 뒤, 가입을 처음부터 다시 진행해야 해요.',
                  style: ts(13.5, color: AppColors.warningText, height: 1.5),
                ),
                const SizedBox(height: 10),
                AppButton('가입 처음부터 다시 하기', size: BtnSize.sm, block: false, onPressed: app.direct.restart),
              ],
            ),
          ),
        if (c != null && !c.ok) ...[
          const SizedBox(height: 8),
          const NoticeBox(body: '완료 여부를 불러오지 못했어요.', tone: UiTone.warning, icon: null),
        ],
        for (final menu in _menuOrder)
          Container(
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
            decoration: highlight == menu
                ? BoxDecoration(color: const Color(0xFFEEF5FF), borderRadius: BorderRadius.circular(AppRadius.card), border: Border.all(color: AppColors.blue))
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
                  child: Text(menu, style: ts(13, weight: FontWeight.w700, color: AppColors.text3)),
                ),
                for (final t in tasks.where((t) => t.menu == menu))
                  _MenuItem(
                    task: t,
                    done: facts != null && t.effects.entries.every((e) => facts[e.key] == e.value),
                    onTap: () => app.menuTask(t.id),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({required this.task, required this.done, required this.onTap});

  final TaskDef task;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12)),
              child: SvgIcon(AppIcons.task(task.icon), size: 22, color: AppColors.blue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(task.label, style: ts(15, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(task.desc, style: ts(12.5, color: AppColors.text2, height: 1.4)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            done ? const ToneBadge('완료', UiTone.success) : SvgIcon(AppIcons.chevron, size: 16, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
