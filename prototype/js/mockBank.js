/**
 * mockBank.js
 * 실제 서버/금융 API 없이 브라우저 안에서 동작하는 가상 은행 API.
 * - 모든 함수는 Promise를 반환한다.
 * - 응답 형식: { ok:true, data } | { ok:false, error:{ code, kind, message, ... } }
 *   kind: 'QUERY_FAILURE'  조회 실패/시스템 이용 불가 (업무 판단 불가)
 *         'BUSINESS_REJECT' 업무 조건 미충족으로 은행이 거절
 * - 거래 성공 여부는 오직 이 모듈이 결정한다.
 */
(function () {
  'use strict';

  const WSP = window.WSP;
  const store = WSP.store;
  const P = WSP.DEMO_POLICY;
  const fmt = WSP.utils.formatWon;

  const LATENCY = { query: 220, mutate: 520, transfer: 760 };
  let latencyScale = 1;

  function wait(kind) {
    const base = LATENCY[kind] || 200;
    const ms = Math.round(base * latencyScale * (0.85 + Math.random() * 0.3));
    return ms > 0 ? new Promise((r) => setTimeout(r, ms)) : Promise.resolve();
  }

  function ok(data) {
    return { ok: true, data: data };
  }

  function err(code, kind, message, extra) {
    return { ok: false, error: Object.assign({ code: code, kind: kind, message: message }, extra || {}) };
  }

  function systemGuard(s, isQuery) {
    if (!s.system.bankAvailable) {
      return err('BANK_UNAVAILABLE', 'QUERY_FAILURE', '은행 시스템에 일시적으로 연결할 수 없습니다.');
    }
    if (isQuery && s.simulation.queryFailure) {
      return err('QUERY_TIMEOUT', 'QUERY_FAILURE', '상태 조회 응답을 받지 못했습니다.');
    }
    return null;
  }

  /** 은행 자체의 이체 사전 검사 (가상 정책 기반) */
  function transferRejectReasons(s, t) {
    const reasons = [];
    if (s.customer.accountRestricted) {
      reasons.push({ code: 'ACCOUNT_RESTRICTED', message: '계좌 이용 제한 상태입니다.' });
    }
    if (!s.customer.kycCompleted) {
      reasons.push({ code: 'KYC_REQUIRED', message: '고객확인이 완료되지 않았습니다.' });
    }
    if (t.amount > P.otpRequiredAbove && !s.customer.digitalOtpRegistered) {
      reasons.push({
        code: 'OTP_REQUIRED',
        message: fmt(P.otpRequiredAbove) + ' 초과 이체는 디지털 OTP 등록이 필요합니다. (가상 정책)',
      });
    }
    if (t.amount > s.customer.transferLimit) {
      reasons.push({
        code: 'LIMIT_EXCEEDED',
        message: '이체 금액이 1일 이체한도(' + fmt(s.customer.transferLimit) + ')를 초과합니다.',
      });
    }
    if (t.amount > s.account.balance) {
      reasons.push({ code: 'INSUFFICIENT_BALANCE', message: '출금 가능 잔액이 부족합니다.' });
    }
    return reasons;
  }

  function limitChangeRejectReasons(s, newLimit) {
    const reasons = [];
    if (s.customer.accountRestricted) {
      reasons.push({ code: 'ACCOUNT_RESTRICTED', message: '계좌 이용 제한 상태에서는 한도를 변경할 수 없습니다.' });
    }
    if (!s.customer.transferLimitChangeAllowed) {
      reasons.push({ code: 'LIMIT_CHANGE_NOT_ALLOWED', message: '현재 이 계좌는 비대면 한도 변경 대상이 아닙니다. (가상)' });
    }
    if (!Number.isFinite(newLimit) || newLimit < P.minTransferLimit || newLimit > P.maxTransferLimit) {
      reasons.push({
        code: 'INVALID_LIMIT',
        message: '변경 가능한 한도 범위는 ' + fmt(P.minTransferLimit) + ' ~ ' + fmt(P.maxTransferLimit) + '입니다.',
      });
    }
    if (newLimit > P.maxLimitWithoutOtp && !s.customer.digitalOtpRegistered) {
      reasons.push({
        code: 'OTP_REQUIRED_FOR_LIMIT',
        message: fmt(P.maxLimitWithoutOtp) + '를 초과하는 한도는 디지털 OTP 등록 후 변경할 수 있습니다. (가상 정책)',
      });
    }
    return reasons;
  }

  function findTransactionByRequest(s, requestId) {
    const list = Object.keys(s.transactions).map((k) => s.transactions[k]);
    return list.find((t) => t.requestId === requestId) || null;
  }

  let requestSeq = 0;

  const ALLOWED_FLOWS = Object.freeze({
    'otp-registration': 'otp',
    'limit-management': 'limit',
    'kyc-flow': 'kyc',
    transfer: 'transfer',
    'solution-plan': 'plan',
    support: 'support',
    'transfer-result': 'result',
    chat: 'chat',
    home: 'home',
  });

  const api = {
    /* ---------------- 조회 ---------------- */

    async getCustomerState() {
      await wait('query');
      const s = store.getState();
      const g = systemGuard(s, true);
      if (g) return g;
      return ok({
        customerName: s.customer.name,
        accountName: s.account.name,
        accountNumber: s.account.number,
        balance: s.account.balance,
        kycCompleted: s.customer.kycCompleted,
        digitalOtpRegistered: s.customer.digitalOtpRegistered,
        transferLimit: s.customer.transferLimit,
        transferLimitChangeAllowed: s.customer.transferLimitChangeAllowed,
        accountRestricted: s.customer.accountRestricted,
        bankAvailable: s.system.bankAvailable,
        stateVersion: s.system.stateVersion,
        policyVersion: P.version,
        checkedAt: Date.now(),
      });
    },

    async getTransferLimit() {
      await wait('query');
      const s = store.getState();
      const g = systemGuard(s, true);
      if (g) return g;
      return ok({
        transferLimit: s.customer.transferLimit,
        changeAllowed: s.customer.transferLimitChangeAllowed,
        maxWithoutOtp: P.maxLimitWithoutOtp,
        stateVersion: s.system.stateVersion,
      });
    },

    async getOtpStatus() {
      await wait('query');
      const s = store.getState();
      const g = systemGuard(s, true);
      if (g) return g;
      return ok({ registered: s.customer.digitalOtpRegistered, stateVersion: s.system.stateVersion });
    },

    async getKycStatus() {
      await wait('query');
      const s = store.getState();
      const g = systemGuard(s, true);
      if (g) return g;
      return ok({ completed: s.customer.kycCompleted, stateVersion: s.system.stateVersion });
    },

    /** 현재 진행 중인 이체 초안(받는 분·금액 등). 해결 절차 중에도 유지된다. */
    async getTransferDraft() {
      await wait('query');
      const s = store.getState();
      const g = systemGuard(s, true);
      if (g) return g;
      const tx = s.transfer.transactionId ? s.transactions[s.transfer.transactionId] || null : null;
      return ok({ draft: s.transfer, transaction: tx, balance: s.account.balance });
    },

    async getTransactions() {
      await wait('query');
      const s = store.getState();
      const g = systemGuard(s, true);
      if (g) return g;
      const list = Object.keys(s.transactions)
        .map((k) => s.transactions[k])
        .sort((a, b) => b.createdAt - a.createdAt);
      return ok({ transactions: list });
    },

    async checkOtpEligibility() {
      await wait('query');
      const s = store.getState();
      const g = systemGuard(s, true);
      if (g) return g;
      if (s.customer.digitalOtpRegistered) {
        return ok({ eligible: false, code: 'ALREADY_REGISTERED', message: '이미 디지털 OTP가 등록되어 있습니다.' });
      }
      if (s.customer.accountRestricted) {
        return ok({ eligible: false, code: 'ACCOUNT_RESTRICTED', message: '계좌 이용 제한 상태에서는 등록할 수 없습니다.' });
      }
      if (P.otpRegistrationRequiresKyc && !s.customer.kycCompleted) {
        return ok({ eligible: false, code: 'KYC_REQUIRED', message: '고객확인을 먼저 완료해야 합니다. (가상 정책)' });
      }
      return ok({ eligible: true, code: 'ELIGIBLE', message: '이 기기에서 디지털 OTP를 등록할 수 있습니다.' });
    },

    async checkLimitChange(newLimit) {
      await wait('query');
      const s = store.getState();
      const g = systemGuard(s, true);
      if (g) return g;
      const reasons = limitChangeRejectReasons(s, Number(newLimit));
      return ok({ allowed: reasons.length === 0, reasons: reasons, currentLimit: s.customer.transferLimit });
    },

    /* ---------------- 변경 ---------------- */

    async registerDigitalOtp() {
      await wait('mutate');
      const s = store.getState();
      const g = systemGuard(s, false);
      if (g) return g;
      if (s.customer.digitalOtpRegistered) {
        return err('ALREADY_REGISTERED', 'BUSINESS_REJECT', '이미 디지털 OTP가 등록되어 있습니다.');
      }
      if (s.customer.accountRestricted) {
        return err('ACCOUNT_RESTRICTED', 'BUSINESS_REJECT', '계좌 이용 제한 상태에서는 등록할 수 없습니다.');
      }
      if (P.otpRegistrationRequiresKyc && !s.customer.kycCompleted) {
        return err('KYC_REQUIRED', 'BUSINESS_REJECT', '고객확인을 먼저 완료해야 합니다. (가상 정책)');
      }
      const next = store.update((d) => {
        d.customer.digitalOtpRegistered = true;
      }, '디지털 OTP 등록 완료');
      return ok({ registered: true, stateVersion: next.system.stateVersion });
    },

    async changeTransferLimit(newLimit) {
      await wait('mutate');
      const value = Number(newLimit);
      const s = store.getState();
      const g = systemGuard(s, false);
      if (g) return g;
      const reasons = limitChangeRejectReasons(s, value);
      if (reasons.length) {
        return err(reasons[0].code, 'BUSINESS_REJECT', reasons[0].message, { reasons: reasons });
      }
      const before = s.customer.transferLimit;
      const next = store.update((d) => {
        d.customer.transferLimit = value;
      }, '1일 이체한도 변경 ' + fmt(before) + ' → ' + fmt(value));
      return ok({ transferLimit: value, previousLimit: before, stateVersion: next.system.stateVersion });
    },

    async completeKyc() {
      await wait('mutate');
      const s = store.getState();
      const g = systemGuard(s, false);
      if (g) return g;
      if (s.customer.kycCompleted) {
        return err('ALREADY_COMPLETED', 'BUSINESS_REJECT', '고객확인이 이미 완료되어 있습니다.');
      }
      if (s.customer.accountRestricted) {
        return err('ACCOUNT_RESTRICTED', 'BUSINESS_REJECT', '계좌 이용 제한 상태에서는 진행할 수 없습니다.');
      }
      const next = store.update((d) => {
        d.customer.kycCompleted = true;
      }, '고객확인 완료');
      return ok({ completed: true, stateVersion: next.system.stateVersion });
    },

    /** 이체 금액 변경 (진행 중이거나 결과 불명인 거래가 있으면 거절) */
    async updateTransferAmount(amount) {
      await wait('query');
      const value = Math.floor(Number(amount));
      const s = store.getState();
      const g = systemGuard(s, false);
      if (g) return g;
      if (['PENDING', 'UNKNOWN', 'SUCCESS'].indexOf(s.transfer.status) !== -1) {
        return err('TRANSFER_LOCKED', 'BUSINESS_REJECT', '처리 중이거나 완료된 이체는 금액을 바꿀 수 없습니다.');
      }
      if (!Number.isFinite(value) || value <= 0) {
        return err('INVALID_AMOUNT', 'BUSINESS_REJECT', '이체 금액을 확인해 주세요.');
      }
      if (value === s.transfer.amount) return ok({ amount: value, changed: false });
      store.update((d) => {
        d.transfer.amount = value;
        d.transfer.requestId = null;
        d.transfer.transactionId = null;
        d.transfer.status = 'IDLE';
      }, '이체 금액 변경 → ' + fmt(value));
      return ok({ amount: value, changed: true });
    },

    /* ---------------- 이체 ---------------- */

    /** 이체 사전 검사. 실패 사유를 한 번에 모두 반환한다. 거래는 발생하지 않는다. */
    async validateTransfer(transfer) {
      await wait('query');
      const s = store.getState();
      const g = systemGuard(s, true);
      if (g) return g;
      const t = transfer || s.transfer;
      const reasons = transferRejectReasons(s, t);
      return ok({
        valid: reasons.length === 0,
        reasons: reasons,
        stateVersion: s.system.stateVersion,
        checkedAt: Date.now(),
      });
    },

    newRequestId() {
      requestSeq += 1;
      return 'REQ-' + Date.now().toString(36).toUpperCase() + '-' + requestSeq;
    },

    /**
     * 이체 실행 요청. 사용자가 승인했을 때만 호출되어야 한다.
     * - 같은 requestId 재요청은 새 거래를 만들지 않고 기존 거래를 반환한다(중복 실행 방지).
     * - 결과(SUCCESS/FAILED/PENDING/UNKNOWN)는 가상 은행이 결정한다.
     */
    async submitTransfer(transfer) {
      await wait('transfer');
      const s = store.getState();
      const g = systemGuard(s, false);
      if (g) return err(g.error.code, g.error.kind, g.error.message + ' 이체 요청은 전송되지 않았습니다.', { submitted: false });
      if (!transfer || !transfer.requestId) {
        return err('REQUEST_ID_REQUIRED', 'BUSINESS_REJECT', '거래 요청 식별값이 없습니다.', { submitted: false });
      }

      const existing = findTransactionByRequest(s, transfer.requestId);
      if (existing) {
        WSP.events.add('BANK', '중복 요청 차단: ' + transfer.requestId + ' → 기존 거래 ' + existing.id + ' 반환');
        return ok({ transaction: existing, duplicate: true });
      }

      const draft = s.transfer;
      if (
        transfer.amount !== draft.amount ||
        transfer.recipient !== draft.recipient ||
        transfer.recipientBank !== draft.recipientBank ||
        transfer.fromAccount !== draft.fromAccount
      ) {
        return err('DRAFT_MISMATCH', 'BUSINESS_REJECT', '확인한 이체 정보와 요청 정보가 다릅니다.', { submitted: false });
      }

      const reasons = transferRejectReasons(s, transfer);
      if (reasons.length) {
        return err('TRANSFER_REJECTED', 'BUSINESS_REJECT', '이체 조건을 충족하지 않아 거래가 실행되지 않았습니다.', {
          reasons: reasons,
          submitted: false,
        });
      }

      const outcome = s.simulation.nextTransferOutcome || 'SUCCESS';
      const seq = Object.keys(s.transactions).length;
      const id = 'DEMO-' + String(1023 + seq);
      const tx = {
        id: id,
        requestId: transfer.requestId,
        amount: transfer.amount,
        recipient: transfer.recipient,
        recipientBank: transfer.recipientBank,
        fromAccount: transfer.fromAccount,
        status: outcome,
        createdAt: Date.now(),
        updatedAt: Date.now(),
        failureReason: outcome === 'FAILED' ? '수취 은행 처리 거절 (가상 응답)' : null,
      };
      store.update((d) => {
        d.transactions[id] = tx;
        d.transfer.requestId = transfer.requestId;
        d.transfer.transactionId = id;
        d.transfer.status = outcome;
        if (outcome === 'SUCCESS') d.account.balance -= transfer.amount;
      }, '이체 요청 ' + id + ' 처리 결과: ' + outcome);
      return ok({ transaction: tx, duplicate: false });
    },

    /** 거래 결과 조회 전용. 어떤 경우에도 재전송하지 않는다. */
    async getTransferResult(transactionId) {
      await wait('query');
      const s = store.getState();
      const g = systemGuard(s, true);
      if (g) return g;
      const tx = s.transactions[transactionId];
      if (!tx) return err('TX_NOT_FOUND', 'BUSINESS_REJECT', '해당 거래를 찾을 수 없습니다.');
      return ok({ transaction: tx });
    },

    /* ---------------- 화면 연결 ---------------- */

    /** 은행이 승인한 내부 화면 ID만 반환한다. 외부 URL은 생성하지 않는다. */
    resolveFlow(flowId) {
      return Object.prototype.hasOwnProperty.call(ALLOWED_FLOWS, flowId) ? ALLOWED_FLOWS[flowId] : null;
    },

    ALLOWED_FLOWS: ALLOWED_FLOWS,

    /* ---------------- 시연 전용 ---------------- */

    setLatencyScale(v) {
      latencyScale = Math.max(0, Number(v) || 0);
    },
    getLatencyScale() {
      return latencyScale;
    },

    /** 시연 패널 전용: 보류/불명 거래를 은행 측에서 확정 처리한 것으로 시뮬레이션 */
    demoResolveTransaction(transactionId, status) {
      const s = store.getState();
      const tx = s.transactions[transactionId];
      if (!tx || (status !== 'SUCCESS' && status !== 'FAILED')) return false;
      if (tx.status === 'SUCCESS' || tx.status === 'FAILED') return false;
      store.update((d) => {
        const t = d.transactions[transactionId];
        t.status = status;
        t.updatedAt = Date.now();
        if (status === 'FAILED') t.failureReason = '은행 처리 결과 실패 (가상 응답)';
        if (status === 'SUCCESS') d.account.balance -= t.amount;
        if (d.transfer.transactionId === transactionId) d.transfer.status = status;
      }, '[시연] 거래 ' + transactionId + ' 은행 측 확정: ' + status);
      return true;
    },
  };

  WSP.mockBank = api;
})();
