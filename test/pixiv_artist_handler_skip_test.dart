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

/// Browser whose image pages load fine but carry no URLs, so processImage
/// completes without touching the network or the filesystem.
class _NoUrlBrowser extends _FakeBrowser {
  _NoUrlBrowser(super.config);

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
    return (PixivImage(iid: imageId, parent: parent), '');
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

/// Creates a temp dir, config, DB (seeded with member 99 and images 111/222),
/// browser, and caller. Registers cleanup via [addTearDown] — no manual
/// teardown needed in individual tests.
Future<
    ({
      PixivConfig config,
      PixivDBManager db,
      _FakeBrowser br,
      _Caller caller,
    })> _makeSetup() async {
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

  return (config: config, db: db, br: br, caller: caller);
}

void main() {
  test('processMember skips images already recorded in the DB', () async {
    final (:config, :db, :br, :caller) = await _makeSetup();

    await artist_handler.processMember(
      caller: caller,
      config: config,
      memberId: 99,
      skipKnownImages: true,
    );

    expect(br.imagePageCalls, 0);
    db.close();
  });

  test('onImageComplete fires per processed image, not for skipped ones',
      () async {
    final (:config, :db, br: _, :caller) = await _makeSetup();
    final br = _NoUrlBrowser(config);
    caller.br = br;
    // 111 stays known (skipped); make 222 unknown so it gets processed.
    db.raw.execute('DELETE FROM pixiv_master_image WHERE image_id = 222');
    final completed = <int>[];

    await artist_handler.processMember(
      caller: caller,
      config: config,
      memberId: 99,
      skipKnownImages: true,
      onImageComplete: (id) async => completed.add(id),
    );

    expect(completed, [222]);
    expect(br.imagePageCalls, 1);
    db.close();
  });

  test('a failing onImageComplete aborts the member', () async {
    final (:config, :db, br: _, :caller) = await _makeSetup();
    caller.br = _NoUrlBrowser(config);

    await expectLater(
      artist_handler.processMember(
        caller: caller,
        config: config,
        memberId: 99,
        onImageComplete: (id) async => throw const FileSystemException('x'),
      ),
      throwsA(isA<FileSystemException>()),
    );
    db.close();
  });

  test('processMember does not skip when skipKnownImages is false', () async {
    final (:config, :db, :br, :caller) = await _makeSetup();

    await expectLater(
      artist_handler.processMember(
        caller: caller,
        config: config,
        memberId: 99,
        skipKnownImages: false,
      ),
      throwsStateError,
    );
    expect(br.imagePageCalls, greaterThan(0));
    db.close();
  });
}
