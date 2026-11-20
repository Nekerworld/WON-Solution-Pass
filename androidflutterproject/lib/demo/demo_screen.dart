import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/demo_profile.dart';
import '../domain/bank_state.dart';
import '../domain/formatters.dart';
import '../domain/goal_info.dart' as gi;
import '../domain/scenario.dart';
import '../ui/app_scope.dart';
import '../ui/icons.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

const _panelBg = Color(0xFFF6F8FB);
const _numBg = Color(0xFFF4F7FB);
const _tagBg = Color(0xFFE8F1FE);
const _btnBg = Color(0xFF18212D);
const _btnBorder = Color(0xFF2B3646);
const _btnText = Color(0xFFD7DEE8);
const _primaryBorder = Color(0xFF0A7FD0);

/// 빈 값(아직 모름 등)이 값으로 바뀌거나 값이 바뀐 줄만 잠깐 강조한다
const List<String> _blankValues = [gi.unknownText, gi.declinedText, gi.skippedText, gi.noGoalText];
const int _highlightMs = 2600;

/// 발표자·청중용 시연 화면 (demoPanel.js).
/// 금융 청중이 읽는 말로, 지금 고객에게 무슨 일이 일어나는지만 보여 준다.
/// 상태머신·경로 그래프·JSON·이벤트 로그·자가 테스트는 이 화면에 올리지 않는다.
class DemoScreen extends StatefulWidget {
  const DemoScreen({super.key});

  @override
  State<DemoScreen> createState() => _DemoScreenState();
}

class _DemoScreenState extends State<DemoScreen> {
  AppController? _app;
  Listenable? _listenable;

  /// 슬라이더를 끄는 동안의 값. 놓을 때 저장한다
  DemoProfile? _live;

  Map<String, String>? _knownValues;
  final Map<String, int> _highlightAt = {};
  Timer? _highlightTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = AppScope.controllerOf(context);
    if (identical(app, _app)) return;
    _app = app;
    _listenable = Listenable.merge([app, app.store, ...app.fsms.values]);
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    super.dispose();
  }

  void _set(DemoProfile next) {
    _live = null;
    _app!.demoProfile.set(next);
  }

  void _reset() {
    final app = _app!;
    _live = null;
    app.demoProfile.set(app.demoProfile.profile.copyWith(personaDone: false));
    app.resetDemo();
  }

  List<(gi.GoalInfoRow row, bool on, int? at)> _markNew(List<gi.GoalInfoRow> rows) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final prev = _knownValues;
    final next = <String, String>{};
    for (final c in rows) {
      next[c.label] = c.value;
      if (prev != null && !_blankValues.contains(c.value) && prev[c.label] != c.value) {
        _highlightAt[c.label] = now;
        _highlightTimer?.cancel();
        _highlightTimer = Timer(const Duration(milliseconds: _highlightMs + 50), () {
          if (mounted) setState(() {});
        });
      }
    }
    _knownValues = next;
    return [
      for (final c in rows)
        () {
          final at = _highlightAt[c.label];
          return (c, at != null && now - at < _highlightMs, at);
        }(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final app = _app!;
    return Scaffold(
      backgroundColor: _panelBg,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
            child: Row(
              children: [
                Expanded(child: Text('시연', style: ts(22, weight: FontWeight.w800, color: AppColors.blueDeep, letterSpacing: -0.03))),
                _DpButton('처음부터', primary: true, onTap: _reset),
                const SizedBox(width: 4),
                AppIconButton(icon: AppIcons.x, label: '닫기', iconSize: 20, onTap: () => Navigator.of(context).maybePop()),
              ],
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: _listenable!,
              builder: (context, _) {
                final st = app.store.state;
                return LayoutBuilder(
                  builder: (context, box) => ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                    children: [
                      _customerCard(app, st),
                      _knownCard(app, st, box.maxWidth),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /* ---------------- 고객 정보 ---------------- */

  Widget _customerCard(AppController app, BankState st) {
    final profile = app.demoProfile.profile;
    final c = st.customer;
    final who = '${c.name} · ${c.age}세';
    final whoText = Text(who, style: ts(26, weight: FontWeight.w700, letterSpacing: -0.03));
    if (profile.personaDone) {
      final sum = personaSummary(profile);
      return _Card(
        children: [
          _kicker('고객 정보', tag: sum.preset),
          whoText,
          const SizedBox(height: 14),
          for (var i = 0; i < sum.lines.length; i++)
            Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 4), child: Text(sum.lines[i], style: ts(14))),
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerLeft, child: _EditButton(onTap: () => _set(profile.copyWith(personaDone: false)))),
        ],
      );
    }
    final live = _live ?? profile;
    return _Card(
      children: [
        _kicker('페르소나 만들기'),
        whoText,
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: _slider(
                label: '수입',
                value: live.income,
                min: 150,
                max: 800,
                step: 10,
                onDrag: (v) => live.copyWith(income: v),
                onEnd: (v) => profile.copyWith(income: v),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: _DpButton(
                '부채 있음',
                primary: profile.debtOn,
                expand: true,
                onTap: () => _set(profile.copyWith(debtOn: !profile.debtOn, debt: profile.debtOn ? 0 : (profile.debt == 0 ? 30000000 : profile.debt))),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: _slider(
                label: '지출',
                value: live.expense,
                min: 50,
                max: 700,
                step: 10,
                onDrag: (v) => live.copyWith(expense: v),
                onEnd: (v) => profile.copyWith(expense: v),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: _slider(
                label: '부채 잔액',
                value: live.debtValue,
                min: 0,
                max: 10000,
                step: 100,
                off: !profile.debtOn,
                onDrag: (v) => live.copyWith(debt: v, debtOn: true),
                onEnd: (v) => profile.copyWith(debt: v, debtOn: true),
              ),
            ),
          ],
        ),
        _line(personaSummary(live).lines[3]),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _PresetButton('기본', onTap: () => _set(presetProfile('base', profile))),
            _PresetButton('여유 없음', onTap: () => _set(presetProfile('spend', profile))),
            _PresetButton('부채 있음', onTap: () => _set(presetProfile('debt', profile))),
            _PresetButton('기본값', onTap: () => _set(profile.copyWith(income: 3500000, expense: 2100000, debtOn: false, debt: 0))),
          ],
        ),
        const SizedBox(height: 12),
        _DpButton('이 설정으로 할게요', primary: true, expand: true, onTap: () => _set(profile.copyWith(personaDone: true))),
        ..._hintLines(app),
      ],
    );
  }

  /// 고객 정보 카드 아래 문구. 새 값은 다음 채팅부터 쓰인다는 것을 알린다
  List<Widget> _hintLines(AppController app) {
    final hint = app.lumpsum.hint();
    return [
      if (hint.active && hint.line.isNotEmpty) _line(hint.line),
      if (hint.decision.isNotEmpty)
        _line('${hint.decision}\n새 채팅부터 반영돼요')
      else if (hint.active)
        _line('새 채팅부터 반영돼요'),
    ];
  }

  Widget _line(String text) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(text, style: ts(13, color: AppColors.text2, height: 1.45)),
      );

  Widget _kicker(String text, {String tag = ''}) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Text(text, style: ts(13, weight: FontWeight.w700, color: AppColors.blue)),
            if (tag.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                decoration: BoxDecoration(color: _tagBg, borderRadius: BorderRadius.circular(99)),
                child: Text(tag, style: ts(11, weight: FontWeight.w700, color: AppColors.blue)),
              ),
          ],
        ),
      );

  /// 값은 만원 단위 정수로 움직인다
  Widget _slider({
    required String label,
    required int value,
    required int min,
    required int max,
    required int step,
    required DemoProfile Function(int won) onDrag,
    required DemoProfile Function(int won) onEnd,
    bool off = false,
  }) {
    final man = (value / 10000).round().clamp(min, max);
    return Opacity(
      opacity: off ? 0.45 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(width: 72, child: Text(label, style: ts(13))),
              const SizedBox(width: 8),
              Expanded(child: Text(formatMan(value), textAlign: TextAlign.right, style: ts(13, weight: FontWeight.w700))),
            ],
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: 28,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                activeTrackColor: AppColors.blue,
                inactiveTrackColor: AppColors.lineStrong,
                thumbColor: AppColors.blue,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              ),
              child: Slider(
                value: man.toDouble(),
                min: min.toDouble(),
                max: max.toDouble(),
                divisions: (max - min) ~/ step,
                onChanged: off ? null : (v) => setState(() => _live = onDrag(v.round() * 10000)),
                onChangeEnd: off ? null : (v) => _set(onEnd(v.round() * 10000)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /* ---------------- 해결패스가 알고 있는 정보 ---------------- */

  Widget _knownCard(AppController app, BankState st, double width) {
    final sess = app.session;
    final apps = st.applications.values.where((a) => a.productId == DemoScenario.productId).toList();
    final info = gi.describe(
      lumpsum: sess.lumpsum,
      lumpsumState: app.lumpsumFsm.state,
      asset: sess.asset,
      assetState: app.assetFsm.state,
      applied: apps.any((a) => const ['PENDING', 'UNKNOWN', 'SUCCESS'].contains(a.status)),
      approved: apps.any((a) => a.status == 'SUCCESS') && !const ['APPLYING', 'VERIFYING'].contains(app.joinFsm.state),
      hasFxAccount: st.facts['hasFxAccount'],
    );
    final marks = _markNew(info.rows);
    // 멀리서도 읽히도록 크게 쓰되, 휴대폰 폭에서는 줄여서 한 줄에 들어가게 한다
    final k = (width / 640).clamp(0.66, 1.0);
    // 첫 줄(목표)은 크게, 나머지 세부 목표는 조금 작게 두 열로 보여 준다
    final head = marks.where((m) => m.$1.label == '목표').toList();
    final subs = marks.where((m) => m.$1.label != '목표').toList();
    Widget cell((gi.GoalInfoRow, bool, int?) m, bool sub) =>
        _KnownCell(key: ValueKey(m.$1.label), label: m.$1.label, value: m.$1.value, on: m.$2, at: m.$3, sub: sub, scale: k);
    return _Card(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text('해결패스가 알고 있는 정보', style: ts(30 * k, weight: FontWeight.w700, letterSpacing: -0.03)),
        ),
        for (var i = 0; i < head.length; i++) Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 12), child: cell(head[i], false)),
        if (subs.isNotEmpty) const SizedBox(height: 10),
        for (var i = 0; i < subs.length; i += 2)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cell(subs[i], true)),
                  const SizedBox(width: 8),
                  Expanded(child: i + 1 < subs.length ? cell(subs[i + 1], true) : const SizedBox.shrink()),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children, this.padding = const EdgeInsets.fromLTRB(18, 16, 18, 14)});

  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: padding,
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), boxShadow: shadowCard),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

/// 새 정보가 들어온 줄: 페이드로 나타나고, 파란 빛이 번졌다가 기본 배경으로 돌아간다.
/// 마지막 값을 기본 배경과 같게 맞춰 강조가 끝나고 다시 그려질 때 색이 튀지 않게 한다.
class _KnownCell extends StatefulWidget {
  const _KnownCell({super.key, required this.label, required this.value, required this.on, required this.at, required this.sub, required this.scale});

  final String label;
  final String value;
  final bool on;
  final int? at;
  final bool sub;
  final double scale;

  @override
  State<_KnownCell> createState() => _KnownCellState();
}

class _KnownCellState extends State<_KnownCell> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: _highlightMs), value: 1);

  static final Animatable<Color?> _glow = TweenSequence<Color?>([
    TweenSequenceItem(tween: ColorTween(begin: const Color(0xFFE3EFFF), end: const Color(0xFFCFE4FF)).chain(CurveTween(curve: Curves.ease)), weight: 30),
    TweenSequenceItem(tween: ColorTween(begin: const Color(0xFFCFE4FF), end: _numBg).chain(CurveTween(curve: Curves.ease)), weight: 70),
  ]);
  static final Animatable<double> _ring = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.ease)), weight: 30),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.ease)), weight: 70),
  ]);
  static final Animatable<double> _badgeOpacity = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.ease)), weight: 12),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 66),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.ease)), weight: 22),
  ]);
  static final Animatable<double> _badgeScale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.85, end: 1.0).chain(CurveTween(curve: Curves.ease)), weight: 12),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 66),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.95).chain(CurveTween(curve: Curves.ease)), weight: 22),
  ]);

  @override
  void initState() {
    super.initState();
    if (widget.on) _start();
  }

  @override
  void didUpdateWidget(_KnownCell old) {
    super.didUpdateWidget(old);
    if (widget.on && widget.at != old.at) _start();
  }

  void _start() {
    final elapsed = widget.at == null ? 0 : DateTime.now().millisecondsSinceEpoch - widget.at!;
    _c.forward(from: (elapsed / _highlightMs).clamp(0.0, 1.0));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.scale;
    final sub = widget.sub;
    final radius = BorderRadius.circular(sub ? 12 : 16);
    final labelStyle = ts((sub ? 18 : 24) * k, color: AppColors.text2, height: 1.3);
    final valueStyle = ts((sub ? 22.5 : 30) * k, weight: FontWeight.w800, height: 1.35, letterSpacing: -0.02);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final live = widget.on && _c.isAnimating;
        // 앞 0.5초: 아래에서 올라오며 나타난다
        final enter = live ? Curves.ease.transform((t * _highlightMs / 500).clamp(0.0, 1.0)) : 1.0;
        final bg = live ? _glow.transform(t)! : _numBg;
        final ring = live ? _ring.transform(t) : 0.0;
        return Opacity(
          opacity: enter,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - enter)),
            child: Container(
              padding: sub ? const EdgeInsets.symmetric(horizontal: 14, vertical: 12) : const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: radius,
                boxShadow: ring > 0 ? [BoxShadow(color: Color.fromRGBO(36, 136, 243, 0.16 * ring), spreadRadius: 6 * ring)] : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(children: [
                      if (widget.on)
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Opacity(
                            opacity: live ? _badgeOpacity.transform(t) : 0,
                            child: Transform.scale(
                              scale: live ? _badgeScale.transform(t) : 1,
                              alignment: Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(right: 10),
                                padding: EdgeInsets.symmetric(horizontal: 12 * k, vertical: 2),
                                decoration: BoxDecoration(color: AppColors.blue, borderRadius: BorderRadius.circular(AppRadius.pill)),
                                child: Text('새 정보', style: ts(18 * k, weight: FontWeight.w700, color: Colors.white, height: 1.5)),
                              ),
                            ),
                          ),
                        ),
                      TextSpan(text: widget.label),
                    ]),
                    style: labelStyle,
                  ),
                  SizedBox(height: sub ? 4 : 6),
                  Text(widget.value, style: valueStyle),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DpButton extends StatelessWidget {
  const _DpButton(this.label, {required this.onTap, this.primary = false, this.expand = false});

  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primary ? AppColors.blueDeep : _btnBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: primary ? _primaryBorder : _btnBorder),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: expand ? double.infinity : null,
          constraints: BoxConstraints(minHeight: primary ? 40 : 30),
          padding: primary ? const EdgeInsets.symmetric(horizontal: 14, vertical: 8) : const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          alignment: expand ? Alignment.center : null,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: ts(primary ? 15 : 12, weight: FontWeight.w600, color: primary ? Colors.white : _btnText, height: 1.2),
          ),
        ),
      ),
    );
  }
}

class _PresetButton extends StatelessWidget {
  const _PresetButton(this.label, {required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill), side: const BorderSide(color: AppColors.line)),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(label, style: ts(12)),
        ),
      ),
    );
  }
}

class _EditButton extends StatelessWidget {
  const _EditButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('바꾸기', style: ts(13, weight: FontWeight.w700, color: AppColors.blue)),
            const SizedBox(width: 6),
            Transform.translate(
              offset: const Offset(0, -2),
              child: Transform.rotate(
                angle: 0.785398,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    border: Border(right: BorderSide(color: AppColors.blue, width: 2), bottom: BorderSide(color: AppColors.blue, width: 2)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
