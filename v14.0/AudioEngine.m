#import "AudioEngine.h"
#import <AVFoundation/AVFoundation.h>

// Procedural WAV generator for realistic game sounds
@interface AudioEngine () {
    AVAudioEngine *_engine;
    AVAudioPlayerNode *_ambientNode, *_sfxNode;
    AVAudioPCMBuffer *_stepBuffers[4];
    AVAudioPCMBuffer *_jumpBuffer, *_slideBuffer, *_coinBuffer, *_hitBuffer, *_deathBuffer;
    int _stepIdx;
    float _ambientVol;
}
@end

@implementation AudioEngine

+ (instancetype)shared {
    static AudioEngine *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [[AudioEngine alloc] init]; });
    return inst;
}

- (instancetype)init {
    if (self = [super init]) {
        _engine = [[AVAudioEngine alloc] init];
        _ambientNode = [[AVAudioPlayerNode alloc] init];
        _sfxNode = [[AVAudioPlayerNode alloc] init];
        
        [_engine attachNode:_ambientNode];
        [_engine attachNode:_sfxNode];
        
        AVAudioFormat *fmt = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100 channels:1];
        [_engine connect:_ambientNode to:_engine.mainMixerNode format:fmt];
        [_engine connect:_sfxNode to:_engine.mainMixerNode format:fmt];
        
        [_engine prepare];
        
        // Generate all sounds procedurally
        for (int i = 0; i < 4; i++) _stepBuffers[i] = [self genStep:i];
        _jumpBuffer = [self genJump];
        _slideBuffer = [self genSlide];
        _coinBuffer = [self genCoin];
        _hitBuffer = [self genHit];
        _deathBuffer = [self genDeath];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
            selector:@selector(interrupt:)
            name:AVAudioSessionInterruptionNotification object:nil];
    }
    return self;
}

- (AVAudioPCMBuffer *)genBuffer:(int)numSamples block:(float(^)(int))block {
    AVAudioFormat *fmt = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:44100 channels:1];
    AVAudioPCMBuffer *buf = [[AVAudioPCMBuffer alloc] initWithPCMFormat:fmt frameCapacity:numSamples];
    buf.frameLength = numSamples;
    float *p = buf.floatChannelData[0];
    for (int i = 0; i < numSamples; i++) p[i] = block(i);
    return buf;
}

// ─── FOOTSTEP: short impact with dirt crunch ───
- (AVAudioPCMBuffer *)genStep:(int)variant {
    return [self genBuffer:2205 block:^float(int i) {
        float t = i / 44100.0;
        float noise = ((float)rand()/RAND_MAX * 2 - 1) * 0.5;
        float env = exp(-t * 60.0);
        float tone = sin(t * 800 * (1 + variant * 0.12)) * 0.3;
        return (noise * 0.4 + tone * 0.3 + sin(t * 200) * 0.15) * env * 0.7;
    }];
}

// ─── JUMP: whoosh up ───
- (AVAudioPCMBuffer *)genJump {
    return [self genBuffer:4410 block:^float(int i) {
        float t = i / 44100.0;
        float env = exp(-t * 8.0);
        float sweep = 200 + t * 3000;
        return sin(t * sweep) * env * 0.4;
    }];
}

// ─── SLIDE: gritty ground scrape ───
- (AVAudioPCMBuffer *)genSlide {
    return [self genBuffer:6615 block:^float(int i) {
        float t = i / 44100.0;
        float env = exp(-t * 20.0);
        float noise = ((float)rand()/RAND_MAX * 2 - 1) * 0.6;
        return (noise + sin(t * 120) * 0.2) * env * 0.5;
    }];
}

// ─── COIN: bright ping ───
- (AVAudioPCMBuffer *)genCoin {
    return [self genBuffer:4410 block:^float(int i) {
        float t = i / 44100.0;
        float env = exp(-t * 15.0);
        float ping = sin(t * 2000) * 0.3 + sin(t * 3000) * 0.2 + sin(t * 5000) * 0.1;
        return ping * env * 0.5;
    }];
}

// ─── HIT: heavy thud + distortion ───
- (AVAudioPCMBuffer *)genHit {
    return [self genBuffer:6615 block:^float(int i) {
        float t = i / 44100.0;
        float env = exp(-t * 30.0);
        float noise = ((float)rand()/RAND_MAX * 2 - 1) * 0.7;
        float thud = sin(t * 80) * 0.5;
        return (noise * 0.3 + thud) * env * 0.65;
    }];
}

// ─── DEATH: dramatic low boom ───
- (AVAudioPCMBuffer *)genDeath {
    return [self genBuffer:13230 block:^float(int i) {
        float t = i / 44100.0;
        float env = exp(-t * 6.0);
        float bass = sin(t * 55) * 0.6 + sin(t * 70) * 0.3;
        float noise = ((float)rand()/RAND_MAX * 2 - 1) * 0.3;
        return (bass + noise * 0.2) * env * 0.7;
    }];
}

// ─── PLAYBACK ───
- (void)startAmbient {
    NSError *err;
    [_engine startAndReturnError:&err];
    if (err) { NSLog(@"Audio error: %@", err); return; }
    
    // Generate ambient jungle loop
    int bufLen = 44100 * 4; // 4 second loop
    AVAudioPCMBuffer *ambBuf = [self genBuffer:bufLen block:^float(int i) {
        float t = i / 44100.0;
        // Wind + distant birds/cicadas
        float wind = ((float)rand()/RAND_MAX * 2 - 1) * 0.03;
        // Low rumble
        float rumble = sin(t * 30) * 0.015 + sin(t * 45) * 0.01;
        // Occasional bird chirp
        float bird = 0;
        if (fmod(t, 2.5) < 0.08) bird = sin(fmod(t, 2.5) * 8000) * exp(-fmod(t, 2.5) * 80) * 0.04;
        return wind + rumble + bird;
    }];
    
    [_ambientNode scheduleBuffer:ambBuf atTime:nil options:AVAudioPlayerNodeBufferLoops completionHandler:nil];
    [_ambientNode play];
    _ambientNode.volume = 0.4;
}

- (void)playFootstep {
    AVAudioPCMBuffer *b = _stepBuffers[_stepIdx % 4];
    _stepIdx++;
    [_sfxNode scheduleBuffer:b atTime:nil options:0 completionHandler:nil];
    if (!_sfxNode.isPlaying) [_sfxNode play];
}

- (void)playJump {
    [_sfxNode scheduleBuffer:_jumpBuffer atTime:nil options:0 completionHandler:nil];
    if (!_sfxNode.isPlaying) [_sfxNode play];
}

- (void)playSlide {
    [_sfxNode scheduleBuffer:_slideBuffer atTime:nil options:0 completionHandler:nil];
    if (!_sfxNode.isPlaying) [_sfxNode play];
}

- (void)playCoin {
    [_sfxNode scheduleBuffer:_coinBuffer atTime:nil options:0 completionHandler:nil];
    if (!_sfxNode.isPlaying) [_sfxNode play];
}

- (void)playHit {
    _sfxNode.volume = 0.9;
    [_sfxNode scheduleBuffer:_hitBuffer atTime:nil options:0 completionHandler:nil];
    if (!_sfxNode.isPlaying) [_sfxNode play];
}

- (void)playDeath {
    _ambientNode.volume = 0.1;
    _sfxNode.volume = 1.0;
    [_sfxNode scheduleBuffer:_deathBuffer atTime:nil options:0 completionHandler:nil];
    if (!_sfxNode.isPlaying) [_sfxNode play];
}

- (void)interrupt:(NSNotification *)note {
    [_engine stop];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_engine stop];
}

@end
