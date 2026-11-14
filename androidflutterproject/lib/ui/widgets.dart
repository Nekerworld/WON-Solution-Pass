import 'dart:async';

import 'package:flutter/material.dart';

import '../app/overlays.dart';
import '../domain/bank_types.dart';
import '../domain/rule_engine.dart' show statusLabel;
import 'icons.dart';
import 'responsive.dart';
import 'theme.dart';

/* ==================================================================
 * 화면 골격
 * ================================================================== */

/// 앱바 + 스크롤 본문 + 하단 고정 영역
class ScreenFrame extends StatelessWidget {
  const ScreenFrame({
    super.key,
    this.appBar,
    required this.children,
    this.footer,
    this.white = false,
    this.bodyPadding = const EdgeInsets.fromLTRB(20, 4, 20, 28),
    this.scrollController,
    this.bodyColor,
  });

  final Widget? appBar;
  final List<Widget> children;
  final Widget? footer;
  final bool white;
  final EdgeInsets bodyPadding;
  final ScrollController? scrollController;
  final Color? bodyColor;

  @override
  Widget build(BuildContext context) {
    final bg = white ? AppColors.surface : AppColors.bg;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final side = wideInsetOf(context);
    return Material(
      color: bg,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ?appBar,
            Expanded(
              child: Material(
                color: bodyColor ?? bg,
                child: ListView(
                  controller: scrollController,
                  padding: bodyPadding.copyWith(
                    left: bodyPadding.left + side,
                    right: bodyPadding.right + side,
                    bottom: bodyPadding.bottom + (footer == null ? bottomInset : 0),
                  ),
                  children: children,
                ),
              ),
            ),
            if (footer != null)
              Container(
                padding: EdgeInsets.fromLTRB(20 + side, 12, 20 + side, 16 + (bottomInset > 0 ? bottomInset : 10)),
                color: bg,
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
}

class WspAppBar extends StatelessWidget {
  const WspAppBar({super.key, required this.title, this.onBack, this.noBack = false, this.right, this.color});

  final String title;
  final VoidCallback? onBack;
  final bool noBack;
  final Widget? right;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: noBack ? null : AppIconButton(icon: AppIcons.back, label: '뒤로 가기', onTap: onBack),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ts(17, weight: FontWeight.w700, letterSpacing: -0.02),
            ),
          ),
          SizedBox(width: 48, child: Align(alignment: Alignment.centerRight, child: right)),
        ],
      ),
    );
  }
}

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.size = 44,
    this.iconSize = 24,
    this.color = AppColors.text,
  });

  final SvgArt icon;
  final String label;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(width: size, height: size, child: Center(child: SvgIcon(icon, size: iconSize, color: color))),
        ),
      ),
    );
  }
}

/* ==================================================================
 * 배지 / 안내 / 목록
 * ================================================================== */

class ToneBadge extends StatelessWidget {
  const ToneBadge(this.text, this.tone, {super.key, this.pop = false});

  final String text;
  final UiTone tone;
  final bool pop;

  @override
  Widget build(BuildContext context) {
    final c = ToneColors.of(tone);
    final badge = Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Center(
        widthFactor: 1,
        child: Text(text, style: ts(11, weight: FontWeight.w700, color: c.fg, letterSpacing: -0.01)),
      ),
    );
    return pop ? PopIn(child: badge) : badge;
  }
}

/// 안내 상자. [title]은 굵게, [body]는 다음 줄에 표시한다. [spans]를 주면 그대로 그린다.
class NoticeBox extends StatelessWidget {
  const NoticeBox({super.key, this.title, this.body, this.spans, this.tone, this.icon});

  final String? title;
  final String? body;
  final List<InlineSpan>? spans;
  final UiTone? tone;
  final SvgArt? icon;

  @override
  Widget build(BuildContext context) {
    final c = tone == null ? const ToneColors(AppColors.neutralBg, AppColors.text2, AppColors.text2) : ToneColors.of(tone!);
    final base = ts(13, color: c.text, height: 1.55);
    final content = spans ??
        [
          if (title != null) TextSpan(text: title, style: weightStyle(FontWeight.w700)),
          if (title != null && body != null) const TextSpan(text: '\n'),
          if (body != null) TextSpan(text: body),
        ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1.5),
            child: SvgIcon(icon ?? AppIcons.info, size: 18, color: c.text),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text.rich(TextSpan(style: base, children: content))),
        ],
      ),
    );
  }
}

TextSpan bold(String text) => TextSpan(text: text, style: weightStyle(FontWeight.w700));

class KvRow {
  const KvRow(this.label, this.value);
  KvRow.text(this.label, String text, {bool strong = false, bool mono = false})
      : value = Text(
          text,
          textAlign: TextAlign.right,
          style: mono ? monoStyle(12, color: AppColors.text) : ts(strong ? 15 : 14, weight: FontWeight.w700),
        );

  final String label;
  final Widget value;
}

class KvRows extends StatelessWidget {
  const KvRows(this.rows, {super.key});

  final List<KvRow> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              border: i == rows.length - 1 ? null : const Border(bottom: BorderSide(color: AppColors.line)),
            ),
            child: Row(
              children: [
                Text(rows[i].label, style: ts(14, color: AppColors.text2)),
                const SizedBox(width: 12),
                Expanded(child: Align(alignment: Alignment.centerRight, child: rows[i].value)),
              ],
            ),
          ),
      ],
    );
  }
}

class CardBox extends StatelessWidget {
  const CardBox({super.key, required this.child, this.outline = false, this.tight = false, this.padding, this.color});

  final Widget child;
  final bool outline;
  final bool tight;
  final EdgeInsets? padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? (tight ? const EdgeInsets.symmetric(horizontal: 16, vertical: 14) : const EdgeInsets.all(18)),
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: outline ? Border.all(color: AppColors.line) : null,
        boxShadow: outline ? null : shadowCard,
      ),
      child: child,
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.small});

  final String text;
  final String? small;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
      child: Row(
        children: [
          Expanded(child: Text(text, style: ts(15, weight: FontWeight.w700, letterSpacing: -0.02))),
          if (small != null) Text(small!, style: ts(12, color: AppColors.text3)),
        ],
      ),
    );
  }
}

class Fineprint extends StatelessWidget {
  const Fineprint(this.text, {super.key, this.top = 14});

  final String text;
  final double top;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(2, top, 2, 0),
      child: Text(text, style: ts(11.5, color: AppColors.text3, height: 1.6)),
    );
  }
}

class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: AppColors.blueLight, shape: BoxShape.circle),
      child: Text(name.isEmpty ? '?' : name.characters.first, style: ts(15, weight: FontWeight.w700, color: AppColors.blue)),
    );
  }
}

/* ==================================================================
 * 버튼
 * ================================================================== */

enum BtnKind { primary, secondary, ghost, danger, white }

enum BtnSize { sm, md, lg }

/// 비동기 동작이 끝날 때까지 로딩 표시를 하는 버튼
class AppButton extends StatefulWidget {
  const AppButton(
    this.label, {
    super.key,
    this.onPressed,
    this.kind = BtnKind.primary,
    this.size = BtnSize.md,
    this.block = true,
    this.loading,
  });

  final String label;
  final FutureOr<void> Function()? onPressed;
  final BtnKind kind;
  final BtnSize size;
  final bool block;

  /// 지정하면 내부 로딩 상태 대신 이 값을 쓴다.
  final bool? loading;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _busy = false;
  bool _pressed = false;

  Future<void> _tap() async {
    final fn = widget.onPressed;
    if (fn == null || _busy) return;
    final r = fn();
    if (r is Future) {
      setState(() => _busy = true);
      try {
        await r;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = widget.loading ?? _busy;
    final disabled = widget.onPressed == null;
    final (bg, fg) = switch (widget.kind) {
      BtnKind.primary => (AppColors.blue, Colors.white),
      BtnKind.secondary => (AppColors.blueLight, AppColors.blue),
      BtnKind.ghost => (AppColors.neutralBg, AppColors.text2),
      BtnKind.danger => (AppColors.danger, Colors.white),
      BtnKind.white => (Colors.white, AppColors.blue),
    };
    final (height, radius, font, hp) = switch (widget.size) {
      BtnSize.sm => (38.0, AppRadius.buttonSm, 13.0, 14.0),
      BtnSize.md => (48.0, AppRadius.button, 15.0, 18.0),
      BtnSize.lg => (56.0, AppRadius.buttonLg, 17.0, 18.0),
    };
    final light = widget.kind == BtnKind.primary || widget.kind == BtnKind.danger;
    final child = AnimatedScale(
      scale: _pressed && !disabled ? 0.98 : 1,
      duration: const Duration(milliseconds: 100),
      child: Opacity(
        opacity: disabled ? 0.45 : 1,
        child: Container(
          height: height,
          width: widget.block ? double.infinity : null,
          padding: EdgeInsets.symmetric(horizontal: hp),
          decoration: BoxDecoration(
            color: _pressed && !disabled && widget.kind == BtnKind.primary ? AppColors.blueDark : bg,
            borderRadius: BorderRadius.circular(radius),
            border: widget.kind == BtnKind.white ? Border.all(color: const Color(0xFFCFE2F5)) : null,
            boxShadow: widget.kind == BtnKind.primary && !disabled
                ? const [BoxShadow(color: Color(0x3D2488F3), blurRadius: 12, offset: Offset(0, 4))]
                : null,
          ),
          child: Center(
            widthFactor: 1,
            child: loading
                ? Spinner(size: 20, stroke: 2.5, color: light ? Colors.white : AppColors.blue, track: light ? Colors.white54 : AppColors.blue.withValues(alpha: 0.25))
                : Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ts(font, weight: FontWeight.w700, color: fg, letterSpacing: -0.02),
                  ),
          ),
        ),
      ),
    );
    return Semantics(
      container: true,
      button: true,
      enabled: !disabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: disabled ? null : (_) => setState(() => _pressed = true),
        onTapUp: disabled ? null : (_) => setState(() => _pressed = false),
        onTapCancel: disabled ? null : () => setState(() => _pressed = false),
        onTap: disabled || loading ? null : _tap,
        child: child,
      ),
    );
  }
}

class ButtonRow extends StatelessWidget {
  const ButtonRow(this.children, {super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}

class LinkButton extends StatelessWidget {
  const LinkButton(this.label, {super.key, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(label, style: ts(13, weight: FontWeight.w700, color: AppColors.blue)),
      ),
    );
  }
}

class ChoiceChipButton extends StatelessWidget {
  const ChoiceChipButton({super.key, required this.label, this.selected = false, this.tag, required this.onTap});

  final String label;
  final bool selected;
  final String? tag;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.text2;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.blue : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: selected ? AppColors.blue : AppColors.lineStrong),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: ts(13, weight: FontWeight.w700, color: fg)),
            if (tag != null) ...[
              const SizedBox(width: 4),
              Text(tag!, style: ts(10, color: fg.withValues(alpha: 0.85))),
            ],
          ],
        ),
      ),
    );
  }
}

/* ==================================================================
 * 진행 표시 / 애니메이션
 * ================================================================== */

class Spinner extends StatefulWidget {
  const Spinner({super.key, this.size = 18, this.stroke = 2.5, this.color = AppColors.blue, this.track = AppColors.blueLight});

  final double size;
  final double stroke;
  final Color color;
  final Color track;

  @override
  State<Spinner> createState() => _SpinnerState();
}

class _SpinnerState extends State<Spinner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: RotationTransition(
        turns: _c,
        child: CustomPaint(painter: _SpinnerPainter(widget.stroke, widget.color, widget.track)),
      ),
    );
  }
}

class _SpinnerPainter extends CustomPainter {
  _SpinnerPainter(this.stroke, this.color, this.track);

  final double stroke;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawOval(r, paint..color = track);
    canvas.drawArc(r, -1.5708 - 0.7854, 1.5708, false, paint..color = color);
  }

  @override
  bool shouldRepaint(_SpinnerPainter old) => old.color != color || old.track != track;
}

/// 작게 시작해 커지며 나타난다 (CSS pop)
class PopIn extends StatelessWidget {
  const PopIn({super.key, required this.child, this.duration = const Duration(milliseconds: 250)});

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: appEase,
      builder: (context, t, child) => Opacity(opacity: t.clamp(0, 1), child: Transform.scale(scale: 0.7 + 0.3 * t, child: child)),
      child: child,
    );
  }
}

/// 아래에서 살짝 올라오며 나타난다 (CSS stepIn)
class RiseIn extends StatefulWidget {
  const RiseIn({super.key, required this.child, this.delay = Duration.zero, this.duration = const Duration(milliseconds: 350)});

  final Widget child;
  final Duration delay;
  final Duration duration;

  @override
  State<RiseIn> createState() => _RiseInState();
}

class _RiseInState extends State<RiseIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: appEase);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(offset: Offset(0, 8 * (1 - _t.value)), child: child),
      ),
      child: widget.child,
    );
  }
}

class FadeIn extends StatelessWidget {
  const FadeIn({super.key, required this.child, this.duration = const Duration(milliseconds: 250)});

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: child,
    );
  }
}

/* ==================================================================
 * 결과 / 흐름 화면 조각
 * ================================================================== */

class ResultHead extends StatelessWidget {
  const ResultHead({
    super.key,
    required this.tone,
    this.icon,
    this.iconChild,
    required this.title,
    this.amount,
    this.desc,
    this.extra,
  });

  final UiTone tone;
  final SvgArt? icon;
  final Widget? iconChild;
  final String title;
  final String? amount;
  final String? desc;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      UiTone.success => (AppColors.successBg, AppColors.success),
      UiTone.warning => (AppColors.warningBg, AppColors.warning),
      UiTone.danger => (AppColors.dangerBg, AppColors.danger),
      _ => (AppColors.neutralBg, AppColors.text2),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 26, 4, 8),
      child: Column(
        children: [
          PopIn(
            duration: const Duration(milliseconds: 400),
            child: Container(
              width: 76,
              height: 76,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: iconChild ?? SvgIcon(icon!, size: 38, color: fg),
            ),
          ),
          const SizedBox(height: 18),
          Text(title, textAlign: TextAlign.center, style: ts(22, weight: FontWeight.w700, letterSpacing: -0.03, height: 1.35)),
          if (amount != null)
            Padding(
              padding: const EdgeInsets.only(top: 14, bottom: 2),
              child: Text(amount!, style: ts(30, weight: FontWeight.w700, letterSpacing: -0.02)),
            ),
          if (desc != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(desc!, textAlign: TextAlign.center, style: ts(14, color: AppColors.text2, height: 1.55)),
            ),
          ?extra,
        ],
      ),
    );
  }
}

enum VerifyState { ok, pending, fail }

class VerifyItem extends StatelessWidget {
  const VerifyItem(this.text, {super.key, this.sub, this.state = VerifyState.ok});

  final String text;
  final String? sub;
  final VerifyState state;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (state) {
      VerifyState.ok => (AppColors.success, Colors.white, AppIcons.check),
      VerifyState.pending => (AppColors.warningBg, AppColors.warning, AppIcons.clock),
      VerifyState.fail => (AppColors.dangerBg, AppColors.danger, AppIcons.x),
    };
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: SvgIcon(icon, size: 13, color: fg),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(text, style: ts(14)),
              if (sub != null && sub!.isNotEmpty) Text(sub!, style: ts(12, color: AppColors.text3)),
            ],
          ),
        ),
      ],
    );
  }
}

class VerifyList extends StatelessWidget {
  const VerifyList(this.items, {super.key});

  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      outline: true,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[if (i > 0) const SizedBox(height: 10), items[i]],
        ],
      ),
    );
  }
}

class FlowHero extends StatelessWidget {
  const FlowHero({super.key, required this.icon, required this.title, required this.desc});

  final SvgArt icon;
  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.blueLight, borderRadius: BorderRadius.circular(20)),
            child: SvgIcon(icon, size: 32, color: AppColors.blue),
          ),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: ts(20, weight: FontWeight.w700, letterSpacing: -0.03)),
          const SizedBox(height: 6),
          Text(desc, textAlign: TextAlign.center, style: ts(14, color: AppColors.text2, height: 1.55)),
        ],
      ),
    );
  }
}

/// 조회 실패 시 확인되지 않은 정보로 진행하지 않는다.
class QueryErrorView extends StatelessWidget {
  const QueryErrorView({super.key, required this.title, this.error, required this.onBack, required this.onHome, required this.onRetry});

  final String title;
  final BankError? error;
  final VoidCallback onBack;
  final VoidCallback onHome;
  final FutureOr<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      white: true,
      appBar: WspAppBar(title: title, onBack: onBack),
      footer: ButtonRow([
        AppButton('홈으로', kind: BtnKind.ghost, onPressed: onHome),
        AppButton('다시 시도', onPressed: onRetry),
      ]),
      children: [
        ResultHead(
          tone: UiTone.neutral,
          icon: AppIcons.alert,
          title: '정보를 불러오지 못했어요',
          desc: '${error?.message ?? '화면을 표시하는 중 문제가 발생했어요.'}\n확인되지 않은 정보로 진행하지 않아요. 잠시 후 다시 시도해 주세요.',
        ),
      ],
    );
  }
}

/* ==================================================================
 * 해결패스 공용 조각
 * ================================================================== */

const Map<String, UiTone> _condTone = {'MET': UiTone.success, 'UNMET': UiTone.danger, 'UNKNOWN': UiTone.neutral, 'IN_PROGRESS': UiTone.warning};
const Map<String, String> _condLabel = statusLabel;

/// 조건 판정 배지
class CondBadge extends StatelessWidget {
  const CondBadge(this.status, {super.key, this.label});

  final String status;
  final String? label;

  @override
  Widget build(BuildContext context) => ToneBadge(label ?? _condLabel[status] ?? status, _condTone[status] ?? UiTone.neutral);
}

/// '**굵게**' 표시를 굵은 글씨로 바꾼다
List<InlineSpan> boldMarkup(String text) {
  final out = <InlineSpan>[];
  final parts = text.split('**');
  for (var i = 0; i < parts.length; i++) {
    if (parts[i].isEmpty) continue;
    out.add(i.isOdd ? bold(parts[i]) : TextSpan(text: parts[i]));
  }
  return out;
}

class LeadText extends StatelessWidget {
  const LeadText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 14),
        child: Text(text, style: ts(15, color: AppColors.text2, height: 1.55)),
      );
}

/// 진행 중인 건이 없을 때의 빈 화면
class EmptyScreen extends StatelessWidget {
  const EmptyScreen({super.key, required this.title, required this.message, this.buttonLabel, this.onButton, this.onBack, this.noBack = false});

  final String title;
  final String message;
  final String? buttonLabel;
  final FutureOr<void> Function()? onButton;
  final VoidCallback? onBack;
  final bool noBack;

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      white: true,
      appBar: WspAppBar(title: title, onBack: onBack, noBack: noBack),
      children: [
        LeadText(message),
        if (buttonLabel != null) AppButton(buttonLabel!, block: false, onPressed: onButton),
      ],
    );
  }
}

/// 답변 칩 (예/아니오, 범위 답변, 빠른 문장)
class AnswerChip extends StatelessWidget {
  const AnswerChip(this.label, {super.key, required this.onTap, this.large = false, this.accent = false, this.selected = false});

  final String label;
  final VoidCallback? onTap;
  final bool large;
  final bool accent;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : (accent ? AppColors.blue : AppColors.text);
    final bg = selected ? AppColors.blue : (accent ? AppColors.blueLight : Colors.white);
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          side: BorderSide(color: selected ? AppColors.blue : (accent ? const Color(0xFFCFE2F5) : AppColors.lineStrong)),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: large ? 16 : 13, vertical: large ? 11 : 8),
            child: Text(label, style: ts(large ? 14 : 13, weight: FontWeight.w700, color: fg)),
          ),
        ),
      ),
    );
  }
}

class ChipWrap extends StatelessWidget {
  const ChipWrap(this.children, {super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: children);
}

/// 카드 제목 (아이콘 + 굵은 글씨)
class CardTitle extends StatelessWidget {
  const CardTitle(this.text, {super.key, this.icon, this.color});

  final String text;
  final SvgArt? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.text;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          if (icon != null) ...[SvgIcon(icon!, size: 18, color: c), const SizedBox(width: 6)],
          Expanded(child: Text(text, style: ts(15, weight: FontWeight.w700, color: c, letterSpacing: -0.02))),
        ],
      ),
    );
  }
}

/// 점 목록 (동의 범위 등)
class BulletList extends StatelessWidget {
  const BulletList(this.items, {super.key, this.negative = false});

  final List<String> items;
  final bool negative;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final t in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 3, right: 8),
                  child: negative
                      ? SvgIcon(AppIcons.x, size: 13, color: AppColors.danger)
                      : SvgIcon(AppIcons.check, size: 13, color: AppColors.success),
                ),
                Expanded(child: Text(t, style: ts(13.5, color: AppColors.text2, height: 1.5))),
              ],
            ),
          ),
      ],
    );
  }
}

/// 가로로 넘기는 카드 + 점 표시
class Carousel extends StatefulWidget {
  const Carousel({super.key, required this.children, required this.height, this.viewportFraction = 1, this.padEnds = false});

  final List<Widget> children;
  final double height;
  final double viewportFraction;
  final bool padEnds;

  @override
  State<Carousel> createState() => _CarouselState();
}

class _CarouselState extends State<Carousel> {
  late final PageController _pc = PageController(viewportFraction: widget.viewportFraction);
  int _index = 0;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.children.length;
    return Column(
      children: [
        SizedBox(
          height: widget.height,
          child: PageView(
            controller: _pc,
            padEnds: widget.padEnds,
            onPageChanged: (i) => setState(() => _index = i),
            children: widget.children,
          ),
        ),
        if (n > 1)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < n; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: i == _index.clamp(0, n - 1) ? 16 : 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    decoration: BoxDecoration(
                      color: i == _index.clamp(0, n - 1) ? const Color(0xFF1F2428) : const Color(0xFFA7AEB6),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
