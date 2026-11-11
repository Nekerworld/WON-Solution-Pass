import 'package:flutter/material.dart';

import '../app/case_controller.dart';
import '../app/overlays.dart';
import '../domain/formatters.dart';
import 'theme.dart';
import 'widgets.dart';

/* ==================================================================
 * 하단 시트
 * ================================================================== */

class SheetLayer extends StatefulWidget {
  const SheetLayer({super.key, required this.app});

  final CaseController app;

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
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Stack(
      children: [
        Positioned.fill(
          child: FadeTransition(
            opacity: _anim,
            child: GestureDetector(
              onTap: widget.app.dismissSheet,
              child: const ColoredBox(color: AppColors.backdrop),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 1.05), end: Offset.zero).animate(curved),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.88),
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(22, 10, 22, 24 + bottomInset),
                  child: ListenableBuilder(
                    listenable: sheet,
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
                        if (sheet is DiagnosisSheetState) _DiagnosisSheet(sheet: sheet, app: widget.app),
                        if (sheet is AccountSheetState) _AccountSheet(sheet: sheet, app: widget.app),
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

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.title, this.desc);

  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: ts(20, weight: FontWeight.w700, letterSpacing: -0.03)),
        const SizedBox(height: 4),
        Text(desc, style: ts(14, color: AppColors.text2, height: 1.5)),
      ],
    );
  }
}

class _DiagnosisSheet extends StatelessWidget {
  const _DiagnosisSheet({required this.sheet, required this.app});

  final DiagnosisSheetState sheet;
  final CaseController app;

  @override
  Widget build(BuildContext context) {
    final summary = sheet.summary;
    if (summary == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: Spinner()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(summary.title, style: ts(20, weight: FontWeight.w700, height: 1.4, letterSpacing: -0.03)),
        const SizedBox(height: 8),
        Text(summary.body, style: ts(15, color: AppColors.text2, height: 1.55)),
        const SizedBox(height: 18),
        AppButton(summary.buttonLabel, size: BtnSize.lg, onPressed: app.diagContinue),
      ],
    );
  }
}

class _AccountSheet extends StatelessWidget {
  const _AccountSheet({required this.sheet, required this.app});

  final AccountSheetState sheet;
  final CaseController app;

  @override
  Widget build(BuildContext context) {
    final c = sheet.customer;
    final txs = sheet.transactions.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SheetTitle('계좌 조회', '가상 계좌 정보예요.'),
        const SizedBox(height: 12),
        CardBox(
          outline: true,
          child: KvRows([
            KvRow.text('계좌', c.accountName),
            KvRow.text('계좌번호', c.accountNumber),
            KvRow.text('잔액', formatWon(c.balance)),
          ]),
        ),
        const SectionTitle('최근 거래'),
        CardBox(
          outline: true,
          tight: true,
          child: txs.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: Text('최근 거래가 없어요', style: ts(13, color: AppColors.text3))),
                )
              : Column(
                  children: [
                    for (var i = 0; i < txs.length; i++)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          border: i == txs.length - 1 ? null : const Border(bottom: BorderSide(color: AppColors.line)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(txs[i].recipient, style: ts(14)),
                                  const SizedBox(height: 2),
                                  Text('${txs[i].id} · ${txs[i].status.code}', style: ts(12, color: AppColors.text3)),
                                ],
                              ),
                            ),
                            Text(formatWon(txs[i].amount), style: ts(14, weight: FontWeight.w700)),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        AppButton('닫기', kind: BtnKind.secondary, onPressed: app.closeSheet),
      ],
    );
  }
}

/* ==================================================================
 * 확인 모달
 * ================================================================== */

class ModalLayer extends StatefulWidget {
  const ModalLayer({super.key, required this.app});

  final CaseController app;

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
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Stack(
      children: [
        Positioned.fill(
          child: FadeTransition(
            opacity: _anim,
            child: GestureDetector(
              onTap: () => m.resolve(false),
              child: const ColoredBox(color: Color(0x730A1423)),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: FadeTransition(
            opacity: _anim,
            child: AnimatedBuilder(
              animation: curved,
              builder: (context, child) => Transform.translate(offset: Offset(0, 40 * (1 - curved.value)), child: child),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(22, 24, 22, 24 + bottomInset),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
                ),
                child: Semantics(
                  scopesRoute: true,
                  explicitChildNodes: true,
                  namesRoute: true,
                  label: m.title,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(m.title, style: ts(19, weight: FontWeight.w700, height: 1.4, letterSpacing: -0.03)),
                      const SizedBox(height: 6),
                      if (m.body != null) Text(m.body!, style: ts(14, color: AppColors.text2, height: 1.55)),
                      if (m.rows.isNotEmpty)
                        KvRows([
                          for (final r in m.rows)
                            KvRow(
                              r.label,
                              Text(
                                r.value,
                                textAlign: TextAlign.right,
                                style: ts(14, weight: FontWeight.w700),
                              ),
                            ),
                        ]),
                      if (m.fineprint != null) Fineprint(m.fineprint!),
                      const SizedBox(height: 18),
                      ButtonRow([
                        AppButton(m.cancelText, kind: BtnKind.ghost, onPressed: () => m.resolve(false)),
                        AppButton(m.confirmText, onPressed: () => m.resolve(true)),
                      ]),
                    ],
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
 * 토스트
 * ================================================================== */

class ToastLayer extends StatelessWidget {
  const ToastLayer({super.key, required this.app});

  final CaseController app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => IgnorePointer(
        child: Column(
          children: [
            for (final t in app.toasts)
              Padding(
                key: ValueKey(t.id),
                padding: const EdgeInsets.only(bottom: 8),
                child: _Toast(t),
              ),
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
