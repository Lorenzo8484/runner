#import <SceneKit/SceneKit.h>
#import <SpriteKit/SpriteKit.h>
#import "GLTFLoader.h"
#import "AudioEngine.h"
#import "ParticleSystem.h"

#define LANE_WIDTH 2.5f
#define LANE_X(l) ((l) * LANE_WIDTH)
#define ROAD_WIDTH (LANE_WIDTH * 3.6f)
#define TILE_LENGTH 8.0f
#define NUM_TILES 30
#define SHADOW_SIZE 2048
#define MAX_TREES 35
#define MAX_ROCKS 8
#define MAX_COINS 12
#define MAX_TURTLES 4
#define MAX_RINGS 8
#define MAX_HEARTS 3

// LOG MACRO
#define LOG(fmt, ...) [_logBuffer appendFormat:@"[%.1f] " fmt @"\n", _distance, ##__VA_ARGS__]; \
                      if (_logVisible) { _logTextView.text = _logBuffer; \
                        [_logTextView scrollRangeToVisible:NSMakeRange(_logBuffer.length-1,0)]; }

static SCNMaterial *pbrMaterial(NSString *set) {
    SCNMaterial *mat = [SCNMaterial material];
    mat.lightingModelName = SCNLightingModelPhysicallyBased;
    NSString *base = [NSString stringWithFormat:@"Assets/%@", set];
    NSBundle *b = [NSBundle mainBundle];
    mat.diffuse.contents = [UIImage imageWithContentsOfFile:[b pathForResource:[base stringByAppendingString:@"/diff.jpg"] ofType:nil]];
    mat.roughness.contents = [UIImage imageWithContentsOfFile:[b pathForResource:[base stringByAppendingString:@"/rough.jpg"] ofType:nil]];
    mat.normal.contents = [UIImage imageWithContentsOfFile:[b pathForResource:[base stringByAppendingString:@"/normal.jpg"] ofType:nil]];
    NSString *ao = [b pathForResource:[base stringByAppendingString:@"/ao.jpg"] ofType:nil];
    if (ao) mat.ambientOcclusion.contents = [UIImage imageWithContentsOfFile:ao];
    mat.diffuse.wrapS = SCNWrapModeRepeat; mat.diffuse.wrapT = SCNWrapModeRepeat;
    mat.roughness.wrapS = SCNWrapModeRepeat; mat.roughness.wrapT = SCNWrapModeRepeat;
    mat.normal.wrapS = SCNWrapModeRepeat; mat.normal.wrapT = SCNWrapModeRepeat;
    mat.metalness.contents = @0.0;
    return mat;
}

@interface GameViewController : UIViewController <SCNSceneRendererDelegate>
@end

@implementation GameViewController {
    SCNView *_scnView;
    SCNNode *_cameraNode, *_playerNode, *_playerModelNode, *_roadContainer;
    SCNNode *_sunNode, *_fillNode;
    
    int _lane; float _laneX;
    BOOL _jumping; float _jumpVel; float _playerY;
    BOOL _sliding; float _slideTimer;
    int _score, _lives, _coins, _rings;
    float _speed, _distance, _invincibleTimer;
    BOOL _gameOver, _paused, _gameStarted;
    
    float _foodBoostTimer, _magnetTimer;
    BOOL _hasFoodBoost, _hasMagnet;
    
    NSMutableArray<SCNNode *> *_roadTiles, *_trees, *_rocks, *_coinObjects;
    NSMutableArray<SCNNode *> *_turtles, *_ringObjects, *_heartObjects;
    float _nextRockZ, _nextCoinZ, _nextTreeZ, _nextTurtleZ, _nextRingZ, _nextHeartZ;
    SCNNode *_dustEmitter, *_monkeyCarNode;
    float _monkeyCarZ; BOOL _monkeyCarActive;
    
    SCNNode *_animRun, *_animJump, *_animSlide, *_animIdle, *_animDie;
    NSString *_currentAnim;
    
    NSArray *_treeNames, *_rockNames;
    
    // ─── LOG SYSTEM ─────────────────
    NSMutableString *_logBuffer;
    UIButton *_logBtn, *_copyBtn, *_clearBtn, *_closeLogBtn;
    UIView *_logOverlay;
    UITextView *_logTextView;
    BOOL _logVisible;
    int _frameCount;
    
    // ─── HUD ───────────────────────
    SKView *_hudView; SKScene *_hudScene;
    SKLabelNode *_scoreLabel, *_coinLabel, *_lifeLabel, *_fpsLabel, *_speedLabel;
    SKLabelNode *_ringLabel, *_boostLabel;
    NSTimeInterval _lastFps; int _fpsCount;
    float _stepTimer;
    NSTimeInterval _lastTime;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _logBuffer = [NSMutableString string];
    LOG(@"🏁 Jungle Runner v8.1 START — SceneKit Native")
    
    _treeNames = @[@"tree_default",@"tree_detailed",@"tree_oak",@"tree_fat",@"tree_cone",@"tree_tall",@"tree_small",@"tree_thin",@"tree_simple",@"tree_blocks",@"tree_pineDefaultA",@"tree_pineDefaultB",@"tree_pineTallA",@"tree_pineTallC",@"tree_pineRoundA",@"tree_pineRoundC",@"tree_pineSmallA",@"tree_pineSmallC",@"tree_palmDetailedShort",@"tree_palmDetailedTall"];
    _rockNames = @[@"cliff_rock",@"cliff_large_rock",@"cliff_half_rock",@"cliff_corner_rock",@"cliff_block_rock"];
    
    SCNScene *scene = [SCNScene scene];
    scene.background.contents = [self skyGradient];
    scene.fogColor = [UIColor colorWithRed:0.6 green:0.7 blue:0.8 alpha:1.0];
    scene.fogStartDistance = 50; scene.fogEndDistance = 200;
    
    _scnView = [[SCNView alloc] initWithFrame:self.view.bounds];
    _scnView.scene = scene; _scnView.delegate = self;
    _scnView.preferredFramesPerSecond = 60;
    _scnView.antialiasingMode = SCNAntialiasingModeMultisampling4X;
    [self.view addSubview:_scnView];
    
    [self setupLighting];
    
    SCNCamera *cam = [SCNCamera camera];
    cam.zNear = 0.2; cam.zFar = 300; cam.fieldOfView = 65;
    cam.wantsHDR = YES; cam.wantsExposureAdaptation = YES;
    cam.exposureOffset = 0.3; cam.bloomIntensity = 0.4;
    cam.bloomThreshold = 0.85; cam.bloomBlurRadius = 10.0;
    _cameraNode = [SCNNode node]; _cameraNode.camera = cam;
    _cameraNode.position = SCNVector3Make(0, 5.5, 7);
    _cameraNode.eulerAngles = SCNVector3Make(-0.5, 0, 0);
    [scene.rootNode addChildNode:_cameraNode];
    
    SCNFloor *floor = [SCNFloor floor];
    floor.reflectivity = 0.0;
    floor.materials = @[pbrMaterial(@"ground")];
    SCNNode *fn = [SCNNode nodeWithGeometry:floor];
    fn.position = SCNVector3Make(0, -0.05, -80);
    [scene.rootNode addChildNode:fn];
    
    [self loadPlayerModels];
    [self createRoad];
    
    _lane = 0; _laneX = 0; _jumping = NO; _jumpVel = 0; _playerY = 1.0;
    _sliding = NO; _slideTimer = 0; _score = 0; _lives = 3; _coins = 0; _rings = 0;
    _speed = 10; _distance = 0; _invincibleTimer = 0; _gameOver = NO;
    _paused = NO; _gameStarted = NO;
    _foodBoostTimer = 0; _magnetTimer = 0; _hasFoodBoost = NO; _hasMagnet = NO;
    
    _roadTiles = [NSMutableArray array]; _trees = [NSMutableArray array];
    _rocks = [NSMutableArray array]; _coinObjects = [NSMutableArray array];
    _turtles = [NSMutableArray array]; _ringObjects = [NSMutableArray array];
    _heartObjects = [NSMutableArray array];
    
    _nextRockZ = -15; _nextCoinZ = -6; _nextTreeZ = -8;
    _nextTurtleZ = -30; _nextRingZ = -10; _nextHeartZ = -50;
    _lastTime = 0; _frameCount = 0;
    _monkeyCarActive = NO;
    
    SCNParticleSystem *dust = [ParticleSystem dustTrail];
    _dustEmitter = [SCNNode node]; [_dustEmitter addParticleSystem:dust];
    _dustEmitter.position = SCNVector3Make(0, 0.15, -0.3);
    [_playerNode addChildNode:_dustEmitter];
    
    [self setupHUD];
    [self setupGestures];
    [self setupLogSystem];
    [self setupMenuOverlay];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [[AudioEngine shared] startAmbient];
        LOG(@"🔊 Audio engine started")
    });
    
    _gameStarted = YES;
    LOG(@"✅ Game ready — distance tracking active")
}

// ─── SKY ─────────────────────────────────────
- (id)skyGradient {
    int h = 256; CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    size_t bpr = h*4; uint8_t *d = (uint8_t *)malloc(h*bpr);
    for (int y=0; y<h; y++) { float t=y/(float)h;
        for (int x=0; x<h; x++) { int i=(y*h+x)*4;
            d[i]=(uint8_t)((0.35+t*0.3)*255); d[i+1]=(uint8_t)((0.55+t*0.25)*255);
            d[i+2]=(uint8_t)((0.75+t*0.2)*255); d[i+3]=255; } }
    CGContextRef ctx = CGBitmapContextCreate(d,h,h,8,bpr,cs,kCGImageAlphaPremultipliedLast);
    CGImageRef img = CGBitmapContextCreateImage(ctx);
    UIImage *ui = [UIImage imageWithCGImage:img];
    CGImageRelease(img); CGContextRelease(ctx); CGColorSpaceRelease(cs); free(d);
    return ui;
}

// ─── LIGHTING ────────────────────────────────
- (void)setupLighting {
    SCNLight *sun = [SCNLight light]; sun.type = SCNLightTypeDirectional;
    sun.color = [UIColor colorWithRed:1.0 green:0.95 blue:0.85 alpha:1.0];
    sun.intensity = 1200; sun.temperature = 5500;
    sun.castsShadow = YES; sun.shadowRadius = 2.0;
    sun.shadowMapSize = CGSizeMake(SHADOW_SIZE,SHADOW_SIZE);
    sun.shadowMode = SCNShadowModeForward;
    _sunNode = [SCNNode node]; _sunNode.light = sun;
    _sunNode.position = SCNVector3Make(8,25,-10);
    [_scnView.scene.rootNode addChildNode:_sunNode];
    SCNLight *fill = [SCNLight light]; fill.type = SCNLightTypeAmbient;
    fill.color = [UIColor colorWithRed:0.45 green:0.55 blue:0.70 alpha:1.0];
    fill.intensity = 400;
    _fillNode = [SCNNode node]; _fillNode.light = fill;
    [_scnView.scene.rootNode addChildNode:_fillNode];
}

// ─── PLAYER ──────────────────────────────────
- (void)loadPlayerModels {
    _playerNode = [SCNNode node]; _playerNode.position = SCNVector3Make(0,_playerY,0);
    [_scnView.scene.rootNode addChildNode:_playerNode];
    _playerModelNode = [SCNNode node]; [_playerNode addChildNode:_playerModelNode];
    _animIdle = [GLTFLoader loadModel:@"DwarfIdle"];
    _animRun = [GLTFLoader loadModel:@"running"];
    _animJump = [GLTFLoader loadModel:@"jump"];
    _animSlide = [GLTFLoader loadModel:@"slide"];
    _animDie = [GLTFLoader loadModel:@"SideHitDie"];
    [self switchAnimation:@"idle"];
    LOG(@"👤 Player models loaded (5 animations)")
}

- (void)switchAnimation:(NSString *)name {
    if ([_currentAnim isEqualToString:name]) return;
    _currentAnim = name;
    for (SCNNode *c in _playerModelNode.childNodes) [c removeFromParentNode];
    SCNNode *model = nil;
    if ([name isEqualToString:@"idle"]) model=[_animIdle clone];
    else if ([name isEqualToString:@"run"]) model=[_animRun clone];
    else if ([name isEqualToString:@"jump"]) model=[_animJump clone];
    else if ([name isEqualToString:@"slide"]) model=[_animSlide clone];
    else if ([name isEqualToString:@"die"]) model=[_animDie clone];
    if (model) { model.scale=SCNVector3Make(0.8,0.8,0.8); [_playerModelNode addChildNode:model]; }
}

// ─── ROAD ────────────────────────────────────
- (void)createRoad {
    _roadContainer = [SCNNode node]; [_scnView.scene.rootNode addChildNode:_roadContainer];
    for (int i=0; i<NUM_TILES; i++) { SCNNode *t=[self makeRoadTile:i]; [_roadContainer addChildNode:t]; [_roadTiles addObject:t]; }
    LOG(@"🛤️ Road: %d tiles", NUM_TILES)
}
- (SCNNode *)makeRoadTile:(int)index {
    SCNBox *box=[SCNBox boxWithWidth:ROAD_WIDTH height:0.15 length:TILE_LENGTH chamferRadius:0.02];
    box.materials=@[pbrMaterial(@"road")]; SCNNode *n=[SCNNode nodeWithGeometry:box];
    n.position=SCNVector3Make(0,-0.07,-index*TILE_LENGTH); return n;
}

// ─── TREE ────────────────────────────────────
- (SCNNode *)createTree {
    NSString *name=_treeNames[arc4random_uniform((uint32_t)_treeNames.count)];
    SCNNode *tree=[GLTFLoader loadModel:name];
    if (!tree) return [SCNNode node];
    tree.scale=SCNVector3Make(0.7,0.7,0.7); return tree;
}

// ─── ROCK ────────────────────────────────────
- (SCNNode *)createRock {
    NSString *name=_rockNames[arc4random_uniform((uint32_t)_rockNames.count)];
    SCNNode *rock=[GLTFLoader loadModel:name];
    if (!rock) rock=[SCNNode node];
    rock.scale=SCNVector3Make(1.5,1.0,1.5); return rock;
}

// ─── TURTLE ──────────────────────────────────
- (SCNNode *)createTurtle {
    SCNNode *turtle = [SCNNode node];
    SCNSphere *shell = [SCNSphere sphereWithRadius:0.35];
    SCNMaterial *sm = [SCNMaterial material];
    sm.lightingModelName = SCNLightingModelPhysicallyBased;
    sm.diffuse.contents = [UIColor colorWithRed:0.12 green:0.42 blue:0.23 alpha:1.0];
    sm.roughness.contents = @0.85; sm.metalness.contents = @0.02;
    shell.materials = @[sm];
    SCNNode *sn = [SCNNode nodeWithGeometry:shell];
    sn.scale = SCNVector3Make(1.2,0.75,1.0); sn.position = SCNVector3Make(0,0.35,0);
    [turtle addChildNode:sn];
    SCNSphere *head = [SCNSphere sphereWithRadius:0.16];
    SCNMaterial *hm = [SCNMaterial material];
    hm.lightingModelName = SCNLightingModelPhysicallyBased;
    hm.diffuse.contents = [UIColor colorWithRed:0.18 green:0.54 blue:0.30 alpha:1.0];
    hm.roughness.contents = @0.85;
    head.materials = @[hm];
    SCNNode *hn = [SCNNode nodeWithGeometry:head];
    hn.position = SCNVector3Make(0,0.25,0.42);
    [turtle addChildNode:hn];
    return turtle;
}

// ─── RING ────────────────────────────────────
- (SCNNode *)createRing {
    SCNTorus *ring = [SCNTorus torusWithRingRadius:0.4 pipeRadius:0.04];
    SCNMaterial *rm = [SCNMaterial material];
    rm.lightingModelName = SCNLightingModelConstant;
    rm.diffuse.contents = [UIColor colorWithRed:1.0 green:0.85 blue:0.1 alpha:1.0];
    rm.emission.contents = [UIColor colorWithRed:0.5 green:0.4 blue:0.0 alpha:1.0];
    ring.materials = @[rm];
    SCNNode *rn = [SCNNode nodeWithGeometry:ring];
    rn.eulerAngles = SCNVector3Make(M_PI_2,0,0);
    return rn;
}

// ─── HEART ───────────────────────────────────
- (SCNNode *)createHeart {
    SCNNode *heart = [SCNNode node];
    SCNSphere *h1 = [SCNSphere sphereWithRadius:0.2];
    SCNMaterial *hm = [SCNMaterial material];
    hm.diffuse.contents = [UIColor redColor];
    hm.emission.contents = [UIColor colorWithRed:0.3 green:0 blue:0 alpha:1.0];
    h1.materials = @[hm];
    SCNNode *n1 = [SCNNode nodeWithGeometry:h1]; n1.position = SCNVector3Make(-0.15,0,0);
    SCNNode *n2 = [SCNNode nodeWithGeometry:h1]; n2.position = SCNVector3Make(0.15,0,0);
    [heart addChildNode:n1]; [heart addChildNode:n2];
    return heart;
}

// ─── COIN ────────────────────────────────────
- (SCNNode *)createCoin {
    SCNNode *coin = [SCNNode node];
    SCNCylinder *body = [SCNCylinder cylinderWithRadius:0.3 height:0.06];
    SCNMaterial *cm = [SCNMaterial material];
    cm.lightingModelName = SCNLightingModelPhysicallyBased;
    cm.diffuse.contents = [UIColor colorWithRed:1.0 green:0.75 blue:0.1 alpha:1.0];
    cm.roughness.contents = @0.15; cm.metalness.contents = @1.0;
    body.materials = @[cm];
    SCNNode *bn = [SCNNode nodeWithGeometry:body]; bn.eulerAngles=SCNVector3Make(M_PI_2,0,0);
    [coin addChildNode:bn];
    SCNTorus *ring=[SCNTorus torusWithRingRadius:0.33 pipeRadius:0.02];
    SCNMaterial *rm=[SCNMaterial material]; rm.lightingModelName=SCNLightingModelConstant;
    rm.diffuse.contents=[UIColor colorWithRed:1.0 green:0.9 blue:0.2 alpha:1.0];
    ring.materials=@[rm];
    SCNNode *rn=[SCNNode nodeWithGeometry:ring]; rn.eulerAngles=SCNVector3Make(M_PI_2,0,0);
    [coin addChildNode:rn];
    return coin;
}

// ─── LOG SYSTEM ──────────────────────────────
- (void)setupLogSystem {
    _logVisible = NO;
    
    _logBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _logBtn.frame = CGRectMake(self.view.bounds.size.width - 70, self.view.bounds.size.height - 90, 60, 36);
    _logBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
    _logBtn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
    _logBtn.layer.cornerRadius = 8;
    [_logBtn setTitle:@"📋 LOG" forState:UIControlStateNormal];
    _logBtn.titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    [_logBtn addTarget:self action:@selector(toggleLog) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_logBtn];
    
    _logOverlay = [[UIView alloc] initWithFrame:self.view.bounds];
    _logOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _logOverlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.92];
    _logOverlay.hidden = YES;
    [self.view addSubview:_logOverlay];
    
    _logTextView = [[UITextView alloc] initWithFrame:CGRectMake(10, 50, self.view.bounds.size.width-20, self.view.bounds.size.height-110)];
    _logTextView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _logTextView.backgroundColor = [UIColor clearColor];
    _logTextView.textColor = [UIColor greenColor];
    _logTextView.font = [UIFont fontWithName:@"Menlo" size:10];
    _logTextView.editable = NO;
    [_logOverlay addSubview:_logTextView];
    
    _copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _copyBtn.frame = CGRectMake(10, 8, 80, 36);
    _copyBtn.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.15];
    _copyBtn.layer.cornerRadius = 6;
    [_copyBtn setTitle:@"📋 Copy" forState:UIControlStateNormal];
    _copyBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    [_copyBtn addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];
    [_logOverlay addSubview:_copyBtn];
    
    _clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _clearBtn.frame = CGRectMake(100, 8, 80, 36);
    _clearBtn.backgroundColor = [[UIColor redColor] colorWithAlphaComponent:0.3];
    _clearBtn.layer.cornerRadius = 6;
    [_clearBtn setTitle:@"🗑 Clear" forState:UIControlStateNormal];
    _clearBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    [_clearBtn addTarget:self action:@selector(clearLog) forControlEvents:UIControlEventTouchUpInside];
    [_logOverlay addSubview:_clearBtn];
    
    _closeLogBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _closeLogBtn.frame = CGRectMake(self.view.bounds.size.width-60, 8, 50, 36);
    _closeLogBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    _closeLogBtn.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.15];
    _closeLogBtn.layer.cornerRadius = 6;
    [_closeLogBtn setTitle:@"✕" forState:UIControlStateNormal];
    _closeLogBtn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    [_closeLogBtn addTarget:self action:@selector(toggleLog) forControlEvents:UIControlEventTouchUpInside];
    [_logOverlay addSubview:_closeLogBtn];
    
    LOG(@"📋 Log system initialized")
}

- (void)toggleLog {
    _logVisible = !_logVisible;
    _logOverlay.hidden = !_logVisible;
    if (_logVisible) {
        _logTextView.text = _logBuffer;
        [_logTextView scrollRangeToVisible:NSMakeRange(_logBuffer.length-1,0)];
    }
}

- (void)copyLog {
    [[UIPasteboard generalPasteboard] setString:_logBuffer];
    LOG(@"📋 Log copied to clipboard (%lu chars)", (unsigned long)_logBuffer.length)
    [self flashButton:_copyBtn];
}

- (void)clearLog {
    [_logBuffer setString:@""];
    _logTextView.text = @"";
    LOG(@"🗑 Log cleared")
    [self flashButton:_clearBtn];
}

- (void)flashButton:(UIButton *)btn {
    btn.backgroundColor = [[UIColor greenColor] colorWithAlphaComponent:0.5];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.3*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        btn.backgroundColor = btn==_clearBtn ? [[UIColor redColor] colorWithAlphaComponent:0.3] : [[UIColor whiteColor] colorWithAlphaComponent:0.15];
    });
}

// ─── MENU OVERLAY ────────────────────────────
- (void)setupMenuOverlay {
    UIButton *restartBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    restartBtn.frame = CGRectMake(self.view.bounds.size.width/2 - 60, 50, 120, 40);
    restartBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    restartBtn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
    restartBtn.layer.cornerRadius = 10;
    [restartBtn setTitle:@"🔄 Restart" forState:UIControlStateNormal];
    restartBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    [restartBtn addTarget:self action:@selector(restartGame) forControlEvents:UIControlEventTouchUpInside];
    restartBtn.hidden = YES;
    restartBtn.tag = 999;
    [self.view addSubview:restartBtn];
}

// ─── HUD ─────────────────────────────────────
- (void)setupHUD {
    _hudView = [[SKView alloc] initWithFrame:self.view.bounds];
    _hudView.backgroundColor = [UIColor clearColor]; _hudView.allowsTransparency = YES;
    [self.view addSubview:_hudView];
    _hudScene = [SKScene sceneWithSize:self.view.bounds.size];
    _hudScene.scaleMode = SKSceneScaleModeResizeFill;
    [_hudView presentScene:_hudScene];
    CGSize s = _hudScene.size; float pad = 25;
    _scoreLabel = [self hl:@"SCORE: 0" sz:28 c:[SKColor whiteColor]];
    _scoreLabel.position = CGPointMake(pad, s.height-45);
    _scoreLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeLeft;
    [_hudScene addChild:_scoreLabel];
    _coinLabel = [self hl:@"🪙 0" sz:24 c:[SKColor colorWithRed:1.0 green:0.85 blue:0.2 alpha:1.0]];
    _coinLabel.position = CGPointMake(pad, s.height-80);
    _coinLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeLeft;
    [_hudScene addChild:_coinLabel];
    _ringLabel = [self hl:@"💍 0" sz:24 c:[SKColor colorWithRed:0.2 green:0.7 blue:1.0 alpha:1.0]];
    _ringLabel.position = CGPointMake(pad, s.height-113);
    _ringLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeLeft;
    [_hudScene addChild:_ringLabel];
    _speedLabel = [self hl:@"⚡ 10 m/s" sz:16 c:[SKColor colorWithRed:0.6 green:0.9 blue:1.0 alpha:1.0]];
    _speedLabel.position = CGPointMake(pad, s.height-140);
    _speedLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeLeft;
    [_hudScene addChild:_speedLabel];
    _boostLabel = [self hl:@"" sz:18 c:[SKColor orangeColor]];
    _boostLabel.position = CGPointMake(s.width/2, s.height-160);
    [_hudScene addChild:_boostLabel];
    _lifeLabel = [self hl:@"❤️❤️❤️" sz:22 c:[SKColor redColor]];
    _lifeLabel.position = CGPointMake(s.width-pad, s.height-45);
    _lifeLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeRight;
    [_hudScene addChild:_lifeLabel];
    _fpsLabel = [self hl:@"60 FPS" sz:13 c:[SKColor greenColor]];
    _fpsLabel.position = CGPointMake(s.width-pad, 22);
    _fpsLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeRight;
    [_hudScene addChild:_fpsLabel];
    _lastFps = CACurrentMediaTime();
}
- (SKLabelNode *)hl:(NSString*)t sz:(float)s c:(SKColor*)c {
    SKLabelNode *l=[SKLabelNode labelNodeWithFontNamed:@"HelveticaNeue-Bold"];
    l.text=t; l.fontSize=s; l.fontColor=c; return l;
}

// ─── GESTURES ────────────────────────────────
- (void)setupGestures {
    UISwipeGestureRecognizer *sl=[[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeLeft)];
    sl.direction=UISwipeGestureRecognizerDirectionLeft; [_scnView addGestureRecognizer:sl];
    UISwipeGestureRecognizer *sr=[[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeRight)];
    sr.direction=UISwipeGestureRecognizerDirectionRight; [_scnView addGestureRecognizer:sr];
    UISwipeGestureRecognizer *su=[[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeUp)];
    su.direction=UISwipeGestureRecognizerDirectionUp; [_scnView addGestureRecognizer:su];
    UISwipeGestureRecognizer *sd=[[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeDown)];
    sd.direction=UISwipeGestureRecognizerDirectionDown; [_scnView addGestureRecognizer:sd];
    UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
    [_scnView addGestureRecognizer:tap];
}
- (void)swipeLeft { if(!_gameOver&&_lane>-1){_lane--;_laneX=LANE_X(_lane);LOG(@"⬅️ Lane %d",_lane);} }
- (void)swipeRight { if(!_gameOver&&_lane<1){_lane++;_laneX=LANE_X(_lane);LOG(@"➡️ Lane %d",_lane);} }
- (void)swipeUp {
    if(!_gameOver&&!_jumping&&!_sliding){_jumping=YES;_jumpVel=7.5;
        [self switchAnimation:@"jump"];[[AudioEngine shared] playJump];LOG(@"🦘 JUMP");}
}
- (void)swipeDown {
    if(!_gameOver&&!_jumping&&!_sliding){_sliding=YES;_slideTimer=0.7;
        _playerModelNode.scale=SCNVector3Make(1,0.4,1);_playerY=0.5;
        [self switchAnimation:@"slide"];[[AudioEngine shared] playSlide];LOG(@"🛝 SLIDE");}
}
- (void)handleTap {
    if (_gameOver) { [self restartGame]; LOG(@"🔄 Restart via tap"); }
}

// ═══════════════ GAME LOOP ═══════════════════
- (void)renderer:(id<SCNSceneRenderer>)renderer updateAtTime:(NSTimeInterval)time {
    if (_gameOver) return;
    _frameCount++;
    
    float dt = (_lastTime==0) ? (1.0/60.0) : MIN(0.05, time-_lastTime);
    _lastTime = time;
    
    [self updFPS:time];
    _distance += _speed*dt; _score = (int)_distance;
    _speed = 10.0+_distance/100.0; if(_speed>40)_speed=40;
    _invincibleTimer = MAX(0,_invincibleTimer-dt);
    
    // Food boost timer
    _foodBoostTimer = MAX(0,_foodBoostTimer-dt);
    if (_foodBoostTimer <= 0 && _hasFoodBoost) {
        _hasFoodBoost = NO; LOG(@"🍕 Food boost ENDED");
    }
    _magnetTimer = MAX(0,_magnetTimer-dt);
    
    float cx = _playerNode.position.x;
    cx += (_laneX-cx)*MIN(1,12*dt);
    _playerNode.position = SCNVector3Make(cx,_playerY,0);
    
    if (!_jumping && !_sliding) {
        _playerModelNode.position = SCNVector3Make(0,sin(_distance*5.0)*0.06,0);
        if (![_currentAnim isEqualToString:@"run"]) [self switchAnimation:@"run"];
    }
    
    // Jump physics
    if (_jumping) {
        _jumpVel -= 20*dt; _playerY += _jumpVel*dt;
        if (_playerY <= 1.0) { _playerY=1.0;_jumping=NO;_jumpVel=0;
            _playerModelNode.position=SCNVector3Make(0,0,0);[self switchAnimation:@"run"];
            SCNParticleSystem *imp=[ParticleSystem impactDirt];
            SCNNode *in=[SCNNode node];[in addParticleSystem:imp];
            in.position=SCNVector3Make(0,0.1,0);[_playerNode addChildNode:in];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1.0*NSEC_PER_SEC),dispatch_get_main_queue(),^{[in removeFromParentNode];});
        }
        _playerNode.position=SCNVector3Make(_playerNode.position.x,_playerY,_playerNode.position.z);
    }
    
    // Slide
    if (_sliding) { _slideTimer-=dt;
        if (_slideTimer<=0){_sliding=NO;_playerModelNode.scale=SCNVector3Make(1,1,1);_playerY=1.0;[self switchAnimation:@"run"];}
    }
    
    // Footstep
    _stepTimer+=dt;
    if (!_jumping&&!_sliding&&_stepTimer>0.35){_stepTimer=0;[[AudioEngine shared] playFootstep];}
    
    // Road
    for(SCNNode *tile in _roadTiles){tile.position=SCNVector3Make(tile.position.x,tile.position.y,tile.position.z+_speed*dt);
        if(tile.position.z>TILE_LENGTH)tile.position=SCNVector3Make(tile.position.x,tile.position.y,tile.position.z-NUM_TILES*TILE_LENGTH);}
    
    // ─── SPAWN: Trees ─────────────────────
    _nextTreeZ+=_speed*dt;
    if(_nextTreeZ>0&&_trees.count<MAX_TREES){_nextTreeZ=-14-drand48()*20;
        SCNNode *tree=[self createTree];int side=(drand48()<0.5)?-1:1;
        tree.position=SCNVector3Make(side*(3.2+drand48()*5.5),0,_playerNode.position.z-35);
        [_scnView.scene.rootNode addChildNode:tree];[_trees addObject:tree];}
    [self recyclePool:_trees dt:dt limitZ:8];
    
    // ─── SPAWN: Rocks ─────────────────────
    _nextRockZ+=_speed*dt;
    if(_nextRockZ>0&&_rocks.count<MAX_ROCKS){_nextRockZ=-18-drand48()*30;
        int rl=(int)(drand48()*3)-1;SCNNode *rock=[self createRock];
        rock.position=SCNVector3Make(LANE_X(rl),0.25,_playerNode.position.z-35);
        [_scnView.scene.rootNode addChildNode:rock];[_rocks addObject:rock];}
    [self recyclePool:_rocks dt:dt limitZ:5];
    
    // ─── SPAWN: Turtles ───────────────────
    _nextTurtleZ+=_speed*dt;
    if(_nextTurtleZ>0&&_turtles.count<MAX_TURTLES){_nextTurtleZ=-35-drand48()*25;
        int tl=(int)(drand48()*3)-1;SCNNode *turtle=[self createTurtle];
        turtle.position=SCNVector3Make(LANE_X(tl),0.3,_playerNode.position.z-40);
        [_scnView.scene.rootNode addChildNode:turtle];[_turtles addObject:turtle];
        if (_turtles.count==1) LOG(@"🐢 Turtle spawned lane %d",tl);}
    [self recyclePool:_turtles dt:dt limitZ:5];
    
    // ─── Monkey Car ───────────────────────
    if (_hasFoodBoost && !_monkeyCarActive && _distance > 30) {
        [self spawnMonkeyCar];
        LOG(@"🚗 Monkey Car spawned!");
    }
    if (_monkeyCarActive) {
        _monkeyCarZ += _speed * dt * 1.05;
        _monkeyCarNode.position = SCNVector3Make(LANE_X(1), 0.3, _monkeyCarZ);
        if (_monkeyCarZ > 8 || _foodBoostTimer <= 0) {
            [_monkeyCarNode removeFromParentNode]; _monkeyCarActive = NO;
            if (_foodBoostTimer <= 0) LOG(@"🚗 Monkey Car despawned (food boost ended)");
        }
    }
    
    // ─── SPAWN: Rings ─────────────────────
    _nextRingZ+=_speed*dt;
    if(_nextRingZ>0&&_ringObjects.count<MAX_RINGS){_nextRingZ=-8-drand48()*12;
        int rl=(int)(drand48()*3)-1;SCNNode *ring=[self createRing];
        ring.position=SCNVector3Make(LANE_X(rl),1.0,_playerNode.position.z-30);
        [_scnView.scene.rootNode addChildNode:ring];[_ringObjects addObject:ring];}
    [self recyclePool:_ringObjects dt:dt limitZ:5];
    
    // ─── SPAWN: Hearts ────────────────────
    _nextHeartZ+=_speed*dt;
    if(_nextHeartZ>0&&_heartObjects.count<MAX_HEARTS){_nextHeartZ=-60-drand48()*40;
        int hl=(int)(drand48()*3)-1;SCNNode *heart=[self createHeart];
        heart.position=SCNVector3Make(LANE_X(hl),1.2,_playerNode.position.z-50);
        [_scnView.scene.rootNode addChildNode:heart];[_heartObjects addObject:heart];}
    [self recyclePool:_heartObjects dt:dt limitZ:5];
    
    // ─── COLLISION: Rocks ─────────────────
    [self checkCollisionPool:_rocks dt:dt damageAmount:1 isRock:YES];
    
    // ─── COLLISION: Turtles ───────────────
    [self checkCollisionPool:_turtles dt:dt damageAmount:1 isRock:NO];
    
    // ─── COLLISION: Coins ─────────────────
    _nextCoinZ+=_speed*dt;
    if(_nextCoinZ>0&&_coinObjects.count<MAX_COINS){_nextCoinZ=-4-drand48()*10;
        int cl=(int)(drand48()*3)-1;SCNNode *coin=[self createCoin];
        coin.position=SCNVector3Make(LANE_X(cl),1.2,_playerNode.position.z-28);
        [_scnView.scene.rootNode addChildNode:coin];[_coinObjects addObject:coin];}
    NSMutableArray *dc=[NSMutableArray array];
    for(SCNNode *c in _coinObjects){c.position=SCNVector3Make(c.position.x,c.position.y,c.position.z+_speed*dt);
        c.rotation=SCNVector4Make(0,1,0,c.rotation.w+dt*5);
        if(c.position.z>5){[dc addObject:c];continue;}
        float dx=fabsf(c.position.x-_playerNode.position.x),dz=fabsf(c.position.z);
        float pull = _hasMagnet ? 3.0 : 0.7;
        if(dx<pull&&dz<pull){_coins++;if(_coins%10==0)LOG(@"🪙 %d coins",_coins);
            [[AudioEngine shared] playCoin];
            SCNParticleSystem *burst=[ParticleSystem coinBurst];SCNNode *bn=[SCNNode node];
            [bn addParticleSystem:burst];bn.position=c.position;
            [_scnView.scene.rootNode addChildNode:bn];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1.0*NSEC_PER_SEC),dispatch_get_main_queue(),^{[bn removeFromParentNode];});
            [c removeFromParentNode];[_coinObjects removeObject:c];
            // Maybe spawn food boost
            if (_coins > 0 && _coins % 30 == 0 && !_hasFoodBoost) {
                _hasFoodBoost = YES; _foodBoostTimer = 8.0;
                LOG(@"🍕 FOOD BOOST activated! (30 coins)");
            }
        }
    }
    for(SCNNode *c in dc){[c removeFromParentNode];[_coinObjects removeObject:c];}
    
    // ─── COLLISION: Rings ─────────────────
    NSMutableArray *dr2=[NSMutableArray array];
    for(SCNNode *r in _ringObjects){r.position=SCNVector3Make(r.position.x,r.position.y,r.position.z+_speed*dt);
        r.rotation=SCNVector4Make(1,0,0,r.rotation.w+dt*4);
        if(r.position.z>5){[dr2 addObject:r];continue;}
        float dx=fabsf(r.position.x-_playerNode.position.x),dz=fabsf(r.position.z);
        if(dx<0.7&&dz<0.7){_rings++;LOG(@"💍 Ring collected (%d total)",_rings);
            [[AudioEngine shared] playCoin];[r removeFromParentNode];[_ringObjects removeObject:r];
        }
    }
    for(SCNNode *r in dr2){[r removeFromParentNode];[_ringObjects removeObject:r];}
    
    // ─── COLLISION: Hearts ────────────────
    NSMutableArray *dh=[NSMutableArray array];
    for(SCNNode *h in _heartObjects){h.position=SCNVector3Make(h.position.x,h.position.y,h.position.z+_speed*dt);
        h.rotation=SCNVector4Make(0,1,0,h.rotation.w+dt*3);
        if(h.position.z>5){[dh addObject:h];continue;}
        float dx=fabsf(h.position.x-_playerNode.position.x),dz=fabsf(h.position.z);
        if(dx<0.7&&dz<0.7&&_lives<5){_lives++;LOG(@"❤️ +1 life (%d total)",_lives);
            [[AudioEngine shared] playCoin];[h removeFromParentNode];[_heartObjects removeObject:h];
        }
    }
    for(SCNNode *h in dh){[h removeFromParentNode];[_heartObjects removeObject:h];}
    
    // ─── HUD ──────────────────────────────
    _scoreLabel.text=[NSString stringWithFormat:@"SCORE: %d",_score];
    _coinLabel.text=[NSString stringWithFormat:@"🪙 %d",_coins];
    _ringLabel.text=[NSString stringWithFormat:@"💍 %d",_rings];
    _speedLabel.text=[NSString stringWithFormat:@"⚡ %.0f m/s",_speed];
    _boostLabel.text=_hasFoodBoost?[NSString stringWithFormat:@"🍕 BOOST %.1fs",_foodBoostTimer]:@"";
    NSMutableString *hearts=[NSMutableString string];
    for(int i=0;i<_lives;i++)[hearts appendString:@"❤️"];
    if(_invincibleTimer>0&&fmod(time,0.2)<0.1)hearts=[NSMutableString string];
    _lifeLabel.text=hearts;
    _dustEmitter.hidden=_jumping;
    SCNParticleSystem *dustSys=_dustEmitter.particleSystems.firstObject;
    dustSys.birthRate=_sliding?60:25;
    
    // Log ogni 60 frame
    if (_frameCount % 360 == 0) {
        LOG(@"📊 F%d | ⚡%.0f | 🪙%d 💍%d ❤️%d | 🌳%lu 🪨%lu 🐢%lu",
            _frameCount, _speed, _coins, _rings, _lives,
            (unsigned long)_trees.count, (unsigned long)_rocks.count, (unsigned long)_turtles.count);
    }
}

// ─── POOL RECYCLE ────────────────────────────
- (void)recyclePool:(NSMutableArray *)pool dt:(float)dt limitZ:(float)limitZ {
    NSMutableArray *toRemove=[NSMutableArray array];
    for(SCNNode *n in pool){n.position=SCNVector3Make(n.position.x,n.position.y, n.position.z+_speed*dt);
        if(n.position.z>limitZ)[toRemove addObject:n];}
    for(SCNNode *n in toRemove){[n removeFromParentNode];[pool removeObject:n];}
}

// ─── COLLISION CHECK ─────────────────────────
- (void)checkCollisionPool:(NSMutableArray *)pool dt:(float)dt damageAmount:(int)dmg isRock:(BOOL)isRock {
    NSMutableArray *toRemove=[NSMutableArray array];
    for(SCNNode *r in pool){r.position=SCNVector3Make(r.position.x,r.position.y,r.position.z+_speed*dt);
        if(r.position.z>5){[toRemove addObject:r];continue;}
        float dx=fabsf(r.position.x-_playerNode.position.x),dz=fabsf(r.position.z);
        float ht=_sliding?0.45:0.65;
        if(dx<ht&&dz<0.6&&_invincibleTimer<=0&&!_jumping&&_playerY<1.2){
            _lives-=dmg;_invincibleTimer=1.5;[[AudioEngine shared] playHit];
            NSString *t=isRock?@"🪨":@"🐢";
            LOG(@"💥 HIT by %@! Lives: %d",t,_lives);
            SCNParticleSystem *hf=[ParticleSystem impactDirt];SCNNode *hn=[SCNNode node];[hn addParticleSystem:hf];
            hn.position=r.position;[_scnView.scene.rootNode addChildNode:hn];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1.5*NSEC_PER_SEC),dispatch_get_main_queue(),^{[hn removeFromParentNode];});
            SCNAction *flash=[SCNAction sequence:@[[SCNAction fadeOpacityTo:0.3 duration:0.06],[SCNAction fadeOpacityTo:1.0 duration:0.06],[SCNAction fadeOpacityTo:0.3 duration:0.06],[SCNAction fadeOpacityTo:1.0 duration:0.06]]];
            [_playerModelNode runAction:flash];
            if(_lives<=0){LOG(@"💀 GAME OVER — Score: %d, Coins: %d, Rings: %d",_score,_coins,_rings);[self doGameOver];return;}
            [r removeFromParentNode];[pool removeObject:r];
        }
    }
    for(SCNNode *r in toRemove){[r removeFromParentNode];[pool removeObject:r];}
}

// ─── MONKEY CAR ──────────────────────────────
- (void)spawnMonkeyCar {
    _monkeyCarZ = -8;
    _monkeyCarNode = [SCNNode node];
    SCNBox *body = [SCNBox boxWithWidth:1.2 height:0.5 length:2.0 chamferRadius:0.1];
    SCNMaterial *m = [SCNMaterial material];
    m.lightingModelName = SCNLightingModelPhysicallyBased;
    m.diffuse.contents = [UIColor yellowColor];
    m.roughness.contents = @0.3; m.metalness.contents = @0.5;
    body.materials = @[m];
    [_monkeyCarNode setGeometry:body];
    [_scnView.scene.rootNode addChildNode:_monkeyCarNode];
    _monkeyCarActive = YES;
}

// ─── FPS ─────────────────────────────────────
- (void)updFPS:(NSTimeInterval)time {_fpsCount++;
    if(time-_lastFps>=0.5){int fps=(int)(_fpsCount/(time-_lastFps));
        _fpsLabel.text=[NSString stringWithFormat:@"%d FPS",fps];
        _fpsLabel.fontColor=fps>50?[SKColor greenColor]:(fps>30?[SKColor yellowColor]:[SKColor redColor]);
        _fpsCount=0;_lastFps=time;}}

// ─── GAME OVER ───────────────────────────────
- (void)doGameOver {_gameOver=YES;[self switchAnimation:@"die"];
    [[AudioEngine shared] playDeath];
    SCNParticleSystem *dp=[ParticleSystem impactDirt];dp.birthRate=80;
    SCNNode *dn=[SCNNode node];[dn addParticleSystem:dp];dn.position=SCNVector3Make(0,0.8,0);
    [_playerNode addChildNode:dn];
    SKLabelNode *go=[SKLabelNode labelNodeWithFontNamed:@"HelveticaNeue-Bold"];
    go.text=@"GAME OVER";go.fontSize=42;go.fontColor=[SKColor redColor];
    go.position=CGPointMake(_hudScene.size.width/2,_hudScene.size.height/2);
    [_hudScene addChild:go];
    SKLabelNode *rs=[SKLabelNode labelNodeWithFontNamed:@"HelveticaNeue"];
    rs.text=@"Tap to restart";rs.fontSize=20;rs.fontColor=[SKColor whiteColor];
    rs.position=CGPointMake(_hudScene.size.width/2,_hudScene.size.height/2-50);
    [_hudScene addChild:rs];
    UIButton *rb = [self.view viewWithTag:999];
    rb.hidden = NO;
    LOG(@"💀 GAME OVER | Score: %d | Coins: %d | Rings: %d | Distance: %.0f", _score, _coins, _rings, _distance);
}

- (void)restartGame {_lives=3;_score=0;_coins=0;_rings=0;_distance=0;_speed=10;
    _lane=0;_laneX=0;_playerY=1.0;_jumping=NO;_sliding=NO;_invincibleTimer=0;
    _gameOver=NO;_foodBoostTimer=0;_magnetTimer=0;_hasFoodBoost=NO;_hasMagnet=NO;
    _playerNode.position=SCNVector3Make(0,1.0,0);_playerModelNode.scale=SCNVector3Make(1,1,1);
    _playerModelNode.position=SCNVector3Make(0,0,0);[self switchAnimation:@"idle"];
    for(SCNNode *r in _rocks)[r removeFromParentNode];for(SCNNode *c in _coinObjects)[c removeFromParentNode];
    for(SCNNode *t in _turtles)[t removeFromParentNode];for(SCNNode *r in _ringObjects)[r removeFromParentNode];
    for(SCNNode *h in _heartObjects)[h removeFromParentNode];
    [_rocks removeAllObjects];[_coinObjects removeAllObjects];[_turtles removeAllObjects];
    [_ringObjects removeAllObjects];[_heartObjects removeAllObjects];
    if (_monkeyCarActive) { [_monkeyCarNode removeFromParentNode]; _monkeyCarActive = NO; }
    [_hudScene removeAllChildren];[self setupHUD];
    UIButton *rb = [self.view viewWithTag:999]; rb.hidden = YES;
    _nextRockZ=-15;_nextCoinZ=-6;_nextTurtleZ=-30;_nextRingZ=-10;_nextHeartZ=-50;
    _frameCount=0;
    LOG(@"🔄 GAME RESTARTED");
}

- (void)viewDidLayoutSubviews {_scnView.frame=self.view.bounds;_hudView.frame=self.view.bounds;_hudScene.size=self.view.bounds.size;}
- (BOOL)prefersStatusBarHidden {return YES;}
- (BOOL)prefersHomeIndicatorAutoHidden {return YES;}
@end
