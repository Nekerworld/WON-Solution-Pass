/// 자산관리 상담의 계산·판단 규칙 (AI가 아닌 코드).
/// - 현재 고객 정보 저장소: 항목별 값·출처·근거와 변경(정정) 이력을 대화 기록과 별도로 관리한다.
/// - 고정 공식 지표: 같은 입력이면 항상 같은 값을 낸다.
/// - 상담 목적별 필수 정보, 부족·모순 판단, 질문 한도, 제안 가능 여부.
/// 공식과 기준값은 시연용 가정이다.
library;

import 'dart:math' as math;

import 'bank_state.dart';
import 'formatters.dart';
import 'scenario.dart';

class ItemDef {
  const ItemDef(this.label, [this.kind = 'won']);
  final String label;
  final String kind;
}

const Map<String, ItemDef> items = {
  'monthlyIncome': ItemDef('월 소득(세후)'),
  'monthlyExpense': ItemDef('월 지출'),
  'liquidAssets': ItemDef('예금성 자산'),
  'investAssets': ItemDef('투자 자산'),
  'debt': ItemDef('부채 잔액'),
  'debtPayment': ItemDef('월 부채 상환액'),
  'goalAmount': ItemDef('목표 금액'),
  'goalMonths': ItemDef('목표 기간', 'months'),
  'plannedLumpSum': ItemDef('예정된 목돈 지출'),
  'monthlySavingPref': ItemDef('희망 월 적립액'),

  /// 남는 돈 중 투자에 쓸 비율(%). 고객이 고른 값만 쓴다.
  'investPace': ItemDef('투자 속도', 'pace'),
};

String itemLabel(String k) => items[k]?.label ?? k;

class PurposeDef {
  const PurposeDef({required this.label, required this.critical, required this.important, required this.minimum, required this.tags});
  final String label;
  final List<String> critical;
  final List<String> important;

  /// 이 값이 없으면 제한적 제안도 하지 않는다
  final List<String> minimum;
  final List<String> tags;
}

const Map<String, PurposeDef> purposes = {
  'INVEST': PurposeDef(
    label: '해외주식 투자 시작',
    critical: ['monthlyIncome', 'monthlyExpense', 'liquidAssets'],
    important: ['investPace', 'investAssets', 'plannedLumpSum'],
    minimum: ['monthlyIncome', 'monthlyExpense'],
    tags: ['해외주식'],
  ),
  'GOAL_SAVING': PurposeDef(
    label: '목돈 마련',
    critical: ['monthlyIncome', 'monthlyExpense', 'goalAmount', 'goalMonths'],
    important: ['plannedLumpSum', 'liquidAssets'],
    minimum: ['monthlyIncome', 'monthlyExpense', 'goalMonths'],
    tags: ['목돈 마련'],
  ),
  'EMERGENCY': PurposeDef(
    label: '비상자금 점검',
    critical: ['monthlyExpense', 'liquidAssets'],
    important: ['monthlyIncome'],
    minimum: ['monthlyExpense'],
    tags: ['비상자금'],
  ),
  'ORIENT': PurposeDef(
    label: '계좌 정보로 시작',
    critical: ['monthlyExpense', 'liquidAssets'],
    important: ['monthlyIncome'],
    minimum: ['monthlyExpense'],
    tags: [],
  ),
};

PurposeDef purposeOf(String? id) => purposes[id] ?? purposes['GOAL_SAVING']!;

class AssetQuestion {
  const AssetQuestion({required this.id, required this.key, required this.text, required this.why, required this.options});
  final String id;
  final String key;
  final String text;
  final String why;
  final List<(String, int)> options;
}

/// 질문 목록. 생활 언어와 범위 답변을 허용한다.
const Map<String, AssetQuestion> questions = {
  'goalAmount': AssetQuestion(
    id: 'Q_GOAL_AMOUNT',
    key: 'goalAmount',
    text: '목표 금액이 어느 정도인가요?',
    why: '필요한 월 적립액을 계산하려면 목표 금액이 필요해요.',
    options: [('2천만원 정도', 20000000), ('3천만원 정도', 30000000), ('5천만원 정도', 50000000)],
  ),
  'goalMonths': AssetQuestion(
    id: 'Q_GOAL_MONTHS',
    key: 'goalMonths',
    text: '언제까지 모으고 싶으세요?',
    why: '기간에 따라 매달 모아야 할 금액이 달라져요.',
    options: [('1년 안에', 12), ('2년 안에', 24), ('3년 안에', 36)],
  ),
  'plannedLumpSum': AssetQuestion(
    id: 'Q_LUMP_SUM',
    key: 'plannedLumpSum',
    text: '앞으로 결혼·이사·경조사처럼 목돈이 나갈 일이 예정돼 있나요?',
    why: '부채가 없어도 큰 지출이 예정돼 있으면 모으거나 투자할 수 있는 금액이 달라져요.',
    options: [('없어요', 0), ('경조사 300만원 정도', 3000000), ('1천만원 정도', 10000000)],
  ),
  'monthlyIncome': AssetQuestion(
    id: 'Q_INCOME',
    key: 'monthlyIncome',
    text: '한 달에 손에 쥐는 소득(세후)이 어느 정도인가요?',
    why: '연결된 기관에서 소득을 확인하지 못했어요. 매달 모을 수 있는 금액을 계산하는 데 필요해요.',
    options: [('250만원 정도', 2500000), ('300만원 정도', 3000000), ('350만원 정도', 3500000)],
  ),
  'monthlyExpense': AssetQuestion(
    id: 'Q_EXPENSE',
    key: 'monthlyExpense',
    text: '한 달 생활비는 보통 얼마 정도 쓰세요?',
    why: '연결된 기관에서 지출을 확인하지 못했어요.',
    options: [('150만원 정도', 1500000), ('200만원 정도', 2000000), ('250만원 정도', 2500000)],
  ),
  'investPace': AssetQuestion(
    id: 'Q_PACE',
    key: 'investPace',
    text: '투자는 얼마나 공격적으로 하고 싶으세요?',
    why: '남는 돈 중에서 투자에 쓸 비율을 정하는 데 필요해요.',
    options: [('조금만', 30), ('보통으로', 50), ('공격적으로', 90)],
  ),
  'investAssets': AssetQuestion(
    id: 'Q_INVEST',
    key: 'investAssets',
    text: '지금 다른 증권사에서 투자하고 있는 돈이 있나요?',
    why: '연결되지 않은 증권사 정보는 확인하지 못했어요. 이미 투자 중인 돈이 많으면 새로 투자할 금액을 줄여야 해요.',
    options: [('없어요', 0), ('500만원 정도', 5000000), ('1천만원 이상', 10000000)],
  ),
  'liquidAssets': AssetQuestion(
    id: 'Q_LIQUID',
    key: 'liquidAssets',
    text: '바로 꺼내 쓸 수 있는 예금·현금은 어느 정도 있으세요?',
    why: '비상자금을 남겨 두고 목표에 쓸 수 있는 돈을 계산하는 데 필요해요.',
    options: [('500만원 정도', 5000000), ('1천만원 정도', 10000000), ('2천만원 정도', 20000000)],
  ),
};

/* ------------------------------------------------------------------
 * 현재 고객 정보 저장소
 * ------------------------------------------------------------------ */

class InfoItem {
  InfoItem({required this.value, required this.source, required this.basis, required this.updatedAt});
  int? value;
  String source;
  String basis;
  int updatedAt;

  Json toJson() => {'value': value, 'source': source, 'basis': basis, 'updatedAt': updatedAt};
  factory InfoItem.fromJson(Json j) => InfoItem(
        value: asInt(j['value']),
        source: j['source'] as String? ?? 'UNKNOWN',
        basis: j['basis'] as String? ?? '',
        updatedAt: asInt(j['updatedAt']) ?? 0,
      );
}

class InfoChange {
  const InfoChange({
    required this.at,
    required this.key,
    required this.from,
    required this.fromSource,
    required this.to,
    required this.toSource,
    required this.reason,
    required this.correction,
  });

  final int at;
  final String key;
  final int? from;
  final String? fromSource;
  final int? to;
  final String toSource;
  final String reason;
  final bool correction;

  Json toJson() => {
        'at': at,
        'key': key,
        'from': from,
        'fromSource': fromSource,
        'to': to,
        'toSource': toSource,
        'reason': reason,
        'correction': correction,
      };

  factory InfoChange.fromJson(Json j) => InfoChange(
        at: asInt(j['at']) ?? 0,
        key: j['key'] as String? ?? '',
        from: asInt(j['from']),
        fromSource: j['fromSource'] as String?,
        to: asInt(j['to']),
        toSource: j['toSource'] as String? ?? 'UNKNOWN',
        reason: j['reason'] as String? ?? '',
        correction: j['correction'] == true,
      );
}

class AssetInfo {
  AssetInfo({required this.items, required this.history, required this.declined});

  final Map<String, InfoItem> items;
  final List<InfoChange> history;
  final List<String> declined;

  Json toJson() => {
        'items': items.map((k, v) => MapEntry(k, v.toJson())),
        'history': history.map((h) => h.toJson()).toList(),
        'declined': declined,
      };

  static AssetInfo? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = asJson(v);
    return AssetInfo(
      items: asJson(j['items']).map((k, v) => MapEntry(k, InfoItem.fromJson(asJson(v)))),
      history: asList(j['history']).map((h) => InfoChange.fromJson(asJson(h))).toList(),
      declined: asStrings(j['declined']),
    );
  }
}

int _now() => DateTime.now().millisecondsSinceEpoch;

AssetInfo createInfo(Map<String, FinItem>? snapshot) {
  final out = <String, InfoItem>{};
  for (final k in items.keys) {
    final src = snapshot?[k];
    out[k] = src != null
        ? InfoItem(value: src.value, source: src.source, basis: src.basis, updatedAt: _now())
        : InfoItem(value: null, source: 'UNKNOWN', basis: '아직 확인하지 않음', updatedAt: _now());
  }
  return AssetInfo(items: out, history: [], declined: []);
}

/// 값 갱신. 이전 값이 있으면 정정 이력으로 남긴다.
void setItem(AssetInfo info, String key, int? value, String source, [String reason = '']) {
  final prev = info.items[key];
  info.history.add(InfoChange(
    at: _now(),
    key: key,
    from: prev?.value,
    fromSource: prev?.source,
    to: value,
    toSource: source,
    reason: reason,
    correction: prev != null && prev.value != null && prev.value != value,
  ));
  info.items[key] = InfoItem(value: value, source: source, basis: reason, updatedAt: _now());
  info.declined.remove(key);
}

/// '모름·답변 거부'는 값을 지우지 않고 미확인으로 기록한다
void markDeclined(AssetInfo info, String key, String kind) {
  if (!info.declined.contains(key)) info.declined.add(key);
  final it = info.items[key]!;
  info.history.add(InfoChange(
    at: _now(),
    key: key,
    from: it.value,
    fromSource: null,
    to: it.value,
    toSource: it.source,
    reason: kind == 'REFUSED' ? '답변 거부' : '모름',
    correction: false,
  ));
}

bool known(AssetInfo info, String key) => info.items[key]?.value != null;
int? val(AssetInfo info, String key) => known(info, key) ? info.items[key]!.value : null;

/// 3.8 → "3.8", 4.0 → "4"
String numText(num v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

/// 투자 속도는 0~100%만 유효하다. 만원 단위로 잘못 저장된 값은 100%로 자른다.
int? pacePercent(num? value) => value?.round().clamp(0, 100);

/// 투자 속도(%)의 짧은 이름. 90 이상은 공격적이다.
String paceName(num pct) => pct >= 90 ? '공격적' : (pct >= 50 ? '보통' : '조금만');

String display(String key, num? value) {
  if (value == null) return '미확인';
  final kind = items[key]?.kind;
  if (kind == 'months') return value % 12 == 0 ? '${(value / 12).round()}년' : '${numText(value)}개월';
  if (kind == 'pace') {
    final pct = pacePercent(value)!;
    return '${paceName(pct)} · $pct%';
  }
  return formatMan(value);
}

String _withRo(String w) => josa(w, '로');

/* ------------------------------------------------------------------
 * 고정 공식 지표
 * ------------------------------------------------------------------ */

// 부동소수 오차(1400000 × 0.7 = 979999.99…)로 만원 단위가 한 칸 밀리지 않도록 원 단위로 먼저 맞춘다
int _roundDown(num v) => (v.round() / 10000).floor() * 10000;
int _roundUp(num v) => (v.round() / 10000).ceil() * 10000;

/// 화면에 보일 큰 금액은 만원 단위로 맞춘다 (예: 30,262,400원 → 3,026만원)
int roundMan(num? v) => (math.max(0, v ?? 0) / 10000).round() * 10000;

class Metric {
  const Metric({
    required this.key,
    required this.label,
    required this.value,
    required this.text,
    required this.formula,
    required this.inputs,
    required this.uncertain,
    this.share,
    this.shareKnown = false,
  });
  final String key;
  final String label;
  final num? value;
  final String text;
  final String formula;
  final List<String> inputs;
  final List<String> uncertain;

  /// 월 투자 금액에만 있다: 남는 돈 중 투자 비율(%)과 고객이 고른 값인지
  final int? share;
  final bool shareKnown;
}

class Metrics {
  const Metrics({required this.list, required this.byKey, required this.feasible});
  final List<Metric> list;
  final Map<String, Metric> byKey;
  final bool? feasible;

  Metric operator [](String k) => byKey[k]!;
}

Metrics computeMetrics(AssetInfo info) {
  final inc = val(info, 'monthlyIncome');
  final exp = val(info, 'monthlyExpense');
  final dp = val(info, 'debtPayment') ?? 0;
  final liq = val(info, 'liquidAssets');
  final goal = val(info, 'goalAmount');
  final months = val(info, 'goalMonths');
  final lump = val(info, 'plannedLumpSum');
  final pref = val(info, 'monthlySavingPref');
  List<String> uncertainOf(List<String> keys) =>
      [for (final k in keys) if (!known(info, k) || info.items[k]!.source == 'ESTIMATED' || info.items[k]!.source == 'UNKNOWN') k];
  final list = <Metric>[];
  void add(String key, String label, num? value, String formula, List<String> inputs,
          [String Function(num)? fmt, int? share, bool shareKnown = false]) =>
      list.add(Metric(
        key: key,
        label: label,
        value: value,
        text: value == null ? '계산 불가' : (fmt != null ? fmt(value) : formatMan(value)),
        formula: formula,
        inputs: inputs,
        uncertain: uncertainOf(inputs),
        share: share,
        shareKnown: shareKnown,
      ));

  final surplus = inc != null && exp != null ? inc - exp - dp : null;
  add('surplus', '월 여유자금', surplus, '월 소득 − 월 지출 − 월 부채 상환액', ['monthlyIncome', 'monthlyExpense', 'debtPayment']);
  final emergency = liq != null && exp != null && exp != 0 ? (liq / exp * 10).round() / 10 : null;
  add('emergencyMonths', '비상자금 보유 개월', emergency, '예금성 자산 ÷ 월 지출', ['liquidAssets', 'monthlyExpense'], (v) => '${numText(v)}개월');
  final reserve = exp != null ? exp * Policy.emergencyMonths : null;
  add('reserve', '남겨 둘 비상자금', reserve, '월 지출 × ${Policy.emergencyMonths}개월', ['monthlyExpense']);
  final int? usable = liq != null && reserve != null ? math.max(0, liq - reserve) : (liq != null ? null : 0);
  add('usableForGoal', '목표에 쓸 수 있는 예금', usable, 'max(0, 예금성 자산 − 남겨 둘 비상자금)', ['liquidAssets', 'monthlyExpense']);
  final target = goal != null ? goal + (lump ?? 0) : null;
  add('target', '모아야 할 총액', target, '목표 금액 + 예정된 목돈 지출', ['goalAmount', 'plannedLumpSum']);
  final need = target != null && months != null && months != 0 ? _roundUp(math.max(0, target - (usable ?? 0)) / months) : null;
  add('needMonthly', '필요 월 적립액', need, '(모아야 할 총액 − 목표에 쓸 예금) ÷ 목표 기간', ['goalAmount', 'plannedLumpSum', 'liquidAssets', 'goalMonths']);
  final capacity = surplus != null ? _roundDown(math.max(0, surplus) * 0.7) : null;
  add('capacity', '무리 없는 월 적립 여력', capacity, '월 여유자금 × 70%', ['monthlyIncome', 'monthlyExpense', 'debtPayment']);
  final pace = pacePercent(val(info, 'investPace'));
  final share = pace ?? 30;
  final invest = surplus != null ? _roundDown(math.max(0, surplus) * share / 100) : null;
  add('investMonthly', '월 투자 시작 금액', invest, '월 여유자금 × $share%${pace != null ? ' (고객이 고른 투자 속도)' : ' (투자 속도를 아직 모름)'}',
      ['monthlyIncome', 'monthlyExpense', 'debtPayment', 'investPace'], null, share, pace != null);
  int? rec;
  if (pref != null) {
    rec = pref;
  } else if (capacity != null) {
    rec = need != null ? math.min(need, capacity) : capacity;
  }
  add('recommendedMonthly', '제안 월 적립액', rec, pref != null ? '고객 희망 월 적립액' : 'min(필요 월 적립액, 월 적립 여력)',
      pref != null ? ['monthlySavingPref'] : ['goalAmount', 'monthlyIncome', 'monthlyExpense']);
  final expected = rec != null && months != null && months != 0 ? rec * months + (usable ?? 0) : null;
  add('expectedAmount', '기간 종료 시 예상 금액', expected, '제안 월 적립액 × 목표 기간 + 목표에 쓸 예금 (이자 제외)', ['goalMonths', 'liquidAssets']);

  return Metrics(
    list: list,
    byKey: {for (final m in list) m.key: m},
    feasible: need != null && capacity != null ? need <= capacity : null,
  );
}

/* ------------------------------------------------------------------
 * 부족·모순 판단, 질문, 제안 가능 여부
 * ------------------------------------------------------------------ */

class Gap {
  const Gap({required this.key, required this.level, required this.question, this.note});
  final String key;

  /// critical | important | contradiction
  final String level;
  final String? question;
  final String? note;
}

List<Gap> findGaps(AssetInfo info, String purposeId, Metrics? metrics) {
  final p = purposeOf(purposeId);
  bool skip(String k) => known(info, k) || info.declined.contains(k);
  final gaps = <Gap>[
    for (final k in p.critical)
      if (!skip(k)) Gap(key: k, level: 'critical', question: questions[k]?.id),
    for (final k in p.important)
      if (!skip(k)) Gap(key: k, level: 'important', question: questions[k]?.id),
  ];
  final sur = metrics?['surplus'].value;
  if (sur != null && sur <= 0 && info.items['monthlyExpense']!.source == 'ESTIMATED' && !info.declined.contains('monthlyExpense')) {
    gaps.insert(
      0,
      Gap(key: 'monthlyExpense', level: 'contradiction', question: questions['monthlyExpense']!.id, note: '추정 지출이 소득보다 많아요. 일시적인 큰 지출이 포함됐을 수 있어요.'),
    );
  }
  return gaps;
}

AssetQuestion? questionFor(Gap g) => questions[g.key];

bool canAsk({required int questionsAsked, required bool stopRequested, required List<Gap> gaps}) =>
    questionsAsked < Policy.assetQuestionLimit && !stopRequested && gaps.any((g) => questionFor(g) != null);

/// 현재 정보로 제안할 수 있는가: 최소 정보가 있어야 제한적 제안이 가능하다
({bool ok, List<String> missing}) proposable(AssetInfo info, String purposeId) {
  final missing = [for (final k in purposeOf(purposeId).minimum) if (!known(info, k)) k];
  return (ok: missing.isEmpty, missing: missing);
}

class Alternative {
  const Alternative({required this.id, required this.label, required this.detail, required this.apply, this.message});
  final String id;
  final String label;
  final String detail;
  final Map<String, int> apply;

  /// 고르면 AI가 대신 말할 문장 (비상자금부터: 몇 개월이면 채워지는지)
  final String? message;

  Json toJson() => {'id': id, 'label': label, 'detail': detail, 'apply': apply, if (message != null) 'message': message};
  factory Alternative.fromJson(Json j) => Alternative(
        id: j['id'] as String? ?? '',
        label: j['label'] as String? ?? '',
        detail: j['detail'] as String? ?? '',
        apply: asJson(j['apply']).map((k, v) => MapEntry(k, asInt(v) ?? 0)),
        message: j['message'] as String?,
      );
}

/// 제안 재료 (문장은 AI가 만든다)
class ProposalBasis {
  const ProposalBasis({
    required this.purposeId,
    required this.purpose,
    required this.tags,
    required this.monthly,
    required this.months,
    required this.feasible,
    required this.alternatives,
    required this.uncertain,
    required this.estimated,
    required this.unconfirmed,
  });

  final String purposeId;
  final String purpose;
  final List<String> tags;
  final int? monthly;
  final int? months;
  final bool? feasible;
  final List<Alternative> alternatives;
  final List<String> uncertain;
  final List<String> estimated;
  final List<String> unconfirmed;

  Json toJson() => {
        'purposeId': purposeId,
        'purpose': purpose,
        'tags': tags,
        'monthly': monthly,
        'months': months,
        'feasible': feasible,
        'alternatives': alternatives.map((a) => a.toJson()).toList(),
        'uncertain': uncertain,
        'estimated': estimated,
        'unconfirmed': unconfirmed,
      };

  static ProposalBasis? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = asJson(v);
    return ProposalBasis(
      purposeId: j['purposeId'] as String? ?? 'GOAL_SAVING',
      purpose: j['purpose'] as String? ?? '',
      tags: asStrings(j['tags']),
      monthly: asInt(j['monthly']),
      months: asInt(j['months']),
      feasible: j['feasible'] as bool?,
      alternatives: asList(j['alternatives']).map((a) => Alternative.fromJson(asJson(a))).toList(),
      uncertain: asStrings(j['uncertain']),
      estimated: asStrings(j['estimated']),
      unconfirmed: asStrings(j['unconfirmed']),
    );
  }
}

ProposalBasis proposalBasis(AssetInfo info, String purposeId, Metrics metrics) {
  final months = val(info, 'goalMonths');
  final p = purposeOf(purposeId);
  final alternatives = <Alternative>[];
  if (metrics.feasible == false && months != null && months != 0) {
    final longer = months + 12;
    final usable = (metrics['usableForGoal'].value ?? 0).round();
    final needLonger = _roundUp(math.max(0, metrics['target'].value!.round() - usable) / longer);
    final lowered = _roundDown((metrics['capacity'].value ?? 0) * months + usable - (val(info, 'plannedLumpSum') ?? 0));
    alternatives.add(Alternative(
      id: 'LONGER',
      label: '기간을 ${_withRo(display('goalMonths', longer))} 늘릴게요',
      detail: '매달 ${formatMan(needLonger)}씩 모으면 돼요',
      apply: {'goalMonths': longer},
    ));
    alternatives.add(Alternative(
      id: 'LOWER_GOAL',
      label: '목표 금액을 ${_withRo(formatMan(lowered))} 줄일게요',
      detail: '지금 여유로 기간 안에 모을 수 있는 금액이에요',
      apply: {'goalAmount': lowered},
    ));
  }
  final em = metrics['emergencyMonths'];
  if (em.value != null && em.value! < Policy.emergencyMonths) {
    // 비상자금을 채우는 기간: 남겨 둘 금액과 지금 예금의 차이를 월 적립 여력으로 나눈다
    final gap = math.max(0, (metrics['reserve'].value ?? 0) - (val(info, 'liquidAssets') ?? 0));
    final save = metrics['capacity'].value ?? 0;
    final fill = save > 0 && gap > 0
        ? '매달 ${formatMan(save)}씩 예금에 모으면 ${(gap / save).ceil()}개월이면 생활비 ${Policy.emergencyMonths}개월치가 채워져요.'
        : '지금 여유로는 비상자금을 채우기 어려워요. 지출을 먼저 줄여 보세요.';
    alternatives.add(Alternative(
      id: 'EMERGENCY_FIRST',
      label: '비상자금부터 채울게요',
      detail: '생활비 ${Policy.emergencyMonths}개월치가 기준인데, 지금은 ${em.text}치예요',
      apply: const {},
      message: fill,
    ));
  }
  final watched = [...p.critical, ...p.important];
  final uncertain = [
    for (final k in info.items.keys)
      if (watched.contains(k) && (!known(info, k) || (info.items[k]!.source != 'STATED' && info.items[k]!.source != 'BANK'))) k,
  ];
  final invest = purposeId == 'INVEST';
  final accountLook = purposeId == 'EMERGENCY' || purposeId == 'ORIENT';
  return ProposalBasis(
    purposeId: purposes.containsKey(purposeId) ? purposeId : 'GOAL_SAVING',
    purpose: p.label,
    tags: p.tags,
    monthly: (invest ? metrics['investMonthly'].value : (accountLook ? null : metrics['recommendedMonthly'].value))?.round(),
    months: invest || accountLook ? null : months,
    feasible: metrics.feasible,
    alternatives: alternatives,
    uncertain: uncertain,
    estimated: [for (final k in uncertain) if (known(info, k)) k],
    unconfirmed: [for (final k in uncertain) if (!known(info, k)) k],
  );
}

/* ------------------------------------------------------------------
 * 고객에게 보여 줄 큰 숫자 (한 번에 3개까지)
 * ------------------------------------------------------------------ */

class Figure {
  const Figure({required this.label, required this.value, this.note = '', this.tone = ''});
  final String label;
  final String value;
  final String note;

  /// '' | 'warning'
  final String tone;

  Json toJson() => {'label': label, 'value': value, 'note': note, 'tone': tone};
  factory Figure.fromJson(Json j) => Figure(
        label: j['label'] as String? ?? '',
        value: j['value'] as String? ?? '',
        note: j['note'] as String? ?? '',
        tone: j['tone'] as String? ?? '',
      );
}

List<Figure> interpretFigures(Metrics metrics, String purposeId) {
  final figs = <Figure>[];
  void add(String label, Metric m, String value, [String note = '', String tone = '']) {
    if (m.value != null) figs.add(Figure(label: label, value: value, note: note, tone: tone));
  }

  final em = Policy.emergencyMonths;
  add('매달 남는 돈', metrics['surplus'], '월 ${metrics['surplus'].text}');
  if (purposeId == 'EMERGENCY') {
    add('바로 쓸 수 있는 예금', metrics['emergencyMonths'], '생활비 ${metrics['emergencyMonths'].text}치');
    add('남겨 둘 비상자금', metrics['reserve'], metrics['reserve'].text);
    return figs;
  }
  if (purposeId == 'INVEST') {
    final v = metrics['emergencyMonths'].value;
    final low = v != null && v < em;
    add('바로 쓸 수 있는 예금', metrics['emergencyMonths'], '생활비 ${metrics['emergencyMonths'].text}치', '', low ? 'warning' : '');
    return figs;
  }
  add('무리 없이 모을 수 있는 돈', metrics['capacity'], '월 ${metrics['capacity'].text}');
  final need = metrics['needMonthly'].value, cap = metrics['capacity'].value;
  final short = need != null && cap != null ? need - cap : null;
  final over = short != null && short > 0;
  add('목표까지 매달 필요한 돈', metrics['needMonthly'], '월 ${metrics['needMonthly'].text}', over ? '여유보다 매달 ${formatMan(short)} 더 필요해요' : '',
      over ? 'warning' : '');
  return figs;
}

List<Figure> proposalFigures(ProposalBasis basis, Metrics metrics) {
  final monthly = basis.monthly;
  if (monthly == null) return [];
  if (basis.purposeId == 'INVEST') {
    final pace = metrics['investMonthly'];
    final sur = metrics['surplus'];
    final note = pace.share != null && sur.value != null
        ? '${pace.shareKnown ? paceName(pace.share!) : '속도를 아직 몰라'} · 남는 ${sur.text}의 ${pace.share}%'
        : '';
    const months = Policy.emergencyMonths;
    return [
      Figure(label: '매달 투자할 돈', value: '월 ${formatMan(monthly)}', note: note),
      if (metrics['reserve'].value != null)
        Figure(label: '예금으로 남길 돈', value: metrics['reserve'].text, note: '$months개월치 지출이에요.\n최소 $months개월치의 예금은 유지하시는걸 추천해요.'),
    ];
  }
  final figs = [Figure(label: '매달 모을 돈', value: '월 ${formatMan(monthly)}')];
  if (basis.months != null && basis.months != 0) figs.add(Figure(label: '모으는 기간', value: display('goalMonths', basis.months)));
  final exp = metrics['expectedAmount'].value;
  if (exp != null) {
    final t = metrics['target'].value;
    final short = t != null ? t - exp : null;
    final over = short != null && short > 0;
    figs.add(Figure(
      label: '기간이 끝나면',
      value: '약 ${formatMan(roundMan(exp))}',
      note: over ? '목표보다 ${formatMan(roundMan(short))} 적어요' : '',
      tone: over ? 'warning' : '',
    ));
  }
  return figs;
}

class ProductMatch {
  const ProductMatch({required this.productId, required this.notes, required this.fit});
  final String productId;
  final List<String> notes;
  final bool fit;
}

/// 서비스 탐색: 상담 목적·기간에 맞는 상품. 선택은 고객이 한다.
List<ProductMatch> matchProducts({required List<String> tags, required int? monthly, required int? months}) {
  final out = <ProductMatch>[];
  for (final p in products) {
    if (!p.goalTags.any(tags.contains)) continue;
    if (p.isBrokerage) {
      out.add(ProductMatch(productId: p.id, notes: ['${p.markets.join('·')} 주식 거래', '원화·외화 계좌 연결'], fit: true));
      continue;
    }
    final periodFit = months != null && months != 0 && p.periods.isNotEmpty ? (p.periods.contains(months) || p.periods.any((x) => x >= months)) : false;
    final amountFit = monthly != null && p.maxMonthly != 0 ? monthly <= p.maxMonthly : false;
    final notes = <String>[];
    if (p.periods.isNotEmpty) {
      notes.add(periodFit ? '목표 기간(${display('goalMonths', months)})으로 가입 가능' : '가입 기간 ${p.periods.map((x) => display('goalMonths', x)).join('·')}');
    }
    if (p.maxMonthly != 0 && monthly != null) notes.add(amountFit ? '월 ${formatMan(monthly)} 적립 가능' : '월 최대 ${formatMan(p.maxMonthly)}');
    if (p.periods.isEmpty) notes.add('언제든 입출금 가능');
    out.add(ProductMatch(productId: p.id, notes: notes, fit: periodFit && (amountFit || p.maxMonthly == 0)));
  }
  return out;
}
