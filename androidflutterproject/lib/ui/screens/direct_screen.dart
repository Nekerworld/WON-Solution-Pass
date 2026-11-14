/// 직접 가입: 기존 가입 화면처럼 단계별로 입력하고, 단계마다 은행 조건을 확인한다.
/// 부족한 조건은 안내만 하고, 고객이 직접 메뉴를 찾아 해결한 뒤 처음부터 다시 시작한다.
library;

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app/overlays.dart';
import '../../app/router.dart';
import '../../app/sessions.dart';
import '../../domain/formatters.dart';
import '../../domain/scenario.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets.dart';

class DirectScreen extends StatefulWidget {
  const DirectScreen({super.key, required this.entry});

  final RouteEntry entry;

  @override
  State<DirectScreen> createState() => _DirectScreenState();
}

class _DirectScreenState extends State<DirectScreen> {
  TextEditingController? _monthly;

  @override
  void dispose() {
    _monthly?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    final d = app.session.direct;
    if (d == null) {
      return EmptyScreen(title: '직접 가입', message: '진행 중인 직접 가입이 없어요.', buttonLabel: '상품 보기', onButton: app.goProducts, onBack: app.back);
    }
    final p = getProduct(d.productId)!;
    final st = app.directFsm.state;
    final onAmount = (st == 'D_STEP' || st == 'D_CHECK') && p.directSteps[d.stepIndex].id == 'amount';
    if (!onAmount && _monthly != null) {
      final old = _monthly!;
      _monthly = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    final body = <Widget>[];
    Widget? foot;

    if (st == 'D_START') {
      body.add(CardBox(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CardTitle('직접 가입 안내', icon: AppIcons.doc),
            Text('아래 단계를 차례로 입력해요. 각 단계에서 가입 조건을 확인하고, 부족하면 해당 메뉴에서 먼저 처리해야 해요.', style: ts(14, color: AppColors.text2, height: 1.55)),
          ],
        ),
      ));
      foot = AppButton('가입 시작', onPressed: app.direct.begin);
    } else if (st == 'D_STEP' || st == 'D_CHECK') {
      final step = p.directSteps[d.stepIndex];
      body
        ..add(_StepTitle('${d.stepIndex + 1}. ${step.label}'))
        ..add(_stepForm(app, p, d, step));
      foot = AppButton(d.checking ? '확인 중' : '다음', loading: d.checking, onPressed: d.checking ? null : () => app.guard('direct-next', app.direct.next));
    } else if (st == 'D_NOTICE') {
      final n = d.notice;
      body.add(CardBox(
        color: AppColors.warningBg,
        outline: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CardTitle('${n?.stepLabel ?? ''} 단계를 진행할 수 없어요', icon: AppIcons.alert, color: AppColors.warningText),
            for (final c in n?.conditions ?? const <NoticeCondition>[])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(padding: const EdgeInsets.only(top: 3), child: SvgIcon(AppIcons.x, size: 14, color: AppColors.danger)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.label, style: ts(14, weight: FontWeight.w700)),
                          if (c.menu != null) Text('전체 메뉴 > ${c.menu}에서 처리', style: ts(12.5, color: AppColors.text2)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const Fineprint('해결한 뒤 가입을 처음부터 다시 진행해 주세요. 입력한 내용은 저장되지 않아요.', top: 4),
          ],
        ),
      ));
      foot = ButtonRow([
        AppButton('그만하기', kind: BtnKind.ghost, onPressed: app.direct.exit),
        AppButton('메뉴로 이동', onPressed: app.direct.goFix),
      ]);
    } else if (st == 'D_SELF_FIX') {
      body.add(const NoticeBox(body: '부족한 조건을 메뉴에서 해결한 뒤, 가입을 처음부터 다시 진행해 주세요.', tone: UiTone.info));
      foot = ButtonRow([
        AppButton('전체 메뉴', kind: BtnKind.secondary, onPressed: () => app.goMenu()),
        AppButton('처음부터 다시', onPressed: app.direct.restart),
      ]);
    } else if (st == 'D_APPROVE') {
      body
        ..add(const _StepTitle('가입 신청 확인'))
        ..add(Column(children: [
          if (d.applyNotice != null) ...[NoticeBox(body: d.applyNotice, tone: UiTone.warning, icon: AppIcons.alert), const SizedBox(height: 10)],
          CardBox(
            child: KvRows([
              KvRow.text('상품', p.name),
              if (p.maxMonthly > 0) KvRow.text('월 납입액', formatMan(d.input.monthly)),
              if (p.periods.isNotEmpty) KvRow.text('가입 기간', '${d.input.months}개월'),
            ]),
          ),
        ]));
      foot = AppButton('가입 신청', loading: d.checking, onPressed: d.checking ? null : () => app.guard('direct-approve', app.direct.approve));
    } else {
      body.add(const LeadText('가입 요청 결과를 확인해 주세요.'));
      foot = AppButton('가입 결과 보기', onPressed: app.direct.open);
    }

    return ScreenFrame(
      appBar: WspAppBar(
        title: '${p.name} 가입',
        onBack: app.back,
        right: app.directFsm.can('EXIT')
            ? TextButton(
                onPressed: app.direct.exit,
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(48, 40)),
                child: Text('그만하기', style: ts(13, color: AppColors.text2)),
              )
            : null,
      ),
      footer: foot,
      children: [_Stepper(product: p, index: d.stepIndex, state: st), ...body],
    );
  }

  Widget _stepForm(AppController app, ProductDef p, DirectSession d, DirectStep step) {
    switch (step.id) {
      case 'terms':
        return Column(
          children: [
            CardBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CardTitle(p.name),
                  Text(p.summary, style: ts(13.5, color: AppColors.text2, height: 1.55)),
                  KvRows([KvRow.text(p.rateLabel ?? '금리', p.rateValue ?? p.rate)]),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Material(
              color: d.input.agreed ? AppColors.blueLight : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
                side: BorderSide(color: d.input.agreed ? AppColors.blue : AppColors.lineStrong),
              ),
              child: InkWell(
                key: const ValueKey('direct-agree'),
                onTap: app.direct.toggleAgree,
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: d.input.agreed ? AppColors.blue : Colors.white,
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(color: d.input.agreed ? AppColors.blue : AppColors.lineStrong, width: 1.5),
                        ),
                        child: d.input.agreed ? SvgIcon(AppIcons.check, size: 15, color: Colors.white) : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text('상품 설명서와 약관을 확인했어요', style: ts(14.5, weight: FontWeight.w700))),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      case 'amount':
        final ctrl = _monthly ??= TextEditingController(text: d.input.monthly > 0 ? '${d.input.monthly}' : '');
        return CardBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (p.maxMonthly > 0) ...[
                Text('월 납입액', style: ts(13, weight: FontWeight.w700, color: AppColors.text2)),
                const SizedBox(height: 6),
                TextField(
                  key: const ValueKey('direct-monthly'),
                  controller: ctrl,
                  keyboardType: TextInputType.number,
                  onChanged: app.direct.setMonthly,
                  style: ts(15),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.lineStrong)),
                  ),
                ),
                const SizedBox(height: 4),
                Text('${formatMan(p.minMonthly)} ~ ${formatMan(p.maxMonthly)}', style: ts(12, color: AppColors.text3)),
                const SizedBox(height: 14),
              ],
              if (p.periods.isNotEmpty) ...[
                Text('가입 기간', style: ts(13, weight: FontWeight.w700, color: AppColors.text2)),
                const SizedBox(height: 8),
                ChipWrap([for (final m in p.periods) AnswerChip('$m개월', selected: d.input.months == m, onTap: () => app.direct.setMonths(m))]),
              ],
            ],
          ),
        );
      case 'account':
        final data = widget.entry.data is AccountData ? widget.entry.data as AccountData : null;
        final r = data?.summary;
        final acc = r != null && r.ok ? r.data!.account : null;
        return CardBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.isBrokerage ? '연결 원화 계좌' : '출금 계좌', style: ts(13, weight: FontWeight.w700, color: AppColors.text2)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: acc != null ? AppColors.blueLight : AppColors.bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: acc != null ? AppColors.blue : AppColors.line),
                ),
                child: Row(
                  children: [
                    SvgIcon(AppIcons.wallet, size: 22, color: acc != null ? AppColors.blue : AppColors.muted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: acc != null
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(acc.name, style: ts(14.5, weight: FontWeight.w700)),
                                Text(acc.number, style: ts(12.5, color: AppColors.text2)),
                              ],
                            )
                          : Text('선택할 수 있는 우리은행 계좌가 없어요', style: ts(14, color: AppColors.text2)),
                    ),
                    if (acc != null) SvgIcon(AppIcons.check, size: 18, color: AppColors.blue),
                  ],
                ),
              ),
            ],
          ),
        );
      default:
        final text = switch (step.id) {
          'info' => '등록된 고객정보(직업·거래 목적)로 가입을 진행해요.',
          'identity' => '실명확인된 정보로 본인을 확인해요.',
          'sign' => '우리 인증서로 가입 신청서에 전자서명해요.',
          'fx' => '외환거래 서비스에 등록된 외화(USD) 계좌를 연결해요.',
          'profile' => '등록된 투자성향으로 해외주식 거래 가능 여부를 확인해요.',
          _ => '',
        };
        return CardBox(
          child: Row(
            children: [
              if (step.id == 'sign') ...[SvgIcon(AppIcons.key, size: 18, color: AppColors.blue), const SizedBox(width: 8)],
              Expanded(child: Text(text, style: ts(14, color: AppColors.text2, height: 1.55))),
            ],
          ),
        );
    }
  }
}

class _StepTitle extends StatelessWidget {
  const _StepTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 8, 2, 12),
        child: Text(text, style: ts(19, weight: FontWeight.w700, letterSpacing: -0.03)),
      );
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.product, required this.index, required this.state});

  final ProductDef product;
  final int index;
  final String state;

  @override
  Widget build(BuildContext context) {
    final steps = product.directSteps;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 14),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var i = 0; i < steps.length; i++)
            Builder(builder: (context) {
              final done = state == 'D_APPROVE' || i < index;
              final current = !done && i == index && state != 'D_START';
              final bg = done ? AppColors.successBg : (current ? AppColors.blue : Colors.white);
              final fg = done ? AppColors.successText : (current ? Colors.white : AppColors.text3);
              return Container(
                padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: done || current ? Colors.transparent : AppColors.line),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: done ? AppColors.success : (current ? Colors.white : AppColors.neutralBg), shape: BoxShape.circle),
                      child: done
                          ? SvgIcon(AppIcons.check, size: 11, color: Colors.white)
                          : Text('${i + 1}', style: ts(10.5, weight: FontWeight.w700, color: current ? AppColors.blue : AppColors.text3)),
                    ),
                    const SizedBox(width: 5),
                    Text(steps[i].label, style: ts(12, weight: current ? FontWeight.w700 : FontWeight.w400, color: fg)),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
