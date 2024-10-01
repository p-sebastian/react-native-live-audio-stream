//
//  Header.h
//  RNLiveAudioStream
//
//  Created by Sebastian Penafiel on 01.10.24.
//  Copyright © 2024 Qi Xi. All rights reserved.
//

#import <Foundation/NSData.h>

/*! Adds compression and decompression messages to NSData.
 * Methods extracted from source given at
 * http://www.cocoadev.com/index.pl?NSDataCategory
 */
@interface NSData (Compression)

- (NSData *)gzipCompress;

@end
