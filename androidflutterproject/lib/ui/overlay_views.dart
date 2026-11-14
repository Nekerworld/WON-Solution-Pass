import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/overlays.dart';
import '../domain/scenario.dart';
import 'icons.dart';
import 'responsive.dart';
import 'screens/asset_screens.dart' show AssetEditSheetView;
import 'screens/home_screens.dart' show JoinMethodSheetView;
import 'theme.dart';
import 'widgets.dart';

/* ==================================================================
 * 하단 시트
 * ================================================================== */

class SheetLayer extends StatefulWidget {
  const SheetLayer({super.key, required this.app});

  final AppController app;

  @override
  State<SheetLayer> createState() => _SheetLayerState();
}

class _SheetLayerState extends State<SheetLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 340));
  SheetState? _shown;

  @override
  void initState() {
    super.initState();
    widget.app.addListener(_sync);
    _sync();
  }

  void _sync() {
    final next = widget.app.sheet;
    if (next == _shown) return;
    if (next != null) {
      setState(() => _shown = next);
      _anim.forward(from: _anim.value == 1 ? 0.6 : _anim.value);
    } else {
      _anim.reverse().whenComplete(() {
        if (mounted && widget.app.sheet == null) setState(() => _shown = null);
      });
    }
  }

  @override
  void dispose() {
    widget.app.removeListener(_sync);
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sheet = _shown;
    if (sheet == null) return const SizedBox.shrink();
    final curved = CurvedAnimation(parent: _anim, curve: appEase);
    final mq = MediaQuery.of(context);
    final bottom = mq.viewInsets.bottom > 0 ? mq.viewInsets.bottom : mq.padding.bottom;
    return Stack(
      children: [
        Positioned.fill(
          child: FadeTransition(
            opacity: _anim,
            child: GestureDetector(onTap: widget.app.dismissSheet, child: const ColoredBox(color: AppColors.backdrop)),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 1.05), end: Offset.zero).animate(curved),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: mq.size.height * 0.88, maxWidth: kSheetMaxWidth),
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(22, 10, 22, 24 + bottom),
                  child: ListenableBuilder(
                    listenable: Listenable.merge([sheet, widget.app]),
                    builder: (context, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 5,
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(color: AppColors.lineStrong, borderRadius: BorderRadius.circular(3)),
                          ),
                        ),
                        if (sheet is JoinMethodSheet) JoinMethodSheetView(sheet: sheet),
                        if (sheet is AssetEditSheet) AssetEditSheetView(sheet: sheet),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/* ==================================================================
 * 확인 모달
 * ================================================================== */

class ModalLayer extends StatefulWidget {
  const ModalLayer({super.key, required this.app});

  final AppController app;

  @override
  State<ModalLayer> createState() => _ModalLayerState();
}

class _ModalLayerState extends State<ModalLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  ConfirmRequest? _shown;

  @override
  void initState() {
    super.initState();
    widget.app.addListener(_sync);
  }

  void _sync() {
    final next = widget.app.modal;
    if (next == _shown) return;
    if (next != null) {
      setState(() => _shown = next);
      _anim.forward(from: 0);
    } else {
      _anim.reverse().whenComplete(() {
        if (mounted && widget.app.modal == null) setState(() => _shown = null);
      });
    }
  }

  @override
  void dispose() {
    widget.app.removeListener(_sync);
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = _shown;
    if (m == null) return const SizedBox.shrink();
    final curved = CurvedAnimation(parent: _anim, curve: appEase);
    return Stack(
      children: [
        Positioned.fill(
          child: FadeTransition(
            opacity: _anim,
            child: GestureDetector(onTap: () => m.resolve(false), child: const ColoredBox(color: Color(0x730A1423))),
          ),
        ),
        Center(
          child: FadeTransition(
            opacity: _anim,
            child: AnimatedBuilder(
              animation: curved,
              builder: (context, child) => Transform.scale(scale: 0.96 + 0.04 * curved.value, child: child),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                constraints: BoxConstraints(maxWidth: 420, maxHeight: MediaQuery.sizeOf(context).height * 0.85),
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.cardLg), boxShadow: shadowFloat),
                child: Semantics(
                  scopesRoute: true,
                  explicitChildNodes: true,
                  namesRoute: true,
                  label: m.title,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(m.title, style: ts(18.5, weight: FontWeight.w700, height: 1.4, letterSpacing: -0.03)),
                        for (final p in m.paragraphs)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text.rich(TextSpan(children: boldMarkup(p)), style: ts(14, color: AppColors.text2, height: 1.55)),
                          ),
                        if (m.rows.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          KvRows([
                            for (final r in m.rows)
                              KvRow(r.label, Text(r.value, textAlign: TextAlign.right, style: ts(r.strong ? 15 : 14, weight: FontWeight.w700))),
                          ]),
                        ],
                        if (m.fineprint != null) Fineprint(m.fineprint!),
                        const SizedBox(height: 18),
                        ButtonRow([
                          AppButton(m.cancelText, kind: BtnKind.ghost, onPressed: () => m.resolve(false)),
                          AppButton(m.confirmText, kind: m.danger ? BtnKind.danger : BtnKind.primary, onPressed: () => m.resolve(true)),
                        ]),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/* ==================================================================
 * 업무 모달 (기존 업무 화면)
 * ================================================================== */

class TaskModalLayer extends StatefulWidget {
  const TaskModalLayer({super.key, required this.app});

  final AppController app;

  @override
  State<TaskModalLayer> createState() => _TaskModalLayerState();
}

class _TaskModalLayerState extends State<TaskModalLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  TaskModalState? _shown;

  @override
  void initState() {
    super.initState();
    widget.app.addListener(_sync);
  }

  void _sync() {
    final next = widget.app.taskModal;
    if (next == _shown) return;
    if (next != null) {
      setState(() => _shown = next);
      _anim.forward(from: 0);
    } else {
      _anim.reverse().whenComplete(() {
        if (mounted && widget.app.taskModal == null) setState(() => _shown = null);
      });
    }
  }

  @override
  void dispose() {
    widget.app.removeListener(_sync);
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _shown;
    if (s == null) return const SizedBox.shrink();
    final curved = CurvedAnimation(parent: _anim, curve: appEase);
    final t = getTask(s.taskId)!;
    final app = widget.app;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Stack(
      children: [
        Positioned.fill(child: FadeTransition(opacity: _anim, child: const ColoredBox(color: AppColors.backdrop))),
        Align(
          alignment: Alignment.bottomCenter,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
            child: Container(
              width: double.infinity,
              constraints: BoxConstraints(maxWidth: kSheetMaxWidth, maxHeight: MediaQuery.sizeOf(context).height * 0.92),
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
              child: ListenableBuilder(
                listenable: s,
                builder: (context, _) {
                  final running = s.running;
                  final finished = s.finished;
                  final result = taskModalStatus[s.status];
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 18, 10, 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(t.menu, style: ts(12, weight: FontWeight.w700, color: AppColors.blue)),
                                  const SizedBox(height: 2),
                                  Text(t.label, style: ts(19, weight: FontWeight.w700, letterSpacing: -0.03)),
                                ],
                              ),
                            ),
                            AppIconButton(icon: AppIcons.x, label: '닫기', onTap: app.taskModalClose),
                          ],
                        ),
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(AppRadius.card)),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                                      child: SvgIcon(AppIcons.task(t.icon), size: 22, color: AppColors.blue),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(t.desc, style: ts(13.5, height: 1.5)),
                                          const SizedBox(height: 4),
                                          Row(children: [
                                            SvgIcon(AppIcons.clock, size: 13, color: AppColors.text3),
                                            const SizedBox(width: 4),
                                            Text('약 ${t.minutes}분', style: ts(12, color: AppColors.text3)),
                                          ]),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (t.prep.isNotEmpty) ...[
                                const _TmHead('준비물'),
                                for (final p in t.prep) Text('· $p', style: ts(13.5, color: AppColors.text2, height: 1.6)),
                              ],
                              if (t.fields.isNotEmpty) ...[
                                const _TmHead('입력'),
                                for (final f in t.fields) ...[
                                  Text(f.label, style: ts(13, weight: FontWeight.w700, color: AppColors.text2)),
                                  const SizedBox(height: 6),
                                  ChipWrap([
                                    for (final o in f.options)
                                      AnswerChip(
                                        o,
                                        selected: s.input[f.id] == o,
                                        onTap: running || finished ? null : () => app.taskModalField(f.id, o),
                                      ),
                                  ]),
                                  const SizedBox(height: 10),
                                ],
                              ],
                              const _TmHead('진행 단계'),
                              for (var i = 0; i < t.steps.length; i++)
                                Builder(builder: (context) {
                                  final done = finished
                                      ? (s.status == 'COMPLETED' || s.status == 'IN_PROGRESS' || (s.status == 'PARTIAL' && i < t.steps.length - 1))
                                      : running && i < s.progress;
                                  final cur = running && i == s.progress;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        AnimatedContainer(
                                          duration: const Duration(milliseconds: 200),
                                          width: 22,
                                          height: 22,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: done ? AppColors.success : (cur ? AppColors.blue : AppColors.neutralBg),
                                            shape: BoxShape.circle,
                                          ),
                                          child: done
                                              ? SvgIcon(AppIcons.check, size: 13, color: Colors.white)
                                              : Text('${i + 1}', style: ts(11, weight: FontWeight.w700, color: cur ? Colors.white : AppColors.text3)),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            t.steps[i],
                                            style: ts(13.5, weight: cur ? FontWeight.w700 : FontWeight.w400, color: done || cur ? AppColors.text : AppColors.text2),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              if (result != null) ...[
                                const SizedBox(height: 8),
                                Builder(builder: (context) {
                                  final c = ToneColors.of(result.$1);
                                  return Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(12)),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(result.$2, style: ts(14, weight: FontWeight.w700, color: c.text)),
                                        if (s.message.isNotEmpty) ...[const SizedBox(height: 3), Text(s.message, style: ts(13, color: c.text, height: 1.5))],
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(22, 10, 22, 16 + (bottom > 0 ? bottom : 6)),
                        child: running
                            ? const AppButton('처리 중', loading: true)
                            : finished
                                ? AppButton(s.mode == 'ai' ? '닫고 은행 기록 확인' : '닫기', onPressed: app.taskModalClose)
                                : ButtonRow([
                                    AppButton('닫기', kind: BtnKind.ghost, onPressed: app.taskModalClose),
                                    AppButton('진행하기', onPressed: app.taskModalRun),
                                  ]),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TmHead extends StatelessWidget {
  const _TmHead(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(text, style: ts(14, weight: FontWeight.w700)),
      );
}

/* ==================================================================
 * 토스트
 * ================================================================== */

class ToastLayer extends StatelessWidget {
  const ToastLayer({super.key, required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => IgnorePointer(
        child: Column(
          children: [
            for (final t in app.toasts) Padding(key: ValueKey(t.id), padding: const EdgeInsets.only(bottom: 8), child: _Toast(t)),
          ],
        ),
      ),
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast(this.t);

  final ToastMessage t;

  @override
  Widget build(BuildContext context) {
    final dot = switch (t.tone) {
      UiTone.success => const Color(0xFF4ADE80),
      UiTone.warning => const Color(0xFFFBBF24),
      UiTone.danger => const Color(0xFFF87171),
      _ => null,
    };
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 250),
      curve: appEase,
      builder: (context, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, -10 * (1 - v)), child: child)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(color: AppColors.toastBg, borderRadius: BorderRadius.circular(12), boxShadow: shadowFloat),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot != null) ...[
              Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: 8),
            ],
            Flexible(child: Text(t.text, style: ts(13, color: Colors.white, height: 1.45))),
          ],
        ),
      ),
    );
  }
}
