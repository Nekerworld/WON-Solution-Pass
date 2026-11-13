/**
 * mockBank.js
 * 브라우저 안에서 동작하는 가상 은행 API.
 * - 모든 함수는 Promise를 반환한다.
 * - 응답: { ok:true, data } | { ok:false, error:{ code, kind, message, ... } }
 *   kind: 'QUERY_FAILURE'  조회 실패·시스템 이용 불가 (업무 판단 불가)
 *         'BUSINESS_REJECT' 업무 조건 미충족으로 은행이 거절
 * - 업무 처리·가입 성공 여부는 오직 이 모듈이 결정한다.
 * - 업무 화면의 결과(getTaskResult)는 참고용이며, 완료 판정은 조건 재조회로 한다.
 */
(function () {
  'use strict';

  const WSP = window.WSP;
  const store = WSP.store;
  const SC = WSP.scenario;
  const newId = WSP.utils.newId;

  const LATENCY = { query: 220, mutate: 600, apply: 800 };
  let latencyScale = 1;

  function wait(kind) {
    const base = LATENCY[kind] || 200;
    const ms = Math.round(base * latencyScale * (0.85 + Math.random() * 0.3));
    return ms > 0 ? new Promise((r) => setTimeout(r, ms)) : Promise.resolve();
  }

  const ok = (data) => ({ ok: true, data: data });
  const err = (code, kind, message, extra) => ({ ok: false, error: Object.assign({ code: code, kind: kind, message: message }, extra || {}) });

  function systemGuard(s, isQuery) {
    if (!s.system.bankAvailable) return err('BANK_UNAVAILABLE', 'QUERY_FAILURE', '은행 시스템에 일시적으로 연결할 수 없어요.');
    if (isQuery && s.simulation.queryFailure) return err('QUERY_TIMEOUT', 'QUERY_FAILURE', '상태 조회 응답을 받지 못했어요.');
    return null;
  }

  function preReasons(s, task) {
    return Object.keys(task.pre)
      .filter((f) => s.facts[f] !== task.pre[f])
      .map((f) => ({ code: 'PRE_' + f, fact: f, message: WSP.utils.josa(SC.FACTS[f].label, '이') + ' 먼저 필요해요.' }));
  }

  function inProgressFacts(s) {
    return Object.keys(s.pending || {});
  }

  function applyEffects(d, task) {
    Object.keys(task.effects).forEach((f) => {
      d.facts[f] = task.effects[f];
      delete d.pending[f];
    });
  }

  function unmetProductFacts(s, product) {
    return product.conditions.map((c) => SC.CONDITIONS[c]).filter((c) => s.facts[c.fact] !== true);
  }

  const api = {
    /* ---------------- 조회 ---------------- */

    async getProfile() {
      await wait('query');
      const s = store.getState();
      const g = systemGuard(s, true);
      if (g) return g;
      return ok(Object.assign({}, s.customer, { stateVersion: s.system.stateVersion }));
    },

    /** 홈 화면용: 우리은행 계좌 보유 여부 */
    async getAccountSummary() {
      await wait('query');
      const s = store.getState();
      const g = systemGuard(s, true);
      if (g) return g;
      const apps = Object.keys(s.applications).map((k) => s.applications[k]);
      return ok({
        customerName: s.customer.name,
        hasDepositAccount: s.facts.hasDepositAccount,
        account: s.facts.hasDepositAccount ? { name: 'WON 통장', number: '1002-***-731024' } : null,
        fxAccount: s.facts.hasFxAccount ? { name: 'WON 외화통장(USD)', number: '1002-***-552190' } : null,
        savings: apps.filter((a) => a.status === 'SUCCESS').map((a) => ({ productId: a.productId, id: a.id, terms: a.terms })),
        stateVersion: s.system.stateVersion,
      });
    },

    /** 상품 조건 확인용 은행 사실 조회 */
    async checkConditions(productId) {
      await wait('query');
      const s = store.getState();
      const g = systemGuard(s, true);
      if (g) return g;
      const product = SC.getProduct(productId);
      if (!product) return err('PRODUCT_NOT_FOUND', 'BUSINESS_REJECT', '상품을 찾을 수 없어요.');
      const pending = inProgressFacts(s);
      return ok({
        productId: productId,
        conditions: product.conditions.map((id) => {
          const c = SC.CONDITIONS[id];
          return { id: id, fact: c.fact, label: c.label, value: s.facts[c.fact] === true, inProgress: pending.indexOf(c.fact) !== -1 };
        }),
        facts: Object.assign({}, s.facts),
        stateVersion: s.system.stateVersion,
        checkedAt: Date.now(),
      });
    },

    /** 정보 이용 동의 후: 연결된 마이데이터 기관의 다른 은행 계좌 보유 여부 */
    async getLinkedAccounts() {
      await wait('query');
      const s = store.getState();
      const g = systemGuard(s, true);
      if (g) return g;
      return ok({
        mydataLinked: s.finance.mydataLinked,
        linked: s.finance.linked.slice(),
        otherBankAccounts: s.finance.otherBankAccounts.slice(),
        mobileOwnerVerified: s.customer.mobileOwnerVerified,
      });
    },

    /** 자산관리용 재무 조회: 조회 범위와 미확인 항목을 함께 돌려준다 */
    async getFinancialSnapshot() {
      await wait('query');
      const s = store.getState();
      const g = systemGuard(s, true);
      if (g) return g;
      return ok({
        coverage: { linked: s.finance.mydataLinked ? s.finance.linked.slice() : [], notLinked: s.finance.notLinked.slice() },
        items: WSP.utils.clone(s.finance.items),
        stateVersion: s.system.stateVersion,
      });
    },

    listProducts() {
      return SC.PRODUCTS.slice();
    },

    /** 조건을 충족시키는 은행 허용 업무(대체 수단 포함) */
    async getAlternatives(conditionId) {
      await wait('query');
      const s = store.getState();
      const g = systemGuard(s, true);
      if (g) return g;
      const c = SC.CONDITIONS[conditionId];
      if (!c) return err('CONDITION_NOT_FOUND', 'BUSINESS_REJECT', '조건을 찾을 수 없어요.');
      return ok({ conditionId: conditionId, tasks: SC.TASKS.filter((t) => t.effects[c.fact] === true).map((t) => t.id) });
    },

    async checkTaskEligibility(taskId) {
      await wait('query');
      const s = store.getState();
      const g = systemGuard(s, true);
      if (g) return g;
      const task = SC.getTask(taskId);
      if (!task) return err('TASK_NOT_FOUND', 'BUSINESS_REJECT', '허용되지 않은 업무예요.');
      const done = Object.keys(task.effects).every((f) => s.facts[f] === task.effects[f]);
      const reasons = preReasons(s, task);
      return ok({ taskId: taskId, alreadyDone: done, eligible: !done && reasons.length === 0, reasons: reasons });
    },

    /* ---------------- 업무 (모달/메뉴) ---------------- */

    /** 은행이 허용한 업무 화면만 연다. 외부 URL은 만들지 않는다. */
    openTask(taskId, opts) {
      const task = SC.getTask(taskId);
      if (!task) return err('TASK_NOT_FOUND', 'BUSINESS_REJECT', '허용되지 않은 업무예요.');
      const id = newId('TS');
      store.update((d) => {
        d.taskSessions[id] = { id: id, taskId: taskId, mode: (opts && opts.mode) || 'modal', status: 'OPEN', openedAt: Date.now() };
      }, '업무 화면 열기 ' + task.label + ' (' + id + ')');
      return ok({ sessionId: id });
    },

    async runTask(sessionId, input) {
      await wait('mutate');
      const s = store.getState();
      const g = systemGuard(s, false);
      if (g) return g;
      const ts = s.taskSessions[sessionId];
      if (!ts) return err('SESSION_NOT_FOUND', 'BUSINESS_REJECT', '업무 세션을 찾을 수 없어요.');
      if (ts.status !== 'OPEN') return ok({ sessionId: sessionId, status: ts.status, duplicate: true });
      const task = SC.getTask(ts.taskId);
      const reasons = preReasons(s, task);
      if (reasons.length) return err('PRECONDITION_UNMET', 'BUSINESS_REJECT', reasons[0].message, { reasons: reasons });

      const outcome = s.simulation.nextTaskOutcome || 'NORMAL';
      let status = 'COMPLETED';
      let message = WSP.utils.josa(task.label, '을') + ' 마쳤어요.';
      const next = store.update((d) => {
        const t = d.taskSessions[sessionId];
        t.input = input || null;
        t.finishedAt = Date.now();
        if (outcome === 'NORMAL') applyEffects(d, task);
        else if (outcome === 'ERROR') {
          status = 'ERROR';
          message = '처리 중 오류가 발생했어요. 변경된 내용은 없어요.';
        } else if (outcome === 'IN_PROGRESS') {
          status = 'IN_PROGRESS';
          message = '은행에서 처리하고 있어요. 완료되면 상태에 반영돼요.';
          Object.keys(task.effects).forEach((f) => (d.pending[f] = { sessionId: sessionId, queriesLeft: 1 }));
        } else if (outcome === 'PARTIAL') {
          status = 'PARTIAL';
          message = '일부 단계만 저장됐어요. 남은 단계를 마쳐야 완료돼요.';
        } else if (outcome === 'MISMATCH' || outcome === 'MISMATCH_ALWAYS') {
          // 업무 화면은 완료로 표시하지만 은행 기록에는 반영되지 않은 상황
          t.mismatch = true;
        }
        t.status = status;
        if (outcome !== 'MISMATCH_ALWAYS') d.simulation.nextTaskOutcome = 'NORMAL';
      }, '업무 처리 ' + task.label + ' → ' + status + (outcome !== 'NORMAL' ? ' [시뮬레이션 ' + outcome + ']' : ''));
      return ok({ sessionId: sessionId, status: status, message: message, stateVersion: next.system.stateVersion });
    },

    cancelTask(sessionId) {
      const s = store.getState();
      const ts = s.taskSessions[sessionId];
      if (!ts || ts.status !== 'OPEN') return ok({ sessionId: sessionId, status: ts ? ts.status : 'NONE' });
      store.update((d) => {
        d.taskSessions[sessionId].status = 'CANCELLED';
      }, '업무 화면 닫기(취소) ' + sessionId);
      return ok({ sessionId: sessionId, status: 'CANCELLED' });
    },

    /** 업무 처리 결과 조회. 처리 중이던 업무는 조회 시점에 은행 처리가 끝날 수 있다. */
    async getTaskResult(sessionId) {
      await wait('query');
      const s = store.getState();
      const g = systemGuard(s, true);
      if (g) return g;
      const ts = s.taskSessions[sessionId];
      if (!ts) return err('SESSION_NOT_FOUND', 'BUSINESS_REJECT', '업무 세션을 찾을 수 없어요.');
      if (ts.status === 'IN_PROGRESS') {
        const task = SC.getTask(ts.taskId);
        const facts = Object.keys(task.effects);
        const p = s.pending[facts[0]];
        if (p && p.sessionId === sessionId) {
          if (p.queriesLeft > 0) {
            store.update((d) => (d.pending[facts[0]].queriesLeft -= 1), '처리 중 업무 조회 ' + sessionId);
            return ok({ sessionId: sessionId, taskId: ts.taskId, status: 'IN_PROGRESS' });
          }
          store.update((d) => {
            applyEffects(d, task);
            d.taskSessions[sessionId].status = 'COMPLETED';
          }, '처리 중이던 업무 완료 확인 ' + task.label);
          return ok({ sessionId: sessionId, taskId: ts.taskId, status: 'COMPLETED' });
        }
      }
      return ok({ sessionId: sessionId, taskId: ts.taskId, status: ts.status, reflected: !ts.mismatch });
    },

    /* ---------------- 가입 ---------------- */

    newRequestId() {
      return newId('REQ');
    },

    /**
     * 가입 요청. 고객이 승인했을 때만 호출되어야 한다.
     * - 같은 requestId 재요청은 새 가입을 만들지 않는다.
     * - 은행이 조건을 다시 검사한다.
     */
    async submitApplication(req) {
      await wait('apply');
      const s = store.getState();
      const g = systemGuard(s, false);
      if (g) return err(g.error.code, g.error.kind, g.error.message + ' 가입 요청은 전송되지 않았어요.', { submitted: false });
      if (!req || !req.requestId) return err('REQUEST_ID_REQUIRED', 'BUSINESS_REJECT', '요청 식별값이 없어요.', { submitted: false });
      const existing = Object.keys(s.applications)
        .map((k) => s.applications[k])
        .find((a) => a.requestId === req.requestId);
      if (existing) {
        WSP.events.add('BANK', '중복 가입 요청 차단: ' + req.requestId + ' → 기존 ' + existing.id);
        return ok({ application: existing, duplicate: true });
      }
      const product = SC.getProduct(req.productId);
      if (!product) return err('PRODUCT_NOT_FOUND', 'BUSINESS_REJECT', '상품을 찾을 수 없어요.', { submitted: false });
      const unmet = unmetProductFacts(s, product);
      if (unmet.length) {
        return err('CONDITION_UNMET', 'BUSINESS_REJECT', '가입 조건을 충족하지 않아 가입되지 않았어요.', {
          submitted: false,
          unmet: unmet.map((c) => c.label),
        });
      }
      const outcome = s.simulation.nextApplicationOutcome || 'SUCCESS';
      const id = 'APP-' + String(2001 + Object.keys(s.applications).length);
      const app = {
        id: id,
        requestId: req.requestId,
        productId: req.productId,
        terms: req.terms || null,
        channel: req.channel || 'AI',
        status: outcome,
        createdAt: Date.now(),
        failureReason: outcome === 'FAILED' ? '은행에서 가입 요청을 처리하지 못했어요.' : null,
      };
      store.update((d) => {
        d.applications[id] = app;
        d.simulation.nextApplicationOutcome = 'SUCCESS';
      }, '가입 요청 ' + id + ' 처리 결과: ' + outcome);
      return ok({ application: app, duplicate: false });
    },

    /** 결과 조회 전용. 어떤 경우에도 가입 요청을 다시 보내지 않는다. */
    async getApplicationResult(appId) {
      await wait('query');
      const s = store.getState();
      const g = systemGuard(s, true);
      if (g) return g;
      const app = s.applications[appId];
      if (!app) return err('APP_NOT_FOUND', 'BUSINESS_REJECT', '가입 요청을 찾을 수 없어요.');
      return ok({ application: app });
    },

    /* ---------------- 상담 ---------------- */

    /** 상담 접수. 요약을 만든 것과 실제 접수 완료를 구분한다. */
    async createConsultation(summary) {
      await wait('mutate');
      const s = store.getState();
      const outcome = s.simulation.nextConsultOutcome || 'ACCEPTED';
      if (!s.system.bankAvailable || outcome === 'FAILED') {
        WSP.events.add('BANK', '상담 접수 실패 (가상 응답)');
        return err('CONSULT_FAILED', 'QUERY_FAILURE', '상담 접수가 완료되지 않았어요.');
      }
      const id = 'CS-' + String(5001 + Object.keys(s.consultations).length);
      const ticket = { id: id, summary: summary, status: 'ACCEPTED', eta: '영업일 기준 1일 이내 상담사 연락', createdAt: Date.now() };
      store.update((d) => {
        d.consultations[id] = ticket;
      }, '상담 접수 ' + id);
      return ok({ ticket: ticket });
    },

    /* ---------------- 시연 전용 ---------------- */

    setLatencyScale(v) {
      latencyScale = Math.max(0, Number(v) || 0);
    },
    getLatencyScale() {
      return latencyScale;
    },
    demoResolveApplication(appId, status) {
      const s = store.getState();
      const app = s.applications[appId];
      if (!app || (status !== 'SUCCESS' && status !== 'FAILED')) return false;
      if (app.status === 'SUCCESS' || app.status === 'FAILED') return false;
      store.update((d) => {
        d.applications[appId].status = status;
        if (status === 'FAILED') d.applications[appId].failureReason = '은행에서 가입 요청을 처리하지 못했어요.';
      }, '[시연] 가입 ' + appId + ' 은행 측 확정: ' + status);
      return true;
    },
  };

  WSP.mockBank = api;
})();
