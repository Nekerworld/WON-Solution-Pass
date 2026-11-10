/**
 * state.js
 * - 데모용 가상 정책(DEMO_POLICY)과 초기 은행 상태(initialBankState)
 * - 중앙 상태 저장소(createStore): 모든 화면/모듈이 같은 저장소를 참조한다.
 * - 이벤트 로그(events)
 * - 해결패스 유한 상태머신(createFSM): 전이 테이블에 없는 전이는 거부한다.
 *
 * 모든 값은 시연용 가상 데이터이며 실제 은행 시스템/정책과 무관하다.
 */
(function () {
  'use strict';

  const WSP = (window.WSP = window.WSP || {});

  function clone(value) {
    return JSON.parse(JSON.stringify(value));
  }

  function safeStorage() {
    try {
      const s = window.sessionStorage;
      const k = '__wsp_probe__';
      s.setItem(k, '1');
      s.removeItem(k);
      return s;
    } catch (e) {
      return null;
    }
  }

  /* ------------------------------------------------------------------
   * 데모용 가상 정책 - 실제 우리은행 정책이 아니다.
   * ------------------------------------------------------------------ */
  const DEMO_POLICY = Object.freeze({
    version: 'DEMO-POLICY-2026.11',
    isDemo: true,
    /** 이 금액을 초과하는 이체는 디지털 OTP 등록이 필요하다 (가상) */
    otpRequiredAbove: 1000000,
    /** OTP 없이 설정할 수 있는 1일 이체한도 상한 (가상) */
    maxLimitWithoutOtp: 1000000,
    /** 디지털 OTP 등록 전 고객확인 완료가 필요하다 (가상) */
    otpRegistrationRequiresKyc: true,
    minTransferLimit: 100000,
    maxTransferLimit: 50000000,
    /**
     * 해결 행동별 비용 가중치 (가상). 상태 그래프 간선의 weight로 쓰이며,
     * 경로 탐색은 이 합이 최소인 경로를 고른다.
     * 비용 = 사용자 부담(소요 시간·입력량) + 인증 강도 + 채널 제약을 단순 점수화한 값
     */
    actionWeights: Object.freeze({
      COMPLETE_KYC: 5,
      REGISTER_OTP: 3,
      CHANGE_TRANSFER_LIMIT: 2,
      RETURN_TO_TRANSFER: 1,
    }),
  });

  const initialBankState = Object.freeze({
    account: {
      name: '우리 주거래 통장',
      number: '1002-***-123456',
      balance: 5000000,
    },
    customer: {
      name: '김우리',
      kycCompleted: true,
      digitalOtpRegistered: false,
      transferLimit: 1000000,
      transferLimitChangeAllowed: true,
      accountRestricted: false,
    },
    transfer: {
      fromAccount: '1002-***-123456',
      amount: 1500000,
      recipient: '홍길동',
      recipientBank: '우리은행',
      recipientAccount: '1002-***-987654',
      requestId: null,
      transactionId: null,
      status: 'IDLE',
    },
    transactions: {},
    simulation: {
      /** 다음 이체 요청에 대해 가상 은행이 반환할 결과 (시연 패널에서만 변경) */
      nextTransferOutcome: 'SUCCESS',
      /** 상태 조회 실패 주입 */
      queryFailure: false,
    },
    system: {
      bankAvailable: true,
      stateVersion: 1,
    },
  });

  /* ------------------------------------------------------------------
   * 이벤트 로그
   * ------------------------------------------------------------------ */
  function createEventLog(limit) {
    const max = limit || 200;
    let items = [];
    const listeners = new Set();
    return {
      add(source, message, meta) {
        const entry = {
          at: new Date().toISOString(),
          source: source,
          message: message,
          meta: meta || null,
        };
        items.push(entry);
        if (items.length > max) items = items.slice(items.length - max);
        listeners.forEach((fn) => {
          try {
            fn(entry);
          } catch (e) {
            console.error(e);
          }
        });
        return entry;
      },
      list() {
        return items.slice();
      },
      clear() {
        items = [];
      },
      subscribe(fn) {
        listeners.add(fn);
        return () => listeners.delete(fn);
      },
    };
  }

  const events = createEventLog(300);

  /* ------------------------------------------------------------------
   * 중앙 상태 저장소
   * ------------------------------------------------------------------ */
  function createStore(initial, options) {
    const opts = options || {};
    const storage = opts.persist === false ? null : safeStorage();
    const key = opts.storageKey || 'wsp.bankState.v1';
    const listeners = new Set();
    let silent = false;

    function load() {
      if (!storage) return null;
      try {
        const raw = storage.getItem(key);
        if (!raw) return null;
        const parsed = JSON.parse(raw);
        if (!parsed || !parsed.system || typeof parsed.system.stateVersion !== 'number') return null;
        return parsed;
      } catch (e) {
        return null;
      }
    }

    let state = load() || clone(initial);

    function persist() {
      if (!storage) return;
      try {
        storage.setItem(key, JSON.stringify(state));
      } catch (e) {
        /* 저장 실패는 시연에 영향 없음 */
      }
    }

    function emit(change) {
      if (silent) return;
      listeners.forEach((fn) => {
        try {
          fn(clone(state), change);
        } catch (e) {
          console.error(e);
        }
      });
    }

    return {
      /** 항상 깊은 복사본을 반환하여 외부에서 직접 변경하지 못하게 한다. */
      getState() {
        return clone(state);
      },
      /** 모든 상태 변경은 이 함수를 거치며 stateVersion이 1 증가한다. */
      update(mutator, reason) {
        const draft = clone(state);
        mutator(draft);
        draft.system.stateVersion = state.system.stateVersion + 1;
        state = draft;
        persist();
        events.add('STORE', reason || '상태 변경', { stateVersion: state.system.stateVersion });
        emit({ type: 'update', reason: reason, stateVersion: state.system.stateVersion });
        return clone(state);
      },
      reset(reason) {
        state = clone(initial);
        persist();
        events.add('STORE', reason || '데모 초기화', { stateVersion: state.system.stateVersion });
        emit({ type: 'reset', reason: reason, stateVersion: state.system.stateVersion });
        return clone(state);
      },
      /** 자가 테스트 후 스냅샷 복원용 */
      replace(snapshot, reason) {
        state = clone(snapshot);
        persist();
        if (reason) events.add('STORE', reason, { stateVersion: state.system.stateVersion });
        emit({ type: 'replace', reason: reason, stateVersion: state.system.stateVersion });
      },
      subscribe(fn) {
        listeners.add(fn);
        return () => listeners.delete(fn);
      },
      setSilent(value) {
        silent = !!value;
      },
    };
  }

  /* ------------------------------------------------------------------
   * 해결패스 유한 상태머신
   * ------------------------------------------------------------------ */
  const FSM_STATES = Object.freeze([
    'IDLE',
    'DIAGNOSING',
    'PLAN_READY',
    'WAITING_USER',
    'RECHECKING',
    'READY_TO_RETRY',
    'VERIFYING',
    'COMPLETED',
    'ESCALATED',
  ]);

  /**
   * 전이 테이블: state -> { event: nextState }
   * - PENDING 결과는 전이 없이 VERIFYING에 머물며 결과 조회만 허용한다.
   * - FAILED / UNKNOWN 결과는 ESCALATED로 보낸다. (자동 재이체 금지)
   * - COMPLETED는 VERIFYING에서 RESULT_SUCCESS로만 도달 가능하다.
   */
  const FSM_TRANSITIONS = Object.freeze({
    IDLE: { TRANSFER_FAILED: 'DIAGNOSING', MANUAL_DIAGNOSE: 'DIAGNOSING' },
    DIAGNOSING: { PATH_FOUND: 'PLAN_READY', NO_ACTION_NEEDED: 'READY_TO_RETRY', ESCALATE: 'ESCALATED' },
    PLAN_READY: { STEP_SELECTED: 'WAITING_USER', RECHECK: 'RECHECKING', ESCALATE: 'ESCALATED' },
    WAITING_USER: { USER_RETURNED: 'RECHECKING', RECHECK: 'RECHECKING', ESCALATE: 'ESCALATED' },
    RECHECKING: { PATH_FOUND: 'PLAN_READY', ALL_MET: 'READY_TO_RETRY', ESCALATE: 'ESCALATED' },
    READY_TO_RETRY: { USER_APPROVED: 'VERIFYING', RECHECK: 'RECHECKING', ESCALATE: 'ESCALATED' },
    VERIFYING: {
      RESULT_SUCCESS: 'COMPLETED',
      RESULT_FAILED: 'ESCALATED',
      RESULT_UNKNOWN: 'ESCALATED',
      ESCALATE: 'ESCALATED',
    },
    COMPLETED: { NEW_CASE: 'IDLE' },
    ESCALATED: { RECHECK: 'RECHECKING', RESULT_QUERY: 'VERIFYING', NEW_CASE: 'IDLE' },
  });

  function createFSM(options) {
    const opts = options || {};
    let current = opts.initial || 'IDLE';
    let history = [];
    const listeners = new Set();
    const log = opts.log !== false;

    function notify(record) {
      listeners.forEach((fn) => {
        try {
          fn(current, record);
        } catch (e) {
          console.error(e);
        }
      });
    }

    return {
      get state() {
        return current;
      },
      can(event) {
        const row = FSM_TRANSITIONS[current];
        return !!(row && row[event]);
      },
      /** @returns {{ok:boolean, from:string, to?:string, event:string}} */
      transition(event, meta) {
        const row = FSM_TRANSITIONS[current];
        const next = row && row[event];
        if (!next) {
          if (log) {
            console.warn('[WSP FSM] 거부된 전이: ' + current + ' --' + event + '--> (정의되지 않음)');
            events.add('FSM', '거부된 전이 ' + current + ' --' + event + '-->', { rejected: true });
          }
          return { ok: false, from: current, event: event };
        }
        const record = { from: current, to: next, event: event, at: new Date().toISOString(), meta: meta || null };
        current = next;
        history.push(record);
        if (history.length > 100) history = history.slice(-100);
        if (log) events.add('FSM', record.from + ' --' + event + '--> ' + next);
        notify(record);
        return { ok: true, from: record.from, to: next, event: event };
      },
      reset() {
        current = 'IDLE';
        history = [];
        if (log) events.add('FSM', '상태머신 초기화 → IDLE');
        notify(null);
      },
      restore(state, savedHistory) {
        if (FSM_STATES.indexOf(state) === -1) return;
        current = state;
        history = Array.isArray(savedHistory) ? savedHistory.slice(-100) : [];
        notify(null);
      },
      history() {
        return history.slice();
      },
      subscribe(fn) {
        listeners.add(fn);
        return () => listeners.delete(fn);
      },
    };
  }

  /* ------------------------------------------------------------------
   * 공용 포맷터
   * ------------------------------------------------------------------ */
  function formatWon(n) {
    return Number(n || 0).toLocaleString('ko-KR') + '원';
  }

  /** 1500000 -> "150만원", 1234567 -> "1,234,567원" */
  function formatMan(n) {
    const v = Number(n || 0);
    if (v >= 10000 && v % 10000 === 0) {
      const man = v / 10000;
      if (man >= 10000 && man % 10000 === 0) return man / 10000 + '억원';
      return man.toLocaleString('ko-KR') + '만원';
    }
    return formatWon(v);
  }

  WSP.utils = { clone: clone, formatWon: formatWon, formatMan: formatMan, safeStorage: safeStorage };
  WSP.DEMO_POLICY = DEMO_POLICY;
  WSP.initialBankState = initialBankState;
  WSP.events = events;
  WSP.createStore = createStore;
  WSP.createFSM = createFSM;
  WSP.FSM_STATES = FSM_STATES;
  WSP.FSM_TRANSITIONS = FSM_TRANSITIONS;

  /** 애플리케이션 전체가 공유하는 단일 저장소 */
  WSP.store = createStore(initialBankState, { storageKey: 'wsp.bankState.v1' });
})();
