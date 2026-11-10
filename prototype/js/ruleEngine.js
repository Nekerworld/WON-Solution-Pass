/**
 * ruleEngine.js
 * 데모용 가상 정책(DEMO_POLICY)과 현재 고객 상태로부터
 *  - 목표 상태(goal)
 *  - 충족해야 할 요구사항(requirements)
 *  - 자동 해결을 금지하는 차단 사유(blockers)
 *  - 행동 간 선후 제약(constraints)
 * 을 계산한다. 규칙은 구조화된 데이터로 관리한다.
 *
 * 실제 은행의 보안 정책·인증 규칙을 추측하여 구현하지 않는다.
 */
(function () {
  'use strict';

  const WSP = window.WSP;
  const P = WSP.DEMO_POLICY;
  const fmt = WSP.utils.formatWon;

  const RULES = Object.freeze([
    {
      id: 'R06',
      type: 'blocker',
      code: 'BANK_UNAVAILABLE',
      title: '은행 시스템 이용 불가',
      when: (c) => !c.bankAvailable,
      guidance: '은행 상태를 확인할 수 없어 거래를 진행하지 않습니다. 잠시 후 다시 확인해 주세요.',
    },
    {
      id: 'R05',
      type: 'blocker',
      code: 'ACCOUNT_RESTRICTED',
      title: '계좌 이용 제한',
      when: (c) => c.accountRestricted,
      guidance: '해결패스는 제한 해제 방법을 안내하지 않습니다. 공식 상담 창구에서 확인해 주세요.',
    },
    {
      id: 'R07',
      type: 'blocker',
      code: 'INSUFFICIENT_BALANCE',
      title: '출금 가능 잔액 부족',
      when: (c) => c.amount > c.balance,
      guidance: '잔액 부족은 설정 변경으로 해결할 수 없습니다. 잔액을 확인한 뒤 다시 시도해 주세요.',
    },
    {
      id: 'R04',
      type: 'requirement',
      fact: 'kycCompleted',
      title: '고객확인 필요',
      when: (c) => !c.kycCompleted,
      describe: () => '고객확인이 완료되지 않아 이체를 진행할 수 없습니다.',
    },
    {
      id: 'R02',
      type: 'requirement',
      fact: 'otpRegistered',
      title: '디지털 OTP 등록 필요',
      when: (c) => c.amount > P.otpRequiredAbove && !c.otpRegistered,
      describe: (c) => fmt(P.otpRequiredAbove) + '를 초과하는 ' + fmt(c.amount) + ' 이체에는 디지털 OTP가 필요합니다. (가상 정책)',
    },
    {
      id: 'R01',
      type: 'requirement',
      fact: 'limitSufficient',
      title: '이체한도 충족 필요',
      when: (c) => c.amount > c.transferLimit,
      describe: (c) => '요청 금액 ' + fmt(c.amount) + '이 1일 이체한도 ' + fmt(c.transferLimit) + '를 초과합니다.',
    },
    {
      id: 'R03',
      type: 'constraint',
      action: 'CHANGE_TRANSFER_LIMIT',
      requiresFact: 'otpRegistered',
      title: '한도 상향 전 디지털 OTP 등록 필요',
      when: (c) => c.amount > c.transferLimit && c.amount > P.maxLimitWithoutOtp,
      relevant: (c, f) => !f.otpRegistered,
      describe: () => fmt(P.maxLimitWithoutOtp) + '를 초과하는 한도로 변경하려면 디지털 OTP 등록이 먼저 필요합니다. (가상 정책)',
    },
    {
      id: 'R08',
      type: 'constraint',
      action: 'REGISTER_OTP',
      requiresFact: 'kycCompleted',
      title: '디지털 OTP 등록 전 고객확인 필요',
      when: () => P.otpRegistrationRequiresKyc,
      relevant: (c, f) => !f.otpRegistered && !f.kycCompleted,
      describe: () => '디지털 OTP 등록은 고객확인 완료 후 진행할 수 있습니다. (가상 정책)',
    },
  ]);

  /** Mock Bank 조회 결과 + 이체 초안 -> 규칙 평가용 컨텍스트 */
  function buildContext(snapshot, draft, amountOverride) {
    const amount = Number(amountOverride || (draft && draft.amount) || 0);
    return {
      amount: amount,
      recipient: draft ? draft.recipient : null,
      recipientBank: draft ? draft.recipientBank : null,
      transferLimit: snapshot.transferLimit,
      otpRegistered: !!snapshot.digitalOtpRegistered,
      kycCompleted: !!snapshot.kycCompleted,
      accountRestricted: !!snapshot.accountRestricted,
      bankAvailable: snapshot.bankAvailable !== false,
      limitChangeAllowed: !!snapshot.transferLimitChangeAllowed,
      balance: snapshot.balance,
      stateVersion: snapshot.stateVersion,
      checkedAt: snapshot.checkedAt,
    };
  }

  /** 경로 탐색에 쓰는 추상 상태(boolean facts) */
  function toFacts(ctx) {
    return {
      otpRegistered: ctx.otpRegistered,
      limitSufficient: ctx.amount <= ctx.transferLimit,
      kycCompleted: ctx.kycCompleted,
      accountRestricted: ctx.accountRestricted,
      bankAvailable: ctx.bankAvailable,
      limitChangeAllowed: ctx.limitChangeAllowed,
      returnedToTransfer: false,
    };
  }

  /**
   * 목표 상태: 이번 이체 요청과 가상 정책에서 도출한다.
   * OTP는 모든 이체에 무조건 필요한 것이 아니라 금액 기준을 넘을 때만 목표에 포함된다.
   */
  function buildGoal(ctx) {
    const goal = {
      kycCompleted: true,
      limitSufficient: true,
      accountRestricted: false,
      bankAvailable: true,
    };
    if (ctx.amount > P.otpRequiredAbove) goal.otpRegistered = true;
    return goal;
  }

  function evaluate(ctx) {
    const facts = toFacts(ctx);
    const goal = buildGoal(ctx);
    const requirements = [];
    const blockers = [];
    const constraints = [];
    const firedRules = [];

    RULES.forEach((rule) => {
      if (!rule.when(ctx)) return;
      if (rule.type === 'blocker') {
        blockers.push({ ruleId: rule.id, code: rule.code, title: rule.title, guidance: rule.guidance });
        firedRules.push(rule.id);
      } else if (rule.type === 'requirement') {
        requirements.push({ ruleId: rule.id, fact: rule.fact, title: rule.title, description: rule.describe(ctx) });
        firedRules.push(rule.id);
      } else if (rule.type === 'constraint') {
        const binding = rule.relevant ? rule.relevant(ctx, facts) : true;
        constraints.push({
          ruleId: rule.id,
          action: rule.action,
          requiresFact: rule.requiresFact,
          title: rule.title,
          description: rule.describe(ctx),
          binding: binding,
        });
        if (binding) firedRules.push(rule.id);
      }
    });

    return {
      ctx: ctx,
      facts: facts,
      goal: goal,
      requirements: requirements,
      blockers: blockers,
      constraints: constraints,
      firedRules: firedRules,
      policyVersion: P.version,
    };
  }

  /** 상태 조회 자체가 실패한 경우: 정상 진단을 가장하지 않고 R06 차단으로 처리 */
  function blockerFromQueryFailure(error) {
    const rule = RULES.find((r) => r.id === 'R06');
    return {
      ruleId: 'R06',
      code: error && error.code === 'QUERY_TIMEOUT' ? 'QUERY_FAILURE' : 'BANK_UNAVAILABLE',
      title: error && error.code === 'QUERY_TIMEOUT' ? '은행 상태 조회 실패' : rule.title,
      guidance: rule.guidance,
      error: error || null,
    };
  }

  function getRule(id) {
    return RULES.find((r) => r.id === id) || null;
  }

  WSP.ruleEngine = {
    RULES: RULES,
    buildContext: buildContext,
    toFacts: toFacts,
    buildGoal: buildGoal,
    evaluate: evaluate,
    blockerFromQueryFailure: blockerFromQueryFailure,
    getRule: getRule,
  };
})();
