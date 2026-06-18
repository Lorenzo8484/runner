#import <SceneKit/SceneKit.h>
#import <UIKit/UIKit.h>
#import "GLTFLoader.h"
#import "AudioEngine.h"
#import "ParticleSystem.h"

// Version string for verification
static const char __attribute__((used)) _game_version[] = "JungleRunner_v14.1";

// ─── Game Constants ──────────────────────────
#define LANE_W 2.5f
#define LX(l) ((l)*LANE_W)
#define RW (LANE_W*3.6f)
#define TL 8.0f
#define NT 30
#define SHADOW_SZ 2048
#define MAX_LIVES 5

// ─── State Machine ───────────────────────────
typedef NS_ENUM(NSInteger, GameState) {
    GameStateHome,
    GameStatePlaying,
    GameStateGameOver
};

// ─── Camera Mode ────────────────────────────
typedef NS_ENUM(NSInteger, ViewMode) {
    ViewModeBack,
    ViewModeFPS,
    ViewModeFront
};

// ─── LOG Macro ───────────────────────────────
#define LOG(fmt,...) [_lbuf appendFormat:@"[%.0f] " fmt @"\n",_dist,##__VA_ARGS__]; if(_logVis){_ltv.text=_lbuf;[_ltv scrollRangeToVisible:NSMakeRange(_lbuf.length-1,0)];}

// ═══════════════════════════════════════════════
// MARK: - PBR Material Helper
// ═══════════════════════════════════════════════
static SCNMaterial *pbr(NSString *s){
    SCNMaterial *m=[SCNMaterial material];m.lightingModelName=SCNLightingModelPhysicallyBased;
    NSString *b=[NSString stringWithFormat:@"Assets/%@",s];NSBundle *bu=[NSBundle mainBundle];
    m.diffuse.contents=[UIImage imageWithContentsOfFile:[bu pathForResource:[b stringByAppendingString:@"/diff.jpg"] ofType:nil]];
    m.roughness.contents=[UIImage imageWithContentsOfFile:[bu pathForResource:[b stringByAppendingString:@"/rough.jpg"] ofType:nil]];
    m.normal.contents=[UIImage imageWithContentsOfFile:[bu pathForResource:[b stringByAppendingString:@"/normal.jpg"] ofType:nil]];
    NSString *ao=[bu pathForResource:[b stringByAppendingString:@"/ao.jpg"] ofType:nil];
    if(ao)m.ambientOcclusion.contents=[UIImage imageWithContentsOfFile:ao];
    m.diffuse.wrapS=SCNWrapModeRepeat;m.diffuse.wrapT=SCNWrapModeRepeat;
    m.roughness.wrapS=SCNWrapModeRepeat;m.roughness.wrapT=SCNWrapModeRepeat;
    m.normal.wrapS=SCNWrapModeRepeat;m.normal.wrapT=SCNWrapModeRepeat;
    m.metalness.contents=@0.0;return m;
}

// ═══════════════════════════════════════════════
// MARK: - Glass Pill (EXACT match of .pillFx from original CSS)
// ═══════════════════════════════════════════════
static UIView *glassPill(CGRect frame){
    UIView *ev=[[UIView alloc]initWithFrame:frame];
    ev.layer.cornerRadius=frame.size.height/2;ev.layer.masksToBounds=YES;
    // Gradient: linear-gradient(180deg, rgba(60,90,140,.28), rgba(12,16,26,.64))
    CAGradientLayer *grad=[CAGradientLayer layer];grad.frame=ev.bounds;
    grad.colors=@[(id)[UIColor colorWithRed:0.235 green:0.353 blue:0.549 alpha:0.28].CGColor,
                   (id)[UIColor colorWithRed:0.047 green:0.063 blue:0.102 alpha:0.64].CGColor];
    grad.cornerRadius=frame.size.height/2;[ev.layer insertSublayer:grad atIndex:0];
    // Border: 1px solid rgba(170,210,255,.22)
    ev.layer.borderWidth=0.5;ev.layer.borderColor=[UIColor colorWithRed:0.667 green:0.824 blue:1.0 alpha:0.22].CGColor;
    return ev;
}

static UIView *glassPillShadow(CGRect frame){
    UIView *ev=glassPill(frame);
    ev.layer.shadowColor=[UIColor blackColor].CGColor;ev.layer.shadowOffset=CGSizeMake(0,7);ev.layer.shadowRadius=22;ev.layer.shadowOpacity=0.50;
    ev.layer.masksToBounds=NO;
    // Inner highlight (::before)
    UIView *inner=[[UIView alloc]initWithFrame:CGRectMake(0,0,frame.size.width,frame.size.height/2)];
    inner.backgroundColor=[UIColor colorWithWhite:1 alpha:0.07];inner.layer.cornerRadius=frame.size.height/2;
    inner.userInteractionEnabled=NO;[ev addSubview:inner];
    return ev;
}

// ═══════════════════════════════════════════════
// MARK: - HUD Scale Helper
// ═══════════════════════════════════════════════
static inline CGFloat hs(void){return 1.40;} // hudScale
static inline CGFloat ms(void){return 1.50;} // menuScale
static inline CGFloat hw(void){return 0.70;} // hudW
static inline CGFloat ph(void){return 12*hs();} // pillHeight
static inline CGFloat gap(void){return 6*hs();} // gap

@interface GameViewController : UIViewController <SCNSceneRendererDelegate>
@end

@implementation GameViewController {
    // SceneKit
    SCNView *_sv; SCNScene *_sc;
    SCNNode *_camNode, *_playerNode, *_modelNode, *_roadContainer;
    SCNNode *_sunNode, *_ambientNode;

    // Player
    int _lane; float _targetX; BOOL _jumping; float _jumpVel, _playerY; BOOL _sliding; float _slideTimer;
    SCNNode *_ai,*_ahi,*_awi,*_ar,*_afi,*_aj,*_as,*_ad,*_asp,*_ama,*_atu,*_ada;
    NSString *_currentAnim;

    // State
    GameState _state; ViewMode _viewMode;
    int _score, _lives, _coins, _rings; float _speed, _dist;
    float _invTimer, _boostTimer; BOOL _hasBoost, _hasMagnet; int _bullets; float _speedBoost;
    float _foodBoostT, _magnetT; int _foodCount, _foodBoostCharges;
    NSMutableArray *_foodHistory;
    BOOL _stopped, _paused, _over;

    // Object pools
    NSMutableArray *_roadTiles,*_trees,*_rocks,*_coinObjs,*_turtles,*_ringObjs,*_heartObjs,*_projectiles;
    float _nextTreeZ,_nextRockZ,_nextCoinZ,_nextTurtleZ,_nextRingZ,_nextHeartZ;

    // Monkey car
    SCNNode *_carNode; float _carZ; BOOL _carActive;

    // Visual FX
    SCNNode *_dustTrail; SCNParticleSystem *_dustPS;
    int _hitCount; // Combo hits for shake intensity

    // Tree/Rock names for random spawn
    NSArray *_treeNames,*_rockNames;

    // Timing
    NSTimeInterval _lastTime; float _stepTimer; int _frameCount; float _lastFPSTime;

    // ═══════════ HUD (original layout) ═══════════
    UIView *_hudWrap;
    // Score pill (half)
    UIView *_scorePill; UILabel *_scoreVal;
    // Emoji/Coins pill (half)
    UIView *_coinPill; UILabel *_coinVal;
    // Rings pill (half)
    UIView *_ringPill; UILabel *_ringVal, *_ringsLabel;
    // Lives pill (half)
    UIView *_lifePill; UILabel *_lifeVal;
    // Magnete pill (full)
    UIView *_magPill; UILabel *_magTxt; UIView *_magBarFill;
    // Cibo Boost pill (full)
    UIView *_foodBoostPill; UILabel *_foodBoostTime; UIView *_foodBarFill;
    // Boost pill (full)
    UIView *_boostPill; UILabel *_boostIcon, *_boostName, *_boostTime; UIView *_boostBarFill;
    // Debug button
    UIButton *_debugBtn;
    // Best score (hidden)
    UILabel *_bestLbl;

    // ═══════════ Top-Right ═══════════
    UIView *_topRightPill;
    UIButton *_homeBtn, *_settingsBtn;

    // ═══════════ Camera Segment ═══════════
    UIView *_camSegPill; UIView *_camThumb; UILabel *_camBackLbl, *_camFPSLbl, *_camFrontLbl;

    // ═══════════ Right Stack ═══════════
    UIView *_rightStack;
    // Bullets row
    UIView *_bulletsRow; UIButton *_bulletsCountBtn, *_bulletsBtn; UILabel *_bulletsCountLbl, *_bulletsLabel;
    // Boost row
    UIView *_boostRow; UIButton *_boostCountBtn, *_foodBoostBtn; UILabel *_boostCountLbl, *_foodBoostLabel;
    // AVVIA/RESTART/STOP
    UIButton *_mainBtn; UILabel *_mainLbl;
    // DANCE
    UIButton *_danceBtn; UILabel *_danceLbl;

    // ═══════════ Right Column (Food) ═══════════
    UIView *_rightCol, *_foodCountPill, *_foodStack;
    UILabel *_foodCountLbl;

    // ═══════════ Settings Overlay ═══════════
    UIView *_settingsOverlay, *_settingsPanel;
    UIButton *_closeSettingsBtn;
    UIButton *_tabCam, *_tabVisual, *_tabAudio;
    // Camera tab
    UIView *_camCard, *_visualCard, *_audioCard;
    UIButton *_camProfFrontBtn, *_camProfBackBtn;
    UISlider *_fovSlider, *_camDistSlider, *_camYSlider, *_frameSlider;
    UILabel *_fovValLbl, *_camDistValLbl, *_camYValLbl, *_frameValLbl;
    // Visual tab
    UIButton *_fpsRealBtn, *_fpsStableBtn;
    UISwitch *_motionSwitch, *_dynFovSwitch, *_shakeSwitch;
    UILabel *_motionLbl, *_dynFovLbl, *_shakeLbl;
    // Audio tab
    UISwitch *_audioSwitch;
    UIButton *_resetBtn;

    // Settings state
    BOOL _fpsRealistic, _motionBlurOn, _dynFovOn, _cameraShakeOn, _audioOn;

    // ═══════════ Debug Panel ═══════════
    UIView *_debugPanel;
    UILabel *_dbgFps, *_dbgCam, *_dbgState, *_dbgEnt, *_dbgLane, *_dbgBoosts;

    // ═══════════ Home Camera ═══════════
    struct { BOOL active, intro; float t, angle, radius, height, targetOffX, targetOffY; } _homeCam;
    float _homeOrbitAngle, _homeOrbitRadius, _homeOrbitHeight;

    // LOG
    NSMutableString *_lbuf; UIView *_logOverlay; UITextView *_ltv; BOOL _logVis;

    // Audio
    AudioEngine *_audio;
}

// ═══════════════════════════════════════════════
// MARK: - Scene Sky (Procedural Gradient)
// ═══════════════════════════════════════════════
-(UIImage*)generateSky{
    int h=256;CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();
    size_t bpr=h*4;uint8_t *d=(uint8_t*)malloc(h*bpr);
    for(int y=0;y<h;y++){float t=y/(float)h;
        for(int x=0;x<h;x++){int i=(y*h+x)*4;
            d[i]=(uint8_t)((0.35+t*0.3)*255);d[i+1]=(uint8_t)((0.55+t*0.25)*255);
            d[i+2]=(uint8_t)((0.75+t*0.2)*255);d[i+3]=255;
        }
    }
    CGContextRef ctx=CGBitmapContextCreate(d,h,h,8,bpr,cs,kCGImageAlphaPremultipliedLast);
    CGImageRef img=CGBitmapContextCreateImage(ctx);UIImage*ui=[UIImage imageWithCGImage:img];
    CGImageRelease(img);CGContextRelease(ctx);CGColorSpaceRelease(cs);free(d);return ui;
}

// ═══════════════════════════════════════════════
// MARK: - Screen Shake (Camera)
// ═══════════════════════════════════════════════
-(void)shakeScreen:(float)intensity{
    if(!_cameraShakeOn)return;
    [_camNode removeAllActions];
    SCNAction *s=[SCNAction sequence:@[
        [SCNAction moveBy:SCNVector3Make(intensity,0,0) duration:0.015],
        [SCNAction moveBy:SCNVector3Make(-intensity*1.5,0,0) duration:0.02],
        [SCNAction moveBy:SCNVector3Make(intensity*1.2,0,0) duration:0.015],
        [SCNAction moveBy:SCNVector3Make(-intensity*0.8,0,0) duration:0.02],
        [SCNAction moveTo:SCNVector3Make(0,5.5,7) duration:0.01]]];
    [_camNode runAction:s];
}

// ═══════════════════════════════════════════════
// MARK: - Safe Dispatch
// ═══════════════════════════════════════════════
-(void)safeAfter:(float)sec block:(void(^)(void))block{
    __weak __typeof__(self) ws=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,sec*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        __strong __typeof__(ws) ss=ws;if(ss)block();
    });
}

// ═══════════════════════════════════════════════
// MARK: - Pill Label Helper
// ═══════════════════════════════════════════════
-(UILabel*)pillLabel:(CGRect)frame text:(NSString*)t{
    UILabel*l=[[UILabel alloc]initWithFrame:frame];
    l.text=t;l.textColor=[UIColor colorWithRed:0.92 green:0.95 blue:1 alpha:1];
    l.font=[UIFont systemFontOfSize:8*hs() weight:UIFontWeightBlack];
    l.adjustsFontSizeToFitWidth=YES;l.minimumScaleFactor=0.5;
    return l;
}

-(UILabel*)hudTitleLabel:(CGRect)frame text:(NSString*)t{
    UILabel*l=[[UILabel alloc]initWithFrame:frame];
    l.text=t;l.textColor=[UIColor colorWithRed:0.85 green:0.9 blue:1 alpha:0.9];
    l.font=[UIFont systemFontOfSize:7*hs() weight:UIFontWeightBlack];
    l.lineBreakMode=NSLineBreakByClipping;
    return l;
}

-(UILabel*)hudValueLabel:(CGRect)frame{
    UILabel*l=[[UILabel alloc]initWithFrame:frame];
    l.textColor=[UIColor colorWithRed:0.92 green:0.95 blue:1 alpha:1];
    l.font=[UIFont systemFontOfSize:8*hs() weight:UIFontWeightBlack];
    l.textAlignment=NSTextAlignmentRight;
    return l;
}

// ═══════════════════════════════════════════════
// MARK: - HUD Pill Builder
// ═══════════════════════════════════════════════
-(UIView*)hudPillFull:(CGRect)frame icon:(NSString*)icon label:(NSString*)label valRef:(UILabel**)valRef{
    UIView*p=glassPill(frame);p.layer.shadowColor=[UIColor blackColor].CGColor;p.layer.shadowOffset=CGSizeMake(0,7);p.layer.shadowRadius=22;p.layer.shadowOpacity=0.5;p.layer.masksToBounds=NO;
    UIView*inner=[[UIView alloc]initWithFrame:CGRectMake(0,0,frame.size.width,frame.size.height/2)];
    inner.backgroundColor=[UIColor colorWithWhite:1 alpha:0.07];inner.layer.cornerRadius=frame.size.height/2;inner.userInteractionEnabled=NO;[p addSubview:inner];
    CGFloat pady=4*hs(),padx=6*hs();
    UILabel*il=nil;
    if(icon.length){
        il=[[UILabel alloc]initWithFrame:CGRectMake(padx,pady,11*hs(),11*hs())];
        il.text=icon;il.font=[UIFont systemFontOfSize:11*hs()];il.textAlignment=NSTextAlignmentCenter;[p addSubview:il];
    }
    CGFloat lx=icon.length?padx+11*hs()+5*hs():padx;
    CGFloat vw=frame.size.width-lx-padx-40;
    UILabel*ll=[self hudTitleLabel:CGRectMake(lx,pady,vw,frame.size.height-2*pady) text:label];[p addSubview:ll];
    UILabel*vl=[self hudValueLabel:CGRectMake(frame.size.width-padx-38,pady,38,frame.size.height-2*pady)];[p addSubview:vl];
    if(valRef)*valRef=vl;
    return p;
}

-(UIView*)hudPillHalf:(CGRect)frame icon:(NSString*)icon label:(NSString*)label valRef:(UILabel**)valRef{
    return [self hudPillFull:frame icon:icon label:label valRef:valRef];
}

-(UIView*)hudPillLife:(CGRect)frame{
    UIView*p=glassPill(frame);p.layer.shadowColor=[UIColor blackColor].CGColor;p.layer.shadowOffset=CGSizeMake(0,7);p.layer.shadowRadius=22;p.layer.shadowOpacity=0.5;p.layer.masksToBounds=NO;
    UILabel*hl=[[UILabel alloc]initWithFrame:CGRectMake(4,4,frame.size.width-8,frame.size.height-8)];
    hl.text=@"❤️❤️❤️";hl.textAlignment=NSTextAlignmentCenter;hl.font=[UIFont systemFontOfSize:8*hs()];hl.textColor=[UIColor whiteColor];hl.adjustsFontSizeToFitWidth=YES;
    _lifeVal=hl;[p addSubview:hl];
    return p;
}

// ═══════════════════════════════════════════════
// MARK: - Bar Pill
// ═══════════════════════════════════════════════
-(UIView*)hudBarPill:(CGRect)frame icon:(NSString*)icon label:(NSString*)label valRef:(UILabel**)valRef fillRef:(UIView**)fillRef{
    UIView*p=glassPill(frame);p.layer.shadowColor=[UIColor blackColor].CGColor;p.layer.shadowOffset=CGSizeMake(0,7);p.layer.shadowRadius=22;p.layer.shadowOpacity=0.5;p.layer.masksToBounds=NO;
    UIView*inner=[[UIView alloc]initWithFrame:CGRectMake(0,0,frame.size.width,frame.size.height/2)];
    inner.backgroundColor=[UIColor colorWithWhite:1 alpha:0.07];inner.layer.cornerRadius=frame.size.height/2;inner.userInteractionEnabled=NO;[p addSubview:inner];
    CGFloat pady=4*hs(),padx=6*hs();
    // Icon
    UILabel*il=[[UILabel alloc]initWithFrame:CGRectMake(padx,pady,11*hs(),11*hs())];
    il.text=icon;il.font=[UIFont systemFontOfSize:11*hs()];il.textAlignment=NSTextAlignmentCenter;[p addSubview:il];
    // Label
    CGFloat lx=padx+11*hs()+5*hs();
    UILabel*ll=[self hudTitleLabel:CGRectMake(lx,pady,40,frame.size.height-2*pady) text:label];[p addSubview:ll];
    // Bar background
    CGFloat bw=60*hs()*hw(),bx=lx+40+5*hs();
    UIView*barBg=[[UIView alloc]initWithFrame:CGRectMake(bx,pady+frame.size.height/2-1.5*hs(),bw,3*hs())];
    barBg.backgroundColor=[UIColor colorWithWhite:1 alpha:0.12];barBg.layer.cornerRadius=1.5*hs();[p addSubview:barBg];
    // Bar fill
    UIView*fill=[[UIView alloc]initWithFrame:CGRectMake(0,0,0,3*hs())];
    fill.backgroundColor=[UIColor colorWithRed:0.78 green:0.85 blue:1 alpha:0.88];fill.layer.cornerRadius=1.5*hs();[barBg addSubview:fill];
    if(fillRef)*fillRef=fill;
    // Value
    UILabel*vl=[self hudValueLabel:CGRectMake(frame.size.width-padx-38,pady,38,frame.size.height-2*pady)];[p addSubview:vl];
    if(valRef)*valRef=vl;
    return p;
}

// ═══════════════════════════════════════════════
// MARK: - Lifecycle
// ═══════════════════════════════════════════════
-(void)viewDidLoad{[super viewDidLoad];
    _lbuf=[NSMutableString string];LOG(@"🏁 Jungle Runner v14.1 — Fixed camera+textures+ground");
    _audio=[AudioEngine shared];

    // Settings defaults (match original)
    _viewMode=ViewModeBack; _fpsRealistic=YES; _motionBlurOn=NO; _dynFovOn=YES; _cameraShakeOn=YES; _audioOn=YES;

    [self setupScene];
    [self setupLights];
    [self setupCamera];
    [self setupPlayer];
    [self setupRoad];
    [self setupHUD];
    [self setupTopRight];
    [self setupCameraSegment];
    [self setupRightStack];
    [self setupRightCol];
    [self setupSettingsPanel];
    [self setupDebugPanel];
    [self setupGestures];
    [self setupLog];
    [self setupHomeCam];

    [self initState];
    [self applyViewMode:(ViewMode)_viewMode];
    _state=GameStateHome;
    _homeCam.active=YES;_homeCam.intro=NO;_homeCam.t=0;
    _stopped=YES;
    [self updateMainButton];
    LOG(@"📋 Home screen — tap PLAY");
    [self safeAfter:0.5 block:^{[_audio startAmbient];}];
}

-(void)initState{
    _lane=0;_targetX=0;_jumping=NO;_jumpVel=0;_playerY=1;_sliding=NO;_slideTimer=0;
    _score=0;_lives=3;_coins=0;_rings=0;_speed=10;_dist=0;
    _invTimer=0;_boostTimer=0;_hasBoost=NO;_hasMagnet=NO;_bullets=5;_speedBoost=0;
    _foodBoostT=0;_magnetT=0;_foodCount=0;_foodBoostCharges=5;
    _foodHistory=[NSMutableArray array];
    _lastTime=0;_stepTimer=0;_frameCount=0;
    _over=NO;_stopped=YES;_paused=NO;

    _trees=[NSMutableArray array];_rocks=[NSMutableArray array];
    _coinObjs=[NSMutableArray array];_turtles=[NSMutableArray array];
    _ringObjs=[NSMutableArray array];_heartObjs=[NSMutableArray array];
    _projectiles=[NSMutableArray array];

    _nextTreeZ=-15;_nextRockZ=-18;_nextCoinZ=-4;_nextTurtleZ=-35;_nextRingZ=-8;_nextHeartZ=-50;
    _carActive=NO;_hitCount=0;
    _treeNames=@[@"tree_default",@"tree_detailed",@"tree_oak",@"tree_fat",@"tree_cone",@"tree_tall",@"tree_small",@"tree_thin",@"tree_simple",@"tree_blocks",@"tree_pineDefaultA",@"tree_pineDefaultB",@"tree_pineTallA",@"tree_pineTallC",@"tree_pineRoundA",@"tree_pineRoundC",@"tree_pineSmallA",@"tree_pineSmallC",@"tree_palmDetailedShort",@"tree_palmDetailedTall"];
    _rockNames=@[@"cliff_rock",@"cliff_large_rock",@"cliff_half_rock",@"cliff_corner_rock",@"cliff_block_rock"];
}

// ═══════════════════════════════════════════════
// MARK: - Scene Setup
// ═══════════════════════════════════════════════
-(void)setupScene{
    _sc=[SCNScene scene];
    _sc.background.contents=[self generateSky];
    _sc.fogColor=[UIColor colorWithRed:0.6 green:0.7 blue:0.8 alpha:1];
    _sc.fogStartDistance=50;_sc.fogEndDistance=200;

    _sv=[[SCNView alloc]initWithFrame:self.view.bounds];
    _sv.scene=_sc;_sv.delegate=self;
    _sv.preferredFramesPerSecond=60;
    _sv.antialiasingMode=SCNAntialiasingModeMultisampling4X;
    [self.view addSubview:_sv];
    // Ground — use large plane for proper PBR UVs
    SCNPlane *gp = [SCNPlane planeWithWidth:300 height:300];
    gp.materials = @[pbr(@"ground")];
    SCNNode *fn = [SCNNode nodeWithGeometry:gp];
    fn.eulerAngles = SCNVector3Make(-M_PI_2, 0, 0);
    fn.position = SCNVector3Make(0, -0.2, -80);
    [_sc.rootNode addChildNode:fn];
}

// ═══════════════════════════════════════════════
// MARK: - Lighting
// ═══════════════════════════════════════════════
-(void)setupLights{
    SCNLight *sun=[SCNLight light];
    sun.type=SCNLightTypeDirectional;
    sun.color=[UIColor colorWithRed:1 green:0.95 blue:0.85 alpha:1];
    sun.intensity=1200;sun.temperature=5500;
    sun.castsShadow=YES;sun.shadowRadius=2;
    sun.shadowMapSize=CGSizeMake(SHADOW_SZ,SHADOW_SZ);
    sun.shadowMode=SCNShadowModeForward;
    sun.orthographicScale=30;
    _sunNode=[SCNNode node];_sunNode.light=sun;
    _sunNode.position=SCNVector3Make(8,25,-10);
    [_sc.rootNode addChildNode:_sunNode];

    SCNLight *amb=[SCNLight light];
    amb.type=SCNLightTypeAmbient;
    amb.color=[UIColor colorWithRed:0.45 green:0.55 blue:0.7 alpha:1];
    amb.intensity=400;
    _ambientNode=[SCNNode node];_ambientNode.light=amb;
    [_sc.rootNode addChildNode:_ambientNode];
}

// ═══════════════════════════════════════════════
// MARK: - Camera
// ═══════════════════════════════════════════════
-(void)setupCamera{
    SCNCamera *c=[SCNCamera camera];
    c.zNear=0.2;c.zFar=300;c.fieldOfView=65;
    c.wantsHDR=YES;c.wantsExposureAdaptation=YES;c.exposureOffset=0.3;
    c.bloomIntensity=0.4;c.bloomThreshold=0.85;c.bloomBlurRadius=10;
    _camNode=[SCNNode node];_camNode.camera=c;
    _camNode.position=SCNVector3Make(0,5.5,7);
    _camNode.eulerAngles=SCNVector3Make(-0.5,0,0);
    [_sc.rootNode addChildNode:_camNode];
}

// ═══════════════════════════════════════════════
// MARK: - Player
// ═══════════════════════════════════════════════
-(void)setupPlayer{
    _playerNode=[SCNNode node];_playerNode.position=SCNVector3Make(0,_playerY,0);
    [_sc.rootNode addChildNode:_playerNode];
    _modelNode=[SCNNode node];[_playerNode addChildNode:_modelNode];

    _ai=[GLTFLoader loadModel:@"DwarfIdle"];_ahi=[GLTFLoader loadModel:@"HappyIdle"];_awi=[GLTFLoader loadModel:@"WarriorIdle"];
    _ar=[GLTFLoader loadModel:@"running"];_afi=[GLTFLoader loadModel:@"RunningForwardFlip"];
    _aj=[GLTFLoader loadModel:@"jump"];_as=[GLTFLoader loadModel:@"slide"];
    _ad=[GLTFLoader loadModel:@"SideHitDie"];_asp=[GLTFLoader loadModel:@"spin dance"];
    _ama=[GLTFLoader loadModel:@"macarena"];_atu=[GLTFLoader loadModel:@"tut dance"];
    _ada=[GLTFLoader loadModel:@"HipHopDance"];
    [self anim:@"idle"];LOG(@"👤 14 animations loaded");
}

-(void)anim:(NSString*)n{
    if([_currentAnim isEqualToString:n])return;_currentAnim=n;
    for(SCNNode*c in _modelNode.childNodes)[c removeFromParentNode];
    SCNNode*m=nil;
    if([n hasPrefix:@"idle"]){NSArray*a=@[_ai,_ahi,_awi];m=[a[arc4random_uniform(3)]clone];}
    else if([n isEqualToString:@"run"])m=[_ar clone];
    else if([n isEqualToString:@"jump"])m=[_aj clone];
    else if([n isEqualToString:@"slide"])m=[_as clone];
    else if([n isEqualToString:@"die"])m=[_ad clone];
    else if([n isEqualToString:@"flip"])m=[_afi clone];
    else if([n isEqualToString:@"spin"])m=[_asp clone];
    else if([n isEqualToString:@"macarena"])m=[_ama clone];
    else if([n isEqualToString:@"tut"])m=[_atu clone];
    else if([n isEqualToString:@"hiphop"])m=[_ada clone];
    if(m){m.scale=SCNVector3Make(0.8,0.8,0.8);[_modelNode addChildNode:m];}
}

// ═══════════════════════════════════════════════
// MARK: - Road System
// ═══════════════════════════════════════════════
-(void)setupRoad{
    _roadContainer=[SCNNode node];[_sc.rootNode addChildNode:_roadContainer];
    _roadTiles=[NSMutableArray array];
    for(int i=0;i<NT;i++){
        SCNBox*b=[SCNBox boxWithWidth:RW height:0.15 length:TL chamferRadius:0.02];
        b.materials=@[pbr(@"road")];SCNNode*n=[SCNNode nodeWithGeometry:b];
        n.position=SCNVector3Make(0,-0.07,-i*TL);[_roadContainer addChildNode:n];
        [_roadTiles addObject:n];
    }
}

// ═══════════════════════════════════════════════
// MARK: - Spawn Helpers
// ═══════════════════════════════════════════════
-(SCNNode*)spawnTree{
    NSString*nm=_treeNames[arc4random_uniform((uint32_t)_treeNames.count)];
    SCNNode*t=[GLTFLoader loadModel:nm];if(!t)t=[SCNNode node];
    t.scale=SCNVector3Make(0.7,0.7,0.7);return t;
}
-(SCNNode*)spawnRock{
    NSString*nm=_rockNames[arc4random_uniform((uint32_t)_rockNames.count)];
    SCNNode*r=[GLTFLoader loadModel:nm];if(!r)r=[SCNNode node];
    r.scale=SCNVector3Make(1.5,1,1.5);return r;
}
-(SCNNode*)spawnTurtle{
    SCNNode*t=[SCNNode node];SCNSphere*s=[SCNSphere sphereWithRadius:0.35];
    SCNMaterial*m=[SCNMaterial material];m.lightingModelName=SCNLightingModelPhysicallyBased;
    m.diffuse.contents=[UIColor colorWithRed:0.12 green:0.42 blue:0.23 alpha:1];m.roughness.contents=@0.85;
    s.materials=@[m];SCNNode*sn=[SCNNode nodeWithGeometry:s];
    sn.scale=SCNVector3Make(1.2,0.75,1);sn.position=SCNVector3Make(0,0.35,0);[t addChildNode:sn];
    SCNSphere*h=[SCNSphere sphereWithRadius:0.16];
    SCNMaterial*hm=[SCNMaterial material];hm.lightingModelName=SCNLightingModelPhysicallyBased;
    hm.diffuse.contents=[UIColor colorWithRed:0.18 green:0.54 blue:0.3 alpha:1];h.materials=@[hm];
    SCNNode*hn=[SCNNode nodeWithGeometry:h];hn.position=SCNVector3Make(0,0.25,0.42);[t addChildNode:hn];
    return t;
}
-(SCNNode*)spawnRing{
    SCNTorus*r=[SCNTorus torusWithRingRadius:0.4 pipeRadius:0.04];
    SCNMaterial*m=[SCNMaterial material];m.lightingModelName=SCNLightingModelConstant;
    m.diffuse.contents=[UIColor colorWithRed:1 green:0.85 blue:0.1 alpha:1];m.emission.contents=[UIColor colorWithRed:0.5 green:0.4 blue:0 alpha:1];
    r.materials=@[m];SCNNode*n=[SCNNode nodeWithGeometry:r];n.eulerAngles=SCNVector3Make(M_PI_2,0,0);return n;
}
-(SCNNode*)spawnHeart{
    SCNNode*h=[SCNNode node];SCNSphere*s=[SCNSphere sphereWithRadius:0.18];SCNMaterial*m=[SCNMaterial material];
    m.diffuse.contents=[UIColor redColor];m.emission.contents=[UIColor colorWithRed:0.3 green:0 blue:0 alpha:1];
    s.materials=@[m];SCNNode*n1=[SCNNode nodeWithGeometry:s];n1.position=SCNVector3Make(-0.13,0,0);
    SCNNode*n2=[SCNNode nodeWithGeometry:s];n2.position=SCNVector3Make(0.13,0,0);
    [h addChildNode:n1];[h addChildNode:n2];return h;
}
-(SCNNode*)spawnCoin{
    SCNNode*c=[SCNNode node];SCNCylinder*b=[SCNCylinder cylinderWithRadius:0.3 height:0.06];
    SCNMaterial*cm=[SCNMaterial material];cm.lightingModelName=SCNLightingModelPhysicallyBased;
    cm.diffuse.contents=[UIColor colorWithRed:1 green:0.75 blue:0.1 alpha:1];cm.roughness.contents=@0.15;cm.metalness.contents=@1;
    b.materials=@[cm];SCNNode*bn=[SCNNode nodeWithGeometry:b];bn.eulerAngles=SCNVector3Make(M_PI_2,0,0);[c addChildNode:bn];
    SCNTorus*r=[SCNTorus torusWithRingRadius:0.33 pipeRadius:0.02];
    SCNMaterial*rm=[SCNMaterial material];rm.lightingModelName=SCNLightingModelConstant;
    rm.diffuse.contents=[UIColor colorWithRed:1 green:0.9 blue:0.2 alpha:1];r.materials=@[rm];
    SCNNode*rn=[SCNNode nodeWithGeometry:r];rn.eulerAngles=SCNVector3Make(M_PI_2,0,0);[c addChildNode:rn];
    return c;
}
-(SCNNode*)spawnBullet{
    SCNSphere*s=[SCNSphere sphereWithRadius:0.08];SCNMaterial*m=[SCNMaterial material];
    m.lightingModelName=SCNLightingModelConstant;m.diffuse.contents=[UIColor yellowColor];
    m.emission.contents=[UIColor colorWithRed:1 green:0.7 blue:0 alpha:1];s.materials=@[m];
    return [SCNNode nodeWithGeometry:s];
}

// ═══════════════════════════════════════════════
// MARK: - HUD (EXACT match of original layout)
// ═══════════════════════════════════════════════
-(void)setupHUD{
    CGFloat sw=self.view.bounds.size.width;
    CGFloat pw=MIN(230*hs()*hw(),sw-16*hs());
    CGFloat y=5*ms(), x=8*hs();

    _hudWrap=[[UIView alloc]initWithFrame:CGRectMake(x,y,pw,0)];
    _hudWrap.backgroundColor=[UIColor clearColor];_hudWrap.userInteractionEnabled=NO;
    [self.view addSubview:_hudWrap];

    // Row 1: [Score] [Emoji] — 2-column grid
    CGFloat cw=(pw-gap())/2;
    CGFloat poff=0;

    // Score (left half)
    __autoreleasing UILabel *sv=nil;
    _scorePill=[self hudPillHalf:CGRectMake(0,poff,cw,ph()) icon:@"⭐" label:@"Score" valRef:&sv];
    _scoreVal=sv;
    [_hudWrap addSubview:_scorePill];

    // Emoji/Coins (right half)
    __autoreleasing UILabel *cv=nil;
    _coinPill=[self hudPillHalf:CGRectMake(cw+gap(),poff,cw,ph()) icon:@"😊" label:@"Emoji" valRef:&cv];
    _coinVal=cv;
    [_hudWrap addSubview:_coinPill];
    poff+=ph()+4*hs();

    // Row 2: [Rings] [Lives]
    __autoreleasing UILabel *rv=nil;
    _ringPill=[self hudPillHalf:CGRectMake(0,poff,cw,ph()) icon:@"💍" label:@"Rings" valRef:&rv];
    _ringVal=rv;
    [_hudWrap addSubview:_ringPill];
    _ringsLabel=[_ringPill.subviews[1] isKindOfClass:[UILabel class]]?(UILabel*)_ringPill.subviews[1]:nil;

    _lifePill=[self hudPillLife:CGRectMake(cw+gap(),poff,cw,ph())];
    [_hudWrap addSubview:_lifePill];
    poff+=ph()+4*hs();

    // Row 3: Magnete (full width)
    __autoreleasing UILabel *mt=nil; __autoreleasing UIView *mf=nil;
    _magPill=[self hudBarPill:CGRectMake(0,poff,pw,ph()) icon:@"🧲" label:@"Magnete" valRef:&mt fillRef:&mf];
    _magTxt=mt; _magBarFill=mf;
    [_hudWrap addSubview:_magPill];
    poff+=ph()+4*hs();

    // Row 4: Cibo Boost (full width, hidden)
    __autoreleasing UILabel *ft=nil; __autoreleasing UIView *ff=nil;
    _foodBoostPill=[self hudBarPill:CGRectMake(0,poff,pw,ph()) icon:@"🍔" label:@"Cibo" valRef:&ft fillRef:&ff];
    _foodBoostTime=ft; _foodBarFill=ff;
    _foodBoostPill.hidden=YES;[_hudWrap addSubview:_foodBoostPill];
    poff+=ph()+4*hs();

    // Row 5: Boost (full width, hidden)
    __autoreleasing UILabel *bt=nil; __autoreleasing UIView *bf=nil;
    _boostPill=[self hudBarPill:CGRectMake(0,poff,pw,ph()) icon:@"⚡" label:@"BOOST" valRef:&bt fillRef:&bf];
    _boostTime=bt; _boostBarFill=bf;
    _boostPill.hidden=YES;[_hudWrap addSubview:_boostPill];
    // Change boost label font
    for(UILabel*l in _boostPill.subviews){if([l isKindOfClass:[UILabel class]]&&l.text.length>0&&![l.text hasPrefix:@"⚡"]){_boostName=l;}}

    // Debug button (below Magnete, matching original position)
    _debugBtn=[UIButton buttonWithType:UIButtonTypeSystem];
    _debugBtn.frame=CGRectMake(0,poff+6*hs(),ph()*hs(),ph()*hs());
    [_debugBtn setTitle:@"🐛" forState:UIControlStateNormal];_debugBtn.titleLabel.font=[UIFont systemFontOfSize:10*ms()];
    [_debugBtn addTarget:self action:@selector(toggleDebug) forControlEvents:UIControlEventTouchUpInside];
    _debugBtn.userInteractionEnabled=YES;[_hudWrap addSubview:_debugBtn];

    // Best score (hidden, like original)
    _bestLbl=[[UILabel alloc]initWithFrame:CGRectZero];_bestLbl.hidden=YES;[self.view addSubview:_bestLbl];
    _bestLbl.text=@"0";

    // Update HUD frame height
    CGRect hf=_hudWrap.frame;hf.size.height=poff+ph()+20;_hudWrap.frame=hf;

    // Initial values
    _scoreVal.text=@"0";_coinVal.text=@"0";_ringVal.text=@"0";_magTxt.text=@"🧲 0";
    _foodBoostTime.text=@"0.0s";_boostTime.text=@"0.0s";
}

// ═══════════════════════════════════════════════
// MARK: - Top Right (Home + Settings)
// ═══════════════════════════════════════════════
-(void)setupTopRight{
    CGFloat sw=self.view.bounds.size.width;
    CGFloat x=sw-8*hs()-66*hs();
    CGFloat y=5*ms();
    CGFloat bw=66*hs(),bh=ph()*hs();

    _topRightPill=glassPillShadow(CGRectMake(x,y,bw,bh));
    _topRightPill.userInteractionEnabled=YES;[self.view addSubview:_topRightPill];

    CGFloat btnW=bw/2;
    _homeBtn=[UIButton buttonWithType:UIButtonTypeSystem];
    _homeBtn.frame=CGRectMake(0,0,btnW,bh);
    [_homeBtn setTitle:@"🏠" forState:UIControlStateNormal];_homeBtn.titleLabel.font=[UIFont systemFontOfSize:13*hs()*1.25];
    [_homeBtn addTarget:self action:@selector(goHome) forControlEvents:UIControlEventTouchUpInside];
    [_topRightPill addSubview:_homeBtn];

    _settingsBtn=[UIButton buttonWithType:UIButtonTypeSystem];
    _settingsBtn.frame=CGRectMake(btnW,0,btnW,bh);
    [_settingsBtn setTitle:@"⚙️" forState:UIControlStateNormal];_settingsBtn.titleLabel.font=[UIFont systemFontOfSize:13*hs()*1.25];
    [_settingsBtn addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
    [_topRightPill addSubview:_settingsBtn];
}

// ═══════════════════════════════════════════════
// MARK: - Camera Segment (BACK/FPS/FRONT)
// ═══════════════════════════════════════════════
-(void)setupCameraSegment{
    CGFloat sw=self.view.bounds.size.width;
    CGFloat segW=90*hs(),segH=ph()*hs();
    CGFloat x=sw-8*hs()-segW;
    CGFloat y=5*ms()+ph()*hs()+6*hs()+12; // camOffsetY

    _camSegPill=glassPillShadow(CGRectMake(x,y,segW,segH));
    _camSegPill.userInteractionEnabled=YES;[self.view addSubview:_camSegPill];

    // Thumb
    CGFloat tw=segW/3-2*hs();
    _camThumb=[[UIView alloc]initWithFrame:CGRectMake(2*hs(),2*hs(),tw,segH-4*hs())];
    _camThumb.backgroundColor=[UIColor colorWithWhite:1 alpha:0.12];_camThumb.layer.cornerRadius=_camThumb.frame.size.height/2;
    _camThumb.layer.borderWidth=1;_camThumb.layer.borderColor=[UIColor colorWithRed:0.57 green:0.8 blue:1 alpha:0.28].CGColor;
    _camThumb.userInteractionEnabled=NO;[_camSegPill addSubview:_camThumb];

    // BACK
    _camBackLbl=[[UILabel alloc]initWithFrame:CGRectMake(0,0,tw+4*hs(),segH)];
    _camBackLbl.text=@"BACK";_camBackLbl.textAlignment=NSTextAlignmentCenter;_camBackLbl.font=[UIFont systemFontOfSize:7*hs() weight:UIFontWeightBlack];
    _camBackLbl.textColor=[UIColor colorWithRed:0.92 green:0.95 blue:1 alpha:1];_camBackLbl.userInteractionEnabled=YES;
    UITapGestureRecognizer*t1=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(camBackTapped)];
    [_camBackLbl addGestureRecognizer:t1];[_camSegPill addSubview:_camBackLbl];

    // FPS
    _camFPSLbl=[[UILabel alloc]initWithFrame:CGRectMake(segW/3,0,segW/3,segH)];
    _camFPSLbl.text=@"FPS";_camFPSLbl.textAlignment=NSTextAlignmentCenter;_camFPSLbl.font=[UIFont systemFontOfSize:7*hs() weight:UIFontWeightBlack];
    _camFPSLbl.textColor=[UIColor colorWithRed:0.92 green:0.95 blue:1 alpha:0.9];_camFPSLbl.userInteractionEnabled=YES;
    UITapGestureRecognizer*t2=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(camFPSTapped)];
    [_camFPSLbl addGestureRecognizer:t2];[_camSegPill addSubview:_camFPSLbl];

    // FRONT
    _camFrontLbl=[[UILabel alloc]initWithFrame:CGRectMake(2*segW/3,0,segW/3,segH)];
    _camFrontLbl.text=@"FRONT";_camFrontLbl.textAlignment=NSTextAlignmentCenter;_camFrontLbl.font=[UIFont systemFontOfSize:7*hs() weight:UIFontWeightBlack];
    _camFrontLbl.textColor=[UIColor colorWithRed:0.92 green:0.95 blue:1 alpha:0.9];_camFrontLbl.userInteractionEnabled=YES;
    UITapGestureRecognizer*t3=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(camFrontTapped)];
    [_camFrontLbl addGestureRecognizer:t3];[_camSegPill addSubview:_camFrontLbl];
}

-(void)updateCamThumb{
    CGFloat segW=90*hs(),segH=ph()*hs(),tw=segW/3-2*hs();
    CGFloat tx=2*hs();
    if(_viewMode==ViewModeFPS)tx=segW/3;
    else if(_viewMode==ViewModeFront)tx=2*segW/3;
    [UIView animateWithDuration:0.18 animations:^{_camThumb.frame=CGRectMake(tx,2*hs(),tw,segH-4*hs());}];
    _camBackLbl.alpha=_viewMode==ViewModeBack?1:0.9;
    _camFPSLbl.alpha=_viewMode==ViewModeFPS?1:0.9;
    _camFrontLbl.alpha=_viewMode==ViewModeFront?1:0.9;
}

-(void)camBackTapped{[self applyViewMode:ViewModeBack];}
-(void)camFPSTapped{[self applyViewMode:ViewModeFPS];}
-(void)camFrontTapped{[self applyViewMode:ViewModeFront];}

-(void)applyViewMode:(ViewMode)mode{
    _viewMode=mode;[self updateCamThumb];
    switch(mode){
        case ViewModeBack:_camNode.position=SCNVector3Make(0,5.5,7);_camNode.eulerAngles=SCNVector3Make(-0.5,0,0);break;
        case ViewModeFPS:_camNode.position=SCNVector3Make(0,1.8,-0.5);_camNode.eulerAngles=SCNVector3Make(0,0,0);break;
        case ViewModeFront:_camNode.position=SCNVector3Make(0,3.5,-5);_camNode.eulerAngles=SCNVector3Make(-0.3,M_PI,0);break;
    }
}

// ═══════════════════════════════════════════════
// MARK: - Right Stack (Bullets, Boost, AVVIA, DANCE)
// ═══════════════════════════════════════════════
-(void)setupRightStack{
    CGFloat sw=self.view.bounds.size.width,sh=self.view.bounds.size.height;
    CGFloat rx=sw-6*ms()-70*ms()*0.75;
    CGFloat bw=70*ms()*0.75,bh=20*ms()*1.5;
    CGFloat gapY=5*ms();

    CGFloat by=sh-(8*ms()+22*ms())-2*(bh+gapY);
    _rightStack=[[UIView alloc]initWithFrame:CGRectMake(rx,by,bw,sh-by)];_rightStack.backgroundColor=[UIColor clearColor];
    [self.view addSubview:_rightStack];

    CGFloat sy=0;

    // Bullets Row (hidden)
    _bulletsRow=[[UIView alloc]initWithFrame:CGRectMake(0,sy,bw,bh)];_bulletsRow.hidden=YES;[_rightStack addSubview:_bulletsRow];
    CGFloat mw=28*ms();
    UIView*bcp=glassPillShadow(CGRectMake(0,0,mw,bh));
    _bulletsCountBtn=[UIButton buttonWithType:UIButtonTypeSystem];_bulletsCountBtn.frame=CGRectMake(0,0,mw,bh);
    _bulletsCountLbl=[[UILabel alloc]initWithFrame:CGRectMake(0,0,mw,bh)];_bulletsCountLbl.text=@"5";_bulletsCountLbl.textAlignment=NSTextAlignmentCenter;_bulletsCountLbl.font=[UIFont systemFontOfSize:7*ms()*1.1 weight:UIFontWeightBlack];_bulletsCountLbl.textColor=[UIColor whiteColor];
    [_bulletsCountBtn addSubview:_bulletsCountLbl];[bcp addSubview:_bulletsCountBtn];[_bulletsRow addSubview:bcp];
    [_bulletsCountBtn addTarget:self action:@selector(fireBullet) forControlEvents:UIControlEventTouchUpInside];

    UIView*bbp=glassPillShadow(CGRectMake(mw+gapY,0,bw-mw-gapY,bh));
    _bulletsBtn=[UIButton buttonWithType:UIButtonTypeSystem];_bulletsBtn.frame=CGRectMake(0,0,bw-mw-gapY,bh);
    _bulletsLabel=[[UILabel alloc]initWithFrame:CGRectMake(0,0,bw-mw-gapY,bh)];_bulletsLabel.text=@"BULLETS";_bulletsLabel.textAlignment=NSTextAlignmentCenter;_bulletsLabel.font=[UIFont systemFontOfSize:7*ms()*1.125 weight:UIFontWeightBlack];_bulletsLabel.textColor=[UIColor whiteColor];
    [_bulletsBtn addSubview:_bulletsLabel];[bbp addSubview:_bulletsBtn];[_bulletsRow addSubview:bbp];
    [_bulletsBtn addTarget:self action:@selector(fireBullet) forControlEvents:UIControlEventTouchUpInside];
    sy+=bh+gapY;

    // Boost Row (hidden)
    _boostRow=[[UIView alloc]initWithFrame:CGRectMake(0,sy,bw,bh)];_boostRow.hidden=YES;[_rightStack addSubview:_boostRow];
    UIView*bcp2=glassPillShadow(CGRectMake(0,0,mw,bh));
    _boostCountBtn=[UIButton buttonWithType:UIButtonTypeSystem];_boostCountBtn.frame=CGRectMake(0,0,mw,bh);
    _boostCountLbl=[[UILabel alloc]initWithFrame:CGRectMake(0,0,mw,bh)];_boostCountLbl.text=@"0";_boostCountLbl.textAlignment=NSTextAlignmentCenter;_boostCountLbl.font=[UIFont systemFontOfSize:7*ms()*1.1 weight:UIFontWeightBlack];_boostCountLbl.textColor=[UIColor whiteColor];
    [_boostCountBtn addSubview:_boostCountLbl];[bcp2 addSubview:_boostCountBtn];[_boostRow addSubview:bcp2];
    [_boostCountBtn addTarget:self action:@selector(useFoodBoost) forControlEvents:UIControlEventTouchUpInside];

    UIView*fbp=glassPillShadow(CGRectMake(mw+gapY,0,bw-mw-gapY,bh));
    _foodBoostBtn=[UIButton buttonWithType:UIButtonTypeSystem];_foodBoostBtn.frame=CGRectMake(0,0,bw-mw-gapY,bh);
    _foodBoostLabel=[[UILabel alloc]initWithFrame:CGRectMake(0,0,bw-mw-gapY,bh)];_foodBoostLabel.text=@"BOOST";_foodBoostLabel.textAlignment=NSTextAlignmentCenter;_foodBoostLabel.font=[UIFont systemFontOfSize:7*ms()*1.125 weight:UIFontWeightBlack];_foodBoostLabel.textColor=[UIColor whiteColor];
    [_foodBoostBtn addSubview:_foodBoostLabel];[fbp addSubview:_foodBoostBtn];[_boostRow addSubview:fbp];
    [_foodBoostBtn addTarget:self action:@selector(useFoodBoost) forControlEvents:UIControlEventTouchUpInside];
    sy+=bh+gapY;

    // AVVIA/RESTART/STOP (big button)
    _mainBtn=[UIButton buttonWithType:UIButtonTypeSystem];_mainBtn.frame=CGRectMake(0,sy,bw,bh);
    UIView*mbp=glassPillShadow(CGRectMake(0,0,bw,bh));
    _mainLbl=[[UILabel alloc]initWithFrame:CGRectMake(0,0,bw,bh)];_mainLbl.text=@"AVVIA";_mainLbl.textAlignment=NSTextAlignmentCenter;_mainLbl.font=[UIFont systemFontOfSize:7*ms()*1.125 weight:UIFontWeightBlack];_mainLbl.textColor=[UIColor whiteColor];_mainLbl.text=@"AVVIA";
    [mbp addSubview:_mainLbl];_mainBtn.frame=CGRectMake(0,0,bw,bh);[_mainBtn addTarget:self action:@selector(mainAction) forControlEvents:UIControlEventTouchUpInside];
    [mbp addSubview:_mainBtn];[_rightStack addSubview:mbp];
    sy+=bh+gapY;

    // DANCE
    _danceBtn=[UIButton buttonWithType:UIButtonTypeSystem];_danceBtn.frame=CGRectMake(0,sy,bw,bh);
    UIView*dbp=glassPillShadow(CGRectMake(0,0,bw,bh));
    _danceLbl=[[UILabel alloc]initWithFrame:CGRectMake(0,0,bw,bh)];_danceLbl.text=@"DANCE";_danceLbl.textAlignment=NSTextAlignmentCenter;_danceLbl.font=[UIFont systemFontOfSize:7*ms()*1.125 weight:UIFontWeightBlack];_danceLbl.textColor=[UIColor whiteColor];
    [dbp addSubview:_danceLbl];[_danceBtn addTarget:self action:@selector(useDance) forControlEvents:UIControlEventTouchUpInside];
    [dbp addSubview:_danceBtn];[_rightStack addSubview:dbp];
}

-(void)updateMainButton{
    if(_over){_mainLbl.text=@"RESTART";return;}
    if(!_stopped){_mainLbl.text=@"STOP";return;}
    _mainLbl.text=@"AVVIA";
}

-(void)updateBulletsUI{
    BOOL show=(_foodBoostT>0&&_bullets>0);
    _bulletsRow.hidden=!show;_bulletsCountLbl.text=[NSString stringWithFormat:@"%d",_bullets];
}

-(void)updateBoostRowUI{
    BOOL show=(_foodBoostCharges>0&&_state==GameStatePlaying);
    _boostRow.hidden=!show;
    _boostCountLbl.text=[NSString stringWithFormat:@"%d",_foodBoostCharges];
    _foodBoostLabel.text=_foodBoostT>0?@"ACTIVE":@"BOOST";
}

// ═══════════════════════════════════════════════
// MARK: - Right Column (Food)
// ═══════════════════════════════════════════════
-(void)setupRightCol{
    CGFloat sw=self.view.bounds.size.width;
    CGFloat x=sw-5*ms()-32*ms(),y=67*ms(),cw=32*ms();
    _rightCol=[[UIView alloc]initWithFrame:CGRectMake(x,y,cw,200)];_rightCol.backgroundColor=[UIColor clearColor];_rightCol.userInteractionEnabled=NO;
    [self.view addSubview:_rightCol];

    // Food Count
    _foodCountPill=glassPillShadow(CGRectMake(0,0,60*ms(),15*ms()));
    _foodCountPill.center=CGPointMake(cw/2,7.5*ms());
    _foodCountLbl=[[UILabel alloc]initWithFrame:CGRectMake(0,0,60*ms(),15*ms())];_foodCountLbl.text=@"🎒 0/10";_foodCountLbl.textAlignment=NSTextAlignmentCenter;_foodCountLbl.font=[UIFont systemFontOfSize:7*ms() weight:UIFontWeightBlack];_foodCountLbl.textColor=[UIColor whiteColor];
    [_foodCountPill addSubview:_foodCountLbl];[_rightCol addSubview:_foodCountPill];

    // Food Stack
    _foodStack=[[UIView alloc]initWithFrame:CGRectMake(0,20*ms(),cw,100*ms())];_foodStack.backgroundColor=[UIColor clearColor];
    [_rightCol addSubview:_foodStack];
}

-(void)refreshFoodUI{
    _foodCountLbl.text=[NSString stringWithFormat:@"🎒 %d/10",_foodCount];
    // Clear food stack
    for(UIView*v in _foodStack.subviews)[v removeFromSuperview];
    // Show last 6 foods
    NSArray*foods=_foodHistory.count>6?[_foodHistory subarrayWithRange:NSMakeRange(_foodHistory.count-6,6)]:_foodHistory;
    CGFloat fy=0;
    for(NSString*emo in foods){
        UIView*fi=glassPill(CGRectMake(0,fy,27*ms(),15*ms()));
        fi.center=CGPointMake(16*ms(),fy+7.5*ms());
        UILabel*fl=[[UILabel alloc]initWithFrame:CGRectMake(0,0,27*ms(),15*ms())];fl.text=emo;fl.textAlignment=NSTextAlignmentCenter;fl.font=[UIFont systemFontOfSize:8*ms()];
        [fi addSubview:fl];[_foodStack addSubview:fi];fy+=20*ms();
    }
}

// ═══════════════════════════════════════════════
// MARK: - Settings Panel (FULL IMPLEMENTATION)
// ═══════════════════════════════════════════════
-(void)setupSettingsPanel{
    CGFloat sw=self.view.bounds.size.width,sh=self.view.bounds.size.height;

    _settingsOverlay=[[UIView alloc]initWithFrame:self.view.bounds];
    _settingsOverlay.backgroundColor=[UIColor colorWithWhite:0 alpha:0.72];_settingsOverlay.hidden=YES;
    UITapGestureRecognizer*bgt=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(closeSettings)];
    [_settingsOverlay addGestureRecognizer:bgt];
    [self.view addSubview:_settingsOverlay];

    CGFloat pw=MIN(740,sw-28);
    _settingsPanel=glassPillShadow(CGRectMake((sw-pw)/2,40,pw,sh-80));
    _settingsPanel.layer.cornerRadius=20;_settingsPanel.layer.masksToBounds=YES;
    _settingsPanel.userInteractionEnabled=YES;

    // Prevent tap-through
    UITapGestureRecognizer*pt=[[UITapGestureRecognizer alloc]initWithTarget:nil action:nil];
    [_settingsPanel addGestureRecognizer:pt];
    [_settingsOverlay addSubview:_settingsPanel];

    // Close X
    _closeSettingsBtn=[UIButton buttonWithType:UIButtonTypeSystem];
    _closeSettingsBtn.frame=CGRectMake(pw-30*hs(),4,22*hs(),22*hs());
    [_closeSettingsBtn setTitle:@"✕" forState:UIControlStateNormal];_closeSettingsBtn.titleLabel.font=[UIFont systemFontOfSize:10*hs() weight:UIFontWeightBlack];
    [_closeSettingsBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_closeSettingsBtn addTarget:self action:@selector(closeSettings) forControlEvents:UIControlEventTouchUpInside];
    _closeSettingsBtn.layer.cornerRadius=11*hs();_closeSettingsBtn.backgroundColor=[UIColor colorWithWhite:1 alpha:0.1];_closeSettingsBtn.layer.borderWidth=1;_closeSettingsBtn.layer.borderColor=[UIColor colorWithRed:0.57 green:0.8 blue:1 alpha:0.25].CGColor;
    [_settingsPanel addSubview:_closeSettingsBtn];

    // Title
    UILabel*title=[[UILabel alloc]initWithFrame:CGRectMake(14,14,pw-60,30)];title.text=@"Impostazioni";title.font=[UIFont systemFontOfSize:16 weight:UIFontWeightBlack];title.textColor=[UIColor colorWithRed:0.92 green:0.95 blue:1 alpha:1];
    [_settingsPanel addSubview:title];

    // Tabs
    UIView*tabs=glassPill(CGRectMake(14,50,pw-28,40));
    tabs.layer.cornerRadius=20;
    CGFloat tw=(pw-28)/3;
    _tabCam=[self tabBtn:CGRectMake(0,0,tw,40) title:@"CAMERA" active:YES];[tabs addSubview:_tabCam];
    _tabVisual=[self tabBtn:CGRectMake(tw,0,tw,40) title:@"VISUAL" active:NO];[tabs addSubview:_tabVisual];
    _tabAudio=[self tabBtn:CGRectMake(2*tw,0,tw,40) title:@"AUDIO" active:NO];[tabs addSubview:_tabAudio];
    [_tabCam addTarget:self action:@selector(settingsTabCamera) forControlEvents:UIControlEventTouchUpInside];
    [_tabVisual addTarget:self action:@selector(settingsTabVisual) forControlEvents:UIControlEventTouchUpInside];
    [_tabAudio addTarget:self action:@selector(settingsTabAudio) forControlEvents:UIControlEventTouchUpInside];
    [_settingsPanel addSubview:tabs];

    // Cards
    CGFloat cy=100,ch=_settingsPanel.frame.size.height-cy-50;
    _camCard=[[UIView alloc]initWithFrame:CGRectMake(14,cy,pw-28,ch)];_camCard.backgroundColor=[UIColor colorWithWhite:1 alpha:0.05];_camCard.layer.cornerRadius=16;_camCard.layer.borderWidth=0.5;_camCard.layer.borderColor=[UIColor colorWithWhite:1 alpha:0.12].CGColor;
    [_settingsPanel addSubview:_camCard];

    _visualCard=[[UIView alloc]initWithFrame:CGRectMake(14,cy,pw-28,ch)];_visualCard.backgroundColor=[UIColor colorWithWhite:1 alpha:0.05];_visualCard.layer.cornerRadius=16;_visualCard.layer.borderWidth=0.5;_visualCard.layer.borderColor=[UIColor colorWithWhite:1 alpha:0.12].CGColor;_visualCard.hidden=YES;
    [_settingsPanel addSubview:_visualCard];

    _audioCard=[[UIView alloc]initWithFrame:CGRectMake(14,cy,pw-28,ch)];_audioCard.backgroundColor=[UIColor colorWithWhite:1 alpha:0.05];_audioCard.layer.cornerRadius=16;_audioCard.layer.borderWidth=0.5;_audioCard.layer.borderColor=[UIColor colorWithWhite:1 alpha:0.12].CGColor;_audioCard.hidden=YES;
    [_settingsPanel addSubview:_audioCard];

    // Camera Card
    [self buildCameraCard:_camCard];

    // Visual Card
    [self buildVisualCard:_visualCard];

    // Audio Card
    [self buildAudioCard:_audioCard];

    // Footer Reset
    _resetBtn=[UIButton buttonWithType:UIButtonTypeSystem];
    _resetBtn.frame=CGRectMake(14,_settingsPanel.frame.size.height-42,80,32);
    [_resetBtn setTitle:@"Reset" forState:UIControlStateNormal];[_resetBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _resetBtn.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    _resetBtn.backgroundColor=[UIColor colorWithWhite:1 alpha:0.08];_resetBtn.layer.cornerRadius=16;
    [_resetBtn addTarget:self action:@selector(resetSettings) forControlEvents:UIControlEventTouchUpInside];
    [_settingsPanel addSubview:_resetBtn];
}

-(UIButton*)tabBtn:(CGRect)frame title:(NSString*)t active:(BOOL)active{
    UIButton*b=[UIButton buttonWithType:UIButtonTypeSystem];b.frame=frame;
    [b setTitle:t forState:UIControlStateNormal];[b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightBlack];
    b.alpha=active?1:0.85;b.layer.cornerRadius=frame.size.height/2;
    return b;
}

-(UILabel*)settingsLabel:(CGRect)frame text:(NSString*)t{
    UILabel*l=[[UILabel alloc]initWithFrame:frame];l.text=t;l.textColor=[UIColor whiteColor];l.font=[UIFont systemFontOfSize:13 weight:UIFontWeightBold];
    return l;
}

-(UISlider*)settingsSlider:(CGRect)frame min:(float)min max:(float)max val:(float)val{
    UISlider*s=[[UISlider alloc]initWithFrame:frame];s.minimumValue=min;s.maximumValue=max;s.value=val;s.tintColor=[UIColor colorWithWhite:0.85 alpha:1];
    return s;
}

-(void)buildCameraCard:(UIView*)card{
    UILabel*h3=[[UILabel alloc]initWithFrame:CGRectMake(12,12,card.frame.size.width-24,20)];h3.text=@"CAMERA";h3.font=[UIFont systemFontOfSize:12 weight:UIFontWeightBold];h3.textColor=[UIColor colorWithWhite:1 alpha:0.9];
    [card addSubview:h3];

    // FRONT/BACK sub-segment
    UIView*seg=glassPill(CGRectMake(12,38,card.frame.size.width-24,36));

    _camProfFrontBtn=[UIButton buttonWithType:UIButtonTypeSystem];_camProfFrontBtn.frame=CGRectMake(0,0,(card.frame.size.width-24)/2,36);[_camProfFrontBtn setTitle:@"FRONT" forState:UIControlStateNormal];[_camProfFrontBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];_camProfFrontBtn.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightBlack];_camProfFrontBtn.alpha=1;
    [_camProfFrontBtn addTarget:self action:@selector(settingsCamProfileFront) forControlEvents:UIControlEventTouchUpInside];[seg addSubview:_camProfFrontBtn];

    _camProfBackBtn=[UIButton buttonWithType:UIButtonTypeSystem];_camProfBackBtn.frame=CGRectMake((card.frame.size.width-24)/2,0,(card.frame.size.width-24)/2,36);[_camProfBackBtn setTitle:@"BACK" forState:UIControlStateNormal];[_camProfBackBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];_camProfBackBtn.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightBlack];_camProfBackBtn.alpha=0.85;
    [_camProfBackBtn addTarget:self action:@selector(settingsCamProfileBack) forControlEvents:UIControlEventTouchUpInside];[seg addSubview:_camProfBackBtn];
    [card addSubview:seg];

    CGFloat cy=84,rowH=30;
    // FOV
    [card addSubview:[self settingsLabel:CGRectMake(12,cy,card.frame.size.width-80,16) text:@"FOV (30-110)"]];
    _fovValLbl=[self settingsLabel:CGRectMake(card.frame.size.width-68,cy,56,16) text:@"60"];_fovValLbl.textAlignment=NSTextAlignmentRight;
    [card addSubview:_fovValLbl];
    _fovSlider=[self settingsSlider:CGRectMake(12,cy+18,card.frame.size.width-24,30) min:30 max:110 val:60];
    [_fovSlider addTarget:self action:@selector(fovChanged) forControlEvents:UIControlEventValueChanged];[card addSubview:_fovSlider];
    cy+=55;

    // Camera Distance
    [card addSubview:[self settingsLabel:CGRectMake(12,cy,card.frame.size.width-80,16) text:@"Distanza (2-15)"]];
    _camDistValLbl=[self settingsLabel:CGRectMake(card.frame.size.width-68,cy,56,16) text:@"5.0"];_camDistValLbl.textAlignment=NSTextAlignmentRight;
    [card addSubview:_camDistValLbl];
    _camDistSlider=[self settingsSlider:CGRectMake(12,cy+18,card.frame.size.width-24,30) min:2 max:15 val:5];
    [_camDistSlider addTarget:self action:@selector(camDistChanged) forControlEvents:UIControlEventValueChanged];[card addSubview:_camDistSlider];
    cy+=55;

    // Camera Height
    [card addSubview:[self settingsLabel:CGRectMake(12,cy,card.frame.size.width-80,16) text:@"Altezza (0-8)"]];
    _camYValLbl=[self settingsLabel:CGRectMake(card.frame.size.width-68,cy,56,16) text:@"4.6"];_camYValLbl.textAlignment=NSTextAlignmentRight;
    [card addSubview:_camYValLbl];
    _camYSlider=[self settingsSlider:CGRectMake(12,cy+18,card.frame.size.width-24,30) min:0 max:8 val:4.6];
    [_camYSlider addTarget:self action:@selector(camYChanged) forControlEvents:UIControlEventValueChanged];[card addSubview:_camYSlider];
    cy+=55;

    // Frame
    [card addSubview:[self settingsLabel:CGRectMake(12,cy,card.frame.size.width-80,16) text:@"Inquadratura (0-1)"]];
    _frameValLbl=[self settingsLabel:CGRectMake(card.frame.size.width-68,cy,56,16) text:@"0.06"];_frameValLbl.textAlignment=NSTextAlignmentRight;
    [card addSubview:_frameValLbl];
    _frameSlider=[self settingsSlider:CGRectMake(12,cy+18,card.frame.size.width-24,30) min:0 max:1 val:0.06];
    [_frameSlider addTarget:self action:@selector(frameChanged) forControlEvents:UIControlEventValueChanged];[card addSubview:_frameSlider];
}

-(void)buildVisualCard:(UIView*)card{
    UILabel*h3=[[UILabel alloc]initWithFrame:CGRectMake(12,12,card.frame.size.width-24,20)];h3.text=@"VISUAL (FPS)";h3.font=[UIFont systemFontOfSize:12 weight:UIFontWeightBold];h3.textColor=[UIColor colorWithWhite:1 alpha:0.9];
    [card addSubview:h3];

    CGFloat cy=40,rowH=50;
    // FPS Mode: Realistico / Stabile
    UIView*fpsRow=[[UIView alloc]initWithFrame:CGRectMake(12,cy,card.frame.size.width-24,rowH)];
    fpsRow.backgroundColor=[UIColor colorWithWhite:1 alpha:0.04];fpsRow.layer.cornerRadius=12;fpsRow.layer.borderWidth=0.5;fpsRow.layer.borderColor=[UIColor colorWithWhite:1 alpha:0.12].CGColor;
    UILabel*fpsLbl=[self settingsLabel:CGRectMake(12,0,card.frame.size.width-160,rowH) text:@"FPS"];[fpsRow addSubview:fpsLbl];
    UIView*fpsSeg=glassPill(CGRectMake(card.frame.size.width-150,8,126,rowH-16));
    _fpsRealBtn=[UIButton buttonWithType:UIButtonTypeSystem];_fpsRealBtn.frame=CGRectMake(0,0,63,rowH-16);[_fpsRealBtn setTitle:@"REALISTICO" forState:UIControlStateNormal];[_fpsRealBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];_fpsRealBtn.titleLabel.font=[UIFont systemFontOfSize:11 weight:UIFontWeightBlack];_fpsRealBtn.alpha=1;
    [_fpsRealBtn addTarget:self action:@selector(setFPSRealistic) forControlEvents:UIControlEventTouchUpInside];[fpsSeg addSubview:_fpsRealBtn];
    _fpsStableBtn=[UIButton buttonWithType:UIButtonTypeSystem];_fpsStableBtn.frame=CGRectMake(63,0,63,rowH-16);[_fpsStableBtn setTitle:@"STABILE" forState:UIControlStateNormal];[_fpsStableBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];_fpsStableBtn.titleLabel.font=[UIFont systemFontOfSize:11 weight:UIFontWeightBlack];_fpsStableBtn.alpha=0.85;
    [_fpsStableBtn addTarget:self action:@selector(setFPSStable) forControlEvents:UIControlEventTouchUpInside];[fpsSeg addSubview:_fpsStableBtn];
    [fpsRow addSubview:fpsSeg];[card addSubview:fpsRow];cy+=rowH+10;

    // Motion Blur
    __autoreleasing UISwitch *ms=nil;
    UIView*mbRow=[self toggleRow:CGRectMake(12,cy,card.frame.size.width-24,rowH) label:@"Motion blur" sub:@"Fake blur durante boost" switchRef:&ms on:_motionBlurOn];[card addSubview:mbRow];_motionSwitch=ms;cy+=rowH+10;

    // FOV dinamico
    __autoreleasing UISwitch *ds=nil;
    UIView*fdRow=[self toggleRow:CGRectMake(12,cy,card.frame.size.width-24,rowH) label:@"FOV dinamico (FPS)" sub:@"Aumenta FOV in boost" switchRef:&ds on:_dynFovOn];[card addSubview:fdRow];_dynFovSwitch=ds;cy+=rowH+10;

    // Camera shake
    __autoreleasing UISwitch *ss=nil;
    UIView*csRow=[self toggleRow:CGRectMake(12,cy,card.frame.size.width-24,rowH) label:@"Camera shake" sub:@"Micro shake durante boost" switchRef:&ss on:_cameraShakeOn];[card addSubview:csRow];_shakeSwitch=ss;
}

-(UIView*)toggleRow:(CGRect)frame label:(NSString*)label sub:(NSString*)sub switchRef:(UISwitch**)swRef on:(BOOL)on{
    UIView*row=[[UIView alloc]initWithFrame:frame];row.backgroundColor=[UIColor colorWithWhite:1 alpha:0.04];row.layer.cornerRadius=12;row.layer.borderWidth=0.5;row.layer.borderColor=[UIColor colorWithWhite:1 alpha:0.12].CGColor;
    UILabel*l=[[UILabel alloc]initWithFrame:CGRectMake(12,4,frame.size.width-80,18)];l.text=label;l.font=[UIFont systemFontOfSize:12 weight:UIFontWeightBold];l.textColor=[UIColor whiteColor];[row addSubview:l];
    UILabel*s=[[UILabel alloc]initWithFrame:CGRectMake(12,20,frame.size.width-80,16)];s.text=sub;s.font=[UIFont systemFontOfSize:10];s.textColor=[UIColor colorWithWhite:1 alpha:0.7];[row addSubview:s];
    UISwitch*sw=[[UISwitch alloc]initWithFrame:CGRectMake(frame.size.width-60,8,51,31)];sw.on=on;[row addSubview:sw];
    if(swRef)*swRef=sw;
    return row;
}

-(void)buildAudioCard:(UIView*)card{
    UILabel*h3=[[UILabel alloc]initWithFrame:CGRectMake(12,12,card.frame.size.width-24,20)];h3.text=@"AUDIO";h3.font=[UIFont systemFontOfSize:12 weight:UIFontWeightBold];h3.textColor=[UIColor colorWithWhite:1 alpha:0.9];
    [card addSubview:h3];

    __autoreleasing UISwitch *asw=nil;
    UIView*ar=[self toggleRow:CGRectMake(12,40,card.frame.size.width-24,50) label:@"Suoni" sub:@"Fallback semplice (stabile su iPhone)" switchRef:&asw on:_audioOn];[card addSubview:ar];_audioSwitch=asw;
}

// ═══════════════════════════════════════════════
// MARK: - Settings Actions
// ═══════════════════════════════════════════════
-(void)openSettings{[_audio playJump];_settingsOverlay.hidden=NO;[self settingsTabCamera];}
-(void)closeSettings{_settingsOverlay.hidden=YES;}

-(void)settingsTabCamera{_camCard.hidden=NO;_visualCard.hidden=YES;_audioCard.hidden=YES;_tabCam.alpha=1;_tabVisual.alpha=0.85;_tabAudio.alpha=0.85;}
-(void)settingsTabVisual{_camCard.hidden=YES;_visualCard.hidden=NO;_audioCard.hidden=YES;_tabCam.alpha=0.85;_tabVisual.alpha=1;_tabAudio.alpha=0.85;}
-(void)settingsTabAudio{_camCard.hidden=YES;_visualCard.hidden=YES;_audioCard.hidden=NO;_tabCam.alpha=0.85;_tabVisual.alpha=0.85;_tabAudio.alpha=1;}

-(void)settingsCamProfileFront{_camProfFrontBtn.alpha=1;_camProfBackBtn.alpha=0.85;}
-(void)settingsCamProfileBack{_camProfFrontBtn.alpha=0.85;_camProfBackBtn.alpha=1;}

-(void)fovChanged{_fovValLbl.text=[NSString stringWithFormat:@"%.0f",_fovSlider.value];_camNode.camera.fieldOfView=_fovSlider.value;}
-(void)camDistChanged{_camDistValLbl.text=[NSString stringWithFormat:@"%.1f",_camDistSlider.value];if(_viewMode==ViewModeBack)_camNode.position=SCNVector3Make(0,_camYSlider.value,_camDistSlider.value);}
-(void)camYChanged{_camYValLbl.text=[NSString stringWithFormat:@"%.1f",_camYSlider.value];if(_viewMode==ViewModeBack)_camNode.position=SCNVector3Make(0,_camYSlider.value,_camDistSlider.value);}
-(void)frameChanged{_frameValLbl.text=[NSString stringWithFormat:@"%.2f",_frameSlider.value];}

-(void)setFPSRealistic{_fpsRealistic=YES;_fpsRealBtn.alpha=1;_fpsStableBtn.alpha=0.85;}
-(void)setFPSStable{_fpsRealistic=NO;_fpsRealBtn.alpha=0.85;_fpsStableBtn.alpha=1;}
-(void)resetSettings{
    _fovSlider.value=60;_camDistSlider.value=5;_camYSlider.value=4.6;_frameSlider.value=0.06;
    _fovValLbl.text=@"60";_camDistValLbl.text=@"5.0";_camYValLbl.text=@"4.6";_frameValLbl.text=@"0.06";
    _camNode.camera.fieldOfView=60;_camNode.position=SCNVector3Make(0,5.5,7);
    _motionSwitch.on=NO;_dynFovSwitch.on=YES;_shakeSwitch.on=YES;
    _motionBlurOn=NO;_dynFovOn=YES;_cameraShakeOn=YES;_audioSwitch.on=YES;_audioOn=YES;
    _fpsRealistic=YES;_fpsRealBtn.alpha=1;_fpsStableBtn.alpha=0.85;
    LOG(@"⚙️ Settings reset");
}

// ═══════════════════════════════════════════════
// MARK: - Debug Panel
// ═══════════════════════════════════════════════
-(void)setupDebugPanel{
    _debugPanel=glassPillShadow(CGRectMake(10,60,MIN(320,self.view.bounds.size.width-20),160));
    _debugPanel.hidden=YES;[self.view addSubview:_debugPanel];

    _dbgFps=[self debugRow:CGRectMake(8,8,_debugPanel.frame.size.width-16,18) label:@"fps:"];
    _dbgCam=[self debugRow:CGRectMake(8,26,_debugPanel.frame.size.width-16,18) label:@"camera:"];
    _dbgState=[self debugRow:CGRectMake(8,44,_debugPanel.frame.size.width-16,18) label:@"state:"];
    _dbgEnt=[self debugRow:CGRectMake(8,62,_debugPanel.frame.size.width-16,18) label:@"entities:"];
    _dbgLane=[self debugRow:CGRectMake(8,80,_debugPanel.frame.size.width-16,18) label:@"lane:"];
    _dbgBoosts=[self debugRow:CGRectMake(8,98,_debugPanel.frame.size.width-16,18) label:@"boosts:"];
}

-(UILabel*)debugRow:(CGRect)frame label:(NSString*)l{
    UILabel*ll=[[UILabel alloc]initWithFrame:frame];ll.text=l;ll.textColor=[UIColor colorWithRed:0.85 green:0.9 blue:1 alpha:0.85];ll.font=[UIFont systemFontOfSize:11];[_debugPanel addSubview:ll];
    return ll;
}

-(void)toggleDebug{_debugPanel.hidden=!_debugPanel.hidden;}

// ═══════════════════════════════════════════════
// MARK: - Home Camera
// ═══════════════════════════════════════════════
-(void)setupHomeCam{
    _homeCam.active=YES;_homeCam.intro=NO;_homeCam.t=0;
    _homeOrbitAngle=M_PI;_homeOrbitRadius=2.6;_homeOrbitHeight=1.9;
}

-(void)updateHomeCam:(float)dt{
    if(!_homeCam.active)return;

    if(_homeCam.intro){
        // Drone camera transition
        _homeCam.t+=dt*0.8;
        float t=_homeCam.t;
        // Ease out cubic: 1-(1-t)³
        float e=1-powf(1-MIN(1,t),3);
        _camNode.position=SCNVector3Make(
            sinf(_homeOrbitAngle)*_homeOrbitRadius*(1-e),
            _homeOrbitHeight+(5.5-_homeOrbitHeight)*(e),
            7*(e)+_homeOrbitRadius*(1-e)*(-cosf(_homeOrbitAngle))
        );
        if(t>=1){_homeCam.intro=NO;_homeCam.active=NO;}
        return;
    }

    // Orbiting camera
    _homeOrbitAngle+=0.15*dt;
    _camNode.position=SCNVector3Make(
        sinf(_homeOrbitAngle)*_homeOrbitRadius,
        _homeOrbitHeight,
        -cosf(_homeOrbitAngle)*_homeOrbitRadius+2
    );
    _camNode.eulerAngles=SCNVector3Make(-0.35,0,0);

    // Keep player in idle
    if(![_currentAnim hasPrefix:@"idle"])[self anim:@"idle"];
    _modelNode.position=SCNVector3Make(0,sin(_homeCam.t*2)*0.04,0);
}

// ═══════════════════════════════════════════════
// MARK: - Gestures
// ═══════════════════════════════════════════════
-(void)setupGestures{
    for(int d=0;d<4;d++){UISwipeGestureRecognizer*sw=[[UISwipeGestureRecognizer alloc]initWithTarget:self action:@selector(swipe:)];sw.direction=1<<d;[_sv addGestureRecognizer:sw];}
    UITapGestureRecognizer*t=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(tap)];[_sv addGestureRecognizer:t];
}
-(void)swipe:(UISwipeGestureRecognizer*)s{if(_state!=GameStatePlaying)return;
    if(s.direction==UISwipeGestureRecognizerDirectionLeft&&_lane>-1){_lane--;_targetX=LX(_lane);}
    if(s.direction==UISwipeGestureRecognizerDirectionRight&&_lane<1){_lane++;_targetX=LX(_lane);}
    if(s.direction==UISwipeGestureRecognizerDirectionUp&&!_jumping&&!_sliding){_jumping=YES;_jumpVel=7.5;[self anim:@"jump"];[_audio playJump];}
    if(s.direction==UISwipeGestureRecognizerDirectionDown&&!_jumping&&!_sliding){_sliding=YES;_slideTimer=0.7;_modelNode.scale=SCNVector3Make(1,0.4,1);_playerY=0.5;[self anim:@"slide"];[_audio playSlide];}
}
-(void)tap{if(_state==GameStateGameOver)[self restartGame];}

// ═══════════════════════════════════════════════
// MARK: - Button Actions
// ═══════════════════════════════════════════════
-(void)mainAction{
    [_audio playJump];

    // Home screen or stopped: start game directly (skip drone intro)
    if(_homeCam.active || _stopped){
        [self startGame];
        return;
    }

    // Game over: restart
    if(_over){[self restartGame];return;}

    // Playing: toggle stop
    _stopped=!_stopped;
    if(_stopped){[self anim:@"idle"];}else{[self anim:@"run"];}
    [self updateMainButton];
}

-(void)goHome{
    [_audio playJump];
    [self resetRun];
}

-(void)useDance{
    [_audio playJump];if(_over)return;
    if(_state==GameStatePlaying&&!_stopped){_stopped=YES;[self updateMainButton];}
    // Dance wiggle animation on button
    _danceBtn.transform=CGAffineTransformMakeScale(1.02,1.02);
    [self safeAfter:0.15 block:^{_danceBtn.transform=CGAffineTransformIdentity;}];
    NSArray*d=@[@"spin",@"macarena",@"tut",@"hiphop"];[self anim:d[arc4random_uniform(4)]];
    LOG(@"💃 Dance!");
}

-(void)useFoodBoost{
    if(_state!=GameStatePlaying||_over||_stopped||_paused)return;
    if(_foodBoostT>0)return;
    if(_foodBoostCharges<=0)return;
    _foodBoostCharges-=1;
    _foodBoostT=10;
    _invTimer=MAX(_invTimer,10);
    _bullets=5;
    _carActive=NO;[self updateBulletsUI];[self updateBoostRowUI];
    LOG(@"🍔 FOOD BOOST! %d charges left",_foodBoostCharges);
}

-(void)fireBullet{
    if(_state!=GameStatePlaying||!_carActive||_bullets<=0||_foodBoostT<=0)return;
    _bullets--;
    SCNNode*b=[self spawnBullet];b.position=SCNVector3Make(_playerNode.position.x,_playerY+0.8,_playerNode.position.z-1);
    [_sc.rootNode addChildNode:b];[_projectiles addObject:@{@"n":b,@"z":@(_playerNode.position.z-1)}];
    LOG(@"🔫 Bullet! %d left",_bullets);[_audio playJump];[self updateBulletsUI];
}

// ═══════════════════════════════════════════════
// MARK: - Game State
// ═══════════════════════════════════════════════
-(void)startGame{
    _homeCam.active=NO;_homeCam.intro=NO;_homeCam.t=0;
    _stopped=NO;_over=NO;
    _state=GameStatePlaying;
    [self anim:@"run"];
    [self applyViewMode:ViewModeBack];
    [self updateMainButton];
    [self updateBoostRowUI];
    LOG(@"▶️ PLAY");
}

-(void)resetRun{
    // Return to home
    _homeCam.active=YES;_homeCam.intro=NO;_homeCam.t=0;
    _homeOrbitAngle=M_PI;_homeOrbitRadius=2.6;_homeOrbitHeight=1.9;
    _lane=0;_targetX=0;
    _playerNode.position=SCNVector3Make(0,1,0);
    _jumping=NO;_jumpVel=0;_playerY=1;_sliding=NO;_slideTimer=0;

    _score=0;_coins=0;_rings=0;_dist=0;
    _foodCount=0;_foodHistory=[NSMutableArray array];
    _foodBoostCharges=5;
    _invTimer=0;_foodBoostT=0;_magnetT=0;
    _over=NO;_stopped=YES;_paused=NO;
    _hasBoost=NO;_hasMagnet=NO;_bullets=5;

    _carActive=NO;[_carNode removeFromParentNode];_carNode=nil;
    [self cleanAllPools];

    _state=GameStateHome;
    [self anim:@"idle"];
    [self updateMainButton];
    [self updateBulletsUI];
    [self updateBoostRowUI];
    [self refreshFoodUI];
    _scoreVal.text=@"0";_coinVal.text=@"0";_ringVal.text=@"0";_lifeVal.text=@"❤️❤️❤️";_magTxt.text=@"🧲 0";
    _foodBoostPill.hidden=YES;_boostPill.hidden=YES;_bulletsRow.hidden=YES;
    LOG(@"🏠 Home");
}

-(void)restartGame{
    [self cleanAllPools];
    [[self.view viewWithTag:777]removeFromSuperview];
    [self initState];
    _playerNode.position=SCNVector3Make(0,1,0);_modelNode.scale=SCNVector3Make(1,1,1);_modelNode.position=SCNVector3Make(0,0,0);
    [self anim:@"idle"];_frameCount=0;
    _homeCam.active=YES;_homeCam.intro=NO;_homeCam.t=0;
    _state=GameStateHome;_stopped=YES;_over=NO;
    [self updateMainButton];[self updateBulletsUI];[self updateBoostRowUI];[self refreshFoodUI];
    _scoreVal.text=@"0";_coinVal.text=@"0";_ringVal.text=@"0";_lifeVal.text=@"❤️❤️❤️";_magTxt.text=@"🧲 0";
    _foodBoostPill.hidden=YES;_boostPill.hidden=YES;_bulletsRow.hidden=YES;_boostRow.hidden=NO;
    LOG(@"🔄 RESTARTED");
}

-(void)cleanAllPools{
    for(SCNNode*n in _trees)[n removeFromParentNode];[_trees removeAllObjects];for(SCNNode*n in _rocks)[n removeFromParentNode];[_rocks removeAllObjects];
    for(SCNNode*n in _coinObjs)[n removeFromParentNode];[_coinObjs removeAllObjects];for(SCNNode*n in _turtles)[n removeFromParentNode];[_turtles removeAllObjects];
    for(SCNNode*n in _ringObjs)[n removeFromParentNode];[_ringObjs removeAllObjects];for(SCNNode*n in _heartObjs)[n removeFromParentNode];[_heartObjs removeAllObjects];
    for(NSDictionary*d in _projectiles)[d[@"n"]removeFromParentNode];[_projectiles removeAllObjects];
    if(_carActive){[_carNode removeFromParentNode];_carActive=NO;_carNode=nil;}
}

// ═══════════════════════════════════════════════
// MARK: - Log System
// ═══════════════════════════════════════════════
-(void)setupLog{_logVis=NO;
    _logOverlay=[[UIView alloc]initWithFrame:self.view.bounds];_logOverlay.backgroundColor=[[UIColor blackColor]colorWithAlphaComponent:0.92];_logOverlay.hidden=YES;[self.view addSubview:_logOverlay];
    _ltv=[[UITextView alloc]initWithFrame:CGRectMake(10,50,self.view.bounds.size.width-20,self.view.bounds.size.height-110)];_ltv.backgroundColor=[UIColor clearColor];_ltv.textColor=[UIColor greenColor];_ltv.font=[UIFont fontWithName:@"Menlo" size:10];_ltv.editable=NO;[_logOverlay addSubview:_ltv];
    UIButton*cb=[UIButton buttonWithType:UIButtonTypeSystem];cb.frame=CGRectMake(10,8,80,36);cb.backgroundColor=[[UIColor whiteColor]colorWithAlphaComponent:0.15];cb.layer.cornerRadius=6;[cb setTitle:@"📋 Copy" forState:UIControlStateNormal];cb.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightBold];[cb addTarget:self action:@selector(copyLog) forControlEvents:UIControlEventTouchUpInside];[_logOverlay addSubview:cb];
    UIButton*cl=[UIButton buttonWithType:UIButtonTypeSystem];cl.frame=CGRectMake(100,8,80,36);cl.backgroundColor=[[UIColor redColor]colorWithAlphaComponent:0.3];cl.layer.cornerRadius=6;[cl setTitle:@"🗑 Clear" forState:UIControlStateNormal];cl.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightBold];[cl addTarget:self action:@selector(clearLog) forControlEvents:UIControlEventTouchUpInside];[_logOverlay addSubview:cl];
    UIButton*xl=[UIButton buttonWithType:UIButtonTypeSystem];xl.frame=CGRectMake(self.view.bounds.size.width-60,8,50,36);xl.backgroundColor=[[UIColor whiteColor]colorWithAlphaComponent:0.15];xl.layer.cornerRadius=6;[xl setTitle:@"✕" forState:UIControlStateNormal];[xl addTarget:self action:@selector(toggleLog) forControlEvents:UIControlEventTouchUpInside];[_logOverlay addSubview:xl];
}
-(void)toggleLog{_logVis=!_logVis;_logOverlay.hidden=!_logVis;if(_logVis){_ltv.text=_lbuf;[_ltv scrollRangeToVisible:NSMakeRange(_lbuf.length-1,0)];}}
-(void)copyLog{[[UIPasteboard generalPasteboard]setString:_lbuf];LOG(@"📋 Copied");}
-(void)clearLog{[_lbuf setString:@""];_ltv.text=@"";LOG(@"🗑 Cleared");}

// ═══════════════════════════════════════════════
// MARK: - GAME LOOP (60 FPS)
// ═══════════════════════════════════════════════
-(void)renderer:(id)s updateAtTime:(NSTimeInterval)t{
    // Always update home cam if active
    if(_homeCam.active){
        float dt=(_lastTime==0)?0.016666:MIN(0.05,t-_lastTime);
        _lastTime=t;
        [self updateHomeCam:dt];
        if(!_homeCam.intro)return;
    }

    if(_state!=GameStatePlaying||_stopped||_over)return;

    float dt=(_lastTime==0)?0.016666:MIN(0.05,t-_lastTime);_lastTime=t;
    _frameCount++;

    // Timers
    _invTimer=MAX(0,_invTimer-dt);_boostTimer=MAX(0,_boostTimer-dt);
    if(_boostTimer<=0&&_hasBoost){_hasBoost=NO;LOG(@"🍕 Boost ended");}
    _speedBoost=MAX(0,_speedBoost-dt);
    _foodBoostT=MAX(0,_foodBoostT-dt);
    _magnetT=MAX(0,_magnetT-dt);
    if(_foodBoostT<=0){_bulletsRow.hidden=YES;_carActive=NO;[_carNode removeFromParentNode];_carNode=nil;}

    float effectiveDt=dt*(1+(_speedBoost>0?0.5:0));

    // Speed + Score
    _dist+=_speed*effectiveDt;_score=(int)_dist;
    _speed=10+_dist/100;if(_speed>40)_speed=40;

    // ── Player (cubic easing lane change + dust trail) ──
    float cx=_playerNode.position.x;float dx=_targetX-cx;
    float et=MIN(1,10*effectiveDt);
    cx+=dx*powf(et,3); // Cubic ease out
    _playerNode.position=SCNVector3Make(cx,_playerY,0);

    // Dynamic dust trail
    if(!_dustTrail){_dustTrail=[SCNNode node];_dustPS=[ParticleSystem dustTrail];[_dustTrail addParticleSystem:_dustPS];_dustTrail.position=SCNVector3Make(0,0.05,0.5);[_playerNode addChildNode:_dustTrail];}
    _dustPS.birthRate=_sliding?60:(_jumping?0:25);

    if(!_jumping&&!_sliding){_modelNode.position=SCNVector3Make(0,sin(_dist*5)*0.06,0);if(![_currentAnim isEqualToString:@"run"])[self anim:@"run"];}
    if(_jumping){_jumpVel-=20*dt;_playerY+=_jumpVel*effectiveDt;
        if(_playerY<=1){_playerY=1;_jumping=NO;_jumpVel=0;_modelNode.position=SCNVector3Make(0,0,0);
            SCNAction*sq=[SCNAction sequence:@[[SCNAction scaleTo:1.15 duration:0.04],[SCNAction scaleTo:1.0 duration:0.06]]];
            [_modelNode runAction:sq];
            SCNParticleSystem*ip=[ParticleSystem impactDirt];SCNNode*in=[SCNNode node];[in addParticleSystem:ip];in.position=SCNVector3Make(0,0.1,0);
            [_playerNode addChildNode:in];[self safeAfter:1 block:^{[in removeFromParentNode];}];
            if(![_currentAnim isEqualToString:@"run"])[self anim:@"run"];
        }_playerNode.position=SCNVector3Make(_playerNode.position.x,_playerY,_playerNode.position.z);
    }
    if(_sliding){_slideTimer-=dt;if(_slideTimer<=0){_sliding=NO;_modelNode.scale=SCNVector3Make(1,1,1);_playerY=1;if(![_currentAnim isEqualToString:@"run"])[self anim:@"run"];}}

    _stepTimer+=effectiveDt;
    if(!_jumping&&!_sliding&&_stepTimer>0.35){_stepTimer=0;[_audio playFootstep];}

    // ── Road ──
    for(SCNNode*ti in _roadTiles){ti.position=SCNVector3Make(ti.position.x,ti.position.y,ti.position.z+_speed*effectiveDt);if(ti.position.z>TL)ti.position=SCNVector3Make(ti.position.x,ti.position.y,ti.position.z-NT*TL);}

    // ── Spawn ──
    SCNNode*(^randTree)(void)=^SCNNode*{SCNNode*tr=[self spawnTree];int si=drand48()<0.5?-1:1;tr.position=SCNVector3Make(si*(3.2+drand48()*5.5),0,_playerNode.position.z-35);return tr;};
    [self spawnPool:&_nextTreeZ dt:effectiveDt max:35 pool:_trees minZ:-14 randZ:20 factory:randTree];
    SCNNode*(^randRock)(void)=^SCNNode*{SCNNode*r=[self spawnRock];r.position=SCNVector3Make(LX((int)(drand48()*3)-1),0.25,_playerNode.position.z-35);return r;};
    [self spawnPool:&_nextRockZ dt:effectiveDt max:8 pool:_rocks minZ:-18 randZ:30 factory:randRock];
    SCNNode*(^randCoin)(void)=^SCNNode*{SCNNode*c=[self spawnCoin];c.position=SCNVector3Make(LX((int)(drand48()*3)-1),1.2,_playerNode.position.z-28);return c;};
    [self spawnPool:&_nextCoinZ dt:effectiveDt max:12 pool:_coinObjs minZ:-4 randZ:10 factory:randCoin];
    SCNNode*(^randTurtle)(void)=^SCNNode*{SCNNode*tu=[self spawnTurtle];tu.position=SCNVector3Make(LX((int)(drand48()*3)-1),0.3,_playerNode.position.z-40);return tu;};
    [self spawnPool:&_nextTurtleZ dt:effectiveDt max:4 pool:_turtles minZ:-35 randZ:25 factory:randTurtle];
    SCNNode*(^randRing)(void)=^SCNNode*{SCNNode*ri=[self spawnRing];ri.position=SCNVector3Make(LX((int)(drand48()*3)-1),1,_playerNode.position.z-30);return ri;};
    [self spawnPool:&_nextRingZ dt:effectiveDt max:8 pool:_ringObjs minZ:-8 randZ:12 factory:randRing];
    SCNNode*(^randHeart)(void)=^SCNNode*{SCNNode*h=[self spawnHeart];h.position=SCNVector3Make(LX((int)(drand48()*3)-1),1.2,_playerNode.position.z-50);return h;};
    [self spawnPool:&_nextHeartZ dt:effectiveDt max:3 pool:_heartObjs minZ:-60 randZ:40 factory:randHeart];

    // Monkey Car (during food boost)
    if(_foodBoostT>0&&!_carActive){_carActive=YES;_carZ=-8;_carNode=[SCNNode node];SCNBox*bo=[SCNBox boxWithWidth:1.2 height:0.5 length:2 chamferRadius:0.1];SCNMaterial*m=[SCNMaterial material];m.lightingModelName=SCNLightingModelPhysicallyBased;m.diffuse.contents=[UIColor yellowColor];m.roughness.contents=@0.3;m.metalness.contents=@0.5;bo.materials=@[m];[_carNode setGeometry:bo];[_sc.rootNode addChildNode:_carNode];LOG(@"🚗 Monkey Car");}
    if(_carActive){_carZ+=_speed*effectiveDt*1.05;_carNode.position=SCNVector3Make(LX(1),0.3,_carZ);if(_carZ>8||_foodBoostT<=0){[_carNode removeFromParentNode];_carActive=NO;_carNode=nil;}}

    // ── Recycle ──
    [self recyclePool:_trees dt:effectiveDt];[self recyclePool:_rocks dt:effectiveDt];
    [self recyclePool:_turtles dt:effectiveDt];[self recyclePool:_ringObjs dt:effectiveDt];
    [self recyclePool:_heartObjs dt:effectiveDt];

    // ── Collisions ──
    [self collidePool:_rocks isEnemy:YES];[self collidePool:_turtles isEnemy:YES];

    // ── Collectibles ──
    [self collectCoins:effectiveDt];[self collectRings:effectiveDt];[self collectHearts:effectiveDt];

    // ── Projectiles ──
    [self updateProjectiles:effectiveDt];

    // ── HUD Update ──
    _scoreVal.text=[NSString stringWithFormat:@"%d",_score];
    _coinVal.text=[NSString stringWithFormat:@"%d",_coins];
    _ringVal.text=[NSString stringWithFormat:@"%d",_rings];
    NSMutableString*hearts=[NSMutableString string];
    for(int i=0;i<_lives;i++)[hearts appendString:@"❤️"];
    for(int i=_lives;i<5;i++)[hearts appendString:@"🖤"];
    if(_invTimer>0&&fmod(t,0.2)<0.1)_lifeVal.text=@"";
    else _lifeVal.text=hearts;

    _magTxt.text=[NSString stringWithFormat:@"🧲 %d",(int)_magnetT];
    CGRect mf=_magBarFill.frame;mf.size.width=(_magnetT>0?60*hs()*hw():0);_magBarFill.frame=mf;

    if(_foodBoostT>0){_foodBoostPill.hidden=NO;_foodBoostTime.text=[NSString stringWithFormat:@"%.1fs",_foodBoostT];CGRect ff=_foodBarFill.frame;ff.size.width=(_foodBoostT/10)*60*hs()*hw();_foodBarFill.frame=ff;}
    else _foodBoostPill.hidden=YES;

    if(_boostTimer>0){_boostPill.hidden=NO;_boostTime.text=[NSString stringWithFormat:@"%.1fs",_boostTimer];CGRect bf=_boostBarFill.frame;bf.size.width=(_boostTimer/8)*60*hs()*hw();_boostBarFill.frame=bf;_boostName.text=@"BOOST";}
    else _boostPill.hidden=YES;

    [self updateBulletsUI];[self updateBoostRowUI];
    [self updateDebugPanel:t];
    [self updateFPS:t];
}

// ═══════════════════════════════════════════════
// MARK: - Spawn Helper
// ═══════════════════════════════════════════════
-(void)spawnPool:(float*)nextZ dt:(float)dt max:(int)max pool:(NSMutableArray*)pool minZ:(float)minZ randZ:(float)randZ factory:(SCNNode*(^)(void))factory{
    *nextZ+=_speed*dt;
    float speedFactor=1+(_speed-10)/30;
    if(*nextZ>0&&pool.count<(int)(max*speedFactor)){
        *nextZ=(minZ-drand48()*randZ)/speedFactor;
        SCNNode*obj=factory();
        [_sc.rootNode addChildNode:obj];[pool addObject:obj];
    }
}

// ═══════════════════════════════════════════════
// MARK: - Recycle Pool
// ═══════════════════════════════════════════════
-(void)recyclePool:(NSMutableArray*)pool dt:(float)dt{
    NSMutableArray*rem=[NSMutableArray array];
    for(SCNNode*n in pool){n.position=SCNVector3Make(n.position.x,n.position.y,n.position.z+_speed*dt);if(n.position.z>8)[rem addObject:n];}
    for(SCNNode*n in rem){[n removeFromParentNode];[pool removeObject:n];}
}

// ═══════════════════════════════════════════════
// MARK: - Collision (ENEMY) — SAFE pattern
// ═══════════════════════════════════════════════
-(void)collidePool:(NSMutableArray*)pool isEnemy:(BOOL)isEnemy{
    NSMutableArray*tr=[NSMutableArray array];
    for(SCNNode*obj in pool){
        if(obj.position.z>5)continue;
        float ht=_sliding?0.45:0.65;
        if(fabsf(obj.position.x-_playerNode.position.x)<ht&&fabsf(obj.position.z)<0.6&&_invTimer<=0&&!_jumping&&_playerY<1.2){
            _lives--;_invTimer=1.5;[_audio playHit];
            NSString*tn=isEnemy?@"🪨":@"🐢";LOG(@"💥 %@! Lives:%d",tn,_lives);
            [self hitFX:obj.position];
            [obj removeFromParentNode];[tr addObject:obj];
            if(_lives<=0){LOG(@"💀 GAME OVER %dpts %d💰 %d💍",_score,_coins,_rings);[pool removeObjectsInArray:tr];[self gameOver];return;}
        }
    }
    [pool removeObjectsInArray:tr];
}

-(void)hitFX:(SCNVector3)pos{
    _hitCount++;
    SCNParticleSystem*hf=[ParticleSystem impactDirt];hf.birthRate=40+_hitCount*10;SCNNode*hn=[SCNNode node];[hn addParticleSystem:hf];hn.position=pos;
    [_sc.rootNode addChildNode:hn];[self safeAfter:1.5 block:^{[hn removeFromParentNode];}];
    SCNAction*fl=[SCNAction sequence:@[[SCNAction fadeOpacityTo:0.3 duration:0.06],[SCNAction fadeOpacityTo:1 duration:0.06],[SCNAction fadeOpacityTo:0.3 duration:0.06],[SCNAction fadeOpacityTo:1 duration:0.06]]];
    [_modelNode runAction:fl];
    [self shakeScreen:MIN(0.12,0.04+_hitCount*0.02)];
    // Blink player on hit
    SCNNode*pmod=_modelNode.childNodes.firstObject;pmod.hidden=YES;
    [self safeAfter:0.08 block:^{SCNNode*pm=_modelNode.childNodes.firstObject;pm.hidden=NO;
        [self safeAfter:0.08 block:^{SCNNode*pm2=_modelNode.childNodes.firstObject;pm2.hidden=YES;
            [self safeAfter:0.08 block:^{SCNNode*pm3=_modelNode.childNodes.firstObject;pm3.hidden=NO;}];}];}];
}

// ═══════════════════════════════════════════════
// MARK: - Collectibles — SAFE pattern
// ═══════════════════════════════════════════════
-(void)collectCoins:(float)dt{
    NSMutableArray*collected=[NSMutableArray array];
    for(SCNNode*c in _coinObjs){c.position=SCNVector3Make(c.position.x,c.position.y,c.position.z+_speed*dt);c.rotation=SCNVector4Make(0,1,0,c.rotation.w+dt*5);
        if(c.position.z>5){[collected addObject:c];continue;}
        float dx=fabsf(c.position.x-_playerNode.position.x),dz=fabsf(c.position.z);
        float range=_magnetT>0?3:0.7;
        if(dx<range&&dz<range){_coins++;[_audio playCoin];
            SCNAction*pu=[SCNAction sequence:@[[SCNAction scaleTo:1.5 duration:0.05],[SCNAction scaleTo:0 duration:0.1]]];
            [c runAction:pu];
            SCNParticleSystem*bu=[ParticleSystem coinBurst];SCNNode*bn=[SCNNode node];[bn addParticleSystem:bu];bn.position=c.position;[_sc.rootNode addChildNode:bn];[self safeAfter:1 block:^{[bn removeFromParentNode];}];
            [c removeFromParentNode];[collected addObject:c];
            if(_coins>0&&_coins%30==0&&!_hasBoost){_hasBoost=YES;_boostTimer=8;LOG(@"🍕 FOOD BOOST!");}
        }
    }
    [_coinObjs removeObjectsInArray:collected];
}

-(void)collectRings:(float)dt{
    NSMutableArray*collected=[NSMutableArray array];
    for(SCNNode*r in _ringObjs){r.position=SCNVector3Make(r.position.x,r.position.y,r.position.z+_speed*dt);r.rotation=SCNVector4Make(1,0,0,r.rotation.w+dt*4);
        if(r.position.z>5){[collected addObject:r];continue;}
        if(fabsf(r.position.x-_playerNode.position.x)<0.7&&fabsf(r.position.z)<0.7){_rings++;[_audio playCoin];[r removeFromParentNode];[collected addObject:r];}
    }
    [_ringObjs removeObjectsInArray:collected];
}

-(void)collectHearts:(float)dt{
    NSMutableArray*collected=[NSMutableArray array];
    for(SCNNode*h in _heartObjs){h.position=SCNVector3Make(h.position.x,h.position.y,h.position.z+_speed*dt);h.rotation=SCNVector4Make(0,1,0,h.rotation.w+dt*3);
        if(h.position.z>5){[collected addObject:h];continue;}
        if(fabsf(h.position.x-_playerNode.position.x)<0.7&&fabsf(h.position.z)<0.7&&_lives<MAX_LIVES){_lives++;[_audio playCoin];[h removeFromParentNode];[collected addObject:h];}
    }
    [_heartObjs removeObjectsInArray:collected];
}

// ═══════════════════════════════════════════════
// MARK: - Projectiles
// ═══════════════════════════════════════════════
-(void)updateProjectiles:(float)dt{
    NSMutableArray*torem=[NSMutableArray array];
    for(NSMutableDictionary*d in _projectiles){
        SCNNode*b=d[@"n"];float bz=[d[@"z"]floatValue];bz-=_speed*dt*2;d[@"z"]=@(bz);b.position=SCNVector3Make(b.position.x,b.position.y,bz);
        if(bz<-20){[b removeFromParentNode];[torem addObject:d];continue;}
        for(SCNNode*tu in _turtles){if(fabsf(b.position.x-tu.position.x)<0.6&&fabsf(bz-tu.position.z)<0.6){
            LOG(@"💥 Turtle killed!");
            SCNParticleSystem*xp=[ParticleSystem impactDirt];xp.birthRate=50;SCNNode*xn=[SCNNode node];[xn addParticleSystem:xp];xn.position=tu.position;
            [_sc.rootNode addChildNode:xn];[self safeAfter:0.8 block:^{[xn removeFromParentNode];}];
            [tu removeFromParentNode];[_turtles removeObject:tu];[b removeFromParentNode];[torem addObject:d];break;
        }}
    }
    for(id td in torem)[_projectiles removeObject:td];
}

// ═══════════════════════════════════════════════
// MARK: - Game Over
// ═══════════════════════════════════════════════
-(void)gameOver{
    _over=YES;_state=GameStateGameOver;
    _stopped=YES;[self anim:@"die"];[_audio playDeath];
    [self updateMainButton];
    SCNParticleSystem*dp=[ParticleSystem impactDirt];dp.birthRate=80;SCNNode*dn=[SCNNode node];[dn addParticleSystem:dp];dn.position=SCNVector3Make(0,0.8,0);[_playerNode addChildNode:dn];
}

// ═══════════════════════════════════════════════
// MARK: - Debug Panel Update
// ═══════════════════════════════════════════════
-(void)updateDebugPanel:(NSTimeInterval)t{
    if(_debugPanel.hidden)return;
    static int fc=0;static NSTimeInterval lf=0;fc++;if(t-lf>=0.5){_dbgFps.text=[NSString stringWithFormat:@"fps: %d",(int)(fc/(t-lf))];fc=0;lf=t;}
    _dbgCam.text=[NSString stringWithFormat:@"camera: %s",_viewMode==ViewModeBack?"BACK":_viewMode==ViewModeFPS?"FPS":"FRONT"];
    _dbgState.text=[NSString stringWithFormat:@"state: %s",_over?"GameOver":_stopped?"Stopped":"Playing"];
    _dbgEnt.text=[NSString stringWithFormat:@"entities: %d",(int)(_trees.count+_rocks.count+_coinObjs.count+_turtles.count)];
    _dbgLane.text=[NSString stringWithFormat:@"lane: %d",_lane];
    _dbgBoosts.text=[NSString stringWithFormat:@"boosts: food=%.1f mag=%.1f",_foodBoostT,_magnetT];
}

// ═══════════════════════════════════════════════
// MARK: - FPS
// ═══════════════════════════════════════════════
-(void)updateFPS:(NSTimeInterval)t{
    static int fc=0;static NSTimeInterval lf=0;
    fc++;if(t-lf>=0.5){int fps=(int)(fc/(t-lf));
        // Update FPS shown in debug or separate label
        fc=0;lf=t;
    }
}

// ═══════════════════════════════════════════════
// MARK: - Layout
// ═══════════════════════════════════════════════
-(void)viewDidLayoutSubviews{
    [super viewDidLayoutSubviews];
    _sv.frame=self.view.bounds;
}

-(BOOL)prefersStatusBarHidden{return YES;}

@end
