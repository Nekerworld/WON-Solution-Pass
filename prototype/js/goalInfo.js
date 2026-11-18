/**
 * goalInfo.js
 * 시연 패널 "해결패스가 알고 있는 정보" 카드의 내용을 만드는 순수 함수.
 * 처음에는 목표만 있고, 목표가 정해지면 그 목표에 필요한 항목이 줄로 늘어난다.
 * 입력은 상담 세션과 상태 문자열뿐이다. 새 상태는 만들지 않는다.
 */
(function () {
  'use strict';

  const WSP = window.WSP;
  const AA = WSP.assetAdvisor;
  const LA = WSP.lumpsumAdvisor;
  const U = WSP.utils;

  const UNKNOWN = '아직 모름';
  const DECLINED = '답하지 않음';
  const SKIPPED = '묻지 않음';

  const KIND_LABEL = {
    LUMP_SUM: '목돈 마련',
    OVERSEAS_ACCOUNT: '해외주식 계좌 개설',
    DOMESTIC_STOCK: '국내주식 투자 알아보기',
    LEVERAGE: '레버리지 상품 알아보기',
    EMERGENCY: '비상자금 점검',
  };

  const PROFILE_LABEL = { STABLE: '안정', NEUTRAL: '중립', ACTIVE: '적극' };
  const EXP_LABEL = ['해본 적 없음', '소액 ETF 경험', '국내주식을 자주'];
  const LOSS_LABEL = ['바로 판다', '길게 버틴다', '더 산다'];

  function pct(rate) {
    return (Math.round(rate * 1000) / 10).toFixed(1).replace(/\.0$/, '') + '%';
  }

  function row(label, value, note) {
    return { label: label, value: value, note: note || '' };
  }

  /* ---------------- 목돈 상담 ---------------- */

  function periodText(goal) {
    const m = goal.months;
    return (m % 12 === 0 ? m / 12 + '년' : m + '개월') + ' · ' + U.formatMan(goal.amount);
  }

  function lumpRows(s, state, applied, hasFx, approved) {
    const kind = s.goalKind || '';
    if (!kind) return { flow: 'lumpsum', goalId: '', rows: [row('목표', '아직 없음')] };
    const ended = state === 'CLOSED' || state === 'SPEND_PLAN';
    const blank = ended ? SKIPPED : UNKNOWN;
    const rows = [row('목표', (kind === 'LUMP_SUM' && s.purposeLabel) || KIND_LABEL[kind])];
    /* 비상자금만 보는 동안은 목표 금액·성향을 묻지 않으므로 예금이 생활비 몇 개월치인지만 보여 준다 */
    if (s.intent === 'EMERGENCY') {
      const sn = s.snap || {};
      if (sn.expense > 0) rows.push(row('비상자금', '생활비 ' + Math.round((sn.deposit / sn.expense) * 10) / 10 + '개월치', '기준 3개월'));
      return { flow: 'lumpsum', goalId: kind, rows: rows };
    }
    /* 해외주식 칩으로 바로 계좌 개설로 간 채팅은 목표·성향을 묻지 않으므로 계좌 상태만 남긴다 */
    if (s.intent === 'OVERSEAS') {
      rows.push(row('해외 계좌', applied ? (approved ? '개설 완료' : '승인 대기') : hasFx === true ? '개설 중' : '없음'));
      return { flow: 'lumpsum', goalId: kind, rows: rows };
    }
    rows.push(row('목표 금액·기간', s.goal ? periodText(s.goal) : blank));
    const prof = s.expText && s.lossText ? LA.inferRiskProfile(s.expText, s.lossText) : null;
    rows.push(row('투자 경험', s.expText ? EXP_LABEL[LA.inferRiskProfile(s.expText, '').experience] : blank));
    rows.push(row('손실 감내', s.lossText ? LOSS_LABEL[LA.inferRiskProfile('', s.lossText).loss] : blank));
    rows.push(row('투자 성향', prof ? PROFILE_LABEL[prof.id] : blank));
    if (kind !== 'LUMP_SUM') {
      const a = s.advice;
      if (kind === 'LEVERAGE') {
        rows.push(row('월 투자 참고 금액', a ? '월 ' + LA.about(a.monthlyInvest) : blank));
        rows.push(row('필요한 연 수익', a ? '연 ' + pct(a.yieldRate) : blank));
      } else if (kind === 'DOMESTIC_STOCK') {
        rows.push(row('월 투자 참고 금액', a ? '월 ' + LA.about(a.monthlyInvest) : blank));
        rows.push(row('국내 비중', a ? '100%' : blank));
      } else {
        rows.push(row('월 투자 참고 금액', a ? '월 ' + LA.about(a.monthlyInvest) : blank));
        /* 해외만 보면 해외 100%, 두 시장을 모두 보면 추천 비중으로 나눈다 */
        if (s.market === 'both') {
          rows.push(row('국내 비중', a ? a.domesticShare + '%' : blank));
          rows.push(row('해외 비중', a ? a.overseasShare + '%' : blank));
        } else rows.push(row('해외 비중', a ? '100%' : blank));
        rows.push(row('해외 계좌', applied ? (approved ? '개설 완료' : '승인 대기') : hasFx === true ? '개설 중' : '없음'));
      }
    }
    return { flow: 'lumpsum', goalId: kind, rows: rows };
  }

  /* ---------------- 이전 자산관리 상담 ---------------- */

  function gapText(info, key) {
    if (!info || !info.items || !info.items[key]) return UNKNOWN;
    if (info.declined && info.declined.indexOf(key) !== -1) return DECLINED;
    const value = info.items[key].value;
    if (value == null) return UNKNOWN;
    if (Number(value) === 0) return '없음';
    if (Number(value) > 0) return U.formatWon(value);
    return UNKNOWN;
  }

  function paceText(info) {
    if (!info || !info.items || !info.items.investPace) return UNKNOWN;
    if (info.declined && info.declined.indexOf('investPace') !== -1) return DECLINED;
    const value = info.items.investPace.value;
    if (value == null) return UNKNOWN;
    return AA.display('investPace', value);
  }

  function monthsText(info) {
    if (!info || !info.items || !info.items.goalMonths) return UNKNOWN;
    if (info.declined && info.declined.indexOf('goalMonths') !== -1) return DECLINED;
    const value = info.items.goalMonths.value;
    return value == null ? UNKNOWN : AA.display('goalMonths', value);
  }

  function fromAccount(info, key) {
    const it = info && info.items && info.items[key];
    return !!it && it.value != null && it.source === 'BANK';
  }

  function assetRows(a) {
    const info = a.info;
    const purpose = AA.PURPOSES[a.purpose] ? a.purpose : 'GOAL_SAVING';
    if (!a.goalText) return { flow: 'asset', goalId: '', rows: [row('목표', '아직 없음')] };
    const rows = [row('목표', AA.PURPOSES[purpose].label, a.goalText)];
    const basics = [
      ['월 소득', 'monthlyIncome'],
      ['월 지출', 'monthlyExpense'],
      ['예금성 자산', 'liquidAssets'],
    ];
    if (purpose === 'INVEST') {
      rows.push(row('투자 속도', paceText(info)));
      rows.push(row('다른 증권 투자금', gapText(info, 'investAssets')));
      rows.push(row('목돈 지출 계획', gapText(info, 'plannedLumpSum')));
    } else if (purpose === 'GOAL_SAVING') {
      rows.push(row('목표 금액', gapText(info, 'goalAmount')));
      rows.push(row('목표 기간', monthsText(info)));
      rows.push(row('목돈 지출 계획', gapText(info, 'plannedLumpSum')));
      if (info && info.items && info.items.monthlySavingPref && info.items.monthlySavingPref.value != null) rows.push(row('희망 월 적립액', gapText(info, 'monthlySavingPref')));
    }
    if (purpose === 'EMERGENCY' || purpose === 'ORIENT') {
      rows.push(row('월 지출', gapText(info, 'monthlyExpense')));
      rows.push(row('예금성 자산', gapText(info, 'liquidAssets')));
      rows.push(row('월 소득', gapText(info, 'monthlyIncome')));
    } else {
      basics.forEach((b) => {
        if (!fromAccount(info, b[1])) rows.push(row(b[0], gapText(info, b[1])));
      });
    }
    return { flow: 'asset', goalId: purpose, rows: rows };
  }

  /**
   * @param {{lumpsum:?object,lumpsumState:string,asset:?object,assetState:string,applied:boolean,hasFxAccount:boolean}} input
   * @returns {{flow:string,goalId:string,rows:{label:string,value:string,note:string}[]}}
   */
  function describe(input) {
    const i = input || {};
    if (i.lumpsum && i.lumpsumState && i.lumpsumState !== 'IDLE') return lumpRows(i.lumpsum, i.lumpsumState, !!i.applied, i.hasFxAccount, !!i.approved);
    if (i.asset) return assetRows(i.asset);
    return { flow: 'none', goalId: '', rows: [row('목표', '아직 없음')] };
  }

  WSP.goalInfo = { describe: describe, UNKNOWN: UNKNOWN, DECLINED: DECLINED, SKIPPED: SKIPPED };
})();
