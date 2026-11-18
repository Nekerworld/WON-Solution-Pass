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

  function bars(list) {
    if (!list || !list.length) return '';
    const man = WSP.utils.formatMan;
    return (
      '<div class="spend-bars">' +
      list
        .map((c) => {
          const pct = Math.round(c.ratio * 100);
          return (
            '<div class="spend-bar"><span class="spend-bar__name">' +
            esc(c.label) +
            '</span><span class="spend-bar__track"><i style="width:' +
            pct +
            '%"></i></span><strong>' +
            esc(man(c.amount)) +
            ' · ' +
            pct +
            '%</strong></div>'
          );
        })
        .join('') +
      '</div>'
    );
  }

  function steps(list) {
    if (!list || !list.length) return '';
    return (
      '<ol class="an-steps">' +
      list
        .map((label, i) => '<li class="an-step" style="animation-delay:' + i * 0.55 + 's"><span class="an-step__mark"></span>' + esc(label) + '</li>')
        .join('') +
      '</ol>'
    );
  }

  function tools(m) {
    if (m.role !== 'ai' || m.streaming) return '';
    return (
      '<div class="msg-tools"><button type="button" data-action="lumpsum-copy" data-id="' +
      esc(m.id) +
      '" aria-label="복사">복사</button><button type="button" class="msg-tools__like' +
      (m.liked ? ' is-on' : '') +
      '" data-action="lumpsum-like" data-id="' +
      esc(m.id) +
      '" aria-label="좋아요">좋아요</button><button type="button" data-action="lumpsum-again" data-id="' +
      esc(m.id) +
      '" aria-label="다시 생성">다시 생성</button></div>'
    );
  }

  const FACE =
    '<svg viewBox="0 0 32 32" aria-hidden="true"><rect x="5" y="9" width="22" height="17" rx="8" fill="#e8f1fe"/><rect x="5" y="9" width="22" height="17" rx="8" fill="none" stroke="#2488f3" stroke-width="1.6"/><circle cx="12.5" cy="17.5" r="1.8" fill="#2488f3"/><circle cx="19.5" cy="17.5" r="1.8" fill="#2488f3"/></svg>';

  function message(m) {
    if (m.role === 'user') return '<div class="msg msg--user"><div class="msg__say">"' + esc(m.text) + '"</div></div>';
    return botMessage(m);
  }

  function botMessage(m) {
    const cursor = m.streaming ? '<i class="stream-caret"></i>' : '';
    const thought = !m.streaming && m.thoughtMs ? '<p class="thought-label">' + esc(String(m.thoughtMs)) + '초 동안 생각했어요</p>' : '';
    return (
      '<div class="msg msg--bot" data-mid="' +
      esc(m.id) +
      '"><span class="msg__avatar" aria-hidden="true">' +
      FACE +
      '</span><div class="msg__card"><div class="msg__text">' +
      rich(m.text) +
      cursor +
      '</div>' +
      steps(m.steps) +
      bars(m.categories) +
      UI.figures(m.figures) +
      UI.figures(m.figures2) +
      (m.decisionLine ? '<p class="decision-line">' + esc(m.decisionLine) + '</p>' : '') +
      thought +
      tools(m) +
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

  function composer(s) {
    const streaming = s.chat.some((m) => m.streaming) || s.thinking;
    const hot = s.typing || (s.draft && s.draft.length);
    const label = streaming ? '응답 중지' : '전송';
    return (
      '<div class="chat-input' +
      (s.typing ? ' is-typing' : '') +
      (hot ? ' is-hot' : '') +
      '"><div class="chat-input__field"><input id="lumpsum-input" data-reset="1" maxlength="160" placeholder="메시지를 입력하세요" aria-label="메시지 입력" autocomplete="off" readonly value="' +
      esc(s.draft || '') +
      '" />' +
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
    title: '목돈 불리기',
    white: true,
    render() {
      const s = app().session.lumpsum;
      const st = lf().state;
      if (!s || st === 'IDLE') {
        return UI.appbar('목돈 불리기') + '<div class="screen-body"><p class="lead">진행 중인 상담이 없어요.</p><button class="btn btn--primary" data-action="lumpsum-new">상담 시작</button></div>';
      }
      const ended = st === 'CLOSED' || st === 'TO_JOIN';
      const thinking = s.thinking ? '<div class="thinking" aria-label="AI가 생각하는 중"><span class="thinking__dots"><i></i><i></i><i></i></span>' + esc(s.thinkLabel || '확인하고 있어요') + '</div>' : '';
      const log = s.chat.map((m) => (m.role === 'user' ? message(m) : botMessage(m))).join('');
      return (
        UI.chatHeader({ action: 'lumpsum-end', label: '상담 종료' }) +
        '<div class="screen-body chat-body" id="lumpsum-body">' +
        UI.chatIntro('목돈 불리기', s.chat[0] && s.chat[0].at) +
        '<div class="chat-log">' +
        log +
        thinking +
        '</div>' +
        (ended ? '<div class="act"><button class="btn btn--primary btn--block" data-action="lumpsum-new">새 상담 시작</button></div>' : choices(s.prompt && s.prompt.choices)) +
        '</div>' +
        (ended ? '' : composer(s))
      );
    },
    mount(el, _params, ctx) {
      const body = el.querySelector('#lumpsum-body');
      UI.scrollToLatest(body);
      if (ctx && ctx.first) WSP.lumpsumFlow.resume();
    },
  });
})();
