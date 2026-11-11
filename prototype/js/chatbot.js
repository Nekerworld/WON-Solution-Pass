/**
 * chatbot.js
 * 외부 AI 모델 없이 동작하는 "규칙 기반" 한국어 질의 처리 시뮬레이션.
 *   사용자 질문 → 정규화 → 키워드/패턴 의도 분류(복합 의도) → 은행 상태 조회
 *   → 규칙 엔진 + 경로 탐색 → 현재 상태 기반 응답 + 기능 링크
 * - 사용자 진술과 은행 상태가 다르면 은행의 확인된 상태를 우선한다.
 * - 규칙으로 해석할 수 없는 질문에는 사실을 만들어내지 않는다.
 */
(function () {
  'use strict';

  const WSP = window.WSP;
  const bank = WSP.mockBank;
  const RE = WSP.ruleEngine;
  const PF = WSP.pathfinder;
  const P = WSP.DEMO_POLICY;
  const fmt = WSP.utils.formatWon;
  const man = WSP.utils.formatMan;

  /** 이 모듈은 LLM이 아니다. 화면과 로그에서 이 값을 근거로 구분 표시한다. */
  const NLU_MODE = 'RULE_BASED_SIMULATION';

  const INTENT_LABELS = {
    TRANSFER_FAILURE: '이체 실패·가능 여부',
    TRANSFER_LIMIT: '이체한도',
    OTP_REGISTRATION: '디지털 OTP',
    KYC_STATUS: '고객확인',
    TRANSFER_STATUS: '이체 결과',
    GENERAL_HELP: '일반 도움',
    UNKNOWN: '해석 불가',
  };

  const INTENT_RULES = [
    { id: 'OTP_REGISTRATION', patterns: [/otp/, /디지털\s?인증/] },
    { id: 'TRANSFER_LIMIT', patterns: [/한도/] },
    { id: 'KYC_STATUS', patterns: [/고객\s?확인/, /본인\s?확인/, /kyc/, /신분증/] },
    {
      id: 'TRANSFER_STATUS',
      patterns: [
        /(이체|송금|거래).*(결과|상태|처리\s?중|진행\s?상황)/,
        /(이체|송금|거래|입금).*(처리|완료|입금)\s?(됐|되었|된\s?거|됐는지)/,
        /(입금|송금|이체)\S*\s?(됐|되었)(나|는지|어|니)/,
        /보낸\s?돈/,
      ],
    },
    {
      id: 'TRANSFER_FAILURE',
      patterns: [
        /(이체|송금|보내|보낼|입금).*(안\s?(돼|되|됨|됩|됐)|실패|오류|에러|막|못|불가)/,
        /안\s?(돼|되|됨|됩|됐)|실패했|막혀|막혔|못\s?보내/,
        /(이체|송금|보내|보낼).*(싶|하려|할래|가능|할\s?수)/,
        /왜.*(이체|송금)/,
      ],
    },
    { id: 'GENERAL_HELP', fallbackOnly: true, patterns: [/오류|에러|문제|도와|도움|어떻게\s?해야|모르겠/] },
  ];

  const CLAIM_RULES = [
    { fact: 'otpRegistered', pattern: /otp.*(등록\s?(했|완료|됐|되었|해\s?놨)|했는데|했어|했고)/ },
    { fact: 'limitChanged', pattern: /한도.*(바꿨|바꿔\s?놨|변경\s?(했|완료|됐)|올렸|늘렸)/ },
    { fact: 'kycCompleted', pattern: /(고객\s?확인|본인\s?확인).*(했|완료|끝났)/ },
  ];

  const SUGGESTIONS = [
    '이체가 왜 안 돼?',
    'OTP 등록했는데 아직 안 돼요.',
    '이체한도 어디서 바꿔?',
    '150만원 보내고 싶어.',
    '고객확인은 어떻게 해?',
    '계속 오류가 나는데 어떻게 해야 해?',
  ];

  function normalize(text) {
    let t = String(text || '').toLowerCase();
    t = t.replace(/(\d),(?=\d)/g, '$1');
    t = t.replace(/오티피|o\s*t\s*p/g, 'otp');
    t = t.replace(/[?!.,~…"'“”‘’()[\]{}]/g, ' ');
    t = t.replace(/\s+/g, ' ').trim();
    return t;
  }

  function parseKoreanNumber(s) {
    const digits = { 일: 1, 이: 2, 삼: 3, 사: 4, 오: 5, 육: 6, 칠: 7, 팔: 8, 구: 9 };
    const units = { 십: 10, 백: 100, 천: 1000 };
    let total = 0;
    let num = 0;
    for (const ch of s) {
      if (digits[ch]) num = digits[ch];
      else if (units[ch]) {
        total += (num || 1) * units[ch];
        num = 0;
      }
    }
    return total + num;
  }

  function extractAmount(t) {
    let m = t.match(/(\d+(?:\.\d+)?)\s*만\s*원?/);
    if (m) return Math.round(parseFloat(m[1]) * 10000);
    m = t.match(/(\d{4,})\s*원/);
    if (m) return parseInt(m[1], 10);
    m = t.match(/([일이삼사오육칠팔구십백천]+)\s*만\s*원?/);
    if (m) {
      const v = parseKoreanNumber(m[1]);
      if (v > 0) return v * 10000;
    }
    return null;
  }

  function analyze(text) {
    const normalized = normalize(text);
    const intents = [];
    INTENT_RULES.forEach((rule) => {
      if (rule.fallbackOnly) return;
      const hits = rule.patterns.filter((p) => p.test(normalized)).length;
      if (hits > 0) intents.push({ id: rule.id, label: INTENT_LABELS[rule.id], score: hits });
    });
    if (!intents.length) {
      const help = INTENT_RULES.find((r) => r.id === 'GENERAL_HELP');
      if (help.patterns.some((p) => p.test(normalized))) {
        intents.push({ id: 'GENERAL_HELP', label: INTENT_LABELS.GENERAL_HELP, score: 1 });
      }
    }
    const claims = {};
    CLAIM_RULES.forEach((c) => {
      if (c.pattern.test(normalized)) claims[c.fact] = true;
    });
    const amount = extractAmount(normalized);
    if (!intents.length && amount) {
      intents.push({ id: 'TRANSFER_FAILURE', label: INTENT_LABELS.TRANSFER_FAILURE, score: 1 });
    }
    if (!intents.length) intents.push({ id: 'UNKNOWN', label: INTENT_LABELS.UNKNOWN, score: 0 });
    return { mode: NLU_MODE, raw: text, normalized: normalized, intents: intents, amount: amount, claims: claims };
  }

  function countWord(n) {
    return ['', '한', '두', '세', '네', '다섯'][n] || String(n);
  }

  function orderSentence(steps) {
    const phrases = steps.map((s) => PF.getAction(s.actionId).phrase);
    if (phrases.length < 2) return '';
    if (phrases.length === 2) return '먼저 ' + phrases[0].first + ' 뒤 ' + phrases[1].last + '.';
    const middle = phrases.slice(1, -1).map((p) => p.mid).join(', ');
    return '먼저 ' + phrases[0].first + ' 뒤, ' + middle + ', 마지막으로 ' + phrases[phrases.length - 1].last + '.';
  }

  /** 이체 사전 조건 진단 문장 (현재 은행 상태 기준) */
  function diagnosisText(plan, ctx, said, tx, draft, amountIsDraft) {
    const links = [];
    if (amountIsDraft && tx) {
      if (tx.status === 'SUCCESS') {
        return {
          text: '요청하신 ' + man(ctx.amount) + ' 이체는 은행 처리 결과 성공으로 확인되었습니다. (거래 확인번호 ' + tx.id + ')',
          links: [],
        };
      }
      if (tx.status === 'PENDING' || tx.status === 'UNKNOWN') {
        return {
          text:
            '앞서 요청한 ' + man(ctx.amount) + ' 이체의 결과가 아직 확정되지 않았습니다. 중복 출금을 막기 위해 다시 이체하지 마시고 결과를 먼저 조회해 주세요.',
          links: [{ label: '거래 결과 조회', flowId: 'transfer-result' }],
          tone: 'warning',
        };
      }
    }

    if (plan.status === 'BLOCKED') {
      const b = plan.blocker;
      if (b.code === 'ACCOUNT_RESTRICTED') {
        return {
          text: '계좌에 이용 제한이 확인되어 해결패스에서 안내할 수 있는 절차가 없습니다. 제한 해제 방법은 임의로 안내하지 않으며, 공식 상담 창구에서 확인해 주세요.',
          links: [{ label: '상담 연결 안내', flowId: 'support' }],
          tone: 'warning',
        };
      }
      if (b.code === 'INSUFFICIENT_BALANCE') {
        return {
          text: '출금 가능 잔액(' + fmt(ctx.balance) + ')이 요청 금액 ' + fmt(ctx.amount) + '보다 적어 이체할 수 없습니다. 설정 변경으로 해결되는 문제가 아니에요.',
          links: [],
          tone: 'warning',
        };
      }
      return { text: b.title + ' 상태로 확인되어 거래를 진행하지 않습니다. ' + b.guidance, links: [{ label: '상담 연결 안내', flowId: 'support' }], tone: 'warning' };
    }

    if (plan.status === 'NO_PATH') {
      const reason = !ctx.limitChangeAllowed ? ' 현재 이 계좌는 비대면 한도 변경 대상이 아니에요. (가상)' : '';
      return {
        text: '현재 상태에서는 해결패스가 안내할 수 있는 절차를 찾지 못했습니다.' + reason + ' 상담을 통해 확인해 주세요.',
        links: [{ label: '상담 연결 안내', flowId: 'support' }],
        tone: 'warning',
      };
    }

    if (plan.status === 'READY') {
      const prefix = amountIsDraft ? '' : '(질문하신 ' + man(ctx.amount) + ' 기준) ';
      if (amountIsDraft) links.push({ label: '원래 이체로 돌아가기', flowId: 'transfer' });
      return {
        text:
          prefix +
          '현재 확인된 이체 사전 조건을 충족했습니다. ' +
          (amountIsDraft
            ? '원래 이체 화면으로 돌아가 수취인과 금액을 확인한 뒤 직접 이체를 진행해 주세요.'
            : '이체 화면에서 금액을 입력한 뒤 직접 이체를 진행해 주세요.'),
        links: links,
      };
    }

    // PLAN
    const ids = plan.actionSteps.map((s) => s.actionId);
    const hasK = ids.indexOf('COMPLETE_KYC') !== -1;
    const hasO = ids.indexOf('REGISTER_OTP') !== -1;
    const hasL = ids.indexOf('CHANGE_TRANSFER_LIMIT') !== -1;
    let s = '';
    if (hasO && hasL) {
      s = '현재 ' + (hasK ? '고객확인이 완료되지 않았고, ' : '') + '디지털 OTP가 등록되어 있지 않고, 이체한도도 ' + man(ctx.transferLimit) + '으로 설정되어 있습니다.';
    } else if (hasL) {
      const otpLine = ctx.otpRegistered && ctx.amount > P.otpRequiredAbove && !said.otpConfirmed ? '디지털 OTP 등록이 확인되었습니다. ' : '';
      if (otpLine) said.otpConfirmed = true;
      s =
        (hasK ? '고객확인이 완료되지 않았습니다. ' : '') +
        otpLine +
        '현재 이체한도는 ' +
        man(ctx.transferLimit) +
        '이므로 ' +
        man(ctx.amount) +
        ' 이체를 위해 한도 변경이 필요합니다.';
    } else if (hasO) {
      s = (hasK ? '현재 고객확인이 완료되지 않았고, 디지털 OTP도 등록되어 있지 않습니다.' : '현재 이체한도는 충분하지만, ' + man(ctx.amount) + ' 이체에는 디지털 OTP 등록이 필요합니다. (데모 가상 정책)');
    } else if (hasK) {
      s = '고객확인이 완료되지 않아 이체 전에 고객확인 절차가 필요합니다.';
    }
    const order = orderSentence(plan.actionSteps);
    if (order) s += ' ' + order;
    if (!amountIsDraft) s = '(질문하신 ' + man(ctx.amount) + ' 기준) ' + s;
    plan.actionSteps.forEach((st) => {
      const a = PF.getAction(st.actionId);
      links.push({ label: a.cta, flowId: a.flowId });
    });
    return { text: s, links: links };
  }

  function unknownReply(analysis) {
    return {
      text:
        '질문을 정확히 이해하지 못했어요. 해결패스는 이체, 이체한도, 디지털 OTP, 고객확인, 이체 결과에 관한 질문을 은행 상태로 확인해 안내할 수 있어요.\n예: "이체가 왜 안 돼?", "이체한도 어디서 바꿔?"\n확인되지 않은 금융 정보는 안내하지 않으며, 다른 문의는 상담으로 연결해 드릴게요.',
      tone: 'warning',
      links: [{ label: '상담 연결 안내', flowId: 'support' }],
      analysis: analysis,
      ruleIds: [],
      stateVersion: null,
    };
  }

  function dedupeLinks(links) {
    const seen = new Set();
    return links.filter((l) => {
      if (seen.has(l.flowId)) return false;
      seen.add(l.flowId);
      return true;
    });
  }

  async function respond(text) {
    const analysis = analyze(text);
    const ids = analysis.intents.map((i) => i.id);
    WSP.events.add('NLU', '[' + NLU_MODE + '] 의도: ' + ids.join(', ') + (analysis.amount ? ' / 금액 ' + analysis.amount : ''));
    if (ids[0] === 'UNKNOWN') return unknownReply(analysis);

    const results = await Promise.all([bank.getCustomerState(), bank.getTransferDraft()]);
    const failed = results.find((r) => !r.ok);
    if (failed) {
      PF.planFromQueryFailure(failed.error);
      return {
        text: '현재 은행 상태를 조회할 수 없어요. (' + failed.error.message + ')\n확인되지 않은 정보로 안내하지 않을게요. 잠시 후 다시 질문하시거나 상담을 이용해 주세요.',
        tone: 'warning',
        links: [{ label: '상담 연결 안내', flowId: 'support' }],
        analysis: analysis,
        ruleIds: ['R06'],
        stateVersion: null,
      };
    }

    const snap = results[0].data;
    const draft = results[1].data.draft;
    const tx = results[1].data.transaction;
    const amount = analysis.amount || draft.amount;
    const amountIsDraft = amount === draft.amount;
    const ctx = RE.buildContext(snap, draft, amount);
    const evaluation = RE.evaluate(ctx);
    const plan = PF.computePlan(evaluation);
    const restricted = plan.status === 'BLOCKED' && plan.blocker.code === 'ACCOUNT_RESTRICTED';

    const parts = [];
    let links = [];
    let tone = 'normal';
    const said = { otpConfirmed: false };

    // 1) 사용자 진술 대조 - 은행의 확인된 상태 우선
    if (analysis.claims.otpRegistered) {
      if (ctx.otpRegistered) {
        parts.push('디지털 OTP 등록이 확인되었습니다.');
        said.otpConfirmed = true;
      } else {
        parts.push('말씀하신 내용과 달리, 은행 기록상 디지털 OTP는 아직 등록되지 않은 상태로 확인됩니다.');
        tone = 'warning';
      }
    }
    if (analysis.claims.limitChanged) {
      if (ctx.transferLimit >= ctx.amount) parts.push('이체한도 변경이 확인되었습니다. (현재 1일 이체한도 ' + fmt(ctx.transferLimit) + ')');
      else {
        parts.push('은행 기록상 현재 1일 이체한도는 ' + fmt(ctx.transferLimit) + '으로, 요청 금액보다 낮습니다.');
        tone = 'warning';
      }
    }
    if (analysis.claims.kycCompleted) {
      if (ctx.kycCompleted) parts.push('고객확인 완료가 확인되었습니다.');
      else {
        parts.push('은행 기록상 고객확인은 아직 완료되지 않은 상태입니다.');
        tone = 'warning';
      }
    }

    const wantsDiagnosis = ids.indexOf('TRANSFER_FAILURE') !== -1 || ids.indexOf('GENERAL_HELP') !== -1;

    // 2) 이체 사전 조건 진단
    if (wantsDiagnosis) {
      const d = diagnosisText(plan, ctx, said, tx, draft, amountIsDraft);
      parts.push(d.text);
      links = links.concat(d.links);
      if (d.tone === 'warning') tone = 'warning';
    }

    // 3) 개별 의도 응답 (진단에 포함되지 않은 정보만)
    if (!wantsDiagnosis && restricted && ids.some((id) => ['OTP_REGISTRATION', 'TRANSFER_LIMIT', 'KYC_STATUS'].indexOf(id) !== -1)) {
      parts.push('계좌에 이용 제한이 확인되어 지금은 설정 변경을 안내하지 않습니다. 공식 상담 창구에서 확인해 주세요.');
      links.push({ label: '상담 연결 안내', flowId: 'support' });
      tone = 'warning';
    } else if (!wantsDiagnosis) {
      if (ids.indexOf('OTP_REGISTRATION') !== -1) {
        if (ctx.otpRegistered) {
          if (!said.otpConfirmed) parts.push('디지털 OTP는 이미 등록되어 있어요. 다시 등록할 필요가 없습니다.');
        } else if (P.otpRegistrationRequiresKyc && !ctx.kycCompleted) {
          parts.push('디지털 OTP가 아직 등록되어 있지 않아요. 데모 가상 정책상 고객확인을 먼저 완료한 뒤 등록할 수 있어요.');
          links.push({ label: '고객확인 하러 가기', flowId: 'kyc-flow' });
          links.push({ label: '디지털 OTP 등록하러 가기', flowId: 'otp-registration' });
        } else {
          parts.push(
            '디지털 OTP가 아직 등록되어 있지 않아요. 디지털 OTP 등록 화면에서 진행할 수 있어요.' +
              (ctx.amount > P.otpRequiredAbove ? ' 현재 준비 중인 ' + man(ctx.amount) + ' 이체에는 OTP 등록이 필요합니다. (가상 정책)' : '')
          );
          links.push({ label: '디지털 OTP 등록하러 가기', flowId: 'otp-registration' });
        }
      }
      if (ids.indexOf('TRANSFER_LIMIT') !== -1) {
        let s = '현재 1일 이체한도는 ' + fmt(ctx.transferLimit) + '입니다.';
        if (!ctx.limitChangeAllowed) {
          s += ' 현재 이 계좌는 비대면 한도 변경 대상이 아니에요. (가상) 상담을 통해 확인해 주세요.';
          links.push({ label: '상담 연결 안내', flowId: 'support' });
        } else if (ctx.transferLimit >= ctx.amount) {
          s += ' ' + man(ctx.amount) + ' 이체에는 현재 한도로 충분해서 변경하지 않아도 됩니다. 한도 변경은 이체한도 관리 화면에서 할 수 있어요.';
          links.push({ label: '이체한도 관리 열기', flowId: 'limit-management' });
        } else {
          s += ' ' + man(ctx.amount) + ' 이체를 위해서는 한도 변경이 필요해요. 이체한도 관리 화면에서 변경할 수 있어요.';
          if (ctx.amount > P.maxLimitWithoutOtp && !ctx.otpRegistered) {
            s += ' 단, 데모 가상 정책상 ' + man(P.maxLimitWithoutOtp) + '을 넘는 한도로 변경하려면 디지털 OTP 등록이 먼저 필요해요.';
            links.push({ label: '디지털 OTP 등록하러 가기', flowId: 'otp-registration' });
          }
          links.push({ label: '이체한도 변경하러 가기', flowId: 'limit-management' });
        }
        parts.push(s);
      }
      if (ids.indexOf('KYC_STATUS') !== -1) {
        if (ctx.kycCompleted) {
          if (!analysis.claims.kycCompleted) parts.push('고객확인은 이미 완료되어 있어 추가로 진행할 필요가 없어요.');
        } else {
          parts.push('고객확인이 아직 완료되지 않았어요. 고객확인 화면에서 진행할 수 있어요. (실제 신분증 정보는 요구하지 않는 시뮬레이션입니다)');
          links.push({ label: '고객확인 하러 가기', flowId: 'kyc-flow' });
        }
      }
    }

    // 4) 이체 결과 문의
    if (ids.indexOf('TRANSFER_STATUS') !== -1) {
      if (!tx) {
        parts.push('아직 진행된 이체 요청이 없어요. 현재 준비 중인 이체는 ' + draft.recipient + '님에게 ' + fmt(draft.amount) + '입니다.');
      } else if (tx.status === 'SUCCESS') {
        parts.push('최근 이체(' + tx.id + ', ' + fmt(tx.amount) + ')는 은행 처리 결과 성공으로 확인되었습니다.');
      } else if (tx.status === 'FAILED') {
        parts.push('최근 이체 요청(' + tx.id + ')은 은행 처리 결과 실패로 확인되었습니다. 출금되지 않았어요.');
      } else if (tx.status === 'PENDING') {
        parts.push('최근 이체 요청(' + tx.id + ')은 은행에서 처리 중이에요. 중복 출금을 막기 위해 다시 이체하지 말고 결과를 조회해 주세요.');
        links.push({ label: '거래 결과 조회', flowId: 'transfer-result' });
        tone = 'warning';
      } else {
        parts.push('최근 이체 요청(' + tx.id + ')의 결과를 아직 확인하지 못했어요. 성공 여부가 확정되기 전에는 다시 이체하지 마시고, 결과를 조회하거나 상담을 이용해 주세요.');
        links.push({ label: '거래 결과 조회', flowId: 'transfer-result' });
        links.push({ label: '상담 연결 안내', flowId: 'support' });
        tone = 'warning';
      }
    }

    if (ids.length === 1 && ids[0] === 'GENERAL_HELP') {
      parts.push('같은 문제가 계속되면 상담으로 연결해 드릴 수도 있어요.');
      links.push({ label: '상담 연결 안내', flowId: 'support' });
    }

    if (!parts.length) parts.push('현재 은행 상태에서 추가로 안내할 내용이 없어요.');

    return {
      text: parts.join('\n'),
      tone: tone,
      links: dedupeLinks(links),
      analysis: analysis,
      ruleIds: evaluation.firedRules,
      stateVersion: snap.stateVersion,
      planStatus: plan.status,
    };
  }

  WSP.chatbot = {
    NLU_MODE: NLU_MODE,
    INTENT_LABELS: INTENT_LABELS,
    SUGGESTIONS: SUGGESTIONS,
    normalize: normalize,
    extractAmount: extractAmount,
    analyze: analyze,
    respond: respond,
    countWord: countWord,
  };
})();
