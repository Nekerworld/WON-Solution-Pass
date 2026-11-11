import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// 태블릿처럼 넓은 화면에서 본문을 가운데 한 단으로 모을 때의 최대 폭 (좌우 여백 포함)
const double kContentMaxWidth = 640;

/// 하단 시트·확인 모달의 최대 폭
const double kSheetMaxWidth = 560;

/// 휴대폰·태블릿 OS (웹·데스크톱 제외)
bool get isMobileOS => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

/// 화면 폭이 [maxWidth]를 넘을 때 본문 단을 가운데에 두기 위한 한쪽 추가 여백
double wideInset(double width, [double maxWidth = kContentMaxWidth]) => width > maxWidth ? (width - maxWidth) / 2 : 0;

/// 현재 화면 폭 기준 [wideInset]
double wideInsetOf(BuildContext context, [double maxWidth = kContentMaxWidth]) => wideInset(MediaQuery.sizeOf(context).width, maxWidth);

/// 자식을 가운데 정렬하고 폭을 [maxWidth]로 제한한다 (높이는 자식 크기)
class MaxWidth extends StatelessWidget {
  const MaxWidth({super.key, required this.child, this.maxWidth = kContentMaxWidth});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      heightFactor: 1,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
    );
  }
}
