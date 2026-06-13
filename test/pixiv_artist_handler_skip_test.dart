import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:pixiv_util2/common/pixiv_browser.dart';
import 'package:pixiv_util2/common/pixiv_config.dart';
import 'package:pixiv_util2/common/pixiv_constant.dart' as pixiv_constant;
import 'package:pixiv_util2/common/pixiv_exception.dart';
import 'package:pixiv_util2/handler/pixiv_artist_handler.dart'
    as artist_handler;
import 'package:pixiv_util2/handler/pixiv_image_handler.dart' as image_handler;
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

class _SuccessfulBrowser extends _FakeBrowser {
  _SuccessfulBrowser(super.config);

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
    final image = PixivImage(iid: imageId, parent: parent)
      ..imageUrls = ['https://i.pximg.net/img-original/$imageId.jpg']
      ..imageCount = 1
      ..imageMode = 'big'
      ..imageTitle = 'title $imageId'
      ..imageCaption = ''
      ..imageTags = []
      ..worksDate = '2026-06-13';
    return (image, '');
  }

  @override
  Future<int> downloadFile(String url, String destination,
      {Map<String, String>? headers}) async {
    await File(destination).writeAsBytes([1, 2, 3], flush: true);
    return 3;
  }
}

class _PartialDownloadBrowser extends _SuccessfulBrowser {
  _PartialDownloadBrowser(super.config);

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
    final (image, page) = await super.getImagePage(
      imageId,
      parent: parent,
      fromBookmark: fromBookmark,
      bookmarkCount: bookmarkCount,
      imageResponseCount: imageResponseCount,
      mangaSeriesOrder: mangaSeriesOrder,
      mangaSeriesParent: mangaSeriesParent,
      tzInfo: tzInfo,
      dateFormat: dateFormat,
      writeRawJSON: writeRawJSON,
      stripHTMLTagsFromCaption: stripHTMLTagsFromCaption,
    );
    image
      ..imageUrls = [
        'https://i.pximg.net/img-original/${imageId}_p0.jpg',
        'https://i.pximg.net/img-original/${imageId}_p1.jpg',
      ]
      ..imageCount = 2
      ..imageMode = 'manga';
    return (image, page);
  }

  @override
  Future<int> downloadFile(String url, String destination,
      {Map<String, String>? headers}) {
    if (url.contains('_p1.')) {
      throw PixivException('second page failed',
          errorCode: PixivException.DOWNLOAD_FAILED_NETWORK);
    }
    return super.downloadFile(url, destination, headers: headers);
  }
}

/// Image pages load with a real URL, but any download attempt fails the
/// test — proves the metadata-only branch never re-downloads the image.
class _MetadataOnlyBrowser extends _FakeBrowser {
  _MetadataOnlyBrowser(super.config);

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
    final image = PixivImage(iid: imageId, parent: parent)
      ..imageUrls = ['https://i.pximg.net/img-original/$imageId.jpg']
      ..imageCount = 1
      ..imageMode = 'big'
      ..imageTitle = 'meta $imageId'
      ..imageCaption = ''
      ..imageTags = []
      ..worksDate = '2026-06-13';
    return (image, '');
  }

  @override
  Future<int> downloadFile(String url, String destination,
      {Map<String, String>? headers}) async {
    throw StateError('metadata-only branch must not download $url');
  }
}

/// Reports the work as deleted on Pixiv when its image page is requested.
class _DeletedMetadataBrowser extends _FakeBrowser {
  _DeletedMetadataBrowser(super.config);

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
    throw PixivException('deleted', errorCode: PixivException.IMAGE_DELETED);
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

  test('one artwork-page access stores picture metadata and reports completion',
      () async {
    final (:config, :db, br: _, :caller) = await _makeSetup();
    final br = _SuccessfulBrowser(config);
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
    expect(db.selectImageByImageId(222), isNotNull);
    expect(db.selectDownloadMetadata(222), containsPair('title', 'title 222'));
    db.close();
  });

  test('fillMissingMetadata fetches metadata only, never re-downloading',
      () async {
    final (:config, :db, br: _, :caller) = await _makeSetup();
    final br = _MetadataOnlyBrowser(config);
    caller.br = br;
    // _makeSetup seeds 111 and 222 with image rows but no metadata.
    final filled = <int>[];
    final completed = <int>[];

    await artist_handler.processMember(
      caller: caller,
      config: config,
      memberId: 99,
      skipKnownImages: true,
      fillMissingMetadata: true,
      onImageComplete: (id) async => completed.add(id),
      onMetadataFilled: (id) async => filled.add(id),
    );

    expect(filled, [111, 222]);
    expect(completed, isEmpty);
    expect(br.imagePageCalls, 2);
    expect(db.selectDownloadMetadata(111), isNotNull);
    expect(db.selectDownloadMetadata(222), containsPair('title', 'meta 222'));
    db.close();
  });

  test('fillMissingMetadata skips works that already have image and metadata',
      () async {
    final (:config, :db, :br, :caller) = await _makeSetup();
    for (final id in [111, 222]) {
      db.insertDownloadMetadata(
        imageId: id,
        title: 'title $id',
        caption: '',
        tags: const [],
        pages: 1,
        worksDate: '2026-06-13',
        totalViews: 0,
        totalRating: 0,
        bookmarkCount: 0,
      );
    }
    final filled = <int>[];

    await artist_handler.processMember(
      caller: caller,
      config: config,
      memberId: 99,
      skipKnownImages: true,
      fillMissingMetadata: true,
      onMetadataFilled: (id) async => filled.add(id),
    );

    expect(br.imagePageCalls, 0); // _FakeBrowser.getImagePage would throw
    expect(filled, isEmpty);
    db.close();
  });

  test('fillMissingMetadata still fully downloads a work with no image row',
      () async {
    final (:config, :db, br: _, :caller) = await _makeSetup();
    final br = _SuccessfulBrowser(config);
    caller.br = br;
    // Give 111 metadata so it is a clean skip; remove 222's image row so it
    // must be downloaded in full.
    db.insertDownloadMetadata(
      imageId: 111,
      title: 'title 111',
      caption: '',
      tags: const [],
      pages: 1,
      worksDate: '2026-06-13',
      totalViews: 0,
      totalRating: 0,
      bookmarkCount: 0,
    );
    db.raw.execute('DELETE FROM pixiv_master_image WHERE image_id = 222');
    final completed = <int>[];
    final filled = <int>[];

    await artist_handler.processMember(
      caller: caller,
      config: config,
      memberId: 99,
      skipKnownImages: true,
      fillMissingMetadata: true,
      onImageComplete: (id) async => completed.add(id),
      onMetadataFilled: (id) async => filled.add(id),
    );

    expect(completed, [222]);
    expect(filled, isEmpty);
    expect(br.imagePageCalls, 1);
    expect(db.selectImageByImageId(222), isNotNull);
    expect(db.selectDownloadMetadata(222), containsPair('title', 'title 222'));
    db.close();
  });

  test('fillMissingMetadata tolerates a deleted work under requireComplete',
      () async {
    final (:config, :db, br: _, :caller) = await _makeSetup();
    final br = _DeletedMetadataBrowser(config);
    caller.br = br;
    // 111 and 222 have image rows but no metadata; the browser reports both
    // deleted when metadata is requested.
    final filled = <int>[];

    // Must NOT throw, even with requireComplete, because deleted works are
    // tolerated (their image is already backed up).
    await artist_handler.processMember(
      caller: caller,
      config: config,
      memberId: 99,
      skipKnownImages: true,
      fillMissingMetadata: true,
      requireComplete: true,
      onMetadataFilled: (id) async => filled.add(id),
    );

    expect(filled, isEmpty);
    expect(br.imagePageCalls, 2);
    expect(db.selectMemberByMemberId(99)!.lastUpdateDate, isNotNull);
    db.close();
  });

  test('strict member processing rejects failed artwork without advancing date',
      () async {
    final (:config, :db, br: _, :caller) = await _makeSetup();
    final br = _NoUrlBrowser(config);
    caller.br = br;
    db.raw.execute('DELETE FROM pixiv_master_image WHERE image_id = 222');
    final completed = <int>[];
    final previousUpdate = db.selectMemberByMemberId(99)!.lastUpdateDate;

    await expectLater(
      artist_handler.processMember(
        caller: caller,
        config: config,
        memberId: 99,
        skipKnownImages: true,
        requireComplete: true,
        onImageComplete: (id) async => completed.add(id),
      ),
      throwsA(isA<PixivException>()),
    );

    expect(completed, isEmpty);
    expect(db.selectImageByImageId(222), isNull);
    expect(db.selectMemberByMemberId(99)!.lastUpdateDate, previousUpdate);
    db.close();
  });

  test('partial multi-page artwork remains unknown for a later retry',
      () async {
    final (:config, :db, br: _, :caller) = await _makeSetup();
    config.setValue('retry', 1);
    final br = _PartialDownloadBrowser(config);
    caller.br = br;
    db.raw.execute('DELETE FROM pixiv_master_image WHERE image_id = 222');

    final result = await image_handler.processImage(
      caller: caller,
      config: config,
      artist: PixivArtist(artistId: 99)
        ..artistName = 'tester'
        ..artistToken = 'tester',
      imageId: 222,
    );

    expect(result, pixiv_constant.PIXIVUTIL_NOT_OK);
    expect(db.selectImageByImageId(222), isNull);
    expect(db.selectDownloadMetadata(222), isNull);
    db.close();
  });

  test('empty caption and tags are valid metadata and are not fetched again',
      () async {
    final (:config, :db, :br, :caller) = await _makeSetup();
    for (final imageId in [111, 222]) {
      db.insertDownloadMetadata(
        imageId: imageId,
        title: 'title $imageId',
        caption: '',
        tags: const [],
        pages: 1,
        worksDate: '2026-06-13',
        totalViews: 0,
        totalRating: 0,
        bookmarkCount: 0,
      );
    }

    await image_handler.processImageMetadataFromDb(
      caller: caller,
      config: config,
    );

    expect(br.imagePageCalls, 0);
    db.close();
  });

  test('stopRequested aborts the member before the next image', () async {
    final (:config, :db, :br, :caller) = await _makeSetup();
    caller.stopRequested = true;

    await artist_handler.processMember(
      caller: caller,
      config: config,
      memberId: 99,
    );

    expect(br.imagePageCalls, 0);
    db.close();
  });

  test('a failing onImageComplete aborts the member', () async {
    final (:config, :db, br: _, :caller) = await _makeSetup();
    caller.br = _SuccessfulBrowser(config);

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
