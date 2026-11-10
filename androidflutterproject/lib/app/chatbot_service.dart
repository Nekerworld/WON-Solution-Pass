/// 규칙 기반 질의 응답: 정규화·의도 분류 → 은행 상태 조회 → 규칙 엔진 + 경로 탐색
/// → 현재 상태 기반 응답 + 기능 링크(허용 플로우 ID만).
/// - 사용자 진술과 은행 상태가 다르면 은행의 확인된 상태를 우선한다.
/// - 규칙으로 해석할 수 없는 질문에는 사실을 만들어내지 않는다.
library;

import '../data/mock_bank.dart';
import '../domain/bank_state.dart';
import '../domain/chatbot_nlu.dart';
import '../domain/event_log.dart';
import '../domain/formatters.dart';
import '../domain/pathfinder.dart';
import '../domain/policy.dart';
import '../domain/rule_engine.dart';

enum Tone { normal, warning }

class FlowLink {
  const FlowLink(this.label, this.flowId);

  final String label;
  final String flowId;

  Map<String, Object?> toJson() => {'label': label, 'flowId': flowId};

  factory FlowLink.fromJson(Map<String, Object?> j) => FlowLink(j['label'] as String, j['flowId'] as String);
}

class ChatReply {
  const ChatReply({
    required this.text,
    required this.tone,
    required this.links,
    required this.analysis,
    required this.ruleIds,
    required this.stateVersion,
    this.planStatus,
  });

  final String text;
  final Tone tone;
  final List<FlowLink> links;
  final Analysis? analysis;
  final List<String> ruleIds;
  final int? stateVersion;
  final PlanStatus? planStatus;
}

class _Said {
  bool otpConfirmed = false;
}

class _Diagnosis {
  const _Diagnosis(this.text, this.links, [this.tone = Tone.normal]);

  final String text;
  final List<FlowLink> links;
  final Tone tone;
}

const _support = FlowLink('상담 연결 안내', 'support');

class ChatbotService {
  ChatbotService({required this.bank, required this.pathfinder, required this.events});

  final MockBank bank;
  final Pathfinder pathfinder;
  final EventLog events;

  String _orderSentence(List<PlanStep> steps) {
    final phrases = steps.map((s) => getAction(s.actionId)!.phrase!).toList();
    if (phrases.length < 2) return '';
    if (phrases.length == 2) return '먼저 ${phrases[0].first} 뒤 ${phrases[1].last}.';
    final middle = phrases.sublist(1, phrases.length - 1).map((p) => p.mid).join(', ');
    return '먼저 ${phrases[0].first} 뒤, $middle, 마지막으로 ${phrases.last.last}.';
  }

  /// 이체 사전 조건 진단 문장 (현재 은행 상태 기준)
  _Diagnosis _diagnosisText(Plan plan, RuleContext ctx, _Said said, Transaction? tx, bool amountIsDraft) {
    final links = <FlowLink>[];
    if (amountIsDraft && tx != null) {
      if (tx.status == TransferStatus.success) {
        return _Diagnosis('요청하신 ${formatMan(ctx.amount)} 이체는 은행 처리 결과 성공으로 확인되었습니다. (거래 확인번호 ${tx.id})', const []);
      }
      if (tx.status.isUnresolved) {
        return _Diagnosis(
          '앞서 요청한 ${formatMan(ctx.amount)} 이체의 결과가 아직 확정되지 않았습니다. 중복 출금을 막기 위해 다시 이체하지 마시고 결과를 먼저 조회해 주세요.',
          const [FlowLink('거래 결과 조회', 'transfer-result')],
          Tone.warning,
        );
      }
    }

    if (plan.status == PlanStatus.blocked) {
      final b = plan.blocker!;
      if (b.code == 'ACCOUNT_RESTRICTED') {
        return const _Diagnosis(
          '계좌에 이용 제한이 확인되어 해결패스에서 안내할 수 있는 절차가 없습니다. 제한 해제 방법은 임의로 안내하지 않으며, 공식 상담 창구에서 확인해 주세요.',
          [_support],
          Tone.warning,
        );
      }
      if (b.code == 'INSUFFICIENT_BALANCE') {
        return _Diagnosis(
          '출금 가능 잔액(${formatWon(ctx.balance)})이 요청 금액 ${formatWon(ctx.amount)}보다 적어 이체할 수 없습니다. 설정 변경으로 해결되는 문제가 아니에요.',
          const [],
          Tone.warning,
        );
      }
      return _Diagnosis('${b.title} 상태로 확인되어 거래를 진행하지 않습니다. ${b.guidance}', const [_support], Tone.warning);
    }

    if (plan.status == PlanStatus.noPath) {
      final reason = !ctx.limitChangeAllowed ? ' 현재 이 계좌는 비대면 한도 변경 대상이 아니에요. (가상)' : '';
      return _Diagnosis('현재 상태에서는 해결패스가 안내할 수 있는 절차를 찾지 못했습니다.$reason 상담을 통해 확인해 주세요.', const [_support], Tone.warning);
    }

    if (plan.status == PlanStatus.ready) {
      final prefix = amountIsDraft ? '' : '(질문하신 ${formatMan(ctx.amount)} 기준) ';
      if (amountIsDraft) links.add(const FlowLink('원래 이체로 돌아가기', 'transfer'));
      return _Diagnosis(
        '$prefix현재 확인된 이체 사전 조건을 충족했습니다. '
        '${amountIsDraft ? '원래 이체 화면으로 돌아가 수취인과 금액을 확인한 뒤 직접 이체를 진행해 주세요.' : '이체 화면에서 금액을 입력한 뒤 직접 이체를 진행해 주세요.'}',
        links,
      );
    }

    // PLAN
    final ids = plan.actionSteps.map((s) => s.actionId).toList();
    final hasK = ids.contains('COMPLETE_KYC');
    final hasO = ids.contains('REGISTER_OTP');
    final hasL = ids.contains('CHANGE_TRANSFER_LIMIT');
    var s = '';
    if (hasO && hasL) {
      s = '현재 ${hasK ? '고객확인이 완료되지 않았고, ' : ''}디지털 OTP가 등록되어 있지 않고, 이체한도도 ${formatMan(ctx.transferLimit)}으로 설정되어 있습니다.';
    } else if (hasL) {
      final otpLine = ctx.otpRegistered && ctx.amount > DemoPolicy.otpRequiredAbove && !said.otpConfirmed ? '디지털 OTP 등록이 확인되었습니다. ' : '';
      if (otpLine.isNotEmpty) said.otpConfirmed = true;
      s = '${hasK ? '고객확인이 완료되지 않았습니다. ' : ''}$otpLine'
          '현재 이체한도는 ${formatMan(ctx.transferLimit)}이므로 ${formatMan(ctx.amount)} 이체를 위해 한도 변경이 필요합니다.';
    } else if (hasO) {
      s = hasK
          ? '현재 고객확인이 완료되지 않았고, 디지털 OTP도 등록되어 있지 않습니다.'
          : '현재 이체한도는 충분하지만, ${formatMan(ctx.amount)} 이체에는 디지털 OTP 등록이 필요합니다. (데모 가상 정책)';
    } else if (hasK) {
      s = '고객확인이 완료되지 않아 이체 전에 고객확인 절차가 필요합니다.';
    }
    final order = _orderSentence(plan.actionSteps);
    if (order.isNotEmpty) s += ' $order';
    if (!amountIsDraft) s = '(질문하신 ${formatMan(ctx.amount)} 기준) $s';
    for (final st in plan.actionSteps) {
      final a = getAction(st.actionId)!;
      links.add(FlowLink(a.cta, a.flowId));
    }
    return _Diagnosis(s, links);
  }

  ChatReply _unknownReply(Analysis analysis) => ChatReply(
        text: '질문을 정확히 이해하지 못했어요. 해결패스는 이체, 이체한도, 디지털 OTP, 고객확인, 이체 결과에 관한 질문을 은행 상태로 확인해 안내할 수 있어요.\n'
            '예: "이체가 왜 안 돼?", "이체한도 어디서 바꿔?"\n'
            '확인되지 않은 금융 정보는 안내하지 않으며, 다른 문의는 상담으로 연결해 드릴게요.',
        tone: Tone.warning,
        links: const [_support],
        analysis: analysis,
        ruleIds: const [],
        stateVersion: null,
      );

  List<FlowLink> _dedupeLinks(List<FlowLink> links) {
    final seen = <String>{};
    return links.where((l) => seen.add(l.flowId)).toList();
  }

  Future<ChatReply> respond(String text) async {
    final analysis = analyze(text);
    final ids = analysis.intentIds;
    events.add('NLU', '[$nluMode] 의도: ${ids.join(', ')}${analysis.amount != null ? ' / 금액 ${analysis.amount}' : ''}');
    if (ids.first == 'UNKNOWN') return _unknownReply(analysis);

    final (cs, dr) = await (bank.getCustomerState(), bank.getTransferDraft()).wait;
    final failedError = cs.error ?? dr.error;
    if (failedError != null) {
      pathfinder.planFromQueryFailure(failedError);
      return ChatReply(
        text: '현재 은행 상태를 조회할 수 없어요. (${failedError.message})\n확인되지 않은 정보로 안내하지 않을게요. 잠시 후 다시 질문하시거나 상담을 이용해 주세요.',
        tone: Tone.warning,
        links: const [_support],
        analysis: analysis,
        ruleIds: const ['R06'],
        stateVersion: null,
      );
    }

    final snap = cs.data!;
    final draft = dr.data!.draft;
    final tx = dr.data!.transaction;
    final amount = analysis.amount ?? draft.amount;
    final amountIsDraft = amount == draft.amount;
    final ctx = buildContext(snap, draft, amount);
    final evaluation = evaluate(ctx);
    final plan = pathfinder.computePlan(evaluation);
    final restricted = plan.status == PlanStatus.blocked && plan.blocker!.code == 'ACCOUNT_RESTRICTED';

    final parts = <String>[];
    var links = <FlowLink>[];
    var tone = Tone.normal;
    final said = _Said();

    // 1) 사용자 진술 대조 - 은행의 확인된 상태 우선
    if (analysis.claims['otpRegistered'] == true) {
      if (ctx.otpRegistered) {
        parts.add('디지털 OTP 등록이 확인되었습니다.');
        said.otpConfirmed = true;
      } else {
        parts.add('말씀하신 내용과 달리, 은행 기록상 디지털 OTP는 아직 등록되지 않은 상태로 확인됩니다.');
        tone = Tone.warning;
      }
    }
    if (analysis.claims['limitChanged'] == true) {
      if (ctx.transferLimit >= ctx.amount) {
        parts.add('이체한도 변경이 확인되었습니다. (현재 1일 이체한도 ${formatWon(ctx.transferLimit)})');
      } else {
        parts.add('은행 기록상 현재 1일 이체한도는 ${formatWon(ctx.transferLimit)}로, 요청 금액보다 낮습니다.');
        tone = Tone.warning;
      }
    }
    if (analysis.claims['kycCompleted'] == true) {
      if (ctx.kycCompleted) {
        parts.add('고객확인 완료가 확인되었습니다.');
      } else {
        parts.add('은행 기록상 고객확인은 아직 완료되지 않은 상태입니다.');
        tone = Tone.warning;
      }
    }

    final wantsDiagnosis = ids.contains('TRANSFER_FAILURE') || ids.contains('GENERAL_HELP');

    // 2) 이체 사전 조건 진단
    if (wantsDiagnosis) {
      final d = _diagnosisText(plan, ctx, said, tx, amountIsDraft);
      parts.add(d.text);
      links = [...links, ...d.links];
      if (d.tone == Tone.warning) tone = Tone.warning;
    }

    // 3) 개별 의도 응답 (진단에 포함되지 않은 정보만)
    final asksSetting = ids.any((id) => const ['OTP_REGISTRATION', 'TRANSFER_LIMIT', 'KYC_STATUS'].contains(id));
    if (!wantsDiagnosis && restricted && asksSetting) {
      parts.add('계좌에 이용 제한이 확인되어 지금은 설정 변경을 안내하지 않습니다. 공식 상담 창구에서 확인해 주세요.');
      links.add(_support);
      tone = Tone.warning;
    } else if (!wantsDiagnosis) {
      if (ids.contains('OTP_REGISTRATION')) {
        if (ctx.otpRegistered) {
          if (!said.otpConfirmed) parts.add('디지털 OTP는 이미 등록되어 있어요. 다시 등록할 필요가 없습니다.');
        } else if (DemoPolicy.otpRegistrationRequiresKyc && !ctx.kycCompleted) {
          parts.add('디지털 OTP가 아직 등록되어 있지 않아요. 데모 가상 정책상 고객확인을 먼저 완료한 뒤 등록할 수 있어요.');
          links.add(const FlowLink('고객확인 하러 가기', 'kyc-flow'));
          links.add(const FlowLink('디지털 OTP 등록하러 가기', 'otp-registration'));
        } else {
          parts.add(
            '디지털 OTP가 아직 등록되어 있지 않아요. 디지털 OTP 등록 화면에서 진행할 수 있어요.'
            '${ctx.amount > DemoPolicy.otpRequiredAbove ? ' 현재 준비 중인 ${formatMan(ctx.amount)} 이체에는 OTP 등록이 필요합니다. (가상 정책)' : ''}',
          );
          links.add(const FlowLink('디지털 OTP 등록하러 가기', 'otp-registration'));
        }
      }
      if (ids.contains('TRANSFER_LIMIT')) {
        var s = '현재 1일 이체한도는 ${formatWon(ctx.transferLimit)}입니다.';
        if (!ctx.limitChangeAllowed) {
          s += ' 현재 이 계좌는 비대면 한도 변경 대상이 아니에요. (가상) 상담을 통해 확인해 주세요.';
          links.add(_support);
        } else if (ctx.transferLimit >= ctx.amount) {
          s += ' ${formatMan(ctx.amount)} 이체에는 현재 한도로 충분해서 변경하지 않아도 됩니다. 한도 변경은 이체한도 관리 화면에서 할 수 있어요.';
          links.add(const FlowLink('이체한도 관리 열기', 'limit-management'));
        } else {
          s += ' ${formatMan(ctx.amount)} 이체를 위해서는 한도 변경이 필요해요. 이체한도 관리 화면에서 변경할 수 있어요.';
          if (ctx.amount > DemoPolicy.maxLimitWithoutOtp && !ctx.otpRegistered) {
            s += ' 단, 데모 가상 정책상 ${formatMan(DemoPolicy.maxLimitWithoutOtp)}을 넘는 한도로 변경하려면 디지털 OTP 등록이 먼저 필요해요.';
            links.add(const FlowLink('디지털 OTP 등록하러 가기', 'otp-registration'));
          }
          links.add(const FlowLink('이체한도 변경하러 가기', 'limit-management'));
        }
        parts.add(s);
      }
      if (ids.contains('KYC_STATUS')) {
        if (ctx.kycCompleted) {
          if (analysis.claims['kycCompleted'] != true) parts.add('고객확인은 이미 완료되어 있어 추가로 진행할 필요가 없어요.');
        } else {
          parts.add('고객확인이 아직 완료되지 않았어요. 고객확인 화면에서 진행할 수 있어요. (실제 신분증 정보는 요구하지 않는 시뮬레이션입니다)');
          links.add(const FlowLink('고객확인 하러 가기', 'kyc-flow'));
        }
      }
    }

    // 4) 이체 결과 문의
    if (ids.contains('TRANSFER_STATUS')) {
      if (tx == null) {
        parts.add('아직 진행된 이체 요청이 없어요. 현재 준비 중인 이체는 ${draft.recipient}님에게 ${formatWon(draft.amount)}입니다.');
      } else if (tx.status == TransferStatus.success) {
        parts.add('최근 이체(${tx.id}, ${formatWon(tx.amount)})는 은행 처리 결과 성공으로 확인되었습니다.');
      } else if (tx.status == TransferStatus.failed) {
        parts.add('최근 이체 요청(${tx.id})은 은행 처리 결과 실패로 확인되었습니다. 출금되지 않았어요.');
      } else if (tx.status == TransferStatus.pending) {
        parts.add('최근 이체 요청(${tx.id})은 은행에서 처리 중이에요. 중복 출금을 막기 위해 다시 이체하지 말고 결과를 조회해 주세요.');
        links.add(const FlowLink('거래 결과 조회', 'transfer-result'));
        tone = Tone.warning;
      } else {
        parts.add('최근 이체 요청(${tx.id})의 결과를 아직 확인하지 못했어요. 성공 여부가 확정되기 전에는 다시 이체하지 마시고, 결과를 조회하거나 상담을 이용해 주세요.');
        links.add(const FlowLink('거래 결과 조회', 'transfer-result'));
        links.add(_support);
        tone = Tone.warning;
      }
    }

    if (ids.length == 1 && ids.first == 'GENERAL_HELP') {
      parts.add('같은 문제가 계속되면 상담으로 연결해 드릴 수도 있어요.');
      links.add(_support);
    }

    if (parts.isEmpty) parts.add('현재 은행 상태에서 추가로 안내할 내용이 없어요.');

    return ChatReply(
      text: parts.join('\n'),
      tone: tone,
      links: _dedupeLinks(links),
      analysis: analysis,
      ruleIds: evaluation.firedRules,
      stateVersion: snap.stateVersion,
      planStatus: plan.status,
    );
  }
}
