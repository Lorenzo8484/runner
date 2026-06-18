#import "GameViewController.h"
#import <SceneKit/SceneKit.h>
#import <SpriteKit/SpriteKit.h>

// ─── TOON SHADER (Metal) ───────────────────────────────────
static SCNProgram* makeToonProgram(void) {
    SCNProgram *p = [[SCNProgram alloc] init];
    p.vertexFunctionName = @"toonVertex";
    p.fragmentFunctionName = @"toonFragment";
    return p;
}
// Shader source is embedded as Metal library string (see build script for .metal file)
// Falls back to SCNMaterial lightingModel = .phong with toon look via shaderModifiers

static void applyToonMaterial(SCNMaterial *mat, UIColor *color) {
    mat.diffuse.contents = color;
    mat.lightingModelName = SCNLightingModelBlinn;
    // Cel banding via shader modifier
    mat.shaderModifiers = @{
        SCNShaderModifierEntryPointFragment:
        @"float NdotL = dot(_surface.normal, _light.direction);"
        @"float toon = NdotL < 0.25 ? 0.30 : (NdotL < 0.55 ? 0.60 : (NdotL < 0.80 ? 0.85 : 1.0));"
        @"float rim = pow(1.0 - abs(NdotL), 3.0) * 0.30;"
        @"_output.color.rgb *= toon;"
        @"_output.color.rgb += vec3(0.85, 0.90, 1.0) * rim;"
        @"_output.color.rgb = clamp(_output.color.rgb, 0.0, 1.0);"
    };
}

// ─── GAME ──────────────────────────────────────────────────
@implementation GameViewController {
    SCNView *_scnView;
    SKView *_hudView;
    SKScene *_hudScene;
    SCNNode *_cameraNode;
    SCNNode *_playerNode;
    SCNNode *_roadNode;
    
    // Game state
    int _lane;          // -1, 0, 1
    float _laneX;       // target X
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
    
    // Road tiles
    NSMutableArray *_roadTiles;
    NSMutableArray *_trees;
    NSMutableArray *_obstacles;
    NSMutableArray *_coins3D;
    float _nextObstacleZ;
    float _nextCoinZ;
    
    // HUD
    SKLabelNode *_scoreLabel, *_coinLabel, *_lifeLabel, *_fpsLabel;
    
    // FPS
    NSTimeInterval _lastFps;
    int _fpsCount;
    
    // Touch
    CGPoint _touchStart;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Scene
    SCNScene *scene = [SCNScene scene];
    scene.background.contents = [UIColor colorWithRed:0.45 green:0.70 blue:0.95 alpha:1.0];
    scene.fogColor = [UIColor colorWithRed:0.75 green:0.85 blue:0.95 alpha:1.0];
    scene.fogStartDistance = 60;
    scene.fogEndDistance = 120;
    
    // SCNView
    _scnView = [[SCNView alloc] initWithFrame:self.view.bounds];
    _scnView.scene = scene;
    _scnView.delegate = self;
    _scnView.antialiasingMode = SCNAntialiasingModeNone;
    _scnView.preferredFramesPerSecond = 60;
    [self.view addSubview:_scnView];
    
    // HUD
    _hudView = [[SKView alloc] initWithFrame:self.view.bounds];
    _hudView.backgroundColor = [UIColor clearColor];
    _hudView.allowsTransparency = YES;
    [self.view addSubview:_hudView];
    _hudScene = [SKScene sceneWithSize:self.view.bounds.size];
    _hudScene.scaleMode = SKSceneScaleModeResizeFill;
    [_hudView presentScene:_hudScene];
    
    // Camera: behind player
    SCNCamera *cam = [SCNCamera camera];
    cam.zNear = 0.1; cam.zFar = 200;
    cam.fieldOfView = 60;
    _cameraNode = [SCNNode node];
    _cameraNode.camera = cam;
    _cameraNode.position = SCNVector3Make(0, 6, 8);
    _cameraNode.eulerAngles = SCNVector3Make(-0.45, 0, 0);
    [scene.rootNode addChildNode:_cameraNode];
    
    // Lights
    SCNNode *sun = [SCNNode node];
    sun.light = [SCNLight light];
    sun.light.type = SCNLightTypeDirectional;
    sun.light.color = [UIColor colorWithWhite:1.0 alpha:1.0];
    sun.light.intensity = 1000;
    sun.light.castsShadow = YES;
    sun.light.shadowMapSize = CGSizeMake(1024, 1024);
    sun.light.shadowMode = SCNShadowModeForward;
    sun.position = SCNVector3Make(5, 20, -5);
    [scene.rootNode addChildNode:sun];
    
    SCNNode *amb = [SCNNode node];
    amb.light = [SCNLight light];
    amb.light.type = SCNLightTypeAmbient;
    amb.light.color = [UIColor colorWithWhite:0.4 alpha:1.0];
    amb.light.intensity = 600;
    [scene.rootNode addChildNode:amb];
    
    // ─── PLAYER (emoji style) ───
    _playerNode = [SCNNode node];
    _playerNode.position = SCNVector3Make(0, 0.8, 0);
    [scene.rootNode addChildNode:_playerNode];
    
    // Body
    SCNCapsule *body = [SCNCapsule capsuleWithCapRadius:0.4 height:1.4];
    applyToonMaterial(body.materials.firstObject, [UIColor colorWithRed:0.2 green:0.45 blue:0.85 alpha:1.0]);
    SCNNode *bodyN = [SCNNode nodeWithGeometry:body];
    bodyN.position = SCNVector3Make(0, 0.7, 0);
    [_playerNode addChildNode:bodyN];
    
    // Head (emoji yellow)
    SCNSphere *head = [SCNSphere sphereWithRadius:0.38];
    applyToonMaterial(head.materials.firstObject, [UIColor colorWithRed:0.98 green:0.85 blue:0.2 alpha:1.0]);
    SCNNode *headN = [SCNNode nodeWithGeometry:head];
    headN.position = SCNVector3Make(0, 1.7, 0);
    [_playerNode addChildNode:headN];
    
    // Eyes
    SCNSphere *eye = [SCNSphere sphereWithRadius:0.07];
    eye.materials.firstObject.diffuse.contents = [UIColor blackColor];
    SCNNode *eyeL = [SCNNode nodeWithGeometry:eye];
    eyeL.position = SCNVector3Make(-0.12, 1.75, 0.33);
    [_playerNode addChildNode:eyeL];
    SCNNode *eyeR = [SCNNode nodeWithGeometry:eye];
    eyeR.position = SCNVector3Make(0.12, 1.75, 0.33);
    [_playerNode addChildNode:eyeR];
    
    // Mouth
    SCNPlane *mouth = [SCNPlane planeWithWidth:0.18 height:0.06];
    mouth.cornerRadius = 0.03;
    mouth.materials.firstObject.diffuse.contents = [UIColor blackColor];
    SCNNode *mouthN = [SCNNode nodeWithGeometry:mouth];
    mouthN.position = SCNVector3Make(0, 1.62, 0.34);
    [_playerNode addChildNode:mouthN];
    
    // ─── INIT ───
    _lane = 0; _laneX = 0;
    _jumping = NO; _jumpVel = 0; _playerY = 0.8;
    _sliding = NO; _slideTimer = 0;
    _score = 0; _lives = 3; _coins = 0;
    _speed = 12; _distance = 0;
    _roadTiles = [NSMutableArray array];
    _trees = [NSMutableArray array];
    _obstacles = [NSMutableArray array];
    _coins3D = [NSMutableArray array];
    _nextObstacleZ = -10;
    _nextCoinZ = -5;
    
    // ─── BUILD WORLD ───
    [self createRoad];
    
    // ─── HUD ───
    CGSize s = _hudScene.size;
    _scoreLabel = [SKLabelNode labelNodeWithFontNamed:@"AvenirNext-Bold"];
    _scoreLabel.text = @"SCORE: 0";
    _scoreLabel.fontSize = 26;
    _scoreLabel.fontColor = [SKColor whiteColor];
    _scoreLabel.position = CGPointMake(20, s.height - 50);
    _scoreLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeLeft;
    [_hudScene addChild:_scoreLabel];
    
    _coinLabel = [SKLabelNode labelNodeWithFontNamed:@"AvenirNext-Bold"];
    _coinLabel.text = @"🪙 0";
    _coinLabel.fontSize = 22;
    _coinLabel.fontColor = [SKColor colorWithRed:1.0 green:0.85 blue:0.2 alpha:1.0];
    _coinLabel.position = CGPointMake(20, s.height - 80);
    _coinLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeLeft;
    [_hudScene addChild:_coinLabel];
    
    _lifeLabel = [SKLabelNode labelNodeWithFontNamed:@"AvenirNext-Bold"];
    _lifeLabel.text = @"❤️❤️❤️";
    _lifeLabel.fontSize = 22;
    _lifeLabel.fontColor = [SKColor redColor];
    _lifeLabel.position = CGPointMake(s.width - 20, s.height - 50);
    _lifeLabel.horizontalAlignmentMode = SKLabelHorizontalAlignmentModeRight;
    [_hudScene addChild:_lifeLabel];
    
    _fpsLabel = [SKLabelNode labelNodeWithFontNamed:@"Courier"];
    _fpsLabel.text = @"60 FPS";
    _fpsLabel.fontSize = 13;
    _fpsLabel.fontColor = [SKColor greenColor];
    _fpsLabel.position = CGPointMake(s.width - 40, 25);
    [_hudScene addChild:_fpsLabel];
    
    _lastFps = CACurrentMediaTime();
    
    // Swipe gestures
    UISwipeGestureRecognizer *swipeLeft = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeLeft)];
    swipeLeft.direction = UISwipeGestureRecognizerDirectionLeft;
    [_scnView addGestureRecognizer:swipeLeft];
    
    UISwipeGestureRecognizer *swipeRight = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeRight)];
    swipeRight.direction = UISwipeGestureRecognizerDirectionRight;
    [_scnView addGestureRecognizer:swipeRight];
    
    UISwipeGestureRecognizer *swipeUp = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeUp)];
    swipeUp.direction = UISwipeGestureRecognizerDirectionUp;
    [_scnView addGestureRecognizer:swipeUp];
    
    UISwipeGestureRecognizer *swipeDown = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeDown)];
    swipeDown.direction = UISwipeGestureRecognizerDirectionDown;
    [_scnView addGestureRecognizer:swipeDown];
}

// ─── WORLD GENERATION ──────────────────────────────────────
- (void)createRoad {
    SCNNode *road = [SCNNode node];
    for (int i = 0; i < 20; i++) {
        SCNBox *tile = [SCNBox boxWithWidth:5 height:0.1 length:6 chamferRadius:0];
        SCNMaterial *mat = [SCNMaterial material];
        mat.diffuse.contents = [UIColor colorWithRed:0.35 green:0.35 blue:0.38 alpha:1.0];
        // White dashes on road
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(64, 64), NO, 0);
        CGContextRef c = UIGraphicsGetCurrentContext();
        CGContextSetFillColorWithColor(c, [UIColor colorWithRed:0.35 green:0.35 blue:0.38 alpha:1.0].CGColor);
        CGContextFillRect(c, CGRectMake(0,0,64,64));
        if (i % 3 == 1) {
            CGContextSetFillColorWithColor(c, [UIColor whiteColor].CGColor);
            CGContextFillRect(c, CGRectMake(28, 10, 8, 44));
        }
        mat.diffuse.contents = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        tile.materials = @[mat];
        
        SCNNode *tn = [SCNNode nodeWithGeometry:tile];
        tn.position = SCNVector3Make(0, -0.05, -i * 6);
        [road addChildNode:tn];
        
        // Track
        [_roadTiles addObject:tn];
    }
    [_scnView.scene.rootNode addChildNode:road];
    _roadNode = road;
    
    // Grass sides
    for (int side = -1; side <= 1; side += 2) {
        SCNBox *grass = [SCNBox boxWithWidth:8 height:0.05 length:120 chamferRadius:0];
        SCNMaterial *gm = [SCNMaterial material];
        gm.diffuse.contents = [UIColor colorWithRed:0.22 green:0.55 blue:0.18 alpha:1.0];
        grass.materials = @[gm];
        SCNNode *gn = [SCNNode nodeWithGeometry:grass];
        gn.position = SCNVector3Make(side * 6.5, -0.02, -60);
        [_scnView.scene.rootNode addChildNode:gn];
    }
}

- (SCNNode *)makeTree {
    SCNNode *tree = [SCNNode node];
    
    SCNCylinder *trunk = [SCNCylinder cylinderWithRadius:0.2 height:3];
    applyToonMaterial(trunk.materials.firstObject, [UIColor colorWithRed:0.45 green:0.28 blue:0.12 alpha:1.0]);
    SCNNode *trunkN = [SCNNode nodeWithGeometry:trunk];
    trunkN.position = SCNVector3Make(0, 1.5, 0);
    [tree addChildNode:trunkN];
    
    // Triple crown (cartoon tree)
    for (int i = -1; i <= 1; i++) {
        SCNSphere *crown = [SCNSphere sphereWithRadius:0.9];
        applyToonMaterial(crown.materials.firstObject, [UIColor colorWithRed:0.12 green:0.65 blue:0.18 alpha:1.0]);
        SCNNode *cn = [SCNNode nodeWithGeometry:crown];
        cn.position = SCNVector3Make(i * 0.7, 3.2 + fabs(i)*0.6, 0);
        cn.scale = SCNVector3Make(1, 0.7, 1);
        [tree addChildNode:cn];
    }
    
    return tree;
}

- (SCNNode *)makeRock {
    SCNNode *rock = [SCNNode node];
    SCNBox *b = [SCNBox boxWithWidth:0.8 height:0.6 length:0.8 chamferRadius:0.2];
    applyToonMaterial(b.materials.firstObject, [UIColor colorWithRed:0.45 green:0.42 blue:0.38 alpha:1.0]);
    SCNNode *rn = [SCNNode nodeWithGeometry:b];
    rn.position = SCNVector3Make(0, 0.3, 0);
    [rock addChildNode:rn];
    return rock;
}

- (SCNNode *)makeCoin {
    SCNNode *coin = [SCNNode node];
    SCNCylinder *c = [SCNCylinder cylinderWithRadius:0.25 height:0.08];
    SCNMaterial *mat = [SCNMaterial material];
    mat.diffuse.contents = [UIColor colorWithRed:1.0 green:0.85 blue:0.1 alpha:1.0];
    mat.emission.contents = [UIColor colorWithRed:0.8 green:0.6 blue:0.0 alpha:1.0];
    mat.metalness.contents = @1.0;
    mat.roughness.contents = @0.2;
    c.materials = @[mat];
    SCNNode *cn = [SCNNode nodeWithGeometry:c];
    cn.eulerAngles = SCNVector3Make(0, 0, M_PI/2);
    cn.position = SCNVector3Make(0, 1.2, 0);
    [coin addChildNode:cn];
    return coin;
}

// ─── CONTROLS ──────────────────────────────────────────────
- (void)swipeLeft {
    if (_lane > -1) { _lane--; _laneX = _lane * 2.0; }
}

- (void)swipeRight {
    if (_lane < 1) { _lane++; _laneX = _lane * 2.0; }
}

- (void)swipeUp {
    if (!_jumping && !_sliding) {
        _jumping = YES;
        _jumpVel = 8.0;
    }
}

- (void)swipeDown {
    if (!_jumping && !_sliding) {
        _sliding = YES;
        _slideTimer = 0.6;
        _playerNode.scale = SCNVector3Make(1, 0.5, 1);
        _playerY = 0.4;
    }
}

// ─── GAME LOOP ─────────────────────────────────────────────
- (void)renderer:(id<SCNSceneRenderer>)renderer updateAtTime:(NSTimeInterval)time {
    float dt = 1.0/60.0;
    
    // FPS
    _fpsCount++;
    if (time - _lastFps >= 0.5) {
        int fps = (int)(_fpsCount / (time - _lastFps));
        _fpsLabel.text = [NSString stringWithFormat:@"%d FPS", fps];
        _fpsCount = 0;
        _lastFps = time;
    }
    
    _distance += _speed * dt;
    _score = (int)(_distance / 2);
    _speed = 12 + _distance / 80; // gradually speed up
    
    // Player position
    float targetX = _laneX;
    float cx = _playerNode.position.x;
    cx += (targetX - cx) * MIN(1, 10 * dt);
    _playerNode.position = SCNVector3Make(cx, _playerY, _playerNode.position.z);
    
    // Jump
    if (_jumping) {
        _jumpVel -= 20 * dt;
        _playerY += _jumpVel * dt;
        if (_playerY <= 0.8) {
            _playerY = 0.8;
            _jumping = NO;
            _jumpVel = 0;
        }
    }
    
    // Slide
    if (_sliding) {
        _slideTimer -= dt;
        if (_slideTimer <= 0) {
            _sliding = NO;
            _playerNode.scale = SCNVector3Make(1, 1, 1);
            _playerY = 0.8;
        }
    }
    
    // Move road tiles
    for (SCNNode *tile in _roadTiles) {
        tile.position = SCNVector3Make(tile.position.x, tile.position.y, tile.position.z + _speed * dt);
        if (tile.position.z > 6) {
            tile.position = SCNVector3Make(tile.position.x, tile.position.y, tile.position.z - 20*6);
        }
    }
    
    // Spawn trees
    if (_trees.count < 30) {
        SCNNode *t = [self makeTree];
        float z = _playerNode.position.z - 20 - drand48() * 40;
        int side = (drand48() < 0.5) ? -1 : 1;
        t.position = SCNVector3Make(side * (3.5 + drand48() * 3), 0, z);
        [_scnView.scene.rootNode addChildNode:t];
        [_trees addObject:t];
    }
    
    // Move/remove trees
    NSMutableArray *deadTrees = [NSMutableArray array];
    for (SCNNode *t in _trees) {
        t.position = SCNVector3Make(t.position.x, t.position.y, t.position.z + _speed * dt);
        if (t.position.z > 8) [deadTrees addObject:t];
    }
    for (SCNNode *t in deadTrees) {
        [t removeFromParentNode];
        [_trees removeObject:t];
    }
    
    // Spawn obstacles
    _nextObstacleZ += _speed * dt;
    if (_nextObstacleZ > 0 && _obstacles.count < 10) {
        _nextObstacleZ = -15 - drand48() * 25;
        float laneX = (int)(drand48() * 3 - 1) * 2.0;
        SCNNode *rock = [self makeRock];
        rock.position = SCNVector3Make(laneX, 0, _playerNode.position.z - 30);
        [_scnView.scene.rootNode addChildNode:rock];
        [_obstacles addObject:rock];
    }
    
    // Move/remove obstacles + collision
    NSMutableArray *deadObs = [NSMutableArray array];
    for (SCNNode *o in _obstacles) {
        o.position = SCNVector3Make(o.position.x, o.position.y, o.position.z + _speed * dt);
        if (o.position.z > 5) [deadObs addObject:o];
        
        // Collision check
        float dx = o.position.x - _playerNode.position.x;
        float dz = o.position.z - _playerNode.position.z;
        if (fabs(dx) < 0.6 && fabs(dz) < 0.6 && _playerY < 1.0) {
            // Hit!
            _lives--;
            [o removeFromParentNode];
            [deadObs removeObject:o];
            [_obstacles removeObject:o];
            // Flash player red
            SCNAction *flash = [SCNAction sequence:@[
                [SCNAction fadeOpacityTo:0.3 duration:0.05],
                [SCNAction fadeOpacityTo:1.0 duration:0.05],
                [SCNAction fadeOpacityTo:0.3 duration:0.05],
                [SCNAction fadeOpacityTo:1.0 duration:0.05]
            ]];
            [_playerNode runAction:flash];
            
            if (_lives <= 0) [self gameOver];
        }
    }
    for (SCNNode *o in deadObs) {
        [o removeFromParentNode];
        [_obstacles removeObject:o];
    }
    
    // Spawn coins
    _nextCoinZ += _speed * dt;
    if (_nextCoinZ > 0 && _coins3D.count < 15) {
        _nextCoinZ = -3 - drand48() * 8;
        float lx = (int)(drand48() * 3 - 1) * 2.0;
        SCNNode *coin = [self makeCoin];
        coin.position = SCNVector3Make(lx, 0, _playerNode.position.z - 25);
        [_scnView.scene.rootNode addChildNode:coin];
        [_coins3D addObject:coin];
    }
    
    // Move/collect coins
    NSMutableArray *deadCoins = [NSMutableArray array];
    for (SCNNode *c in _coins3D) {
        c.position = SCNVector3Make(c.position.x, c.position.y, c.position.z + _speed * dt);
        c.rotation = SCNVector4Make(0, 1, 0, c.rotation.w + dt * 4);
        if (c.position.z > 5) [deadCoins addObject:c];
        
        float dx = c.position.x - _playerNode.position.x;
        float dz = c.position.z - _playerNode.position.z;
        if (fabs(dx) < 0.7 && fabs(dz) < 0.7) {
            _coins++;
            [c removeFromParentNode];
            [deadCoins removeObject:c];
            [_coins3D removeObject:c];
        }
    }
    for (SCNNode *c in deadCoins) {
        [c removeFromParentNode];
        [_coins3D removeObject:c];
    }
    
    // Update HUD
    _scoreLabel.text = [NSString stringWithFormat:@"SCORE: %d", _score];
    _coinLabel.text = [NSString stringWithFormat:@"🪙 %d", _coins];
    NSString *hearts = @"";
    for (int i = 0; i < _lives; i++) hearts = [hearts stringByAppendingString:@"❤️"];
    _lifeLabel.text = hearts;
}

- (void)gameOver {
    _lives = 3;
    _score = 0;
    _coins = 0;
    _distance = 0;
    _speed = 12;
    _lane = 0; _laneX = 0;
    _playerY = 0.8;
    
    // Clear world
    for (SCNNode *o in _obstacles) [o removeFromParentNode];
    [_obstacles removeAllObjects];
    for (SCNNode *c in _coins3D) [c removeFromParentNode];
    [_coins3D removeAllObjects];
    
    _playerNode.position = SCNVector3Make(0, 0.8, 0);
}

- (void)viewDidLayoutSubviews {
    _scnView.frame = self.view.bounds;
    _hudView.frame = self.view.bounds;
    _hudScene.size = self.view.bounds.size;
}
@end
