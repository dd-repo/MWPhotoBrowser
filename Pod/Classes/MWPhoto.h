//
//  MWPhoto.h
//  MWPhotoBrowser
//
//  Created by Michael Waterfall on 17/10/2010.
//  Copyright 2010 d3i. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "MWPhotoProtocol.h"

// This class models a photo/image and it's caption
// If you want to handle photos, caching, decompression
// yourself then you can simply ensure your custom data model
// conforms to MWPhotoProtocol
@interface MWPhoto : NSObject <MWPhoto>

@property (nonatomic, strong) NSURL *videoURL;
@property (nonatomic) BOOL emptyImage;
@property (nonatomic) BOOL isVideo;
@property (nonatomic) BOOL isGridMode;
@property (nonatomic) BOOL isFromFolderLink;
@property (strong, nonatomic) MEGANode *node;

- (instancetype)initWithNode:(MEGANode *)node;

@end

