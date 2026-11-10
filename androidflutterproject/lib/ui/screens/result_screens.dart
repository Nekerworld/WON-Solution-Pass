import 'package:flutter/material.dart';

import '../../app/overlays.dart';
import '../../app/router.dart';
import '../../app/screen_data.dart';
import '../../domain/bank_state.dart';
import '../../domain/formatters.dart';
import '../../domain/fsm.dart';
import '../../domain/pathfinder.dart';
import '../app_scope.dart';
import '../icons.dart';
import '../widgets.dart';

/* ---------- 처리 결과 ---------- */
class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.entry});

  final RouteEntry entry;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    final p = entry.params;
    final s = app.session;
    final bar = WspAppBar(title: '처리 결과', noBack: true);

    if (p['processing'] == true) {
      return ScreenFrame(
        white: true,
        appBar: bar,
        children: const [
          ResultHead(
            tone: UiTone.neutral,
            iconChild: Spinner(size: 34, stroke: 3.5),
            title: '이체 요청을 처리하고 있어요',
            desc: '은행 처리 결과를 확인한 뒤 알려드릴게요.\n화면을 닫거나 다시 이체하지 마세요.',
          ),
        ],
      );
    }

    if (p['notSent'] == true) {
      return ScreenFrame(
        white: true,
        appBar: bar,
        footer: ButtonRow([
          AppButton('홈으로', kind: BtnKind.ghost, onPressed: app.goHome),
          AppButton('상태 다시 확인', onPressed: () => app.startDiagnosis('MANUAL')),
        ]),
        children: [
          ResultHead(
            tone: UiTone.neutral,
            icon: AppIcons.alert,
            title: '이체 요청이 전송되지 않았어요',
            desc: '${p['message'] ?? ''}\n출금되지 않았어요.',
          ),
        ],
      );
    }

    final data = entry.data is ResultData ? entry.data as ResultData : null;
    if (data == null || data.transactionId == null) {
      return ScreenFrame(
        white: true,
        appBar: WspAppBar(title: '처리 결과', onBack: app.back),
        footer: AppButton('홈으로', size: BtnSize.lg, onPressed: app.goHome),
        children: [ResultHead(tone: UiTone.neutral, icon: AppIcons.info, title: '확인할 이체 결과가 없어요')],
      );
    }

    final r = data.result!;
    if (!r.ok) {
      return ScreenFrame(
        white: true,
        appBar: WspAppBar(title: '처리 결과', onBack: app.back),
        footer: ButtonRow([
          AppButton('홈으로', kind: BtnKind.ghost, onPressed: app.goHome),
          AppButton('결과 다시 조회', onPressed: app.queryResult),
        ]),
        children: [
          ResultHead(
            tone: UiTone.neutral,
            icon: AppIcons.question,
            title: '지금은 결과를 조회할 수 없어요',
            desc: '${r.error!.message}\n결과가 확인되기 전에는 완료로 표시하지 않아요.\n다시 이체하지 말고 잠시 후 조회해 주세요.',
          ),
        ],
      );
    }

    final tx = r.data!;
    final viaPass = s.resultCtx != null && s.resultCtx!.viaPass && s.resultCtx!.transactionId == tx.id;
    final completedPass = viaPass && app.fsm.state == FsmState.completed;
    final timeline = s.caseCtx?.timeline ?? const <String>[];
    final dup = p['duplicate'] == true
        ? NoticeBox(body: '같은 요청이 이미 접수되어 있어 새 거래를 만들지 않고 기존 결과를 보여드려요.', tone: UiTone.info, icon: AppIcons.shield)
        : null;

    switch (tx.status) {
      case TransferStatus.success:
        final checks = <Widget>[
          if (viaPass && timeline.contains('COMPLETE_KYC')) const VerifyItem('고객확인 · 은행 상태 확인'),
          if (viaPass && timeline.contains('REGISTER_OTP')) const VerifyItem('디지털 OTP · 은행 등록 상태 확인'),
          if (viaPass && timeline.contains('CHANGE_TRANSFER_LIMIT')) const VerifyItem('이체한도 · 은행 상태 확인'),
          VerifyItem('이체 · 은행 성공 응답 확인', sub: '거래 확인번호 ${tx.id}'),
        ];
        return ScreenFrame(
          white: true,
          appBar: bar,
          footer: AppButton('홈으로', size: BtnSize.lg, onPressed: app.goHome),
          children: [
            ResultHead(
              tone: UiTone.success,
              icon: AppIcons.check,
              title: '이체 완료를 확인했어요',
              amount: formatWon(tx.amount),
              desc: '${tx.recipient}님(${tx.recipientBank})에게 보냈어요',
              extra: completedPass
                  ? const Padding(padding: EdgeInsets.only(top: 12), child: ToneBadge('WON 해결패스 해결 완료', UiTone.success))
                  : null,
            ),
            ?dup,
            const SizedBox(height: 16),
            VerifyList(checks),
            const Fineprint('완료 표시는 가상 은행이 반환한 성공(SUCCESS) 응답을 확인한 뒤에만 보여드려요. 실제 거래가 아닌 시연용 결과입니다.'),
          ],
        );
      case TransferStatus.pending:
        return ScreenFrame(
          white: true,
          appBar: bar,
          footer: ButtonRow([
            AppButton('홈으로', kind: BtnKind.ghost, onPressed: app.goHome),
            AppButton('결과 조회', onPressed: app.queryResult),
          ]),
          children: [
            ResultHead(
              tone: UiTone.warning,
              icon: AppIcons.clock,
              title: '이체를 처리하고 있어요',
              amount: formatWon(tx.amount),
              desc: '은행 처리 결과가 아직 확정되지 않았어요.\n중복 출금을 막기 위해 다시 이체하지 마세요.',
            ),
            ?dup,
            const SizedBox(height: 16),
            VerifyList([
              VerifyItem('이체 요청 접수', sub: '거래 확인번호 ${tx.id}'),
              const VerifyItem('은행 처리 결과', sub: '확인 중 · 완료로 표시하지 않아요', state: VerifyState.pending),
            ]),
          ],
        );
      case TransferStatus.unknown:
        return ScreenFrame(
          white: true,
          appBar: bar,
          footer: ButtonRow([
            AppButton('상담 연결', kind: BtnKind.ghost, onPressed: () => app.goSupport('TRANSFER_UNKNOWN')),
            AppButton('결과 조회', onPressed: app.queryResult),
          ]),
          children: [
            ResultHead(
              tone: UiTone.warning,
              icon: AppIcons.question,
              title: '이체 결과를 확인하지 못했어요',
              amount: formatWon(tx.amount),
              desc: '성공 여부가 확정되지 않아 완료로 표시하지 않아요.\n자동으로 다시 보내지 않아요.',
            ),
            ?dup,
            const SizedBox(height: 16),
            VerifyList([
              VerifyItem('이체 요청 접수', sub: '거래 확인번호 ${tx.id}'),
              const VerifyItem('은행 처리 결과', sub: '결과 불명 · 재이체 금지', state: VerifyState.pending),
            ]),
            const SizedBox(height: 12),
            NoticeBox(
              body: '같은 이체를 다시 시도하면 중복 출금이 생길 수 있어요. 결과를 조회하거나 상담을 이용해 주세요.',
              tone: UiTone.warning,
              icon: AppIcons.alert,
            ),
          ],
        );
      default:
        return ScreenFrame(
          white: true,
          appBar: bar,
          footer: ButtonRow([
            AppButton('상담 연결', kind: BtnKind.ghost, onPressed: () => app.goSupport('TRANSFER_FAILED')),
            AppButton('다시 진단하기', onPressed: () => app.startDiagnosis('MANUAL')),
          ]),
          children: [
            ResultHead(
              tone: UiTone.danger,
              icon: AppIcons.x,
              title: '이체가 실패했어요',
              amount: formatWon(tx.amount),
              desc: '은행 처리 결과 실패로 확인되었어요.\n출금되지 않았어요.',
            ),
            const SizedBox(height: 16),
            VerifyList([VerifyItem('은행 처리 결과 · 실패', sub: tx.failureReason ?? '', state: VerifyState.fail)]),
          ],
        );
    }
  }
}

/* ---------- 상담 안내 ---------- */
class _SupportCopy {
  const _SupportCopy(this.icon, this.title, this.desc, this.primary);

  final String icon;
  final String title;
  final String desc;

  /// (동작, 버튼 문구)
  final (String, String) primary;
}

const Map<String, _SupportCopy> _supportCopy = {
  'BANK_UNAVAILABLE': _SupportCopy(
    'alert',
    '지금은 은행 상태를 확인할 수 없어요',
    '정상적으로 진단할 수 없어 안내를 멈췄어요. 확인되지 않은 상태로 해결 방법을 추측하지 않아요. 잠시 후 다시 확인해 주세요.',
    ('diagnose', '다시 확인하기'),
  ),
  'QUERY_FAILURE': _SupportCopy(
    'alert',
    '은행 상태 조회에 실패했어요',
    '상태를 확인하지 못해 해결 경로를 계산하지 않았어요. 정상 진단을 가장하지 않아요. 잠시 후 다시 확인해 주세요.',
    ('diagnose', '다시 확인하기'),
  ),
  'ACCOUNT_RESTRICTED': _SupportCopy(
    'lock',
    '계좌 이용 제한이 확인되었어요',
    '해결패스는 제한 해제 방법을 안내하지 않아요. 보호를 위해 상세 사유는 표시하지 않으며, 공식 상담 창구에서 본인 확인 후 안내받을 수 있어요.',
    ('support-connect', '상담 연결하기'),
  ),
  'INSUFFICIENT_BALANCE': _SupportCopy(
    'coin',
    '출금 가능 잔액이 부족해요',
    '잔액 부족은 설정 변경으로 해결할 수 없어요. 잔액을 확인한 뒤 다시 시도해 주세요.',
    ('go-home', '홈으로'),
  ),
  'NO_PATH': _SupportCopy(
    'question',
    '안내할 수 있는 절차를 찾지 못했어요',
    '현재 상태에서 정상 이체까지 이어지는 허용된 절차가 없어요. 상담을 통해 확인해 주세요.',
    ('support-connect', '상담 연결하기'),
  ),
  'TRANSFER_UNKNOWN': _SupportCopy(
    'question',
    '이체 결과 확인을 도와드릴게요',
    '결과가 확정되지 않은 거래는 다시 보내지 않아요. 상담사가 은행 처리 결과를 확인해 드릴 수 있어요.',
    ('support-connect', '상담 연결하기'),
  ),
  'TRANSFER_FAILED': _SupportCopy(
    'headset',
    '실패 원인 확인을 도와드릴게요',
    '은행 처리 결과 실패로 확인된 거래예요. 출금되지 않았으며, 원인 확인이 필요하면 상담을 이용해 주세요.',
    ('support-connect', '상담 연결하기'),
  ),
  'GENERAL': _SupportCopy(
    'headset',
    '상담 연결 안내',
    '해결패스가 확인한 내용과 시도한 절차를 상담사에게 전달해 같은 설명을 반복하지 않도록 도와드려요.',
    ('support-connect', '상담 연결하기'),
  ),
};

SvgArt _supportIcon(String name) => switch (name) {
      'alert' => AppIcons.alert,
      'lock' => AppIcons.lock,
      'coin' => AppIcons.coin,
      'question' => AppIcons.question,
      _ => AppIcons.headset,
    };

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key, required this.entry});

  final RouteEntry entry;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.controllerOf(context);
    final s = app.session;
    final plan = s.plan;
    final caseCtx = s.caseCtx;
    var code = (entry.params['code'] as String?) ?? caseCtx?.escalation?.code;
    if (code == null && plan != null) code = plan.status == PlanStatus.noPath ? 'NO_PATH' : plan.blocker?.code;
    final copy = _supportCopy[code] ?? _supportCopy['GENERAL']!;

    final rows = <KvRow>[];
    final ev = plan?.evaluation;
    if (ev != null) {
      final c = ev.ctx;
      rows.addAll([
        KvRow.text('요청 이체', '${c.recipient} · ${formatWon(c.amount)}'),
        KvRow.text('1일 이체한도', formatWon(c.transferLimit)),
        KvRow.text('디지털 OTP', c.otpRegistered ? '등록됨' : '미등록'),
        KvRow.text('고객확인', c.kycCompleted ? '완료' : '미완료'),
        KvRow.text('계좌 상태', c.accountRestricted ? '제한 (상세 사유 미전달)' : '정상'),
      ]);
    } else {
      rows.add(KvRow.text('확인한 상태', '은행 상태 조회 실패 · 확인된 정보 없음'));
    }
    final tried = caseCtx != null && caseCtx.timeline.isNotEmpty ? caseCtx.timeline.map((id) => getAction(id)!.label).join(', ') : '없음';
    rows.add(KvRow.text('안내된 절차', tried));
    if (caseCtx != null) rows.add(KvRow.text('사건 번호', caseCtx.caseId, mono: true));

    Future<void> runPrimary() async {
      switch (copy.primary.$1) {
        case 'diagnose':
          await app.startDiagnosis('MANUAL');
        case 'go-home':
          await app.goHome();
        default:
          await app.supportConnect();
      }
    }

    final secondary = copy.primary.$1 == 'support-connect'
        ? AppButton('홈으로', kind: BtnKind.ghost, onPressed: app.goHome)
        : AppButton('상담 연결', kind: BtnKind.ghost, onPressed: app.supportConnect);

    return ScreenFrame(
      white: true,
      appBar: WspAppBar(title: '상담 안내', onBack: app.back),
      footer: ButtonRow([secondary, AppButton(copy.primary.$2, onPressed: runPrimary)]),
      children: [
        ResultHead(
          tone: code == 'ACCOUNT_RESTRICTED' ? UiTone.danger : UiTone.warning,
          icon: _supportIcon(copy.icon),
          title: copy.title,
          desc: copy.desc,
        ),
        if (code == 'NO_PATH' && ev != null && !ev.ctx.limitChangeAllowed)
          NoticeBox(body: '확인된 사유: 이 계좌는 비대면 이체한도 변경 대상이 아니에요. (가상)', tone: UiTone.warning, icon: AppIcons.info),
        const SectionTitle('상담사에게 전달할 내용', small: '동의 시에만 전달'),
        CardBox(outline: true, child: KvRows(rows)),
        const Fineprint('해결패스는 보호 제한·사고 통제를 우회하지 않으며, 확인되지 않은 해결 방법을 만들어내지 않습니다. 상담 연결은 시연용 시뮬레이션입니다.'),
      ],
    );
  }
}
