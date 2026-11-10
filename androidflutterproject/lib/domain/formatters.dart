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

/// 1500000 -> "150만원", 1234567 -> "1,234,567원"
String formatMan(num? value) {
  final v = (value ?? 0).round();
  if (v >= 10000 && v % 10000 == 0) {
    final man = v ~/ 10000;
    if (man >= 10000 && man % 10000 == 0) return '${man ~/ 10000}억원';
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
