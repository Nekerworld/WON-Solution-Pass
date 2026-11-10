import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/case_controller.dart';
import '../../app/overlays.dart';
import '../../app/router.dart';
import '../../app/screen_data.dart';
import '../../domain/formatters.dart';
import '../../domain/fsm.dart';
import '../../domain/pathfinder.dart';
import '../../domain/policy.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets.dart';

/// 해결패스에서 연결된 화면이면 위에 안내를 띄운다.
Widget? _passLinkedNotice(CaseController app, String actionId) {
  if (app.fsm.state != FsmState.waitingUser) return null;
  final label = getAction(actionId)!.label;
  return NoticeBox(
    title: 'WON 해결패스에서 연결된 화면이에요.',
    body: '$label을 마치면 해결패스가 은행 상태를 다시 확인해요.',
    tone: UiTone.info,
    icon: AppIcons.spark,
  );
}

/// 처리 중 화면 (3단계 진행 표시)
class _ProcessingView extends StatelessWidget {
  const _ProcessingView({required this.title, required this.icon, required this.heroTitle, required this.steps, required this.fineprint});

  final String title;
  final SvgArt icon;
  final String heroTitle;
  final List<String> steps;
  final String fineprint;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    final progress = app.progress;
    return ScreenFrame(
      white: true,
      appBar: WspAppBar(title: title, noBack: true),
      children: [
        FlowHero(icon: icon, title: heroTitle, desc: '잠시만 기다려 주세요.'),
        const SizedBox(height: 16),
        CardBox(
          outline: true,
          child: ListenableBuilder(
            listenable: progress ?? ValueNotifier(0),
            builder: (context, _) {
              final done = progress?.done ?? 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    for (var i = 0; i < steps.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      Row(
                        children: [
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: Center(
                              child: i < done
                                  ? PopIn(
                                      child: Container(
                                        width: 22,
                                        height: 22,
                                        alignment: Alignment.center,
                                        decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
                                        child: SvgIcon(AppIcons.check, size: 14, color: Colors.white),
                                      ),
                                    )
                                  : const Spinner(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            steps[i],
                            style: ts(14, weight: i < done ? FontWeight.w700 : FontWeight.w400, color: i < done ? AppColors.text : AppColors.text2),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
        Fineprint(fineprint),
      ],
    );
  }
}

/// 완료 화면
class _DoneView extends StatelessWidget {
  const _DoneView({required this.title, required this.heroTitle, this.amount, required this.desc});

  final String title;
  final String heroTitle;
  final String? amount;
  final String desc;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    final waiting = app.fsm.state == FsmState.waitingUser;
    return ScreenFrame(
      white: true,
      appBar: WspAppBar(title: title, noBack: true),
      footer: waiting
          ? AppButton('해결패스로 돌아가기', size: BtnSize.lg, onPressed: app.returnFromFlow)
          : AppButton('확인', size: BtnSize.lg, onPressed: app.back),
      children: [
        ResultHead(tone: UiTone.success, icon: AppIcons.check, title: heroTitle, amount: amount, desc: desc),
        if (waiting)
          NoticeBox(body: '해결패스로 돌아가면 은행 상태를 다시 조회하고 남은 경로를 다시 계산해요.', tone: UiTone.info, icon: AppIcons.spark),
      ],
    );
  }
}

List<Widget> _spaced(List<Widget?> items, {double gap = 12}) {
  final list = items.whereType<Widget>().toList();
  return [
    for (var i = 0; i < list.length; i++) ...[if (i > 0) SizedBox(height: gap), list[i]],
  ];
}

/* ---------- 디지털 OTP ---------- */
class OtpScreen extends StatelessWidget {
  const OtpScreen({super.key, required this.entry});

  final RouteEntry entry;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    final p = entry.params;
    if (p['phase'] == 'processing') {
      return _ProcessingView(
        title: '디지털 OTP 등록',
        icon: AppIcons.phone,
        heroTitle: '디지털 OTP를 등록하고 있어요',
        steps: const ['이 기기 정보 확인', '보안 매체 등록 요청', '은행 등록 결과 확인'],
        fineprint: '시뮬레이션: 실제 OTP 번호, 인증 비밀번호, 신분증 정보는 요구하지 않습니다.',
      );
    }
    if (p['phase'] == 'done') {
      return _DoneView(title: '디지털 OTP 등록', heroTitle: '디지털 OTP 등록이 완료되었어요', desc: '은행 상태에 반영되었어요. (상태 v${p['stateVersion']})');
    }
    final data = entry.data is OtpData ? entry.data as OtpData : null;
    if (data == null || data.error != null) {
      return QueryErrorView(title: '디지털 OTP', error: data?.error, onBack: app.back, onHome: app.goHome, onRetry: app.router.rerender);
    }
    final registered = data.status.data!;
    final elig = data.eligibility.data!;

    final Widget footer;
    if (registered) {
      footer = AppButton('확인', size: BtnSize.lg, kind: BtnKind.secondary, onPressed: app.back);
    } else if (elig.eligible) {
      footer = AppButton('디지털 OTP 등록 진행', size: BtnSize.lg, onPressed: app.registerOtp);
    } else {
      footer = const AppButton('등록할 수 없어요', size: BtnSize.lg);
    }

    return ScreenFrame(
      white: true,
      appBar: WspAppBar(title: '디지털 OTP', onBack: app.back),
      footer: footer,
      children: [
        ?_passLinkedNotice(app, 'REGISTER_OTP'),
        FlowHero(icon: AppIcons.key, title: '디지털 OTP', desc: '이 휴대폰을 OTP 기기로 등록해\n고액 이체 등의 보안 인증에 사용해요.'),
        const SizedBox(height: 12),
        ..._spaced([
          CardBox(
            outline: true,
            child: KvRows([
              KvRow('현재 등록 상태', registered ? const ToneBadge('등록됨', UiTone.success) : const ToneBadge('미등록', UiTone.warning)),
              KvRow(
                '등록 가능 여부',
                registered
                    ? const ToneBadge('이미 등록됨', UiTone.neutral)
                    : elig.eligible
                        ? const ToneBadge('가능', UiTone.success)
                        : const ToneBadge('불가', UiTone.danger),
              ),
            ]),
          ),
          if (!registered && !elig.eligible) NoticeBox(body: elig.message, tone: UiTone.warning, icon: AppIcons.alert),
          if (p['error'] != null) NoticeBox(body: p['error'] as String, tone: UiTone.danger, icon: AppIcons.alert),
          NoticeBox(body: '시뮬레이션 화면이에요. 실제 OTP 번호, 인증 비밀번호, 신분증 정보는 요구하지 않습니다.', icon: AppIcons.info),
        ]),
      ],
    );
  }
}

/* ---------- 이체한도 관리 ---------- */
class LimitScreen extends StatefulWidget {
  const LimitScreen({super.key, required this.entry});

  final RouteEntry entry;

  @override
  State<LimitScreen> createState() => _LimitScreenState();
}

class _LimitScreenState extends State<LimitScreen> {
  final _custom = TextEditingController();
  int _shownVersion = -1;

  void _sync() {
    if (_shownVersion == widget.entry.version) return;
    _shownVersion = widget.entry.version;
    final custom = widget.entry.params['custom'] as int?;
    _custom.text = custom != null ? groupDigits(custom) : '';
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(LimitScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    final p = widget.entry.params;
    if (p['phase'] == 'done') {
      return _DoneView(
        title: '이체한도 관리',
        heroTitle: '1일 이체한도가 변경되었어요',
        amount: formatWon(p['newLimit'] as int?),
        desc: '이전 한도 ${formatWon(p['previousLimit'] as int?)} · 은행 상태에 반영됨 (상태 v${p['stateVersion']})',
      );
    }
    final data = widget.entry.data is LimitData ? widget.entry.data as LimitData : null;
    if (data == null || data.error != null) {
      return QueryErrorView(title: '이체한도 관리', error: data?.error, onBack: app.back, onHome: app.goHome, onRetry: app.router.rerender);
    }
    final lim = data.limit.data!;
    final otp = data.otp.data!;
    final draftAmount = data.draft.data!.draft.amount;
    final selected = data.selected;
    final check = p['check'] as LimitCheckView?;
    final canApply = check != null && check.allowed && check.value == selected;

    final footer = canApply
        ? AppButton('이 한도로 변경', size: BtnSize.lg, onPressed: () => app.limitApply(selected!))
        : AppButton('변경 가능 여부 확인', size: BtnSize.lg, onPressed: () => app.limitCheck(_custom.text));

    Widget? checkBox;
    if (check != null) {
      checkBox = FadeIn(
        child: check.allowed
            ? NoticeBox(
                spans: [bold(formatWon(check.value)), const TextSpan(text: '으로 변경할 수 있어요. 아래 버튼을 눌러 변경을 확정해 주세요.')],
                tone: UiTone.success,
                icon: AppIcons.check,
              )
            : NoticeBox(
                spans: [
                  bold(formatWon(check.value)),
                  TextSpan(text: '으로 변경할 수 없어요.\n${check.reasons.map((r) => '· ${r.message}').join('\n')}'),
                ],
                tone: UiTone.danger,
                icon: AppIcons.alert,
              ),
      );
    }

    return ScreenFrame(
      white: true,
      appBar: WspAppBar(title: '이체한도 관리', onBack: app.back),
      footer: footer,
      children: [
        ?_passLinkedNotice(app, 'CHANGE_TRANSFER_LIMIT'),
        const SizedBox(height: 12),
        CardBox(
          outline: true,
          child: KvRows([
            KvRow.text('현재 1일 이체한도', formatWon(lim.transferLimit)),
            KvRow('디지털 OTP', otp ? const ToneBadge('등록됨', UiTone.success) : const ToneBadge('미등록', UiTone.warning)),
            KvRow('비대면 한도 변경', lim.changeAllowed ? const ToneBadge('가능', UiTone.success) : const ToneBadge('불가', UiTone.danger)),
          ]),
        ),
        const SectionTitle('변경할 한도'),
        if (data.options.isEmpty)
          Text('선택 가능한 추천 한도가 없어요', style: ts(13, color: AppColors.text3))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in data.options)
                ChoiceChipButton(
                  label: formatMan(v),
                  selected: v == selected,
                  tag: v == data.recommended && draftAmount > lim.transferLimit ? '이체 금액 기준' : null,
                  onTap: () => app.limitSelect(v),
                ),
            ],
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _custom,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, _GroupFormatter()],
          style: ts(15),
          decoration: InputDecoration(
            hintText: '직접 입력 (원)',
            hintStyle: ts(15, color: AppColors.text3),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.lineStrong),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.blue),
            ),
          ),
        ),
        if (checkBox != null) ...[const SizedBox(height: 14), checkBox],
        Fineprint(
          '데모용 가상 정책: ${formatWon(DemoPolicy.maxLimitWithoutOtp)}을 초과하는 한도는 디지털 OTP 등록 후 변경할 수 있어요. 실제 우리은행 정책이 아닙니다. 변경 가능 여부는 가상 은행이 판정합니다.',
        ),
      ],
    );
  }
}

class _GroupFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length > 13) digits = digits.substring(0, 13);
    final n = int.tryParse(digits) ?? 0;
    final text = n == 0 ? '' : groupDigits(n);
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/* ---------- 고객확인 ---------- */
class KycScreen extends StatelessWidget {
  const KycScreen({super.key, required this.entry});

  final RouteEntry entry;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    final p = entry.params;
    if (p['phase'] == 'processing') {
      return _ProcessingView(
        title: '고객확인',
        icon: AppIcons.idcard,
        heroTitle: '고객확인을 진행하고 있어요',
        steps: const ['보유 정보 확인', '고객확인 처리 요청', '은행 처리 결과 확인'],
        fineprint: '시뮬레이션: 신분증 촬영 등 실제 개인정보는 요구하지 않습니다.',
      );
    }
    if (p['phase'] == 'done') {
      return _DoneView(title: '고객확인', heroTitle: '고객확인이 완료되었어요', desc: '은행 상태에 반영되었어요. (상태 v${p['stateVersion']})');
    }
    final data = entry.data is KycData ? entry.data as KycData : null;
    if (data == null || data.error != null) {
      return QueryErrorView(title: '고객확인', error: data?.error, onBack: app.back, onHome: app.goHome, onRetry: app.router.rerender);
    }
    final completed = data.kyc.data!;
    final restricted = data.customer.data!.accountRestricted;

    final Widget footer;
    if (completed) {
      footer = AppButton('확인', size: BtnSize.lg, kind: BtnKind.secondary, onPressed: app.back);
    } else if (restricted) {
      footer = const AppButton('진행할 수 없어요', size: BtnSize.lg);
    } else {
      footer = AppButton('고객확인 진행', size: BtnSize.lg, onPressed: app.completeKyc);
    }

    return ScreenFrame(
      white: true,
      appBar: WspAppBar(title: '고객확인', onBack: app.back),
      footer: footer,
      children: [
        ?_passLinkedNotice(app, 'COMPLETE_KYC'),
        FlowHero(icon: AppIcons.idcard, title: '고객확인', desc: '안전한 금융거래를 위해\n고객 정보를 확인하는 절차예요.'),
        const SizedBox(height: 12),
        ..._spaced([
          CardBox(
            outline: true,
            child: KvRows([
              KvRow('고객확인 상태', completed ? const ToneBadge('완료', UiTone.success) : const ToneBadge('미완료', UiTone.warning)),
            ]),
          ),
          if (restricted && !completed)
            NoticeBox(body: '계좌 이용 제한 상태에서는 진행할 수 없어요. 상담 창구에서 확인해 주세요.', tone: UiTone.danger, icon: AppIcons.lock),
          if (p['error'] != null) NoticeBox(body: p['error'] as String, tone: UiTone.danger, icon: AppIcons.alert),
          NoticeBox(body: '시뮬레이션 화면이에요. 신분증, 주민등록번호 등 실제 개인정보는 요구하지 않습니다.', icon: AppIcons.info),
        ]),
      ],
    );
  }
}
