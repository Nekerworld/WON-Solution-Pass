import 'package:flutter/material.dart';

import '../../app/overlays.dart';
import '../../app/router.dart';
import '../../domain/chatbot_nlu.dart';
import '../../domain/formatters.dart';
import '../../domain/pathfinder.dart';
import '../../domain/rule_engine.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets.dart';

enum _StepMode { done, current, locked }

class _StepItem {
  const _StepItem(this.actionId, this.mode, this.ctx, [this.lockReason = '']);

  final String actionId;
  final _StepMode mode;
  final RuleContext ctx;
  final String lockReason;
}

class PlanScreen extends StatelessWidget {
  const PlanScreen({super.key, required this.entry});

  final RouteEntry entry;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    final s = app.session;
    final plan = s.plan;
    final caseCtx = s.caseCtx;
    final refresh = AppIconButton(icon: AppIcons.refresh, label: '상태 다시 확인', onTap: app.planRecheck);

    if (plan == null || caseCtx == null || plan.evaluation == null) {
      return ScreenFrame(
        appBar: WspAppBar(title: 'WON 해결패스', onBack: app.back),
        footer: AppButton('현재 상태 확인하기', size: BtnSize.lg, onPressed: app.openPass),
        children: [
          ResultHead(
            tone: UiTone.neutral,
            icon: AppIcons.spark,
            title: '진행 중인 해결 계획이 없어요',
            desc: '현재 이체 요청과 은행 상태를 확인해 필요한 절차가 있는지 알려드릴게요.',
          ),
        ],
      );
    }

    final ev = plan.evaluation!;
    final ctx = ev.ctx;
    final currentIds = plan.actionSteps.map((x) => x.actionId).toList();
    final doneIds = caseCtx.timeline.where((id) {
      final act = getAction(id);
      return !currentIds.contains(id) && act?.resolves != null && ev.facts[act!.resolves] == true;
    }).toList();

    final items = <_StepItem>[
      for (final id in doneIds) _StepItem(id, _StepMode.done, ctx),
      for (var i = 0; i < plan.actionSteps.length; i++)
        _StepItem(
          plan.actionSteps[i].actionId,
          i == 0 ? _StepMode.current : _StepMode.locked,
          ctx,
          i > 0 ? '${getAction(plan.actionSteps[i - 1].actionId)!.label}을 마친 뒤 진행할 수 있어요. (사전 조건)' : '',
        ),
      _StepItem(
        'RETURN_TO_TRANSFER',
        plan.status == PlanStatus.ready ? _StepMode.current : _StepMode.locked,
        ctx,
        '모든 사전 조건이 확인되면 원래 이체로 돌아갈 수 있어요.',
      ),
    ];

    final n = plan.actionSteps.length;
    final ready = plan.status == PlanStatus.ready;
    final String eyebrow;
    final String heroTitle;
    if (ready) {
      eyebrow = '사전 조건 확인 완료';
      heroTitle = doneIds.isNotEmpty
          ? '이체 사전 조건을 모두 확인했어요.\n원래 이체로 돌아가 직접 승인해 주세요.'
          : '추가 절차 없이 이체할 수 있어요.\n원래 이체에서 직접 승인해 주세요.';
    } else if (doneIds.isNotEmpty) {
      eyebrow = '해결 계획';
      heroTitle = '${formatMan(ctx.amount)} 이체까지\n남은 설정은 ${countWord(n)} 가지예요.';
    } else {
      eyebrow = '해결 계획';
      heroTitle = '${formatMan(ctx.amount)} 이체를 진행하려면\n다음 ${countWord(n)} 가지 설정이 필요합니다.';
    }

    final checkedAt = ctx.checkedAt != null ? formatClock(DateTime.fromMillisecondsSinceEpoch(ctx.checkedAt!)) : '-';

    return ScreenFrame(
      appBar: WspAppBar(title: 'WON 해결패스', onBack: app.back, right: refresh),
      children: [
        _PlanHero(eyebrow: eyebrow, title: heroTitle, ready: ready, pills: ev.requirements.map((r) => r.title).toList()),
        if (entry.params['rechecking'] == true) const _RecheckBar(),
        const SizedBox(height: 12),
        CardBox(
          tight: true,
          child: Row(
            children: [
              Avatar(ctx.recipient ?? '?'),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${ctx.recipient}님에게 ${formatWon(ctx.amount)}\n', style: ts(15, weight: FontWeight.w700)),
                    TextSpan(text: '${ctx.recipientBank} · 원래 이체 정보는 그대로 유지돼요'),
                  ]),
                  style: ts(13, color: AppColors.text2, height: 1.45),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        KeyedSubtree(
          key: ValueKey('steps-${entry.version}'),
          child: Column(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                RiseIn(delay: Duration(milliseconds: i * 60), child: _StepCard(item: items[i], index: i)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        NoticeBox(body: 'AI는 OTP 번호나 비밀번호를 묻지 않아요. 인증과 이체 승인은 은행 화면에서 직접 진행해요.', icon: AppIcons.lock),
        const SizedBox(height: 16),
        _PlanMeta(
          firedRules: ev.firedRules,
          policyVersion: ev.policyVersion,
          stateVersion: ctx.stateVersion,
          checkedAt: checkedAt,
          visited: plan.visited,
          cost: plan.cost,
          caseId: caseCtx.caseId,
        ),
        const SizedBox(height: 12),
        Center(child: LinkButton('궁금한 점이 있나요? 질문하기', onTap: app.goChat)),
      ],
    );
  }
}

class _PlanHero extends StatelessWidget {
  const _PlanHero({required this.eyebrow, required this.title, required this.ready, required this.pills});

  final String eyebrow;
  final String title;
  final bool ready;
  final List<String> pills;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.cardLg),
        gradient: LinearGradient(
          begin: const Alignment(-0.6, -1),
          end: const Alignment(0.6, 1),
          colors: ready ? const [Color(0xFF13906A), Color(0xFF0C6D55)] : const [AppColors.blue, Color(0xFF0A4F8F)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Opacity(
            opacity: 0.85,
            child: Row(
              children: [
                SvgIcon(AppIcons.spark, size: 14, color: Colors.white),
                const SizedBox(width: 6),
                Text(eyebrow, style: ts(12, weight: FontWeight.w700, color: Colors.white)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(title, style: ts(19, weight: FontWeight.w700, color: Colors.white, height: 1.4, letterSpacing: -0.03)),
          if (pills.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in pills)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(AppRadius.pill)),
                    child: Text(p, style: ts(12, weight: FontWeight.w700, color: Colors.white)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RecheckBar extends StatelessWidget {
  const _RecheckBar();

  @override
  Widget build(BuildContext context) {
    return FadeIn(
      duration: const Duration(milliseconds: 200),
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: AppColors.blueLight, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            const Spinner(),
            const SizedBox(width: 10),
            Expanded(child: Text('변경된 상태를 은행에서 다시 확인하고 있어요', style: ts(13, weight: FontWeight.w700, color: AppColors.blueDark))),
          ],
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({required this.item, required this.index});

  final _StepItem item;
  final int index;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    final a = getAction(item.actionId)!;
    final d = describeStep(item.actionId, item.ctx);
    final mode = item.mode;

    final (numBg, numFg) = switch (mode) {
      _StepMode.done => (AppColors.success, Colors.white),
      _StepMode.current => (AppColors.blue, Colors.white),
      _StepMode.locked => (AppColors.neutralBg, AppColors.text2),
    };
    final badge = switch (mode) {
      _StepMode.done => const ToneBadge('완료', UiTone.success),
      _StepMode.current => const ToneBadge('지금 할 일', UiTone.info),
      _StepMode.locked => const ToneBadge('대기', UiTone.neutral),
    };

    Widget body;
    if (mode == _StepMode.current) {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StepGrid(rows: [
            ('해결할 문제', d.problem),
            ('현재 상태', d.current),
            ('필요한 행동', d.action),
            ('예상 결과', d.expected),
          ]),
          const SizedBox(height: 14),
          AppButton(
            a.cta,
            onPressed: item.actionId == 'RETURN_TO_TRANSFER' ? app.returnToTransfer : () => app.openFlow(a.flowId),
          ),
          if (d.ruleIds.isNotEmpty) ...[
            const SizedBox(height: 8),
            _Note('근거 규칙 ${d.ruleIds.join(' · ')} (데모용 가상 정책)'),
          ],
        ],
      );
    } else if (mode == _StepMode.done) {
      body = _Note('${d.current} · 은행 상태 재조회로 확인됨 (상태 v${item.ctx.stateVersion})');
    } else {
      body = _Note(item.lockReason.isNotEmpty ? item.lockReason : '이전 단계를 마치면 진행할 수 있어요.');
    }

    return Opacity(
      opacity: mode == _StepMode.locked ? 0.78 : 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: mode == _StepMode.done ? const Color(0xFFFAFCFB) : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            width: 1.5,
            color: switch (mode) {
              _StepMode.current => AppColors.blue,
              _StepMode.done => AppColors.line,
              _StepMode.locked => Colors.transparent,
            },
          ),
          boxShadow: switch (mode) {
            _StepMode.current => const [BoxShadow(color: Color(0x242488F3), blurRadius: 20, offset: Offset(0, 6))],
            _StepMode.done => null,
            _StepMode.locked => shadowCard,
          },
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: numBg, shape: BoxShape.circle),
                    child: mode == _StepMode.done
                        ? SvgIcon(AppIcons.check, size: 16, color: numFg)
                        : Text('${index + 1}', style: ts(13, weight: FontWeight.w700, color: numFg)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      a.label,
                      style: ts(15, weight: FontWeight.w700, letterSpacing: -0.02, color: mode == _StepMode.done ? AppColors.text2 : AppColors.text),
                    ),
                  ),
                  badge,
                ],
              ),
            ),
            Padding(padding: const EdgeInsets.fromLTRB(50, 0, 16, 16), child: body),
          ],
        ),
      ),
    );
  }
}

class _StepGrid extends StatelessWidget {
  const _StepGrid({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Table(
      columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
      children: [
        for (final (k, v) in rows)
          TableRow(children: [
            Padding(
              padding: const EdgeInsets.only(right: 12, bottom: 6),
              child: Text(k, style: ts(13, weight: FontWeight.w700, color: AppColors.text3, height: 1.5)),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(v, style: ts(13, height: 1.5)),
            ),
          ]),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(text, style: ts(12, color: AppColors.text3)),
    );
  }
}

class _PlanMeta extends StatelessWidget {
  const _PlanMeta({
    required this.firedRules,
    required this.policyVersion,
    required this.stateVersion,
    required this.checkedAt,
    required this.visited,
    required this.cost,
    required this.caseId,
  });

  final List<String> firedRules;
  final String policyVersion;
  final int stateVersion;
  final String checkedAt;
  final int visited;
  final int? cost;
  final String caseId;

  @override
  Widget build(BuildContext context) {
    WidgetSpan code(String t) => WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(color: AppColors.neutralBg, borderRadius: BorderRadius.circular(4)),
            child: Text(t, style: monoStyle(11)),
          ),
        );
    return CustomPaint(
      painter: const _DashedBorderPainter(),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Text.rich(
          TextSpan(children: [
            const TextSpan(text: '근거 규칙 '),
            if (firedRules.isEmpty) code('없음'),
            for (final r in firedRules) ...[code(r), const TextSpan(text: ' ')],
            const TextSpan(text: '\n정책 '),
            code(policyVersion),
            const TextSpan(text: ' 데모용 가상 정책 · 실제 은행 정책 아님\n상태 버전 '),
            code('v$stateVersion'),
            TextSpan(text: ' · $checkedAt 조회 · 상태 그래프 $visited개 상태${cost != null ? ' · 최소 비용 경로 $cost' : ''}\n사건 번호 '),
            code(caseId),
          ]),
          style: ts(11.5, color: AppColors.text3, height: 1.7),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12));
    canvas.drawRRect(rrect, Paint()..color = Colors.white);
    final path = Path()..addRRect(rrect.deflate(0.5));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = AppColors.lineStrong;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 3), paint);
        d += 6;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) => false;
}
