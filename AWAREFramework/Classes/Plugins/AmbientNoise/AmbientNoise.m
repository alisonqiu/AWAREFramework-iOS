//
//  AmbientNoise.m
//  AWARE
//
//  Created by Yuuki Nishiyama on 11/26/15.
//  Copyright © 2015 Yuuki NISHIYAMA. All rights reserved.
//

#import "AmbientNoise.h"
#import "AudioAnalysis.h"
#import "EntityAmbientNoise+CoreDataClass.h"
#import "InferenceModule.h"
#import <AVFoundation/AVFoundation.h>

static vDSP_Length const FFTViewControllerFFTWindowSize = 4096;

NSString * const _Nonnull AWARE_PREFERENCES_STATUS_PLUGIN_AMBIENT_NOISE = @"status_plugin_ambient_noise";

/** How frequently do we sample the microphone (default = 5) in minutes */
NSString * const _Nonnull AWARE_PREFERENCES_FREQUENCY_PLUGIN_AMBIENT_NOISE = @"frequency_plugin_ambient_noise";

/** For how long we listen (default = 30) in seconds */
NSString * const _Nonnull AWARE_PREFERENCES_PLUGIN_AMBIENT_NOISE_SAMPLE_SIZE = @"plugin_ambient_noise_sample_size";

/** Silence threshold (default = 50) in dB */
NSString * const _Nonnull AWARE_PREFERENCES_PLUGIN_AMBIENT_NOISE_SILENCE_THRESHOLD = @"plugin_ambient_noise_silence_threshold";

@implementation AmbientNoise{
    NSString * KEY_AMBIENT_NOISE_TIMESTAMP;
    NSString * KEY_AMBIENT_NOISE_DEVICE_ID;
    NSString * KEY_AMBIENT_NOISE_FREQUENCY;
    NSString * KEY_AMBIENT_NOISE_DECIDELS;
    NSString * KEY_AMBIENT_NOISE_PROB;
    NSString * KEY_AMBIENT_NOISE_SILENT;
    NSString * KEY_AMBIENT_NOISE_SILENT_THRESHOLD;
    NSString * KEY_AMBIENT_NOISE_RAW;
    NSString * KEY_AMBIENT_DNN_RES;
    
    NSTimer *mainTimer;
    
    float recordingSampleRate;
    float targetSampleRate;
    
    float  maxFrequency;
    double db;
    double prob;
    
    float  lastdb;
    
    bool   isSaveRawData;
    
    NSString * KEY_AUDIO_CLIP_NUMBER;
    
    CXCallObserver * callObserver;

    NSString *wav2vec2Path;
    InferenceModule * module;
    NSURL *audio_url;
    
    AudioFileGenerationHandler audioFileGenerationHandler;
}

- (BOOL)isSaveRawData{
    return isSaveRawData;
}

- (void)saveRawData:(BOOL)state{
    isSaveRawData = state;
}


- (instancetype)initWithAwareStudy:(AWAREStudy *)study dbType:(AwareDBType)dbType{
    
    KEY_AMBIENT_NOISE_TIMESTAMP = @"timestamp";
    KEY_AMBIENT_NOISE_DEVICE_ID = @"device_id";
    KEY_AMBIENT_NOISE_FREQUENCY = @"double_frequency";
    KEY_AMBIENT_NOISE_DECIDELS  = @"double_decibels";
    KEY_AMBIENT_NOISE_PROB       = @"double_prob";
    KEY_AMBIENT_NOISE_SILENT    = @"is_silent";
    KEY_AMBIENT_NOISE_SILENT_THRESHOLD = @"double_silent_threshold";
    KEY_AMBIENT_NOISE_RAW       = @"raw";
    KEY_AMBIENT_DNN_RES         = @"dnn_res";
    
    AWAREStorage * storage = nil;
    
    
    if (dbType == AwareDBTypeJSON) {
        storage = [[JSONStorage alloc] initWithStudy:study sensorName:SENSOR_AMBIENT_NOISE];
    }else if(dbType == AwareDBTypeCSV){
        NSArray * header = @[KEY_AMBIENT_NOISE_TIMESTAMP,KEY_AMBIENT_NOISE_DEVICE_ID,KEY_AMBIENT_NOISE_FREQUENCY,KEY_AMBIENT_NOISE_DECIDELS,KEY_AMBIENT_NOISE_PROB,KEY_AMBIENT_NOISE_SILENT,KEY_AMBIENT_NOISE_SILENT_THRESHOLD,KEY_AMBIENT_NOISE_RAW,KEY_AMBIENT_DNN_RES];
        
            NSArray * headerTypes  = @[@(CSVTypeReal),@(CSVTypeText),@(CSVTypeReal),@(CSVTypeReal),@(CSVTypeReal),@(CSVTypeInteger),@(CSVTypeReal),@(CSVTypeText),@(CSVTypeText)];
        storage = [[CSVStorage alloc] initWithStudy:study sensorName:SENSOR_AMBIENT_NOISE headerLabels:header headerTypes:headerTypes];
    }else{

        storage = [[SQLiteStorage alloc] initWithStudy:study sensorName:SENSOR_AMBIENT_NOISE entityName:NSStringFromClass([EntityAmbientNoise class])
                                        insertCallBack:^(NSDictionary *data, NSManagedObjectContext *childContext, NSString *entity) {
                                            
                                            EntityAmbientNoise * ambientNoise = (EntityAmbientNoise *)[NSEntityDescription insertNewObjectForEntityForName:entity
                                                                                                                                    inManagedObjectContext:childContext];
                                            ambientNoise.device_id = [data objectForKey:@"device_id"];
                                            ambientNoise.timestamp = [data objectForKey:@"timestamp"];
                                            ambientNoise.double_frequency = [data objectForKey:self->KEY_AMBIENT_NOISE_FREQUENCY];
                                            ambientNoise.double_decibels = [data objectForKey:self->KEY_AMBIENT_NOISE_DECIDELS];
                                            ambientNoise.double_prob = [data objectForKey:self->KEY_AMBIENT_NOISE_PROB];
                                            ambientNoise.is_silent = [data objectForKey:self->KEY_AMBIENT_NOISE_SILENT];
                                            ambientNoise.double_silent_threshold = [data objectForKey:self->KEY_AMBIENT_NOISE_SILENT_THRESHOLD];
                                            ambientNoise.raw = [data objectForKey:self->KEY_AMBIENT_NOISE_RAW];
            ambientNoise.dnn_res = [data objectForKey:self->KEY_AMBIENT_DNN_RES];
                                            
                                        }];
    }
    self = [super initWithAwareStudy:study
                          sensorName:SENSOR_AMBIENT_NOISE
                             storage:storage];
    if (self) {

        _frequencyMin     = 1;
        _sampleSize       = 10;
        _silenceThreshold = 50;
        _sampleDuration   = 6;
        // isSaveRawData = YES;
        
        recordingSampleRate = 16000;
        targetSampleRate    = 8000;
        
        maxFrequency = 0;
        db  = 0;
        prob = 0;
        
        KEY_AUDIO_CLIP_NUMBER = @"key_audio_clip";
    
        callObserver = [[CXCallObserver alloc] init];
        [callObserver setDelegate:self queue:nil];
        
        
        [self createRawAudioDataDirectory];
        
    }
    return self;
}

- (void)createTable {
    NSMutableString * query = [[NSMutableString alloc] init];
    [query appendFormat:@"_id integer primary key autoincrement,"];
    [query appendFormat:@"%@ real default 0,",    KEY_AMBIENT_NOISE_TIMESTAMP];
    [query appendFormat:@"%@ text default '',",   KEY_AMBIENT_NOISE_DEVICE_ID];
    [query appendFormat:@"%@ real default 0,",    KEY_AMBIENT_NOISE_FREQUENCY];
    [query appendFormat:@"%@ real default 0,",    KEY_AMBIENT_NOISE_DECIDELS];
    [query appendFormat:@"%@ real default 0,",    KEY_AMBIENT_NOISE_PROB];
    [query appendFormat:@"%@ integer default 0,", KEY_AMBIENT_NOISE_SILENT];
    [query appendFormat:@"%@ real default 0,",    KEY_AMBIENT_NOISE_SILENT_THRESHOLD];
    [query appendFormat:@"%@ text default ''",    KEY_AMBIENT_NOISE_RAW];
    [query appendFormat:@"%@ text default 'dnn default'",    KEY_AMBIENT_DNN_RES];
    [self.storage createDBTableOnServerWithQuery:query];
}

- (void)setParameters:(NSArray *)parameters{
    int frequency = [self getSensorSetting:parameters withKey:AWARE_PREFERENCES_FREQUENCY_PLUGIN_AMBIENT_NOISE];
    if (frequency > 0) {
        _frequencyMin = frequency;
    }
    
    int sampleSize = [self getSensorSetting:parameters withKey:AWARE_PREFERENCES_PLUGIN_AMBIENT_NOISE_SAMPLE_SIZE];
    if (sampleSize > 0) {
        _sampleSize = sampleSize;
    }
    
    int silenceThreshold = [self getSensorSetting:parameters withKey:AWARE_PREFERENCES_PLUGIN_AMBIENT_NOISE_SILENCE_THRESHOLD];
    if (silenceThreshold > 0){
        _silenceThreshold = silenceThreshold;
    }

}

-(BOOL) startSensor {
    if (self.isDebug) NSLog(@"Start Ambient Noise Sensor!");
    
    [self setupMicrophone];
    mainTimer = [NSTimer scheduledTimerWithTimeInterval:60.0f*_frequencyMin
                                                 target:self
                                               selector:@selector(startRecording:)
              
                                               userInfo:[NSDictionary dictionaryWithObject: @0 forKey:KEY_AUDIO_CLIP_NUMBER]
                                                repeats:YES];
 
    [mainTimer fire];
    
    [self setSensingState:YES];
    return YES;
}


-(BOOL) stopSensor {
    if(mainTimer != nil){
        [mainTimer invalidate];
        mainTimer = nil;
    }
    if (self.storage != nil) {
        [self.storage saveBufferDataInMainThread:YES];
    }
    [self setSensingState:NO];
    return YES;
}

//////////////////



- (void)callObserver:(nonnull CXCallObserver *)callObserver
         callChanged:(nonnull CXCall *)call {
    
    if(!call.hasConnected && !call.hasEnded && !call.isOutgoing && !call.isOnHold){
        if (self.isDebug) NSLog(@"[%@] phone call is comming", [self getSensorName] );
        if(_isRecording) [self stopRecording:@{@(self->_sampleSize):self->KEY_AUDIO_CLIP_NUMBER}];
    }else if(call.hasEnded){
        if (self.isDebug) NSLog(@"[%@] phone call is end", [self getSensorName]);
    }else if(call.outgoing){
        if (self.isDebug) NSLog(@"[%@] outgoing call", [self getSensorName]);
        if(_isRecording) [self stopRecording:@{@(self->_sampleSize):self->KEY_AUDIO_CLIP_NUMBER}];
    }
}

/////////////////////////////////////////////////////////////////////////

-(void)setupMicrophone {
    //https://github.com/syedhali/EZAudio
    //
    // Setup the AVAudioSession. EZMicrophone will not work properly on iOS
    // if you don't do this!
    //
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error;
    [session setCategory:AVAudioSessionCategoryPlayAndRecord
             withOptions:AVAudioSessionCategoryOptionInterruptSpokenAudioAndMixWithOthers |
     AVAudioSessionCategoryOptionDefaultToSpeaker |
     AVAudioSessionCategoryOptionAllowBluetooth
                   error:&error];
    if (error) {
        NSLog(@"Error setting up audio session category: %@", error.localizedDescription);
    }
    [session setActive:YES error:&error];
    if (error) {
        NSLog(@"Error setting up audio session active: %@", error.localizedDescription);
    }
    
//    AudioStreamBasicDescription absd = [EZAudioUtilities floatFormatWithNumberOfChannels:1 sampleRate:recordingSampleRate];
    AudioStreamBasicDescription absd = [EZAudioUtilities monoFloatFormatWithSampleRate:recordingSampleRate];
    
    self.microphone = [EZMicrophone microphoneWithDelegate:self withAudioStreamBasicDescription:absd];
    
}


/**
 * Start recording ambient noise
 */
- (void) startRecording:(id)sender{
    
    // check a phone call status
    NSArray * calls = callObserver.calls;
    if (calls==nil || calls.count == 0) {
        // NSLog(@"NO phone call");
    }else if(calls.count > 0){
        if (self.isDebug) NSLog(@"the microphone is busy by a phone call");
        return;
    }
    
    // init microphone if it is nil
    if (self.microphone == nil) {
        [self setupMicrophone];
 
    }
    

    NSNumber * number = @-1;
    if([sender isKindOfClass:[NSTimer class]]){
        NSDictionary * userInfo = ((NSTimer *) sender).userInfo;
        number = [userInfo objectForKey:KEY_AUDIO_CLIP_NUMBER];
        NSLog(@"start recording from timer with number %@", number);
    }else if([sender isKindOfClass:[NSDictionary class]]){
        number = [(NSDictionary *)sender objectForKey:KEY_AUDIO_CLIP_NUMBER];
        NSLog(@" start recording from stop recording with number %@", number);
        
    }else{
        NSLog(@"An error at ambient noise sensor. There is an unknow userInfo format.");
    }
    
    // if ([self isDebug] && currentSecond == 0) {
    if ([self isDebug] && [number isEqualToNumber:@0]) {
        if (self.isDebug) NSLog(@"Start Recording");
    } else if ([number isEqualToNumber:@-1]){
        NSLog(@"An error at ambient noise sensor...");
    }

    if (!_recorder) {
        NSLog(@"startRecoding: no recorder");

        self.recorder = [EZRecorder recorderWithURL:[self getAudioFilePathWithNumber:[number intValue]]
                                       clientFormat:[self.microphone audioStreamBasicDescription]
                                           fileType:EZRecorderFileTypeWAV
                                           delegate:self];


    }
    
    [self.microphone startFetchingAudio];

    _isRecording = YES;
    [self performSelector:@selector(stopRecording:)
               withObject:[NSDictionary dictionaryWithObject:number forKey:KEY_AUDIO_CLIP_NUMBER]
               afterDelay:_sampleDuration];
    
}


/**
 * Stop recording ambient noise
 */
- (void) stopRecording:(id)sender{
    NSLog(@"should happen every 6 secs");
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_isRecording) {
            int number = -1;
            if(sender != nil){
                number = [[(NSDictionary * )sender objectForKey:self->KEY_AUDIO_CLIP_NUMBER] intValue];
            }

            //[self saveAudioDataWithNumber:number];
            
            // init variables
            self->maxFrequency = 0;
            self->db     = 0;
            self->prob    = 0;
            self->lastdb = 0;
            
            self.recorder = nil;
            
            //[self saveAudioDataWithNumber:number];
            if (self->audioFileGenerationHandler != nil) {
                self->audioFileGenerationHandler([self getAudioFilePathWithNumber:number]);
            }
            
            [self.recorder closeAudioFile];
            NSString * _dnn_res = [self audioDidSave:number];
            NSLog(@"res in AN is %@ ", _dnn_res);

            
            // check a dutyCycle
            if( self->_sampleSize > number ){
                number++;
                [self startRecording:[NSDictionary dictionaryWithObject:@(number) forKey:self->KEY_AUDIO_CLIP_NUMBER]];
            }else{
                // stop fetching audio
                [self.microphone stopFetchingAudio];
                self.microphone.delegate = nil;
                self.microphone = nil;
                // stop recording audio
                [self.recorder closeAudioFile];
                self.recorder.delegate = nil;

                // init
                number = 0;
                self->_isRecording = NO;
                if ([self isDebug]) NSLog(@"Stop Recording");
            }
        }
    });
}


////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////

- (void) saveAudioDataWithNumber:(int)number andResult:(NSString*)res andProb:(NSNumber*)prob {
    NSLog(@"inside saveAudioDataWithNumber");
    NSNumber * unixtime = [AWAREUtils getUnixTimestamp:[NSDate new]];
    
    
    [self setLatestValue:[NSString stringWithFormat:@"DNN:%@, Prob:%f", res, prob]];
    

    
    NSMutableDictionary *dict = [[NSMutableDictionary alloc] init];
    [dict setObject:unixtime forKey:KEY_AMBIENT_NOISE_TIMESTAMP];
    [dict setObject:[self getDeviceId] forKey:KEY_AMBIENT_NOISE_DEVICE_ID];
    [dict setObject:[NSNumber numberWithFloat:maxFrequency] forKey:KEY_AMBIENT_NOISE_FREQUENCY];
    [dict setObject:[NSNumber numberWithDouble:db] forKey:KEY_AMBIENT_NOISE_DECIDELS];
    [dict setObject:prob forKey:KEY_AMBIENT_NOISE_PROB];
    [dict setObject:[NSNumber numberWithBool:[AudioAnalysis isSilent:[prob floatValue] threshold:_silenceThreshold]] forKey:KEY_AMBIENT_NOISE_SILENT];
    [dict setObject:[NSNumber numberWithInteger:_silenceThreshold] forKey:KEY_AMBIENT_NOISE_SILENT_THRESHOLD];
    //[dict setObject:@"" forKey:KEY_AMBIENT_NOISE_RAW];
    if(res){
        [dict setObject:res forKey:KEY_AMBIENT_DNN_RES];
    }else{
        NSLog(@"no dnn res yet");
        return;
    }

    

    if(isSaveRawData){
             NSData * data = [NSData dataWithContentsOfURL:[self getAudioFilePathWithNumber:number]];
             [dict setObject:@"[data base64EncodedStringWithOptions:0] "forKey:KEY_AMBIENT_NOISE_RAW];
      
        }else{
            [dict setObject:@"" forKey:KEY_AMBIENT_NOISE_RAW];
            NSURL * url = [self getAudioFilePathWithNumber:number];
             NSError * error = nil;
             if (url != nil) {
                 if ([NSFileManager.defaultManager removeItemAtURL:url error:&error] ){
     //                if (self.isDebug) NSLog(@"[%@] Remove an audio file -> Success: %@", self.getSensorName, url.debugDescription);
                     NSLog(@"[%@] Remove an audio file -> Success", self.getSensorName);
                 }else{
                     if (self.isDebug) NSLog(@"[%@] Remove an audio file -> Error: %@",   self.getSensorName, url.debugDescription);
                     NSLog(@"[%@] Remove an audio file -> Success", self.getSensorName);
            }
        }
    

        
        
    }
    
    [self setLatestData:dict];
    
    @try {
        //NSLog(@"---------print dict");
//        for (id key in dict) {
//            NSLog(@"key: %@, value: %@ \n", key, [dict objectForKey:key]);
//        }
        [self.storage saveDataWithDictionary:dict buffer:YES saveInMainThread:YES];
        
        SensorEventHandler handler = [self getSensorEventHandler];
        if (handler!=nil) {
            handler(self, dict);
        }
        
    } @catch (NSException *exception) {
        NSLog(@"AN line 437 exception: %@", exception.debugDescription);
    }
}

- (void) setAudioFileGenerationHandler:(AudioFileGenerationHandler)handler{
    audioFileGenerationHandler = handler;
}

//////////////////////////////////////////////////////////////////////
// delegate

/**
 Called anytime the EZMicrophone starts or stops.
 
 @param microphone The instance of the EZMicrophone that triggered the event.
 @param isPlaying A BOOL indicating whether the EZMicrophone instance is playing or not.
 */
- (void)microphone:(EZMicrophone *)microphone changedPlayingState:(BOOL)isPlaying{
    
}

//------------------------------------------------------------------------------

/**
 Called anytime the input device changes on an `EZMicrophone` instance.
 @param microphone The instance of the EZMicrophone that triggered the event.
 @param device The instance of the new EZAudioDevice the microphone is using to pull input.
 */
- (void)microphone:(EZMicrophone *)microphone changedDevice:(EZAudioDevice *)device{
    // This is not always guaranteed to occur on the main thread so make sure you
    // wrap it in a GCD block
    dispatch_async(dispatch_get_main_queue(), ^{
        // Update UI here
        NSLog(@"Changed input device: %@", device);
        
    });
}

//------------------------------------------------------------------------------

/**
 Returns back the audio stream basic description as soon as it has been initialized. This is guaranteed to occur before the stream callbacks, `microphone:hasBufferList:withBufferSize:withNumberOfChannels:` or `microphone:hasAudioReceived:withBufferSize:withNumberOfChannels:`
 @param microphone The instance of the EZMicrophone that triggered the event.
 @param audioStreamBasicDescription The AudioStreamBasicDescription that was created for the microphone instance.
 */
- (void)              microphone:(EZMicrophone *)microphone
  hasAudioStreamBasicDescription:(AudioStreamBasicDescription)audioStreamBasicDescription{
    
}

///-----------------------------------------------------------
/// @name Audio Data Callbacks
///-----------------------------------------------------------

/**
 This method provides an array of float arrays of the audio received, each float array representing a channel of audio data This occurs on the background thread so any drawing code must explicity perform its functions on the main thread.
 @param microphone       The instance of the EZMicrophone that triggered the event.
 @param buffer           The audio data as an array of float arrays. In a stereo signal buffer[0] represents the left channel while buffer[1] would represent the right channel.
 @param bufferSize       The size of each of the buffers (the length of each float array).
 @param numberOfChannels The number of channels for the incoming audio.
 @warning This function executes on a background thread to avoid blocking any audio operations. If operations should be performed on any other thread (like the main thread) it should be performed within a dispatch block like so: dispatch_async(dispatch_get_main_queue(), ^{ ...Your Code... })
 */
- (void)    microphone:(EZMicrophone *)microphone
      hasAudioReceived:(float **)buffer
        withBufferSize:(UInt32)bufferSize
  withNumberOfChannels:(UInt32)numberOfChannels{

    float one     = 1.0;
    float meanVal = 0.0;
    float tiny    = 0.1;
    
    vDSP_vsq(buffer[0],   1, buffer[0], 1, bufferSize);
    vDSP_meanv(buffer[0], 1, &meanVal,  bufferSize);
    vDSP_vdbcon(&meanVal, 1, &one,      &meanVal, 1, 1, 0);
    
    float currentdb = 1.0 - (fabs(meanVal)/100);
    
}

//------------------------------------------------------------------------------

/**
 Returns back the buffer list containing the audio received. This occurs on the background thread so any drawing code must explicity perform its functions on the main thread.
 @param microphone       The instance of the EZMicrophone that triggered the event.
 @param bufferList       The AudioBufferList holding the audio data.
 @param bufferSize       The size of each of the buffers of the AudioBufferList.
 @param numberOfChannels The number of channels for the incoming audio.
 @warning This function executes on a background thread to avoid blocking any audio operations. If operations should be performed on any other thread (like the main thread) it should be performed within a dispatch block like so: dispatch_async(dispatch_get_main_queue(), ^{ ...Your Code... })
 */
- (void)    microphone:(EZMicrophone *)microphone
         hasBufferList:(AudioBufferList *)bufferList
        withBufferSize:(UInt32)bufferSize
  withNumberOfChannels:(UInt32)numberOfChannels{
    if (self.isRecording)
    {
        [self.recorder appendDataFromBufferList:bufferList
                                 withBufferSize:bufferSize];
    }
}


///////////////////////////////////////////////
///////////////////////////////////////////////
// EZRecorderDelegate
/**
 Triggers when the EZRecorder is explicitly closed with the `closeAudioFile` method.
 @param recorder The EZRecorder instance that triggered the action
 */
- (void)recorderDidClose:(EZRecorder *)recorder{
    recorder.delegate = nil;
}

/**
 Triggers after the EZRecorder has successfully written audio data from the `appendDataFromBufferList:withBufferSize:` method.
 @param recorder The EZRecorder instance that triggered the action
 */
- (void)recorderUpdatedCurrentTime:(EZRecorder *)recorder{
    //    __weak typeof (self) weakSelf = self;
    //    NSString *formattedCurrentTime = [recorder formattedCurrentTime];
    //    dispatch_async(dispatch_get_main_queue(), ^{
    //        weakSelf.currentTimeLabel.text = formattedCurrentTime;
    //    });
}


///////////////////////////////////////////////
//////////////////////////////////////////////


- (NSString *)applicationDocumentsDirectory
{
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    return basePath;
}

- (NSURL *)getAudioFilePathWithNumber:(int)number{

    return [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@/%@/%d_%@",
                                   [self applicationDocumentsDirectory],
                                   kRawAudioDirectory,
                                   number,
                                   kAudioFilePath
                                   ]];
}

- (BOOL) createRawAudioDataDirectory{
    NSString *basePath = [self applicationDocumentsDirectory];
    NSString *newCacheDirPath = [basePath stringByAppendingPathComponent:kRawAudioDirectory];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    BOOL created = [fileManager createDirectoryAtPath:newCacheDirPath
                          withIntermediateDirectories:YES
                                           attributes:nil
                                                error:&error];
    if (!created) {
        NSLog(@"failed to create directory. reason is %@ - %@", error, error.userInfo);
        return NO;
    }else{
        return YES;
    }
}


/////////////////////////////////////////////
///////////////////////////////////////////////
// FFT delegate
//- (void)        fft:(EZAudioFFT *)fft
// updatedWithFFTData:(float *)fftData
//         bufferSize:(vDSP_Length)bufferSize
//{
//    maxFrequency = [fft maxFrequency];
//
//    if(self.fftDelegate != nil){
//        if ([self.fftDelegate respondsToSelector:@selector(fft:updatedWithFFTData:bufferSize:)]) {
//            [self.fftDelegate fft:fft updatedWithFFTData:fftData bufferSize:bufferSize];
//        }
//    }
    
//    for (int i = 0; i<bufferSize; i++) {
//        if (fftData[i] > 0.01) {
//            NSLog(@"fft val [%d] %f", i, fftData[i]);
//        }
//    }
    //    [self setLatestValue:[NSString stringWithFormat:@"dB:%f, RMS:%f, Frequency:%f", db, rms, maxFrequency]];
//}

- (NSString *)audioDidSave:(int)number
{
    
     
        //[self saveAudioDataWithNumber:[NSNumber numberWithChar:KEY_AUDIO_CLIP_NUMBER]]
        NSURL * audio_url = [self getAudioFilePathWithNumber:number];
        if(audio_url.isFileURL){
            if ([self.delegate respondsToSelector:@selector(audioDidSave:completion:)]) {

                [self.delegate audioDidSave:audio_url completion:^(NSString *result, NSNumber *prob) {
                    NSLog(@"called completion with result %@ and %@",result,prob);
                    [self saveAudioDataWithNumber:[NSNumber numberWithChar:self->KEY_AUDIO_CLIP_NUMBER] andResult:result andProb:prob];
                }];
                return [NSString stringWithFormat:@"%@/%@", @"audioDidSave:(int)number %@",[@(number) stringValue]];
                ;
            }else{
                return @"audio_url isFileURL is false";
            }
        }
    return @"doesn't respond to selector";

}

    



@end
