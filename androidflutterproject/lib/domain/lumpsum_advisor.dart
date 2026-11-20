/// 목돈 불리기 상담의 순수 계산. 화면 문장에 쓰는 숫자는 이 결과만 쓴다.
/// 대출 가능 여부는 계산하지 않는다. 있는 부채의 상환액만 뺀다.
library;

import 'dart:math' as math;

import 'asset_advisor.dart' show Figure, numText;
import 'bank_state.dart';
import 'formatters.dart';

const double savingsRate = 0.032;

/// 투자 몫의 기대 수익(가정). 화면에는 "연 6%로 가정"이라고 밝힌다
const double investAssumedRate = 0.06;
const double debtRate = 0.055;
const int debtMonths = 60;
const int emergencyMin = 3;
const int depositDefault = 8482400;

/// JS Math.round와 같게 반올림한다 (음수의 .5는 0 쪽으로)
int jsRound(num v) => (v + 0.5).floor();

class LumpGoal {
  const LumpGoal({required this.amount, required this.months, required this.text, this.assumed = false});
  final int amount;
  final int months;
  final String text;

  /// 금액만 말해서 기간을 3년으로 가정했는지
  final bool assumed;

  Json toJson() => {'amount': amount, 'months': months, 'text': text, if (assumed) 'assumed': true};
  static LumpGoal? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = asJson(v);
    return LumpGoal(amount: asInt(j['amount']) ?? 0, months: asInt(j['months']) ?? 36, text: j['text'] as String? ?? '', assumed: j['assumed'] == true);
  }
}

const Map<String, LumpGoal> lumpGoals = {
  'goal-100': LumpGoal(amount: 100000000, months: 36, text: '3년 안에 1억 정도 만들고 싶어요'),
  'goal-50': LumpGoal(amount: 50000000, months: 60, text: '5년 안에 5천만 원 만들고 싶어요'),
  'goal-20': LumpGoal(amount: 20000000, months: 12, text: '1년 안에 2천만 원 만들고 싶어요'),
};

/// 선택지에 없는 목표를 직접 입력할 때 쓰는 문장
const LumpGoal goalTyped = LumpGoal(amount: 80000000, months: 36, text: '3년 안에 8천만 원 정도 만들고 싶어요');

const Map<String, String> experienceTexts = {
  'exp-0': '주식은 해본 적 없어요',
  'exp-1': '소액으로 ETF 조금 해봤어요',
  'exp-2': '국내주식은 자주 해요',
};

const Map<String, String> lossTexts = {
  'loss-0': '떨어지면 바로 팔 것 같아요',
  'loss-1': '불안하긴 한데 길게 보면 버틸 수 있을 것 같아요',
  'loss-2': '더 떨어지면 더 살 수 있어요',
};

int roundMan(num? n) => n == null || n.isNaN ? 0 : jsRound(n / 10000) * 10000;

/// 원리금 균등. 잔액이 없으면 0.
int debtPayment(num? balance) {
  final p = balance ?? 0;
  if (p <= 0) return 0;
  const r = debtRate / 12;
  final g = math.pow(1 + r, debtMonths);
  return jsRound(p * r * g / (g - 1));
}

double _grow(num amount, double annual, int months) => (amount * math.pow(1 + annual / 12, months)).toDouble();

double _annuityFv(num payment, double annual, int months) {
  if (months <= 0 || payment <= 0) return 0;
  final r = annual / 12;
  final g = math.pow(1 + r, months);
  return payment * (g - 1) / r;
}

double _annuityPmt(num target, double annual, int months) {
  if (months <= 0 || target <= 0) return 0;
  final r = annual / 12;
  final g = math.pow(1 + r, months);
  return target * r / (g - 1);
}

/// 월 납입과 예금으로 목표에 닿는 최소 연 수익. 적금 금리로 되면 0.
double requiredYield(num payment, num deposit, int months, num goal) {
  final plain = payment * months + deposit;
  if (plain >= goal) return 0;
  var lo = 0.0, hi = 1.2;
  for (var i = 0; i < 48; i++) {
    final mid = (lo + hi) / 2;
    final fv = _annuityFv(payment, mid, months) + _grow(deposit, mid, months);
    if (fv >= goal) {
      hi = mid;
    } else {
      lo = mid;
    }
  }
  return hi;
}

int _experienceScore(String? text) {
  final t = text ?? '';
  if (t.contains('자주')) return 2;
  if (RegExp(r'없어요|해본 적 없').hasMatch(t)) return 0;
  return 1;
}

int _lossScore(String? text) {
  final t = text ?? '';
  if (t.contains('바로 팔')) return 0;
  if (t.contains('더 살')) return 2;
  return 1;
}

class RiskProfile {
  const RiskProfile(this.id, this.experience, this.loss);

  /// STABLE | NEUTRAL | ACTIVE
  final String id;
  final int experience;
  final int loss;
}

/// 안정: 손실을 바로 줄이거나, 경험이 없고 버티기만 하는 경우.
/// 적극: 경험이 많고 하락 때 더 사는 경우.
/// 그 외는 중립. 기본 문장 쌍(ETF 소액, 장기 보유)은 중립.
RiskProfile inferRiskProfile(String? expText, String? lossText) {
  final e = _experienceScore(expText), l = _lossScore(lossText);
  var id = 'NEUTRAL';
  if (l == 0 || (e == 0 && l == 1)) {
    id = 'STABLE';
  } else if (e == 2 && l == 2) {
    id = 'ACTIVE';
  }
  return RiskProfile(id, e, l);
}

const Map<String, String> profileName = {'STABLE': '안정', 'NEUTRAL': '중립', 'ACTIVE': '적극'};
const Map<String, double> _profileShare = {'STABLE': 0.25, 'NEUTRAL': 0.45, 'ACTIVE': 0.65};
const Map<String, (int, int)> _profileSplit = {'STABLE': (70, 30), 'NEUTRAL': (55, 45), 'ACTIVE': (40, 60)};

class SpendCategory {
  const SpendCategory(this.label, this.ratio, this.amount);
  final String label;
  final double ratio;
  final int amount;

  Json toJson() => {'label': label, 'ratio': ratio, 'amount': amount};
  factory SpendCategory.fromJson(Json j) => SpendCategory(j['label'] as String? ?? '', (j['ratio'] as num?)?.toDouble() ?? 0, asInt(j['amount']) ?? 0);
}

const List<(String, double)> _categoryWeights = [
  ('식비', 0.28),
  ('주거·관리', 0.22),
  ('교통', 0.12),
  ('쇼핑', 0.15),
  ('문화·여가', 0.08),
  ('기타', 0.15),
];

List<SpendCategory> categories(int expense) {
  var used = 0;
  return [
    for (var i = 0; i < _categoryWeights.length; i++)
      () {
        final (label, ratio) = _categoryWeights[i];
        final amount = i == _categoryWeights.length - 1 ? math.max(0, expense - used) : jsRound(expense * ratio);
        used += amount;
        return SpendCategory(label, ratio, amount);
      }(),
  ];
}

Figure _fig(String label, String value, [String note = '', String tone = '']) => Figure(label: label, value: value, note: note, tone: tone);

/// 어림한 금액은 만원 단위로 맞추고 앞에 "약"을 붙인다. 0은 "0원", 음수는 "약 -10만원"
String about(num n) {
  final v = roundMan(n);
  if (v == 0) return '0원';
  return '약 ${v < 0 ? '-' : ''}${formatMan(v.abs())}';
}

/// 음수도 만원 단위로 쓴다. -100000 → "-10만원"
String manSigned(num n) => '${n < 0 ? '-' : ''}${formatMan(n.abs())}';

/// 부족하면 "약 24만원 부족", 아니면 about과 같다. 음수를 그대로 쓰지 않는다
String aboutGap(num n) {
  final v = roundMan(n);
  if (v < 0) return '약 ${formatMan(v.abs())} 부족';
  return about(v);
}

/// 줄이기 후보. 노력이 적게 드는 순서(effort)로 담는다.
/// rate는 해당 항목 지출에서 줄일 수 있는 비율이다. 주거·관리와 교통은 고정비라 후보가 아니다.
class CutDef {
  const CutDef(this.id, this.category, this.label, this.rate, this.effort, this.reason);
  final String id;
  final String category;
  final String label;
  final double rate;
  final int effort;
  final String reason;
}

const List<CutDef> cutPool = [
  CutDef('subs', '문화·여가', '구독 서비스 정리', 0.3, 1, '자주 안 쓰는 구독부터 정리하면 생활 불편이 거의 없어요'),
  CutDef('impulse', '쇼핑', '충동구매 줄이기', 0.3, 2, '월 후반에 몰려 있어서 줄이기 가장 쉬워요'),
  CutDef('delivery', '식비', '배달 횟수 줄이기', 0.1, 3, '배달을 조금만 줄여도 금액이 커요'),
  CutDef('small', '기타', '소액 결제 정리', 0.2, 4, '건별 금액은 작지만 모이면 커져요'),
];
const List<String> fixedCategories = ['주거·관리', '교통'];
const int _spareGoal = 100000;

class CutItem {
  const CutItem({required this.id, required this.category, required this.label, required this.reason, required this.amount, required this.saved, required this.trimmed});
  final String id;
  final String category;
  final String label;
  final String reason;
  final int amount;
  final int saved;
  final bool trimmed;
}

class SpendPlan {
  const SpendPlan({required this.items, required this.target, required this.total, required this.after});
  final List<CutItem> items;
  final int target;
  final int total;
  final int after;
  bool get enough => after > 0;
}

/// 지출 줄이기 계획. 부족한 금액에 여유 목표(10만원)를 더한 만큼만 줄인다.
/// 후보를 노력 순으로 담다가 필요한 금액에 닿으면 멈추고, 마지막 후보는 필요한 만큼으로 줄인다. 금액은 만원 단위다.
SpendPlan spendPlan(LumpAdvice a, [int? targetOverride]) {
  final target = targetOverride != null ? roundMan(math.max(0, targetOverride)) : roundMan(math.max(0, -a.surplus) + _spareGoal);
  final items = <CutItem>[];
  var total = 0;
  final pool = [...cutPool]..sort((x, y) => x.effort.compareTo(y.effort));
  for (final p in pool) {
    if (total >= target) break;
    final c = a.categories.where((x) => x.label == p.category).firstOrNull;
    if (c == null) continue;
    final full = roundMan(c.amount * p.rate);
    if (full <= 0) continue;
    final need = roundMan(target - total);
    final saved = math.min(full, need);
    if (saved <= 0) continue;
    items.add(CutItem(id: p.id, category: p.category, label: p.label, reason: p.reason, amount: c.amount, saved: saved, trimmed: saved < full));
    total += saved;
  }
  return SpendPlan(items: items, target: target, total: total, after: a.surplus + total);
}

class CutForYield {
  const CutForYield({required this.plan, required this.extra, required this.yieldBefore, required this.yieldAfter});
  final SpendPlan plan;
  final int extra;
  final double yieldBefore;
  final double yieldAfter;
}

/// 적금 + 투자 제안(MIX)에서 소비를 줄이면 필요한 연 수익이 얼마나 내려가는지 계산한다.
/// 줄일 목표는 적금만으로 목표를 메우는 데 부족한 월 저축액이고, 후보 풀이 담을 수 있는 만큼만 줄인다.
CutForYield? cutForYield(LumpAdvice a) {
  if (a.decisionId != 'MIX') return null;
  final save = math.max(0, a.surplus);
  final extra = roundMan(math.max(0, a.requiredMonthly - save));
  if (extra <= 0) return null;
  final plan = spendPlan(a, extra);
  if (plan.total <= 0) return null;
  return CutForYield(
    plan: plan,
    extra: extra,
    yieldBefore: requiredYield(save, a.deposit, a.goalMonths, a.goalAmount),
    yieldAfter: requiredYield(save + plan.total, a.deposit, a.goalMonths, a.goalAmount),
  );
}

/// 지난달 대비 증감(%). 이번 달 지출 = 지난달 × (1 + 증감)
const Map<String, int> monthChange = {'식비': 4, '주거·관리': 1, '교통': -2, '쇼핑': 12, '문화·여가': 9, '기타': -3};
const String insightSource = '최근 3개월 카드·계좌 거래 기준';

class InsightRow {
  const InsightRow({required this.label, required this.ratio, required this.amount, required this.prev, required this.changePct});
  final String label;
  final double ratio;
  final int amount;
  final int prev;
  final int changePct;
}

class SpendTag {
  const SpendTag(this.id, this.text);
  final String id;
  final String text;
  Json toJson() => {'id': id, 'text': text};
  factory SpendTag.fromJson(Json j) => SpendTag(j['id'] as String? ?? '', j['text'] as String? ?? '');
}

class SpendInsight {
  const SpendInsight({
    required this.rows,
    required this.tags,
    required this.weekendShare,
    required this.lateShopping,
    required this.subsCount,
    required this.subsAmount,
    required this.deliveryCount,
  });
  final String source = insightSource;
  final List<InsightRow> rows;
  final List<SpendTag> tags;
  final int weekendShare;
  final int lateShopping;
  final int subsCount;
  final int subsAmount;
  final int deliveryCount;
}

/// 소비 분석 화면과 같은 방식의 요약. 페르소나의 지출에서 고정 비율로 계산한다.
SpendInsight spendInsight(List<SpendCategory> cats) {
  final rows = [
    for (final c in cats)
      InsightRow(
        label: c.label,
        ratio: c.ratio,
        amount: c.amount,
        prev: jsRound(c.amount / (1 + (monthChange[c.label] ?? 0) / 100) / 1000) * 1000,
        changePct: monthChange[c.label] ?? 0,
      ),
  ];
  int by(String label) => cats.where((c) => c.label == label).firstOrNull?.amount ?? 0;
  final subsAmount = math.max(10000, roundMan(by('문화·여가') * 0.5));
  final deliveryCount = math.max(1, jsRound(by('식비') * 0.4 / 25000));
  const weekendShare = 41, lateShopping = 62, subsCount = 4;
  return SpendInsight(
    rows: rows,
    tags: [
      const SpendTag('weekend', '주말 소비 비중 $weekendShare%'),
      SpendTag('subs', '정기결제 $subsCount건 · 월 ${formatMan(subsAmount)}'),
      const SpendTag('late', '쇼핑 $lateShopping% 월 후반 집중'),
      SpendTag('delivery', '배달·외식 월 $deliveryCount회'),
    ],
    weekendShare: weekendShare,
    lateShopping: lateShopping,
    subsCount: subsCount,
    subsAmount: subsAmount,
    deliveryCount: deliveryCount,
  );
}

/// 목표 기간 말의 예상 금액. 여유 중 투자 몫은 연 6%(가정), 나머지 여유와 예금은 적금 금리로 본다.
int plannedFuture(LumpAdvice a, double share) {
  final months = a.goalMonths;
  final save = math.max(0, a.surplus);
  final invest = roundMan(save * share);
  return jsRound(_annuityFv(invest, investAssumedRate, months) + _annuityFv(save - invest, savingsRate, months) + _grow(a.deposit, savingsRate, months));
}

class Infeasible {
  const Infeasible({required this.planned, required this.short, required this.yieldRate});
  final int planned;
  final int short;
  final double yieldRate;
  bool get unrealistic => yieldRate >= 0.12;
}

/// 적금 + 투자(MIX)에서 여유 돈을 전부 투자해도(연 6% 가정) 목표에 못 닿는지 본다.
/// 닿거나 MIX가 아니면 null. 성향을 묻기 전에 "투자로도 어렵다"를 먼저 알리는 데 쓴다.
Infeasible? infeasible(LumpAdvice? a) {
  if (a == null || a.decisionId != 'MIX' || a.surplus <= 0) return null;
  final planned = plannedFuture(a, 1);
  if (planned >= a.goalAmount) return null;
  return Infeasible(planned: planned, short: a.goalAmount - planned, yieldRate: a.yieldRate);
}

class Shortfall {
  const Shortfall({required this.shortfall, required this.planned, required this.neededShare, required this.neededMonthly});
  final int shortfall;
  final int planned;

  /// 목표에 닿는 투자 비중(5% 단위). 여유를 전부 투자해도 닿지 않으면 null
  final double? neededShare;
  final int? neededMonthly;

  Json toJson() => {'shortfall': shortfall, 'planned': planned, 'neededShare': neededShare, 'neededMonthly': neededMonthly};
  static Shortfall? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = asJson(v);
    return Shortfall(
      shortfall: asInt(j['shortfall']) ?? 0,
      planned: asInt(j['planned']) ?? 0,
      neededShare: (j['neededShare'] as num?)?.toDouble(),
      neededMonthly: asInt(j['neededMonthly']),
    );
  }
}

/// 적금 + 투자(MIX)에서 투자 비중대로 해도 목표에 못 미치는지 본다.
Shortfall? shortfall(LumpAdvice? a) {
  if (a == null || a.decisionId != 'MIX' || a.surplus <= 0) return null;
  final planned = plannedFuture(a, a.investShare);
  if (planned >= a.goalAmount) return null;
  double? needed;
  if (plannedFuture(a, 1) >= a.goalAmount) {
    var lo = a.investShare, hi = 1.0;
    for (var i = 0; i < 40; i++) {
      final mid = (lo + hi) / 2;
      if (plannedFuture(a, mid) >= a.goalAmount) {
        hi = mid;
      } else {
        lo = mid;
      }
    }
    needed = math.min(1.0, (hi * 20).ceil() / 20);
  }
  return Shortfall(
    shortfall: a.goalAmount - planned,
    planned: planned,
    neededShare: needed,
    neededMonthly: needed == null ? null : roundMan(math.max(0, a.surplus) * needed),
  );
}

/// 상담 계산의 입력. 세션에는 이 값만 저장하고 결과는 다시 계산한다.
class AdviseInput {
  const AdviseInput({
    required this.income,
    required this.expense,
    required this.debt,
    this.deposit,
    required this.goalAmount,
    required this.goalMonths,
    this.expText = '',
    this.lossText = '',
    this.investFocus = false,
    this.boldShare,
  });
  final int income;
  final int expense;
  final int debt;
  final int? deposit;
  final int goalAmount;
  final int goalMonths;
  final String expText;
  final String lossText;
  final bool investFocus;
  final double? boldShare;

  Json toJson() => {
        'income': income,
        'expense': expense,
        'debt': debt,
        'deposit': deposit,
        'goalAmount': goalAmount,
        'goalMonths': goalMonths,
        'expText': expText,
        'lossText': lossText,
        'investFocus': investFocus,
        'boldShare': boldShare,
      };
  static AdviseInput? fromJson(Object? v) {
    if (v is! Map) return null;
    final j = asJson(v);
    return AdviseInput(
      income: asInt(j['income']) ?? 0,
      expense: asInt(j['expense']) ?? 0,
      debt: asInt(j['debt']) ?? 0,
      deposit: asInt(j['deposit']),
      goalAmount: asInt(j['goalAmount']) ?? 0,
      goalMonths: asInt(j['goalMonths']) ?? 1,
      expText: j['expText'] as String? ?? '',
      lossText: j['lossText'] as String? ?? '',
      investFocus: j['investFocus'] == true,
      boldShare: (j['boldShare'] as num?)?.toDouble(),
    );
  }
}

class LumpFigures {
  const LumpFigures({required this.income, required this.balance, required this.decision, required this.recommend});
  final List<Figure> income;
  final List<Figure> balance;
  final List<Figure> decision;
  final List<Figure> recommend;
}

class LumpAdvice {
  LumpAdvice._({
    required this.input,
    required this.income,
    required this.expense,
    required this.debt,
    required this.debtPayment,
    required this.deposit,
    required this.surplusBeforeDebt,
    required this.surplus,
    required this.emergencyMonths,
    required this.future,
    required this.gap,
    required this.requiredMonthly,
    required this.yieldRate,
    required this.leverageGate,
    required this.goalAmount,
    required this.goalMonths,
    required this.decisionId,
    required this.profile,
    required this.leverage,
    required this.monthlyInvest,
    required this.domesticShare,
    required this.overseasShare,
    required this.focusApplied,
    required this.boldApplied,
    required this.investBase,
    required this.investShare,
    required this.domesticAmount,
    required this.overseasAmount,
    required this.categories,
    required this.figures,
  });

  final AdviseInput input;
  final int income;
  final int expense;
  final int debt;
  final int debtPayment;
  final int deposit;
  final int surplusBeforeDebt;
  final int surplus;

  /// 소수 첫째 자리까지 (4.0 → 4)
  final double emergencyMonths;
  final int future;
  final int gap;
  final int requiredMonthly;
  final double yieldRate;
  final double leverageGate;
  final int goalAmount;
  final int goalMonths;

  /// SPEND_CHECK | DEBT_FIRST | EMERGENCY_FIRST | SAVINGS_ENOUGH | MIX
  final String decisionId;
  final RiskProfile profile;
  final bool leverage;
  final int monthlyInvest;
  final int domesticShare;
  final int overseasShare;
  final bool focusApplied;
  final bool boldApplied;
  final int investBase;
  final double investShare;
  final int domesticAmount;
  final int overseasAmount;
  final List<SpendCategory> categories;
  final LumpFigures figures;

  bool get investFocus => input.investFocus;

  /// "4개월" / "2.8개월"에 쓰는 숫자 글자
  String get emergencyText => numText(emergencyMonths);
}

LumpAdvice advise(AdviseInput input) {
  final income = math.max(0, input.income);
  final expense = math.max(0, input.expense);
  final debt = math.max(0, input.debt);
  final deposit = math.max(0, input.deposit ?? depositDefault);
  final goalAmount = math.max(0, input.goalAmount);
  final goalMonths = math.max(1, input.goalMonths);
  final payment = debtPayment(debt);
  final before = income - expense;
  final surplus = before - payment;
  final emergencyMonths = expense > 0 ? jsRound(deposit / expense * 10) / 10 : 0.0;
  final save = math.max(0, surplus);
  final future = jsRound(_annuityFv(save, savingsRate, goalMonths) + _grow(deposit, savingsRate, goalMonths));
  final gap = math.max(0, goalAmount - future);
  final needRaw = _annuityPmt(math.max(0, goalAmount - _grow(deposit, savingsRate, goalMonths)), savingsRate, goalMonths);
  final requiredMonthly = roundMan(math.max(0, needRaw));
  final yieldRate = save > 0 || deposit > 0 ? requiredYield(save, deposit, goalMonths, goalAmount) : 1.0;
  final profile = inferRiskProfile(input.expText, input.lossText);

  var decisionId = 'MIX';
  if (surplus <= 0) {
    decisionId = 'SPEND_CHECK';
  } else if (debt > 0) {
    decisionId = 'DEBT_FIRST';
  } else if (emergencyMonths < emergencyMin) {
    decisionId = 'EMERGENCY_FIRST';
  } else if (future >= goalAmount) {
    decisionId = 'SAVINGS_ENOUGH';
  }

  final gate = defaultRequiredYield() + 0.03;
  final leverage = decisionId == 'MIX' && profile.id == 'ACTIVE' && yieldRate >= gate;

  var share = _profileShare[profile.id]!;
  if (decisionId == 'EMERGENCY_FIRST') share *= 0.5;
  if (decisionId == 'SAVINGS_ENOUGH') share *= 0.35;
  var focusApplied = false;
  if (input.investFocus && (decisionId == 'MIX' || decisionId == 'SAVINGS_ENOUGH' || decisionId == 'DEBT_FIRST')) {
    share = math.min(0.85, share + 0.15);
    focusApplied = true;
  }
  // 목표를 채우려고 고객이 과감한 비중을 고르면 그 비중을 쓴다
  var boldApplied = false;
  if (input.boldShare != null) {
    share = input.boldShare!.clamp(0, 1).toDouble();
    boldApplied = true;
  }
  final investBase = decisionId == 'SPEND_CHECK' ? 0 : save;
  final monthlyInvest = roundMan(investBase * share);
  final (dom, os) = _profileSplit[profile.id]!;
  // 매달 투자할 돈의 근거 문장. 금액이 어디서 나왔는지 카드에서 바로 보이게 한다
  final investNote = '${decisionId == 'DEBT_FIRST' ? '갚고 남는 돈 ' : '월 여유 '}${about(investBase)}의 ${jsRound(share * 100)}%';
  final emText = numText(emergencyMonths);

  final incomeFigs = [_fig('평균 수입', about(income)), _fig('평균 지출', about(expense))];
  final balanceFigs = [
    _fig('월평균 여유 자금', about(math.max(0, before)), before <= 0 ? '지출이 월급보다 많아요' : '', before <= 0 ? 'warning' : ''),
    _fig('예적금 및 현금', about(deposit), '생활비 $emText개월치', emergencyMonths < emergencyMin ? 'warning' : ''),
  ];

  final List<Figure> decisionFigs = switch (decisionId) {
    'SPEND_CHECK' => [
        _fig('월급', about(income)),
        _fig('지출', about(expense)),
        _fig('월 여유', surplus < 0 ? aboutGap(surplus) : '0원', payment > 0 ? '부채 상환 포함' : '', 'warning'),
      ],
    'DEBT_FIRST' => [
        _fig('갚기 전 월 여유', about(before)),
        _fig('매달 갚을 돈', about(payment), '연 5.5% · 60개월'),
        _fig('갚고 남는 여력', about(math.max(0, surplus))),
      ],
    'EMERGENCY_FIRST' => [
        _fig('비상자금', '$emText개월', '기준 3개월'),
        _fig('예금', about(deposit)),
        _fig('월 여유', about(surplus)),
      ],
    'SAVINGS_ENOUGH' => [
        _fig('예금과 적금으로 모이는 돈', about(future), '$goalMonths개월'),
        _fig('목표', formatMan(goalAmount)),
        _fig('월 여유', about(surplus)),
      ],
    _ => [
        _fig('예금과 적금으로 모이는 돈', about(future)),
        _fig('목표까지 부족한 돈', about(gap)),
        _fig('필요한 월 저축', about(requiredMonthly), '연 3.2% 적금 기준'),
      ],
  };

  // 추천 카드는 금액만 보인다. 국내·해외 비중은 어느 시장을 볼지 고른 뒤에 말한다
  final recommendFigs = monthlyInvest > 0 ? [_fig('매달 투자할 돈', '월 ${about(monthlyInvest)}', investNote)] : <Figure>[];

  return LumpAdvice._(
    input: input,
    income: income,
    expense: expense,
    debt: debt,
    debtPayment: payment,
    deposit: deposit,
    surplusBeforeDebt: before,
    surplus: surplus,
    emergencyMonths: emergencyMonths,
    future: future,
    gap: gap,
    requiredMonthly: requiredMonthly,
    yieldRate: yieldRate,
    leverageGate: gate,
    goalAmount: goalAmount,
    goalMonths: goalMonths,
    decisionId: decisionId,
    profile: profile,
    leverage: leverage,
    monthlyInvest: monthlyInvest,
    domesticShare: dom,
    overseasShare: os,
    focusApplied: focusApplied,
    boldApplied: boldApplied,
    investBase: investBase,
    investShare: share,
    domesticAmount: roundMan(monthlyInvest * dom / 100),
    overseasAmount: roundMan(monthlyInvest * os / 100),
    categories: categories(expense),
    figures: LumpFigures(income: incomeFigs, balance: balanceFigs, decision: decisionFigs, recommend: recommendFigs),
  );
}

double? _defaultYield;

/// 기본 페르소나(월 여유 140만원, 예금 약 848만원, 3년 1억)의 필요 수익. 레버리지 안내 기준이다.
double defaultRequiredYield() => _defaultYield ??= requiredYield(3500000 - 2100000, depositDefault, 36, 100000000);

LumpGoal goalById(String? id) => lumpGoals[id] ?? lumpGoals['goal-100']!;
