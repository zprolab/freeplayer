// FreePlayer shell — shared path-containment + audio-type helpers
// Q2: single implementation used by the bridge (getCover/getLrc/media writes)
// and the media:// scheme handler, instead of two divergent copies.
#pragma once
#import <Foundation/Foundation.h>

// True when `path` (standardized) lives inside library_dir AND, after
// resolving symlinks, its final target still lives inside library_dir
// (S3d: a renderer-planted symlink to an arbitrary file must not read).
BOOL fpIsPathInLibrary(NSString *path);

// True for audio file extensions the import pipeline + media:// accept
// (S3b / Q9): mp3 flac m4a mp4 aac wav ogg oga opus wma aif aiff m4b
BOOL fpIsAudioFile(NSString *path);
