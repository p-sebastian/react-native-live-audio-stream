//
//  NSData+Compression.m
//  RNLiveAudioStream
//
//  Created by Sebastian Penafiel on 01.10.24.
//  Copyright © 2024 Qi Xi. All rights reserved.
//

#import "NSData+Compression.h"
#include <zlib.h>

@implementation NSData (Compression)

// GZIP Compression
- (NSData *)gzipCompress {
    if ([self length] == 0) {
        return self;
    }
    
    // Define the stream
    z_stream stream;
    stream.zalloc = Z_NULL;
    stream.zfree = Z_NULL;
    stream.opaque = Z_NULL;
    stream.avail_in = (uInt)[self length];
    stream.next_in = (Bytef *)[self bytes];
    
    // Initialize the deflate (GZIP) process
    if (deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, (MAX_WBITS + 16), 8, Z_DEFAULT_STRATEGY) != Z_OK) {
        return nil;
    }
    
    // Create a mutable data object to hold the compressed data
    NSMutableData *compressedData = [NSMutableData dataWithLength:16384]; // Start with a reasonable buffer size
    
    // Compress the data
    do {
        if (stream.total_out >= [compressedData length]) {
            [compressedData increaseLengthBy:16384]; // Expand buffer size if necessary
        }
        
        stream.next_out = [compressedData mutableBytes] + stream.total_out;
        stream.avail_out = (uInt)([compressedData length] - stream.total_out);
        
        deflate(&stream, Z_FINISH); // Perform compression
    } while (stream.avail_out == 0);
    
    // Finalize the compression
    deflateEnd(&stream);
    
    // Set the actual length of the compressed data
    [compressedData setLength:stream.total_out];
    
    return compressedData;
}

@end
