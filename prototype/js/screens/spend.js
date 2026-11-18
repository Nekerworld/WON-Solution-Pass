/**
 * screens/spend.js
 * 소비 분석 화면과, 챗봇이 같은 모양으로 쓰는 소비 막대·패턴 태그.
 * 숫자는 lumpsumAdvisor의 spendInsight 결과만 쓴다.
 */
(function () {
  'use strict';

  const WSP = window.WSP;
  const UI = WSP.ui;
  const esc = UI.esc;
  const man = WSP.utils.formatMan;
  const won = WSP.utils.formatWon;
  const LA = WSP.lumpsumAdvisor;
  const app = () => WSP.app;

  /** 토스 지출 분석처럼 하나의 막대에 항목을 색으로 나눠 담고, 아래에 범례로 금액·비율을 읽어 준다 */
  const SPEND_COLORS = { 식비: '#2488f3', '주거·관리': '#1f9d7a', 교통: '#f2a33a', 쇼핑: '#7b61ff', '문화·여가': '#ec5f8f', 기타: '#b4bcc8' };

  function changeText(pct) {
    return (pct > 0 ? '+' : pct < 0 ? '-' : '') + Math.abs(pct) + '%';
  }

  function changeBadge(pct) {
    const tone = pct > 0 ? ' is-up' : pct < 0 ? ' is-down' : '';
    return '<em class="spend-chg' + tone + '">' + esc(changeText(pct)) + '</em>';
  }

  /**
   * opts.fresh: 처음 그려질 때 막대가 차오른다. opts.insight: 출처 라벨과 지난달 대비 증감을 함께 보여 준다.
   */
  function stack(list, opts) {
    if (!list || !list.length) return '';
    const o = opts || {};
    const ins = o.insight || null;
    const color = (c) => SPEND_COLORS[c.label] || '#b4bcc8';
    const change = (c) => {
      const r = ins && ins.rows.filter((x) => x.label === c.label)[0];
      return r ? changeBadge(r.changePct) : '';
    };
    return (
      '<div class="spend-stack' +
      (o.fresh ? ' is-new' : '') +
      (ins ? ' has-chg' : '') +
      '">' +
      (ins ? '<p class="spend-source">' + esc(ins.source) + '</p>' : '') +
      '<div class="spend-stack__bar" role="img" aria-label="소비 항목별 비율">' +
      list.map((c) => '<i style="flex:' + c.ratio + ';background:' + color(c) + '"></i>').join('') +
      '</div><ul class="spend-legend">' +
      list
        .map(
          (c) =>
            '<li><i class="dot" style="background:' +
            color(c) +
            '"></i><span>' +
            esc(c.label) +
            '</span><strong>' +
            esc(won(c.amount)) +
            ' · ' +
            Math.round(c.ratio * 100) +
            '%</strong>' +
            change(c) +
            '</li>'
        )
        .join('') +
      '</ul></div>'
    );
  }

  function tags(items) {
    if (!items || !items.length) return '';
    return '<div class="pat-tags">' + items.map((t) => '<span class="pat-tag">' + esc(t.text) + '</span>').join('') + '</div>';
  }

  /** 지금 페르소나의 월 지출로 소비 분석을 만든다 */
  function current() {
    const s = app().session.lumpsum;
    const items = WSP.store.getState().finance.items;
    const income = s ? s.snap.income : items.monthlyIncome && items.monthlyIncome.value ? items.monthlyIncome.value : 0;
    const expense = s ? s.snap.expense : items.monthlyExpense && items.monthlyExpense.value ? items.monthlyExpense.value : 0;
    const a = LA.advise({ income: income, expense: expense, debt: 0, goalAmount: 0, goalMonths: 1 });
    return { expense: expense, categories: a.categories, insight: LA.spendInsight(a) };
  }

  function compareList(ins) {
    const rows = ins.rows
      .slice()
      .sort((x, y) => y.changePct - x.changePct)
      .map(
        (r) =>
          '<li><span>' +
          esc(r.label) +
          '</span><span class="cmp__prev">' +
          esc(won(r.prev)) +
          '</span><i class="cmp__arrow" aria-hidden="true">→</i><strong>' +
          esc(won(r.amount)) +
          '</strong>' +
          changeBadge(r.changePct) +
          '</li>'
      )
      .join('');
    return '<ul class="cmp">' + rows + '</ul>';
  }

  function goalCard() {
    const g = app().session.spendGoal;
    if (!g) {
      return (
        '<div class="card spend-goal"><h3 class="card__title">줄이기 목표</h3><p class="spend-goal__empty">아직 설정한 목표가 없어요.</p>' +
        '<p class="spend-goal__hint">AI 자산관리 상담에서 지출 점검을 받으면 줄이기 계획을 저장할 수 있어요.</p></div>'
      );
    }
    const rows = (g.items || []).map((it) => '<li><span>' + esc(it.label) + '</span><strong>월 ' + esc(man(it.saved)) + '</strong></li>').join('');
    return (
      '<div class="card spend-goal is-set"><h3 class="card__title">줄이기 목표</h3>' +
      '<p class="spend-goal__big">매달 <strong>' +
      esc(man(g.total)) +
      '</strong> 줄이기</p>' +
      '<ul class="spend-goal__list">' +
      rows +
      '</ul>' +
      '<div class="spend-goal__prog"><span>이번 달 아낀 돈 0원 / 목표 ' +
      esc(man(g.total)) +
      '</span><div class="spend-goal__track"><i style="width:0%"></i></div></div>' +
      '<p class="spend-goal__after">줄인 뒤 월 여유 <strong>' +
      esc(LA.manSigned(g.after)) +
      '</strong></p></div>'
    );
  }

  function renderScreen() {
    const c = current();
    return (
      UI.appbar('소비 분석') +
      '<div class="screen-body spend-body">' +
      '<div class="spend-head"><span>이번 달 소비</span><strong>' +
      esc(won(c.expense)) +
      '</strong></div>' +
      '<div class="card">' +
      stack(c.categories, { fresh: true, insight: c.insight }) +
      '</div>' +
      '<div class="card"><h3 class="card__title">지난달과 비교</h3>' +
      compareList(c.insight) +
      '</div>' +
      '<div class="card"><h3 class="card__title">소비 패턴</h3>' +
      tags(c.insight.tags) +
      '</div>' +
      goalCard() +
      '</div>'
    );
  }

  UI.registerScreen('spend', {
    title: '소비 분석',
    white: true,
    render: renderScreen,
  });

  WSP.spendView = { render: renderScreen, stack: stack, tags: tags, changeText: changeText, colors: SPEND_COLORS, current: current };

  WSP.registerActions({
    'spend-open'() {
      return UI.navigate('spend');
    },
  });
})();
