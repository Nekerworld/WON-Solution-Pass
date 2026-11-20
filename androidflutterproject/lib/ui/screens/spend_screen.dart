import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/router.dart';
import '../../app/sessions.dart';
import '../../domain/formatters.dart';
import '../../domain/lumpsum_advisor.dart' as la;
import '../app_scope.dart';
import '../theme.dart';
import '../widgets.dart';

/// 하나의 막대에 항목을 색으로 나눠 담고, 아래 범례로 금액·비율을 읽어 준다
const Map<String, Color> spendColors = {
  '식비': Color(0xFF2488F3),
  '주거·관리': Color(0xFF1F9D7A),
  '교통': Color(0xFFF2A33A),
  '쇼핑': Color(0xFF7B61FF),
  '문화·여가': Color(0xFFEC5F8F),
  '기타': Color(0xFFB4BCC8),
};
const Color _otherColor = Color(0xFFB4BCC8);
const Color _mutedText = Color(0xFF7B8794);
const Color _chgFlat = Color(0xFF8A94A3);

String spendChangeText(int pct) => '${pct > 0 ? '+' : pct < 0 ? '-' : ''}${pct.abs()}%';

class SpendSnapshot {
  const SpendSnapshot({required this.expense, required this.categories, required this.insight});
  final int expense;
  final List<la.SpendCategory> categories;
  final la.SpendInsight insight;
}

/// 지금 페르소나의 월 지출로 소비 분석을 만든다. 목돈 상담 중이면 채팅 시작 때 값을 쓴다
SpendSnapshot currentSpend(AppController app) {
  final expense = app.session.lumpsum?.snap.expense ?? app.store.state.finance.items['monthlyExpense']?.value ?? 0;
  final cats = la.categories(expense);
  return SpendSnapshot(expense: expense, categories: cats, insight: la.spendInsight(cats));
}

class _ChangeBadge extends StatelessWidget {
  const _ChangeBadge(this.pct);

  final int pct;

  @override
  Widget build(BuildContext context) {
    final color = pct > 0 ? AppColors.danger : (pct < 0 ? AppColors.blue : _chgFlat);
    return SizedBox(
      width: 44,
      child: Text(
        spendChangeText(pct),
        textAlign: TextAlign.right,
        style: ts(12, weight: FontWeight.w700, color: color).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
  }
}

/// [fresh]: 처음 그려질 때 막대가 차오른다. [insight]: 출처 라벨과 지난달 대비 증감을 함께 보여 준다.
class SpendStack extends StatelessWidget {
  const SpendStack({super.key, required this.categories, this.insight, this.fresh = false});

  final List<la.SpendCategory> categories;
  final la.SpendInsight? insight;
  final bool fresh;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) return const SizedBox.shrink();
    final ins = insight;
    Color color(la.SpendCategory c) => spendColors[c.label] ?? _otherColor;
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: SizedBox(
        height: 14,
        child: Row(
          children: [
            for (var i = 0; i < categories.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                flex: (categories[i].ratio * 1000).round().clamp(1, 1000000),
                child: Container(constraints: const BoxConstraints(minWidth: 4), color: color(categories[i])),
              ),
            ],
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ins != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(ins.source, style: ts(12, color: _mutedText)),
          ),
        fresh
            ? TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 700),
                curve: Curves.ease,
                builder: (context, t, child) => ClipRect(child: Align(alignment: Alignment.centerLeft, widthFactor: t, child: child)),
                child: bar,
              )
            : bar,
        const SizedBox(height: 12),
        for (var i = 0; i < categories.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
            child: _legendRow(categories[i], color(categories[i]), ins),
          ),
      ],
    );
  }

  Widget _legendRow(la.SpendCategory c, Color dot, la.SpendInsight? ins) {
    final row = ins?.rows.where((x) => x.label == c.label).firstOrNull;
    return Row(
      children: [
        SizedBox(
          width: 12,
          child: Container(width: 10, height: 10, decoration: BoxDecoration(color: dot, borderRadius: BorderRadius.circular(3))),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(c.label, style: ts(13.5))),
        const SizedBox(width: 8),
        Text(
          '${formatWon(c.amount)} · ${(c.ratio * 100).round()}%',
          style: ts(13.5, weight: FontWeight.w700).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        if (ins != null) ...[const SizedBox(width: 8), row != null ? _ChangeBadge(row.changePct) : const SizedBox(width: 44)],
      ],
    );
  }
}

class PatternTags extends StatelessWidget {
  const PatternTags(this.tags, {super.key});

  final List<la.SpendTag> tags;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final t in tags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xFFEEF4FD), borderRadius: BorderRadius.circular(AppRadius.pill)),
            child: Text(t.text, style: ts(12.5, weight: FontWeight.w600, color: const Color(0xFF1C5FB8))),
          ),
      ],
    );
  }
}

/// 소비 분석 화면 (screens/spend.js)
class SpendScreen extends StatelessWidget {
  const SpendScreen({super.key, required this.entry});

  final RouteEntry entry;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    return ListenableBuilder(
      listenable: app.store,
      builder: (context, _) {
        final c = currentSpend(app);
        return ScreenFrame(
          white: true,
          appBar: WspAppBar(title: '소비 분석', onBack: app.goBack),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('이번 달 소비', style: ts(13, color: _mutedText)),
                  const SizedBox(height: 4),
                  Text(formatWon(c.expense), style: ts(26, weight: FontWeight.w800)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            CardBox(child: SpendStack(categories: c.categories, insight: c.insight, fresh: true)),
            const SizedBox(height: 12),
            CardBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _cardTitle('지난달과 비교'),
                  const SizedBox(height: 8),
                  _CompareList(c.insight),
                ],
              ),
            ),
            const SizedBox(height: 12),
            CardBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _cardTitle('소비 패턴'),
                  PatternTags(c.insight.tags),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _GoalCard(app.session.spendGoal),
          ],
        );
      },
    );
  }
}

Widget _cardTitle(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text, style: ts(16, weight: FontWeight.w700, letterSpacing: -0.02)),
    );

class _CompareList extends StatelessWidget {
  const _CompareList(this.insight);

  final la.SpendInsight insight;

  @override
  Widget build(BuildContext context) {
    final rows = [...insight.rows]..sort((x, y) => y.changePct.compareTo(x.changePct));
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
            child: Row(
              children: [
                Expanded(child: Text(rows[i].label, style: ts(13.5))),
                const SizedBox(width: 6),
                Text(formatWon(rows[i].prev), style: ts(13.5, color: _chgFlat)),
                const SizedBox(width: 6),
                SizedBox(width: 14, child: Text('→', textAlign: TextAlign.center, style: ts(13.5, color: _otherColor))),
                const SizedBox(width: 6),
                Text(formatWon(rows[i].amount), style: ts(13.5, weight: FontWeight.w700)),
                const SizedBox(width: 6),
                _ChangeBadge(rows[i].changePct),
              ],
            ),
          ),
      ],
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard(this.goal);

  final SpendGoal? goal;

  @override
  Widget build(BuildContext context) {
    final g = goal;
    if (g == null) {
      return CardBox(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle('줄이기 목표'),
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 2),
              child: Text('아직 설정한 목표가 없어요.', style: ts(14, weight: FontWeight.w700)),
            ),
            Text('AI 자산관리 상담에서 지출 점검을 받으면 줄이기 계획을 저장할 수 있어요.', style: ts(12.5, color: _mutedText, height: 1.5)),
          ],
        ),
      );
    }
    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _cardTitle('줄이기 목표'),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 10),
            child: Text.rich(
              TextSpan(children: [
                const TextSpan(text: '매달 '),
                TextSpan(text: formatMan(g.total), style: weightStyle(FontWeight.w700, color: AppColors.blue)),
                const TextSpan(text: ' 줄이기'),
              ]),
              style: ts(18),
            ),
          ),
          for (var i = 0; i < g.items.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
              child: Row(
                children: [
                  Expanded(child: Text(g.items[i].label, style: ts(13.5))),
                  Text('월 ${formatMan(g.items[i].saved)}', style: ts(13.5, weight: FontWeight.w700)),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Text('이번 달 아낀 돈 0원 / 목표 ${formatMan(g.total)}', style: ts(12.5, color: _mutedText)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: const SizedBox(
              height: 8,
              child: ColoredBox(
                color: Color(0xFFE8EDF3),
                child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: 0, child: ColoredBox(color: AppColors.blue)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: '줄인 뒤 월 여유 '),
              TextSpan(text: la.manSigned(g.after), style: weightStyle(FontWeight.w700)),
            ]),
            style: ts(13.5),
          ),
        ],
      ),
    );
  }
}
