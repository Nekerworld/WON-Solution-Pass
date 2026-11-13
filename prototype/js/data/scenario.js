/**
 * data/scenario.js
 * 시연용 공통 가상 데이터. 자산관리·가입 지원·시연 패널이 모두 이 데이터를 쓴다.
 * - 조건(CONDITIONS): 상품 가입에 필요한 은행 측 사실(fact)
 * - 고객 제약(CONSTRAINTS): 은행이 모르는, 고객만 답할 수 있는 사정
 * - 업무(TASKS): 기존 업무 화면. 선행 조건(pre), 고객 제약(needs), 성공 효과(effects)를 가진다.
 *   같은 효과를 내는 업무가 여러 개면 서로의 대체 수단이다.
 * - 상품(PRODUCTS), 재무 항목(finance)
 * 상품명·조건·수치는 모두 시연용으로 만든 값이다.
 */
(function () {
  'use strict';

  const WSP = window.WSP;

  const POLICY = Object.freeze({
    version: 'DEMO-2026.11',
    joinQuestionLimit: 3,
    assetQuestionLimit: 3,
    /** 같은 조건이 업무 완료 후에도 진전이 없을 때 반복으로 판정하는 횟수 */
    repeatLimit: 2,
    emergencyMonths: 3,
  });

  /** 은행 측 사실 */
  const FACTS = Object.freeze({
    adult: { label: '만 19세 이상', short: '성인' },
    identityVerified: { label: '비대면 실명확인', short: '실명' },
    hasDepositAccount: { label: '우리은행 입출금 계좌', short: '계좌' },
    certRegistered: { label: '우리 인증서', short: '인증서' },
    kycDone: { label: '고객정보 확인', short: '고객정보' },
  });

  /** 상품 가입 조건. blocker: 앱 안에서 해결할 업무가 없는 조건 */
  const CONDITIONS = Object.freeze({
    ADULT: { fact: 'adult', label: '만 19세 이상', blocker: true, evidence: '고객 기본 정보' },
    IDENTITY: { fact: 'identityVerified', label: '비대면 실명확인 완료', evidence: '실명확인 기록' },
    ACCOUNT: { fact: 'hasDepositAccount', label: '납입용 우리은행 입출금 계좌', evidence: '보유 계좌 목록' },
    KYC: { fact: 'kycDone', label: '고객정보(직업·거래 목적) 확인', evidence: '고객정보 등록 기록' },
    CERT: { fact: 'certRegistered', label: '전자서명용 우리 인증서', evidence: '인증서 등록 기록' },
  });

  /** 고객 제약: 은행 데이터로 알 수 없어 고객에게 확인해야 하는 사정 */
  const CONSTRAINTS = Object.freeze({
    hasIdCard: { label: '실물 신분증(주민등록증·운전면허증)' },
    hasMobileId: { label: '모바일 신분증(모바일 운전면허·모바일 주민등록증)' },
    hasOtherBankAccount: { label: '다른 은행 본인 명의 계좌' },
  });

  /** 기존 업무 화면 (모달 또는 별도 메뉴로 열림) */
  const TASKS = Object.freeze([
    {
      id: 'ID_CARD_VERIFY',
      label: '신분증 촬영 실명확인',
      menu: '실명확인',
      icon: 'idcard',
      pre: {},
      needs: { hasIdCard: true },
      effects: { identityVerified: true },
      weight: 3,
      minutes: 3,
      prep: ['실물 신분증(주민등록증 또는 운전면허증)'],
      steps: ['신분증 촬영', '신분증 진위 확인 요청', '은행 확인 결과 수신'],
      desc: '신분증을 촬영해 본인임을 확인해요.',
    },
    {
      id: 'MOBILE_ID_VERIFY',
      label: '모바일 신분증 실명확인',
      menu: '실명확인',
      icon: 'phone',
      pre: {},
      needs: { hasMobileId: true },
      effects: { identityVerified: true },
      weight: 2,
      minutes: 2,
      prep: ['모바일 운전면허 또는 모바일 주민등록증 앱'],
      steps: ['모바일 신분증 앱 연결', '신분 정보 제출 동의', '은행 확인 결과 수신'],
      desc: '휴대폰에 등록된 모바일 신분증으로 본인임을 확인해요.',
    },
    {
      id: 'OPEN_ACCOUNT_OTHERBANK',
      label: '입출금 계좌 개설 (다른 은행 계좌 확인)',
      menu: '계좌 개설',
      icon: 'wallet',
      pre: { identityVerified: true },
      needs: { hasOtherBankAccount: true },
      effects: { hasDepositAccount: true },
      weight: 3,
      minutes: 4,
      prep: ['다른 은행 본인 명의 계좌번호'],
      steps: ['계좌 정보 입력', '다른 은행 계좌로 1원 입금 확인', '계좌 개설 결과 수신'],
      desc: '다른 은행 본인 계좌로 1원을 보내 본인 계좌인지 확인한 뒤 계좌를 만들어요.',
    },
    {
      id: 'OPEN_ACCOUNT_CERT',
      label: '입출금 계좌 개설 (인증서 확인)',
      menu: '계좌 개설',
      icon: 'wallet',
      pre: { identityVerified: true, certRegistered: true },
      needs: {},
      effects: { hasDepositAccount: true },
      weight: 2,
      minutes: 3,
      prep: ['우리 인증서'],
      steps: ['계좌 정보 입력', '인증서 전자서명', '계좌 개설 결과 수신'],
      desc: '우리 인증서로 본인 확인 후 계좌를 만들어요.',
    },
    {
      id: 'ISSUE_CERT',
      label: '우리 인증서 발급',
      menu: '인증센터',
      icon: 'key',
      pre: { identityVerified: true, hasDepositAccount: true },
      needs: {},
      effects: { certRegistered: true },
      weight: 2,
      minutes: 2,
      prep: ['우리은행 계좌 비밀번호'],
      steps: ['우리은행 계좌 확인', '인증서 비밀번호 설정', '인증서 등록 결과 수신'],
      desc: '전자서명에 쓰는 우리 인증서를 이 기기에 발급해요. 우리은행 계좌가 있어야 해요.',
    },
    {
      id: 'KYC_UPDATE',
      label: '고객정보 확인 (직업·거래 목적)',
      menu: '내 정보 관리',
      icon: 'user',
      pre: { hasDepositAccount: true },
      needs: {},
      effects: { kycDone: true },
      weight: 1,
      minutes: 1,
      prep: [],
      steps: ['직업 정보 저장', '거래 목적 저장', '고객정보 확인 결과 수신'],
      fields: [
        { id: 'job', label: '직업', options: ['회사원', '공무원', '자영업', '프리랜서', '학생', '기타'] },
        { id: 'purpose', label: '거래 목적', options: ['저축·자산 형성', '급여 수령', '생활비 관리', '기타'] },
      ],
      desc: '금융거래를 위해 직업과 거래 목적을 확인해요.',
    },
  ]);

  /** 상품 */
  const PRODUCTS = Object.freeze([
    {
      id: 'SAVINGS_GOAL',
      name: 'WON 목돈마련 적금',
      type: '적금',
      rate: '연 3.2%',
      summary: '매월 정해진 금액을 모아 목돈을 만드는 적립식 상품',
      goalTags: ['목돈 마련'],
      periods: [12, 24, 36],
      minMonthly: 10000,
      maxMonthly: 1000000,
      conditions: ['ADULT', 'IDENTITY', 'ACCOUNT', 'KYC', 'CERT'],
      directSteps: [
        { id: 'terms', label: '상품 안내·약관 동의', checks: [] },
        { id: 'amount', label: '가입 금액·기간 입력', checks: ['ADULT'] },
        { id: 'account', label: '출금 계좌 선택', checks: ['IDENTITY', 'ACCOUNT'] },
        { id: 'info', label: '고객정보 확인', checks: ['KYC'] },
        { id: 'sign', label: '전자서명', checks: ['CERT'] },
      ],
    },
    {
      id: 'FREE_SAVINGS',
      name: 'WON 자유적립 예금',
      type: '자유적립식',
      rate: '연 2.8%',
      summary: '원하는 날 원하는 금액을 자유롭게 넣는 적립식 상품',
      goalTags: ['목돈 마련', '비상자금'],
      periods: [6, 12, 24],
      minMonthly: 10000,
      maxMonthly: 3000000,
      conditions: ['ADULT', 'IDENTITY', 'ACCOUNT', 'CERT'],
      directSteps: [
        { id: 'terms', label: '상품 안내·약관 동의', checks: [] },
        { id: 'amount', label: '가입 기간 입력', checks: ['ADULT'] },
        { id: 'account', label: '출금 계좌 선택', checks: ['IDENTITY', 'ACCOUNT'] },
        { id: 'sign', label: '전자서명', checks: ['CERT'] },
      ],
    },
    {
      id: 'PARKING',
      name: 'WON 파킹 통장',
      type: '입출금',
      rate: '연 2.0%',
      summary: '비상자금을 넣어 두고 언제든 꺼내 쓰는 입출금 통장',
      goalTags: ['비상자금'],
      periods: [],
      minMonthly: 0,
      maxMonthly: 0,
      conditions: ['ADULT', 'IDENTITY', 'CERT'],
      directSteps: [
        { id: 'terms', label: '상품 안내·약관 동의', checks: [] },
        { id: 'identity', label: '본인 확인', checks: ['ADULT', 'IDENTITY'] },
        { id: 'sign', label: '전자서명', checks: ['CERT'] },
      ],
    },
  ]);

  const SOURCE_LABEL = Object.freeze({ BANK: '조회', STATED: '고객 답변', ESTIMATED: '추정', UNKNOWN: '미확인' });

  const initialBankState = Object.freeze({
    customer: {
      name: '김우리',
      age: 29,
      firstTimeCustomer: true,
      /** 로그인 시 확인된 정보: 다시 묻지 않는다 */
      mobileOwnerVerified: true,
    },
    facts: {
      adult: true,
      identityVerified: false,
      hasDepositAccount: false,
      certRegistered: false,
      kycDone: false,
    },
    /** 처리 중인 업무: fact -> { sessionId, queriesLeft } */
    pending: {},
    taskSessions: {},
    applications: {},
    consultations: {},
    finance: {
      mydataLinked: true,
      linked: ['가상 A은행', '가상 B카드'],
      notLinked: ['증권사', '보험사', '부동산·현금'],
      otherBankAccounts: [{ bank: '가상 A은행', name: '입출금 통장', masked: '110-***-4421' }],
      items: {
        monthlyIncome: { value: 3500000, source: 'ESTIMATED', basis: '가상 A은행 급여성 입금 최근 6개월 평균' },
        monthlyExpense: { value: 2100000, source: 'ESTIMATED', basis: '가상 A은행·B카드 출금 최근 6개월 평균' },
        liquidAssets: { value: 8000000, source: 'BANK', basis: '가상 A은행 예금·적금 잔액' },
        investAssets: { value: null, source: 'UNKNOWN', basis: '연결되지 않은 증권사' },
        debt: { value: 0, source: 'BANK', basis: '연결 기관 대출 없음 (연결 안 된 기관은 미확인)' },
        debtPayment: { value: 0, source: 'BANK', basis: '연결 기관 상환 내역 없음' },
      },
    },
    simulation: {
      /** NORMAL | ERROR | IN_PROGRESS | PARTIAL | MISMATCH | MISMATCH_ALWAYS */
      nextTaskOutcome: 'NORMAL',
      /** SUCCESS | FAILED | PENDING | UNKNOWN */
      nextApplicationOutcome: 'SUCCESS',
      /** ACCEPTED | FAILED */
      nextConsultOutcome: 'ACCEPTED',
      queryFailure: false,
    },
    system: { bankAvailable: true, stateVersion: 1 },
  });

  function getTask(id) {
    return TASKS.find((t) => t.id === id) || null;
  }
  function getProduct(id) {
    return PRODUCTS.find((p) => p.id === id) || null;
  }

  WSP.scenario = {
    POLICY: POLICY,
    FACTS: FACTS,
    CONDITIONS: CONDITIONS,
    CONSTRAINTS: CONSTRAINTS,
    TASKS: TASKS,
    PRODUCTS: PRODUCTS,
    SOURCE_LABEL: SOURCE_LABEL,
    initialBankState: initialBankState,
    getTask: getTask,
    getProduct: getProduct,
  };

  WSP.store = WSP.createStore(initialBankState, { storageKey: 'wsp.bankState.v2' });
})();
