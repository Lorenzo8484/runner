#import "GameViewController.h"
#import "AudioEngine.h"
#import "ParticleSystem.h"
#import "TextureGenerator.h"

// ─── Forward declarations for procedural texture helpers ──
static inline float hash_f(float x, float y);
static inline float smoothNoise_f(float x, float y);
float fbm(float x, float y, int octaves);
static UIImage *genImage(int size, float(^block)(int, int));
static UIImage *genColorImage(int size, void(^block)(int, int, float*));

// ═══════════════════════════════════════════════════════════
// HELPERS — must be defined before @implementation
// ═══════════════════════════════════════════════════════════
static inline float hash_f(float x, float y) {
    return fmodf(sinf(x * 127.1f + y * 311.7f) * 43758.5453f, 1.0f);
}

static inline float smoothNoise_f(float x, float y) {
    int ix = (int)floorf(x), iy = (int)floorf(y);
    float fx = x - ix, fy = y - iy;
    float sx = fx * fx * (3.0f - 2.0f * fx);
    float sy = fy * fy * (3.0f - 2.0f * fy);
    return hash_f(ix,iy)*(1-sx)*(1-sy) + hash_f(ix+1,iy)*sx*(1-sy) + hash_f(ix,iy+1)*(1-sx)*sy + hash_f(ix+1,iy+1)*sx*sy;
}

float fbm(float x, float y, int octaves) {
    float val = 0, amp = 0.5f, freq = 1.0f;
    for (int i = 0; i < octaves; i++) {
        val += amp * smoothNoise_f(x * freq, y * freq);
        amp *= 0.5f; freq *= 2.0f;
    }
    return val;
}

static UIImage *genImage(int size, float(^block)(int, int)) {
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    size_t bpr = size * 4;
    uint8_t *data = (uint8_t *)malloc(size * bpr);
    for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
            float v = block(x, y);
            uint8_t b = (uint8_t)(v * 255);
            int idx = (y * size + x) * 4;
            data[idx] = b; data[idx+1] = b; data[idx+2] = b; data[idx+3] = 255;
        }
    }
    CGContextRef ctx = CGBitmapContextCreate(data, size, size, 8, bpr, cs, kCGImageAlphaPremultipliedLast);
    CGImageRef imgRef = CGBitmapContextCreateImage(ctx);
    UIImage *ui = [UIImage imageWithCGImage:imgRef];
    CGImageRelease(imgRef); CGContextRelease(ctx); CGColorSpaceRelease(cs); free(data);
    return ui;
}

static UIImage *genColorImage(int size, void(^block)(int, int, float*)) {
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    size_t bpr = size * 4;
    uint8_t *data = (uint8_t *)malloc(size * bpr);
    for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
            float c[3]; block(x, y, c);
            int idx = (y * size + x) * 4;
            data[idx] = (uint8_t)(c[0]*255);
            data[idx+1] = (uint8_t)(c[1]*255);
            data[idx+2] = (uint8_t)(c[2]*255);
            data[idx+3] = 255;
        }
    }
    CGContextRef ctx = CGBitmapContextCreate(data, size, size, 8, bpr, cs, kCGImageAlphaPremultipliedLast);
    CGImageRef imgRef = CGBitmapContextCreateImage(ctx);
    UIImage *ui = [UIImage imageWithCGImage:imgRef];
    CGImageRelease(imgRef); CGContextRelease(ctx); CGColorSpaceRelease(cs); free(data);
    return ui;
}

// ─── PBR TEXTURE HELPER — Loads real 2K textures from bundle ──
static SCNMaterial *pbrMaterial(NSString *set) {
    SCNMaterial *mat = [SCNMaterial material];
    mat.lightingModelName = SCNLightingModelPhysicallyBased;
    
    NSString *base = [NSString stringWithFormat:@"Assets/%@", set];
    NSBundle *bundle = [NSBundle mainBundle];
    
    mat.diffuse.contents = [UIImage imageWithContentsOfFile:[bundle pathForResource:[base stringByAppendingString:@"/diff.jpg"] ofType:nil]];
    mat.roughness.contents = [UIImage imageWithContentsOfFile:[bundle pathForResource:[base stringByAppendingString:@"/rough.jpg"] ofType:nil]];
    mat.normal.contents = [UIImage imageWithContentsOfFile:[bundle pathForResource:[base stringByAppendingString:@"/normal.jpg"] ofType:nil]];
    
    // AO map (multiply into diffuse or use as ambient occlusion property)
    NSString *aoPath = [bundle pathForResource:[base stringByAppendingString:@"/ao.jpg"] ofType:nil];
    if (aoPath) mat.ambientOcclusion.contents = [UIImage imageWithContentsOfFile:aoPath];
    
    // Wrap modes
    mat.diffuse.wrapS = SCNWrapModeRepeat;
    mat.diffuse.wrapT = SCNWrapModeRepeat;
    mat.roughness.wrapS = SCNWrapModeRepeat;
    mat.roughness.wrapT = SCNWrapModeRepeat;
    mat.normal.wrapS = SCNWrapModeRepeat;
    mat.normal.wrapT = SCNWrapModeRepeat;
    
    mat.metalness.contents = @0.0; // default non-metallic
    
    return mat;
}

static UIImage *loadImage(NSString *name) {
    return [UIImage imageWithContentsOfFile:[[NSBundle mainBundle] pathForResource:name ofType:nil]];
}
#define LANE_WIDTH 2.5f
#define LANE_X(l) ((l) * LANE_WIDTH)
#define ROAD_WIDTH (LANE_WIDTH * 3.6f)
#define TILE_LENGTH 8.0f
#define NUM_TILES 30
#define SHADOW_SIZE 2048

// ─── GAME VIEW CONTROLLER ─────────────────────────────────
@implementation GameViewController {
    // SceneKit
    SCNView *_scnView;
    SCNNode *_cameraNode;
    SCNNode *_playerNode;
    SCNNode *_playerBodyNode;   // rotates for drift effect
    SCNNode *_roadContainer;
    
    // Lighting
    SCNNode *_sunNode;
    SCNNode *_fillNode;
    
    // Game state
    int _lane;              // -1, 0, 1
    float _laneX;
    BOOL _jumping;
    float _jumpVel;
    float _playerY;
    BOOL _sliding;
    float _slideTimer;
    int _score;
    int _lives;
    int _coins;
    float _speed;
    float _distance;
    float _invincibleTimer;
    BOOL _gameOver;
    
    // World objects
    NSMutableArray<SCNNode *> *_roadTiles;
    NSMutableArray<SCNNode *> *_trees;
    NSMutableArray<SCNNode *> *_rocks;
    NSMutableArray<SCNNode *> *_coinObjects;
    float _nextRockZ;
    float _nextCoinZ;
    float _nextTreeZ;
    
    // Particles
    SCNNode *_dustEmitter;
    
    // HUD (SpriteKit overlay)
    SKView *_hudView;
    SKScene *_hudScene;
    SKLabelNode *_scoreLabel, *_coinLabel, *_lifeLabel, *_fpsLabel, *_speedLabel;
    
    // FPS tracking
    NSTimeInterval _lastFps;
    int _fpsCount;
    
    // Touch
    CGPoint _touchStart;
    NSTimeInterval _touchTime;
    
    // Footstep timer
    float _stepTimer;
    
    // Post-process textures
    id<MTLDevice> _metalDevice;
}

// ─── VIEW DID LOAD ────────────────────────────────────────
- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Metal device
    _metalDevice = MTLCreateSystemDefaultDevice();
    
    // ─── SCENE ───
    SCNScene *scene = [SCNScene scene];
    scene.background.contents = [self createSkyGradient];
    
    // Atmospheric fog — depth-based realism
    scene.fogColor = [UIColor colorWithRed:0.6 green:0.7 blue:0.8 alpha:1.0];
    scene.fogStartDistance = 50;
    scene.fogEndDistance = 200;
    scene.fogDensityExponent = 1.5;
    
    // ─── SCENEKIT VIEW ───
    _scnView = [[SCNView alloc] initWithFrame:self.view.bounds];
    _scnView.scene = scene;
    _scnView.delegate = self;
    _scnView.preferredFramesPerSecond = 60;
    _scnView.antialiasingMode = SCNAntialiasingModeMultisampling4X;
    
    // HDR enabled via camera settings
    
    [self.view addSubview:_scnView];
    
    // ─── LIGHTING (PBR realism) ───
    [self setupLighting];
    
    // ─── CAMERA ───
    SCNCamera *cam = [SCNCamera camera];
    cam.zNear = 0.2;
    cam.zFar = 300;
    cam.fieldOfView = 65;
    cam.wantsHDR = YES;
    cam.wantsExposureAdaptation = YES;
    cam.exposureOffset = 0.3;
    cam.bloomIntensity = 0.4;
    cam.bloomThreshold = 0.85;
    cam.bloomBlurRadius = 10.0;
    
    _cameraNode = [SCNNode node];
    _cameraNode.camera = cam;
    _cameraNode.position = SCNVector3Make(0, 5.5, 7);
    _cameraNode.eulerAngles = SCNVector3Make(-0.5, 0, 0);
    [scene.rootNode addChildNode:_cameraNode];
    
    // ─── FLOOR (ground plane with real PBR texture) ───
    SCNFloor *floor = [SCNFloor floor];
    floor.reflectivity = 0.0;
    floor.materials = @[pbrMaterial(@"ground")];
    SCNNode *floorNode = [SCNNode nodeWithGeometry:floor];
    floorNode.position = SCNVector3Make(0, -0.05, -80);
    [scene.rootNode addChildNode:floorNode];
    
    // ─── PLAYER ───
    [self createPlayer];
    
    // ─── ROAD ───
    [self createRoad];
    
    // ─── INIT STATE ───
    _lane = 0; _laneX = 0;
    _jumping = NO; _jumpVel = 0; _playerY = 0.95;
    _sliding = NO; _slideTimer = 0;
    _score = 0; _lives = 3; _coins = 0;
    _speed = 10; _distance = 0;
    _invincibleTimer = 0;
    _gameOver = NO;
    _stepTimer = 0;
    _roadTiles = [NSMutableArray array];
    _trees = [NSMutableArray array];
    _rocks = [NSMutableArray array];
    _coinObjects = [NSMutableArray array];
    _nextRockZ = -15;
    _nextCoinZ = -6;
    _nextTreeZ = -8;
    
    // ─── DUST PARTICLES ───
    SCNParticleSystem *dust = [ParticleSystem dustTrail];
    _dustEmitter = [SCNNode node];
    [_dustEmitter addParticleSystem:dust];
    _dustEmitter.position = SCNVector3Make(0, 0.1, -0.2);
    [_playerNode addChildNode:_dustEmitter];
    
    // ─── HUD ───
    [self setupHUD];
    
    // ─── GESTURES ───
    [self setupGestures];
    
    // ─── AUDIO ───
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [[AudioEngine shared] startAmbient];
    });
}

// ─── SKY GRADIENT ─────────────────────────────────────────
- (id)createSkyGradient {
    int h = 512;
    return genColorImage(h, ^(int x, int y, float *c) {
        float t = y / (float)h;
        // Blue sky at top, light blue horizon
        c[0] = 0.35 + t * 0.25;   // R
        c[1] = 0.55 + t * 0.25;   // G
        c[2] = 0.80 + t * 0.15;   // B
    });
}

// ─── LIGHTING SETUP (PBR) ─────────────────────────────────
- (void)setupLighting {
    // Sun — directional with soft shadows
    SCNLight *sun = [SCNLight light];
    sun.type = SCNLightTypeDirectional;
    sun.color = [UIColor colorWithRed:1.0 green:0.95 blue:0.85 alpha:1.0];
    sun.intensity = 1200;
    sun.temperature = 5500;
    sun.castsShadow = YES;
    sun.shadowRadius = 2.0;
    sun.shadowMapSize = CGSizeMake(SHADOW_SIZE, SHADOW_SIZE);
    sun.shadowMode = SCNShadowModeForward;
    sun.shadowBias = 0.5;
    sun.shadowCascadeCount = 2;
    sun.shadowCascadeSplittingFactor = 0.5;
    
    _sunNode = [SCNNode node];
    _sunNode.light = sun;
    _sunNode.position = SCNVector3Make(8, 25, -10);
    _sunNode.eulerAngles = SCNVector3Make(-0.6, 0.3, 0);
    [_scnView.scene.rootNode addChildNode:_sunNode];
    
    // Fill light — soft ambient from sky
    SCNLight *fill = [SCNLight light];
    fill.type = SCNLightTypeAmbient;
    fill.color = [UIColor colorWithRed:0.45 green:0.55 blue:0.70 alpha:1.0];
    fill.intensity = 400;
    
    _fillNode = [SCNNode node];
    _fillNode.light = fill;
    [_scnView.scene.rootNode addChildNode:_fillNode];
    
    // Rim/back light — subtle separation
    SCNLight *rim = [SCNLight light];
    rim.type = SCNLightTypeDirectional;
    rim.color = [UIColor colorWithRed:0.7 green:0.8 blue:1.0 alpha:1.0];
    rim.intensity = 300;
    
    SCNNode *rimNode = [SCNNode node];
    rimNode.light = rim;
    rimNode.position = SCNVector3Make(-5, 8, 5);
    [_scnView.scene.rootNode addChildNode:rimNode];
}

// ─── PLAYER CREATION ──────────────────────────────────────
- (void)createPlayer {
    _playerNode = [SCNNode node];
    _playerNode.position = SCNVector3Make(0, _playerY, 0);
    [_scnView.scene.rootNode addChildNode:_playerNode];
    
    // Container for drift rotation
    _playerBodyNode = [SCNNode node];
    [_playerNode addChildNode:_playerBodyNode];
    
    // ── SHOES ──
    for (int s = -1; s <= 1; s += 2) {
        SCNBox *shoe = [SCNBox boxWithWidth:0.35 height:0.15 length:0.55 chamferRadius:0.05];
        SCNMaterial *sm = [SCNMaterial material];
        sm.lightingModelName = SCNLightingModelPhysicallyBased;
        sm.diffuse.contents = [UIColor colorWithRed:0.15 green:0.12 blue:0.10 alpha:1.0];
        sm.roughness.contents = @0.6;
        sm.metalness.contents = @0.05;
        shoe.materials = @[sm];
        SCNNode *sn = [SCNNode nodeWithGeometry:shoe];
        sn.position = SCNVector3Make(s * 0.2, 0.08, 0.05);
        [_playerBodyNode addChildNode:sn];
    }
    
    // ── LEGS ──
    for (int l = -1; l <= 1; l += 2) {
        SCNCapsule *leg = [SCNCapsule capsuleWithCapRadius:0.15 height:0.9];
        SCNMaterial *lm = [SCNMaterial material];
        lm.lightingModelName = SCNLightingModelPhysicallyBased;
        lm.diffuse.contents = [UIColor colorWithRed:0.25 green:0.22 blue:0.18 alpha:1.0];
        lm.roughness.contents = @0.5;
        lm.metalness.contents = @0.02;
        leg.materials = @[lm];
        SCNNode *ln = [SCNNode nodeWithGeometry:leg];
        ln.position = SCNVector3Make(l * 0.2, 0.6, 0);
        [_playerBodyNode addChildNode:ln];
    }
    
    // ── TORSO ──
    SCNCapsule *torso = [SCNCapsule capsuleWithCapRadius:0.3 height:1.2];
    SCNMaterial *tm = [SCNMaterial material];
    tm.lightingModelName = SCNLightingModelPhysicallyBased;
    tm.diffuse.contents = [UIColor colorWithRed:0.15 green:0.30 blue:0.55 alpha:1.0];  // Navy blue shirt
    tm.roughness.contents = @0.4;
    tm.metalness.contents = @0.03;
    torso.materials = @[tm];
    SCNNode *tn = [SCNNode nodeWithGeometry:torso];
    tn.position = SCNVector3Make(0, 1.2, 0);
    [_playerBodyNode addChildNode:tn];
    
    // ── ARMS ──
    for (int a = -1; a <= 1; a += 2) {
        SCNCapsule *arm = [SCNCapsule capsuleWithCapRadius:0.1 height:0.8];
        SCNMaterial *am = [SCNMaterial material];
        am.lightingModelName = SCNLightingModelPhysicallyBased;
        am.diffuse.contents = [UIColor colorWithRed:0.22 green:0.20 blue:0.17 alpha:1.0];
        am.roughness.contents = @0.45;
        arm.materials = @[am];
        SCNNode *an = [SCNNode nodeWithGeometry:arm];
        an.position = SCNVector3Make(a * 0.4, 1.35, 0);
        an.eulerAngles = SCNVector3Make(0, 0, a * 0.4);
        [_playerBodyNode addChildNode:an];
    }
    
    // ── HEAD ──
    SCNSphere *head = [SCNSphere sphereWithRadius:0.32];
    SCNMaterial *hm = [SCNMaterial material];
    hm.lightingModelName = SCNLightingModelPhysicallyBased;
    hm.diffuse.contents = [UIColor colorWithRed:0.85 green:0.65 blue:0.45 alpha:1.0];  // Skin tone
    hm.roughness.contents = @0.6;
    hm.metalness.contents = @0.01;
    // Subsurface approximation for skin
    hm.transparent.contents = [UIColor colorWithWhite:0.05 alpha:1.0];
    head.materials = @[hm];
    SCNNode *hn = [SCNNode nodeWithGeometry:head];
    hn.position = SCNVector3Make(0, 2.05, 0);
    [_playerBodyNode addChildNode:hn];
    
    // ── EYES ──
    for (int e = -1; e <= 1; e += 2) {
        SCNSphere *eye = [SCNSphere sphereWithRadius:0.06];
        SCNMaterial *em = [SCNMaterial material];
        em.lightingModelName = SCNLightingModelPhysicallyBased;
        em.diffuse.contents = [UIColor whiteColor];
        em.roughness.contents = @0.1;
        eye.materials = @[em];
        SCNNode *en = [SCNNode nodeWithGeometry:eye];
        en.position = SCNVector3Make(e * 0.1, 2.12, 0.28);
        [_playerBodyNode addChildNode:en];
        
        // Pupil
        SCNSphere *pupil = [SCNSphere sphereWithRadius:0.03];
        pupil.materials.firstObject.diffuse.contents = [UIColor blackColor];
        SCNNode *pn = [SCNNode nodeWithGeometry:pupil];
        pn.position = SCNVector3Make(0, 0, 0.04);
        [en addChildNode:pn];
    }
    
    // ── MOUTH ──
    SCNBox *mouth = [SCNBox boxWithWidth:0.12 height:0.02 length:0.01 chamferRadius:0.005];
    mouth.materials.firstObject.diffuse.contents = [UIColor colorWithRed:0.5 green:0.25 blue:0.2 alpha:1.0];
    SCNNode *mn = [SCNNode nodeWithGeometry:mouth];
    mn.position = SCNVector3Make(0, 1.97, 0.3);
    [_playerBodyNode addChildNode:mn];
    
    // ── HAIR ──
    SCNSphere *hair = [SCNSphere sphereWithRadius:0.33];
    SCNMaterial *hairMat = [SCNMaterial material];
    hairMat.lightingModelName = SCNLightingModelPhysicallyBased;
    hairMat.diffuse.contents = [UIColor colorWithRed:0.12 green:0.08 blue:0.05 alpha:1.0];
    hairMat.roughness.contents = @0.7;
    hair.materials = @[hairMat];
    SCNNode *hairN = [SCNNode nodeWithGeometry:hair];
    hairN.position = SCNVector3Make(0, 0.12, -0.05);
    hairN.scale = SCNVector3Make(1.05, 0.55, 1.0);
    [hn addChildNode:hairN];
}

// ─── ROAD ─────────────────────────────────────────────────
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

// ─── TREE (PBR) ───────────────────────────────────────────
- (SCNNode *)createTree {
    SCNNode *tree = [SCNNode node];
    
    // Trunk — real bark texture
    SCNCylinder *trunk = [SCNCylinder cylinderWithRadius:0.25 height:2.5];
    trunk.materials = @[pbrMaterial(@"bark")];
    SCNNode *tNode = [SCNNode nodeWithGeometry:trunk];
    tNode.position = SCNVector3Make(0, 1.25, 0);
    [tree addChildNode:tNode];
    
    // Canopy — real foliage texture
    SCNMaterial *leafMat = pbrMaterial(@"foliage");
    
    // Crown spheres
    NSArray *crowns = @[
        @[@0, @2.5, @0, @1.2],
        @[@0.5, @3.0, @0.3, @0.9],
        @[@(-0.5), @2.8, @(-0.2), @1.0],
        @[@0, @3.5, @0, @0.7],
    ];
    
    for (NSArray *c in crowns) {
        SCNSphere *leaf = [SCNSphere sphereWithRadius:[c[3] floatValue]];
        leaf.materials = @[leafMat];
        SCNNode *ln = [SCNNode nodeWithGeometry:leaf];
        ln.position = SCNVector3Make([c[0] floatValue], [c[1] floatValue], [c[2] floatValue]);
        [tree addChildNode:ln];
    }
    
    return tree;
}

// ─── ROCK (PBR) ───────────────────────────────────────────
- (SCNNode *)createRock {
    SCNNode *rock = [SCNNode node];
    
    // Compound rock — real rock texture
    SCNNode *main = [SCNNode node];
    SCNSphere *body = [SCNSphere sphereWithRadius:0.5];
    SCNMaterial *rm = pbrMaterial(@"rock");
    body.materials = @[rm];
    main.geometry = body;
    main.scale = SCNVector3Make(1.0, 0.5, 0.8);
    [rock addChildNode:main];
    
    // Small detail rock
    SCNSphere *detail = [SCNSphere sphereWithRadius:0.25];
    detail.materials = @[rm];
    SCNNode *dn = [SCNNode nodeWithGeometry:detail];
    dn.position = SCNVector3Make(0.3, 0.15, 0.2);
    [rock addChildNode:dn];
    
    [rock setValue:@1 forKey:@"isObstacle"];
    return rock;
}

// ─── COIN (PBR Gold) ──────────────────────────────────────
- (SCNNode *)createCoin {
    SCNNode *coin = [SCNNode node];
    
    SCNCylinder *body = [SCNCylinder cylinderWithRadius:0.3 height:0.06];
    SCNMaterial *cm = [SCNMaterial material];
    cm.lightingModelName = SCNLightingModelPhysicallyBased;
    cm.diffuse.contents = [UIColor colorWithRed:1.0 green:0.75 blue:0.1 alpha:1.0];
    cm.roughness.contents = @0.15;
    cm.metalness.contents = @1.0;
    cm.emission.contents = [UIColor colorWithRed:0.3 green:0.2 blue:0.0 alpha:1.0];
    body.materials = @[cm];
    
    SCNNode *bn = [SCNNode nodeWithGeometry:body];
    bn.eulerAngles = SCNVector3Make(M_PI/2, 0, 0);
    [coin addChildNode:bn];
    
    // Glow ring
    SCNTorus *ring = [SCNTorus torusWithRingRadius:0.32 pipeRadius:0.02];
    SCNMaterial *rmat = [SCNMaterial material];
    rmat.lightingModelName = SCNLightingModelConstant;
    rmat.diffuse.contents = [UIColor colorWithRed:1.0 green:0.9 blue:0.2 alpha:1.0];
    rmat.emission.contents = [UIColor colorWithRed:1.0 green:0.8 blue:0.1 alpha:1.0];
    ring.materials = @[rmat];
    SCNNode *rn = [SCNNode nodeWithGeometry:ring];
    rn.eulerAngles = SCNVector3Make(M_PI/2, 0, 0);
    [coin addChildNode:rn];
    
    [coin setValue:@1 forKey:@"isCoin"];
    return coin;
}

// ─── HUD ──────────────────────────────────────────────────
- (void)setupHUD {
    _hudView = [[SKView alloc] initWithFrame:self.view.bounds];
    _hudView.backgroundColor = [UIColor clearColor];
    _hudView.allowsTransparency = YES;
    [self.view addSubview:_hudView];
    
    _hudScene = [SKScene sceneWithSize:self.view.bounds.size];
    _hudScene.scaleMode = SKSceneScaleModeResizeFill;
    [_hudView presentScene:_hudScene];
    
    CGSize s = _hudScene.size;
    float pad = 25;
    
    // Score
    _scoreLabel = [self hudLabel:@"SCORE: 0" size:28 color:[SKColor whiteColor]];
    _scoreLabel.position = CGPointMake(pad, s.height - 45);
    _scoreLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeLeft;
    [_hudScene addChild:_scoreLabel];
    
    // Coins
    _coinLabel = [self hudLabel:@"🪙 0" size:24 color:[SKColor colorWithRed:1.0 green:0.85 blue:0.2 alpha:1.0]];
    _coinLabel.position = CGPointMake(pad, s.height - 80);
    _coinLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeLeft;
    [_hudScene addChild:_coinLabel];
    
    // Speed
    _speedLabel = [self hudLabel:@"⚡ 10 m/s" size:16 color:[SKColor colorWithRed:0.6 green:0.9 blue:1.0 alpha:1.0]];
    _speedLabel.position = CGPointMake(pad, s.height - 108);
    _speedLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeLeft;
    [_hudScene addChild:_speedLabel];
    
    // Lives
    _lifeLabel = [self hudLabel:@"❤️❤️❤️" size:22 color:[SKColor redColor]];
    _lifeLabel.position = CGPointMake(s.width - pad, s.height - 45);
    _lifeLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeRight;
    [_hudScene addChild:_lifeLabel];
    
    // FPS
    _fpsLabel = [self hudLabel:@"60 FPS" size:13 color:[SKColor greenColor]];
    _fpsLabel.position = CGPointMake(s.width - pad, 22);
    _fpsLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeRight;
    [_hudScene addChild:_fpsLabel];
    
    _lastFps = CACurrentMediaTime();
}

- (SKLabelNode *)hudLabel:(NSString *)text size:(float)size color:(SKColor *)color {
    SKLabelNode *l = [SKLabelNode labelNodeWithFontNamed:@"HelveticaNeue-Bold"];
    l.text = text;
    l.fontSize = size;
    l.fontColor = color;
    return l;
}

// ─── GESTURES ─────────────────────────────────────────────
- (void)setupGestures {
    UISwipeGestureRecognizer *sl = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeLeft)];
    sl.direction = UISwipeGestureRecognizerDirectionLeft;
    [_scnView addGestureRecognizer:sl];
    
    UISwipeGestureRecognizer *sr = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeRight)];
    sr.direction = UISwipeGestureRecognizerDirectionRight;
    [_scnView addGestureRecognizer:sr];
    
    UISwipeGestureRecognizer *su = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeUp)];
    su.direction = UISwipeGestureRecognizerDirectionUp;
    [_scnView addGestureRecognizer:su];
    
    UISwipeGestureRecognizer *sd = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeDown)];
    sd.direction = UISwipeGestureRecognizerDirectionDown;
    [_scnView addGestureRecognizer:sd];
}

- (void)swipeLeft  { if (!_gameOver && _lane > -1) { _lane--; _laneX = LANE_X(_lane); } }
- (void)swipeRight { if (!_gameOver && _lane < 1)  { _lane++; _laneX = LANE_X(_lane); } }
- (void)swipeUp {
    if (!_gameOver && !_jumping && !_sliding) {
        _jumping = YES; _jumpVel = 7.5;
        [[AudioEngine shared] playJump];
    }
}
- (void)swipeDown {
    if (!_gameOver && !_jumping && !_sliding) {
        _sliding = YES; _slideTimer = 0.7;
        _playerBodyNode.scale = SCNVector3Make(1, 0.45, 1);
        _playerY = 0.45;
        [[AudioEngine shared] playSlide];
    }
}

// ═══════════════════════════════════════════════════════════
// GAME LOOP
// ═══════════════════════════════════════════════════════════
- (void)renderer:(id<SCNSceneRenderer>)renderer updateAtTime:(NSTimeInterval)time {
    if (_gameOver) return;
    
    float dt = MIN(0.05, 1.0/60.0);
    
    // FPS counter
    [self updateFPS:time];
    
    // Speed & score
    _distance += _speed * dt;
    _score = (int)_distance;
    _speed = 10.0 + _distance / 100.0;
    if (_speed > 40) _speed = 40;
    _invincibleTimer = MAX(0, _invincibleTimer - dt);
    
    // ── PLAYER MOVEMENT ──
    float cx = _playerNode.position.x;
    cx += (_laneX - cx) * MIN(1, 12 * dt);
    _playerNode.position = SCNVector3Make(cx, _playerY, 0);
    
    // Slight lean on lane change
    float leanTarget = (_laneX - cx) * 0.3;
    _playerBodyNode.eulerAngles = SCNVector3Make(0, 0, leanTarget);
    
    // Running animation — subtle bob
    float bob = sin(_distance * 3.0) * 0.08;
    if (!_jumping && !_sliding) _playerBodyNode.position = SCNVector3Make(0, bob, 0);
    
    // Jump physics
    if (_jumping) {
        _jumpVel -= 20 * dt;
        _playerY += _jumpVel * dt;
        if (_playerY <= 0.95) {
            _playerY = 0.95; _jumping = NO; _jumpVel = 0;
            _playerBodyNode.position = SCNVector3Make(0, 0, 0);
            // Impact particles
            SCNParticleSystem *impact = [ParticleSystem impactDirt];
            SCNNode *in = [SCNNode node];
            [in addParticleSystem:impact];
            in.position = SCNVector3Make(0, 0.1, 0);
            [_playerNode addChildNode:in];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [in removeFromParentNode];
            });
        }
    }
    
    // Slide timer
    if (_sliding) {
        _slideTimer -= dt;
        if (_slideTimer <= 0) {
            _sliding = NO;
            _playerBodyNode.scale = SCNVector3Make(1, 1, 1);
            _playerY = 0.95;
        }
    }
    
    // ── FOOTSTEPS ──
    _stepTimer += dt;
    if (!_jumping && !_sliding && _stepTimer > 0.35) {
        _stepTimer = 0;
        [[AudioEngine shared] playFootstep];
    }
    
    // ── ROAD SCROLLING ──
    for (SCNNode *tile in _roadTiles) {
        tile.position = SCNVector3Make(tile.position.x, tile.position.y, tile.position.z + _speed * dt);
        if (tile.position.z > TILE_LENGTH) {
            tile.position = SCNVector3Make(tile.position.x, tile.position.y, tile.position.z - NUM_TILES * TILE_LENGTH);
        }
    }
    
    // ── SPAWN TREES ──
    _nextTreeZ += _speed * dt;
    if (_nextTreeZ > 0 && _trees.count < 40) {
        _nextTreeZ = -12 - drand48() * 20;
        SCNNode *tree = [self createTree];
        int side = (drand48() < 0.5) ? -1 : 1;
        tree.position = SCNVector3Make(side * (3.0 + drand48() * 5), 0, _playerNode.position.z - 35);
        [_scnView.scene.rootNode addChildNode:tree];
        [_trees addObject:tree];
    }
    
    // Move + recycle trees
    NSMutableArray *deadTrees = [NSMutableArray array];
    for (SCNNode *t in _trees) {
        t.position = SCNVector3Make(t.position.x, t.position.y, t.position.z + _speed * dt);
        if (t.position.z > 8) [deadTrees addObject:t];
    }
    for (SCNNode *t in deadTrees) { [t removeFromParentNode]; [_trees removeObject:t]; }
    
    // ── SPAWN ROCKS ──
    _nextRockZ += _speed * dt;
    if (_nextRockZ > 0 && _rocks.count < 8) {
        _nextRockZ = -18 - drand48() * 30;
        int rlane = (int)(drand48() * 3) - 1;
        SCNNode *rock = [self createRock];
        rock.position = SCNVector3Make(LANE_X(rlane), 0.2, _playerNode.position.z - 35);
        [_scnView.scene.rootNode addChildNode:rock];
        [_rocks addObject:rock];
    }
    
    // Move rocks + collision
    NSMutableArray *deadRocks = [NSMutableArray array];
    for (SCNNode *r in _rocks) {
        r.position = SCNVector3Make(r.position.x, r.position.y, r.position.z + _speed * dt);
        if (r.position.z > 5) { [deadRocks addObject:r]; continue; }
        
        // Collision detection
        float dx = fabsf(r.position.x - _playerNode.position.x);
        float dz = fabsf(r.position.z);
        float hitThreshold = _sliding ? 0.5 : 0.7;
        
        if (dx < hitThreshold && dz < 0.6 && _invincibleTimer <= 0 && !_jumping && _playerY < 1.2) {
            _lives--;
            _invincibleTimer = 1.5;
            [[AudioEngine shared] playHit];
            
            // Impact particles at hit point
            SCNParticleSystem *hitFx = [ParticleSystem impactDirt];
            SCNNode *hn = [SCNNode node];
            [hn addParticleSystem:hitFx];
            hn.position = r.position;
            [_scnView.scene.rootNode addChildNode:hn];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [hn removeFromParentNode];
            });
            
            // Flash player red
            SCNAction *flash = [SCNAction sequence:@[
                [SCNAction fadeOpacityTo:0.3 duration:0.06],
                [SCNAction fadeOpacityTo:1.0 duration:0.06],
                [SCNAction fadeOpacityTo:0.3 duration:0.06],
                [SCNAction fadeOpacityTo:1.0 duration:0.06],
            ]];
            [_playerBodyNode runAction:flash];
            
            // Camera shake
            SCNAction *shake = [SCNAction sequence:@[
                [SCNAction moveBy:SCNVector3Make(0.15, 0.1, 0) duration:0.03],
                [SCNAction moveBy:SCNVector3Make(-0.3, -0.15, 0) duration:0.03],
                [SCNAction moveBy:SCNVector3Make(0.15, 0.05, 0) duration:0.03],
                [SCNAction moveTo:_cameraNode.position duration:0.03],
            ]];
            [_cameraNode runAction:shake];
            
            if (_lives <= 0) { [self doGameOver]; return; }
            
            // Remove rock on hit
            [r removeFromParentNode];
            [deadRocks removeObject:r];
            [_rocks removeObject:r];
        }
    }
    for (SCNNode *r in deadRocks) { [r removeFromParentNode]; [_rocks removeObject:r]; }
    
    // ── SPAWN COINS ──
    _nextCoinZ += _speed * dt;
    if (_nextCoinZ > 0 && _coinObjects.count < 12) {
        _nextCoinZ = -4 - drand48() * 10;
        int clane = (int)(drand48() * 3) - 1;
        SCNNode *coin = [self createCoin];
        coin.position = SCNVector3Make(LANE_X(clane), 1.2, _playerNode.position.z - 28);
        [_scnView.scene.rootNode addChildNode:coin];
        [_coinObjects addObject:coin];
    }
    
    // Move coins + collection
    NSMutableArray *deadCoins = [NSMutableArray array];
    for (SCNNode *c in _coinObjects) {
        c.position = SCNVector3Make(c.position.x, c.position.y, c.position.z + _speed * dt);
        c.rotation = SCNVector4Make(0, 1, 0, c.rotation.w + dt * 5);
        if (c.position.z > 5) { [deadCoins addObject:c]; continue; }
        
        float dx = fabsf(c.position.x - _playerNode.position.x);
        float dz = fabsf(c.position.z);
        if (dx < 0.7 && dz < 0.7) {
            _coins++;
            [[AudioEngine shared] playCoin];
            
            // Coin burst particles
            SCNParticleSystem *burst = [ParticleSystem coinBurst];
            SCNNode *bn = [SCNNode node];
            [bn addParticleSystem:burst];
            bn.position = c.position;
            [_scnView.scene.rootNode addChildNode:bn];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                [bn removeFromParentNode];
            });
            
            [c removeFromParentNode];
            [deadCoins removeObject:c];
            [_coinObjects removeObject:c];
        }
    }
    for (SCNNode *c in deadCoins) { [c removeFromParentNode]; [_coinObjects removeObject:c]; }
    
    // ── UPDATE HUD ──
    _scoreLabel.text = [NSString stringWithFormat:@"SCORE: %d", _score];
    _coinLabel.text = [NSString stringWithFormat:@"🪙 %d", _coins];
    _speedLabel.text = [NSString stringWithFormat:@"⚡ %.0f m/s", _speed];
    
    NSMutableString *hearts = [NSMutableString string];
    for (int i = 0; i < _lives; i++) [hearts appendString:@"❤️"];
    if (_invincibleTimer > 0 && fmod(time, 0.2) < 0.1) hearts = [NSMutableString string];
    _lifeLabel.text = hearts;
    
    // ── DUST PARTICLES ──
    _dustEmitter.hidden = _jumping;
    SCNParticleSystem *dustSys = _dustEmitter.particleSystems.firstObject;
    dustSys.birthRate = _sliding ? 60 : 25;
    dustSys.speedFactor = _sliding ? 1.5 : 0.8;
}

// ─── FPS ──────────────────────────────────────────────────
- (void)updateFPS:(NSTimeInterval)time {
    _fpsCount++;
    if (time - _lastFps >= 0.5) {
        int fps = (int)(_fpsCount / (time - _lastFps));
        _fpsLabel.text = [NSString stringWithFormat:@"%d FPS", fps];
        _fpsLabel.fontColor = fps > 50 ? [SKColor greenColor] : (fps > 30 ? [SKColor yellowColor] : [SKColor redColor]);
        _fpsCount = 0;
        _lastFps = time;
    }
}

// ─── GAME OVER ────────────────────────────────────────────
- (void)doGameOver {
    _gameOver = YES;
    [[AudioEngine shared] playDeath];
    
    // Death particles
    SCNParticleSystem *deathP = [ParticleSystem impactDirt];
    deathP.birthRate = 80;
    deathP.particleColor = [UIColor redColor];
    SCNNode *dn = [SCNNode node];
    [dn addParticleSystem:deathP];
    dn.position = SCNVector3Make(0, 0.8, 0);
    [_playerNode addChildNode:dn];
    
    // Player falls over
    SCNAction *fall = [SCNAction rotateByX:0 y:0 z:M_PI/2 duration:0.5];
    [_playerBodyNode runAction:fall];
    
    // Show game over HUD
    SKLabelNode *goLabel = [SKLabelNode labelNodeWithFontNamed:@"HelveticaNeue-Bold"];
    goLabel.text = @"GAME OVER";
    goLabel.fontSize = 42;
    goLabel.fontColor = [SKColor redColor];
    goLabel.position = CGPointMake(_hudScene.size.width/2, _hudScene.size.height/2);
    [_hudScene addChild:goLabel];
    
    SKLabelNode *restartLabel = [SKLabelNode labelNodeWithFontNamed:@"HelveticaNeue"];
    restartLabel.text = @"Tap to restart";
    restartLabel.fontSize = 20;
    restartLabel.fontColor = [SKColor whiteColor];
    restartLabel.position = CGPointMake(_hudScene.size.width/2, _hudScene.size.height/2 - 50);
    [_hudScene addChild:restartLabel];
    
    // Tap to restart
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(restartGame)];
    [_scnView addGestureRecognizer:tap];
}

- (void)restartGame {
    _lives = 3; _score = 0; _coins = 0; _distance = 0;
    _speed = 10; _lane = 0; _laneX = 0;
    _playerY = 0.95; _jumping = NO; _sliding = NO;
    _invincibleTimer = 0; _gameOver = NO;
    
    _playerNode.position = SCNVector3Make(0, 0.95, 0);
    _playerBodyNode.scale = SCNVector3Make(1, 1, 1);
    _playerBodyNode.eulerAngles = SCNVector3Make(0, 0, 0);
    _playerBodyNode.position = SCNVector3Make(0, 0, 0);
    
    // Clear world
    for (SCNNode *r in _rocks) [r removeFromParentNode];
    for (SCNNode *c in _coinObjects) [c removeFromParentNode];
    [_rocks removeAllObjects];
    [_coinObjects removeAllObjects];
    
    // Clear HUD
    [_hudScene removeAllChildren];
    [self setupHUD];
    
    // Remove tap gesture
    for (UIGestureRecognizer *g in _scnView.gestureRecognizers) {
        if ([g isKindOfClass:[UITapGestureRecognizer class]]) [_scnView removeGestureRecognizer:g];
    }
    
    _nextRockZ = -15; _nextCoinZ = -6;
}

// ─── LAYOUT ───────────────────────────────────────────────
- (void)viewDidLayoutSubviews {
    _scnView.frame = self.view.bounds;
    _hudView.frame = self.view.bounds;
    _hudScene.size = self.view.bounds.size;
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }

@end
