import 'package:cookie_jar/cookie_jar.dart';
import 'package:http/http.dart' as http;
import 'package:pixiv_util2/common/pixiv_browser.dart';
import 'package:pixiv_util2/common/pixiv_config.dart';
import 'package:test/test.dart';

class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.now);

  final DateTime Function() now;
  final requestTimes = <DateTime>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requestTimes.add(now());
    return Future.value(http.StreamedResponse(Stream.value(const []), 200));
  }
}

void main() {
  group('PixivBrowser cookie parsing', () {
    test('accepts browser Cookie header format', () {
      expect(
        PixivBrowser.parseCookieHeader('Cookie: PHPSESSID=abc; user=123'),
        {'PHPSESSID': 'abc', 'user': '123'},
      );
    });

    test('accepts raw PHPSESSID value like upstream PixivUtil2', () {
      expect(PixivBrowser.parseCookieHeader('abc123'), {'PHPSESSID': 'abc123'});
    });

    test('ignores Set-Cookie attributes when pasted into config', () {
      expect(
        PixivBrowser.parseCookieHeader(
          'PHPSESSID=abc; Path=/; Domain=.pixiv.net; Secure; HttpOnly',
        ),
        {'PHPSESSID': 'abc'},
      );
    });
  });

  test('page requests wait before each access after the first', () async {
    final config = PixivConfig()..setValue('downloadDelay', 2);
    var now = DateTime.utc(2026, 6, 13);
    final delays = <Duration>[];
    final client = _RecordingClient(() => now);
    final browser = PixivBrowser(
      config: config,
      cookieJar: CookieJar(),
      client: client,
      now: () => now,
      delay: (duration) async {
        delays.add(duration);
        now = now.add(duration);
      },
    );
    addTearDown(browser.close);

    await Future.wait([
      browser.getContent('https://www.pixiv.net/ajax/one'),
      browser.getContent('https://www.pixiv.net/ajax/two'),
      browser.postContent('https://www.pixiv.net/ajax/three'),
    ]);

    expect(delays, [const Duration(seconds: 2), const Duration(seconds: 2)]);
    expect(client.requestTimes, [
      DateTime.utc(2026, 6, 13),
      DateTime.utc(2026, 6, 13, 0, 0, 2),
      DateTime.utc(2026, 6, 13, 0, 0, 4),
    ]);
  });
}
