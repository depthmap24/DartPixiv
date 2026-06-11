import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:pixiv_util2/common/pixiv_browser.dart';
import 'package:pixiv_util2/common/pixiv_config.dart';
import 'package:pixiv_util2/handler/pixiv_artist_handler.dart'
    as artist_handler;
import 'package:pixiv_util2/model/pixiv_artist.dart';
import 'package:pixiv_util2/model/pixiv_image.dart';
import 'package:pixiv_util2/pixiv_db_manager.dart';
import 'package:test/test.dart';

/// Browser whose member page lists two known images; fetching an image
/// page (the first step of a download) fails the test.
class _FakeBrowser extends PixivBrowser {
  _FakeBrowser(PixivConfig config)
      : super(config: config, cookieJar: CookieJar());

  int imagePageCalls = 0;

  @override
  Future<(PixivArtist, String)> getMemberPage(
    int memberId, {
    int page = 1,
    int? referenceImageId,
    bool tagsOnly = false,
    String? tags,
  }) async {
    final artist = PixivArtist(artistId: memberId)
      ..artistName = 'tester'
      ..artistToken = 'tester'
      ..imageList = [111, 222];
    return (artist, '');
  }

  @override
  Future<(PixivImage, String)> getImagePage(
    int imageId, {
    PixivArtist? parent,
    bool fromBookmark = false,
    int bookmarkCount = -1,
    int imageResponseCount = -1,
    int mangaSeriesOrder = -1,
    PixivMangaSeries? mangaSeriesParent,
    Duration? tzInfo,
    String? dateFormat,
    bool writeRawJSON = false,
    bool stripHTMLTagsFromCaption = false,
  }) async {
    imagePageCalls++;
    throw StateError('image $imageId should have been skipped via the DB');
  }
}

class _Caller {
  _Caller({required this.config, required this.br, required this.dbManager});

  PixivConfig config;
  PixivBrowser br;
  PixivDBManager dbManager;
  int errorCode = 0;
  bool DEBUG_SKIP_PROCESS_IMAGE = false;
  bool DEBUG_SKIP_DOWNLOAD_IMAGE = false;
  bool stopRequested = false;
  List<dynamic> errorList = [];
}

void main() {
  test('processMember skips images already recorded in the DB', () async {
    final tmp = Directory.systemTemp.createTempSync('dartpixiv_skip_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final config = PixivConfig();
    await config.loadConfig('${tmp.path}/config.ini');
    config.setValue('rootDirectory', tmp.path);
    config.setValue('disableLog', true);

    final db = PixivDBManager(
      rootDirectory: tmp.path,
      target: '${tmp.path}/db.sqlite',
    )..createDatabase();
    db.insertNewMember(99);
    db.insertImage(111, 99, saveName: 'a.jpg', title: 'old title');
    db.insertImage(222, 99, saveName: 'b.jpg', title: 'old title');

    final br = _FakeBrowser(config);
    final caller = _Caller(config: config, br: br, dbManager: db);

    await artist_handler.processMember(
      caller: caller,
      config: config,
      memberId: 99,
      skipKnownImages: true,
    );

    expect(br.imagePageCalls, 0);
    db.close();
  });
}
