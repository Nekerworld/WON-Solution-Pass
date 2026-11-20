/// 시연 화면 "해결패스가 알고 있는 정보" 카드의 내용을 만드는 순수 함수.
/// 처음에는 목표만 있고, 목표가 정해지면 그 목표에 필요한 항목이 줄로 늘어난다.
/// 입력은 상담 세션과 상태 문자열뿐이다. 새 상태는 만들지 않는다.
library;

import '../app/sessions.dart';
import 'asset_advisor.dart' as aa;
import 'formatters.dart';
import 'lumpsum_advisor.dart' as la;

const String unknownText = '아직 모름';
const String declinedText = '답하지 않음';
const String skippedText = '묻지 않음';
const String noGoalText = '아직 없음';

const Map<String, String> kindLabel = {
  'LUMP_SUM': '목돈 마련',
  'OVERSEAS_ACCOUNT': '해외주식 계좌 개설',
  'DOMESTIC_STOCK': '국내주식 투자 알아보기',
  'LEVERAGE': '레버리지 상품 알아보기',
  'EMERGENCY': '비상자금 점검',
};

const Map<String, String> profileLabel = {'STABLE': '안정', 'NEUTRAL': '중립', 'ACTIVE': '적극'};
const List<String> experienceLabel = ['해본 적 없음', '소액 ETF 경험', '국내주식을 자주'];
const List<String> lossLabel = ['바로 판다', '길게 버틴다', '더 산다'];

class GoalInfoRow {
  const GoalInfoRow(this.label, this.value, [this.note = '']);
  final String label;
  final String value;
  final String note;
}

class GoalInfo {
  const GoalInfo({required this.flow, required this.goalId, required this.rows});

  /// lumpsum | asset | none
  final String flow;
  final String goalId;
  final List<GoalInfoRow> rows;
}

/// 0.0723 → "7.2%", 0.07 → "7%"
String _pct(double rate) {
  final v = la.jsRound(rate * 1000) / 10;
  return '${v.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')}%';
}

/* ---------------- 목돈 상담 ---------------- */

String _periodText(la.LumpGoal goal) {
  final m = goal.months;
  return '${m % 12 == 0 ? '${m ~/ 12}년' : '$m개월'} · ${formatMan(goal.amount)}';
}

String _fxText(bool applied, bool approved, bool? hasFx) => applied ? (approved ? '개설 완료' : '승인 대기') : (hasFx == true ? '개설 중' : '없음');

GoalInfo _lumpRows(LumpsumSession s, String state, bool applied, bool? hasFx, bool approved) {
  final kind = s.goalKind;
  if (kind.isEmpty) return const GoalInfo(flow: 'lumpsum', goalId: '', rows: [GoalInfoRow('목표', noGoalText)]);
  final ended = state == 'CLOSED' || state == 'SPEND_PLAN';
  final blank = ended ? skippedText : unknownText;
  final rows = <GoalInfoRow>[GoalInfoRow('목표', (kind == 'LUMP_SUM' && s.purposeLabel.isNotEmpty) ? s.purposeLabel : (kindLabel[kind] ?? ''))];
  // 비상자금만 보는 동안은 목표 금액·성향을 묻지 않으므로 예금이 생활비 몇 개월치인지만 보여 준다
  if (s.intent == 'EMERGENCY') {
    final sn = s.snap;
    if (sn.expense > 0) rows.add(GoalInfoRow('비상자금', '생활비 ${aa.numText(la.jsRound(sn.deposit / sn.expense * 10) / 10)}개월치', '기준 3개월'));
    return GoalInfo(flow: 'lumpsum', goalId: kind, rows: rows);
  }
  // 해외주식 칩으로 바로 계좌 개설로 간 채팅은 목표·성향을 묻지 않으므로 계좌 상태만 남긴다
  if (s.intent == 'OVERSEAS') {
    rows.add(GoalInfoRow('해외 계좌', _fxText(applied, approved, hasFx)));
    return GoalInfo(flow: 'lumpsum', goalId: kind, rows: rows);
  }
  final goal = s.goal;
  rows.add(GoalInfoRow('목표 금액·기간', goal != null ? _periodText(goal) : blank));
  final prof = s.expText.isNotEmpty && s.lossText.isNotEmpty ? la.inferRiskProfile(s.expText, s.lossText) : null;
  rows.add(GoalInfoRow('투자 경험', s.expText.isNotEmpty ? experienceLabel[la.inferRiskProfile(s.expText, '').experience] : blank));
  rows.add(GoalInfoRow('손실 감내', s.lossText.isNotEmpty ? lossLabel[la.inferRiskProfile('', s.lossText).loss] : blank));
  rows.add(GoalInfoRow('투자 성향', prof != null ? (profileLabel[prof.id] ?? '') : blank));
  if (kind != 'LUMP_SUM') {
    final a = s.advice;
    rows.add(GoalInfoRow('월 투자 참고 금액', a != null ? '월 ${la.about(a.monthlyInvest)}' : blank));
    if (kind == 'LEVERAGE') {
      rows.add(GoalInfoRow('필요한 연 수익', a != null ? '연 ${_pct(a.yieldRate)}' : blank));
    } else if (kind == 'DOMESTIC_STOCK') {
      rows.add(GoalInfoRow('국내 비중', a != null ? '100%' : blank));
    } else {
      // 해외만 보면 해외 100%, 두 시장을 모두 보면 추천 비중으로 나눈다
      if (s.market == 'both') {
        rows.add(GoalInfoRow('국내 비중', a != null ? '${a.domesticShare}%' : blank));
        rows.add(GoalInfoRow('해외 비중', a != null ? '${a.overseasShare}%' : blank));
      } else {
        rows.add(GoalInfoRow('해외 비중', a != null ? '100%' : blank));
      }
      rows.add(GoalInfoRow('해외 계좌', _fxText(applied, approved, hasFx)));
    }
  }
  return GoalInfo(flow: 'lumpsum', goalId: kind, rows: rows);
}

/* ---------------- 이전 자산관리 상담 ---------------- */

String _gapText(aa.AssetInfo? info, String key) {
  final it = info?.items[key];
  if (info == null || it == null) return unknownText;
  if (info.declined.contains(key)) return declinedText;
  final value = it.value;
  if (value == null) return unknownText;
  if (value == 0) return '없음';
  if (value > 0) return formatWon(value);
  return unknownText;
}

String _displayText(aa.AssetInfo? info, String key) {
  final it = info?.items[key];
  if (info == null || it == null) return unknownText;
  if (info.declined.contains(key)) return declinedText;
  final value = it.value;
  return value == null ? unknownText : aa.display(key, value);
}

bool _fromAccount(aa.AssetInfo? info, String key) {
  final it = info?.items[key];
  return it != null && it.value != null && it.source == 'BANK';
}

GoalInfo _assetRows(AssetSession a) {
  final info = a.info;
  final purpose = aa.purposes.containsKey(a.purpose) ? a.purpose : 'GOAL_SAVING';
  if (a.goalText.isEmpty) return const GoalInfo(flow: 'asset', goalId: '', rows: [GoalInfoRow('목표', noGoalText)]);
  final rows = <GoalInfoRow>[GoalInfoRow('목표', aa.purposes[purpose]!.label, a.goalText)];
  const basics = [('월 소득', 'monthlyIncome'), ('월 지출', 'monthlyExpense'), ('예금성 자산', 'liquidAssets')];
  if (purpose == 'INVEST') {
    rows.add(GoalInfoRow('투자 속도', _displayText(info, 'investPace')));
    rows.add(GoalInfoRow('다른 증권 투자금', _gapText(info, 'investAssets')));
    rows.add(GoalInfoRow('목돈 지출 계획', _gapText(info, 'plannedLumpSum')));
  } else if (purpose == 'GOAL_SAVING') {
    rows.add(GoalInfoRow('목표 금액', _gapText(info, 'goalAmount')));
    rows.add(GoalInfoRow('목표 기간', _displayText(info, 'goalMonths')));
    rows.add(GoalInfoRow('목돈 지출 계획', _gapText(info, 'plannedLumpSum')));
    if (info?.items['monthlySavingPref']?.value != null) rows.add(GoalInfoRow('희망 월 적립액', _gapText(info, 'monthlySavingPref')));
  }
  if (purpose == 'EMERGENCY' || purpose == 'ORIENT') {
    rows.add(GoalInfoRow('월 지출', _gapText(info, 'monthlyExpense')));
    rows.add(GoalInfoRow('예금성 자산', _gapText(info, 'liquidAssets')));
    rows.add(GoalInfoRow('월 소득', _gapText(info, 'monthlyIncome')));
  } else {
    for (final (label, key) in basics) {
      if (!_fromAccount(info, key)) rows.add(GoalInfoRow(label, _gapText(info, key)));
    }
  }
  return GoalInfo(flow: 'asset', goalId: purpose, rows: rows);
}

GoalInfo describe({
  LumpsumSession? lumpsum,
  String lumpsumState = 'IDLE',
  AssetSession? asset,
  String assetState = 'IDLE',
  bool applied = false,
  bool approved = false,
  bool? hasFxAccount,
}) {
  if (lumpsum != null && lumpsumState.isNotEmpty && lumpsumState != 'IDLE') return _lumpRows(lumpsum, lumpsumState, applied, hasFxAccount, approved);
  if (asset != null) return _assetRows(asset);
  return const GoalInfo(flow: 'none', goalId: '', rows: [GoalInfoRow('목표', noGoalText)]);
}
