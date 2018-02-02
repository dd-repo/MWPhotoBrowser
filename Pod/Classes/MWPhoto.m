//
//  MWPhoto.m
//  MWPhotoBrowser
//
//  Created by Michael Waterfall on 17/10/2010.
//  Copyright 2010 d3i. All rights reserved.
//

#import "MWPhoto.h"
#import "MWPhotoBrowser.h"
#import "Helper.h"
#import "MEGASdkManager.h"
#import "MEGAStore.h"
#import "MEGAGetPreviewRequestDelegate.h"
#import "NSFileManager+MNZCategory.h"
#import "MEGAGetThumbnailRequestDelegate.h"

@interface MWPhoto () <MEGATransferDelegate> {
    BOOL _loadingInProgress;
}

@property (nonatomic, strong) UIImage *image;
@property (nonatomic, strong) NSURL *photoURL;
@property (nonatomic) CGSize assetTargetSize;
@property (strong, nonatomic) NSString *imagePath;
@property (nonatomic, strong) NSString *caption;

- (void)imageLoadingComplete;

@end

@implementation MWPhoto

@synthesize underlyingImage = _underlyingImage; // synth property from protocol

#pragma mark - Init

- (instancetype)initWithNode:(MEGANode *)node {
    if ((self = [super init])) {
        _node = node;
        _caption = node.name;
    }
    return self;
}

- (void)dealloc {
    [self cancelAnyLoading];
}

#pragma mark - Video

- (void)setVideoURL:(NSURL *)videoURL {
    _videoURL = videoURL;
    self.isVideo = YES;
}

- (void)getVideoURL:(void (^)(NSURL *url))completion {
    if (_videoURL) {
        completion(_videoURL);
    }
}

#pragma mark - MWPhoto Protocol Methods

- (UIImage *)underlyingImage {
    if (self.isGridMode) {
        self.imagePath = [Helper pathForNode:self.node inSharedSandboxCacheDirectory:@"thumbnailsV3"];
        if(![[NSFileManager defaultManager] fileExistsAtPath:self.imagePath]) {
            return nil;
        }
    } else {
        self.imagePath = [Helper pathForNode:self.node searchPath:NSCachesDirectory directory:@"previewsV3"];
        if(![[NSFileManager defaultManager] fileExistsAtPath:self.imagePath]) {
            return nil;
        }
    }
    
    return [UIImage imageWithContentsOfFile:self.imagePath];
}

- (void)loadUnderlyingImageAndNotify {
    NSAssert([[NSThread currentThread] isMainThread], @"This method must be called on the main thread.");
    if (_loadingInProgress) return;
    _loadingInProgress = YES;
    @try {
        if (self.underlyingImage) {
            [self imageLoadingComplete];
        } else {
            [self performLoadUnderlyingImageAndNotify];
        }
    }
    @catch (NSException *exception) {
        self.underlyingImage = nil;
        _loadingInProgress = NO;
        [self imageLoadingComplete];
    }
    @finally {
    }
}

// Set the underlyingImage
- (void)performLoadUnderlyingImageAndNotify {
    if (self.isGridMode) {
        if([self.node hasThumbnail]) {
            MEGAGetThumbnailRequestDelegate *getThumbnailRequestDelegate = [[MEGAGetThumbnailRequestDelegate alloc] initWithCompletion:^(MEGARequest *request) {
                [self performSelector:@selector(imageLoadingComplete) withObject:nil afterDelay:0];
            }];
            if (self.isFromFolderLink) {
                [[MEGASdkManager sharedMEGASdkFolder] getThumbnailNode:self.node destinationFilePath:self.imagePath delegate:getThumbnailRequestDelegate];
            } else {
                [[MEGASdkManager sharedMEGASdk] getThumbnailNode:self.node destinationFilePath:self.imagePath delegate:getThumbnailRequestDelegate];
            }
        }
    } else {
        if([self.node hasPreview]) {
            MEGAGetPreviewRequestDelegate *getPreviewRequestDelegate = [[MEGAGetPreviewRequestDelegate alloc] initWithCompletion:^(MEGARequest *request) {
                [self performSelector:@selector(imageLoadingComplete) withObject:nil afterDelay:0];
            }];
            if (self.isFromFolderLink) {
                [[MEGASdkManager sharedMEGASdkFolder] getPreviewNode:self.node destinationFilePath:self.imagePath delegate:getPreviewRequestDelegate];
            } else {
                [[MEGASdkManager sharedMEGASdk] getPreviewNode:self.node destinationFilePath:self.imagePath delegate:getPreviewRequestDelegate];
            }
        } else {
            NSString *offlineImagePath = [[NSFileManager defaultManager] downloadsDirectory];
            offlineImagePath = [offlineImagePath stringByReplacingOccurrencesOfString:[NSHomeDirectory() stringByAppendingString:@"/"] withString:@""];
            offlineImagePath = [offlineImagePath stringByAppendingPathComponent:[[MEGASdkManager sharedMEGASdk] escapeFsIncompatible:[self.node name]]];
            if (self.isFromFolderLink) {
                [[MEGASdkManager sharedMEGASdkFolder] startDownloadNode:self.node localPath:offlineImagePath appData:@"generate_fa" delegate:self];
            } else {
                [[MEGASdkManager sharedMEGASdk] startDownloadNode:self.node localPath:offlineImagePath appData:@"generate_fa" delegate:self];
            }
        }
    }
}

// Load from local file
- (void)_performLoadUnderlyingImageAndNotifyWithLocalFileURL:(NSURL *)url {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            @try {
                self.underlyingImage = [UIImage imageWithContentsOfFile:url.path];
                if (!_underlyingImage) {
                    MEGALogError(@"Error loading photo from path: %@", url.path);
                }
            } @finally {
                [self performSelectorOnMainThread:@selector(imageLoadingComplete) withObject:nil waitUntilDone:NO];
            }
        }
    });
}

// Release if we can get it again from path or url
- (void)unloadUnderlyingImage {
    _loadingInProgress = NO;
	self.underlyingImage = nil;
}

- (void)imageLoadingComplete {
    NSAssert([[NSThread currentThread] isMainThread], @"This method must be called on the main thread.");
    // Complete so notify
    _loadingInProgress = NO;
    // Notify on next run loop
    [self performSelector:@selector(postCompleteNotification) withObject:nil afterDelay:0];
}

- (void)postCompleteNotification {
    [[NSNotificationCenter defaultCenter] postNotificationName:MWPHOTO_LOADING_DID_END_NOTIFICATION
                                                        object:self];
}

- (void)cancelAnyLoading {
}

#pragma mark - MEGATransferDelegate

- (void)onTransferStart:(MEGASdk *)api transfer:(MEGATransfer *)transfer {
    [[Helper downloadingNodes] removeObjectForKey:[MEGASdk base64HandleForHandle:[transfer nodeHandle]]];
}

- (void)onTransferFinish:(MEGASdk *)api transfer:(MEGATransfer *)transfer error:(MEGAError *)error {
    if (error.type) {
        return;
    }
    
    [self performSelector:@selector(imageLoadingComplete) withObject:nil afterDelay:0];
    
    NSError *e;
    if (![[NSFileManager defaultManager] removeItemAtPath:[NSHomeDirectory() stringByAppendingPathComponent:[transfer path]] error:&e]) {
        MEGALogError(@"Remove item at path failed with error: %@", e);
    }
}

@end
