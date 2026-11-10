import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/overlays.dart';
import '../../app/router.dart';
import '../../app/screen_data.dart';
import '../../domain/bank_state.dart';
import '../../domain/formatters.dart';
import '../../domain/fsm.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets.dart';

class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key, required this.entry});

  final RouteEntry entry;

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  final _amount = TextEditingController();
  final _focus = FocusNode();
  int _shownVersion = -1;

  TransferDraft _draft(BuildContext context) {
    final data = widget.entry.data is TransferData ? widget.entry.data as TransferData : null;
    final app = AppScope.controllerOf(context);
    return data?.draft.data?.draft ?? app.session.lastDraft ?? BankState.initial().transfer;
  }

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncText();
  }

  @override
  void didUpdateWidget(TransferScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncText();
  }

  /// 화면을 다시 그릴 때마다 은행 이체 초안의 금액으로 맞춘다.
  void _syncText() {
    if (_shownVersion == widget.entry.version && _amount.text.isNotEmpty) return;
    _shownVersion = widget.entry.version;
    _amount.text = groupDigits(_draft(context).amount);
  }

  void _commit() {
    final n = digitsOf(_amount.text);
    if (n > 0) AppScope.controllerOf(context).commitAmount(n);
  }

  void _add(int v) {
    final n = digitsOf(_amount.text) + v;
    setState(() => _amount.text = groupDigits(n));
    AppScope.controllerOf(context).commitAmount(n);
  }

  void _clear() {
    setState(() => _amount.clear());
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _amount.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    final data = widget.entry.data is TransferData ? widget.entry.data as TransferData : null;
    final draftOk = data?.draft.ok ?? false;
    final draft = _draft(context);
    final tx = data?.draft.data?.transaction;
    final cs = data?.customer;
    final st = app.fsm.state;
    final s = app.session;
    final returned = widget.entry.params['returned'] == true || (s.returnedFromPass && st == FsmState.readyToRetry);
    final editable = (st == FsmState.idle || st == FsmState.completed) &&
        !const [TransferStatus.pending, TransferStatus.unknown, TransferStatus.success].contains(draft.status);
    final unresolved = tx != null && tx.status.isUnresolved;
    final done = tx != null && tx.status == TransferStatus.success;
    final balance = cs?.ok == true ? formatWon(cs!.data!.balance) : '확인 불가';
    final amountNow = digitsOf(_amount.text);

    final top = <Widget>[
      if (!draftOk) NoticeBox(body: '일시적으로 은행 시스템에 연결할 수 없어요. 잠시 후 다시 시도해 주세요.', tone: UiTone.warning, icon: AppIcons.alert),
      if (returned && !done && !unresolved)
        NoticeBox(
          title: 'WON 해결패스에서 돌아왔어요.',
          body: '확인한 이체 정보를 그대로 유지했어요. 받는 분과 금액을 확인한 뒤 직접 이체해 주세요. 자동으로 이체되지 않아요.',
          tone: UiTone.success,
          icon: AppIcons.shield,
        ),
      if (unresolved)
        NoticeBox(
          title: '이전 이체 요청의 결과가 확정되지 않았어요.',
          body: '중복 출금을 막기 위해 새로 이체하지 말고 결과를 먼저 조회해 주세요.',
          tone: UiTone.warning,
          icon: AppIcons.clock,
        ),
      if (done)
        NoticeBox(
          spans: [const TextSpan(text: '이 이체는 은행 처리 결과 '), bold('성공'), TextSpan(text: '으로 확인되었어요. (${tx.id})')],
          tone: UiTone.success,
          icon: AppIcons.check,
        ),
    ];

    final Widget footer;
    if (unresolved) {
      footer = AppButton('거래 결과 조회', size: BtnSize.lg, onPressed: app.openResult);
    } else if (done) {
      footer = AppButton('결과 보기', size: BtnSize.lg, kind: BtnKind.secondary, onPressed: app.openResult);
    } else {
      footer = AppButton(
        '이체하기',
        size: BtnSize.lg,
        loading: app.transferLoading,
        onPressed: () {
          _focus.unfocus();
          return app.attemptTransfer(editable ? _amount.text : null);
        },
      );
    }

    final hint = editable
        ? (amountNow > 0 ? formatMan(amountNow) : '보낼 금액을 입력해 주세요')
        : '${formatMan(draft.amount)} · 해결패스에서 확인한 금액을 유지하고 있어요';

    return ScreenFrame(
      white: true,
      appBar: WspAppBar(title: '이체', onBack: app.back),
      footer: footer,
      children: [
        for (var i = 0; i < top.length; i++) ...[if (i > 0) const SizedBox(height: 12), top[i]],
        if (top.isNotEmpty) const SizedBox(height: 12),
        CardBox(
          outline: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Field(
                label: '출금 계좌',
                first: true,
                value: Text(cs?.data?.accountName ?? '우리 주거래 통장', style: ts(16, weight: FontWeight.w700)),
                sub: '우리은행 ${draft.fromAccount} · 출금가능 $balance',
              ),
              _Field(
                label: '받는 분',
                last: true,
                value: Row(
                  children: [
                    Avatar(draft.recipient),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(draft.recipient, style: ts(16, weight: FontWeight.w700)),
                          const SizedBox(height: 3),
                          Text('${draft.recipientBank} ${draft.recipientAccount}', style: ts(13, color: AppColors.text2)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        CardBox(
          outline: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('보낼 금액', style: ts(12, weight: FontWeight.w700, color: AppColors.text3)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.only(top: 4, bottom: 6),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: editable ? AppColors.blue : AppColors.lineStrong, width: 2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _amount,
                        focusNode: _focus,
                        enabled: editable,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, _GroupFormatter()],
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) => _commit(),
                        style: ts(28, weight: FontWeight.w700, letterSpacing: -0.02),
                        decoration: const InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          hintText: '0',
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text('원', style: ts(22, weight: FontWeight.w700)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(hint, style: ts(13, color: AppColors.text2)),
              if (editable) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (label, v) in const [('+1만', 10000), ('+10만', 100000), ('+50만', 500000), ('+100만', 1000000)])
                      ChoiceChipButton(label: label, onTap: () => _add(v)),
                    ChoiceChipButton(label: '정정', onTap: _clear),
                  ],
                ),
              ],
            ],
          ),
        ),
        const Fineprint('가상 계좌·가상 금액이며 실제 거래는 발생하지 않습니다. 이체 버튼을 누르면 은행이 현재 상태를 먼저 검사합니다.'),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, this.sub, this.first = false, this.last = false});

  final String label;
  final Widget value;
  final String? sub;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(top: first ? 2 : 14, bottom: last ? 4 : 14),
      decoration: BoxDecoration(border: last ? null : const Border(bottom: BorderSide(color: AppColors.line))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: ts(12, weight: FontWeight.w700, color: AppColors.text3)),
          const SizedBox(height: 6),
          value,
          if (sub != null) ...[
            const SizedBox(height: 3),
            Text(sub!, style: ts(13, color: AppColors.text2)),
          ],
        ],
      ),
    );
  }
}

/// 숫자를 천 단위로 묶어 표시한다 (최대 13자리)
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
