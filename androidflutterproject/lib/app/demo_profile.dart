/// 시연 패널의 페르소나(수입·지출·부채). 앱의 계좌 정보에 BANK 출처로 넣는다.
library;

import 'dart:convert';

import '../data/bank_store.dart';
import '../data/key_value_storage.dart';
import '../domain/bank_state.dart';
import '../domain/formatters.dart';
import '../domain/lumpsum_advisor.dart' as la;

const String demoProfileKey = 'wsp.demoProfile.v1';

class DemoProfile {
  const DemoProfile({this.income = 3500000, this.expense = 2100000, this.debtOn = false, this.debt = 0, this.personaDone = false});
  final int income;
  final int expense;
  final bool debtOn;
  final int debt;
  final bool personaDone;

  int get debtValue => debtOn ? debt : 0;

  DemoProfile copyWith({int? income, int? expense, bool? debtOn, int? debt, bool? personaDone}) {
    final on = debtOn ?? this.debtOn;
    return DemoProfile(
      income: income ?? this.income,
      expense: expense ?? this.expense,
      debtOn: on,
      debt: on ? (debt ?? this.debt) : 0,
      personaDone: personaDone ?? this.personaDone,
    );
  }

  Json toJson() => {'income': income, 'expense': expense, 'debtOn': debtOn, 'debt': debt, 'personaDone': personaDone};
  factory DemoProfile.fromJson(Json j) => DemoProfile(
        income: asInt(j['income']) ?? 3500000,
        expense: asInt(j['expense']) ?? 2100000,
        debtOn: j['debtOn'] == true,
        debt: asInt(j['debt']) ?? 0,
        personaDone: j['personaDone'] == true,
      );
}

const DemoProfile baseProfile = DemoProfile();

/// 프리셋 id: base | spend | debt
DemoProfile presetProfile(String id, DemoProfile cur) => switch (id) {
      'spend' => cur.copyWith(income: 3500000, expense: 3600000, debtOn: false, debt: 0),
      'debt' => cur.copyWith(income: 3500000, expense: 2100000, debtOn: true, debt: 30000000),
      _ => cur.copyWith(income: 3500000, expense: 2100000, debtOn: false, debt: 0),
    };

/// 천만원 단위로 딱 떨어지면 "3천만원"처럼 읽기 쉽게 쓴다
String manText(int n) {
  final man = n / 10000;
  if (man >= 1000 && man % 1000 == 0 && man < 10000) return '${(man / 1000).round()}천만원';
  return formatMan(n);
}

class PersonaSummary {
  const PersonaSummary(this.preset, this.lines);
  final String preset;
  final List<String> lines;
}

/// 페르소나 요약 줄과 프리셋 이름. 값이 프리셋과 똑같을 때만 이름을 붙인다
PersonaSummary personaSummary(DemoProfile p) {
  final debt = p.debtValue;
  final pay = la.debtPayment(debt);
  var preset = '';
  if (p.income == 3500000 && p.expense == 2100000 && !p.debtOn) {
    preset = '기본';
  } else if (p.income == 3500000 && p.expense == 3600000 && !p.debtOn) {
    preset = '여유 없음';
  } else if (p.income == 3500000 && p.expense == 2100000 && p.debtOn && p.debt == 30000000) {
    preset = '부채 있음';
  }
  return PersonaSummary(preset, [
    '수입 ${formatMan(p.income)}',
    '지출 ${formatMan(p.expense)}',
    debt > 0 ? '부채 ${manText(debt)} · 월 상환 ${formatMan(pay)}' : '부채 없음',
    '월 여유 ${la.manSigned(p.income - p.expense - pay)}',
  ]);
}

class DemoProfileStore {
  DemoProfileStore({required this.store, this.storage}) : profile = _load(storage);

  final BankStore store;
  final KeyValueStorage? storage;
  DemoProfile profile;

  static DemoProfile _load(KeyValueStorage? storage) {
    try {
      final raw = storage?.read(demoProfileKey);
      if (raw == null) return baseProfile;
      return DemoProfile.fromJson(asJson(jsonDecode(raw)));
    } catch (_) {
      return baseProfile;
    }
  }

  void set(DemoProfile next) {
    profile = next;
    storage?.write(demoProfileKey, jsonEncode(profile.toJson()));
    apply();
  }

  void reapply() {
    profile = _load(storage);
    apply();
  }

  void apply() {
    final p = profile;
    final debt = p.debtValue;
    final pay = la.debtPayment(debt);
    store.update((d) {
      d.finance.items['monthlyIncome'] = FinItem(value: p.income, source: 'BANK', basis: '보유 입출금 계좌의 급여 내역');
      d.finance.items['monthlyExpense'] = FinItem(value: p.expense, source: 'BANK', basis: '보유 입출금 계좌의 지출 내역');
      d.finance.items['debt'] = FinItem(value: debt, source: 'BANK', basis: debt > 0 ? '보유 계좌 기준 대출 잔액' : '보유 계좌 기준 대출 없음');
      d.finance.items['debtPayment'] = FinItem(value: pay, source: 'BANK', basis: debt > 0 ? '원리금 균등, 연 5.5%, 60개월' : '보유 계좌 기준 상환 내역 없음');
    }, '시연 프로필');
  }
}
