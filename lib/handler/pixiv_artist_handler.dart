/// Artist (member) handler.
library;

import '../common/pixiv_browser.dart';
import '../common/pixiv_config.dart';
import '../common/pixiv_constant.dart' as pixiv_constant;
import '../common/pixiv_exception.dart';
import '../common/pixiv_helper.dart' as pixiv_helper;
import 'pixiv_image_handler.dart' as image_handler;

/// Update only the metadata for [memberId] (no image downloads).
Future<void> processMemberMetadata({
  required dynamic caller,
  required PixivConfig config,
  required int memberId,
  bool bookmark = false,
  String? tags,
  String titlePrefix = '',
  void Function({String? title, String? message, dynamic type})? notifier,
}) async {
  notifier ??= pixiv_helper.dummyNotifier;
  pixiv_helper.printAndLog('info', 'Processing Member Metadata: $memberId');
  try {
    pixiv_helper.setConsoleTitle('${titlePrefix}MemberId: $memberId');
    final br = caller.br as PixivBrowser;
    final (artist, _) = await br.getMemberPage(memberId, tags: tags);
    pixiv_helper.printAndLog(null, 'Member Name   : ${artist.artistName}');
    pixiv_helper.printAndLog(null, 'Member Avatar : ${artist.artistAvatar}');
    pixiv_helper.printAndLog(null, 'Member Token  : ${artist.artistToken}');
    pixiv_helper.printAndLog(
        null, 'Member Backgrd: ${artist.artistBackground}');

    final db = caller.dbManager;
    db.insertNewMember(memberId);
    db.updateMemberName(memberId, artist.artistName);
    db.updateMemberToken(memberId, artist.artistToken);
    pixiv_helper.printAndLog('info', 'Member_id: $memberId metadata updated.');
  } on PixivException catch (e) {
    caller.errorCode = e.errorCode;
    pixiv_helper.printAndLog('info', 'Member ID ($memberId): $e');
    rethrow;
  } catch (e) {
    pixiv_helper.printAndLog('error', 'Error at processMemberMetadata(): $e');
    rethrow;
  }
}

/// Process a single member: fetch the image list and download each image.
///
/// [onImageComplete] is awaited after each image has been processed (it is
/// not called for images skipped via [skipKnownImages]). Callers can use it
/// to move the finished files elsewhere before the next image starts; an
/// exception thrown by the callback aborts the member. When [requireComplete]
/// is true, any failed artwork prevents the member's last-download date from
/// advancing and throws after the full list has been checked.
/// When [fillMissingMetadata] is true, a work that already has its image but
/// no metadata row is not skipped: its metadata is fetched on its own (one
/// request, no image re-download) and [onMetadataFilled] is awaited on
/// success. A work deleted on Pixiv is tolerated here (its image is already
/// saved) and does not count against [requireComplete].
Future<void> processMember({
  required dynamic caller,
  required PixivConfig config,
  required int memberId,
  String userDir = '',
  bool bookmark = false,
  String? tags,
  String titlePrefix = '',
  int startPage = 1,
  int endPage = 0,
  bool skipKnownImages = false,
  bool requireComplete = false,
  Future<void> Function(int imageId)? onImageComplete,
  bool fillMissingMetadata = false,
  Future<void> Function(int imageId)? onMetadataFilled,
  void Function({String? title, String? message, dynamic type})? notifier,
}) async {
  notifier ??= pixiv_helper.dummyNotifier;
  pixiv_helper.setConsoleTitle('${titlePrefix}MemberId: $memberId');
  pixiv_helper.printAndLog('info', 'Processing Member: $memberId (tags=$tags)');
  final br = caller.br as PixivBrowser;
  final (artist, _) =
      await br.getMemberPage(memberId, page: startPage, tags: tags);
  artist.printInfo();

  if (artist.imageList.isEmpty) {
    pixiv_helper.printAndLog('warn', 'Member $memberId has no images.');
    return;
  }

  final failedImages = <int>[];
  var i = 1;
  for (final imageId in artist.imageList) {
    if (caller.stopRequested == true) {
      pixiv_helper.printAndLog(
          'info', 'Stop requested - aborting member $memberId.');
      return;
    }
    try {
      if (skipKnownImages &&
          caller.dbManager.selectImageByImageId(imageId) != null) {
        final hasMetadata =
            caller.dbManager.selectDownloadMetadata(imageId) != null;
        if (hasMetadata || !fillMissingMetadata) {
          pixiv_helper.printAndLog(
              'info', 'Image $imageId already in DB - skipped.');
          i++;
          continue;
        }
        // Image is saved but its metadata row is missing: fetch metadata
        // only (one request, no image re-download) so a later run can treat
        // the work as fully complete.
        pixiv_helper.printAndLog('info',
            'Image $imageId missing metadata - fetching metadata only.');
        try {
          await image_handler.processImageMetadata(
            caller: caller,
            config: config,
            imageId: imageId,
            notifier: notifier,
          );
          if (onMetadataFilled != null) {
            await onMetadataFilled(imageId);
          }
        } on PixivException catch (e) {
          if (e.errorCode == PixivException.IMAGE_DELETED) {
            pixiv_helper.printAndLog('info',
                'Image $imageId deleted on Pixiv - metadata skip tolerated.');
          } else {
            failedImages.add(imageId);
            pixiv_helper.printAndLog('error',
                'Failed metadata fetch for image $imageId: ${e.message}');
          }
        }
        i++;
        continue;
      }
      pixiv_helper.printAndLog(
          null, '#$i of ${artist.imageList.length} - image_id=$imageId');
      final result = await image_handler.processImage(
        caller: caller,
        config: config,
        artist: artist,
        imageId: imageId,
        userDir: userDir,
        bookmark: bookmark,
        searchTags: tags ?? '',
        titlePrefix: titlePrefix,
        notifier: notifier,
      );
      final complete = result == pixiv_constant.PIXIVUTIL_OK ||
          result == pixiv_constant.PIXIVUTIL_SKIP_DUPLICATE ||
          result == pixiv_constant.PIXIVUTIL_SKIP_BLACKLIST;
      if (!complete) {
        failedImages.add(imageId);
      } else if (onImageComplete != null) {
        await onImageComplete(imageId);
      }
    } on PixivException catch (e) {
      failedImages.add(imageId);
      pixiv_helper.printAndLog(
          'error', 'Failed to process image $imageId: ${e.message}');
    }
    i++;
    if (endPage > 0 && i > endPage * 60) {
      pixiv_helper.printAndLog('info', 'Reached page limit $endPage');
      break;
    }
  }
  if (requireComplete && failedImages.isNotEmpty) {
    throw PixivException(
      'Member $memberId incomplete; failed artwork(s): '
      '${failedImages.join(', ')}',
      errorCode: PixivException.DOWNLOAD_FAILED_OTHER,
    );
  }
  caller.dbManager.updateLastDownloadedImage(memberId, artist.imageList.first);
  pixiv_helper.printAndLog('info', 'Done with member $memberId.');
}

/// Process a member's image bookmarks.
Future<void> processMemberBookmark({
  required dynamic caller,
  required PixivConfig config,
  required int memberId,
  String? tags,
  String titlePrefix = '',
}) async {
  pixiv_helper.printAndLog(
      'info', 'Processing Bookmarked images for member $memberId');
  // The browser layer would expose dedicated calls; here we re-use the standard
  // page request and treat each image as a bookmark.
  await processMember(
    caller: caller,
    config: config,
    memberId: memberId,
    tags: tags,
    bookmark: true,
    titlePrefix: titlePrefix,
  );
}

/// Constants re-exported for convenience.
const int artistHandlerOk = pixiv_constant.PIXIVUTIL_OK;
const int artistHandlerNotOk = pixiv_constant.PIXIVUTIL_NOT_OK;
