/**
 * ui.js
 * - 화면 ID 허용목록 기반 라우터 (history stack, 전환 애니메이션)
 * - 화면 등록(registerScreen): 화면 정의는 js/screens/*.js에 있다
 * - 하단 시트 / 확인 모달 / 토스트 / 업무 모달(기존 업무 화면 재사용)
 * - 대화 렌더링 공용 함수
 * 사용자 동작은 data-action 속성으로 app.js(동작 등록소)에 위임한다.
 */
(function () {
  'use strict';

  const WSP = window.WSP;
  const SC = WSP.scenario;
  const bank = WSP.mockBank;

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
  }

  const svg = (d, extra) =>
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"' +
    (extra || '') +
    '>' +
    d +
    '</svg>';

  const I = {
    back: svg('<path d="M15 5l-7 7 7 7"/>'),
    bell: svg('<path d="M6 16V11a6 6 0 1 1 12 0v5l1.5 2h-15L6 16z"/><path d="M10 20a2 2 0 0 0 4 0"/>'),
    menu: svg('<path d="M4 7h16M4 12h16M4 17h16"/>'),
    refresh: svg('<path d="M20 11a8 8 0 1 0-2.3 5.7"/><path d="M20 5v6h-6"/>'),
    send: svg('<path d="M4 12l16-8-6 16-2.5-6.5L4 12z"/>'),
    key: svg('<circle cx="8" cy="15" r="4"/><path d="M11 12l8-8M16 7l2 2M14 9l2 2"/>'),
    user: svg('<circle cx="12" cy="8" r="4"/><path d="M4 21c1-4 4-6 8-6s7 2 8 6"/>'),
    idcard: svg('<rect x="3" y="5" width="18" height="14" rx="2"/><circle cx="9" cy="12" r="2.2"/><path d="M14 10h4M14 14h4M6 16c.6-1.2 1.7-1.8 3-1.8s2.4.6 3 1.8"/>'),
    list: svg('<path d="M8 6h12M8 12h12M8 18h12"/><circle cx="4" cy="6" r="1"/><circle cx="4" cy="12" r="1"/><circle cx="4" cy="18" r="1"/>'),
    coin: svg('<circle cx="12" cy="12" r="8"/><path d="M9.5 9.5h4a1.5 1.5 0 0 1 0 3h-3a1.5 1.5 0 0 0 0 3h4M12 8v1.5M12 15v1.5"/>'),
    chart: svg('<path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/>'),
    home: svg('<path d="M4 11l8-7 8 7v9h-5v-6H9v6H4z"/>'),
    gift: svg('<rect x="4" y="9" width="16" height="11" rx="1"/><path d="M3 9h18v-3H3zM12 6v14M12 6c-2-3-5-3-5-1s3 1 5 1zm0 0c2-3 5-3 5-1s-3 1-5 1z"/>'),
    grid: svg('<rect x="4" y="4" width="6" height="6" rx="1"/><rect x="14" y="4" width="6" height="6" rx="1"/><rect x="4" y="14" width="6" height="6" rx="1"/><rect x="14" y="14" width="6" height="6" rx="1"/>'),
    product: svg('<path d="M4 8l8-4 8 4-8 4-8-4z"/><path d="M4 12l8 4 8-4M4 16l8 4 8-4"/>'),
    spark: svg('<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"/><path d="M19 16l.8 2.2L22 19l-2.2.8L19 22l-.8-2.2L16 19l2.2-.8z"/>'),
    check: svg('<path d="M5 12.5l4.5 4.5L19 7.5"/>', ' stroke-width="2.6"'),
    clock: svg('<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>'),
    alert: svg('<path d="M12 3l10 18H2z"/><path d="M12 10v5M12 18v.5"/>'),
    question: svg('<circle cx="12" cy="12" r="9"/><path d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.7.3-1 .9-1 1.7M12 17v.5"/>'),
    x: svg('<path d="M6 6l12 12M18 6L6 18"/>', ' stroke-width="2.4"'),
    lock: svg('<rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>'),
    shield: svg('<path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/><path d="M9 12l2 2 4-4"/>'),
    info: svg('<circle cx="12" cy="12" r="9"/><path d="M12 11v6M12 7.5v.5"/>'),
    chat: svg('<path d="M4 5h16v11H9l-5 4z"/><path d="M8 10h8M8 13h5"/>'),
    headset: svg('<path d="M4 14v-2a8 8 0 1 1 16 0v2"/><rect x="3" y="14" width="4" height="6" rx="1.5"/><rect x="17" y="14" width="4" height="6" rx="1.5"/><path d="M19 20c0 1-1.5 2-4 2h-2"/>'),
    phone: svg('<rect x="7" y="2.5" width="10" height="19" rx="2.5"/><path d="M11 18.5h2"/>'),
    chevron: svg('<path d="M9 6l6 6-6 6"/>'),
    eyeOff: svg('<path d="M3 3l18 18"/><path d="M10.6 5.1A10.6 10.6 0 0 1 12 5c6.5 0 10 7 10 7a17 17 0 0 1-3 3.9M6.6 6.6C3.8 8.4 2 12 2 12s3.5 7 10 7c1.8 0 3.3-.5 4.6-1.2"/>'),
    wallet: svg('<path d="M4 7h14a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2z"/><path d="M4 7l11-3v3"/><path d="M15 13.5h2"/>'),
    more: svg('<circle cx="12" cy="5" r="1.4" style="fill:currentColor;stroke:none"/><circle cx="12" cy="12" r="1.4" style="fill:currentColor;stroke:none"/><circle cx="12" cy="19" r="1.4" style="fill:currentColor;stroke:none"/>'),
    gear: svg('<circle cx="12" cy="12" r="3"/><path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M5.3 18.7l2.1-2.1M16.6 7.4l2.1-2.1"/>'),
    pie: svg('<path d="M12 3a9 9 0 1 0 9 9h-9z"/><path d="M15 3.5A9 9 0 0 1 20.5 9H15z"/>'),
    stock: svg('<path d="M3 17l5-5 4 3 8-8"/><path d="M15 7h5v5"/>'),
    plus: svg('<path d="M12 5v14M5 12h14"/>'),
    target: svg('<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1.5"/>'),
    doc: svg('<path d="M6 3h8l4 4v14H6z"/><path d="M14 3v4h4M9 12h6M9 16h6"/>'),
    route: svg('<circle cx="6" cy="18" r="2.5"/><circle cx="18" cy="6" r="2.5"/><path d="M8.5 18H15a3 3 0 0 0 0-6H9a3 3 0 0 1 0-6h6.5"/>'),
    homeFill:
      '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3.5 10.6L12 3.5l8.5 7.1V20a1 1 0 0 1-1 1H15v-6H9v6H4.5a1 1 0 0 1-1-1z" fill="currentColor"/></svg>',
    ai:
      '<svg viewBox="0 0 28 28" aria-hidden="true"><circle cx="13" cy="15" r="10" fill="none" stroke="currentColor" stroke-width="1.9"/><text x="13" y="18.6" text-anchor="middle" font-size="10" font-weight="800" fill="currentColor" font-family="Arial, sans-serif">AI</text><path d="M23 1.5l.9 2.4 2.4.9-2.4.9-.9 2.4-.9-2.4-2.4-.9 2.4-.9z" fill="#2488f3"/></svg>',
    robot:
      '<svg viewBox="0 0 40 40" aria-hidden="true"><rect x="9" y="13" width="22" height="17" rx="7" fill="#fff"/><circle cx="16" cy="21.5" r="2" fill="#2488f3"/><circle cx="24" cy="21.5" r="2" fill="#2488f3"/><path d="M20 13V9" stroke="#fff" stroke-width="2" stroke-linecap="round"/><circle cx="20" cy="8" r="2" fill="#fff"/></svg>',
  };

  /** 업무 아이콘 이름 → 아이콘 */
  const TASK_ICON = { idcard: I.idcard, phone: I.phone, wallet: I.wallet, key: I.key, user: I.user };

  /* ==================================================================
   * 공용 템플릿 조각
   * ================================================================== */
  function appbar(title, opts) {
    const o = opts || {};
    const left = o.noBack ? '<span></span>' : '<button class="icon-btn" data-action="back" aria-label="뒤로 가기">' + I.back + '</button>';
    return '<header class="appbar">' + left + '<div class="appbar__title">' + esc(title) + '</div>' + (o.right || '<span></span>') + '</header>';
  }

  function badge(text, tone) {
    return '<span class="badge' + (tone ? ' badge--' + tone : '') + '">' + esc(text) + '</span>';
  }

  function notice(html, tone, icon) {
    return '<div class="notice' + (tone ? ' notice--' + tone : '') + '">' + (icon || I.info) + '<div>' + html + '</div></div>';
  }

  function kvRows(rows) {
    return (
      '<div class="kv">' +
      rows.map((r) => '<div class="kv__row"><span class="kv__key">' + esc(r[0]) + '</span><span class="kv__val">' + r[1] + '</span></div>').join('') +
      '</div>'
    );
  }

  function queryErrorCard(title, error) {
    return (
      appbar(title) +
      '<div class="screen-body"><div class="result"><div class="result__icon result__icon--neutral">' +
      I.alert +
      '</div><h2 class="result__title">정보를 불러오지 못했어요</h2><p class="result__desc">' +
      esc(error ? error.message : '') +
      '<br>확인되지 않은 정보로 진행하지 않아요. 잠시 후 다시 시도해 주세요.</p></div></div>' +
      '<div class="screen-footer"><div class="btn-row"><button class="btn btn--ghost" data-action="go-home">홈으로</button><button class="btn btn--primary" data-action="reload-screen">다시 시도</button></div></div>'
    );
  }

  const COND_TONE = { MET: 'success', UNMET: 'danger', UNKNOWN: 'neutral', IN_PROGRESS: 'warning' };
  function condBadge(status) {
    return badge(WSP.ruleEngine.STATUS_LABEL[status] || status, COND_TONE[status]);
  }

  /* ---------- 대화 ---------- */
  function figures(list) {
    if (!list || !list.length) return '';
    return (
      '<div class="figs">' +
      list
        .map(
          (f) =>
            '<div class="fig' +
            (f.tone ? ' is-' + f.tone : '') +
            '"><span class="fig__label">' +
            esc(f.label) +
            '</span><strong class="fig__value">' +
            esc(f.value) +
            '</strong>' +
            (f.note ? '<span class="fig__note">' + esc(f.note) + '</span>' : '') +
            '</div>'
        )
        .join('') +
      '</div>'
    );
  }

  function renderMessage(m) {
    if (m.role === 'user') return '<div class="msg msg--user"><div class="msg__bubble">' + esc(m.text) + '</div></div>';
    if (m.role === 'system') return '<div class="msg-sys' + (m.tone ? ' is-' + m.tone : '') + '">' + (m.tone === 'warning' ? I.alert : I.info) + '<span>' + esc(m.text) + '</span></div>';
    return (
      '<div class="msg msg--bot"><div class="bot-label">' +
      I.spark.replace('<svg', '<svg width="13" height="13"') +
      'AI 도우미' +
      '</div><div class="msg__bubble' +
      (m.tone === 'warning' ? ' is-warning' : '') +
      '">' +
      esc(m.text).replace(/\n/g, '<br>') +
      '</div>' +
      figures(m.figures) +
      (m.why ? '<div class="msg__why">' + I.question.replace('<svg', '<svg width="13" height="13"') + esc(m.why) + '</div>' : '') +
      '</div>'
    );
  }

  function chatLog(messages, thinking) {
    return (
      (messages || []).map(renderMessage).join('') +
      (thinking ? '<div class="thinking" aria-label="AI가 생각하는 중"><span class="thinking__dots"><i></i><i></i><i></i></span>AI가 확인하고 있어요</div>' : '')
    );
  }

  /** 가장 최근 메시지의 첫 줄이 화면 위로 밀려나지 않는 만큼만 아래로 내린다 */
  function scrollToLatest(body) {
    if (!body) return;
    const bottom = body.scrollHeight - body.clientHeight;
    const msgs = body.querySelectorAll('.chat-log > .msg, .chat-log > .msg-sys');
    const last = msgs[msgs.length - 1];
    if (!last) {
      body.scrollTop = bottom;
      return;
    }
    const top = last.getBoundingClientRect().top - body.getBoundingClientRect().top + body.scrollTop - 12;
    body.scrollTop = Math.max(0, Math.min(bottom, top));
  }

  function chatInput(id, action, placeholder, disabled) {
    return (
      '<div class="chat-input"><div class="chat-input__field"><input id="' +
      id +
      '" data-enter="' +
      action +
      '" maxlength="120" placeholder="' +
      esc(placeholder) +
      '" aria-label="메시지 입력" autocomplete="off"' +
      (disabled ? ' disabled' : '') +
      ' /><button class="chat-input__send" data-action="' +
      action +
      '" aria-label="전송"' +
      (disabled ? ' disabled' : '') +
      '>' +
      I.send +
      '</button></div></div>'
    );
  }

  /* ==================================================================
   * 화면 등록 / 라우터
   * ================================================================== */
  const SCREEN_IDS = Object.freeze(['home', 'products', 'product', 'menu', 'join-consent', 'join', 'apply', 'apply-result', 'support', 'direct', 'asset-consent', 'asset', 'explore']);
  const SCREENS = {};

  function registerScreen(id, def) {
    if (SCREEN_IDS.indexOf(id) === -1) {
      console.warn('[WSP UI] 허용목록에 없는 화면 등록 거부: ' + id);
      return;
    }
    SCREENS[id] = def;
  }

  let viewport = null;
  let overlay = null;
  let current = null;
  let currentEl = null;
  let stack = [];
  let navToken = 0;
  let rerenderToken = 0;
  const navListeners = new Set();

  function emitNav() {
    navListeners.forEach((fn) => {
      try {
        fn(current);
      } catch (e) {
        console.error(e);
      }
    });
  }

  async function renderScreen(def, params) {
    try {
      return await def.render(params || {});
    } catch (e) {
      console.error('[WSP UI] 화면 렌더링 오류', e);
      return queryErrorCard(def.title, { message: '화면을 표시하는 중 문제가 발생했어요.' });
    }
  }

  async function navigate(id, params, opts) {
    const o = opts || {};
    const def = SCREENS[id];
    if (!def || SCREEN_IDS.indexOf(id) === -1) {
      console.warn('[WSP UI] 허용되지 않은 화면 ID: ' + id);
      return false;
    }
    const token = ++navToken;
    const html = await renderScreen(def, params);
    if (token !== navToken) return false;

    let back = !!o.back;
    if (o.resetHistory) stack = [];
    else if (o.backTo) {
      let idx = -1;
      for (let i = stack.length - 1; i >= 0; i--) {
        if (stack[i].id === id) {
          idx = i;
          break;
        }
      }
      if (idx >= 0) stack = stack.slice(0, idx);
      back = true;
    } else if (!o.replace && current) stack.push({ id: current.id, params: current.params });
    if (stack.length > 20) stack = stack.slice(-20);

    const el = document.createElement('section');
    el.className = 'screen' + (def.white ? ' is-white' : '');
    el.dataset.screen = id;
    el.innerHTML = html;
    const old = currentEl;
    currentEl = el;
    current = { id: id, params: params || {} };
    viewport.appendChild(el);

    if (old) {
      if (o.animate === false) old.remove();
      else {
        el.classList.add(back ? 'enter-back' : 'enter');
        old.classList.add(back ? 'leave-back' : 'leave');
        old.style.pointerEvents = 'none';
        setTimeout(() => old.remove(), 360);
      }
    } else el.classList.add('enter-fade');

    if (def.mount) def.mount(el, current.params, { first: true });
    emitNav();
    return true;
  }

  /** 현재 화면을 같은 자리에서 다시 그린다 (스크롤·입력 중인 값 유지) */
  async function rerender(paramsPatch) {
    if (!current) return;
    const id = current.id;
    const def = SCREENS[id];
    const params = Object.assign({}, current.params, paramsPatch || {});
    const nav = navToken;
    const token = ++rerenderToken;
    const html = await renderScreen(def, params);
    if (nav !== navToken || token !== rerenderToken || !current || current.id !== id) return;
    const body = currentEl.querySelector('.screen-body');
    const scroll = body ? body.scrollTop : 0;
    const active = document.activeElement && currentEl.contains(document.activeElement) && document.activeElement.id ? document.activeElement : null;
    const keep = {};
    currentEl.querySelectorAll('input[id]').forEach((inp) => (keep[inp.id] = inp.value));
    currentEl.innerHTML = html;
    current.params = params;
    Object.keys(keep).forEach((k) => {
      const inp = currentEl.querySelector('#' + k);
      if (inp && !inp.hasAttribute('data-reset')) inp.value = keep[k];
    });
    const nb = currentEl.querySelector('.screen-body');
    if (nb) nb.scrollTop = scroll;
    if (active) {
      const again = currentEl.querySelector('#' + active.id);
      if (again && !again.disabled) again.focus();
    }
    if (def.mount) def.mount(currentEl, params, { first: false });
    emitNav();
  }

  function back() {
    if (!current) return;
    const def = SCREENS[current.id];
    if (def.onBack && def.onBack(current.params) === true) return;
    goBack();
  }

  function goBack() {
    const prev = stack.pop();
    if (!prev) {
      navigate('home', {}, { resetHistory: true, back: true });
      return;
    }
    navigate(prev.id, prev.params, { replace: true, back: true });
  }

  /* ==================================================================
   * 오버레이: 시트 / 모달 / 토스트
   * ================================================================== */
  let sheetEls = null;

  function openSheet(html, opts) {
    closeSheet(true);
    const bd = document.createElement('div');
    bd.className = 'sheet-backdrop';
    const sh = document.createElement('div');
    sh.className = 'sheet';
    sh.setAttribute('role', 'dialog');
    sh.innerHTML = '<div class="sheet__handle"></div>' + html;
    overlay.appendChild(bd);
    overlay.appendChild(sh);
    requestAnimationFrame(() =>
      requestAnimationFrame(() => {
        bd.classList.add('is-open');
        sh.classList.add('is-open');
      })
    );
    const o = opts || {};
    sheetEls = { bd: bd, sh: sh, dismissible: !!o.dismissible, onClose: o.onClose || null };
    const own = sheetEls;
    bd.addEventListener('click', () => {
      if (sheetEls === own && own.dismissible) closeSheet();
    });
    return sh;
  }

  function closeSheet(immediate) {
    if (!sheetEls) return;
    const els = sheetEls;
    sheetEls = null;
    if (els.onClose) els.onClose();
    if (immediate) {
      els.bd.remove();
      els.sh.remove();
      return;
    }
    els.bd.classList.remove('is-open');
    els.sh.classList.remove('is-open');
    setTimeout(() => {
      els.bd.remove();
      els.sh.remove();
    }, 340);
  }

  function getSheet() {
    return sheetEls ? sheetEls.sh : null;
  }

  let modalResolve = null;

  function confirm(opts) {
    closeModal(false);
    const o = opts || {};
    return new Promise((resolve) => {
      const bd = document.createElement('div');
      bd.className = 'modal-backdrop';
      bd.innerHTML =
        '<div class="modal" role="dialog" aria-modal="true"><h3 class="modal__title">' +
        esc(o.title) +
        '</h3><div class="modal__body">' +
        (o.bodyHtml || '') +
        '</div><div class="btn-row"><button class="btn btn--ghost" data-modal="cancel">' +
        esc(o.cancelText || '취소') +
        '</button><button class="btn ' +
        (o.danger ? 'btn--danger' : 'btn--primary') +
        '" data-modal="ok">' +
        esc(o.confirmText || '확인') +
        '</button></div></div>';
      overlay.appendChild(bd);
      requestAnimationFrame(() => requestAnimationFrame(() => bd.classList.add('is-open')));
      modalResolve = (v) => {
        bd.classList.remove('is-open');
        setTimeout(() => bd.remove(), 260);
        modalResolve = null;
        resolve(v);
      };
      bd.addEventListener('click', (e) => {
        const b = e.target.closest('[data-modal]');
        if (b) modalResolve && modalResolve(b.dataset.modal === 'ok');
        else if (e.target === bd) modalResolve && modalResolve(false);
      });
    });
  }

  function closeModal(value) {
    if (modalResolve) modalResolve(value);
  }

  let toastWrap = null;

  function toast(message, type, ms) {
    if (!toastWrap || !toastWrap.isConnected) {
      toastWrap = document.createElement('div');
      toastWrap.className = 'toast-wrap';
      overlay.appendChild(toastWrap);
    }
    const t = document.createElement('div');
    t.className = 'toast' + (type ? ' toast--' + type : '');
    t.textContent = message;
    toastWrap.appendChild(t);
    while (toastWrap.children.length > 2) toastWrap.firstChild.remove();
    setTimeout(() => {
      t.classList.add('is-leaving');
      setTimeout(() => t.remove(), 220);
    }, ms || 2600);
  }

  /* ==================================================================
   * 업무 모달: 기존 업무 화면을 그대로 열고, 닫힐 때 호출자에게 알린다.
   * 업무 화면은 결과를 보여 줄 뿐이며, 완료 판정은 호출자가 은행 재조회로 한다.
   * ================================================================== */
  let tm = null;

  const TM_STATUS = {
    COMPLETED: ['success', '업무 화면에서 완료됐어요'],
    IN_PROGRESS: ['warning', '은행에서 처리 중이에요'],
    PARTIAL: ['warning', '일부 단계만 저장됐어요'],
    ERROR: ['danger', '처리 중 오류가 발생했어요'],
    REJECTED: ['danger', '지금은 진행할 수 없어요'],
  };

  function taskBodyHtml(state) {
    const t = SC.getTask(state.taskId);
    const running = state.status === 'RUNNING';
    const finished = !!TM_STATUS[state.status];
    let html = '<div class="tm-hero"><span class="tm-hero__icon">' + (TASK_ICON[t.icon] || I.doc) + '</span><div><p>' + esc(t.desc) + '</p><span class="tm-hero__meta">' + I.clock + '약 ' + t.minutes + '분</span></div></div>';
    if (t.prep.length) html += '<div class="tm-sec"><h4>준비물</h4><ul class="tm-prep">' + t.prep.map((p) => '<li>' + esc(p) + '</li>').join('') + '</ul></div>';
    if (t.fields) {
      html +=
        '<div class="tm-sec"><h4>입력</h4>' +
        t.fields
          .map(
            (f) =>
              '<div class="tm-field"><span class="tm-field__label">' +
              esc(f.label) +
              '</span><div class="chip-row">' +
              f.options
                .map(
                  (o) =>
                    '<button class="chip' +
                    (state.input[f.id] === o ? ' is-on' : '') +
                    '" data-action="tm-field" data-field="' +
                    f.id +
                    '" data-value="' +
                    esc(o) +
                    '"' +
                    (running || finished ? ' disabled' : '') +
                    '>' +
                    esc(o) +
                    '</button>'
                )
                .join('') +
              '</div></div>'
          )
          .join('') +
        '</div>';
    }
    html +=
      '<div class="tm-sec"><h4>진행 단계</h4><ol class="tm-steps">' +
      t.steps
        .map((s, i) => {
          const done = finished ? state.status === 'COMPLETED' || state.status === 'IN_PROGRESS' || (state.status === 'PARTIAL' && i < t.steps.length - 1) : running && i < state.progress;
          const cur = running && i === state.progress;
          return '<li class="' + (done ? 'is-done' : cur ? 'is-current' : '') + '"><span class="tm-steps__dot">' + (done ? I.check : i + 1) + '</span>' + esc(s) + '</li>';
        })
        .join('') +
      '</ol></div>';
    if (finished) {
      const st = TM_STATUS[state.status];
      html += '<div class="tm-result tm-result--' + st[0] + '"><strong>' + esc(st[1]) + '</strong><p>' + esc(state.message || '') + '</p></div>';
    }
    return html;
  }

  function taskFootHtml(state) {
    const finished = !!TM_STATUS[state.status];
    if (state.status === 'RUNNING') return '<button class="btn btn--primary btn--block is-loading" disabled>처리 중</button>';
    if (finished)
      return '<button class="btn btn--primary btn--block" data-action="tm-close">' + (state.mode === 'ai' ? '닫고 은행 기록 확인' : '닫기') + '</button>';
    return '<div class="btn-row"><button class="btn btn--ghost" data-action="tm-close">닫기</button><button class="btn btn--primary" data-action="tm-run">진행하기</button></div>';
  }

  function paintTask() {
    if (!tm) return;
    const t = SC.getTask(tm.state.taskId);
    tm.el.querySelector('.tm__title').textContent = t.label;
    tm.el.querySelector('.tm__body').innerHTML = taskBodyHtml(tm.state);
    tm.el.querySelector('.tm__foot').innerHTML = taskFootHtml(tm.state);
  }

  function openTaskModal(taskId, sessionId, opts) {
    closeTaskModal(true);
    const o = opts || {};
    const t = SC.getTask(taskId);
    const bd = document.createElement('div');
    bd.className = 'tm-backdrop';
    bd.innerHTML =
      '<div class="tm" role="dialog" aria-modal="true"><header class="tm__head"><div><span class="tm__menu">' +
      esc(t.menu) +
      '</span><h3 class="tm__title"></h3></div><button class="icon-btn" data-action="tm-close" aria-label="닫기">' +
      I.x +
      '</button></header><div class="tm__body"></div><footer class="tm__foot"></footer></div>';
    overlay.appendChild(bd);
    tm = { el: bd, onClose: o.onClose || null, state: { taskId: taskId, sessionId: sessionId, mode: o.mode || 'menu', status: 'OPEN', progress: 0, message: '', input: {} } };
    paintTask();
    requestAnimationFrame(() => requestAnimationFrame(() => bd.classList.add('is-open')));
  }

  function closeTaskModal(silent) {
    if (!tm) return;
    const cur = tm;
    tm = null;
    cur.el.classList.remove('is-open');
    setTimeout(() => cur.el.remove(), silent ? 0 : 280);
    const status = cur.state.status === 'RUNNING' ? 'OPEN' : cur.state.status;
    if (!silent && cur.onClose) cur.onClose({ status: status, taskId: cur.state.taskId, sessionId: cur.state.sessionId });
  }

  async function runTaskInModal() {
    if (!tm || tm.state.status !== 'OPEN') return;
    const own = tm;
    const t = SC.getTask(own.state.taskId);
    if (t.fields) {
      const miss = t.fields.find((f) => !own.state.input[f.id]);
      if (miss) {
        toast(WSP.utils.josa(miss.label, '을') + ' 선택해 주세요.', 'warning');
        return;
      }
    }
    own.state.status = 'RUNNING';
    own.state.progress = 0;
    paintTask();
    const timer = setInterval(() => {
      if (tm !== own) return clearInterval(timer);
      if (own.state.progress < t.steps.length - 1) {
        own.state.progress += 1;
        paintTask();
      }
    }, Math.max(120, 260 * (bank.getLatencyScale() || 0.5)));
    const r = await bank.runTask(own.state.sessionId, own.state.input);
    clearInterval(timer);
    if (tm !== own) return;
    if (!r.ok) {
      own.state.status = 'REJECTED';
      own.state.message = r.error.message;
    } else {
      own.state.status = r.data.status === 'COMPLETED' ? 'COMPLETED' : r.data.status;
      own.state.message = r.data.message;
    }
    paintTask();
  }

  WSP.registerActions({
    'tm-run'() {
      return runTaskInModal();
    },
    'tm-close'() {
      if (tm && tm.state.status === 'RUNNING') return;
      closeTaskModal(false);
    },
    'tm-field'(d) {
      if (!tm || tm.state.status !== 'OPEN') return;
      tm.state.input[d.field] = d.value;
      paintTask();
    },
  });

  function closeAllOverlays() {
    closeSheet(true);
    closeModal(false);
    closeTaskModal(true);
    overlay.querySelectorAll('.modal-backdrop').forEach((n) => n.remove());
  }

  /* ==================================================================
   * 초기화 / 이벤트 위임
   * ================================================================== */
  function init() {
    viewport = document.getElementById('viewport');
    overlay = document.getElementById('overlay-root');

    function onClick(e) {
      const t = e.target.closest('[data-action]');
      if (!t) return;
      if (t.disabled || t.getAttribute('aria-disabled') === 'true') return;
      e.preventDefault();
      WSP.app.dispatch(t.dataset.action, t.dataset, t, e);
    }
    viewport.addEventListener('click', onClick);
    overlay.addEventListener('click', onClick);

    viewport.addEventListener('input', (e) => {
      const t = e.target.closest('[data-input]');
      if (t) WSP.app.onInput(t.dataset.input, t, e);
    });
    viewport.addEventListener(
      'blur',
      (e) => {
        const t = e.target.closest && e.target.closest('[data-input]');
        if (t) WSP.app.onCommit(t.dataset.input, t, e);
      },
      true
    );
    const onEnter = (e) => {
      if (e.key !== 'Enter' || e.isComposing) return;
      const t = e.target.closest('[data-enter]');
      if (t) {
        e.preventDefault();
        WSP.app.dispatch(t.dataset.enter, t.dataset, t, e);
      }
    };
    viewport.addEventListener('keydown', onEnter);
    overlay.addEventListener('keydown', onEnter);
  }

  function setLoading(el, loading) {
    if (!el) return;
    el.classList.toggle('is-loading', !!loading);
    el.disabled = !!loading;
  }

  WSP.ui = {
    SCREEN_IDS: SCREEN_IDS,
    I: I,
    TASK_ICON: TASK_ICON,
    esc: esc,
    appbar: appbar,
    badge: badge,
    notice: notice,
    kvRows: kvRows,
    condBadge: condBadge,
    queryErrorCard: queryErrorCard,
    chatLog: chatLog,
    scrollToLatest: scrollToLatest,
    chatInput: chatInput,
    registerScreen: registerScreen,
    init: init,
    navigate: navigate,
    rerender: rerender,
    back: back,
    goBack: goBack,
    current: () => current,
    currentEl: () => currentEl,
    onNavigate: (fn) => {
      navListeners.add(fn);
      return () => navListeners.delete(fn);
    },
    openSheet: openSheet,
    closeSheet: closeSheet,
    getSheet: getSheet,
    confirm: confirm,
    toast: toast,
    openTaskModal: openTaskModal,
    isTaskModalOpen: () => !!tm,
    closeAllOverlays: closeAllOverlays,
    setLoading: setLoading,
  };
})();
