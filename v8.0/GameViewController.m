#import <SceneKit/SceneKit.h>
#import <SpriteKit/SpriteKit.h>
#import "GLTFLoader.h"
#import "AudioEngine.h"
#import "ParticleSystem.h"

// ─── CONSTANTS ─────────────────────────────────
#define LANE_WIDTH 2.5f
#define LANE_X(l) ((l) * LANE_WIDTH)
#define ROAD_WIDTH (LANE_WIDTH * 3.6f)
#define TILE_LENGTH 8.0f
#define NUM_TILES 30
#define SHADOW_SIZE 2048
#define MAX_TREES 35
#define MAX_ROCKS 8
#define MAX_COINS 12

// ─── PBR MATERIAL FROM BUNDLE ──────────────────
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
    int _score, _lives, _coins;
    float _speed, _distance, _invincibleTimer;
    BOOL _gameOver;
    
    NSMutableArray<SCNNode *> *_roadTiles, *_trees, *_rocks, *_coinObjects;
    float _nextRockZ, _nextCoinZ, _nextTreeZ;
    SCNNode *_dustEmitter;
    
    SCNNode *_animRun, *_animJump, *_animSlide, *_animIdle, *_animDie;
    NSString *_currentAnim;
    
    NSArray *_treeNames, *_rockNames;
    
    SKView *_hudView; SKScene *_hudScene;
    SKLabelNode *_scoreLabel, *_coinLabel, *_lifeLabel, *_fpsLabel, *_speedLabel;
    NSTimeInterval _lastFps; int _fpsCount;
    float _stepTimer;
    NSTimeInterval _lastTime;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _treeNames = [[NSArray alloc] initWithObjects:@"tree_default",@"tree_detailed",@"tree_oak",@"tree_fat",@"tree_cone",@"tree_tall",@"tree_small",@"tree_thin",@"tree_simple",@"tree_blocks",@"tree_pineDefaultA",@"tree_pineDefaultB",@"tree_pineTallA",@"tree_pineTallC",@"tree_pineRoundA",@"tree_pineRoundC",@"tree_pineSmallA",@"tree_pineSmallC", nil];
    _rockNames = [[NSArray alloc] initWithObjects:@"cliff_rock",@"cliff_large_rock",@"cliff_half_rock",@"cliff_corner_rock",@"cliff_block_rock", nil];
    
    // Scene setup
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
    
    // Camera
    SCNCamera *cam = [SCNCamera camera];
    cam.zNear = 0.2; cam.zFar = 300; cam.fieldOfView = 65;
    cam.wantsHDR = YES; cam.wantsExposureAdaptation = YES;
    cam.exposureOffset = 0.3; cam.bloomIntensity = 0.4;
    cam.bloomThreshold = 0.85; cam.bloomBlurRadius = 10.0;
    _cameraNode = [SCNNode node]; _cameraNode.camera = cam;
    _cameraNode.position = SCNVector3Make(0, 5.5, 7);
    _cameraNode.eulerAngles = SCNVector3Make(-0.5, 0, 0);
    [scene.rootNode addChildNode:_cameraNode];
    
    // Ground (PBR)
    SCNFloor *floor = [SCNFloor floor];
    floor.reflectivity = 0.0;
    floor.materials = @[pbrMaterial(@"ground")];
    SCNNode *fn = [SCNNode nodeWithGeometry:floor];
    fn.position = SCNVector3Make(0, -0.05, -80);
    [scene.rootNode addChildNode:fn];
    
    // Load player models
    [self loadPlayerModels];
    
    // Create road system
    [self createRoad];
    
    // Game state init
    _lane = 0; _laneX = 0; _jumping = NO; _jumpVel = 0; _playerY = 1.0;
    _sliding = NO; _slideTimer = 0; _score = 0; _lives = 3; _coins = 0;
    _speed = 10; _distance = 0; _invincibleTimer = 0; _gameOver = NO;
    _roadTiles = [NSMutableArray array];
    _trees = [NSMutableArray array]; _rocks = [NSMutableArray array];
    _coinObjects = [NSMutableArray array];
    _nextRockZ = -15; _nextCoinZ = -6; _nextTreeZ = -8;
    _lastTime = 0;
    
    // Dust particle
    SCNParticleSystem *dust = [ParticleSystem dustTrail];
    _dustEmitter = [SCNNode node]; [_dustEmitter addParticleSystem:dust];
    _dustEmitter.position = SCNVector3Make(0, 0.15, -0.3);
    [_playerNode addChildNode:_dustEmitter];
    
    // HUD + Gestures
    [self setupHUD];
    [self setupGestures];
    
    // Start audio
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5*NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [[AudioEngine shared] startAmbient];
    });
}

// ─── SKY GRADIENT ─────────────────────────────
- (id)skyGradient {
    int h = 256;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    size_t bpr = h * 4;
    uint8_t *d = (uint8_t *)malloc(h * bpr);
    for (int y = 0; y < h; y++) {
        float t = y / (float)h;
        for (int x = 0; x < h; x++) {
            int i = (y * h + x) * 4;
            d[i] = (uint8_t)((0.35 + t * 0.3) * 255);
            d[i+1] = (uint8_t)((0.55 + t * 0.25) * 255);
            d[i+2] = (uint8_t)((0.75 + t * 0.2) * 255);
            d[i+3] = 255;
        }
    }
    CGContextRef ctx = CGBitmapContextCreate(d, h, h, 8, bpr, cs, kCGImageAlphaPremultipliedLast);
    CGImageRef img = CGBitmapContextCreateImage(ctx);
    UIImage *ui = [UIImage imageWithCGImage:img];
    CGImageRelease(img); CGContextRelease(ctx); CGColorSpaceRelease(cs); free(d);
    return ui;
}

// ─── LIGHTING ──────────────────────────────────
- (void)setupLighting {
    SCNLight *sun = [SCNLight light]; sun.type = SCNLightTypeDirectional;
    sun.color = [UIColor colorWithRed:1.0 green:0.95 blue:0.85 alpha:1.0];
    sun.intensity = 1200; sun.temperature = 5500;
    sun.castsShadow = YES; sun.shadowRadius = 2.0;
    sun.shadowMapSize = CGSizeMake(SHADOW_SIZE, SHADOW_SIZE);
    sun.shadowMode = SCNShadowModeForward;
    _sunNode = [SCNNode node]; _sunNode.light = sun;
    _sunNode.position = SCNVector3Make(8, 25, -10);
    [_scnView.scene.rootNode addChildNode:_sunNode];
    
    SCNLight *fill = [SCNLight light]; fill.type = SCNLightTypeAmbient;
    fill.color = [UIColor colorWithRed:0.45 green:0.55 blue:0.70 alpha:1.0];
    fill.intensity = 400;
    _fillNode = [SCNNode node]; _fillNode.light = fill;
    [_scnView.scene.rootNode addChildNode:_fillNode];
}

// ─── PLAYER ────────────────────────────────────
- (void)loadPlayerModels {
    _playerNode = [SCNNode node];
    _playerNode.position = SCNVector3Make(0, _playerY, 0);
    [_scnView.scene.rootNode addChildNode:_playerNode];
    _playerModelNode = [SCNNode node];
    [_playerNode addChildNode:_playerModelNode];
    
    _animIdle = [GLTFLoader loadModel:@"DwarfIdle"];
    _animRun = [GLTFLoader loadModel:@"running"];
    _animJump = [GLTFLoader loadModel:@"jump"];
    _animSlide = [GLTFLoader loadModel:@"slide"];
    _animDie = [GLTFLoader loadModel:@"SideHitDie"];
    
    [self switchAnimation:@"idle"];
}

- (void)switchAnimation:(NSString *)name {
    if ([_currentAnim isEqualToString:name]) return;
    _currentAnim = name;
    for (SCNNode *c in _playerModelNode.childNodes) [c removeFromParentNode];
    SCNNode *model = nil;
    if ([name isEqualToString:@"idle"])  model = [_animIdle clone];
    else if ([name isEqualToString:@"run"])   model = [_animRun clone];
    else if ([name isEqualToString:@"jump"])  model = [_animJump clone];
    else if ([name isEqualToString:@"slide"]) model = [_animSlide clone];
    else if ([name isEqualToString:@"die"])   model = [_animDie clone];
    if (model) {
        model.scale = SCNVector3Make(0.8, 0.8, 0.8);
        [_playerModelNode addChildNode:model];
    }
}

// ─── ROAD ──────────────────────────────────────
- (void)createRoad {
    _roadContainer = [SCNNode node];
    [_scnView.scene.rootNode addChildNode:_roadContainer];
    for (int i = 0; i < NUM_TILES; i++) {
        SCNNode *tile = [self makeRoadTile:i];
        [_roadContainer addChildNode:tile];
        [_roadTiles addObject:tile];
    }
}

- (SCNNode *)makeRoadTile:(int)index {
    SCNBox *box = [SCNBox boxWithWidth:ROAD_WIDTH height:0.15 length:TILE_LENGTH chamferRadius:0.02];
    box.materials = @[pbrMaterial(@"road")];
    SCNNode *node = [SCNNode nodeWithGeometry:box];
    node.position = SCNVector3Make(0, -0.07, -index * TILE_LENGTH);
    return node;
}

// ─── TREE (from Kenney GLB) ──────────────────
- (SCNNode *)createTree {
    NSString *name = _treeNames[arc4random_uniform((uint32_t)_treeNames.count)];
    SCNNode *tree = [GLTFLoader loadModel:name];
    if (!tree) { return [SCNNode node]; }
    tree.scale = SCNVector3Make(0.7, 0.7, 0.7);
    return tree;
}

// ─── ROCK (from Kenney GLB) ───────────────────
- (SCNNode *)createRock {
    NSString *name = _rockNames[arc4random_uniform((uint32_t)_rockNames.count)];
    SCNNode *rock = [GLTFLoader loadModel:name];
    if (!rock) { rock = [SCNNode node]; }
    rock.scale = SCNVector3Make(1.5, 1.0, 1.5);
    return rock;
}

// ─── COIN ──────────────────────────────────────
- (SCNNode *)createCoin {
    SCNNode *coin = [SCNNode node];
    SCNCylinder *body = [SCNCylinder cylinderWithRadius:0.3 height:0.06];
    SCNMaterial *cm = [SCNMaterial material];
    cm.lightingModelName = SCNLightingModelPhysicallyBased;
    cm.diffuse.contents = [UIColor colorWithRed:1.0 green:0.75 blue:0.1 alpha:1.0];
    cm.roughness.contents = @0.15; cm.metalness.contents = @1.0;
    body.materials = @[cm];
    SCNNode *bn = [SCNNode nodeWithGeometry:body];
    bn.eulerAngles = SCNVector3Make(M_PI_2, 0, 0);
    [coin addChildNode:bn];
    SCNTorus *ring = [SCNTorus torusWithRingRadius:0.33 pipeRadius:0.02];
    SCNMaterial *rm = [SCNMaterial material];
    rm.lightingModelName = SCNLightingModelConstant;
    rm.diffuse.contents = [UIColor colorWithRed:1.0 green:0.9 blue:0.2 alpha:1.0];
    ring.materials = @[rm];
    SCNNode *rn = [SCNNode nodeWithGeometry:ring];
    rn.eulerAngles = SCNVector3Make(M_PI_2, 0, 0);
    [coin addChildNode:rn];
    return coin;
}

// ─── HUD ──────────────────────────────────────
- (void)setupHUD {
    _hudView = [[SKView alloc] initWithFrame:self.view.bounds];
    _hudView.backgroundColor = [UIColor clearColor];
    _hudView.allowsTransparency = YES;
    [self.view addSubview:_hudView];
    _hudScene = [SKScene sceneWithSize:self.view.bounds.size];
    _hudScene.scaleMode = SKSceneScaleModeResizeFill;
    [_hudView presentScene:_hudScene];
    
    CGSize s = _hudScene.size; float pad = 25;
    _scoreLabel = [self hl:@"SCORE: 0" sz:28 c:[SKColor whiteColor]];
    _scoreLabel.position = CGPointMake(pad, s.height - 45);
    _scoreLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeLeft;
    [_hudScene addChild:_scoreLabel];
    
    _coinLabel = [self hl:@"🪙 0" sz:24 c:[SKColor colorWithRed:1.0 green:0.85 blue:0.2 alpha:1.0]];
    _coinLabel.position = CGPointMake(pad, s.height - 80);
    _coinLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeLeft;
    [_hudScene addChild:_coinLabel];
    
    _speedLabel = [self hl:@"⚡ 10 m/s" sz:16 c:[SKColor colorWithRed:0.6 green:0.9 blue:1.0 alpha:1.0]];
    _speedLabel.position = CGPointMake(pad, s.height - 108);
    _speedLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeLeft;
    [_hudScene addChild:_speedLabel];
    
    _lifeLabel = [self hl:@"❤️❤️❤️" sz:22 c:[SKColor redColor]];
    _lifeLabel.position = CGPointMake(s.width - pad, s.height - 45);
    _lifeLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeRight;
    [_hudScene addChild:_lifeLabel];
    
    _fpsLabel = [self hl:@"60 FPS" sz:13 c:[SKColor greenColor]];
    _fpsLabel.position = CGPointMake(s.width - pad, 22);
    _fpsLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeRight;
    [_hudScene addChild:_fpsLabel];
    _lastFps = CACurrentMediaTime();
}

- (SKLabelNode *)hl:(NSString *)t sz:(float)s c:(SKColor *)c {
    SKLabelNode *l = [SKLabelNode labelNodeWithFontNamed:@"HelveticaNeue-Bold"];
    l.text = t; l.fontSize = s; l.fontColor = c; return l;
}

// ─── GESTURES ──────────────────────────────────
- (void)setupGestures {
    UISwipeGestureRecognizer *sl = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeLeft)];
    sl.direction = UISwipeGestureRecognizerDirectionLeft; [_scnView addGestureRecognizer:sl];
    UISwipeGestureRecognizer *sr = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeRight)];
    sr.direction = UISwipeGestureRecognizerDirectionRight; [_scnView addGestureRecognizer:sr];
    UISwipeGestureRecognizer *su = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeUp)];
    su.direction = UISwipeGestureRecognizerDirectionUp; [_scnView addGestureRecognizer:su];
    UISwipeGestureRecognizer *sd = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeDown)];
    sd.direction = UISwipeGestureRecognizerDirectionDown; [_scnView addGestureRecognizer:sd];
}

- (void)swipeLeft  { if (!_gameOver && _lane > -1) { _lane--; _laneX = LANE_X(_lane); } }
- (void)swipeRight { if (!_gameOver && _lane < 1)  { _lane++; _laneX = LANE_X(_lane); } }
- (void)swipeUp    { if (!_gameOver && !_jumping && !_sliding) { _jumping = YES; _jumpVel = 7.5; [self switchAnimation:@"jump"]; [[AudioEngine shared] playJump]; } }
- (void)swipeDown  { if (!_gameOver && !_jumping && !_sliding) { _sliding = YES; _slideTimer = 0.7; _playerModelNode.scale = SCNVector3Make(1, 0.4, 1); _playerY = 0.5; [self switchAnimation:@"slide"]; [[AudioEngine shared] playSlide]; } }

// ═══════════════ GAME LOOP ════════════════════
- (void)renderer:(id<SCNSceneRenderer>)renderer updateAtTime:(NSTimeInterval)time {
    if (_gameOver) return;
    
    float dt = (_lastTime == 0) ? (1.0/60.0) : MIN(0.05, time - _lastTime);
    _lastTime = time;
    
    [self updFPS:time];
    
    _distance += _speed * dt;
    _score = (int)_distance;
    _speed = 10.0 + _distance / 100.0;
    if (_speed > 40) _speed = 40;
    _invincibleTimer = MAX(0, _invincibleTimer - dt);
    
    // Player lane movement
    float cx = _playerNode.position.x;
    cx += (_laneX - cx) * MIN(1, 12 * dt);
    _playerNode.position = SCNVector3Make(cx, _playerY, 0);
    
    // Running bob
    if (!_jumping && !_sliding) {
        _playerModelNode.position = SCNVector3Make(0, sin(_distance * 5.0) * 0.06, 0);
        if (![_currentAnim isEqualToString:@"run"]) [self switchAnimation:@"run"];
    }
    
    // Jump physics
    if (_jumping) {
        _jumpVel -= 20 * dt;
        _playerY += _jumpVel * dt;
        if (_playerY <= 1.0) {
            _playerY = 1.0; _jumping = NO; _jumpVel = 0;
            _playerModelNode.position = SCNVector3Make(0, 0, 0);
            [self switchAnimation:@"run"];
            SCNParticleSystem *imp = [ParticleSystem impactDirt];
            SCNNode *in = [SCNNode node]; [in addParticleSystem:imp];
            in.position = SCNVector3Make(0, 0.1, 0);
            [_playerNode addChildNode:in];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.0*NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [in removeFromParentNode]; });
        }
        _playerNode.position = SCNVector3Make(_playerNode.position.x, _playerY, _playerNode.position.z);
    }
    
    // Slide
    if (_sliding) {
        _slideTimer -= dt;
        if (_slideTimer <= 0) {
            _sliding = NO;
            _playerModelNode.scale = SCNVector3Make(1, 1, 1);
            _playerY = 1.0;
            [self switchAnimation:@"run"];
        }
    }
    
    // Footstep audio
    _stepTimer += dt;
    if (!_jumping && !_sliding && _stepTimer > 0.35) {
        _stepTimer = 0; [[AudioEngine shared] playFootstep];
    }
    
    // Road recycling
    for (SCNNode *tile in _roadTiles) {
        tile.position = SCNVector3Make(tile.position.x, tile.position.y, tile.position.z + _speed * dt);
        if (tile.position.z > TILE_LENGTH) {
            tile.position = SCNVector3Make(tile.position.x, tile.position.y, tile.position.z - NUM_TILES * TILE_LENGTH);
        }
    }
    
    // Spawn trees
    _nextTreeZ += _speed * dt;
    if (_nextTreeZ > 0 && _trees.count < MAX_TREES) {
        _nextTreeZ = -14 - drand48() * 20;
        SCNNode *tree = [self createTree];
        int side = (drand48() < 0.5) ? -1 : 1;
        tree.position = SCNVector3Make(side * (3.2 + drand48() * 5.5), 0, _playerNode.position.z - 35);
        [_scnView.scene.rootNode addChildNode:tree];
        [_trees addObject:tree];
    }
    NSMutableArray *dt2 = [NSMutableArray array];
    for (SCNNode *t in _trees) {
        t.position = SCNVector3Make(t.position.x, t.position.y, t.position.z + _speed * dt);
        if (t.position.z > 8) [dt2 addObject:t];
    }
    for (SCNNode *t in dt2) { [t removeFromParentNode]; [_trees removeObject:t]; }
    
    // Spawn rocks
    _nextRockZ += _speed * dt;
    if (_nextRockZ > 0 && _rocks.count < MAX_ROCKS) {
        _nextRockZ = -18 - drand48() * 30;
        int rl = (int)(drand48() * 3) - 1;
        SCNNode *rock = [self createRock];
        rock.position = SCNVector3Make(LANE_X(rl), 0.25, _playerNode.position.z - 35);
        [_scnView.scene.rootNode addChildNode:rock];
        [_rocks addObject:rock];
    }
    NSMutableArray *dr = [NSMutableArray array];
    for (SCNNode *r in _rocks) {
        r.position = SCNVector3Make(r.position.x, r.position.y, r.position.z + _speed * dt);
        if (r.position.z > 5) { [dr addObject:r]; continue; }
        float dx = fabsf(r.position.x - _playerNode.position.x);
        float dz = fabsf(r.position.z);
        float ht = _sliding ? 0.45 : 0.65;
        if (dx < ht && dz < 0.6 && _invincibleTimer <= 0 && !_jumping && _playerY < 1.2) {
            _lives--; _invincibleTimer = 1.5; [[AudioEngine shared] playHit];
            SCNParticleSystem *hf = [ParticleSystem impactDirt];
            SCNNode *hn = [SCNNode node]; [hn addParticleSystem:hf];
            hn.position = r.position;
            [_scnView.scene.rootNode addChildNode:hn];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.5*NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [hn removeFromParentNode]; });
            SCNAction *flash = [SCNAction sequence:@[
                [SCNAction fadeOpacityTo:0.3 duration:0.06],
                [SCNAction fadeOpacityTo:1.0 duration:0.06],
                [SCNAction fadeOpacityTo:0.3 duration:0.06],
                [SCNAction fadeOpacityTo:1.0 duration:0.06]
            ]];
            [_playerModelNode runAction:flash];
            if (_lives <= 0) { [self doGameOver]; return; }
            [r removeFromParentNode]; [_rocks removeObject:r];
        }
    }
    for (SCNNode *r in dr) { [r removeFromParentNode]; [_rocks removeObject:r]; }
    
    // Spawn coins
    _nextCoinZ += _speed * dt;
    if (_nextCoinZ > 0 && _coinObjects.count < MAX_COINS) {
        _nextCoinZ = -4 - drand48() * 10;
        int cl = (int)(drand48() * 3) - 1;
        SCNNode *coin = [self createCoin];
        coin.position = SCNVector3Make(LANE_X(cl), 1.2, _playerNode.position.z - 28);
        [_scnView.scene.rootNode addChildNode:coin];
        [_coinObjects addObject:coin];
    }
    NSMutableArray *dc = [NSMutableArray array];
    for (SCNNode *c in _coinObjects) {
        c.position = SCNVector3Make(c.position.x, c.position.y, c.position.z + _speed * dt);
        c.rotation = SCNVector4Make(0, 1, 0, c.rotation.w + dt * 5);
        if (c.position.z > 5) { [dc addObject:c]; continue; }
        float dx = fabsf(c.position.x - _playerNode.position.x);
        float dz = fabsf(c.position.z);
        if (dx < 0.7 && dz < 0.7) {
            _coins++; [[AudioEngine shared] playCoin];
            SCNParticleSystem *burst = [ParticleSystem coinBurst];
            SCNNode *bn = [SCNNode node]; [bn addParticleSystem:burst];
            bn.position = c.position;
            [_scnView.scene.rootNode addChildNode:bn];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.0*NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [bn removeFromParentNode]; });
            [c removeFromParentNode]; [_coinObjects removeObject:c];
        }
    }
    for (SCNNode *c in dc) { [c removeFromParentNode]; [_coinObjects removeObject:c]; }
    
    // HUD update
    _scoreLabel.text = [NSString stringWithFormat:@"SCORE: %d", _score];
    _coinLabel.text = [NSString stringWithFormat:@"🪙 %d", _coins];
    _speedLabel.text = [NSString stringWithFormat:@"⚡ %.0f m/s", _speed];
    NSMutableString *hearts = [NSMutableString string];
    for (int i = 0; i < _lives; i++) [hearts appendString:@"❤️"];
    if (_invincibleTimer > 0 && fmod(time, 0.2) < 0.1) hearts = [NSMutableString string];
    _lifeLabel.text = hearts;
    _dustEmitter.hidden = _jumping;
    SCNParticleSystem *dustSys = _dustEmitter.particleSystems.firstObject;
    dustSys.birthRate = _sliding ? 60 : 25;
}

- (void)updFPS:(NSTimeInterval)time {
    _fpsCount++;
    if (time - _lastFps >= 0.5) {
        int fps = (int)(_fpsCount / (time - _lastFps));
        _fpsLabel.text = [NSString stringWithFormat:@"%d FPS", fps];
        _fpsLabel.fontColor = fps > 50 ? [SKColor greenColor] : (fps > 30 ? [SKColor yellowColor] : [SKColor redColor]);
        _fpsCount = 0; _lastFps = time;
    }
}

- (void)doGameOver {
    _gameOver = YES;
    [self switchAnimation:@"die"];
    [[AudioEngine shared] playDeath];
    SCNParticleSystem *dp = [ParticleSystem impactDirt];
    dp.birthRate = 80;
    SCNNode *dn = [SCNNode node]; [dn addParticleSystem:dp];
    dn.position = SCNVector3Make(0, 0.8, 0);
    [_playerNode addChildNode:dn];
    SKLabelNode *go = [SKLabelNode labelNodeWithFontNamed:@"HelveticaNeue-Bold"];
    go.text = @"GAME OVER"; go.fontSize = 42;
    go.fontColor = [SKColor redColor];
    go.position = CGPointMake(_hudScene.size.width/2, _hudScene.size.height/2);
    [_hudScene addChild:go];
    SKLabelNode *rs = [SKLabelNode labelNodeWithFontNamed:@"HelveticaNeue"];
    rs.text = @"Tap to restart"; rs.fontSize = 20;
    rs.fontColor = [SKColor whiteColor];
    rs.position = CGPointMake(_hudScene.size.width/2, _hudScene.size.height/2 - 50);
    [_hudScene addChild:rs];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(restartGame)];
    [_scnView addGestureRecognizer:tap];
}

- (void)restartGame {
    _lives = 3; _score = 0; _coins = 0; _distance = 0; _speed = 10;
    _lane = 0; _laneX = 0; _playerY = 1.0;
    _jumping = NO; _sliding = NO; _invincibleTimer = 0; _gameOver = NO;
    _playerNode.position = SCNVector3Make(0, 1.0, 0);
    _playerModelNode.scale = SCNVector3Make(1, 1, 1);
    _playerModelNode.position = SCNVector3Make(0, 0, 0);
    [self switchAnimation:@"idle"];
    for (SCNNode *r in _rocks) [r removeFromParentNode];
    for (SCNNode *c in _coinObjects) [c removeFromParentNode];
    [_rocks removeAllObjects]; [_coinObjects removeAllObjects];
    [_hudScene removeAllChildren]; [self setupHUD];
    for (UIGestureRecognizer *g in _scnView.gestureRecognizers)
        if ([g isKindOfClass:[UITapGestureRecognizer class]])
            [_scnView removeGestureRecognizer:g];
    _nextRockZ = -15; _nextCoinZ = -6;
}

- (void)viewDidLayoutSubviews {
    _scnView.frame = self.view.bounds;
    _hudView.frame = self.view.bounds;
    _hudScene.size = self.view.bounds.size;
}
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
@end
