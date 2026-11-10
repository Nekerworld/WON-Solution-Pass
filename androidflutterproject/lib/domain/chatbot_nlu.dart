/// 외부 AI 모델 없이 동작하는 "규칙 기반" 한국어 질의 해석 시뮬레이션.
///   사용자 질문 → 정규화 → 키워드/패턴 의도 분류(복합 의도) → 금액·진술 추출
/// 규칙으로 해석할 수 없는 질문에는 사실을 만들어내지 않는다.
library;

/// 이 모듈은 LLM이 아니다. 화면과 로그에서 이 값을 근거로 구분 표시한다.
const String nluMode = 'RULE_BASED_SIMULATION';

const Map<String, String> intentLabels = {
  'TRANSFER_FAILURE': '이체 실패·가능 여부',
  'TRANSFER_LIMIT': '이체한도',
  'OTP_REGISTRATION': '디지털 OTP',
  'KYC_STATUS': '고객확인',
  'TRANSFER_STATUS': '이체 결과',
  'GENERAL_HELP': '일반 도움',
  'UNKNOWN': '해석 불가',
};

class _IntentRule {
  const _IntentRule(this.id, this.patterns, {this.fallbackOnly = false});

  final String id;
  final List<RegExp> patterns;
  final bool fallbackOnly;
}

final List<_IntentRule> _intentRules = [
  _IntentRule('OTP_REGISTRATION', [RegExp(r'otp'), RegExp(r'디지털\s?인증')]),
  _IntentRule('TRANSFER_LIMIT', [RegExp(r'한도')]),
  _IntentRule('KYC_STATUS', [RegExp(r'고객\s?확인'), RegExp(r'본인\s?확인'), RegExp(r'kyc'), RegExp(r'신분증')]),
  _IntentRule('TRANSFER_STATUS', [
    RegExp(r'(이체|송금|거래).*(결과|상태|처리\s?중|진행\s?상황)'),
    RegExp(r'(이체|송금|거래|입금).*(처리|완료|입금)\s?(됐|되었|된\s?거|됐는지)'),
    RegExp(r'(입금|송금|이체)\S*\s?(됐|되었)(나|는지|어|니)'),
    RegExp(r'보낸\s?돈'),
  ]),
  _IntentRule('TRANSFER_FAILURE', [
    RegExp(r'(이체|송금|보내|보낼|입금).*(안\s?(돼|되|됨|됩|됐)|실패|오류|에러|막|못|불가)'),
    RegExp(r'안\s?(돼|되|됨|됩|됐)|실패했|막혀|막혔|못\s?보내'),
    RegExp(r'(이체|송금|보내|보낼).*(싶|하려|할래|가능|할\s?수)'),
    RegExp(r'왜.*(이체|송금)'),
  ]),
  _IntentRule('GENERAL_HELP', [RegExp(r'오류|에러|문제|도와|도움|어떻게\s?해야|모르겠')], fallbackOnly: true),
];

final List<({String fact, RegExp pattern})> _claimRules = [
  (fact: 'otpRegistered', pattern: RegExp(r'otp.*(등록\s?(했|완료|됐|되었|해\s?놨)|했는데|했어|했고)')),
  (fact: 'limitChanged', pattern: RegExp(r'한도.*(바꿨|바꿔\s?놨|변경\s?(했|완료|됐)|올렸|늘렸)')),
  (fact: 'kycCompleted', pattern: RegExp(r'(고객\s?확인|본인\s?확인).*(했|완료|끝났)')),
];

const List<String> chatSuggestions = [
  '이체가 왜 안 돼?',
  'OTP 등록했는데 아직 안 돼요.',
  '이체한도 어디서 바꿔?',
  '150만원 보내고 싶어.',
  '고객확인은 어떻게 해?',
  '계속 오류가 나는데 어떻게 해야 해?',
];

class Intent {
  const Intent({required this.id, required this.label, required this.score});

  final String id;
  final String label;
  final int score;

  Map<String, Object?> toJson() => {'id': id, 'label': label, 'score': score};

  factory Intent.fromJson(Map<String, Object?> j) =>
      Intent(id: j['id'] as String, label: j['label'] as String? ?? '', score: (j['score'] as num?)?.toInt() ?? 0);
}

class Analysis {
  const Analysis({
    required this.mode,
    required this.raw,
    required this.normalized,
    required this.intents,
    required this.amount,
    required this.claims,
  });

  final String mode;
  final String raw;
  final String normalized;
  final List<Intent> intents;
  final int? amount;
  final Map<String, bool> claims;

  List<String> get intentIds => intents.map((i) => i.id).toList();
}

String normalize(String? text) {
  var t = (text ?? '').toLowerCase();
  t = t.replaceAllMapped(RegExp(r'(\d),(?=\d)'), (m) => m[1]!);
  t = t.replaceAll(RegExp(r'오티피|o\s*t\s*p'), 'otp');
  t = t.replaceAll(RegExp(r'''[?!.,~…"'“”‘’()\[\]{}]'''), ' ');
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t;
}

int _parseKoreanNumber(String s) {
  const digits = {'일': 1, '이': 2, '삼': 3, '사': 4, '오': 5, '육': 6, '칠': 7, '팔': 8, '구': 9};
  const units = {'십': 10, '백': 100, '천': 1000};
  var total = 0;
  var num = 0;
  for (final rune in s.runes) {
    final ch = String.fromCharCode(rune);
    if (digits.containsKey(ch)) {
      num = digits[ch]!;
    } else if (units.containsKey(ch)) {
      total += (num == 0 ? 1 : num) * units[ch]!;
      num = 0;
    }
  }
  return total + num;
}

/// "150만원", "1,500,000원", "백오십만원" -> 1500000
int? extractAmount(String normalized) {
  var m = RegExp(r'(\d+(?:\.\d+)?)\s*만\s*원?').firstMatch(normalized);
  if (m != null) return (double.parse(m[1]!) * 10000).round();
  m = RegExp(r'(\d{4,})\s*원').firstMatch(normalized);
  if (m != null) return int.parse(m[1]!);
  m = RegExp(r'([일이삼사오육칠팔구십백천]+)\s*만\s*원?').firstMatch(normalized);
  if (m != null) {
    final v = _parseKoreanNumber(m[1]!);
    if (v > 0) return v * 10000;
  }
  return null;
}

Analysis analyze(String text) {
  final normalized = normalize(text);
  final intents = <Intent>[];
  for (final rule in _intentRules) {
    if (rule.fallbackOnly) continue;
    final hits = rule.patterns.where((p) => p.hasMatch(normalized)).length;
    if (hits > 0) intents.add(Intent(id: rule.id, label: intentLabels[rule.id]!, score: hits));
  }
  if (intents.isEmpty) {
    final help = _intentRules.firstWhere((r) => r.id == 'GENERAL_HELP');
    if (help.patterns.any((p) => p.hasMatch(normalized))) {
      intents.add(Intent(id: 'GENERAL_HELP', label: intentLabels['GENERAL_HELP']!, score: 1));
    }
  }
  final claims = <String, bool>{};
  for (final c in _claimRules) {
    if (c.pattern.hasMatch(normalized)) claims[c.fact] = true;
  }
  final amount = extractAmount(normalized);
  if (intents.isEmpty && amount != null) {
    intents.add(Intent(id: 'TRANSFER_FAILURE', label: intentLabels['TRANSFER_FAILURE']!, score: 1));
  }
  if (intents.isEmpty) intents.add(Intent(id: 'UNKNOWN', label: intentLabels['UNKNOWN']!, score: 0));
  return Analysis(mode: nluMode, raw: text, normalized: normalized, intents: intents, amount: amount, claims: claims);
}

String countWord(int n) {
  const words = ['', '한', '두', '세', '네', '다섯'];
  return (n >= 0 && n < words.length) ? words[n] : '$n';
}
