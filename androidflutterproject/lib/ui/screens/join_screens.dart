/// 가입 지원(AI) 화면: 동의, 대화+체크리스트, 가입 정보 확인·승인, 가입 결과(직접 가입 공용), 상담 연결(자산관리 공용).
library;

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/join_flow.dart';
import '../../app/overlays.dart';
import '../../app/router.dart';
import '../../app/sessions.dart';
import '../../domain/formatters.dart';
import '../../domain/pathfinder.dart';
import '../../domain/scenario.dart';
import '../app_scope.dart';
import '../chat_parts.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets.dart';

String customerNameOf(AppController app) => app.store.state.customer.name;

/// 방금 도착한 AI 답이면 아래 칩·카드를 순서대로 올라오게 한다
bool freshReply(List<ChatMsg> chat) {
  if (chat.isEmpty) return false;
  final last = chat.last;
  return last.role == 'ai' && DateTime.now().millisecondsSinceEpoch - last.at < 1600;
}

/* ==================================================================
 * 동의
 * ================================================================== */

class JoinConsentScreen extends StatelessWidget {
  const JoinConsentScreen({super.key, required this.entry});

  final RouteEntry entry;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    final j = app.session.join;
    if (j == null || app.joinFsm.state != 'CONSENT') {
      return EmptyScreen(title: '가입 지원', message: '진행 중인 동의 요청이 없어요.', onBack: app.back);
    }
    final p = getProduct(j.productId)!;
    return ScreenFrame(
      white: true,
      appBar: WspAppBar(title: 'AI 가입 지원', onBack: app.back),
      footer: ButtonRow([
        AppButton('다음에 할게요', kind: BtnKind.ghost, onPressed: app.join.exit),
        AppButton('가입 조건 확인', onPressed: () => app.guard('join-agree', app.join.agree)),
      ]),
      children: [
        ConsentHero(icon: AppIcons.spark, title: '${p.name}\n가입을 도와드릴게요'),
        CardBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CardTitle('조회·분석 동의 (필수)', icon: AppIcons.shield),
              const BulletList([
                '실명확인·계좌·인증서·고객정보 등록 기록',
                '마이데이터로 연결된 다른 은행 계좌 목록',
                '로그인 때 확인된 휴대폰 본인 명의 여부',
              ]),
            ],
          ),
        ),
        const SizedBox(height: 12),
        CardBox(
          outline: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CardTitle('이 동의로 하지 않는 것', icon: AppIcons.lock),
              const BulletList(['상품 가입 자동 신청'], negative: true),
            ],
          ),
        ),
      ],
    );
  }
}

/// 동의 화면 머리
class ConsentHero extends StatelessWidget {
  const ConsentHero({super.key, required this.icon, required this.title, this.desc});

  final SvgArt icon;
  final String title;
  final String? desc;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 14, 2, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.blueLight, borderRadius: BorderRadius.circular(14)),
            child: SvgIcon(icon, size: 26, color: AppColors.blue),
          ),
          const SizedBox(height: 14),
          Text(title, style: ts(21, weight: FontWeight.w700, height: 1.4, letterSpacing: -0.03)),
          if (desc != null) ...[
            const SizedBox(height: 8),
            Text(desc!, style: ts(14, color: AppColors.text2, height: 1.55)),
          ],
        ],
      ),
    );
  }
}

/* ==================================================================
 * 대화 + 체크리스트
 * ================================================================== */

const List<String> _talkStates = ['CLARIFYING', 'OPTIONS_READY', 'REMAINING'];

class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key, required this.entry});

  final RouteEntry entry;

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
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
    final j = app.session.join;
    if (j == null) {
      return EmptyScreen(title: 'AI 가입 지원', message: '진행 중인 가입 지원이 없어요.', buttonLabel: '상품 보기', onButton: app.goProducts, onBack: app.back);
    }
    final st = app.joinFsm.state;
    if (j.chat.length != _count || j.thinking != _thinking || st != _state) {
      _count = j.chat.length;
      _thinking = j.thinking;
      _state = st;
      scrollToLatest(_lastKey, _scroll);
    }
    final canTalk = _talkStates.contains(st) && !j.thinking;
    final side = MediaQuery.sizeOf(context).width > 640 ? (MediaQuery.sizeOf(context).width - 640) / 2 : 0.0;
    return Material(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ChatHeader(
              onBack: app.back,
              exitLabel: app.joinFsm.can('EXIT') ? '그만하기' : null,
              onExit: app.join.exit,
            ),
            Expanded(
              child: Material(
                color: AppColors.chatBg,
                child: ListView(
                  controller: _scroll,
                  padding: EdgeInsets.fromLTRB(16 + side, 16, 16 + side, 24),
                  children: [
                    ChatIntro(service: 'AI 가입 지원', customerName: customerNameOf(app), startedAt: j.chat.isNotEmpty ? j.chat.first.at : null),
                    _Checklist(j: j, state: st),
                    const SizedBox(height: 14),
                    ChatLogView(messages: j.chat, thinking: j.thinking, lastKey: _lastKey),
                    _JoinActionPanel(j: j, state: st),
                  ],
                ),
              ),
            ),
            if (canTalk) QuickChips(items: const ['상담 연결해 주세요', '완료했다고 떴는데 다시 하래요', '그만할래요'], onTap: app.join.sendText),
            const ChatInputBar(fieldKey: ValueKey('join-input')),
          ],
        ),
      ),
    );
  }
}

/// 가입 조건 체크리스트. 확인 중에는 조건마다 결과가 하나씩 드러난다 (checkPending/checkDone).
class _Checklist extends StatefulWidget {
  const _Checklist({required this.j, required this.state});

  final JoinSession j;
  final String state;

  @override
  State<_Checklist> createState() => _ChecklistState();
}

class _ChecklistState extends State<_Checklist> {
  bool _entered = false;

  @override
  Widget build(BuildContext context) {
    final j = widget.j;
    final p = getProduct(j.productId)!;
    final ev = j.evaluation;
    final ids = ev != null ? [for (final c in ev.conditions) c.id] : p.conditions;
    final byId = {if (ev != null) for (final c in ev.conditions) c.id: c};
    final checking = j.checkPending != null;
    final done = j.checkDone ?? const <String>[];
    final fresh = j.checkFresh;
    final entered = _entered;
    if (!_entered) WidgetsBinding.instance.addPostFrameCallback((_) => _entered = true);
    final met = ev != null ? ev.conditions.where((c) => c.status == 'MET' && (!checking || done.contains(c.id))).length : 0;
    final ready = widget.state == 'READY_TO_APPLY';
    final rows = <Widget>[];
    for (var i = 0; i < ids.length; i++) {
      final id = ids[i];
      final cond = conditions[id];
      final label = facts[cond?.fact]?.short ?? cond?.label ?? id;
      final revealed = !checking || done.contains(id);
      final isMet = revealed && byId[id]?.status == 'MET';
      final row = Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            _CkTick(met: isMet, loading: checking && !revealed, pop: fresh == id),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: ts(14, weight: FontWeight.w600))),
          ],
        ),
      );
      rows.add(entered ? row : RiseIn(key: ValueKey('ck-$id'), delay: Duration(milliseconds: i * 80), child: row));
    }
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [if (ready) const BoxShadow(color: AppColors.success, spreadRadius: 2), ...shadowCard],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('가입 조건 $met/${ids.length}', style: ts(14, weight: FontWeight.w700)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(p.name, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12, weight: FontWeight.w600, color: AppColors.blue)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...rows,
        ],
      ),
    );
  }
}

class _CkTick extends StatelessWidget {
  const _CkTick({required this.met, required this.loading, required this.pop});

  final bool met;
  final bool loading;
  final bool pop;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Spinner(size: 18, stroke: 1.5, track: Color(0xFFE4E9F0));
    final circle = Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: met ? AppColors.blue : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(color: met ? AppColors.blue : const Color(0xFFD5DBE3), width: 1.5),
      ),
      child: met ? SvgIcon(AppIcons.check, size: 11, color: Colors.white) : null,
    );
    if (!met || !pop) return circle;
    return TweenAnimationBuilder<double>(
      key: const ValueKey('pop'),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 400),
      curve: Curves.ease,
      builder: (context, t, child) => Opacity(opacity: t, child: Transform.scale(scale: 0.3 + 0.7 * t, child: child)),
      child: circle,
    );
  }
}

class _JoinActionPanel extends StatelessWidget {
  const _JoinActionPanel({required this.j, required this.state});

  final JoinSession j;
  final String state;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    final st = state;
    if (j.thinking) return const SizedBox.shrink();
    Widget wrap(Widget child) => Padding(padding: const EdgeInsets.only(top: 4), child: child);
    final rise = freshReply(j.chat);
    final riseKey = j.chat.isNotEmpty ? j.chat.last.id : '';
    Widget riseAt(int i, Widget w) => rise ? RiseIn(key: ValueKey('rise-$riseKey-$i'), delay: Duration(milliseconds: 70 * i), child: w) : w;
    final q = j.pendingKey;
    if (q != null && (st == 'CLARIFYING' || st == 'REMAINING')) {
      return wrap(ChipWrap([
        riseAt(0, AnswerChip('네, 있어요', large: true, accent: true, onTap: () => app.join.answer(q, true))),
        riseAt(1, AnswerChip('아니요, 없어요', large: true, onTap: () => app.join.answer(q, false))),
      ]));
    }
    if ((st == 'OPTIONS_READY' || st == 'REMAINING') && j.options.isNotEmpty) {
      final shown = j.options.where((o) => o.shown).toList();
      final blocked = j.options.where((o) => !o.shown).toList();
      return wrap(Column(
        children: [
          for (var i = 0; i < shown.length; i++) riseAt(i, _OptionCard(option: shown[i], onTap: () => app.join.chooseOption(shown[i].actionId))),
          for (var i = 0; i < blocked.length; i++) riseAt(shown.length + i, _OptionCard(option: blocked[i])),
        ],
      ));
    }
    if (st == 'TASK_OPEN') {
      return wrap(NoticeBox(body: '업무 화면이 열려 있어요. 화면을 닫으면 은행 기록을 다시 확인해요.', tone: UiTone.info, icon: AppIcons.doc));
    }
    if (st == 'CHECK_FAILED') {
      return wrap(ButtonRow([
        AppButton('상담 연결', kind: BtnKind.secondary, onPressed: () => app.join.requestConsult('CUSTOMER_REQUEST', '고객이 상담 연결을 요청했어요.')),
        AppButton('다시 확인', onPressed: app.join.retryCheck),
      ]));
    }
    if (st == 'INVESTIGATING' && j.exception != null) {
      final ex = j.exception!;
      final fact = ex.facts.isNotEmpty ? ex.facts.first : null;
      final rep = fact != null ? (j.repeat[fact] ?? 0) : 0;
      final requery = ex.cause == 'IN_PROGRESS' || ex.cause == 'QUERY_FAILED';
      return wrap(Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.warningBg, borderRadius: BorderRadius.circular(AppRadius.card)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              SvgIcon(AppIcons.alert, size: 17, color: AppColors.warningText),
              const SizedBox(width: 6),
              Expanded(child: Text(exceptionLabel[ex.cause] ?? ex.cause, style: ts(14, weight: FontWeight.w700, color: AppColors.warningText))),
              if (rep > 0) Text('같은 문제 $rep/${Policy.repeatLimit}회', style: ts(12, color: AppColors.warningText)),
            ]),
            const SizedBox(height: 12),
            ButtonRow([
              AppButton('상담 연결', kind: BtnKind.secondary, onPressed: () => app.guard('join-investigate', () => app.join.investigate('consult'))),
              requery
                  ? AppButton('처리 결과 다시 확인', onPressed: () => app.guard('join-investigate', () => app.join.investigate('requery')))
                  : AppButton('다시 진행', onPressed: () => app.guard('join-investigate', () => app.join.investigate('retry'))),
            ]),
          ],
        ),
      ));
    }
    if (st == 'READY_TO_APPLY') {
      return wrap(Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.successBg, borderRadius: BorderRadius.circular(AppRadius.card)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              SvgIcon(AppIcons.check, size: 18, color: AppColors.successText),
              const SizedBox(width: 6),
              Text('가입 준비가 끝났어요', style: ts(15, weight: FontWeight.w700, color: AppColors.successText)),
            ]),
            const SizedBox(height: 4),
            Text('가입 정보를 확인하고 직접 승인해 주세요.', style: ts(13.5, color: AppColors.successText)),
            if (j.applyNotice != null) ...[
              const SizedBox(height: 6),
              Text(j.applyNotice!.text, style: ts(13, weight: FontWeight.w700, color: AppColors.warningText, height: 1.5)),
            ],
            const SizedBox(height: 12),
            AppButton('가입 정보 확인하기', onPressed: app.join.openApply),
          ],
        ),
      ));
    }
    if (st == 'ESCALATED') return wrap(AppButton('상담 연결 화면으로', onPressed: app.join.open));
    if (const ['APPLYING', 'VERIFYING', 'RESULT_UNCERTAIN', 'COMPLETED', 'FAILED'].contains(st)) {
      return wrap(AppButton('가입 결과 보기', onPressed: app.join.open));
    }
    return const SizedBox.shrink();
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({required this.option, this.onTap});

  final RouteOption option;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final o = option;
    final t = getTask(o.actionId)!;
    final off = onTap == null;
    final unknownNeeds = o.unknownNeeds;
    final blockedNeeds = o.blockedNeeds;
    final body = Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: off ? AppColors.neutralBg : AppColors.blueLight, borderRadius: BorderRadius.circular(12)),
            child: SvgIcon(AppIcons.task(t.icon), size: 22, color: off ? AppColors.muted : AppColors.blue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(child: Text(t.label, style: ts(15, weight: FontWeight.w700, color: off ? AppColors.text3 : AppColors.text))),
                  if (!off && o.recommended) ...[const SizedBox(width: 6), const ToneBadge('추천', UiTone.info)],
                ]),
                const SizedBox(height: 3),
                if (off)
                  Text(
                    '이용 불가: ${blockedNeeds.isNotEmpty ? '${blockedNeeds.map((k) => constraintLabels[k]).join(', ')} 없음' : '이후 단계로 이어지지 않음'}',
                    style: ts(12.5, color: AppColors.text3, height: 1.45),
                  )
                else ...[
                  Text(t.desc, style: ts(13, color: AppColors.text2, height: 1.45)),
                  const SizedBox(height: 4),
                  Row(children: [
                    SvgIcon(AppIcons.clock, size: 13, color: AppColors.text3),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text('약 ${t.minutes}분${t.prep.isNotEmpty ? ' · 준비물: ${t.prep.join(', ')}' : ''}', style: ts(12, color: AppColors.text3, height: 1.4)),
                    ),
                  ]),
                  if (unknownNeeds.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '이 방법을 고르면 ${josa(unknownNeeds.map((k) => constraintLabels[k]).join(', '), '이')} 있는 것으로 볼게요',
                      style: ts(12, color: AppColors.warningText, height: 1.45),
                    ),
                  ],
                ],
              ],
            ),
          ),
          if (!off) Padding(padding: const EdgeInsets.only(top: 10), child: SvgIcon(AppIcons.chevron, size: 16, color: AppColors.muted)),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: off ? const Color(0xFFF7F8FA) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card), side: const BorderSide(color: AppColors.line)),
        child: off ? body : InkWell(onTap: onTap, borderRadius: BorderRadius.circular(AppRadius.card), child: body),
      ),
    );
  }
}

/* ==================================================================
 * 가입 정보 확인·승인
 * ================================================================== */

class ApplyScreen extends StatefulWidget {
  const ApplyScreen({super.key, required this.entry});

  final RouteEntry entry;

  @override
  State<ApplyScreen> createState() => _ApplyScreenState();
}

class _ApplyScreenState extends State<ApplyScreen> {
  String? _market;
  int? _months;
  TextEditingController? _monthly;

  @override
  void dispose() {
    _monthly?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    final j = app.session.join;
    if (j == null || app.joinFsm.state != 'READY_TO_APPLY') {
      return EmptyScreen(title: '가입 정보 확인', message: '가입 준비가 끝난 건이 없어요.', buttonLabel: '진행 상황 보기', onButton: app.join.open, onBack: app.back);
    }
    final data = widget.entry.data is AccountData ? widget.entry.data as AccountData : null;
    final acc = data?.summary;
    if (acc == null || !acc.ok) {
      return QueryErrorView(title: '가입 정보 확인', error: acc?.error, onBack: app.back, onHome: app.goHome, onRetry: () => app.router.rerender());
    }
    final p = getProduct(j.productId)!;
    final ctx = j.assetContext;
    final a = acc.data!.account;
    final account = a != null ? '${a.name} ${a.number}' : '계좌 없음';
    final ev = j.evaluation;

    Widget staticField(String label, String value) => Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: ts(13, weight: FontWeight.w700, color: AppColors.text2)),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12)),
                child: Text(value, style: ts(14.5, color: AppColors.text2)),
              ),
            ],
          ),
        );

    final head = <Widget>[
      if (j.applyNotice != null) ...[
        const SizedBox(height: 8),
        NoticeBox(body: j.applyNotice!.text, tone: toneOf(j.applyNotice!.tone), icon: AppIcons.alert),
      ],
    ];
    final tail = <Widget>[
      const SizedBox(height: 12),
      CardBox(
        outline: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CardTitle('은행 기록으로 확인한 가입 조건', icon: AppIcons.shield),
            if (ev != null) BulletList([for (final c in ev.conditions) c.label]),
            const Fineprint('승인하면 은행이 조건을 한 번 더 확인해요.', top: 4),
          ],
        ),
      ),
    ];

    final List<Widget> body;
    final VoidCallback onApprove;
    if (p.isBrokerage) {
      final market = _market ?? j.terms?.market ?? p.markets.first;
      const fx = 'WON 외화통장(USD) 1002-***-552190';
      body = [
        ...head,
        const SizedBox(height: 12),
        CardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [CardTitle(p.name), KvRows([KvRow.text(p.rateLabel ?? '', p.rateValue ?? '')])])),
        const SizedBox(height: 12),
        CardBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('거래 시장', style: ts(13, weight: FontWeight.w700, color: AppColors.text2)),
              const SizedBox(height: 8),
              ChipWrap([for (final m in p.markets) AnswerChip(m, selected: m == market, onTap: () => setState(() => _market = m))]),
              staticField('연결 원화 계좌', account),
              staticField('연결 외화 계좌', fx),
            ],
          ),
        ),
        ...tail,
      ];
      onApprove = () => app.join.approveFromForm(market: market, account: account, fxAccount: fx);
    } else {
      final months = _months ??
          (ctx?.months != null && p.periods.contains(ctx!.months) ? ctx.months! : (p.periods.contains(24) ? 24 : p.periods.first));
      final initialMonthly = j.terms?.monthly ?? ctx?.monthly ?? 300000;
      final ctrl = _monthly ??= TextEditingController(text: '$initialMonthly');
      body = [
        ...head,
        const SizedBox(height: 12),
        CardBox(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [CardTitle(p.name), KvRows([KvRow.text('금리', p.rate)])])),
        const SizedBox(height: 12),
        CardBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('월 납입액', style: ts(13, weight: FontWeight.w700, color: AppColors.text2)),
              const SizedBox(height: 6),
              TextField(
                key: const ValueKey('apply-monthly'),
                controller: ctrl,
                keyboardType: TextInputType.number,
                style: ts(15),
                decoration: _inputDeco(),
              ),
              const SizedBox(height: 4),
              Text('${formatMan(p.minMonthly)} ~ ${formatMan(p.maxMonthly)}', style: ts(12, color: AppColors.text3)),
              const SizedBox(height: 14),
              Text('가입 기간', style: ts(13, weight: FontWeight.w700, color: AppColors.text2)),
              const SizedBox(height: 8),
              ChipWrap([for (final m in p.periods) AnswerChip('$m개월', selected: m == months, onTap: () => setState(() => _months = m))]),
              staticField('출금 계좌', account),
            ],
          ),
        ),
        ...tail,
      ];
      onApprove = () => app.join.approveFromForm(monthlyText: ctrl.text, months: months, account: account);
    }

    return ScreenFrame(
      appBar: WspAppBar(title: '가입 정보 확인', onBack: app.back),
      footer: AppButton('가입 승인', size: BtnSize.lg, onPressed: onApprove),
      children: body,
    );
  }
}

InputDecoration _inputDeco() => InputDecoration(
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.lineStrong)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.lineStrong)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.blue, width: 1.5)),
    );

/* ==================================================================
 * 가입 결과 (AI·직접 공용)
 * ================================================================== */

class ApplyResultScreen extends StatelessWidget {
  const ApplyResultScreen({super.key, required this.entry});

  final RouteEntry entry;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    final isJoin = entry.params['track'] != 'direct';
    final s = app.session;
    final productId = isJoin ? s.join?.productId : s.direct?.productId;
    if (productId == null) {
      return EmptyScreen(title: '가입 결과', message: '진행 중인 가입이 없어요.', buttonLabel: '홈으로', onButton: app.goHome, noBack: true);
    }
    final st = isJoin ? app.joinFsm.state : app.directFsm.state;
    final appRec = isJoin ? s.join!.application : s.direct!.application;
    final requestId = isJoin ? s.join!.requestId : s.direct!.requestId;
    final p = getProduct(productId)!;
    final terms = appRec?.terms;
    final rows = <KvRow>[
      KvRow.text('상품', p.name),
      if (terms?.monthly != null) KvRow.text('월 납입액', formatMan(terms!.monthly)),
      if (terms?.months != null) KvRow.text('가입 기간', '${terms!.months}개월'),
      if (terms?.market != null) KvRow.text('거래 시장', terms!.market!),
      if (requestId != null) KvRow.text('요청 번호', requestId, mono: true),
    ];
    final VoidCallback newCase = isJoin ? app.join.newCase : app.direct.newCase;
    final brokerage = p.isBrokerage;
    if (brokerage && appRec != null && const ['VERIFYING', 'D_VERIFYING', 'COMPLETED', 'D_DONE'].contains(st)) {
      rows.insert(0, KvRow.text('접수 번호', appRec.id, strong: true));
    }

    Widget? icon;
    Widget? extra;
    UiTone tone;
    String title;
    String desc;
    Widget? foot;
    if (brokerage && const ['APPLYING', 'VERIFYING', 'D_VERIFYING'].contains(st)) {
      final applying = st == 'APPLYING';
      icon = const Spinner(size: 34, stroke: 3.5);
      tone = UiTone.neutral;
      title = applying ? '신청을 접수하고 있어요' : '은행 승인을 기다리고 있어요';
      desc = applying ? '잠시만 기다려 주세요.' : '신청은 접수됐어요. 은행이 계좌 개설을 승인하는 중이에요. 다시 신청하지 말고 잠시만 기다려 주세요.';
      extra = ApprovalTimeline(
        key: ValueKey('tl-$st'),
        steps: applying ? _brokerSteps.sublist(0, 2) : _brokerSteps,
        wait: !applying,
        marks: true,
        gap: applying ? 0.7 : 0.15,
      );
    } else if (const ['APPLYING', 'VERIFYING', 'D_VERIFYING'].contains(st)) {
      icon = const Spinner(size: 34, stroke: 3.5);
      tone = UiTone.neutral;
      title = '은행 심사에 등록하고 있어요';
      desc = '신청 접수부터 승인 대기까지 순서대로 확인해요. 다시 신청하지 마세요.';
      extra = const ApprovalTimeline(key: ValueKey('tl-wait'));
    } else if (brokerage && (st == 'COMPLETED' || st == 'D_DONE')) {
      tone = UiTone.success;
      title = '해외주식 계좌 개설이 완료됐어요';
      desc = '은행 승인이 끝났어요. 홈에서 새 계좌를 확인할 수 있어요.';
      extra = const ApprovalTimeline(key: ValueKey('tl-done'), steps: _brokerSteps, marks: true, gap: 0.25);
      foot = AppButton('홈으로', onPressed: newCase);
    } else if (st == 'COMPLETED' || st == 'D_DONE') {
      rows.insert(0, KvRow.text('접수 번호', appRec?.id ?? '-', strong: true));
      tone = UiTone.success;
      title = '가입 신청이 접수됐어요';
      desc = '은행 심사에 등록되었어요.';
      extra = const ApprovalTimeline(key: ValueKey('tl-done'));
      foot = AppButton('홈으로', onPressed: newCase);
    } else if (st == 'FAILED' || st == 'D_FAILED') {
      tone = UiTone.danger;
      title = '가입이 처리되지 않았어요';
      desc = appRec?.failureReason ?? '은행이 가입 요청을 처리하지 못했어요.';
      foot = ButtonRow([
        isJoin ? AppButton('상담 연결', kind: BtnKind.secondary, onPressed: app.join.escalateFailed) : AppButton('고객센터 1588-0000', kind: BtnKind.secondary, onPressed: () {}),
        AppButton('처음으로', onPressed: newCase),
      ]);
    } else if (st == 'RESULT_UNCERTAIN' || st == 'D_UNCERTAIN') {
      tone = UiTone.warning;
      title = '가입 결과를 아직 확인하지 못했어요';
      desc = '요청이 은행에 접수됐을 수 있어요. 다시 신청하면 중복 가입될 수 있어서, 결과 조회만 해요.';
      foot = AppButton('결과 다시 조회', onPressed: () => app.guard(isJoin ? 'join-query' : 'direct-query', isJoin ? app.join.queryResult : app.direct.queryResult));
    } else {
      tone = UiTone.neutral;
      title = '진행 중인 가입 요청이 없어요';
      desc = '';
      rows.clear();
      foot = AppButton('진행 상황 보기', onPressed: isJoin ? app.join.open : app.direct.open);
    }
    final toneIcon = switch (tone) {
      UiTone.success => AppIcons.check,
      UiTone.danger => AppIcons.x,
      UiTone.warning => AppIcons.clock,
      _ => AppIcons.info,
    };
    return ScreenFrame(
      white: true,
      appBar: const WspAppBar(title: '가입 결과', noBack: true),
      footer: foot,
      children: [
        ResultHead(tone: tone, icon: icon == null ? toneIcon : null, iconChild: icon, title: title, desc: desc.isEmpty ? null : desc, extra: extra),
        if (rows.isNotEmpty) CardBox(child: KvRows(rows)),
      ],
    );
  }
}

/// 해외주식 계좌 개설: 신청 접수 → 은행 승인 대기(약 5초) → 개설 완료
const List<String> _brokerSteps = ['신청 접수', '본인/조건 재확인', '은행 심사 등록', '은행 승인'];

/// 접수·심사 순서. [wait]이면 마지막 단계를 대기 표시(깜빡이는 점, '중')로 둔다.
class ApprovalTimeline extends StatefulWidget {
  const ApprovalTimeline({
    super.key,
    this.steps = const ['신청 접수', '본인/조건 재확인', '은행 심사 등록', '승인 대기'],
    this.wait = false,
    this.marks = false,
    this.gap = 0.55,
  });

  final List<String> steps;
  final bool wait;
  final bool marks;

  /// 단계 사이 등장 간격(초)
  final double gap;

  @override
  State<ApprovalTimeline> createState() => _ApprovalTimelineState();
}

class _ApprovalTimelineState extends State<ApprovalTimeline> with SingleTickerProviderStateMixin {
  late final AnimationController _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));

  @override
  void initState() {
    super.initState();
    if (widget.wait) _blink.repeat();
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < widget.steps.length; i++) {
      final waiting = widget.wait && i == widget.steps.length - 1;
      final text = Text('${widget.steps[i]}${waiting ? ' 중' : ''}', style: ts(14, color: waiting ? AppColors.text3 : AppColors.text2));
      final row = widget.marks
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                waiting
                    ? AnimatedBuilder(
                        animation: _blink,
                        builder: (context, child) => Opacity(opacity: _blink.value < 0.5 ? 1 : 0, child: child),
                        child: _dot(const Color(0xFFB7C2D0)),
                      )
                    : _dot(const Color(0xFF1FA463)),
                const SizedBox(width: 8),
                text,
              ],
            )
          : text;
      items.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: RiseIn(delay: Duration(milliseconds: (i * widget.gap * 1000).round()), duration: const Duration(milliseconds: 450), child: row),
      ));
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: widget.marks ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: items,
        ),
      ),
    );
  }

  Widget _dot(Color c) => Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle));
}

/* ==================================================================
 * 상담 연결 (가입 지원·자산관리 공용)
 * ================================================================== */

const Map<String, String> _reasonTitle = {
  'CUSTOMER_REQUEST': '고객님이 상담을 요청했어요',
  'BLOCKER': '앱에서 해결할 수 없는 조건이 있어요',
  'CYCLE': '앱 안에서는 순서가 막혀요',
  'NO_ROUTE': '앱 안에서 해결할 방법을 찾지 못했어요',
  'REPEAT': '같은 문제가 반복됐어요',
  'EXCEPTION': '업무 처리 결과를 확인하지 못했어요',
  'APPLY_FAILED': '가입이 처리되지 않았어요',
  'HOLD': '지금 정보로는 제안하기 어려워요',
  'QUERY_FAILED': '은행 기록을 확인하지 못했어요',
};

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key, required this.entry});

  final RouteEntry entry;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    final track = entry.params['track'] == 'asset' ? 'asset' : 'join';
    final d = app.supportCase(track);
    if (d == null || !app.supportValid(track)) {
      return EmptyScreen(title: '상담 연결', message: '상담 연결이 필요한 건이 없어요.', buttonLabel: '홈으로', onButton: app.goHome, onBack: app.back);
    }
    final esc8 = d.escalation ?? Escalation(reason: 'CUSTOMER_REQUEST', text: '');
    final h = d.handoff;
    final consult = d.consult;
    final accepted = consult?.status == 'ACCEPTED';
    final canSubmit = h != null && !accepted && d.handoffConsent;
    final cause = esc8.cause;
    final busy = app.isBusy('support-submit');

    return ScreenFrame(
      white: true,
      appBar: WspAppBar(title: '상담 연결', onBack: app.back),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!accepted) ...[
            AppButton(
              consult?.status == 'FAILED' ? '다시 접수하기' : '상담 접수하기',
              loading: busy,
              onPressed: canSubmit ? () => app.supportSubmit(track) : null,
            ),
            const SizedBox(height: 8),
          ],
          if (track == 'join')
            ButtonRow([
              AppButton('처음으로', kind: BtnKind.ghost, onPressed: app.join.newCase),
              AppButton('은행 기록 다시 확인', kind: BtnKind.secondary, onPressed: () => app.guard('join-recheck', app.join.recheckFromEscalated)),
            ])
          else
            AppButton('상담 종료', kind: BtnKind.ghost, onPressed: app.supportAssetEnd),
        ],
      ),
      children: [
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.blueLight, borderRadius: BorderRadius.circular(14)),
              child: SvgIcon(AppIcons.headset, size: 24, color: AppColors.blue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_reasonTitle[esc8.reason] ?? '상담이 필요해요', style: ts(17, weight: FontWeight.w700, letterSpacing: -0.02)),
                  if (esc8.text.isNotEmpty) ...[const SizedBox(height: 4), Text(esc8.text, style: ts(13.5, color: AppColors.text2, height: 1.5))],
                ],
              ),
            ),
          ],
        ),
        if (cause != null && cause.type == 'CYCLE') ...[
          const SizedBox(height: 12),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 6,
            children: [
              for (var i = 0; i < cause.chain.length; i++) ...[
                if (i > 0) SvgIcon(AppIcons.chevron, size: 14, color: AppColors.muted),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: AppColors.dangerBg, borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: Text(facts[cause.chain[i]]?.short ?? cause.chain[i], style: ts(12.5, weight: FontWeight.w700, color: AppColors.dangerText)),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: 16),
        if (h == null)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(AppRadius.card)),
            child: Row(children: [
              const Spinner(),
              const SizedBox(width: 10),
              Text('상담 요약을 정리하고 있어요', style: ts(14, color: AppColors.text2)),
            ]),
          )
        else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(AppRadius.card)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  SvgIcon(AppIcons.doc, size: 17, color: AppColors.text),
                  const SizedBox(width: 6),
                  Expanded(child: Text('상담 요약', style: ts(15, weight: FontWeight.w700))),
                  ToneBadge(accepted ? '전달됨' : '아직 접수 전', accepted ? UiTone.success : UiTone.neutral),
                ]),
                const SizedBox(height: 10),
                for (final l in h.lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text('· $l', style: ts(13.5, color: AppColors.text2, height: 1.5)),
                  ),
              ],
            ),
          ),
        if (!accepted) ...[
          const SizedBox(height: 12),
          InkWell(
            onTap: () => app.toggleSupportConsent(track),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    key: const ValueKey('support-consent'),
                    value: d.handoffConsent,
                    onChanged: (_) => app.toggleSupportConsent(track),
                    visualDensity: VisualDensity.compact,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text('위 요약을 상담사에게 전달하는 데 동의해요. 상담사가 처음부터 다시 묻지 않도록 쓰여요.', style: ts(13.5, height: 1.5)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (accepted) ...[
          const SizedBox(height: 12),
          CardBox(
            color: AppColors.successBg,
            outline: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CardTitle('상담이 접수됐어요', icon: AppIcons.check, color: AppColors.successText),
                KvRows([KvRow.text('접수 번호', consult!.ticket?.id ?? '-', strong: true), KvRow.text('안내', consult.ticket?.eta ?? '')]),
              ],
            ),
          ),
        ] else if (consult?.status == 'FAILED') ...[
          const SizedBox(height: 12),
          CardBox(
            color: AppColors.warningBg,
            outline: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CardTitle('상담 접수가 완료되지 않았어요', icon: AppIcons.alert, color: AppColors.warningText),
                Text('요약은 만들었지만 접수는 되지 않았어요. 아래 방법으로 다시 연결해 주세요.', style: ts(13.5, color: AppColors.warningText, height: 1.5)),
                const SizedBox(height: 8),
                const BulletList(['잠시 후 다시 접수하기', '고객센터 1588-0000', '가까운 영업점 방문 (신분증 지참)']),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
