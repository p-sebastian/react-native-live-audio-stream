#import "RNLiveAudioStream.h"

@implementation RNLiveAudioStream

RCT_EXPORT_MODULE();

RCT_EXPORT_METHOD(init:(NSDictionary *) options) {
    RCTLogInfo(@"[RNLiveAudioStream] init");
    _recordState.mDataFormat.mSampleRate        = options[@"sampleRate"] == nil ? 44100 : [options[@"sampleRate"] doubleValue];
    _recordState.mDataFormat.mBitsPerChannel    = options[@"bitsPerSample"] == nil ? 16 : [options[@"bitsPerSample"] unsignedIntValue];
    _recordState.mDataFormat.mChannelsPerFrame  = options[@"channels"] == nil ? 1 : [options[@"channels"] unsignedIntValue];
    _recordState.mDataFormat.mBytesPerPacket    = (_recordState.mDataFormat.mBitsPerChannel / 8) * _recordState.mDataFormat.mChannelsPerFrame;
    _recordState.mDataFormat.mBytesPerFrame     = _recordState.mDataFormat.mBytesPerPacket;
    _recordState.mDataFormat.mFramesPerPacket   = 1;
    _recordState.mDataFormat.mReserved          = 0;
    _recordState.mDataFormat.mFormatID          = kAudioFormatLinearPCM;
    _recordState.mDataFormat.mFormatFlags       = _recordState.mDataFormat.mBitsPerChannel == 8 ? kLinearPCMFormatFlagIsPacked : (kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked);
    _recordState.bufferByteSize                 = options[@"bufferSize"] == nil ? 2048 : [options[@"bufferSize"] unsignedIntValue];
    _recordState.mSelf = self;
}

RCT_EXPORT_METHOD(start) {
    RCTLogInfo(@"[RNLiveAudioStream] start");
    
    // If already running, stop and clean up first
    if (_recordState.mIsRunning) {
        [self stop:^(id result) {
            RCTLogInfo(@"Stopped the existing recording before starting a new one");
        } rejecter:nil];
    }
    
    // Reset mCurrentPacket to 0 to start a new file cleanly
    _recordState.mCurrentPacket = 0;
    
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    NSError *error = nil;
    BOOL success;

    // Apple recommended:
    // Instead of setting your category and mode properties independently, set them at the same time
    if (@available(iOS 10.0, *)) {
        success = [audioSession setCategory: AVAudioSessionCategoryPlayAndRecord
                                       mode: AVAudioSessionModeVoiceChat
                                    options: AVAudioSessionCategoryOptionMixWithOthers |
                                             AVAudioSessionCategoryOptionAllowBluetooth |
                                             AVAudioSessionCategoryOptionAllowAirPlay
                                      error: &error];
    } else {
        success = [audioSession setCategory: AVAudioSessionCategoryRecord withOptions: AVAudioSessionCategoryOptionDuckOthers error: &error];
        success = [audioSession setMode: AVAudioSessionModeVoiceChat error: &error] && success;
    }
    if (!success || error != nil) {
        RCTLog(@"[RNLiveAudioStream] Problem setting up AVAudioSession category and mode. Error: %@", error);
        return;
    }

    _recordState.mIsRunning = true;
    
    // Dispose of any existing queue before starting a new one
    if (_recordState.mQueue != NULL) {
        AudioQueueFlush(_recordState.mQueue);
        AudioQueueDispose(_recordState.mQueue, true);
        _recordState.mQueue = NULL;
    }
    
    OSStatus status = AudioQueueNewInput(&_recordState.mDataFormat, HandleInputBuffer, &_recordState, NULL, NULL, 0, &_recordState.mQueue);
    if (status != 0) {
        RCTLog(@"[RNLiveAudioStream] Record Failed. Cannot initialize AudioQueueNewInput. status: %i", (int) status);
        return;
    }

    // Allocate and enqueue buffers
    for (int i = 0; i < kNumberBuffers; i++) {
        AudioQueueAllocateBuffer(_recordState.mQueue, _recordState.bufferByteSize, &_recordState.mBuffers[i]);
        AudioQueueEnqueueBuffer(_recordState.mQueue, _recordState.mBuffers[i], 0, NULL);
    }
    
    AudioQueueStart(_recordState.mQueue, NULL);
}

RCT_EXPORT_METHOD(stop:(RCTPromiseResolveBlock)resolve
                  rejecter:(__unused RCTPromiseRejectBlock)reject) {
    RCTLogInfo(@"[RNLiveAudioStream] stop");
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];

    if (_recordState.mIsRunning) {
        _recordState.mIsRunning = false;

        // Stop the queue
        AudioQueueStop(_recordState.mQueue, true);

        // Free allocated buffers
        for (int i = 0; i < kNumberBuffers; i++) {
            if (_recordState.mBuffers[i] != NULL) {
                AudioQueueFreeBuffer(_recordState.mQueue, _recordState.mBuffers[i]);
                _recordState.mBuffers[i] = NULL;  // Clear buffer after freeing
            }
        }

        // Dispose of the audio queue
        if (_recordState.mQueue != NULL) {
            AudioQueueDispose(_recordState.mQueue, true);
            _recordState.mQueue = NULL;
        }

        [audioSession setCategory:AVAudioSessionCategoryPlayback error:nil];
        [audioSession setMode:AVAudioSessionModeMoviePlayback error:nil];

        NSString *str = @"end";
        [self sendEventWithName:@"data" body:str];
        
        resolve(nil);
    } else {
        RCTLogInfo(@"Recording is not running, skipping stop.");
        resolve(nil);
    }
}

void HandleInputBuffer(void *inUserData,
                       AudioQueueRef inAQ,
                       AudioQueueBufferRef inBuffer,
                       const AudioTimeStamp *inStartTime,
                       UInt32 inNumPackets,
                       const AudioStreamPacketDescription *inPacketDesc) {
    AQRecordState* pRecordState = (AQRecordState *)inUserData;

    if (!pRecordState->mIsRunning) {
        return;
    }


    short *samples = (short *) inBuffer->mAudioData;
    long nsamples = inBuffer->mAudioDataByteSize;
    NSData *data = [NSData dataWithBytes:samples length:nsamples];
    NSData* compressed = [data zlibDeflate];
//    NSData *data = [NSData dataWithBytes:samples length:nsamples];
    NSMutableArray *byteArray = [NSMutableArray compressed.length];
    const uint8_t *bytes = [compressedData bytes];
    for (NSUInteger i = 0; i < compressedData.length; i++) {
        [byteArray addObject:@(bytes[i])];
    }
    [pRecordState->mSelf sendEventWithName:@"data" body:byteArray];

    AudioQueueEnqueueBuffer(pRecordState->mQueue, inBuffer, 0, NULL);
}

- (NSArray<NSString *> *)supportedEvents {
    return @[@"data"];
}

- (void)dealloc {
    RCTLogInfo(@"[RNLiveAudioStream] dealloc");
    AudioQueueDispose(_recordState.mQueue, true);
}

@end
