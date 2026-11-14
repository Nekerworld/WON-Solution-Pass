/// 시연용 공통 가상 데이터. 자산관리·가입 지원·시연 화면이 모두 이 데이터를 쓴다.
/// - 조건(conditions): 상품 가입에 필요한 은행 측 사실(fact)
/// - 고객 제약(constraints): 은행이 모르는, 고객만 답할 수 있는 사정
/// - 업무(tasks): 기존 업무 화면. 선행 조건(pre), 고객 제약(needs), 성공 효과(effects)를 가진다.
///   같은 효과를 내는 업무가 여러 개면 서로의 대체 수단이다.
/// 상품명·조건·수치는 모두 시연용으로 만든 값이며 실제 은행 정책과 무관하다.
library;

class Policy {
  static const String version = 'DEMO-2026.11';
  static const int joinQuestionLimit = 3;
  static const int assetQuestionLimit = 3;

  /// 같은 조건이 업무 완료 후에도 진전이 없을 때 반복으로 판정하는 횟수
  static const int repeatLimit = 2;
  static const int emergencyMonths = 3;
}

class FactDef {
  const FactDef(this.label, this.short);
  final String label;
  final String short;
}

/// 은행 측 사실 (순서가 상태 그래프 키 순서다)
const Map<String, FactDef> facts = {
  'adult': FactDef('만 19세 이상', '성인'),
  'identityVerified': FactDef('비대면 실명확인', '실명'),
  'hasDepositAccount': FactDef('우리은행 입출금 계좌', '계좌'),
  'certRegistered': FactDef('우리 인증서', '인증서'),
  'kycDone': FactDef('고객정보 확인', '고객정보'),
  'fxRegistered': FactDef('외환거래 서비스 신청', '외환'),
  'hasFxAccount': FactDef('외화 입출금 계좌', '외화계좌'),
  'investorProfiled': FactDef('투자성향 진단', '투자성향'),
};

String factLabel(String f) => facts[f]?.label ?? f;

class ConditionDef {
  const ConditionDef({required this.fact, required this.label, required this.evidence, this.blocker = false});
  final String fact;
  final String label;
  final String evidence;

  /// 앱 안에서 해결할 업무가 없는 조건
  final bool blocker;
}

const Map<String, ConditionDef> conditions = {
  'ADULT': ConditionDef(fact: 'adult', label: '만 19세 이상', blocker: true, evidence: '고객 기본 정보'),
  'IDENTITY': ConditionDef(fact: 'identityVerified', label: '비대면 실명확인 완료', evidence: '실명확인 기록'),
  'ACCOUNT': ConditionDef(fact: 'hasDepositAccount', label: '납입용 우리은행 입출금 계좌', evidence: '보유 계좌 목록'),
  'KYC': ConditionDef(fact: 'kycDone', label: '고객정보(직업·거래 목적) 확인', evidence: '고객정보 등록 기록'),
  'CERT': ConditionDef(fact: 'certRegistered', label: '전자서명용 우리 인증서', evidence: '인증서 등록 기록'),
  'FX': ConditionDef(fact: 'fxRegistered', label: '외환거래 서비스 신청', evidence: '외환거래 약정 기록'),
  'FX_ACCOUNT': ConditionDef(fact: 'hasFxAccount', label: '외화(USD) 입출금 계좌', evidence: '보유 외화 계좌 목록'),
  'PROFILE': ConditionDef(fact: 'investorProfiled', label: '투자성향 진단 완료', evidence: '투자자 정보 확인 기록'),
};

/// 고객 제약: 은행 데이터로 알 수 없어 고객에게 확인해야 하는 사정
const Map<String, String> constraintLabels = {
  'hasIdCard': '실물 신분증(주민등록증·운전면허증)',
  'hasMobileId': '모바일 신분증(모바일 운전면허·모바일 주민등록증)',
  'hasOtherBankAccount': '다른 은행 본인 명의 계좌',
};

class TaskField {
  const TaskField(this.id, this.label, this.options);
  final String id;
  final String label;
  final List<String> options;
}

class TaskDef {
  const TaskDef({
    required this.id,
    required this.label,
    required this.menu,
    required this.icon,
    required this.pre,
    required this.needs,
    required this.effects,
    required this.weight,
    required this.minutes,
    required this.prep,
    required this.steps,
    required this.desc,
    this.fields = const [],
  });

  final String id;
  final String label;
  final String menu;
  final String icon;
  final Map<String, bool> pre;
  final Map<String, bool> needs;
  final Map<String, bool> effects;
  final int weight;
  final int minutes;
  final List<String> prep;
  final List<String> steps;
  final String desc;
  final List<TaskField> fields;
}

const List<TaskDef> tasks = [
  TaskDef(
    id: 'ID_CARD_VERIFY',
    label: '신분증 촬영 실명확인',
    menu: '실명확인',
    icon: 'idcard',
    pre: {},
    needs: {'hasIdCard': true},
    effects: {'identityVerified': true},
    weight: 3,
    minutes: 3,
    prep: ['실물 신분증(주민등록증 또는 운전면허증)'],
    steps: ['신분증 촬영', '신분증 진위 확인 요청', '은행 확인 결과 수신'],
    desc: '신분증을 촬영해 본인임을 확인해요.',
  ),
  TaskDef(
    id: 'MOBILE_ID_VERIFY',
    label: '모바일 신분증 실명확인',
    menu: '실명확인',
    icon: 'phone',
    pre: {},
    needs: {'hasMobileId': true},
    effects: {'identityVerified': true},
    weight: 2,
    minutes: 2,
    prep: ['모바일 운전면허 또는 모바일 주민등록증 앱'],
    steps: ['모바일 신분증 앱 연결', '신분 정보 제출 동의', '은행 확인 결과 수신'],
    desc: '휴대폰에 등록된 모바일 신분증으로 본인임을 확인해요.',
  ),
  TaskDef(
    id: 'OPEN_ACCOUNT_OTHERBANK',
    label: '입출금 계좌 개설 (다른 은행 계좌 확인)',
    menu: '계좌 개설',
    icon: 'wallet',
    pre: {'identityVerified': true},
    needs: {'hasOtherBankAccount': true},
    effects: {'hasDepositAccount': true},
    weight: 3,
    minutes: 4,
    prep: ['다른 은행 본인 명의 계좌번호'],
    steps: ['계좌 정보 입력', '다른 은행 계좌로 1원 입금 확인', '계좌 개설 결과 수신'],
    desc: '다른 은행 본인 계좌로 1원을 보내 본인 계좌인지 확인한 뒤 계좌를 만들어요.',
  ),
  TaskDef(
    id: 'OPEN_ACCOUNT_CERT',
    label: '입출금 계좌 개설 (인증서 확인)',
    menu: '계좌 개설',
    icon: 'wallet',
    pre: {'identityVerified': true, 'certRegistered': true},
    needs: {},
    effects: {'hasDepositAccount': true},
    weight: 2,
    minutes: 3,
    prep: ['우리 인증서'],
    steps: ['계좌 정보 입력', '인증서 전자서명', '계좌 개설 결과 수신'],
    desc: '우리 인증서로 본인 확인 후 계좌를 만들어요.',
  ),
  TaskDef(
    id: 'ISSUE_CERT',
    label: '우리 인증서 발급',
    menu: '인증센터',
    icon: 'key',
    pre: {'identityVerified': true, 'hasDepositAccount': true},
    needs: {},
    effects: {'certRegistered': true},
    weight: 2,
    minutes: 2,
    prep: ['우리은행 계좌 비밀번호'],
    steps: ['우리은행 계좌 확인', '인증서 비밀번호 설정', '인증서 등록 결과 수신'],
    desc: '전자서명에 쓰는 우리 인증서를 이 기기에 발급해요. 우리은행 계좌가 있어야 해요.',
  ),
  TaskDef(
    id: 'KYC_UPDATE',
    label: '고객정보 확인 (직업·거래 목적)',
    menu: '내 정보 관리',
    icon: 'user',
    pre: {'hasDepositAccount': true, 'certRegistered': true},
    needs: {},
    effects: {'kycDone': true},
    weight: 1,
    minutes: 1,
    prep: ['우리 인증서'],
    steps: ['직업 정보 저장', '거래 목적 저장', '고객정보 확인 결과 수신'],
    fields: [
      TaskField('job', '직업', ['회사원', '공무원', '자영업', '프리랜서', '학생', '기타']),
      TaskField('purpose', '거래 목적', ['저축·자산 형성', '해외주식 투자', '급여 수령', '생활비 관리', '기타']),
    ],
    desc: '금융거래를 위해 직업과 거래 목적을 확인해요. 인증서로 본인 확인 후 저장해요.',
  ),
  TaskDef(
    id: 'FX_REGISTER',
    label: '외환거래 서비스 신청',
    menu: '외환',
    icon: 'globe',
    pre: {'certRegistered': true, 'kycDone': true},
    needs: {},
    effects: {'fxRegistered': true},
    weight: 2,
    minutes: 2,
    prep: ['우리 인증서'],
    steps: ['외환거래 약관 확인', '인증서 전자서명', '외환거래 등록 결과 수신'],
    desc: '외화를 사고팔고 외화 계좌를 쓰려면 외환거래 서비스를 먼저 신청해야 해요.',
  ),
  TaskDef(
    id: 'OPEN_FX_ACCOUNT',
    label: '외화(USD) 입출금 계좌 개설',
    menu: '외환',
    icon: 'globe',
    pre: {'fxRegistered': true, 'hasDepositAccount': true},
    needs: {},
    effects: {'hasFxAccount': true},
    weight: 2,
    minutes: 2,
    prep: ['우리은행 입출금 계좌'],
    steps: ['통화 선택(USD)', '원화 계좌 연결', '외화 계좌 개설 결과 수신'],
    desc: '해외주식을 사고팔 때 달러를 넣어 두는 외화 계좌를 만들어요.',
  ),
  TaskDef(
    id: 'INVESTOR_PROFILE',
    label: '투자성향 진단',
    menu: '투자',
    icon: 'chart',
    pre: {'kycDone': true, 'hasFxAccount': true},
    needs: {},
    effects: {'investorProfiled': true},
    weight: 2,
    minutes: 3,
    prep: [],
    steps: ['투자 경험 확인', '감당할 수 있는 손실 확인', '투자성향 결과 수신'],
    fields: [
      TaskField('experience', '투자 경험', ['없어요', '1년 미만', '1~3년', '3년 이상']),
      TaskField('loss', '감당할 수 있는 손실', ['원금은 지키고 싶어요', '10% 이내', '20% 이내', '그 이상도 괜찮아요']),
    ],
    desc: '해외주식 계좌를 열기 전에 투자 경험과 감당할 수 있는 손실을 확인해요.',
  ),
];

class DirectStep {
  const DirectStep(this.id, this.label, this.checks);
  final String id;
  final String label;
  final List<String> checks;
}

class ProductDef {
  const ProductDef({
    required this.id,
    required this.name,
    required this.type,
    required this.rate,
    required this.summary,
    required this.goalTags,
    required this.periods,
    required this.minMonthly,
    required this.maxMonthly,
    required this.conditions,
    required this.directSteps,
    this.kind,
    this.rateLabel,
    this.rateValue,
    this.markets = const [],
  });

  final String id;
  final String name;
  final String type;

  /// 'BROKERAGE': 납입액·기간 대신 거래 시장과 연결 계좌를 정한다
  final String? kind;
  final String rate;
  final String? rateLabel;
  final String? rateValue;
  final String summary;
  final List<String> goalTags;
  final List<int> periods;
  final int minMonthly;
  final int maxMonthly;
  final List<String> markets;
  final List<String> conditions;
  final List<DirectStep> directSteps;

  bool get isBrokerage => kind == 'BROKERAGE';
}

const List<ProductDef> products = [
  ProductDef(
    id: 'OVERSEAS_STOCK',
    name: 'WON 해외주식 계좌',
    type: '해외주식',
    kind: 'BROKERAGE',
    rate: '수수료 0.25%',
    rateLabel: '매매 수수료',
    rateValue: '0.25%',
    summary: '미국 등 해외 주식을 사고팔 수 있는 투자 계좌 (증권사 연계)',
    goalTags: ['해외주식'],
    periods: [],
    minMonthly: 0,
    maxMonthly: 0,
    markets: ['미국', '홍콩', '일본'],
    conditions: ['ADULT', 'IDENTITY', 'ACCOUNT', 'CERT', 'KYC', 'FX', 'FX_ACCOUNT', 'PROFILE'],
    directSteps: [
      DirectStep('terms', '상품 안내·약관 동의', []),
      DirectStep('identity', '본인 확인', ['ADULT', 'IDENTITY']),
      DirectStep('account', '연결 원화 계좌 선택', ['ACCOUNT']),
      DirectStep('sign', '인증서 확인', ['CERT']),
      DirectStep('info', '고객정보 확인', ['KYC']),
      DirectStep('fx', '외화 계좌 연결', ['FX', 'FX_ACCOUNT']),
      DirectStep('profile', '투자성향 확인', ['PROFILE']),
    ],
  ),
  ProductDef(
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
      DirectStep('terms', '상품 안내·약관 동의', []),
      DirectStep('amount', '가입 금액·기간 입력', ['ADULT']),
      DirectStep('account', '출금 계좌 선택', ['IDENTITY', 'ACCOUNT']),
      DirectStep('info', '고객정보 확인', ['KYC']),
      DirectStep('sign', '전자서명', ['CERT']),
    ],
  ),
  ProductDef(
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
      DirectStep('terms', '상품 안내·약관 동의', []),
      DirectStep('amount', '가입 기간 입력', ['ADULT']),
      DirectStep('account', '출금 계좌 선택', ['IDENTITY', 'ACCOUNT']),
      DirectStep('sign', '전자서명', ['CERT']),
    ],
  ),
  ProductDef(
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
      DirectStep('terms', '상품 안내·약관 동의', []),
      DirectStep('identity', '본인 확인', ['ADULT', 'IDENTITY']),
      DirectStep('sign', '전자서명', ['CERT']),
    ],
  ),
];

const Map<String, String> sourceLabel = {'BANK': '조회', 'STATED': '고객 답변', 'ESTIMATED': '추정', 'UNKNOWN': '미확인'};

class DemoStage {
  const DemoStage(this.id, this.label, this.facts, {this.application});
  final String id;
  final String label;
  final List<String> facts;
  final String? application;
}

/// 발표용 통합 시나리오: 처음 거래하는 고객의 해외주식 계좌 개설
class DemoScenario {
  static const String title = '처음 거래하는 고객의 해외주식 계좌 개설';
  static const String productId = 'OVERSEAS_STOCK';
  static const List<(String, String)> customerAnswers = [('실물 신분증', '없음'), ('모바일 신분증', '있음')];
  static const List<String> givens = ['우리은행 계좌·인증서 없음', '다른 은행 계좌 있음(마이데이터 연결)', '고객정보·투자성향 미등록'];
  static const List<DemoStage> stages = [
    DemoStage('ACCOUNT', '계좌 개설', ['identityVerified', 'hasDepositAccount']),
    DemoStage('AUTH', '인증', ['certRegistered', 'kycDone']),
    DemoStage('FX', '외환거래', ['fxRegistered']),
    DemoStage('FX_ACCOUNT', '해외계좌', ['hasFxAccount']),
    DemoStage('STOCK', '주식계좌', ['investorProfiled'], application: 'OVERSEAS_STOCK'),
  ];
}

TaskDef? getTask(String? id) {
  for (final t in tasks) {
    if (t.id == id) return t;
  }
  return null;
}

ProductDef? getProduct(String? id) {
  for (final p in products) {
    if (p.id == id) return p;
  }
  return null;
}
