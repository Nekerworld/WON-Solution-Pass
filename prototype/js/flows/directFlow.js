/**
 * flows/directFlow.js
 * 가입 지원 - 직접 가입 (상태머신 direct)
 * 기존 가입 화면 흐름: 단계마다 입력하고, 단계별로 은행이 조건을 확인한다.
 * 조건이 부족하면 안내만 받고 고객이 직접 메뉴를 찾아 해결한 뒤 처음부터 다시 시작한다(P6).
 * 가입 승인·결과 확인은 AI 경로와 같은 은행 API와 규칙을 쓴다(P5).
 */
(function () {
  'use strict';

  const WSP = window.WSP;
  const SC = WSP.scenario;
  const bank = WSP.mockBank;
  const A = () => WSP.app;
  const UI = () => WSP.ui;
  const fsm = () => WSP.app.fsms.direct;
  const S = () => WSP.app.session.direct;
  const SCREENS = ['direct', 'apply-result', 'menu', 'home'];

  /** 조건별로 고객이 찾아가야 하는 메뉴 (직접 가입 화면은 대체 수단까지 안내하지 않는다) */
  const FIX_MENU = { IDENTITY: '실명확인', ACCOUNT: '계좌 개설', KYC: '내 정보 관리', CERT: '인증센터', ADULT: null };

  function fresh(productId) {
    const p = SC.getProduct(productId);
    return {
      productId: productId,
      stepIndex: 0,
      input: { agreed: false, monthly: 300000, months: p.periods[1] || p.periods[0] || 0, job: '', purpose: '' },
      checking: false,
      notice: null,
      requestId: null,
      appId: null,
      application: null,
      applyNotice: null,
      metrics: { startedAt: Date.now(), endedAt: null, steps: 0, restarts: 0, menuVisits: 0, notices: 0 },
    };
  }

  function stale(ep) {
    return ep !== A().epoch() || !S();
  }

  function product() {
    return SC.getProduct(S().productId);
  }

  function start(productId) {
    if (fsm().state !== 'IDLE') return false;
    WSP.app.session.direct = fresh(productId);
    fsm().transition('START', { productId: productId });
    return true;
  }

  function begin() {
    if (fsm().state !== 'D_START') return;
    S().stepIndex = 0;
    fsm().transition('BEGIN');
    A().refresh(SCREENS);
  }

  /** 현재 단계 입력값 검증 (화면 입력 규칙) */
  function validateStep(step) {
    const d = S();
    const p = product();
    if (step.id === 'terms' && !d.input.agreed) return '상품 안내와 약관에 동의해 주세요.';
    if (step.id === 'amount') {
      if (p.maxMonthly && (!d.input.monthly || d.input.monthly < p.minMonthly || d.input.monthly > p.maxMonthly)) {
        return '월 납입액은 ' + WSP.utils.formatMan(p.minMonthly) + '~' + WSP.utils.formatMan(p.maxMonthly) + ' 사이로 입력해 주세요.';
      }
      if (p.periods.length && !d.input.months) return '가입 기간을 선택해 주세요.';
    }
    return null;
  }

  async function next() {
    const d = S();
    if (!d || fsm().state !== 'D_STEP') return;
    const p = product();
    const step = p.directSteps[d.stepIndex];
    const msg = validateStep(step);
    if (msg) {
      UI().toast(msg, 'warning');
      return;
    }
    const ep = A().epoch();
    d.metrics.steps += 1;
    fsm().transition('STEP_DONE', { step: step.id });
    d.checking = true;
    A().refresh(SCREENS);
    let unmet = [];
    if (step.checks.length) {
      const c = await bank.checkConditions(d.productId);
      if (stale(ep)) return;
      d.checking = false;
      if (!c.ok) {
        fsm().transition('QUERY_FAILED', { code: c.error.code });
        UI().toast('확인하지 못했어요. 잠시 후 다시 시도해 주세요.', 'danger');
        A().refresh(SCREENS);
        return;
      }
      // 기존 가입 화면처럼 첫 번째 미충족 조건 하나만 알려 준다
      unmet = c.data.conditions.filter((x) => step.checks.indexOf(x.id) !== -1 && !x.value).slice(0, 1);
    }
    d.checking = false;
    if (unmet.length) {
      d.metrics.notices += 1;
      d.notice = {
        stepId: step.id,
        stepLabel: step.label,
        conditions: unmet.map((x) => ({ id: x.id, label: SC.CONDITIONS[x.id].label, menu: FIX_MENU[x.id] })),
      };
      fsm().transition('UNMET', { step: step.id, unmet: unmet.map((x) => x.id) });
      A().refresh(SCREENS);
      return;
    }
    if (d.stepIndex >= p.directSteps.length - 1) {
      if (!d.requestId) d.requestId = bank.newRequestId();
      fsm().transition('ALL_PASSED');
    } else {
      d.stepIndex += 1;
      fsm().transition('PASS', { next: p.directSteps[d.stepIndex].id });
    }
    A().refresh(SCREENS);
  }

  function goFix() {
    const d = S();
    if (fsm().state !== 'D_NOTICE') return;
    fsm().transition('GO_FIX');
    const menus = (d.notice ? d.notice.conditions : []).map((c) => c.menu).filter(Boolean);
    UI().navigate('menu', { highlight: menus[0] || null, from: 'direct' });
  }

  function restart() {
    const d = S();
    if (fsm().state !== 'D_SELF_FIX') return;
    d.stepIndex = 0;
    d.notice = null;
    d.input.agreed = false;
    d.metrics.restarts += 1;
    fsm().transition('RESTART');
    UI().navigate('direct', {}, { backTo: true });
  }

  async function approve() {
    const d = S();
    if (!d || fsm().state !== 'D_APPROVE') return;
    const p = product();
    const ok = await UI().confirm({
      title: '가입을 신청할까요?',
      bodyHtml:
        UI().kvRows([
          ['상품', UI().esc(p.name)],
          p.maxMonthly ? ['월 납입액', WSP.utils.formatMan(d.input.monthly)] : null,
          p.periods.length ? ['가입 기간', d.input.months + '개월'] : null,
        ].filter(Boolean)) + '<p class="fineprint">가입 완료는 은행 처리 결과로 확인해요.</p>',
      confirmText: '가입 신청',
      cancelText: '취소',
    });
    if (!ok || fsm().state !== 'D_APPROVE') return;
    const ep = A().epoch();
    d.applyNotice = null;
    d.checking = true;
    A().refresh(SCREENS);
    const r = await bank.submitApplication({
      requestId: d.requestId,
      productId: d.productId,
      terms: { monthly: d.input.monthly, months: d.input.months },
      channel: 'DIRECT',
    });
    if (stale(ep)) return;
    d.checking = false;
    if (!r.ok) {
      if (r.error.code === 'CONDITION_UNMET') {
        d.notice = { stepId: 'approve', stepLabel: '가입 신청', conditions: (r.error.unmet || []).map((l) => ({ id: null, label: l, menu: null })) };
        fsm().transition('REJECTED', { code: r.error.code });
      } else {
        d.applyNotice = r.error.message + ' 다시 신청해도 중복 가입되지 않아요.';
      }
      A().refresh(SCREENS);
      return;
    }
    d.appId = r.data.application.id;
    d.application = r.data.application;
    fsm().transition('APPROVED', { appId: d.appId });
    UI().navigate('apply-result', { track: 'direct' }, { replace: true });
    await verify(ep);
  }

  let verifying = false;
  async function verify(ep) {
    if (verifying) return;
    verifying = true;
    try {
      await verifyOnce(ep);
    } finally {
      verifying = false;
    }
  }

  async function verifyOnce(ep) {
    const d = S();
    const r = await bank.getApplicationResult(d.appId);
    if (stale(ep) || fsm().state !== 'D_VERIFYING') return;
    if (r.ok) d.application = r.data.application;
    const status = r.ok ? r.data.application.status : 'UNKNOWN';
    if (status === 'SUCCESS') {
      d.metrics.endedAt = Date.now();
      WSP.app.session.lastMetrics.direct = d.metrics;
      fsm().transition('RESULT_SUCCESS');
    } else if (status === 'FAILED') fsm().transition('RESULT_FAILED');
    else fsm().transition('RESULT_UNKNOWN', { status: status });
    A().refresh(SCREENS);
  }

  async function queryResult() {
    if (fsm().state !== 'D_UNCERTAIN') return;
    fsm().transition('RESULT_QUERY');
    A().refresh(SCREENS);
    await verify(A().epoch());
  }

  async function exit() {
    if (!fsm().can('EXIT')) return;
    const ok = await UI().confirm({
      title: '가입을 그만할까요?',
      bodyHtml: '<p>입력한 내용은 저장되지 않아요. 다시 가입하면 처음부터 입력해야 해요.</p>',
      confirmText: '그만하기',
      cancelText: '계속하기',
    });
    if (!ok || !fsm().can('EXIT')) return;
    fsm().transition('EXIT');
    WSP.app.session.direct = null;
    UI().navigate('home', {}, { resetHistory: true, back: true });
  }

  function newCase() {
    if (!fsm().can('NEW_CASE')) return;
    fsm().transition('NEW_CASE');
    WSP.app.session.direct = null;
    UI().navigate('home', {}, { resetHistory: true, back: true });
  }

  /** 새로고침 등으로 확인 단계에서 멈춘 경우 */
  function resume() {
    const st = fsm().state;
    if (!S()) return;
    if (st === 'D_CHECK') {
      fsm().transition('QUERY_FAILED', { reason: 'RESUME' });
      A().refresh(SCREENS);
    } else if (st === 'D_VERIFYING') verify(A().epoch());
  }

  WSP.directFlow = { start: start, begin: begin, next: next, goFix: goFix, restart: restart, approve: approve, queryResult: queryResult, exit: exit, newCase: newCase, resume: resume, FIX_MENU: FIX_MENU };

  WSP.registerActions({
    'direct-start'(d) {
      const st = fsm().state;
      if (st !== 'IDLE') {
        if (S() && S().productId === d.product) return UI().navigate('direct');
        UI().toast('진행 중인 직접 가입이 있어요. 홈에서 이어 가거나 그만해 주세요.', 'warning');
        return;
      }
      if (start(d.product)) UI().navigate('direct');
    },
    'direct-begin'() {
      begin();
    },
    'direct-next'() {
      return A().guard('direct-next', next);
    },
    'direct-go-fix'() {
      goFix();
    },
    'direct-restart'() {
      restart();
    },
    'direct-approve'() {
      return A().guard('direct-approve', approve);
    },
    'direct-query-result'() {
      return A().guard('direct-query', queryResult);
    },
    'direct-exit'() {
      return exit();
    },
    'direct-new'() {
      newCase();
    },
    'direct-open'() {
      const st = fsm().state;
      if (st === 'IDLE') return;
      if (['D_VERIFYING', 'D_UNCERTAIN', 'D_DONE', 'D_FAILED'].indexOf(st) !== -1) UI().navigate('apply-result', { track: 'direct' });
      else if (st === 'D_SELF_FIX') UI().navigate('menu', { from: 'direct' });
      else UI().navigate('direct');
    },
    'direct-agree'(d, el) {
      if (!S()) return;
      S().input.agreed = !S().input.agreed;
      A().refresh(['direct']);
    },
    'direct-months'(d) {
      if (!S()) return;
      S().input.months = Number(d.value);
      A().refresh(['direct']);
    },
    'direct-field'(d) {
      if (!S()) return;
      S().input[d.field] = d.value;
      A().refresh(['direct']);
    },
    'input:direct-monthly'(el) {
      if (!S()) return;
      S().input.monthly = Number(String(el.value).replace(/[^\d]/g, '')) || 0;
      A().save();
    },
  });
})();
