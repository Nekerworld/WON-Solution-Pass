/**
 * state.js
 * - 공용 유틸, 이벤트 로그, 중앙 상태 저장소(createStore)
 * - 트랙별 유한 상태머신 정의(FSM_DEFS)와 생성기(createFSM)
 *   전이표에 없는 전이는 거부한다. 각 간선에는 출처(src)를 기록한다.
 *   D: 합의 워크플로우(Group 1.png)에 있는 화살표
 *   P1~P8: 계획 0-2절에서 제안한 보완 전이
 *   S: 안전 장치(중복 실행 방지, 결과 조회 등) 전이
 * - 동작 등록소(WSP.actions): 각 모듈이 data-action 처리기를 등록한다.
 */
(function () {
  'use strict';

  const WSP = (window.WSP = window.WSP || {});

  function clone(value) {
    return value === undefined ? undefined : JSON.parse(JSON.stringify(value));
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

  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  /* ------------------------------------------------------------------
   * 이벤트 로그
   * ------------------------------------------------------------------ */
  function createEventLog(limit) {
    const max = limit || 200;
    let items = [];
    const listeners = new Set();
    return {
      add(source, message, meta) {
        const entry = { at: new Date().toISOString(), source: source, message: message, meta: meta || null };
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

  const events = createEventLog(400);

  /* ------------------------------------------------------------------
   * 중앙 상태 저장소
   * ------------------------------------------------------------------ */
  function createStore(initial, options) {
    const opts = options || {};
    const storage = opts.persist === false ? null : safeStorage();
    const key = opts.storageKey || 'wsp.store';
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
   * 상태머신 정의
   * 간선: [from, event, to, src]
   * ------------------------------------------------------------------ */
  const EXIT_P8 = (states, to) => states.map((s) => [s, 'EXIT', to, 'P8']);

  const FSM_DEFS = Object.freeze({
    join: {
      name: '가입 지원 (AI)',
      initial: 'IDLE',
      edges: [
        ['IDLE', 'START', 'CONSENT', 'D'],
        ['CONSENT', 'AGREE', 'CHECKING', 'D'],
        ['CHECKING', 'NONE_MISSING', 'READY_TO_APPLY', 'D'],
        ['CHECKING', 'MISSING', 'CLARIFYING', 'D'],
        ['CHECKING', 'QUERY_FAILED', 'CHECK_FAILED', 'P3'],
        ['CHECK_FAILED', 'RETRY', 'CHECKING', 'P3'],
        ['CHECK_FAILED', 'ESCALATE', 'ESCALATED', 'P3'],
        ['CLARIFYING', 'CLARIFIED', 'ROUTE_CHECK', 'D'],
        ['CLARIFYING', 'ESCALATE', 'ESCALATED', 'P8'],
        ['ROUTE_CHECK', 'ROUTE_FOUND', 'OPTIONS_READY', 'D'],
        ['ROUTE_CHECK', 'NO_ROUTE', 'ESCALATED', 'D'],
        ['OPTIONS_READY', 'TASK_OPENED', 'TASK_OPEN', 'D'],
        ['OPTIONS_READY', 'CONSTRAINT_CHANGED', 'CLARIFYING', 'P4'],
        ['OPTIONS_READY', 'ESCALATE', 'ESCALATED', 'P8'],
        ['TASK_OPEN', 'MODAL_CLOSED', 'RECHECKING', 'D'],
        ['RECHECKING', 'ALL_MET', 'READY_TO_APPLY', 'D'],
        ['RECHECKING', 'REMAINING', 'REMAINING', 'D'],
        ['RECHECKING', 'EXCEPTION', 'INVESTIGATING', 'D'],
        ['REMAINING', 'TASK_OPENED', 'TASK_OPEN', 'D'],
        ['REMAINING', 'NO_ROUTE', 'ESCALATED', 'P1'],
        ['REMAINING', 'ESCALATE', 'ESCALATED', 'P8'],
        ['INVESTIGATING', 'RESOLVED', 'RECHECKING', 'P2'],
        ['INVESTIGATING', 'RETRY', 'REMAINING', 'P2'],
        ['INVESTIGATING', 'UNRESOLVABLE', 'ESCALATED', 'D'],
        ['READY_TO_APPLY', 'APPROVED', 'APPLYING', 'D'],
        ['APPLYING', 'SUBMITTED', 'VERIFYING', 'D'],
        ['APPLYING', 'NOT_SENT', 'READY_TO_APPLY', 'S'],
        ['APPLYING', 'REJECTED', 'RECHECKING', 'S'],
        ['VERIFYING', 'RESULT_SUCCESS', 'COMPLETED', 'D'],
        ['VERIFYING', 'RESULT_FAILED', 'FAILED', 'D'],
        ['VERIFYING', 'RESULT_UNKNOWN', 'RESULT_UNCERTAIN', 'D'],
        ['RESULT_UNCERTAIN', 'RESULT_QUERY', 'VERIFYING', 'S'],
        ['COMPLETED', 'NEW_CASE', 'IDLE', 'S'],
        ['FAILED', 'NEW_CASE', 'IDLE', 'S'],
        ['FAILED', 'ESCALATE', 'ESCALATED', 'P7'],
        ['ESCALATED', 'RECHECK', 'CHECKING', 'P7'],
        ['ESCALATED', 'NEW_CASE', 'IDLE', 'P7'],
      ].concat(EXIT_P8(['CONSENT', 'CHECK_FAILED', 'CLARIFYING', 'OPTIONS_READY', 'REMAINING', 'INVESTIGATING', 'READY_TO_APPLY'], 'IDLE')),
    },
    direct: {
      name: '직접 가입',
      initial: 'IDLE',
      edges: [
        ['IDLE', 'START', 'D_START', 'D'],
        ['D_START', 'BEGIN', 'D_STEP', 'D'],
        ['D_STEP', 'STEP_DONE', 'D_CHECK', 'D'],
        ['D_CHECK', 'PASS', 'D_STEP', 'D'],
        ['D_CHECK', 'UNMET', 'D_NOTICE', 'D'],
        ['D_CHECK', 'ALL_PASSED', 'D_APPROVE', 'P5'],
        ['D_CHECK', 'QUERY_FAILED', 'D_STEP', 'S'],
        ['D_NOTICE', 'GO_FIX', 'D_SELF_FIX', 'D'],
        ['D_SELF_FIX', 'RESTART', 'D_STEP', 'P6'],
        ['D_APPROVE', 'APPROVED', 'D_VERIFYING', 'P5'],
        ['D_APPROVE', 'REJECTED', 'D_NOTICE', 'S'],
        ['D_VERIFYING', 'RESULT_SUCCESS', 'D_DONE', 'D'],
        ['D_VERIFYING', 'RESULT_FAILED', 'D_FAILED', 'S'],
        ['D_VERIFYING', 'RESULT_UNKNOWN', 'D_UNCERTAIN', 'S'],
        ['D_UNCERTAIN', 'RESULT_QUERY', 'D_VERIFYING', 'S'],
        ['D_DONE', 'NEW_CASE', 'IDLE', 'S'],
        ['D_FAILED', 'NEW_CASE', 'IDLE', 'S'],
      ].concat(EXIT_P8(['D_START', 'D_STEP', 'D_NOTICE', 'D_SELF_FIX', 'D_APPROVE'], 'IDLE')),
    },
    asset: {
      name: '자산관리',
      initial: 'IDLE',
      edges: [
        ['IDLE', 'START', 'CONSENT', 'D'],
        ['CONSENT', 'AGREE', 'GOAL', 'D'],
        ['GOAL', 'GOAL_SET', 'COLLECTING', 'D'],
        ['COLLECTING', 'COLLECTED', 'TAGGING', 'D'],
        ['COLLECTING', 'QUERY_FAILED', 'HOLD', 'P3'],
        ['TAGGING', 'TAGGED', 'CALCULATING', 'D'],
        ['CALCULATING', 'CALCULATED', 'INTERPRETING', 'D'],
        ['INTERPRETING', 'INTERPRETED', 'GAP_CHECK', 'D'],
        ['GAP_CHECK', 'NO_GAP', 'PROPOSED_FULL', 'D'],
        ['GAP_CHECK', 'ASK', 'ASKING', 'D'],
        ['GAP_CHECK', 'LIMIT_OR_STOP', 'PROPOSABLE_CHECK', 'D'],
        ['ASKING', 'ANSWERED', 'RECALC_ANSWER', 'D'],
        ['ASKING', 'UNKNOWN_OR_REFUSED', 'PROPOSABLE_CHECK', 'D'],
        ['ASKING', 'STOP_REQUEST', 'PROPOSABLE_CHECK', 'D'],
        ['RECALC_ANSWER', 'RECALCULATED', 'INTERPRETING', 'D'],
        ['PROPOSABLE_CHECK', 'PROPOSABLE', 'PROPOSED_LIMITED', 'D'],
        ['PROPOSABLE_CHECK', 'NOT_PROPOSABLE', 'HOLD', 'D'],
        ['PROPOSED_FULL', 'SHOWN', 'REVIEW', 'D'],
        ['PROPOSED_LIMITED', 'SHOWN', 'REVIEW', 'D'],
        ['REVIEW', 'ACCEPT', 'NEXT_ACTION', 'D'],
        ['REVIEW', 'MODIFY', 'RECALC_CHANGE', 'D'],
        ['REVIEW', 'END', 'CLOSED', 'D'],
        ['RECALC_CHANGE', 'RECALCULATED', 'INTERPRETING', 'D'],
        ['NEXT_ACTION', 'CONSULT', 'HANDOFF', 'D'],
        ['NEXT_ACTION', 'KEEP', 'CLOSED', 'D'],
        ['NEXT_ACTION', 'RECHECK_INFO', 'RECONSULT', 'D'],
        ['NEXT_ACTION', 'EXPLORE', 'EXPLORE', 'D'],
        ['EXPLORE', 'PRODUCT_SELECTED', 'TO_JOIN', 'D'],
        ['EXPLORE', 'BACK', 'NEXT_ACTION', 'S'],
        ['HOLD', 'CONSULT', 'HANDOFF', 'P7'],
        ['HOLD', 'RECHECK_INFO', 'RECONSULT', 'P7'],
        ['HOLD', 'END', 'CLOSED', 'P7'],
        ['RECONSULT', 'RESUME', 'INTERPRETING', 'P7'],
        ['RECONSULT', 'END', 'CLOSED', 'P7'],
        ['HANDOFF', 'END', 'CLOSED', 'P7'],
        ['CLOSED', 'NEW_CASE', 'IDLE', 'S'],
        ['TO_JOIN', 'NEW_CASE', 'IDLE', 'S'],
      ].concat(EXIT_P8(['CONSENT', 'GOAL', 'ASKING', 'GAP_CHECK', 'REVIEW', 'NEXT_ACTION', 'EXPLORE', 'HOLD'], 'CLOSED')),
    },
  });

  function buildTable(def) {
    const table = {};
    const src = {};
    const states = [];
    const addState = (s) => {
      if (states.indexOf(s) === -1) states.push(s);
    };
    addState(def.initial);
    def.edges.forEach((e) => {
      addState(e[0]);
      addState(e[2]);
      (table[e[0]] = table[e[0]] || {})[e[1]] = e[2];
      src[e[0] + '|' + e[1]] = e[3];
    });
    return { table: table, src: src, states: states };
  }

  const FSM_TABLES = {};
  Object.keys(FSM_DEFS).forEach((k) => (FSM_TABLES[k] = buildTable(FSM_DEFS[k])));

  function createFSM(kind, options) {
    const opts = options || {};
    const def = FSM_DEFS[kind];
    const tbl = FSM_TABLES[kind];
    let current = def.initial;
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
      kind: kind,
      get state() {
        return current;
      },
      can(event) {
        const row = tbl.table[current];
        return !!(row && row[event]);
      },
      transition(event, meta) {
        const row = tbl.table[current];
        const next = row && row[event];
        if (!next) {
          if (log) {
            console.warn('[WSP FSM:' + kind + '] 거부된 전이: ' + current + ' --' + event + '-->');
            events.add('FSM', '[' + kind + '] 거부된 전이 ' + current + ' --' + event + '-->', { rejected: true });
          }
          return { ok: false, from: current, event: event };
        }
        const record = {
          from: current,
          to: next,
          event: event,
          src: tbl.src[current + '|' + event],
          at: new Date().toISOString(),
          meta: meta || null,
        };
        current = next;
        history.push(record);
        if (history.length > 120) history = history.slice(-120);
        if (log) events.add('FSM', '[' + kind + '] ' + record.from + ' --' + event + '--> ' + next + (record.src !== 'D' ? ' (' + record.src + ')' : ''));
        notify(record);
        return { ok: true, from: record.from, to: next, event: event };
      },
      reset() {
        current = def.initial;
        history = [];
        notify(null);
      },
      restore(state, savedHistory) {
        if (tbl.states.indexOf(state) === -1) return;
        current = state;
        history = Array.isArray(savedHistory) ? savedHistory.slice(-120) : [];
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
   * 동작 등록소
   * ------------------------------------------------------------------ */
  const actions = {};
  function registerActions(map) {
    Object.keys(map).forEach((k) => {
      if (actions[k]) console.warn('[WSP] 동작 중복 등록: ' + k);
      actions[k] = map[k];
    });
  }

  /* ------------------------------------------------------------------
   * 포맷터
   * ------------------------------------------------------------------ */
  function formatWon(n) {
    return Number(n || 0).toLocaleString('ko-KR') + '원';
  }

  /** 1500000 -> "150만원", 1234567 -> "1,234,567원" */
  function formatMan(n) {
    const v = Number(n || 0);
    if (v >= 10000 && v % 10000 === 0) {
      const man = v / 10000;
      if (man >= 10000) {
        const eok = Math.floor(man / 10000);
        const rest = man % 10000;
        return eok + '억' + (rest ? ' ' + rest.toLocaleString('ko-KR') + '만' : '') + '원';
      }
      return man.toLocaleString('ko-KR') + '만원';
    }
    return formatWon(v);
  }

  /** [받침 있음, 받침 없음, 판단 불가] */
  const JOSA = {
    을: ['을', '를', '을(를)'],
    이: ['이', '가', '이(가)'],
    은: ['은', '는', '은(는)'],
    과: ['과', '와', '과(와)'],
    로: ['으로', '로', '(으)로'],
    이에요: ['이에요', '예요', '(이)에요'],
  };
  /** 받침에 맞춘 조사를 붙인다. josa('계좌', '을') → '계좌를'. 끝의 괄호 보충 설명은 건너뛰고 판단한다. */
  function josa(word, kind) {
    const w = String(word);
    const forms = JOSA[kind];
    const base = w.replace(/\s*\([^)]*\)\s*$/, '');
    const code = base.charCodeAt(base.length - 1) - 0xac00;
    if (code < 0 || code > 11171) return w + forms[2];
    const jong = code % 28;
    if (kind === '로') return w + (jong === 0 || jong === 8 ? forms[1] : forms[0]);
    return w + (jong === 0 ? forms[1] : forms[0]);
  }

  function newId(prefix) {
    return prefix + '-' + Date.now().toString(36).toUpperCase().slice(-5) + Math.random().toString(36).slice(2, 5).toUpperCase();
  }

  WSP.utils = { clone: clone, formatWon: formatWon, formatMan: formatMan, safeStorage: safeStorage, sleep: sleep, newId: newId, josa: josa };
  WSP.events = events;
  WSP.createStore = createStore;
  WSP.FSM_DEFS = FSM_DEFS;
  WSP.FSM_TABLES = FSM_TABLES;
  WSP.createFSM = createFSM;
  WSP.actions = actions;
  WSP.registerActions = registerActions;
})();
