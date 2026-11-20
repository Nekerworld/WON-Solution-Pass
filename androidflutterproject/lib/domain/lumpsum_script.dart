/// 목돈 불리기 고정 대본. 숫자는 lumpsum_advisor 결과만 넣는다.
/// 실제 LLM 호출은 없다. "우리 상황에 맞는 게 없네요?"는 여기 넣지 않는다.
library;

import 'dart:math' as math;

import 'asset_advisor.dart' show Figure;
import 'bank_state.dart';
import 'formatters.dart';
import 'lumpsum_advisor.dart' as la;

const String opening = '목돈 마련하고 싶어요';

/// 자산 상담과 목돈 상담 첫 화면이 같이 쓰는 선택지
const List<String> assetGoalChips = ['해외주식 투자를 처음 시작해 보고 싶어요', '결혼 자금 3천만원을 3년 안에 모으고 싶어요', '비상자금이 충분한지 알고 싶어요'];

class LChoice {
  const LChoice(this.id, this.text);
  final String id;
  final String text;
  Json toJson() => {'id': id, 'text': text};
  factory LChoice.fromJson(Json j) => LChoice(j['id'] as String? ?? '', j['text'] as String? ?? '');
}

class CutRow {
  const CutRow({required this.id, required this.label, required this.saved, required this.reason});
  final String id;
  final String label;
  final int saved;
  final String reason;
  Json toJson() => {'id': id, 'label': label, 'saved': saved, 'reason': reason};
  factory CutRow.fromJson(Json j) => CutRow(id: j['id'] as String? ?? '', label: j['label'] as String? ?? '', saved: asInt(j['saved']) ?? 0, reason: j['reason'] as String? ?? '');
}

/// 응답 한 덩어리. t: text | steps | details | figures | tags | link
class LBlock {
  const LBlock(
    this.t, {
    this.text = '',
    this.items = const [],
    this.label = '',
    this.categories,
    this.insight = false,
    this.cuts,
    this.figures = const [],
    this.tags = const [],
    this.action = '',
  });
  final String t;
  final String text;

  /// steps의 단계 문장
  final List<String> items;
  final String label;
  final List<la.SpendCategory>? categories;

  /// details에서 categories로 소비 분석 요약(출처·지난달 대비)을 같이 보일지
  final bool insight;
  final List<CutRow>? cuts;
  final List<Figure> figures;
  final List<la.SpendTag> tags;
  final String action;

  Json toJson() => {
        't': t,
        if (text.isNotEmpty) 'text': text,
        if (items.isNotEmpty) 'items': items,
        if (label.isNotEmpty) 'label': label,
        if (categories != null) 'categories': categories!.map((c) => c.toJson()).toList(),
        if (insight) 'insight': true,
        if (cuts != null) 'cuts': cuts!.map((c) => c.toJson()).toList(),
        if (figures.isNotEmpty) 'figures': figures.map((f) => f.toJson()).toList(),
        if (tags.isNotEmpty) 'tags': tags.map((g) => g.toJson()).toList(),
        if (action.isNotEmpty) 'action': action,
      };

  factory LBlock.fromJson(Json j) => LBlock(
        j['t'] as String? ?? 'text',
        text: j['text'] as String? ?? '',
        items: asStrings(j['items']),
        label: j['label'] as String? ?? '',
        categories: j['categories'] is List ? asList(j['categories']).map((c) => la.SpendCategory.fromJson(asJson(c))).toList() : null,
        insight: j['insight'] == true,
        cuts: j['cuts'] is List ? asList(j['cuts']).map((c) => CutRow.fromJson(asJson(c))).toList() : null,
        figures: asList(j['figures']).map((f) => Figure.fromJson(asJson(f))).toList(),
        tags: asList(j['tags']).map((g) => la.SpendTag.fromJson(asJson(g))).toList(),
        action: j['action'] as String? ?? '',
      );
}

LBlock tb(String text) => LBlock('text', text: text);

/// 응답 하나. text는 블록 없이 문장만 있는 응답에 쓴다
class LMessage {
  const LMessage({this.text = '', this.blocks = const []});
  final String text;
  final List<LBlock> blocks;
}

/// 판단 뒤 "투자 비중도 같이 볼까요?"에 대한 두 답. 질문과 맞는 답만 둔다
const List<LChoice> investChoicesDefault = [LChoice('inv-yes', '네, 투자도 같이 볼게요'), LChoice('inv-no', '아니요, 여기서 마칠게요')];

/// 입력창을 눌렀을 때 타이핑되는 문장. 선택지에 원하는 상황이 없을 때 쓰므로 어떤 선택지와도 같으면 안 된다.
/// (DEBT_CHECK는 부채 유무에 따라 situationText로 따로 만든다)
final Map<String, String> typed = {
  'INTRO': opening,
  'GOAL': la.goalTyped.text,
  'PROFILING': '연금이랑 펀드를 조금 해봤어요',
  'LOSS': '일단 지켜보다가 반등하면 정리할 것 같아요',
  'RECOMMEND': '두 계좌 모두 보고 싶어요',
  'NO_ACCOUNT': '네, 계좌 만들어 주세요',
  'EMERGENCY': '지금은 비상자금만 볼게요',
};

const List<String> analysisSteps = ['입출금 내역 불러오는 중', '카드 소비 분류 중', '고정지출/변동지출 계산 중'];

final RegExp banned = RegExp(r'종목|매수|매도|수익률|추천주|사세요|가입이 완료|가입 완료됐|승인됐습니다|가입해 드렸');

T pick<T>(List<T> list, int seed) => list[seed.abs() % list.length];

String _man(num n) => formatMan(n);

String pct(double rate) {
  final s = (la.jsRound(rate * 1000) / 10).toStringAsFixed(1);
  return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}%';
}

/// 선택지에 없는 답. 투자 쪽에 더 무게를 둔다는 뜻이다. 부채는 해결패스가 계좌에서 보므로 묻거나 말하지 않는다
String situationText() => '투자에 더 집중하고 싶어요';

List<LChoice> goalChoices() => [for (final e in la.lumpGoals.entries) LChoice(e.key, e.value.text)];
List<LChoice> experienceChoices() => [for (final e in la.experienceTexts.entries) LChoice(e.key, e.value)];
List<LChoice> lossChoices() => [for (final e in la.lossTexts.entries) LChoice(e.key, e.value)];

List<LChoice> productChoices(bool showLeverage) => [
      const LChoice('prod-dom', '국내주식'),
      const LChoice('prod-os', '해외주식'),
      if (showLeverage) const LChoice('prod-lev', '레버리지 상품'),
    ];

List<LChoice> openChoices() => const [LChoice('open-yes', '네, 개설해 주세요'), LChoice('open-no', '다음에 할게요')];

/// 목표를 "3년 안에 1억원"처럼 쓴다
String goalPhrase(int months, int amount) => '${months % 12 == 0 ? '${months ~/ 12}년' : '$months개월'} 안에 ${_man(amount)}';
String _goalOf(la.LumpAdvice a) => goalPhrase(a.goalMonths, a.goalAmount);
String goalText(la.LumpGoal g) => '${goalPhrase(g.months, g.amount)} 만들고 싶어요';

/// 비상자금을 채우는 방법 한 문장. 남는 돈의 70%를 만원 단위로 모은다고 본다 (이전 자산관리 상담과 같은 기준)
String emergencyFill(la.LumpAdvice a) {
  final gap = math.max(0, a.expense * la.emergencyMin - a.deposit);
  final save = (la.jsRound(math.max(0, a.surplus) * 0.7) / 10000).floor() * 10000;
  if (a.surplus <= 0) return '지금은 남는 돈이 없어서 채우기 어려우니, 지출부터 같이 줄여 볼게요.';
  if (save < 10000) return '매달 모으기에는 남는 돈이 적어서, 지출부터 같이 줄여 보는 게 좋아요.';
  return '매달 ${la.about(save)}씩 예금에 모으면 ${(gap / save).ceil()}개월이면 채워져요.';
}

/// 필요한 연 수익을 말로 쓴다. 너무 크면 구체 숫자 대신 "50% 이상"이라고 한다
String yieldText(double rate) => rate >= 0.5 ? '연 50% 이상' : '연 약 ${la.jsRound(rate * 100)}%';

/// 판단 문장. skipFill이면 비상자금 채우는 방법은 이미 말했으므로 생략한다.
/// 비상자금·상환이 먼저인 경우에도 고른 목표를 한 번 언급한다.
String decisionSentence(la.LumpAdvice a, {bool skipFill = false}) {
  if (a.decisionId == 'SPEND_CHECK') {
    if (a.surplusBeforeDebt <= 0) return '지출이 월급보다 많아서 투자나 저축은 제안하지 않고, 지출부터 같이 볼게요.';
    return '부채 상환으로 매달 ${la.about(a.debtPayment)}이 나가면 월 여유가 없어서, 투자나 저축은 제안하지 않고 지출부터 같이 볼게요.';
  }
  if (a.decisionId == 'DEBT_FIRST') {
    return '갚는 이자 연 5.5%가 적금 연 3.2%보다 높아서, 투자보다 대출 상환을 먼저 권해요. 이후 금액은 갚고 남는 ${la.about(math.max(0, a.surplus))} 기준이에요. ${_goalOf(a)} 목표는 상환을 이어 가면서 이 돈으로 보는 게 안전해요.';
  }
  if (a.decisionId == 'EMERGENCY_FIRST') {
    final head = '비상자금이 ${a.emergencyText}개월로 3개월보다 짧아서, 목표보다 예금을 먼저 채우는 걸 권해요.';
    return [head, skipFill ? '' : emergencyFill(a), '${_goalOf(a)} 목표는 그다음에 보는 게 안전해요.'].where((s) => s.isNotEmpty).join(' ');
  }
  if (a.decisionId == 'SAVINGS_ENOUGH') return '예금과 적금만으로도 기간 안에 목표가 모여요. 투자하지 않아도 괜찮아요.';
  return '목표까지 월 ${la.about(a.requiredMonthly)}을 모아야 하는데, 적금만으로는 부족해요.';
}

/// 투자 경험 답변을 한 문장으로 읽는다. 선택지 문장과 직접 쓴 문장 모두 다룬다
String _experienceRead(int score, String text) {
  if (RegExp(r'연금|펀드').hasMatch(text)) return '투자 경험은 연금이나 펀드를 조금 해 본 정도예요.';
  if (score == 0) return '투자 경험은 아직 없는 편이에요.';
  if (score == 2) return '투자 경험은 꽤 있는 편이에요.';
  return '투자 경험은 소액으로 해 본 정도예요.';
}

/// 손실 반응 답변을 "~쪽이라"로 읽는다
String _lossRead(int score, String text) {
  if (RegExp(r'반등|정리').hasMatch(text) && !text.contains('바로 팔')) return '바로 팔지는 않지만 반등하면 정리하는 쪽이라';
  if (score == 0) return '떨어지면 바로 정리하는 쪽이라';
  if (score == 2) return '떨어질 때 더 살 수 있는 쪽이라';
  return '손실이 나도 길게 보고 버틸 수 있는 쪽이라';
}

/// 두 답변을 따로 읽어서, 답한 내용과 어긋나는 설명이 나오지 않게 한다
String profileSentence(la.LumpAdvice a, String expText, String lossText) {
  final name = la.profileName[a.profile.id] ?? '중립';
  return '“$expText”, “$lossText”에서 ${_experienceRead(a.profile.experience, expText)} ${_lossRead(a.profile.loss, lossText)} 성향은 $name으로 볼게요.';
}

/// 첫 질문. 이전 자산관리 상담과 같은 문장 계열이다
LMessage greeting() {
  const text = '어떤 목표로 상담받고 싶으세요? 편하게 말씀해 주세요.';
  return LMessage(text: text, blocks: [tb(text)]);
}

/// 첫 질문 선택지는 이전 자산관리 상담의 3개 그대로다
List<LChoice> introChoices() => [for (var i = 0; i < assetGoalChips.length; i++) LChoice('intro-${i + 1}', assetGoalChips[i])];

/// 첫 질문 선택지 중 해외주식 칩(또는 그 뜻으로 직접 쓴 말)은 목돈 채팅 안에서 이어 간다
bool isOverseasIntro(String? text) => (text ?? '').contains('해외주식');

/// 해외주식 칩의 첫 답. 목돈 목표는 묻지 않고, 외화 계좌가 없으니 개설할지 바로 묻는다.
LMessage overseasIntro(bool hasFx) => LMessage(blocks: [
      tb('해외주식 투자를 처음 시작하시는군요. 해외주식은 달러를 넣어 두는 외화 계좌로 거래해요.'),
      tb(hasFx ? '외화 계좌는 이미 있어요. 이어서 **해외주식 계좌 개설을 도와드릴까요?**' : '외화 계좌는 아직 없네요. **개설 도와드릴까요?**'),
    ]);

/// 비상자금을 묻는 첫 말(또는 그 뜻으로 직접 쓴 말)
bool isEmergencyIntro(String? text) => RegExp(r'비상|급할\s?때|예비').hasMatch(text ?? '');

/// 첫 말에 "결혼"이 들어 있으면 목표 이름을 결혼 자금으로 보인다. 없으면 빈 문자열
String purposeLabelOf(String? text) => (text ?? '').contains('결혼') ? '결혼 자금 마련' : '';

/// 비상자금이 기준(3개월치)을 넘는지
bool emergencyEnough(la.LumpAdvice? a) => a != null && a.emergencyMonths >= la.emergencyMin;

const List<LChoice> emergencyChoicesHigh = [LChoice('em-yes', '네, 목돈 마련도 같이 볼게요'), LChoice('em-no', '아니요, 여기서 마칠게요')];
const List<LChoice> emergencyChoicesLow = [LChoice('em-yes', '그래도 목돈 마련도 같이 볼게요'), LChoice('em-no', '아니요, 비상자금부터 채울게요')];

/// 비상자금 점검 뒤에 목돈 마련도 볼지 묻는 두 답. 기준에 못 미치면 "그래도"로 묻고, 마치는 답도 비상자금 쪽으로 쓴다
List<LChoice> emergencyChoices(la.LumpAdvice? a) => a != null && !emergencyEnough(a) ? emergencyChoicesLow : emergencyChoicesHigh;

/// 비상자금 점검 문장: 예금이 생활비 몇 개월치인지 말하고, 기준(3개월)보다 적으면 채우는 기간을 계산해 준다.
/// 월 여유가 없으면 목돈은 묻지 않고 지출부터 본다고 말한다.
String emergencyLine(la.LumpAdvice a) {
  const min = la.emergencyMin;
  final head = '예금이 생활비 ${a.emergencyText}개월치예요.';
  if (emergencyEnough(a)) {
    final ok = '$head 기준인 $min개월치보다 많아서, 비상자금은 충분한 편이에요.';
    return a.surplus <= 0 ? '$ok 다만 지금은 남는 돈이 없어서, 지출부터 같이 볼게요.' : ok;
  }
  return '$head 기준인 $min개월치에 못 미쳐서 아직 부족해요. ${emergencyFill(a)}';
}

/// 첫 말에 목적이 들어 있으면 먼저 받아 준다. 지금은 결혼 자금만 있다
String _purposeAck(String label) => label == '결혼 자금 마련' ? '결혼 자금을 준비하시는군요. ' : '';

/// 분석 마무리의 첫 문장: 남는 돈. 지출이 더 많거나 상환까지 빼면 모자란 경우는 그대로 말한다
String _surplusClosing(la.LumpAdvice a) {
  final before = a.surplusBeforeDebt;
  if (before <= 0) return la.jsRound(-before / 10000) == 0 ? '월급과 지출이 거의 같아서 남는 돈이 없어요.' : '지출이 월급보다 ${la.about(-before)} 많아요.';
  final base = '매달 남는 돈은 ${la.about(before)}이에요.';
  if (a.debt <= 0) return base;
  final head = '매달 남는 돈은 ${la.about(before)}이고, 부채 상환(월 ${la.about(a.debtPayment)})을 빼면 ';
  if (a.surplus > 0) return '$head매달 평균 ${la.about(a.surplus)} 남아요.';
  if (la.jsRound(-a.surplus / 10000) == 0) return '$head남는 돈이 없어요.';
  return '$head${la.about(-a.surplus)}이 모자라요.';
}

/// 분석 응답: 문장 → 진행 단계 → 소비 드롭다운 → 카드 2줄 → 마무리 → 질문
LMessage analysisMessage(la.LumpAdvice a, {bool goalKnown = false, bool assumedMonths = false, bool skipGoal = false, bool emergency = false, String purposeLabel = ''}) {
  final closing = _surplusClosing(a);
  var last = '$closing\n\n**목돈 목표가 얼마인가요?**';
  // 목표를 이미 말한 경우(결혼 자금 3천만원 3년 등)는 목표를 다시 묻지 않고 바로 계산으로 간다
  if (goalKnown) {
    last = '$closing\n\n${assumedMonths ? '기간은 3년으로 보고 바로 계산해 볼게요.' : '말씀하신 목표로 바로 계산해 볼게요.'}';
  } else if (skipGoal) {
    // 남는 돈이 없으면 목표를 묻지 않고 바로 지출부터 본다. 묻고 나서 무시하지 않는다
    last = '$closing\n\n목표는 지출을 정리한 뒤에 같이 볼게요.';
  }
  // 비상자금을 물은 경우는 점검 결과를 말하고, 목돈 마련도 볼지 묻는다
  if (emergency) {
    if (skipGoal) {
      last = emergencyLine(a);
    } else if (emergencyEnough(a)) {
      last = '${emergencyLine(a)}\n\n**남는 돈으로 목돈 마련도 같이 볼까요?**';
    } else {
      last = '${emergencyLine(a)}\n\n비상자금을 채운 뒤에 목돈을 보는 게 안전하지만, 그래도 같이 볼 수 있어요. **목돈 마련도 같이 볼까요?**';
    }
  }
  return LMessage(blocks: [
    tb('${_purposeAck(purposeLabel)}월급과 지출을 분석해볼게요.'),
    const LBlock('steps', items: analysisSteps),
    LBlock('details', label: '내 소비 자세히 보기', categories: a.categories),
    LBlock('figures', figures: a.figures.income),
    LBlock('figures', figures: a.figures.balance),
    tb(last),
  ]);
}

/// 비상자금만 보다가 목돈 마련도 보겠다고 했을 때: 목표를 묻는다
LMessage goalAskMessage(la.LumpAdvice? a) {
  final lead = a != null && !emergencyEnough(a) ? '좋아요. 비상자금을 채우는 것과 함께 목돈을 볼게요.' : '좋아요. 남는 돈으로 목돈을 만든다고 보고 계산해 볼게요.';
  return LMessage(blocks: [tb('$lead\n\n**목돈 목표가 얼마인가요?**')]);
}

/// 비상자금만 보고 마칠 때. 충분하다고 말한 뒤에 "먼저 챙겨 보세요"라고 하지 않는다
LMessage emergencyStop(la.LumpAdvice? a) {
  final tail = a != null && emergencyEnough(a) ? '지금 비상자금은 충분하니 그대로 유지하세요.' : '비상자금부터 채워 보세요.';
  final text = '좋아요, 목돈 마련은 빼고 여기서 마칠게요. $tail 다시 보려면 새 상담을 시작하세요.';
  return LMessage(text: text, blocks: [tb(text)]);
}

/// 계좌 개설을 다음으로 미룰 때: 마무리 말만 하고 상담을 닫는다
LMessage laterMessage() {
  const text = '알겠어요. 필요하실 때 언제든 다시 말씀해 주세요. 새 상담을 시작하면 처음부터 같이 볼 수 있어요.';
  return LMessage(text: text, blocks: [tb(text)]);
}

/// 레버리지 상품을 골랐을 때: 이번 상담에서는 이어 가지 않는다고 말하고 국내·해외를 다시 묻는다
LMessage leverageRetry() {
  const text = '레버리지 상품은 이번 상담에서 가입 절차를 도와드리지 못해요. 일반 주식으로 먼저 볼게요.\n\n**국내주식과 해외주식 중 어느 쪽으로 볼까요?**';
  return LMessage(text: text, blocks: [tb(text)]);
}

const List<String> spendSteps = ['소비 패턴 비교 중', '줄이기 쉬운 항목 고르는 중', '필요한 금액 계산하는 중'];

/// 항목 하나를 대화 문장으로 쓴다. 소비 분석의 패턴 숫자를 근거로 붙인다
String _cutSentence(la.CutItem it, la.SpendInsight ins) {
  final s = _man(it.saved);
  if (it.id == 'subs') return '정기결제가 ${ins.subsCount}건이라 자주 안 쓰는 구독을 정리하면 한 달에 $s 정도 줄어요.';
  if (it.id == 'impulse') return '쇼핑은 ${ins.lateShopping}%가 월 후반에 몰려 있어서, 충동구매만 줄여도 한 달에 $s 정도예요.';
  if (it.id == 'delivery') return '배달·외식이 월 ${ins.deliveryCount}회라, 조금만 줄여도 한 달에 $s 정도 아낄 수 있어요.';
  return '소액 결제를 정리하면 한 달에 $s 정도가 남아요.';
}

/// 줄이기 계획 문장. 부족분과 여유 목표, 항목별 이유, 고정비 설명, 결과를 이어서 쓴다
String _spendPlanText(la.LumpAdvice a, la.SpendPlan plan, la.SpendInsight ins) {
  final deficit = math.max(0, -a.surplus);
  final cover = a.debtPayment > 0 ? '상환까지 빼고 보면 모자란 ' : '모자란 ';
  final head = deficit > 0 ? '$cover${la.about(deficit)}에 여유 10만원을 더하려면, 한 달에 ${_man(plan.target)} 정도를 줄여야 해요.' : '한 달에 ${_man(plan.target)} 정도 줄이는 걸 목표로 잡아 볼게요.';
  const lead = ['먼저', '다음으로', '그다음엔', '마지막으로'];
  final body = [for (var i = 0; i < plan.items.length; i++) '${lead[math.min(i, lead.length - 1)]} **${plan.items[i].label}**. ${_cutSentence(plan.items[i], ins)}'].join('\n\n');
  const fixed = '주거·관리와 교통은 고정비라 이번 계획에서는 건드리지 않았어요.';
  final lack = la.jsRound(-plan.after / 10000) > 0;
  var tail = '이렇게 하면 매달 ${_man(plan.total)}을 아끼고, 월 여유는 ${la.about(plan.after)}이 돼요.';
  if (plan.after <= 0) {
    tail = lack
        ? '이 항목을 모두 줄이면 매달 ${_man(plan.total)}을 아끼지만, 그래도 월 ${la.about(-plan.after)}이 모자라요. 주거·관리와 교통 같은 고정비도 같이 봐야 해요.'
        : '이 항목을 모두 줄이면 매달 ${_man(plan.total)}을 아끼지만, 월 여유는 0원 근처예요. 주거·관리와 교통 같은 고정비도 같이 봐야 해요.';
  }
  return [head, body, fixed, tail].where((s) => s.isNotEmpty).join('\n\n');
}

/// 월 여유가 0원 이하일 때: 소비 분석을 불러온 문장 → 진행 단계 → 소비 막대(출처·지난달 대비) →
/// 패턴 태그 → 대화체 줄이기 계획 → 전후 카드 → 안내. 이어서 칩 두 개가 나온다.
List<LBlock> spendPlanBlocks(la.LumpAdvice a) {
  final plan = la.spendPlan(a);
  final ins = la.spendInsight(a.categories);
  return [
    tb('지출을 줄이는 계획을 세워 볼게요. 자산·소비에서 분석한 최근 3개월 소비 내역을 가져왔어요.'),
    const LBlock('steps', items: spendSteps),
    LBlock('details', label: '지출 항목 자세히 보기', categories: a.categories, insight: true),
    LBlock('tags', tags: ins.tags),
    tb(_spendPlanText(a, plan, ins)),
    LBlock('figures', figures: [
      Figure(label: '줄이기 전 월 여유', value: la.aboutGap(a.surplus), tone: a.surplus <= 0 ? 'warning' : ''),
      Figure(label: '줄인 뒤 월 여유', value: la.aboutGap(plan.after), note: '매달 ${_man(plan.total)} 절약', tone: plan.after > 0 ? '' : 'warning'),
    ]),
    tb('소비 분석에서 더 자세히 보거나, 이 계획을 줄이기 목표로 저장할 수 있어요.'),
  ];
}

/// 줄이기 계획 뒤 선택지. 첫 번째는 화면 이동만 하고 말풍선을 만들지 않는다
List<LChoice> spendChoices() => const [LChoice('spend-view', '소비 분석에서 자세히 보기'), LChoice('spend-save', '줄이기 목표로 저장')];

LMessage savedMessage(la.LumpAdvice a) {
  final plan = la.spendPlan(a);
  return LMessage(blocks: [tb('줄이기 목표를 저장했어요. 매달 ${_man(plan.total)} 줄이는 걸 목표로 잡았고, 소비 분석에서 이번 달 진행 상황을 볼 수 있어요.')]);
}

/// 드롭다운 안에서 항목마다 붙는 짧은 이유. 소비 분석의 패턴 숫자를 쓴다
String _cutReason(la.CutItem it, la.SpendInsight ins) {
  if (it.id == 'subs') return '정기결제 ${ins.subsCount}건 중 자주 안 쓰는 구독 정리';
  if (it.id == 'impulse') return '쇼핑의 ${ins.lateShopping}%가 월 후반에 몰려 있어요';
  if (it.id == 'delivery') return '배달·외식이 월 ${ins.deliveryCount}회예요';
  return '자잘한 카드 결제가 쌓이는 항목이에요';
}

/// 적금 + 투자(MIX)에서 투자 몫이 남을 때: 소비를 줄이면 필요한 연 수익이 얼마나 내려가는지 한 줄로 말하고,
/// 줄일 항목은 "지출 줄이기 제안" 드롭다운 안에 둔다(항목, 줄이는 돈, 이유). 마지막에 소비 분석 버튼.
List<LBlock> cutForYieldBlocks(la.LumpAdvice a) {
  final cut = la.cutForYield(a);
  if (cut == null) return [];
  final ins = la.spendInsight(a.categories);
  return [
    tb('소비를 **매달 ${_man(cut.plan.total)}** 줄이면 필요한 연 수익이 ${pct(cut.yieldBefore)}에서 ${pct(cut.yieldAfter)}로 내려가요.'),
    LBlock('details', label: '지출 줄이기 제안', cuts: [for (final it in cut.plan.items) CutRow(id: it.id, label: it.label, saved: it.saved, reason: _cutReason(it, ins))]),
    const LBlock('link', label: '소비 분석에서 자세히 보기', action: 'spend-open'),
  ];
}

/// 판단 응답: 결론 문장 → 근거 카드. 사용자 문장을 되묻지 않는다
LMessage decisionMessage(la.LumpAdvice a, {bool skipFill = false, la.LumpGoal? adjusted}) {
  final blocks = <LBlock>[];
  if (adjusted != null) blocks.add(tb('목표를 **${goalPhrase(adjusted.months, adjusted.amount)}**으로 바꿔서 다시 계산했어요.'));
  blocks.addAll([tb(decisionSentence(a, skipFill: skipFill)), LBlock('figures', figures: a.figures.decision)]);
  if (a.decisionId == 'SPEND_CHECK') blocks.addAll(spendPlanBlocks(a));
  if (a.decisionId == 'MIX') blocks.addAll(cutForYieldBlocks(a));
  // 투자로도 어려우면 성향을 묻기 전에 먼저 알린다
  final hope = la.infeasible(a);
  if (hope != null) blocks.add(tb(infeasibleText(hope, la.cutForYield(a))));
  // 판단을 보여 준 뒤에는 반드시 질문을 던진다. 선택지는 이 질문에 대한 답이다
  if (a.decisionId != 'SPEND_CHECK') blocks.add(tb(investQuestion(a)));
  return LMessage(blocks: blocks);
}

/// 투자로도 목표에 못 닿을 때, 성향을 묻기 전에 먼저 알린다.
/// 필요한 연 수익이 비현실적으로 크면 "현실적으로 어려워요"라고 분명히 말한다.
String infeasibleText(la.Infeasible h, la.CutForYield? cut) {
  // 소비를 줄이는 제안을 이미 보여 줬으면 줄인 뒤의 필요한 수익으로 말한다
  final useCut = cut != null && cut.yieldAfter >= la.investAssumedRate;
  final rate = useCut ? cut.yieldAfter : h.yieldRate;
  final hard = '${useCut ? '소비를 줄여도 ' : ''}목표에 닿으려면 ${yieldText(rate)} 수익이 필요해서 ${rate >= 0.12 ? '현실적으로 어려워요.' : '쉽지 않아요.'}';
  return '여유 돈을 전부 투자해도(연 6% 가정) 목표 기간 뒤 ${la.about(h.planned)}이라 목표에 ${la.about(h.short)} 못 미쳐요. $hard';
}

/// 판단 뒤 질문. 판단에 따라 묻는 말이 다르다
String investQuestion(la.LumpAdvice? a) {
  if (a != null && la.infeasible(a) != null) return '**목표를 조정할까요, 아니면 그래도 투자도 알아볼까요?**';
  if (a != null && (a.decisionId == 'EMERGENCY_FIRST' || a.decisionId == 'DEBT_FIRST')) return '**그래도 투자도 알아볼까요?**';
  if (a != null && a.decisionId == 'SAVINGS_ENOUGH') return '**혹시 주식 투자도 해 보고 싶으세요?**';
  return '**투자 비중도 같이 볼까요?**';
}

/// 판단 뒤 선택지. 투자로도 어려우면 목표 조정을 먼저 보여 주고 "그래도 투자"를 이어서 둔다.
/// 목표 조정은 목표가 이미 5천만 원 이하·5년 이상이면 해당 선택지를 뺀다.
List<LChoice> investChoices(la.LumpAdvice? a, la.LumpGoal? goal) {
  final g = goal ?? la.lumpGoals['goal-100']!;
  final id = a?.decisionId;
  if (a != null && la.infeasible(a) != null) {
    return [
      if (g.amount > 50000000) const LChoice('sf-amount', '목표를 5천만 원·5년으로 낮출게요'),
      if (g.months < 60) const LChoice('sf-period', '기간을 5년으로 늘릴게요'),
      const LChoice('inv-yes', '그래도 투자도 알아볼게요'),
      const LChoice('inv-no', '아니요, 여기서 마칠게요'),
    ];
  }
  if (id == 'EMERGENCY_FIRST') return const [LChoice('inv-yes', '그래도 투자도 알아볼게요'), LChoice('inv-no', '아니요, 비상자금부터 채울게요')];
  if (id == 'DEBT_FIRST') return const [LChoice('inv-yes', '그래도 투자도 알아볼게요'), LChoice('inv-no', '아니요, 상환부터 할게요')];
  if (id == 'SAVINGS_ENOUGH') return const [LChoice('inv-yes', '네, 투자도 해보고 싶어요'), LChoice('inv-no', '아니요, 적금으로 갈게요')];
  return investChoicesDefault;
}

/// 투자는 빼고 마칠 때. 판단에 맞는 다음 행동을 말한다
LMessage stopMessage(la.LumpAdvice? a) {
  final id = a?.decisionId;
  var tail = '위 금액을 기준으로 적금을 준비해 보세요.';
  if (id == 'DEBT_FIRST') {
    tail = '대출 상환을 먼저 이어 가 보세요.';
  } else if (id == 'EMERGENCY_FIRST') {
    tail = '비상자금부터 채워 보세요.';
  } else if (id == 'SAVINGS_ENOUGH') {
    tail = '월 여유 안에서 적금을 이어 가면 기간 안에 목표가 모여요.';
  } else if (id == 'MIX') {
    tail = '적금만으로는 목표에 못 미치니, 목표나 기간을 조정해서 다시 상담해 보세요.';
  }
  final head = id == 'SAVINGS_ENOUGH' ? '좋아요, 주식은 빼고 적금으로 가요.' : '좋아요, 투자는 빼고 여기서 마칠게요.';
  return LMessage(text: '$head $tail 다시 보려면 새 상담을 시작하세요.');
}

/// 투자 질문에 "예"라고 한 뒤의 첫 말. 사용자가 직접 쓴 말(focus)일 때만 "투자에 더 집중"이라고 받는다.
/// 성향을 이미 답했으면(profileKnown) 다시 묻지 않고 그대로 계산한다.
LMessage afterSituation(la.LumpAdvice? a, {bool focus = false, bool profileKnown = false}) {
  final hope = a != null && la.infeasible(a) != null;
  var body = focus ? '좋아요, 투자에 더 집중해서 볼게요.' : '좋아요, 투자도 같이 볼게요.';
  if (a?.decisionId == 'DEBT_FIRST') {
    body = focus
        ? '대출이 있으면 투자보다 상환을 먼저 권해요. 그래도 투자에 더 집중하고 싶으시니, 갚고 남는 돈 기준으로 투자 비중을 높여서 볼게요. 추가 대출은 제안하지 않아요.'
        : '대출 상환을 이어 가는 걸 전제로, 갚고 남는 돈 기준으로 투자를 알아볼게요. 추가 대출은 제안하지 않아요.';
  } else if (a?.decisionId == 'EMERGENCY_FIRST') {
    body = focus ? '비상자금을 채우는 걸 먼저 두되, 투자에 더 집중하고 싶으시니 투자 비중을 조금 높여서 볼게요.' : '비상자금을 채우는 걸 먼저 두고, 투자는 일부만 알아볼게요.';
  } else if (a?.decisionId == 'SAVINGS_ENOUGH') {
    body = focus ? '좋아요, 투자에 더 집중해서 볼게요. 목표는 적금으로 채워지니 남는 돈 일부로 볼게요.' : '좋아요, 목표는 적금으로 채우고 남는 돈 일부로 투자를 알아볼게요.';
  } else if (hope) {
    body = focus ? '좋아요, 투자에 더 집중해서 얼마나 가까워지는지 볼게요.' : '좋아요, 그래도 투자로 얼마나 가까워지는지 같이 볼게요.';
  }
  if (profileKnown) return LMessage(text: '$body 앞서 말씀해 주신 투자 성향대로 계산해 볼게요.');
  return LMessage(text: '$body 투자 경험과 손실을 견디는 정도에 따라 맞는 비중이 달라져서, 두 가지만 여쭤볼게요.\n\n**주식이나 펀드는 해보신 적 있어요?**');
}

LMessage lossAsk() => const LMessage(text: '**투자한 돈이 한 달 새 20% 떨어지면 어떻게 하실 것 같아요?**');

/// 판단이 상환·비상자금 우선이거나 적금으로 충분할 때, 투자 금액이 어떤 몫인지 한 줄로 밝힌다
String _recommendNote(la.LumpAdvice a) {
  if (a.decisionId == 'EMERGENCY_FIRST') return '나머지 돈은 비상자금을 채우는 데 쓰세요.';
  if (a.decisionId == 'DEBT_FIRST') return '대출 상환은 그대로 이어 가세요.';
  if (a.decisionId == 'SAVINGS_ENOUGH') return '목표는 적금으로 채워지니, 투자는 남는 돈 일부만 이 금액으로 봤어요.';
  return '';
}

/// ack가 있으면 직전 선택(예: 그래도 이 비중으로)을 먼저 받아 준다
LMessage recommendMessage(la.LumpAdvice a, String expText, String lossText, int seed, {String ack = '', bool noLeverage = false}) {
  final head = profileSentence(a, expText, lossText);
  final mix = pick(const ['어느 시장을 볼지 골라 주세요. 그에 맞춰 비중을 같이 볼게요.', '국내와 해외 중 보고 싶은 쪽을 골라 주세요. 비중은 그다음에 볼게요.'], seed + 3);
  final focus = a.boldApplied
      ? '목표를 채우려고 투자 비중을 ${la.jsRound(a.investShare * 100)}%로 올렸어요. '
      : a.focusApplied
          ? '투자에 더 집중하고 싶다고 하셔서 투자 비중에 15%p를 더했어요. '
          : '';
  return LMessage(blocks: [
    if (ack.isNotEmpty) tb(ack),
    tb(head),
    LBlock('figures', figures: a.figures.recommend),
    tb([focus.trim(), _recommendNote(a), mix].where((s) => s.isNotEmpty).join(' ')),
    if (a.leverage && !noLeverage) tb('레버리지 상품은 가격이 움직일 때 손실이 커지고, **넣은 돈보다 더 잃을 수 있어요.**'),
  ]);
}

/// 목표에 못 미칠 때: 부족한 돈과 예상 금액을 카드로 보여 주고, 투자 비중을 올리면 닿는지 말한다.
/// 투자 수익은 연 6%로 가정한 계산이라는 점을 함께 밝힌다.
LMessage shortfallMessage(la.LumpAdvice a, la.Shortfall info) {
  final has = info.neededShare != null;
  return LMessage(blocks: [
    tb(has
        ? '이 비중으로는 목표에 못 미쳐요. 매달 **${la.about(a.monthlyInvest)}** 투자하고 나머지는 적금에 넣어도, 목표 기간 뒤 ${la.about(info.planned)}이라 목표보다 적어요.'
        : '말씀하신 투자 성향대로 계산해 보면, 매달 **${la.about(a.monthlyInvest)}** 투자하고 나머지는 적금에 넣어도 목표 기간 뒤 ${la.about(info.planned)}이에요. 목표에는 ${la.about(info.shortfall)} 못 미쳐요.'),
    LBlock('figures', figures: [
      Figure(label: '목표 기간 뒤 예상', value: la.about(info.planned), note: '투자 연 6% 가정', tone: 'warning'),
      Figure(label: '부족한 돈', value: la.about(info.shortfall), tone: 'warning'),
    ]),
    tb('투자 수익은 연 6%로 가정한 계산이에요.'),
    tb(has
        ? '투자 비중을 **${la.jsRound(info.neededShare! * 100)}%**(월 ${la.about(info.neededMonthly ?? 0)})까지 올리면 목표에 닿아요. 과감하게 가시려면 이쪽이에요.'
        : '앞서 말씀드린 대로 투자만으로 채우기는 어려워요. 목표를 조정하는 편이 현실적이에요.'),
    tb(has ? '**어떻게 하실래요?**' : '**그래도 이 비중으로 갈까요, 목표를 조정할까요?**'),
  ]);
}

/// 부족할 때 고르는 선택지. 닿는 비중이 있을 때만 과감한 투자를 보여 준다
List<LChoice> shortfallChoices(la.Shortfall? info, la.LumpGoal goal) {
  final has = info?.neededShare != null;
  return [
    if (has) LChoice('sf-bold', '과감하게 월 ${la.about(info!.neededMonthly ?? 0)} 투자할게요'),
    if (goal.amount > 50000000) const LChoice('sf-amount', '목표를 5천만 원·5년으로 낮출게요'),
    if (goal.months < 60) const LChoice('sf-period', '기간을 5년으로 늘릴게요'),
    LChoice('sf-keep', has ? '지금 비중으로 갈게요' : '그래도 이 비중으로 갈게요'),
  ];
}

/// 직전에 "이 비중으로 간다"고 답한 것을 받아 주는 첫 문장
String keepAck() => '알겠어요. 목표는 그대로 두고 이 비중으로 볼게요.';

/// 월 투자금을 어디에 넣는지 풀어 쓴다. 해외만이면 전액, 둘 다면 비중대로 나눈 금액이다
String placeText(la.LumpAdvice a, String kind) {
  final all = la.about(a.monthlyInvest);
  if (kind == 'dom') return '매달 투자할 $all 전부를 국내주식에 넣는 거예요(국내 100%).';
  if (kind == 'os') return '매달 투자할 $all 전부를 해외주식에 넣는 거예요(해외 100%).';
  return '매달 투자할 $all 중 국내주식에 ${a.domesticShare}%(${la.about(a.domesticAmount)}), 해외주식에 ${a.overseasShare}%(${la.about(a.overseasAmount)})를 넣는 거예요.';
}

/// 국내주식만 보면 거기서 상담을 끝낸다. 고르기 전에는 비중을 말하지 않는다
LMessage sideStop(la.LumpAdvice? a) {
  if (a != null) return LMessage(text: '국내주식은 지금 쓰시는 증권 계좌로 바로 시작할 수 있어요. ${placeText(a, 'dom')}');
  return const LMessage(text: '국내주식은 상품군으로만 소개해요. 개설 절차는 해외주식을 고를 때 이어가요.');
}

/// 해외주식 계좌 질문 문장. 외화 계좌 유무에 따라 다르다
String accountTail(bool hasFx) =>
    hasFx ? '해외주식은 외화 계좌로 거래하는데, 외화 계좌는 이미 있어요. **해외주식 계좌 개설을 도와드릴까요?**' : '해외주식은 외화 계좌가 필요한데 아직 없네요. **개설 도와드릴까요?**';

/// 해외 계좌 안내와 개설 질문. 해외주식만 보면 전액, 두 시장을 모두 보면(split) 해외 몫을 말한다.
LMessage noAccount(la.LumpAdvice? a, bool split, bool hasFx) {
  var share = '';
  if (a != null) share = split ? '해외주식에는 ${a.overseasShare}%, ${la.about(a.overseasAmount)}을 넣어요. ' : '${placeText(a, 'os')} ';
  return LMessage(text: share + accountTail(hasFx));
}

/// 국내·해외를 모두 보고 싶다고 했을 때: 월 투자금을 나눠 말하고, 해외 계좌 질문으로 잇는다
LMessage bothMessage(la.LumpAdvice a, bool hasFx) => LMessage(blocks: [
      tb('국내주식은 지금 쓰시는 증권 계좌로 바로 시작할 수 있어요. ${placeText(a, 'both')}'),
      tb(accountTail(hasFx)),
    ]);

List<String> thoughtSteps(String kind) => switch (kind) {
      'analysis' => const ['계좌 내역 확인하는 중', '소비를 나누는 중'],
      'decision' => const ['여러 방법 비교하는 중', '부족분을 계산하는 중'],
      'save' => const ['줄이기 목표를 저장하는 중'],
      _ => const ['말씀하신 내용을 읽는 중', '다음 질문을 고르는 중'],
    };

List<String> allFixedLines() {
  final lines = <String>[
    opening,
    typed['GOAL']!,
    typed['PROFILING']!,
    typed['LOSS']!,
    typed['RECOMMEND']!,
    typed['NO_ACCOUNT']!,
    greeting().text,
    situationText(),
    noAccount(null, false, false).text,
    sideStop(null).text,
    leverageRetry().text,
    laterMessage().text,
    investQuestion(null),
    stopMessage(null).text,
    lossAsk().text,
    keepAck(),
  ];
  for (final c in investChoicesDefault) {
    lines.add(c.text);
  }
  for (final id in ['EMERGENCY_FIRST', 'DEBT_FIRST', 'SAVINGS_ENOUGH']) {
    final choices = switch (id) {
      'EMERGENCY_FIRST' => const [LChoice('inv-yes', '그래도 투자도 알아볼게요'), LChoice('inv-no', '아니요, 비상자금부터 채울게요')],
      'DEBT_FIRST' => const [LChoice('inv-yes', '그래도 투자도 알아볼게요'), LChoice('inv-no', '아니요, 상환부터 할게요')],
      _ => const [LChoice('inv-yes', '네, 투자도 해보고 싶어요'), LChoice('inv-no', '아니요, 적금으로 갈게요')],
    };
    lines.addAll(choices.map((c) => c.text));
  }
  lines.addAll(emergencyChoicesLow.map((c) => c.text));
  lines.addAll(introChoices().map((c) => c.text));
  lines.addAll(goalChoices().map((c) => c.text));
  lines.addAll(experienceChoices().map((c) => c.text));
  lines.addAll(lossChoices().map((c) => c.text));
  lines.addAll(productChoices(true).map((c) => c.text));
  lines.addAll(openChoices().map((c) => c.text));
  lines.addAll(spendChoices().map((c) => c.text));
  lines.addAll(spendSteps);
  lines.addAll(overseasIntro(false).blocks.map((b) => b.text));
  lines.addAll(emergencyChoicesHigh.map((c) => c.text));
  lines.addAll([typed['EMERGENCY']!, emergencyStop(null).text]);
  lines.addAll(goalAskMessage(null).blocks.map((b) => b.text));
  return lines;
}
