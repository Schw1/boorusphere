import 'package:boorusphere/presentation/screens/post/post_video.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formatVideoTime', () {
    expect(formatVideoTime(Duration.zero), '0:00');
    expect(formatVideoTime(const Duration(seconds: 9)), '0:09');
    expect(formatVideoTime(const Duration(minutes: 3, seconds: 7)), '3:07');
    expect(
      formatVideoTime(const Duration(hours: 1, minutes: 2, seconds: 3)),
      '1:02:03',
    );
    expect(formatVideoTime(const Duration(seconds: -5)), '0:00');
  });
}
