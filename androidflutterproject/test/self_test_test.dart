// 시연 제어의 자가 테스트(계획 7장 검증 항목)를 flutter test에서도 그대로 실행한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:won_solution_pass/demo/self_test.dart';

void main() {
  test('자가 테스트 전체 통과', () async {
    final report = await runSelfTests(onProgress: (r) => printOnFailure('${r.ok ? '✔' : '✘'} ${r.name}'));
    final failed = report.results.where((r) => !r.ok).map((r) => '${r.name} — ${r.detail}').join('\n');
    expect(report.failed, 0, reason: failed);
    expect(report.total, selfTestCount);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
