/**
 * aiSchema.js
 * AI 출력은 자유 문장이 아니라 아래 구조를 따라야 한다. 시스템은 검증을 통과한
 * 행동만 실행하고, 실패하면 기본 선택지(대체 응답)로 되돌린다.
 *
 * { intent: string, message: string, actions: [{ type, ... }] }
 *
 * - AI는 가입 신청을 직접 실행할 수 없다 (submitApplication 금지, 고객 승인 화면에서만).
 * - AI가 제시하는 업무는 경로 계산 결과(허용 목록)에 있는 것만 가능하다.
 * - AI 문장은 '가입 완료'를 단정할 수 없다. 완료는 은행 결과 조회로만 판단한다.
 */
(function () {
  'use strict';

  const WSP = window.WSP;
  const SC = WSP.scenario;

  const TYPES = Object.freeze({
    ASK: ['questionId', 'text'],
    SET_CONSTRAINT: ['key', 'value'],
    SET_INFO: ['key', 'value'],
    PRESENT_OPTIONS: ['options'],
    CALL_TOOL: ['tool'],
    PROPOSE: ['text'],
    HOLD: ['reason'],
    ESCALATE: ['reason'],
    EXPLAIN: ['text'],
    STOP_QUESTIONS: [],
    END: [],
  });

  const TOOLS = Object.freeze(['checkConditions', 'getLinkedAccounts', 'getFinancialSnapshot', 'getTaskResult', 'computeRoute', 'computeMetrics', 'getApplicationResult']);
  const FORBIDDEN_TOOLS = Object.freeze(['submitApplication', 'runTask', 'demoResolveApplication']);
  const FORBIDDEN_PHRASES = [/가입이 완료/, /가입 완료됐/, /승인됐습니다/, /가입해 드렸/];

  /**
   * @param {object} out AI 출력
   * @param {{allowedActionIds?:string[], allowedQuestionIds?:string[], infoKeys?:string[]}} ctx
   */
  function validate(out, ctx) {
    const c = ctx || {};
    const errors = [];
    if (!out || typeof out !== 'object') return { valid: false, errors: ['출력이 객체가 아님'] };
    if (typeof out.intent !== 'string' || !out.intent) errors.push('intent 누락');
    if (typeof out.message !== 'string') errors.push('message 누락');
    if (!Array.isArray(out.actions)) errors.push('actions 배열 누락');
    else {
      out.actions.forEach((a, i) => {
        const tag = 'actions[' + i + ']';
        if (!a || !TYPES[a.type]) return errors.push(tag + ': 알 수 없는 type ' + (a && a.type));
        TYPES[a.type].forEach((f) => a[f] === undefined && errors.push(tag + ': ' + f + ' 누락'));
        if (a.type === 'SET_CONSTRAINT') {
          if (!SC.CONSTRAINTS[a.key]) errors.push(tag + ': 허용되지 않은 고객 제약 ' + a.key);
          if (typeof a.value !== 'boolean') errors.push(tag + ': value는 true/false');
        }
        if (a.type === 'SET_INFO') {
          if (c.infoKeys && c.infoKeys.indexOf(a.key) === -1) errors.push(tag + ': 허용되지 않은 정보 항목 ' + a.key);
          if (a.value !== null && typeof a.value !== 'number') errors.push(tag + ': value는 숫자');
        }
        if (a.type === 'PRESENT_OPTIONS') {
          if (!Array.isArray(a.options) || !a.options.length) errors.push(tag + ': options 비어 있음');
          else if (c.allowedActionIds) {
            a.options.forEach((id) => c.allowedActionIds.indexOf(id) === -1 && errors.push(tag + ': 경로 계산에 없는 업무 ' + id));
          }
        }
        if (a.type === 'ASK' && c.allowedQuestionIds && c.allowedQuestionIds.indexOf(a.questionId) === -1) {
          errors.push(tag + ': 허용되지 않은 질문 ' + a.questionId);
        }
        if (a.type === 'CALL_TOOL') {
          if (FORBIDDEN_TOOLS.indexOf(a.tool) !== -1) errors.push(tag + ': AI가 실행할 수 없는 도구 ' + a.tool);
          else if (TOOLS.indexOf(a.tool) === -1) errors.push(tag + ': 허용 목록에 없는 도구 ' + a.tool);
        }
      });
    }
    if (typeof out.message === 'string' && FORBIDDEN_PHRASES.some((re) => re.test(out.message))) {
      errors.push('message: 은행 결과 없이 완료를 단정');
    }
    return { valid: errors.length === 0, errors: errors };
  }

  WSP.aiSchema = { TYPES: TYPES, TOOLS: TOOLS, FORBIDDEN_TOOLS: FORBIDDEN_TOOLS, validate: validate };
})();
