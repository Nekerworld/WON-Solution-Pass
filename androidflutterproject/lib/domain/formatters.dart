import 'dart:math';

/// 1500000 -> "1,500,000"
String groupDigits(num value) {
  final n = value.round();
  final negative = n < 0;
  final digits = n.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return negative ? '-$buf' : buf.toString();
}

/// 1500000 -> "1,500,000원"
String formatWon(num? value) => '${groupDigits(value ?? 0)}원';

/// 1500000 -> "150만원", 1234567 -> "1,234,567원", 120000000 -> "1억 2,000만원"
String formatMan(num? value) {
  final v = (value ?? 0).round();
  if (v >= 10000 && v % 10000 == 0) {
    final man = v ~/ 10000;
    if (man >= 10000) {
      final eok = man ~/ 10000;
      final rest = man % 10000;
      return '$eok억${rest != 0 ? ' ${groupDigits(rest)}만' : ''}원';
    }
    return '${groupDigits(man)}만원';
  }
  return formatWon(v);
}

/// 문자열에서 숫자만 뽑는다. "1,500,000원" -> 1500000
int digitsOf(String? text) {
  final only = (text ?? '').replaceAll(RegExp(r'[^\d]'), '');
  if (only.isEmpty) return 0;
  return int.tryParse(only) ?? 0;
}

String pad2(int n) => n < 10 ? '0$n' : '$n';

/// HH:mm:ss
String formatClock(DateTime t) => '${pad2(t.hour)}:${pad2(t.minute)}:${pad2(t.second)}';

/// [받침 있음, 받침 없음, 판단 불가]
const Map<String, List<String>> _josa = {
  '을': ['을', '를', '을(를)'],
  '이': ['이', '가', '이(가)'],
  '은': ['은', '는', '은(는)'],
  '과': ['과', '와', '과(와)'],
  '로': ['으로', '로', '(으)로'],
  '이에요': ['이에요', '예요', '(이)에요'],
};

/// 받침에 맞춘 조사를 붙인다. josa('계좌', '을') → '계좌를'. 끝의 괄호 보충 설명은 건너뛰고 판단한다.
String josa(String word, String kind) {
  final forms = _josa[kind]!;
  final base = word.replaceFirst(RegExp(r'\s*\([^)]*\)\s*$'), '');
  if (base.isEmpty) return word + forms[2];
  final code = base.codeUnitAt(base.length - 1) - 0xac00;
  if (code < 0 || code > 11171) return word + forms[2];
  final jong = code % 28;
  if (kind == '로') return word + (jong == 0 || jong == 8 ? forms[1] : forms[0]);
  return word + (jong == 0 ? forms[1] : forms[0]);
}

final Random _rand = Random();

/// 시연용 식별자. 'TS-3ENF1MBE'
String newId(String prefix) {
  final t = DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase();
  final r = List.generate(3, (_) => '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'[_rand.nextInt(36)]).join();
  return '$prefix-${t.substring(max(0, t.length - 5))}$r';
}
