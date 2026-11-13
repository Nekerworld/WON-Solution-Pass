/**
 * ruleEngine.js
 * 은행 조회 결과로 상품 가입 조건의 상태를 판정한다.
 * 상태: MET(충족) | UNMET(미충족) | UNKNOWN(미확인) | IN_PROGRESS(처리 중)
 * - 조회에 실패하면 모든 조건을 UNKNOWN으로 둔다. 미충족으로 단정하지 않는다.
 * - 조건 정의는 data/scenario.js의 데이터에서 읽는다. 조건을 만들어 내지 않는다.
 */
(function () {
  'use strict';

  const WSP = window.WSP;
  const SC = WSP.scenario;

  const STATUS_LABEL = Object.freeze({ MET: '충족', UNMET: '미충족', UNKNOWN: '미확인', IN_PROGRESS: '처리 중' });

  /**
   * @param {string} productId
   * @param {{ok:boolean, data?:object, error?:object}} resp mockBank.checkConditions 응답
   */
  function evaluate(productId, resp) {
    const product = SC.getProduct(productId);
    const ids = product ? product.conditions : [];
    if (!resp || !resp.ok) {
      return {
        productId: productId,
        ok: false,
        error: resp ? resp.error : { code: 'NO_RESPONSE', message: '응답이 없어요.' },
        conditions: ids.map((id) => ({ id: id, label: SC.CONDITIONS[id].label, fact: SC.CONDITIONS[id].fact, status: 'UNKNOWN', evidence: '조회 실패' })),
        facts: null,
        goal: goalOf(ids),
        unmet: [],
        unknown: ids.slice(),
        inProgress: [],
        blockers: [],
        allMet: false,
        stateVersion: null,
      };
    }
    const d = resp.data;
    const conditions = d.conditions.map((c) => {
      const def = SC.CONDITIONS[c.id];
      const status = c.value ? 'MET' : c.inProgress ? 'IN_PROGRESS' : 'UNMET';
      return { id: c.id, label: def.label, fact: def.fact, status: status, evidence: def.evidence, blocker: !!def.blocker };
    });
    const pick = (st) => conditions.filter((c) => c.status === st).map((c) => c.id);
    const unmet = pick('UNMET');
    return {
      productId: productId,
      ok: true,
      error: null,
      conditions: conditions,
      facts: Object.assign({}, d.facts),
      goal: goalOf(ids),
      unmet: unmet,
      unknown: [],
      inProgress: pick('IN_PROGRESS'),
      blockers: unmet.filter((id) => SC.CONDITIONS[id].blocker),
      allMet: conditions.every((c) => c.status === 'MET'),
      stateVersion: d.stateVersion,
    };
  }

  function goalOf(ids) {
    const goal = {};
    ids.forEach((id) => (goal[SC.CONDITIONS[id].fact] = true));
    return goal;
  }

  WSP.ruleEngine = { evaluate: evaluate, STATUS_LABEL: STATUS_LABEL };
})();
