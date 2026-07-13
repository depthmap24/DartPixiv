import 'package:pixiv_util2/common/pixiv_config.dart';
import 'package:pixiv_util2/common/pixiv_constant.dart' as pixiv_constant;
import 'package:pixiv_util2/common/pixiv_helper.dart' as pixiv_helper;
import 'package:test/test.dart';

PixivConfig _config(int downloadDelay) {
  final config = PixivConfig();
  config.setValue('downloadDelay', downloadDelay);
  return config;
}

void main() {
  test('wait() sleeps a uniform random 0..downloadDelay seconds '
      '(upstream PixivHelper.wait parity)', () async {
    final delays = <Duration>[];
    int? seenMax;
    await pixiv_helper.wait(
      null,
      _config(5),
      delay: (d) async => delays.add(d),
      randomInt: (max) {
        seenMax = max;
        return 3210;
      },
    );
    expect(seenMax, 5000, reason: 'random range is downloadDelay in ms');
    expect(delays, [const Duration(milliseconds: 3210)]);
  });

  test('wait() still skips entirely on SKIP_DUPLICATE_NO_WAIT', () async {
    final delays = <Duration>[];
    await pixiv_helper.wait(
      pixiv_constant.PIXIVUTIL_SKIP_DUPLICATE_NO_WAIT,
      _config(5),
      delay: (d) async => delays.add(d),
      randomInt: (max) => 1000,
    );
    expect(delays, isEmpty);
  });

  test('wait() does nothing when downloadDelay is 0', () async {
    final delays = <Duration>[];
    await pixiv_helper.wait(
      null,
      _config(0),
      delay: (d) async => delays.add(d),
      randomInt: (max) => 1,
    );
    expect(delays, isEmpty);
  });
}
