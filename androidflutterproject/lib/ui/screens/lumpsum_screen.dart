import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../app/app_controller.dart';
import '../../app/router.dart';
import '../../app/sessions.dart';
import '../../domain/asset_advisor.dart' as aa;
import '../../domain/formatters.dart';
import '../../domain/lumpsum_advisor.dart' as la;
import '../../domain/lumpsum_script.dart' as ls;
import '../app_scope.dart';
import '../chat_parts.dart';
import '../icons.dart';
import '../responsive.dart';
import '../theme.dart';
import '../widgets.dart';

const Color _chatBg = Color(0xFFF8F9FB);
const Color _blockLine = Color(0xFFE3E9F1);
const List<BoxShadow> _softShadow = [BoxShadow(color: Color(0x0D1E3C6E), blurRadius: 10, offset: Offset(0, 2))];

/// 소비 막대 색 (소비 분석 화면과 같은 팔레트)
const Map<String, Color> _spendColors = {
  '식비': Color(0xFF2488F3),
  '주거·관리': Color(0xFF1F9D7A),
  '교통': Color(0xFFF2A33A),
  '쇼핑': Color(0xFF7B61FF),
  '문화·여가': Color(0xFFEC5F8F),
  '기타': Color(0xFFB4BCC8),
};
const Color _spendFallback = Color(0xFFB4BCC8);

/// 한 번이라도 그려진 블록. 처음 그려질 때만 나타나는 연출을 넣는다 (화면을 다시 열어도 반복하지 않는다)
final Set<String> _seenBlocks = {};

/// 목돈 불리기 채팅 화면 (screens/lumpsum.js)
class LumpsumScreen extends StatefulWidget {
  const LumpsumScreen({super.key, required this.entry});

  final RouteEntry entry;

  @override
  State<LumpsumScreen> createState() => _LumpsumScreenState();
}

class _LumpsumScreenState extends State<LumpsumScreen> {
  final _scroll = ScrollController();
  final _logKey = GlobalKey();
  int _msgCount = 0;

  /// 사용자가 위로 올려 읽는 중이면 그때의 메시지 수. 새 메시지가 오면 풀린다.
  int _hold = 0;

  /// 화면이 직접 스크롤을 움직이는 동안은 사용자 조작으로 보지 않는다
  int _driving = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 짧은 메시지는 첫 줄을 위에 맞추고, 화면보다 길어지면 지금 생성되는 끝 줄을 따라간다
  double? _followTarget() {
    final ctx = _logKey.currentContext;
    final flex = ctx?.findRenderObject();
    if (flex is! RenderFlex || !flex.attached) return null;
    final last = flex.lastChild;
    if (last == null || !last.attached || !last.hasSize) return null;
    final vp = RenderAbstractViewport.maybeOf(last);
    if (vp == null) return null;
    final top = vp.getOffsetToReveal(last, 0).offset;
    final bottom = vp.getOffsetToReveal(last, 1).offset;
    return math.max(0, math.max(top - 12, bottom + 28));
  }

  void _follow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (_hold != 0 && _hold == _msgCount) return;
      final target = _followTarget();
      if (target == null) return;
      final pos = _scroll.position;
      final to = target.clamp(pos.minScrollExtent, pos.maxScrollExtent).toDouble();
      final d = to - pos.pixels;
      if (d.abs() < 1) return;
      _driving += 1;
      if (d.abs() > pos.viewportDimension * 1.2) {
        pos.jumpTo(to);
        _driving -= 1;
      } else {
        pos.animateTo(to, duration: const Duration(milliseconds: 220), curve: Curves.easeOut).whenComplete(() => _driving -= 1);
      }
    });
  }

  bool _onScroll(ScrollNotification n) {
    if (_driving > 0) return false;
    if (n is ScrollUpdateNotification || n is ScrollEndNotification) {
      final t = _followTarget();
      if (t != null && _scroll.hasClients) _hold = _scroll.position.pixels < t - 60 ? _msgCount : 0;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    final s = app.session.lumpsum;
    final st = app.lumpsum.fsm.state;
    if (s == null || st == 'IDLE') {
      return EmptyScreen(
        title: 'AI 자산관리 상담',
        message: '진행 중인 상담이 없어요.',
        buttonLabel: '상담 시작',
        onButton: () => app.lumpsum.startNew(),
        onBack: app.back,
      );
    }
    final ended = st == 'CLOSED' || st == 'TO_JOIN';
    final viewSpend = ended && app.session.spendGoal != null && s.advice?.decisionId == 'SPEND_CHECK';
    final side = wideInsetOf(context);
    _msgCount = s.chat.length;
    _follow();
    return Material(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _LumpHeader(name: app.store.state.customer.name, onBack: app.back, onEnd: () => unawaited(app.lumpsum.end())),
            Expanded(
              child: Material(
                color: _chatBg,
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScroll,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: EdgeInsets.fromLTRB(18 + side, 14, 18 + side, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ChatIntro(service: 'AI 자산관리 상담', customerName: app.store.state.customer.name, startedAt: s.chat.isNotEmpty ? s.chat.first.at : null),
                        Column(
                          key: _logKey,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          spacing: 14,
                          children: [
                            for (final m in s.chat)
                              RiseIn(
                                key: ValueKey('m${m.id}'),
                                duration: const Duration(milliseconds: 250),
                                child: m.role == 'user' ? _UserMessage(m.text) : _BotMessage(row: m, onToggle: () => app.lumpsum.toggle(m.id), onLink: (a) => _link(app, a)),
                              ),
                          ],
                        ),
                        if (s.thinking) Padding(padding: const EdgeInsets.only(top: 14), child: _Thinking(label: s.thinkLabel.isEmpty ? '확인하고 있어요' : s.thinkLabel)),
                        if (ended)
                          RiseIn(
                            key: const ValueKey('lump-act'),
                            duration: const Duration(milliseconds: 250),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (viewSpend) ...[
                                    AppButton('소비 분석에서 보기', kind: BtnKind.secondary, onPressed: () => app.navigate(ScreenId.spend)),
                                    const SizedBox(height: 8),
                                  ],
                                  AppButton('새 상담 시작', onPressed: () => app.lumpsum.startNew()),
                                ],
                              ),
                            ),
                          )
                        else if (s.prompt.choices.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 2,
                              children: [
                                for (final c in s.prompt.choices) _ChoiceChip(c.text, onTap: () => unawaited(app.lumpsum.choice(c.id, c.text))),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (!ended) _Composer(s: s, onField: app.lumpsum.startTyping, onSend: app.lumpsum.send),
          ],
        ),
      ),
    );
  }

  void _link(AppController app, String action) {
    if (action == 'spend-open') unawaited(app.navigate(ScreenId.spend));
  }
}

/* ==================================================================
 * 머리
 * ================================================================== */

class _LumpHeader extends StatelessWidget {
  const _LumpHeader({required this.name, required this.onBack, required this.onEnd});

  final String name;
  final VoidCallback onBack;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final side = wideInsetOf(context);
    return Column(
      children: [
        WspAppBar(title: '$name님의 해결패스', onBack: onBack, right: const _AiBadge()),
        Container(
          height: 38,
          padding: EdgeInsets.fromLTRB(12 + side, 0, 12 + side, 0),
          alignment: Alignment.centerRight,
          decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Color(0xFFEEF0F3)))),
          child: Semantics(
            button: true,
            label: '상담 종료',
            child: InkWell(
              onTap: onEnd,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgIcon(AppIcons.refresh, size: 15, color: Color(0xFF5A636C)),
                    const SizedBox(width: 4),
                    Text('상담 종료', style: ts(12.5, weight: FontWeight.w700, color: const Color(0xFF5A636C))),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AiBadge extends StatelessWidget {
  const _AiBadge();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 42,
        height: 42,
        margin: const EdgeInsets.only(right: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.aiBadgeFrom, AppColors.aiBadgeTo]),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('AI', style: ts(15, weight: FontWeight.w700, color: Colors.white, height: 1.1)),
            Text('챗봇', style: ts(9, color: Colors.white, height: 1.15)),
          ],
        ),
      ),
    );
  }
}

/* ==================================================================
 * 메시지
 * ================================================================== */

class _UserMessage extends StatelessWidget {
  const _UserMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Align(
        alignment: Alignment.centerRight,
        child: FractionallySizedBox(
          widthFactor: 0.86,
          alignment: Alignment.centerRight,
          child: Text('"$text"', textAlign: TextAlign.right, style: ts(15, weight: FontWeight.w700, color: AppColors.blue, height: 1.5)),
        ),
      ),
    );
  }
}

/// 굵게 표시(**글자**)만 바꾼다. 줄바꿈은 글자 그대로 둔다.
List<InlineSpan> _rich(String text) {
  final out = <InlineSpan>[];
  var last = 0;
  for (final m in RegExp(r'\*\*(.+?)\*\*').allMatches(text)) {
    if (m.start > last) out.add(TextSpan(text: text.substring(last, m.start)));
    out.add(bold(m.group(1)!));
    last = m.end;
  }
  if (last < text.length) out.add(TextSpan(text: text.substring(last)));
  return out;
}

String _sec(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

class _BotMessage extends StatelessWidget {
  const _BotMessage({required this.row, required this.onToggle, required this.onLink});

  final LumpRow row;
  final VoidCallback onToggle;
  final void Function(String action) onLink;

  @override
  Widget build(BuildContext context) {
    final live = row.streaming;
    // 블록이 없는 옛 메시지는 문장 하나로 보여 준다
    final blocks = row.blocks.isEmpty ? [ls.LBlock('text', text: row.text)] : row.blocks;
    final shown = row.blocks.isEmpty ? 1 : row.shown;
    final visible = [for (var i = 0; i < blocks.length; i++) if (i < shown || (live && row.cur == i)) i];
    final kids = <Widget>[];
    for (var n = 0; n < visible.length; n++) {
      final i = visible[n];
      final b = blocks[i];
      final key = '${row.id}:$i';
      final fresh = b.t != 'text' && _seenBlocks.add(key);
      var w = _block(b, i, key, fresh, live, first: n == 0, last: n == visible.length - 1);
      if (w == null) continue;
      if (b.t != 'text') w = _BlkIn(fresh: fresh, child: w);
      // 카드 위 간격: 큰 숫자는 12, 나머지는 10
      if (kids.isNotEmpty && b.t != 'figures') kids.add(const SizedBox(height: 10));
      kids.add(w);
    }
    final thought = !live && row.thoughtMs != 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BotAvatar(size: 32),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: _softShadow),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...kids,
              if (thought) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${_sec(row.thoughtMs)}초 동안 생각했어요', style: ts(12, color: AppColors.text3))),
            ],
          ),
        ),
      ],
    );
  }

  Widget? _block(ls.LBlock b, int i, String key, bool fresh, bool live, {required bool first, required bool last}) {
    switch (b.t) {
      case 'text':
        final partial = live && row.cur == i;
        final text = partial ? row.curText : b.text;
        return Text.rich(
          TextSpan(
            style: ts(14, height: 1.65),
            children: [
              ..._rich(text),
              if (partial) const WidgetSpan(alignment: PlaceholderAlignment.middle, child: _Caret(height: 14, margin: 1)),
            ],
          ),
        );
      case 'steps':
        if (b.items.isEmpty) return null;
        return Padding(
          padding: EdgeInsets.only(top: first ? 8 : 0, bottom: last ? 8 : 0),
          child: _StepsView(items: b.items, fresh: fresh),
        );
      case 'details':
        return _Details(row: row, block: b, stackKey: '$key:stack', onToggle: onToggle);
      case 'link':
        return AppButton(b.label, kind: BtnKind.secondary, onPressed: () => onLink(b.action));
      case 'tags':
        if (b.tags.isEmpty) return null;
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in b.tags)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xFFEEF4FD), borderRadius: BorderRadius.circular(AppRadius.pill)),
                child: Text(t.text, style: ts(12.5, weight: FontWeight.w700, color: const Color(0xFF1C5FB8))),
              ),
          ],
        );
      case 'figures':
        if (b.figures.isEmpty) return null;
        return Padding(padding: const EdgeInsets.only(top: 12), child: _Figs(b.figures));
    }
    return null;
  }
}

/// 처음 나올 때만 살짝 올라오며 나타난다 (CSS blk-in)
class _BlkIn extends StatefulWidget {
  const _BlkIn({required this.fresh, required this.child});

  final bool fresh;
  final Widget child;

  @override
  State<_BlkIn> createState() => _BlkInState();
}

class _BlkInState extends State<_BlkIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 450), value: widget.fresh ? 0 : 1);

  @override
  void initState() {
    super.initState();
    if (widget.fresh) _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.ease.transform(_c.value);
        return Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 6 * (1 - t)), child: child));
      },
      child: widget.child,
    );
  }
}

/// 깜박이는 세로 막대 (글자 흐름 · 입력 중)
class _Caret extends StatefulWidget {
  const _Caret({required this.height, this.margin = 0});

  final double height;
  final double margin;

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Opacity(
        opacity: _c.value < 0.5 ? 1 : 0,
        child: Container(width: 2, height: widget.height, margin: EdgeInsets.only(left: widget.margin), color: AppColors.blue),
      ),
    );
  }
}

/// 분석 단계. 처음 나올 때는 돌다가 하나씩 체크로 바뀐다
class _StepsView extends StatefulWidget {
  const _StepsView({required this.items, required this.fresh});

  final List<String> items;
  final bool fresh;

  @override
  State<_StepsView> createState() => _StepsViewState();
}

class _StepsViewState extends State<_StepsView> with SingleTickerProviderStateMixin {
  late final double _total = (widget.items.length - 1) * 0.7 + 0.8;
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(milliseconds: (_total * 1000).round()), value: widget.fresh ? 0 : 1);

  @override
  void initState() {
    super.initState();
    if (widget.fresh) _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fresh = widget.fresh;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final e = _c.value * _total;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < widget.items.length; i++)
              Builder(builder: (context) {
                final t = e - i * 0.7;
                final done = !fresh || t >= 0.6;
                return Opacity(
                  opacity: fresh ? (t / 0.3).clamp(0.0, 1.0) : 1,
                  child: Padding(
                    padding: EdgeInsets.only(top: i == 0 ? 0 : 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CustomPaint(painter: _StepMarkPainter(done: done, spin: (t / 0.7).clamp(0.0, 1.0), check: fresh ? ((t - 0.6) / 0.2).clamp(0.0, 1.0) : 1)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(widget.items[i], style: ts(13.5, color: AppColors.text2))),
                      ],
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

class _StepMarkPainter extends CustomPainter {
  _StepMarkPainter({required this.done, required this.spin, required this.check});

  final bool done;
  final double spin;
  final double check;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = done ? AppColors.blue : const Color(0xFFCFE0F7);
    canvas.drawOval(rect, ring);
    if (!done) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.butt
        ..color = AppColors.blue;
      canvas.drawArc(rect, -math.pi / 2 - math.pi / 4 + spin * math.pi * 2, math.pi / 2, false, arc);
      return;
    }
    if (check <= 0) return;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = AppColors.blue.withValues(alpha: check);
    final path = Path()
      ..moveTo(size.width * 0.29, size.height * 0.52)
      ..lineTo(size.width * 0.45, size.height * 0.68)
      ..lineTo(size.width * 0.72, size.height * 0.34);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(_StepMarkPainter old) => old.done != done || old.spin != spin || old.check != check;
}

/// 큰 숫자 카드 (둘일 때는 2열)
class _Figs extends StatelessWidget {
  const _Figs(this.figures);

  final List<aa.Figure> figures;

  Widget _card(aa.Figure f, double valueSize) {
    final warn = f.tone == 'warning';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: shadowCard),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(f.label, style: ts(14, color: AppColors.text2)),
          const SizedBox(height: 2),
          Text(f.value, style: ts(valueSize, weight: FontWeight.w700, letterSpacing: -0.02).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
          if (f.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(f.note, style: ts(13.5, weight: warn ? FontWeight.w700 : FontWeight.w400, color: warn ? const Color(0xFFA55F00) : AppColors.text2, height: 1.5)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (figures.length == 2) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _card(figures[0], 20)),
            const SizedBox(width: 8),
            Expanded(child: _card(figures[1], 20)),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [for (final f in figures) _card(f, 26)],
    );
  }
}

/* ==================================================================
 * 펼침(지출 줄이기 제안 · 소비 막대)
 * ================================================================== */

class _Details extends StatelessWidget {
  const _Details({required this.row, required this.block, required this.stackKey, required this.onToggle});

  final LumpRow row;
  final ls.LBlock block;
  final String stackKey;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final open = row.open;
    final Widget? body;
    if (!open) {
      body = null;
    } else if (block.cuts != null) {
      body = RiseIn(duration: const Duration(milliseconds: 350), child: _CutList(block.cuts!));
    } else {
      final cats = block.categories ?? const <la.SpendCategory>[];
      body = cats.isEmpty ? null : _SpendStack(categories: cats, fresh: _seenBlocks.add(stackKey), insight: block.insight ? la.spendInsight(cats) : null);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: open,
          child: Material(
            color: const Color(0xFFF6F9FD),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: _blockLine)),
            child: InkWell(
              onTap: onToggle,
              customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Expanded(child: Text(block.label, style: ts(13.5, weight: FontWeight.w700))),
                    AnimatedRotation(
                      turns: open ? -0.375 : 0.125,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          border: Border(
                            right: BorderSide(color: AppColors.text3, width: 2),
                            bottom: BorderSide(color: AppColors.text3, width: 2),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        ?body,
      ],
    );
  }
}

class _CutList extends StatelessWidget {
  const _CutList(this.cuts);

  final List<ls.CutRow> cuts;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _blockLine)),
      child: Column(
        children: [
          for (var i = 0; i < cuts.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(border: i == cuts.length - 1 ? null : const Border(bottom: BorderSide(color: Color(0xFFEEF2F7)))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(child: Text(cuts[i].label, style: ts(14, weight: FontWeight.w700))),
                      const SizedBox(width: 8),
                      Text('월 ${formatMan(cuts[i].saved)}', style: ts(14, weight: FontWeight.w700, color: AppColors.blue)),
                    ],
                  ),
                  Padding(padding: const EdgeInsets.only(top: 2), child: Text(cuts[i].reason, style: ts(12.5, color: AppColors.text3, height: 1.45))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 하나의 막대에 항목을 색으로 나눠 담고, 아래 범례로 금액·비율을 읽어 준다
class _SpendStack extends StatelessWidget {
  const _SpendStack({required this.categories, required this.fresh, this.insight});

  final List<la.SpendCategory> categories;
  final bool fresh;
  final la.SpendInsight? insight;

  Color _color(la.SpendCategory c) => _spendColors[c.label] ?? _spendFallback;

  Widget _change(la.SpendCategory c) {
    final r = insight?.rows.where((x) => x.label == c.label).firstOrNull;
    if (r == null) return const SizedBox.shrink();
    final pct = r.changePct;
    final color = pct > 0 ? const Color(0xFFE5484D) : (pct < 0 ? AppColors.blue : const Color(0xFF8A94A3));
    return Text('${pct > 0 ? '+' : (pct < 0 ? '-' : '')}${pct.abs()}%', textAlign: TextAlign.right, style: ts(12, weight: FontWeight.w700, color: color));
  }

  @override
  Widget build(BuildContext context) {
    final ins = insight;
    Widget bar = ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: SizedBox(
        height: 14,
        child: Row(
          spacing: 2,
          children: [
            for (final c in categories) Expanded(flex: math.max(1, (c.ratio * 1000).round()), child: ColoredBox(color: _color(c))),
          ],
        ),
      ),
    );
    if (fresh) {
      bar = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 700),
        curve: Curves.ease,
        child: bar,
        builder: (context, t, child) => ClipRect(clipper: _RevealClipper(t), child: child),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ins != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(ins.source, style: ts(12, color: const Color(0xFF7B8794)))),
          Semantics(label: '소비 항목별 비율', child: bar),
          const SizedBox(height: 12),
          Column(
            spacing: 8,
            children: [
              for (final c in categories)
                Row(
                  children: [
                    SizedBox(
                      width: 12,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(width: 10, height: 10, decoration: BoxDecoration(color: _color(c), borderRadius: BorderRadius.circular(3))),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(c.label, style: ts(13.5))),
                    const SizedBox(width: 8),
                    Text(
                      '${formatWon(c.amount)} · ${(c.ratio * 100).round()}%',
                      style: ts(13.5, weight: FontWeight.w700).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                    if (ins != null) ...[const SizedBox(width: 8), SizedBox(width: 44, child: _change(c))],
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RevealClipper extends CustomClipper<Rect> {
  _RevealClipper(this.t);

  final double t;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * t, size.height);

  @override
  bool shouldReclip(_RevealClipper old) => old.t != t;
}

/* ==================================================================
 * 생각 중 · 선택지 · 입력줄
 * ================================================================== */

class _Thinking extends StatefulWidget {
  const _Thinking({required this.label});

  final String label;

  @override
  State<_Thinking> createState() => _ThinkingState();
}

class _ThinkingState extends State<_Thinking> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'AI가 생각하는 중',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            AnimatedBuilder(
              animation: _c,
              builder: (context, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 3),
                      child: Builder(builder: (context) {
                        var p = (_c.value - i * 0.15) % 1;
                        if (p < 0) p += 1;
                        final k = p < 0.5 ? p / 0.5 : (1 - p) / 0.5;
                        return Opacity(opacity: 1 - k, child: Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.blue, shape: BoxShape.circle)));
                      }),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 7),
            Flexible(child: Text(widget.label, style: ts(13, color: AppColors.text2))),
          ],
        ),
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip(this.label, {required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFE2EEFC),
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(label, style: ts(13, weight: FontWeight.w700, color: const Color(0xFF2B6FD0), height: 1.3)),
          ),
        ),
      ),
    );
  }
}

/// 읽기 전용 입력줄. 입력창을 누르면 대본 문장이 자동으로 타이핑된다
class _Composer extends StatefulWidget {
  const _Composer({required this.s, required this.onField, required this.onSend});

  final LumpsumSession s;
  final VoidCallback onField;
  final VoidCallback onSend;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  final _inner = ScrollController();

  @override
  void dispose() {
    _inner.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final streaming = s.chat.any((m) => m.streaming) || s.thinking;
    final hot = s.typing || s.draft.isNotEmpty;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final side = wideInsetOf(context);
    final Color sendBg = hot ? AppColors.blue : (streaming ? AppColors.text : Colors.transparent);
    return Container(
      padding: EdgeInsets.fromLTRB(6 + side, 10, 12 + side, bottomInset > 0 ? bottomInset + 4 : 12),
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFEEF0F3)))),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onField,
        child: Container(
          constraints: const BoxConstraints(minHeight: 46),
          margin: const EdgeInsets.only(left: 2),
          padding: const EdgeInsets.only(left: 16, right: 6),
          decoration: BoxDecoration(color: AppColors.inputBg, borderRadius: BorderRadius.circular(12)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 22 * 6 + 22),
                  child: SingleChildScrollView(
                    controller: _inner,
                    reverse: true,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      child: SizedBox(
                        width: double.infinity,
                        child: s.draft.isEmpty
                            ? Text('메시지를 입력하세요', style: ts(14.5, color: AppColors.text3, height: 22 / 14.5))
                            : Text(s.draft, style: ts(14.5, height: 22 / 14.5)),
                      ),
                    ),
                  ),
                ),
              ),
              if (s.typing) const Padding(padding: EdgeInsets.only(bottom: 15, right: 4), child: _Caret(height: 15, margin: 1)),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Semantics(
                  button: true,
                  label: streaming ? '응답 중지' : '전송',
                  child: Material(
                    color: sendBg,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: widget.onSend,
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: Center(
                          child: streaming && !hot
                              ? Container(width: 10, height: 10, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)))
                              : SvgIcon(AppIcons.send, size: 21, color: hot ? Colors.white : AppColors.blue),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
