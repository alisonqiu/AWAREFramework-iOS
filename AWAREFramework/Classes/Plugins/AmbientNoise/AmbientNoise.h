//
//  AmbientNoise.h
//  AWARE
//
//  Created by Yuuki Nishiyama on 11/26/15.
//  Copyright © 2015 Yuuki NISHIYAMA. All rights reserved.
//

#import "AWARESensor.h"
#import "AWAREKeys.h"
#import <Accelerate/Accelerate.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <GLKit/GLKit.h>
#import <CallKit/CallKit.h>
#import "EZAudio.h"

//
// By default this will record a file to the application's documents directory
// (within the application's sandbox)
//
#define kAudioFilePath @"rawAudio.wav"
#define kRawAudioDirectory @"rawAudioData"

extern NSString * _Nonnull const AWARE_PREFERENCES_STATUS_PLUGIN_AMBIENT_NOISE;

/** How frequently do we sample the microphone (default = 5) in minutes */
extern NSString * _Nonnull const AWARE_PREFERENCES_FREQUENCY_PLUGIN_AMBIENT_NOISE;

/** For how long we listen (default = 30) in seconds */
extern NSString * _Nonnull const AWARE_PREFERENCES_PLUGIN_AMBIENT_NOISE_SAMPLE_SIZE;

/** Silence threshold (default = 50) in dB */
extern NSString * _Nonnull const AWARE_PREFERENCES_PLUGIN_AMBIENT_NOISE_SILENCE_THRESHOLD;

/**
 The EZAudioFFTDelegate provides event callbacks for the EZAudioFFT (and subclasses such as the EZAudioFFTRolling) whenvever the FFT is computed.
 */
@protocol AWAREAmbientNoiseFFTDelegate <NSObject>

@optional

///-----------------------------------------------------------
/// @name Getting FFT Output Data
///-----------------------------------------------------------

/**
 Triggered when the EZAudioFFT computes an FFT from a buffer of input data. Provides an array of float data representing the computed FFT.
 @param fft        The EZAudioFFT instance that triggered the event.
 @param fftData    A float pointer representing the float array of FFT data.
 @param bufferSize A vDSP_Length (unsigned long) representing the length of the float array.
 */
- (void)        fft:(EZAudioFFT * _Nullable)fft
 updatedWithFFTData:(float * _Nullable)fftData
         bufferSize:(vDSP_Length)bufferSize;

@end

@protocol AWAREAmbientNoiseDelegate <NSObject>

@optional

//- (void)recorderDidClose:(EZRecorder *)recorder;
//- (NSString *_Nullable)audioDidSave:(NSURL *_Nullable)audio_url;
- (void)audioDidSave:(NSURL *_Nullable)audio_url completion:(void(^_Nonnull)(NSString* _Nullable result, NSNumber* prob))callback;
@end


@interface AmbientNoise : AWARESensor <AWARESensorDelegate, EZMicrophoneDelegate, EZRecorderDelegate, EZAudioFFTDelegate, CXCallObserverDelegate>

@property (nonatomic, weak, nullable) id<AWAREAmbientNoiseDelegate> delegate;
//
// The microphone component
//
@property (nonatomic, strong, nullable) EZMicrophone *microphone;

//
// The recorder component
//
@property (nonatomic, strong, nullable) EZRecorder *recorder;

//
// Used to calculate a rolling FFT of the incoming audio data.
//
@property (nonatomic, strong, nullable) EZAudioFFTRolling *fft;

//
// A flag indicating whether we are recording or not
//
@property (nonatomic, assign, readonly) BOOL isRecording;

@property (nonatomic, weak, nullable) id<AWAREAmbientNoiseFFTDelegate> fftDelegate;

@property int frequencyMin;
@property int sampleSize;
@property double sampleDuration;
@property int silenceThreshold;
@property NSString* dnn_res;

- (BOOL) isSaveRawData;
- (void) saveRawData:(BOOL)state;

- (BOOL) startSensor;

typedef void (^AudioFileGenerationHandler)(NSURL * _Nullable fileURL);

- (void) setAudioFileGenerationHandler:(AudioFileGenerationHandler __nullable)handler;

@end
