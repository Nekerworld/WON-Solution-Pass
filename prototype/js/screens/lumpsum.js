/**
 * screens/lumpsum.js
 * 목돈 불리기 상담 화면. 선택지 탭과 클릭 타이핑을 같은 대화에서 쓴다.
 */
(function () {
  'use strict';

  const WSP = window.WSP;
  const UI = WSP.ui;
  const esc = UI.esc;
  const app = () => WSP.app;
  const lf = () => app().fsms.lumpsum;

  function rich(text) {
    return WSP.lumpsumFlow.formatRich(text || '');
  }

  /** 소비 막대와 패턴 태그는 소비 분석 화면(spend.js)과 같은 모양을 쓴다 */
  function stack(list, fresh, insight) {
    return WSP.spendView.stack(list, { fresh: fresh, insight: insight });
  }

  function steps(list, fresh) {
    if (!list || !list.length) return '';
    return (
      '<ol class="an-steps' +
      (fresh ? ' is-new' : '') +
      '">' +
      list
        .map((label, i) => '<li class="an-step" style="--i:' + i + '"><span class="an-step__mark"></span>' + esc(label) + '</li>')
        .join('') +
      '</ol>'
    );
  }

  const FACE =
    '<svg viewBox="0 0 32 32" aria-hidden="true"><rect x="5" y="9" width="22" height="17" rx="8" fill="#e8f1fe"/><rect x="5" y="9" width="22" height="17" rx="8" fill="none" stroke="#2488f3" stroke-width="1.6"/><circle cx="12.5" cy="17.5" r="1.8" fill="#2488f3"/><circle cx="19.5" cy="17.5" r="1.8" fill="#2488f3"/></svg>';

  function message(m) {
    if (m.role === 'user') return '<div class="msg msg--user"><div class="msg__say">"' + esc(m.text) + '"</div></div>';
    return botMessage(m);
  }

  /** 블록 하나. 처음 그려지는 블록만 페이드 인 표시를 단다 */
  function block(m, b, i, live) {
    const fresh = !b.seen;
    b.seen = true;
    const cls = fresh ? ' is-new' : '';
    if (b.t === 'text') {
      const partial = live && m.cur === i;
      const text = partial ? m.curText : b.text;
      return '<div class="msg__text blk' + cls + '" data-bi="' + i + '">' + rich(text) + (partial ? '<i class="stream-caret"></i>' : '') + '</div>';
    }
    if (b.t === 'steps') return '<div class="blk' + cls + '" data-bi="' + i + '">' + steps(b.items, fresh) + '</div>';
    if (b.t === 'details') {
      return (
        '<div class="blk an-more' +
        (m.open ? ' is-open' : '') +
        cls +
        '" data-bi="' +
        i +
        '"><button type="button" class="an-more__head" data-action="lumpsum-toggle" data-id="' +
        esc(m.id) +
        '" aria-expanded="' +
        (m.open ? 'true' : 'false') +
        '">' +
        esc(b.label) +
        '<i class="an-more__chev" aria-hidden="true"></i></button>' +
        (m.open ? stack(b.categories, !b.stackSeen && ((b.stackSeen = true), true), b.insight) : '') +
        '</div>'
      );
    }
    if (b.t === 'link') return '<div class="blk blk--link' + cls + '" data-bi="' + i + '"><button type="button" class="btn btn--secondary btn--block" data-action="' + esc(b.action) + '">' + esc(b.label) + '</button></div>';
    if (b.t === 'tags') return '<div class="blk blk--tags' + cls + '" data-bi="' + i + '">' + WSP.spendView.tags(b.items) + '</div>';
    if (b.t === 'figures') {
      const n = (b.figures || []).length;
      return '<div class="blk blk--figs' + (n === 2 ? ' blk--cols' : '') + cls + '" data-bi="' + i + '">' + UI.figures(b.figures) + '</div>';
    }
    return '';
  }

  function botMessage(m) {
    if (!m.blocks) m = Object.assign({}, m, { blocks: [{ t: 'text', text: m.text || '', seen: true }], shown: 1 });
    const live = !!m.streaming;
    const shown = m.shown || 0;
    let inner = '';
    for (let i = 0; i < m.blocks.length; i++) {
      const b = m.blocks[i];
      if (i < shown || (live && m.cur === i)) inner += block(m, b, i, live);
    }
    const thought = !live && m.thoughtMs ? '<p class="thought-label">' + esc(String(m.thoughtMs)) + '초 동안 생각했어요</p>' : '';
    return (
      '<div class="msg msg--bot" data-mid="' +
      esc(m.id) +
      '"><span class="msg__avatar" aria-hidden="true">' +
      FACE +
      '</span><div class="msg__card">' +
      inner +
      thought +
      '</div></div>'
    );
  }

  function choices(list) {
    if (!list || !list.length) return '';
    return (
      '<div class="chat-suggest">' +
      list
        .map((c) => '<button type="button" class="chip" data-action="lumpsum-choice" data-id="' + esc(c.id) + '">' + esc(c.text) + '</button>')
        .join('') +
      '</div>'
    );
  }

  /** 입력창 높이를 글자 수에 맞춘다. 긴 문장은 세로로 늘어나고, 6줄을 넘으면 안에서 스크롤한다 */
  function autoGrow(el) {
    if (!el || el.tagName !== 'TEXTAREA') return;
    const body = document.getElementById('lumpsum-body');
    const near = body ? body.scrollHeight - body.scrollTop - body.clientHeight < 80 : false;
    const max = 22 * 6 + 22;
    el.style.height = 'auto';
    const full = el.scrollHeight;
    el.style.height = Math.min(full, max) + 'px';
    el.style.overflowY = full > max ? 'auto' : 'hidden';
    if (full > max) el.scrollTop = el.scrollHeight;
    if (near && body) body.scrollTop = body.scrollHeight;
  }
  UI.autoGrow = autoGrow;

  function composer(s) {
    const streaming = s.chat.some((m) => m.streaming) || s.thinking;
    const hot = s.typing || (s.draft && s.draft.length);
    const label = streaming ? '응답 중지' : '전송';
    return (
      '<div class="chat-input' +
      (s.typing ? ' is-typing' : '') +
      (hot ? ' is-hot' : '') +
      '"><div class="chat-input__field"><textarea id="lumpsum-input" data-reset="1" rows="1" maxlength="160" placeholder="메시지를 입력하세요" aria-label="메시지 입력" autocomplete="off" readonly>' +
      esc(s.draft || '') +
      '</textarea>' +
      (s.typing ? '<i class="type-caret"></i>' : '') +
      '<button class="chat-input__send' +
      (streaming ? ' is-stop' : '') +
      '" data-action="lumpsum-send" aria-label="' +
      label +
      '">' +
      (streaming ? '<i class="stop-sq"></i>' : UI.I.send) +
      '</button></div></div>'
    );
  }

  UI.registerScreen('lumpsum', {
    title: 'AI 자산관리 상담',
    white: true,
    render() {
      const s = app().session.lumpsum;
      const st = lf().state;
      if (!s || st === 'IDLE') {
        return UI.appbar('AI 자산관리 상담') + '<div class="screen-body"><p class="lead">진행 중인 상담이 없어요.</p><button class="btn btn--primary" data-action="lumpsum-new">상담 시작</button></div>';
      }
      const ended = st === 'CLOSED' || st === 'TO_JOIN';
      const viewSpend = ended && !!app().session.spendGoal && !!(s.advice && s.advice.decisionId === 'SPEND_CHECK');
      const thinking = s.thinking ? '<div class="thinking" aria-label="AI가 생각하는 중"><span class="thinking__dots"><i></i><i></i><i></i></span>' + esc(s.thinkLabel || '확인하고 있어요') + '</div>' : '';
      const log = s.chat.map((m) => (m.role === 'user' ? message(m) : botMessage(m))).join('');
      return (
        UI.chatHeader({ action: 'lumpsum-end', label: '상담 종료' }) +
        '<div class="screen-body chat-body" id="lumpsum-body">' +
        UI.chatIntro('AI 자산관리 상담', s.chat[0] && s.chat[0].at) +
        '<div class="chat-log">' +
        log +
        thinking +
        '</div>' +
        (ended ? '<div class="act">' + (viewSpend ? '<button class="btn btn--secondary btn--block" data-action="spend-open">소비 분석에서 보기</button>' : '') + '<button class="btn btn--primary btn--block" data-action="lumpsum-new">새 상담 시작</button></div>' : choices(s.prompt && s.prompt.choices)) +
        '</div>' +
        (ended ? '' : composer(s))
      );
    },
    mount(el, _params, ctx) {
      const body = el.querySelector('#lumpsum-body');
      UI.scrollToLatest(body);
      autoGrow(el.querySelector('#lumpsum-input'));
      if (ctx && ctx.first) WSP.lumpsumFlow.resume();
    },
  });
})();
