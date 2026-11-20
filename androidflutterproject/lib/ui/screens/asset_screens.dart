/// 자산관리 상담: 동의, 상담(대화·큰 숫자·제안·다음 행동), 서비스 탐색.
library;

import 'package:flutter/material.dart';

import '../../app/overlays.dart';
import '../../app/router.dart';
import '../../app/sessions.dart';
import '../../domain/asset_advisor.dart' as aa;
import '../../domain/formatters.dart';
import '../../domain/lumpsum_script.dart' as ls;
import '../../domain/scenario.dart';
import '../app_scope.dart';
import '../chat_parts.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets.dart';
import 'join_screens.dart' show ConsentHero, customerNameOf, freshReply;

class AssetConsentScreen extends StatelessWidget {
  const AssetConsentScreen({super.key, required this.entry});

  final RouteEntry entry;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    if (app.assetFsm.state != 'CONSENT') {
      return EmptyScreen(title: 'AI 자산관리 상담', message: '진행 중인 동의 요청이 없어요.', onBack: app.back);
    }
    return ScreenFrame(
      white: true,
      appBar: WspAppBar(title: 'AI 자산관리 상담', onBack: app.back),
      footer: ButtonRow([
        AppButton('다음에 할게요', kind: BtnKind.ghost, onPressed: app.asset.decline),
        AppButton('상담 시작', onPressed: app.asset.agree),
      ]),
      children: [
        ConsentHero(icon: AppIcons.target, title: '목표에 맞춰\n모을 돈과 투자할 돈을 정해요'),
        CardBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CardTitle('조회·분석 동의 (필수)', icon: AppIcons.shield),
              const BulletList(['마이데이터로 연결된 기관의 잔액·입출금·카드 내역', '상담 중 고객님이 답한 정보']),
            ],
          ),
        ),
        const SizedBox(height: 12),
        CardBox(
          outline: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CardTitle('이 상담에서 하지 않는 것', icon: AppIcons.lock),
              const BulletList(['상품 가입·이체·해지'], negative: true),
            ],
          ),
        ),
      ],
    );
  }
}

const List<String> _infoKeys = ['monthlyIncome', 'monthlyExpense', 'liquidAssets', 'investPace', 'investAssets', 'debt', 'goalAmount', 'goalMonths', 'plannedLumpSum', 'monthlySavingPref'];


class AssetScreen extends StatefulWidget {
  const AssetScreen({super.key, required this.entry});

  final RouteEntry entry;

  @override
  State<AssetScreen> createState() => _AssetScreenState();
}

class _AssetScreenState extends State<AssetScreen> {
  final _scroll = ScrollController();
  final _lastKey = GlobalKey();
  int _count = -1;
  bool _thinking = false;
  String _state = '';

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    final a = app.session.asset;
    if (a == null) {
      return EmptyScreen(title: 'AI 자산관리 상담', message: '진행 중인 상담이 없어요.', buttonLabel: '상담 시작', onButton: app.asset.startAction, onBack: app.back);
    }
    final st = app.assetFsm.state;
    if (a.chat.length != _count || a.thinking != _thinking || st != _state) {
      _count = a.chat.length;
      _thinking = a.thinking;
      _state = st;
      scrollToLatest(_lastKey, _scroll);
    }
    final f = app.assetFsm;
    final w = MediaQuery.sizeOf(context).width;
    final side = w > 640 ? (w - 640) / 2 : 0.0;
    return Material(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ChatHeader(onBack: app.back, exitLabel: f.can('END') || f.can('EXIT') ? '분석 종료' : null, onExit: app.asset.end),
            Expanded(
              child: Material(
                color: AppColors.chatBg,
                child: ListView(
                  controller: _scroll,
                  padding: EdgeInsets.fromLTRB(16 + side, 16, 16 + side, 24),
                  children: [
                    ChatIntro(service: 'AI 자산관리 상담', customerName: customerNameOf(app), startedAt: a.chat.isNotEmpty ? a.chat.first.at : null),
                    ChatLogView(messages: a.chat, thinking: a.thinking, lastKey: _lastKey),
                    _AssetActionPanel(a: a, state: st),
                  ],
                ),
              ),
            ),
            const ChatInputBar(fieldKey: ValueKey('asset-input')),
          ],
        ),
      ),
    );
  }
}

class _AssetActionPanel extends StatelessWidget {
  const _AssetActionPanel({required this.a, required this.state});

  final AssetSession a;
  final String state;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    final st = state;
    if (a.thinking || a.pendingAccept) return const SizedBox.shrink();
    final rise = freshReply(a.chat);
    final riseKey = a.chat.isNotEmpty ? a.chat.last.id : '';
    Widget riseAt(int i, Widget w) => rise ? RiseIn(key: ValueKey('rise-$riseKey-$i'), delay: Duration(milliseconds: 70 * i), child: w) : w;
    Widget wrap(List<Widget> children) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        );
    void chip(String value, String label) => app.guard('asset-send', () => app.asset.answerChip(value, label));

    if (st == 'GOAL') {
      return wrap([
        ChipWrap([
          for (var i = 0; i < ls.assetGoalChips.length; i++)
            riseAt(i, AnswerChip(ls.assetGoalChips[i], large: true, onTap: () => app.guard('asset-send', () => app.asset.answerText(ls.assetGoalChips[i])))),
        ]),
      ]);
    }
    if (st == 'ASKING') {
      final q = aa.questions[a.pendingQuestion];
      if (q == null) return const SizedBox.shrink();
      final n = q.options.length;
      return wrap([
        ChipWrap([for (var i = 0; i < n; i++) riseAt(i, AnswerChip(q.options[i].$1, large: true, onTap: () => chip('${q.options[i].$2}', q.options[i].$1)))]),
        const SizedBox(height: 10),
        ChipWrap([
          riseAt(n, AnswerChip('잘 모르겠어요', onTap: () => chip('UNKNOWN', '잘 모르겠어요'))),
          riseAt(n + 1, AnswerChip('답하고 싶지 않아요', onTap: () => chip('REFUSED', '답하고 싶지 않아요'))),
          riseAt(n + 2, AnswerChip('지금 정보로 알려주세요', accent: true, onTap: () => chip('STOP', '지금 정보로 알려주세요'))),
        ]),
      ]);
    }
    if (st == 'REVIEW') {
      final alts = a.proposal?.basis.alternatives ?? const <aa.Alternative>[];
      return wrap([
        if (alts.isNotEmpty) ...[
          Text('이렇게 바꿀 수도 있어요', style: ts(12.5, weight: FontWeight.w700, color: AppColors.text2)),
          const SizedBox(height: 6),
          for (final x in alts)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.line)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => app.guard('asset-alt', () => app.asset.applyAlternative(x.id)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(x.label, style: ts(14, weight: FontWeight.w700)),
                        Text(x.detail, style: ts(12.5, color: AppColors.text2, height: 1.45)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 4),
        ],
        AppButton('이 방향으로 할게요', onPressed: () => app.guard('asset-accept', app.asset.accept)),
      ]);
    }
    if (st == 'NEXT_ACTION') {
      Widget next(String kind, SvgArt icon, String title, String sub) => Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card), side: const BorderSide(color: AppColors.line)),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.card),
              onTap: () => app.asset.nextAction(kind),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SvgIcon(icon, size: 22, color: AppColors.blue),
                    const SizedBox(height: 8),
                    Text(title, style: ts(14, weight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(sub, style: ts(12, color: AppColors.text2)),
                  ],
                ),
              ),
            ),
          );
      return wrap([
        Row(children: [
          Expanded(child: next('explore', AppIcons.product, '상품 둘러보기', '정한 방향에 맞는 상품 보기')),
          const SizedBox(width: 8),
          Expanded(child: next('consult', AppIcons.headset, '전문 상담 연결', '상담사에게 요약 전달')),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: next('recheck', AppIcons.list, '정보 다시 확인', '틀린 정보 고치기')),
          const SizedBox(width: 8),
          Expanded(child: next('keep', AppIcons.check, '지금은 유지', '상담 마치기')),
        ]),
      ]);
    }
    if (st == 'HOLD') {
      return wrap([
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.warningBg, borderRadius: BorderRadius.circular(AppRadius.card)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                SvgIcon(AppIcons.alert, size: 17, color: AppColors.warningText),
                const SizedBox(width: 6),
                Text('제안 보류', style: ts(14.5, weight: FontWeight.w700, color: AppColors.warningText)),
              ]),
              const SizedBox(height: 4),
              Text(a.hold?.text ?? '', style: ts(13.5, color: AppColors.warningText, height: 1.5)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppButton('정보 다시 확인', kind: BtnKind.secondary, onPressed: () => app.asset.nextAction('recheck')),
        const SizedBox(height: 8),
        AppButton('상담 연결', kind: BtnKind.secondary, onPressed: () => app.asset.nextAction('consult')),
        const SizedBox(height: 8),
        AppButton('상담 종료', kind: BtnKind.ghost, onPressed: app.asset.end),
      ]);
    }
    if (st == 'RECONSULT') {
      return wrap([
        if (a.info != null) _InfoEditor(a: a) else const NoticeBox(body: '정보를 다시 불러온 뒤 분석해요.', tone: UiTone.info),
        const SizedBox(height: 10),
        ButtonRow([
          AppButton('상담 종료', kind: BtnKind.ghost, onPressed: app.asset.end),
          AppButton(a.info != null ? '다시 분석' : '다시 조회하고 분석', onPressed: () => app.guard('asset-resume', app.asset.resumeAnalysis)),
        ]),
      ]);
    }
    if (st == 'EXPLORE') return wrap([AppButton('상품 둘러보기 화면으로', onPressed: app.asset.open)]);
    if (st == 'HANDOFF') return wrap([AppButton('상담 연결 화면으로', onPressed: app.asset.open)]);
    if (st == 'CLOSED' || st == 'TO_JOIN') {
      return wrap([
        ButtonRow([
          AppButton('홈으로', kind: BtnKind.ghost, onPressed: app.goHome),
          AppButton('새 상담 시작', onPressed: app.asset.startAction),
        ]),
      ]);
    }
    return const SizedBox.shrink();
  }
}

/// 정보 다시 확인: 값과 고치기 버튼만 보여 준다
class _InfoEditor extends StatelessWidget {
  const _InfoEditor({required this.a});

  final AssetSession a;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    final info = a.info!;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.card), border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            SvgIcon(AppIcons.list, size: 16, color: AppColors.text),
            const SizedBox(width: 6),
            Text('고객님 정보', style: ts(14, weight: FontWeight.w700)),
          ]),
          const SizedBox(height: 4),
          for (final k in _infoKeys)
            if (!(k == 'monthlySavingPref' && info.items[k]?.value == null))
              Row(
                children: [
                  Expanded(child: Text(aa.itemLabel(k), style: ts(13, color: AppColors.text2))),
                  Text(info.items[k]?.value == null ? '입력 전' : aa.display(k, info.items[k]!.value), style: ts(13.5, weight: FontWeight.w700)),
                  TextButton(
                    onPressed: () => app.asset.openEdit(k),
                    style: TextButton.styleFrom(minimumSize: const Size(48, 36), padding: const EdgeInsets.symmetric(horizontal: 8)),
                    child: Text('고치기', style: ts(12.5, color: AppColors.blue)),
                  ),
                ],
              ),
        ],
      ),
    );
  }
}

/// 정보 고치기 시트 내용
class AssetEditSheetView extends StatefulWidget {
  const AssetEditSheetView({super.key, required this.sheet});

  final AssetEditSheet sheet;

  @override
  State<AssetEditSheetView> createState() => _AssetEditSheetViewState();
}

class _AssetEditSheetViewState extends State<AssetEditSheetView> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    final app = AppScope.controllerOf(context);
    final key = widget.sheet.itemKey;
    final v = app.session.asset?.info?.items[key]?.value;
    final isMonths = aa.items[key]?.kind == 'months';
    _ctrl = TextEditingController(text: v == null ? '' : (isMonths ? '$v' : '${(v / 10000).round()}'));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    final key = widget.sheet.itemKey;
    final v = app.session.asset?.info?.items[key]?.value;
    final isMonths = aa.items[key]?.kind == 'months';
    final now = v == null ? '입력 전' : aa.display(key, v);
    if (aa.items[key]?.kind == 'pace') {
      final q = aa.questions['investPace']!;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('투자 속도 고치기', style: ts(19, weight: FontWeight.w700, letterSpacing: -0.03)),
          const SizedBox(height: 4),
          Text('지금 $now', style: ts(14, color: AppColors.text2)),
          const SizedBox(height: 14),
          ChipWrap([for (final o in q.options) AnswerChip(o.$1, large: true, onTap: () => app.asset.savePace(key, o.$2))]),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${aa.itemLabel(key)} 고치기', style: ts(19, weight: FontWeight.w700, letterSpacing: -0.03)),
        const SizedBox(height: 4),
        Text('지금 $now', style: ts(14, color: AppColors.text2)),
        const SizedBox(height: 14),
        Text(isMonths ? '개월 수' : '금액(만원)', style: ts(13, weight: FontWeight.w700, color: AppColors.text2)),
        const SizedBox(height: 6),
        TextField(
          key: const ValueKey('asset-edit-value'),
          controller: _ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: ts(15),
          onSubmitted: (_) => app.asset.saveEdit(key, _ctrl.text),
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 16),
        ButtonRow([
          AppButton('취소', kind: BtnKind.ghost, onPressed: app.closeSheet),
          AppButton('저장', onPressed: () => app.asset.saveEdit(key, _ctrl.text)),
        ]),
      ],
    );
  }
}

/* ==================================================================
 * 서비스 탐색
 * ================================================================== */

class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key, required this.entry});

  final RouteEntry entry;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    final a = app.session.asset;
    final st = app.assetFsm.state;
    if (a == null || a.handoffTerms == null || (st != 'EXPLORE' && st != 'TO_JOIN')) {
      return EmptyScreen(title: '상품 둘러보기', message: '상담에서 정한 방향이 없어요.', buttonLabel: '전체 상품 보기', onButton: app.goProducts, onBack: app.back);
    }
    final t = a.handoffTerms!;
    return ScreenFrame(
      appBar: WspAppBar(title: '상품 둘러보기', onBack: app.back),
      children: [
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0xFFEEF5FF), borderRadius: BorderRadius.circular(AppRadius.card)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                SvgIcon(AppIcons.target, size: 15, color: AppColors.blue),
                const SizedBox(width: 5),
                Text('상담에서 정한 방향', style: ts(12.5, weight: FontWeight.w700, color: AppColors.blue)),
              ]),
              const SizedBox(height: 6),
              Text(
                '${t.purpose}${t.monthly != null ? ' · 월 ${formatMan(t.monthly)}' : ''}${t.months != null ? ' · ${t.months}개월' : ''}',
                style: ts(16, weight: FontWeight.w700),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final p in products)
          Builder(builder: (context) {
            final pick = p.id == DemoScenario.productId;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: CardBox(
                outline: pick,
                color: pick ? const Color(0xFFF4F8FE) : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      ToneBadge(p.type, UiTone.info),
                      const Spacer(),
                      Text(p.rate, style: ts(13, weight: FontWeight.w700, color: AppColors.blue)),
                    ]),
                    const SizedBox(height: 10),
                    Text(p.name, style: ts(16, weight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(p.summary, style: ts(13, color: AppColors.text2, height: 1.5)),
                    const SizedBox(height: 12),
                    pick
                        ? AppButton('이 계좌 보기', onPressed: () => app.asset.selectProduct(p.id))
                        : AppButton('다른 상품', kind: BtnKind.ghost, size: BtnSize.sm, block: false, onPressed: () => app.asset.selectProduct(p.id)),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}
