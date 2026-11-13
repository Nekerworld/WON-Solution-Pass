/**
 * app.js
 * 앱 공통 오케스트레이션.
 * - 트랙별 상태머신 3개(가입 지원 AI / 직접 가입 / 자산관리)와 화면 세션을 보관한다.
 * - data-action은 WSP.actions(동작 등록소)로 위임한다. 등록되지 않은 동작은 무시한다.
 * - 새로고침 시 세션을 복원하고, 처리 중이던 단계는 각 흐름의 resume()이 은행 재조회로 이어 간다.
 * - 데모 초기화 시 epoch를 올려 진행 중이던 비동기 흐름이 이후 상태를 건드리지 못하게 한다.
 */
(function () {
  'use strict';

  const WSP = window.WSP;
  const storage = WSP.utils.safeStorage();
  const SESSION_KEY = 'wsp.session.v2';

  const fsms = {
    join: WSP.createFSM('join'),
    direct: WSP.createFSM('direct'),
    asset: WSP.createFSM('asset'),
  };

  function freshSession() {
    return {
      ui: { hideBalance: false, disclaimerClosed: false },
      join: null,
      direct: null,
      asset: null,
      /** 직전 완료 건의 지표 (시연 패널 비교용) */
      lastMetrics: { join: null, direct: null },
    };
  }

  let session = freshSession();
  let epoch = 0;
  const busy = new Set();
  const changeListeners = new Set();

  function save() {
    if (!storage) return;
    try {
      const f = {};
      Object.keys(fsms).forEach((k) => (f[k] = { state: fsms[k].state, history: fsms[k].history() }));
      storage.setItem(SESSION_KEY, JSON.stringify({ fsm: f, session: session }));
    } catch (e) {
      /* 저장 실패는 시연에 영향 없음 */
    }
  }

  function load() {
    if (!storage) return;
    try {
      const raw = storage.getItem(SESSION_KEY);
      if (!raw) return;
      const d = JSON.parse(raw);
      session = Object.assign(freshSession(), d.session || {});
      Object.keys(fsms).forEach((k) => {
        const saved = d.fsm && d.fsm[k];
        if (saved) fsms[k].restore(saved.state, saved.history);
      });
      WSP.events.add('APP', '세션 복원 (가입 ' + fsms.join.state + ' / 직접 ' + fsms.direct.state + ' / 자산 ' + fsms.asset.state + ')');
    } catch (e) {
      session = freshSession();
    }
  }

  function emitChange() {
    save();
    changeListeners.forEach((fn) => {
      try {
        fn();
      } catch (e) {
        console.error(e);
      }
    });
  }

  Object.keys(fsms).forEach((k) => fsms[k].subscribe(() => emitChange()));

  /** 같은 동작의 중복 실행(연타)을 막는다 */
  async function guard(name, fn) {
    if (busy.has(name)) return undefined;
    busy.add(name);
    try {
      return await fn();
    } finally {
      busy.delete(name);
    }
  }

  function dispatch(name, data, el, e) {
    const fn = WSP.actions[name];
    if (!fn) {
      console.warn('[WSP] 등록되지 않은 동작: ' + name);
      return;
    }
    Promise.resolve()
      .then(() => fn(data || {}, el, e))
      .catch((err) => {
        console.error(err);
        WSP.ui.toast('처리 중 문제가 발생했어요.', 'danger');
      });
  }

  function onInput(name, el, e) {
    const fn = WSP.actions['input:' + name];
    if (fn) fn(el, e);
  }

  function onCommit(name, el, e) {
    const fn = WSP.actions['commit:' + name];
    if (fn) fn(el, e);
  }

  /** 지정한 화면이 열려 있으면 다시 그린다 (생략 시 현재 화면) */
  function refresh(screenIds) {
    emitChange();
    const cur = WSP.ui.current();
    if (!cur) return;
    if (!screenIds || screenIds.indexOf(cur.id) !== -1) WSP.ui.rerender();
  }

  function resetDemo() {
    epoch += 1;
    WSP.ui.closeAllOverlays();
    WSP.store.reset('데모 초기화');
    Object.keys(fsms).forEach((k) => fsms[k].reset());
    // AI 경로와 직접 가입을 같은 초기 상태에서 번갈아 시연해 비교할 수 있도록 지난 기록은 남긴다
    const lastMetrics = session.lastMetrics;
    session = freshSession();
    session.lastMetrics = lastMetrics;
    if (WSP.aiAgent) WSP.aiAgent.clearTrace();
    WSP.events.clear();
    WSP.events.add('APP', '데모 초기화');
    emitChange();
    WSP.ui.navigate('home', {}, { resetHistory: true, animate: false });
  }

  WSP.registerActions({
    noop() {},
    back() {
      WSP.ui.back();
    },
    'go-home'() {
      WSP.ui.navigate('home', {}, { resetHistory: true, back: true });
    },
    'reload-screen'() {
      WSP.ui.rerender();
    },
    'toggle-balance'() {
      session.ui.hideBalance = !session.ui.hideBalance;
      refresh(['home']);
    },
    'close-disclaimer'() {
      session.ui.disclaimerClosed = true;
      refresh(['home']);
    },
    'go-products'() {
      WSP.ui.navigate('products');
    },
    'open-product'(d) {
      WSP.ui.navigate('product', { productId: d.product, from: d.from || null });
    },
    'go-menu'(d) {
      WSP.ui.navigate('menu', { highlight: d.highlight || null });
    },
    'demo-reset'() {
      resetDemo();
    },
  });

  function init() {
    load();
    WSP.ui.init();
    WSP.ui.navigate('home', {}, { resetHistory: true, animate: false });
    WSP.events.add('APP', '앱 시작');
  }

  WSP.app = {
    fsms: fsms,
    get session() {
      return session;
    },
    epoch: () => epoch,
    /** 진행 중인 비동기 흐름의 이후 결과를 무효로 만든다 (데모 초기화·자가 테스트) */
    invalidate: () => {
      epoch += 1;
    },
    /** 자가 테스트가 세션을 바꿔 끼우고 복원할 때만 쓴다 */
    replaceSession: (s) => {
      session = Object.assign(freshSession(), s || {});
      save();
    },
    guard: guard,
    save: save,
    dispatch: dispatch,
    onInput: onInput,
    onCommit: onCommit,
    refresh: refresh,
    resetDemo: resetDemo,
    onChange: (fn) => {
      changeListeners.add(fn);
      return () => changeListeners.delete(fn);
    },
  };

  window.addEventListener('DOMContentLoaded', init);
})();
