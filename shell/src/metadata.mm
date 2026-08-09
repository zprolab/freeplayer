// FreePlayer shell — audio metadata extraction via AVFoundation
// Replaces music-metadata (electron). Synchronous (semaphore) so the
// import loop stays simple; call from a background queue.

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#include <CoreMedia/CoreMedia.h>
#include <AudioToolbox/AudioToolbox.h>
#include <dispatch/dispatch.h>
#include "db.h"

namespace fpmeta {

static NSString *firstValue(NSArray<AVMetadataItem *> *items, NSString *key) {
  for (AVMetadataItem *it in items) {
    if ([it.commonKey isEqualToString:key] && it.value) {
      return [it.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
  }
  return nil;
}

// Strip downloader suffixes: "Artist - Title_EM.flac" -> "Artist - Title"
NSString *cleanAudioStem(NSString *stem) {
  NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"_[A-Za-z]{1,4}$" options:0 error:nil];
  return [re stringByReplacingMatchesInString:stem options:0 range:NSMakeRange(0, stem.length) withTemplate:@""];
}

// Try to find a sidecar .lrc for an audio file (same dir, same stem,
// tolerant of _EM/_L downloader suffixes and prefix-style names).
NSString *findSidecarLrc(NSString *audioPath) {
  NSString *dir = audioPath.stringByDeletingLastPathComponent;
  NSString *audioStem = cleanAudioStem(audioPath.lastPathComponent.stringByDeletingPathExtension);
  NSArray<NSString *> *lrcs = [NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:nil];
  NSMutableArray *candidates = [NSMutableArray array];
  for (NSString *name in lrcs) {
    if ([name.pathExtension.lowercaseString isEqualToString:@"lrc"]) {
      NSString *stem = cleanAudioStem(name.stringByDeletingPathExtension);
      if ([stem isEqualToString:audioStem]) {
        return [dir stringByAppendingPathComponent:name]; // exact match wins
      }
      [candidates addObject:@[ stem, name ]];
    }
  }
  // Prefix match: "Welcome Home" is a prefix of "Welcome Home, Son (Remaster)".
  // Auto-fetched sidecars are "<stem>.<trackId>.lrc" — a numeric suffix must
  // never prefix-match a sibling track, so skip ".<digits>" stems here.
  for (NSArray *pair in candidates) {
    NSString *stem = pair[0];
    if ([stem rangeOfString:@"\\.[0-9]+$" options:NSRegularExpressionSearch].location != NSNotFound) {
      continue;
    }
    NSString *a = audioStem.lowercaseString;
    NSString *s = stem.lowercaseString;
    NSUInteger minLen = MIN(a.length, s.length);
    if (minLen >= 8 && [s hasPrefix:a]) {
      return [dir stringByAppendingPathComponent:pair[1]];
    }
  }
  return nil;
}

// Parse FLAC VORBIS_COMMENT block manually (AVFoundation hides these tags).
// Returns nil if the file isn't a FLAC / has no comments.
static NSDictionary *parseFlacVorbisComments(NSString *path) {
  NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
  if (data.length < 4 || memcmp(data.bytes, "fLaC", 4) != 0) return nil;

  const uint8_t *p = (const uint8_t *)data.bytes + 4;
  NSUInteger remaining = data.length - 4;
  while (remaining >= 4) {
    uint8_t blockHeader = p[0];
    int type = blockHeader & 0x7f;
    uint32_t len = ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3];
    p += 4; remaining -= 4;
    if (remaining < len) return nil;

    if (type == 4) { // VORBIS_COMMENT
      const uint8_t *c = p;
      NSUInteger cRem = len;
      // vendor string (4-byte LE length + data)
      if (cRem < 4) return nil;
      uint32_t vendorLen = c[0] | (c[1] << 8) | (c[2] << 16) | ((uint32_t)c[3] << 24);
      c += 4; cRem -= 4;
      if (cRem < vendorLen) return nil;
      c += vendorLen; cRem -= vendorLen;
      if (cRem < 4) return nil;
      uint32_t count = c[0] | (c[1] << 8) | (c[2] << 16) | ((uint32_t)c[3] << 24);
      c += 4; cRem -= 4;

      NSMutableDictionary *tags = [NSMutableDictionary dictionary];
      for (uint32_t i = 0; i < count && cRem >= 4; i++) {
        uint32_t clen = c[0] | (c[1] << 8) | (c[2] << 16) | ((uint32_t)c[3] << 24);
        c += 4; cRem -= 4;
        if (cRem < clen) break;
        NSString *entry = [[NSString alloc] initWithBytes:c length:clen encoding:NSUTF8StringEncoding];
        c += clen; cRem -= clen;
        NSRange eq = [entry rangeOfString:@"="];
        if (eq.location != NSNotFound) {
          NSString *key = [entry substringToIndex:eq.location].lowercaseString;
          NSString *value = [entry substringFromIndex:eq.location + 1];
          if (key.length && value.length) tags[key] = value;
        }
      }
      return tags.count ? tags : nil;
    }
    p += len; remaining -= len;
  }
  return nil;
}

// Decode an ID3v2 text frame. Encoding byte: 0=ISO-8859-1 (often actually
// GBK for CJK tags), 1=UTF-16 w/ BOM, 2=UTF-16BE, 3=UTF-8.
static NSString *decodeId3Text(const uint8_t *p, uint32_t len) {
  if (len == 0) return @"";
  uint8_t enc = p[0];
  const uint8_t *text = p + 1;
  uint32_t textLen = len - 1;
  if (enc == 0) {
    NSInteger high = 0;
    for (uint32_t i = 0; i < textLen; i++) if (text[i] > 0x7F) high++;
    if (textLen > 0 && high * 10 > textLen * 3) {
      // Mostly high bytes -> likely GBK mislabeled as Latin-1
      NSString *gb = [[NSString alloc] initWithBytes:text length:textLen
                                            encoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000)];
      if (gb.length > 0 && ![gb containsString:@"\uFFFD"]) return gb;
    }
    return [[NSString alloc] initWithBytes:text length:textLen encoding:NSISOLatin1StringEncoding] ?: @"";
  }
  if (enc == 1) {
    if (textLen >= 2 && text[textLen - 1] == 0 && text[textLen - 2] == 0) textLen -= 2;
    return [[NSString alloc] initWithBytes:text length:textLen encoding:NSUTF16StringEncoding] ?: @"";
  }
  if (enc == 2) {
    return [[NSString alloc] initWithBytes:text length:textLen encoding:NSUTF16BigEndianStringEncoding] ?: @"";
  }
  return [[NSString alloc] initWithBytes:text length:textLen encoding:NSUTF8StringEncoding] ?: @"";
}

// Parse ID3v2 (v2.3/v2.4) text frames from an MP3 file.
static NSDictionary *parseId3v2(NSString *path) {
  NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
  if (data.length < 10 || memcmp(data.bytes, "ID3", 3) != 0) return nil;
  const uint8_t *p = (const uint8_t *)data.bytes;
  uint8_t ver = p[3];
  if (ver != 3 && ver != 4) return nil;
  uint32_t tagSize = ((uint32_t)(p[6] & 0x7f) << 21) | ((uint32_t)(p[7] & 0x7f) << 14)
                   | ((uint32_t)(p[8] & 0x7f) << 7) | (p[9] & 0x7f);
  if (tagSize > data.length - 10) tagSize = (uint32_t)(data.length - 10);
  const uint8_t *end = p + 10 + tagSize;
  p += 10;
  if (p < end && (p[5] & 0x40)) { // extended header
    uint32_t extSize = ver == 4
      ? (((uint32_t)(p[6] & 0x7f) << 21) | ((uint32_t)(p[7] & 0x7f) << 14) | ((uint32_t)(p[8] & 0x7f) << 7) | (p[9] & 0x7f))
      : ((uint32_t)p[6] << 24) | ((uint32_t)p[7] << 16) | ((uint32_t)p[8] << 8) | p[9];
    p += 10 + extSize;
  }
  NSMutableDictionary *tags = [NSMutableDictionary dictionary];
  while (p + 10 <= end) {
    char id[5] = { 0 };
    memcpy(id, p, 4);
    uint32_t size;
    if (ver == 4) {
      size = ((uint32_t)(p[4] & 0x7f) << 21) | ((uint32_t)(p[5] & 0x7f) << 14)
           | ((uint32_t)(p[6] & 0x7f) << 7) | (p[7] & 0x7f);
    } else {
      size = ((uint32_t)p[4] << 24) | ((uint32_t)p[5] << 16) | ((uint32_t)p[6] << 8) | p[7];
    }
    const uint8_t *frame = p + 10;
    if (frame + size > end) break;
    if (size > 0 && id[0] == 'T') {
      NSString *value = decodeId3Text(frame, size);
      NSString *key = [NSString stringWithUTF8String:id];
      if ([key isEqualToString:@"TIT2"]) tags[@"title"] = value;
      else if ([key isEqualToString:@"TPE1"]) tags[@"artist"] = value;
      else if ([key isEqualToString:@"TALB"]) tags[@"album"] = value;
      else if ([key isEqualToString:@"TYER"] || [key isEqualToString:@"TDRC"]) tags[@"year"] = value;
      else if ([key isEqualToString:@"TCON"]) tags[@"genre"] = value;
      else if ([key isEqualToString:@"TRCK"]) tags[@"track"] = value;
      else if ([key isEqualToString:@"TPOS"]) tags[@"disc"] = value;
    }
    p = frame + size;
  }
  return tags.count ? tags : nil;
}

// Extract everything the import pipeline needs.
// Returns nil on failure. Call on a background queue.
NSDictionary *extractAtPath(NSString *path) {
  NSURL *url = [NSURL fileURLWithPath:path];
  AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];

  __block BOOL loaded = NO;
  __block NSError *loadError = nil;
  dispatch_semaphore_t sem = dispatch_semaphore_create(0);
  [asset loadValuesAsynchronouslyForKeys:@[ @"commonMetadata", @"duration", @"tracks" ]
                       completionHandler:^{
    loaded = YES;
    dispatch_semaphore_signal(sem);
  }];
  dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)));
  if (!loaded || loadError) return nil;

  NSArray<AVMetadataItem *> *meta = asset.commonMetadata;
  NSMutableDictionary *out = [NSMutableDictionary dictionary];

  // FLAC: pull Vorbis comments manually (AVFoundation hides them)
  NSDictionary *vorbis = nil;
  NSDictionary *id3 = nil;
  if ([path.pathExtension.lowercaseString isEqualToString:@"flac"]) {
    vorbis = parseFlacVorbisComments(path);
  } else if ([path.pathExtension.lowercaseString isEqualToString:@"mp3"]) {
    id3 = parseId3v2(path); // handles GBK/CJK tags AVFoundation mangles
  }

  NSString *title = firstValue(meta, AVMetadataCommonKeyTitle);
  NSString *artist = firstValue(meta, AVMetadataCommonKeyArtist);
  NSString *album = firstValue(meta, AVMetadataCommonKeyAlbumName);
  NSString *genre = firstValue(meta, AVMetadataCommonKeyType);
  NSString *yearStr = firstValue(meta, AVMetadataCommonKeyCreationDate);

  // Manual tag blocks take precedence (deterministic decoding)
  NSInteger year = 0;
  NSInteger trackNo = 0, discNo = 0;

  // Manual tag blocks take precedence (deterministic decoding)
  if (vorbis) {
    if (vorbis[@"title"]) title = vorbis[@"title"];
    if (vorbis[@"artist"]) artist = vorbis[@"artist"];
    if (vorbis[@"album"]) album = vorbis[@"album"];
    if (vorbis[@"genre"]) genre = vorbis[@"genre"];
    if (vorbis[@"date"]) yearStr = vorbis[@"date"];
  } else if (id3) {
    if (id3[@"title"]) title = id3[@"title"];
    if (id3[@"artist"]) artist = id3[@"artist"];
    if (id3[@"album"]) album = id3[@"album"];
    if (id3[@"genre"]) genre = id3[@"genre"];
    if (id3[@"year"]) yearStr = id3[@"year"];
    if (id3[@"track"]) trackNo = [id3[@"track"] integerValue];
    if (id3[@"disc"]) discNo = [id3[@"disc"] integerValue];
  }

  NSString *baseName = path.lastPathComponent;
  NSString *ext = path.pathExtension.lowercaseString;
  if (!title || title.length == 0) {
    title = cleanAudioStem(baseName.stringByDeletingPathExtension);
  }

  if (yearStr.length >= 4) {
    year = [[yearStr substringToIndex:4] integerValue];
  }

  // Track number: value is {trackNumber, totalTrackCount}
  for (AVMetadataItem *it in meta) {
    if ([it.commonKey isEqualToString:@"tracknumber"] && it.value) {
      NSDictionary *d = (NSDictionary *)it.value;
      if ([d isKindOfClass:NSDictionary.class]) {
        if (trackNo == 0) trackNo = [d[@"trackNumber"] integerValue];
        if (discNo == 0) discNo = [d[@"discNumber"] integerValue];
      }
    }
  }

  // Audio track -> sample rate / channels
  double sampleRate = 0;
  NSInteger channels = 0;
  for (AVAssetTrack *t in asset.tracks) {
    if ([t.mediaType isEqualToString:AVMediaTypeAudio]) {
      CMFormatDescriptionRef fd = (__bridge CMFormatDescriptionRef)t.formatDescriptions.firstObject;
      if (fd) {
        CMAudioFormatDescriptionRef afd = (CMAudioFormatDescriptionRef)fd;
        const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(afd);
        if (asbd) {
          sampleRate = asbd->mSampleRate;
          channels = asbd->mChannelsPerFrame;
        }
      }
      break;
    }
  }

  double duration = CMTimeGetSeconds(asset.duration);
  if (!isfinite(duration) || duration <= 0) duration = 0;

  unsigned long long fileSize = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil].fileSize;
  // Bitrate from size/duration (kbps), like "1411 kbps"
  NSInteger bitrateKbps = 0;
  if (duration > 1 && fileSize > 0) {
    bitrateKbps = (NSInteger)((double)fileSize * 8.0 / duration / 1000.0);
  }

  out[@"title"] = title;
  out[@"artist"] = (artist.length ? artist : @"Unknown Artist");
  out[@"album"] = (album.length ? album : @"Unknown Album");
  out[@"track_number"] = trackNo ? @(trackNo) : NSNull.null;
  out[@"disc_number"] = discNo ? @(discNo) : NSNull.null;
  out[@"genre"] = genre.length ? genre : NSNull.null;
  out[@"year"] = year ? @(year) : NSNull.null;
  out[@"duration"] = @(duration);
  out[@"file_name"] = baseName;
  out[@"file_size"] = @(fileSize);
  out[@"file_format"] = ext;
  out[@"bitrate"] = bitrateKbps ? @(bitrateKbps) : NSNull.null;
  out[@"sample_rate"] = sampleRate ? @(sampleRate) : NSNull.null;
  out[@"channels"] = channels ? @(channels) : NSNull.null;

  // Cover art
  NSData *artwork = nil;
  for (AVMetadataItem *it in meta) {
    if ([it.commonKey isEqualToString:AVMetadataCommonKeyArtwork] && it.value) {
      if ([it.value isKindOfClass:NSData.class]) {
        artwork = (NSData *)it.value;
      } else if ([it.value isKindOfClass:NSDictionary.class]) {
        artwork = ((NSDictionary *)it.value)[@"data"];
      }
      break;
    }
  }
  if (artwork && artwork.length > 0) {
    out[@"artwork"] = artwork;
  }

  return out;
}

} // namespace fpmeta
