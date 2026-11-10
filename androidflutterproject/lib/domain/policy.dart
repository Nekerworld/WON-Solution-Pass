/// 데모용 가상 정책 - 실제 우리은행 정책이 아니다.
///
/// 화면에 표시되는 모든 한도·인증 규칙은 이 값에서 나오며, 시연을 위해 정의한 값이다.
abstract final class DemoPolicy {
  static const String version = 'DEMO-POLICY-2026.11';
  static const bool isDemo = true;

  /// 이 금액을 초과하는 이체는 디지털 OTP 등록이 필요하다 (가상)
  static const int otpRequiredAbove = 1000000;

  /// OTP 없이 설정할 수 있는 1일 이체한도 상한 (가상)
  static const int maxLimitWithoutOtp = 1000000;

  /// 디지털 OTP 등록 전 고객확인 완료가 필요하다 (가상)
  static const bool otpRegistrationRequiresKyc = true;

  static const int minTransferLimit = 100000;
  static const int maxTransferLimit = 50000000;

  /// 해결 행동별 비용 가중치 (가상). 상태 그래프 간선의 weight로 쓰이며,
  /// 경로 탐색은 이 합이 최소인 경로를 고른다.
  /// 비용 = 사용자 부담(소요 시간·입력량) + 인증 강도 + 채널 제약을 단순 점수화한 값
  static const Map<String, int> actionWeights = {
    'COMPLETE_KYC': 5,
    'REGISTER_OTP': 3,
    'CHANGE_TRANSFER_LIMIT': 2,
    'RETURN_TO_TRANSFER': 1,
  };
}
