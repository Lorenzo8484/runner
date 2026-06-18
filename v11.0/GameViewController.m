#import <SceneKit/SceneKit.h>
#import <SpriteKit/SpriteKit.h>
#import "GLTFLoader.h"
#import "AudioEngine.h"
#import "ParticleSystem.h"

#define LANE_W 2.5f
#define LX(l) ((l)*LANE_W)
#define RW (LANE_W*3.6f)
#define TL 8.0f
#define NT 30
#define SHADOW_SZ 2048

#define LOG(fmt,...) [_lbuf appendFormat:@"[%.0f] " fmt @"\n",_dist,##__VA_ARGS__]; if(_logVis){_ltv.text=_lbuf;[_ltv scrollRangeToVisible:NSMakeRange(_lbuf.length-1,0)];}

// ─── PBR ────────────────────────────────────
static SCNMaterial *pbr(NSString *s){
    SCNMaterial *m=[SCNMaterial material];m.lightingModelName=SCNLightingModelPhysicallyBased;
    NSString *b=[NSString stringWithFormat:@"Assets/%@",s];NSBundle *bu=[NSBundle mainBundle];
    m.diffuse.contents=[UIImage imageWithContentsOfFile:[bu pathForResource:[b stringByAppendingString:@"/diff.jpg"] ofType:nil]];
    m.roughness.contents=[UIImage imageWithContentsOfFile:[bu pathForResource:[b stringByAppendingString:@"/rough.jpg"] ofType:nil]];
    m.normal.contents=[UIImage imageWithContentsOfFile:[bu pathForResource:[b stringByAppendingString:@"/normal.jpg"] ofType:nil]];
    NSString *ao=[bu pathForResource:[b stringByAppendingString:@"/ao.jpg"] ofType:nil];
    if(ao)m.ambientOcclusion.contents=[UIImage imageWithContentsOfFile:ao];
    m.diffuse.wrapS=SCNWrapModeRepeat;m.diffuse.wrapT=SCNWrapModeRepeat;m.roughness.wrapS=SCNWrapModeRepeat;m.roughness.wrapT=SCNWrapModeRepeat;m.normal.wrapS=SCNWrapModeRepeat;m.normal.wrapT=SCNWrapModeRepeat;m.metalness.contents=@0.0;return m;
}

// ─── GLASS PILL ─────────────────────────────
static UIVisualEffectView *glassPill(CGRect frame){
    UIBlurEffect *blur=[UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    UIVisualEffectView *ev=[[UIVisualEffectView alloc]initWithEffect:blur];ev.frame=frame;
    ev.layer.cornerRadius=frame.size.height/2;ev.layer.masksToBounds=YES;
    ev.layer.borderWidth=0.5;ev.layer.borderColor=[UIColor colorWithRed:0.4 green:0.6 blue:1 alpha:0.3].CGColor;
    return ev;
}

@interface GameViewController:UIViewController<SCNSceneRendererDelegate>
@end

@implementation GameViewController{
    SCNView *_sv;SCNNode *_cam,*_pn,*_pmn,*_rc;SCNNode *_sun,*_fill;
    int _ln;float _lx;BOOL _jp;float _jv,_py;BOOL _sl;float _st;
    int _sc,_li,_co,_ri;float _sp,_dist,_it;BOOL _go,_pa,_gs;
    float _fbt,_mt;BOOL _hfb,_hm;int _bul;float _stb;
    NSMutableArray *_rt,*_tr,*_rk,*_coo,*_tu,*_rio,*_heo,*_proj;
    float _nrz,_ncz,_ntz,_ntz2,_nriz,_nhez;SCNNode *_de,*_mcn;float _mcz;BOOL _mca;
    SCNNode *_ai,*_ar,*_aj,*_as,*_ad,*_ahi,*_awi,*_afi,*_asp,*_ama,*_atu,*_ada;
    NSString *_ca;NSArray *_tna,*_rna;
    // LOG
    NSMutableString *_lbuf;UIView *_lo;UITextView *_ltv;BOOL _logVis;int _fc;
    // HUD pills
    UIView *_hudWrap,*_scorePill,*_coinPill,*_ringPill,*_lifePill,*_boostPill;
    UILabel *_scoreVal,*_coinVal,*_ringVal,*_lifeVal,*_fpsLbl,*_spdLbl;
    UIButton *_logBtn,*_menuBtn;
    NSTimeInterval _lf;int _fpc;float _stp;NSTimeInterval _lt;
    UIView *_menu,*_set,*_shop;BOOL _menuVis;float _vol;
    NSMutableSet *_pendingTimers;
}

// ─── LIFECYCLE ──────────────────────────────
- (void)viewDidLoad{[super viewDidLoad];
    _pendingTimers=[NSMutableSet set];
    _lbuf=[NSMutableString string];LOG(@"🏁 v11 Glassmorphism Native");
    _tna=@[@"tree_default",@"tree_detailed",@"tree_oak",@"tree_fat",@"tree_cone",@"tree_tall",@"tree_small",@"tree_thin",@"tree_simple",@"tree_blocks",@"tree_pineDefaultA",@"tree_pineDefaultB",@"tree_pineTallA",@"tree_pineTallC",@"tree_pineRoundA",@"tree_pineRoundC",@"tree_pineSmallA",@"tree_pineSmallC",@"tree_palmDetailedShort",@"tree_palmDetailedTall"];
    _rna=@[@"cliff_rock",@"cliff_large_rock",@"cliff_half_rock",@"cliff_corner_rock",@"cliff_block_rock"];
    SCNScene *sc=[SCNScene scene];sc.background.contents=[self sky];sc.fogColor=[UIColor colorWithRed:0.6 green:0.7 blue:0.8 alpha:1];sc.fogStartDistance=50;sc.fogEndDistance=200;
    _sv=[[SCNView alloc]initWithFrame:self.view.bounds];_sv.scene=sc;_sv.delegate=self;_sv.preferredFramesPerSecond=60;_sv.antialiasingMode=SCNAntialiasingModeMultisampling4X;[self.view addSubview:_sv];
    [self lights];
    SCNCamera *c=[SCNCamera camera];c.zNear=0.2;c.zFar=300;c.fieldOfView=65;c.wantsHDR=YES;c.wantsExposureAdaptation=YES;c.exposureOffset=0.3;c.bloomIntensity=0.4;c.bloomThreshold=0.85;c.bloomBlurRadius=10;
    _cam=[SCNNode node];_cam.camera=c;_cam.position=SCNVector3Make(0,5.5,7);_cam.eulerAngles=SCNVector3Make(-0.5,0,0);[sc.rootNode addChildNode:_cam];
    SCNFloor *fl=[SCNFloor floor];fl.reflectivity=0;fl.materials=@[pbr(@"ground")];SCNNode *fn=[SCNNode nodeWithGeometry:fl];fn.position=SCNVector3Make(0,-0.05,-80);[sc.rootNode addChildNode:fn];
    [self loadPlayer];[self road];[self initState];[self setupHUD];[self setupGestures];[self setupLog];[self setupMenu];
    _gs=NO;_pa=YES;LOG(@"📋 Menu shown — tap PLAY");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,0.5*NSEC_PER_SEC),dispatch_get_main_queue(),^{[[AudioEngine shared]startAmbient];});
}
-(void)initState{_ln=0;_lx=0;_jp=0;_jv=0;_py=1;_sl=0;_st=0;_sc=0;_li=3;_co=0;_ri=0;_sp=10;_dist=0;_it=0;_go=0;_fbt=0;_mt=0;_hfb=0;_hm=0;_bul=5;_stb=0;_rt=[NSMutableArray array];_tr=[NSMutableArray array];_rk=[NSMutableArray array];_coo=[NSMutableArray array];_tu=[NSMutableArray array];_rio=[NSMutableArray array];_heo=[NSMutableArray array];_proj=[NSMutableArray array];_nrz=-15;_ncz=-6;_ntz=-8;_ntz2=-30;_nriz=-10;_nhez=-50;_lt=0;_fc=0;_mca=0;_vol=0.7;}

// ─── SKY / LIGHTS ───────────────────────────
-(id)sky{int h=256;CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();size_t bpr=h*4;uint8_t *d=(uint8_t*)malloc(h*bpr);for(int y=0;y<h;y++){float t=y/(float)h;for(int x=0;x<h;x++){int i=(y*h+x)*4;d[i]=(uint8_t)((0.35+t*0.3)*255);d[i+1]=(uint8_t)((0.55+t*0.25)*255);d[i+2]=(uint8_t)((0.75+t*0.2)*255);d[i+3]=255;}}CGContextRef ctx=CGBitmapContextCreate(d,h,h,8,bpr,cs,kCGImageAlphaPremultipliedLast);CGImageRef img=CGBitmapContextCreateImage(ctx);UIImage*ui=[UIImage imageWithCGImage:img];CGImageRelease(img);CGContextRelease(ctx);CGColorSpaceRelease(cs);free(d);return ui;}
-(void)lights{SCNLight *s=[SCNLight light];s.type=SCNLightTypeDirectional;s.color=[UIColor colorWithRed:1 green:0.95 blue:0.85 alpha:1];s.intensity=1200;s.temperature=5500;s.castsShadow=YES;s.shadowRadius=2;s.shadowMapSize=CGSizeMake(SHADOW_SZ,SHADOW_SZ);s.shadowMode=SCNShadowModeForward;_sun=[SCNNode node];_sun.light=s;_sun.position=SCNVector3Make(8,25,-10);[_sv.scene.rootNode addChildNode:_sun];SCNLight*f=[SCNLight light];f.type=SCNLightTypeAmbient;f.color=[UIColor colorWithRed:0.45 green:0.55 blue:0.7 alpha:1];f.intensity=400;_fill=[SCNNode node];_fill.light=f;[_sv.scene.rootNode addChildNode:_fill];}

// ─── PLAYER ──────────────────────────────────
-(void)loadPlayer{_pn=[SCNNode node];_pn.position=SCNVector3Make(0,_py,0);[_sv.scene.rootNode addChildNode:_pn];_pmn=[SCNNode node];[_pn addChildNode:_pmn];_ai=[GLTFLoader loadModel:@"DwarfIdle"];_ahi=[GLTFLoader loadModel:@"HappyIdle"];_awi=[GLTFLoader loadModel:@"WarriorIdle"];_ar=[GLTFLoader loadModel:@"running"];_afi=[GLTFLoader loadModel:@"RunningForwardFlip"];_aj=[GLTFLoader loadModel:@"jump"];_as=[GLTFLoader loadModel:@"slide"];_ad=[GLTFLoader loadModel:@"SideHitDie"];_asp=[GLTFLoader loadModel:@"spin dance"];_ama=[GLTFLoader loadModel:@"macarena"];_atu=[GLTFLoader loadModel:@"tut dance"];_ada=[GLTFLoader loadModel:@"HipHopDance"];[self anim:@"idle"];LOG(@"👤 14 anims");}
-(void)anim:(NSString*)n{if([_ca isEqualToString:n])return;_ca=n;for(SCNNode*c in _pmn.childNodes)[c removeFromParentNode];SCNNode*m=nil;if([n hasPrefix:@"idle"]){NSArray*a=@[_ai,_ahi,_awi];m=[a[arc4random_uniform(3)]clone];}else if([n isEqualToString:@"run"])m=[_ar clone];else if([n isEqualToString:@"jump"])m=[_aj clone];else if([n isEqualToString:@"slide"])m=[_as clone];else if([n isEqualToString:@"die"])m=[_ad clone];else if([n isEqualToString:@"flip"])m=[_afi clone];else if([n isEqualToString:@"spin"])m=[_asp clone];else if([n isEqualToString:@"macarena"])m=[_ama clone];else if([n isEqualToString:@"tut"])m=[_atu clone];else if([n isEqualToString:@"hiphop"])m=[_ada clone];if(m){m.scale=SCNVector3Make(0.8,0.8,0.8);[_pmn addChildNode:m];}}

// ─── ROAD ────────────────────────────────────
-(void)road{_rc=[SCNNode node];[_sv.scene.rootNode addChildNode:_rc];for(int i=0;i<NT;i++){SCNBox*b=[SCNBox boxWithWidth:RW height:0.15 length:TL chamferRadius:0.02];b.materials=@[pbr(@"road")];SCNNode*n=[SCNNode nodeWithGeometry:b];n.position=SCNVector3Make(0,-0.07,-i*TL);[_rc addChildNode:n];[_rt addObject:n];}}
-(SCNNode*)tree{NSString*n=_tna[arc4random_uniform((uint32_t)_tna.count)];SCNNode*t=[GLTFLoader loadModel:n];if(!t)t=[SCNNode node];t.scale=SCNVector3Make(0.7,0.7,0.7);return t;}
-(SCNNode*)rock{NSString*n=_rna[arc4random_uniform((uint32_t)_rna.count)];SCNNode*r=[GLTFLoader loadModel:n];if(!r)r=[SCNNode node];r.scale=SCNVector3Make(1.5,1,1.5);return r;}
-(SCNNode*)turtle{SCNNode*t=[SCNNode node];SCNSphere*s=[SCNSphere sphereWithRadius:0.35];SCNMaterial*m=[SCNMaterial material];m.lightingModelName=SCNLightingModelPhysicallyBased;m.diffuse.contents=[UIColor colorWithRed:0.12 green:0.42 blue:0.23 alpha:1];m.roughness.contents=@0.85;s.materials=@[m];SCNNode*sn=[SCNNode nodeWithGeometry:s];sn.scale=SCNVector3Make(1.2,0.75,1);sn.position=SCNVector3Make(0,0.35,0);[t addChildNode:sn];SCNSphere*h=[SCNSphere sphereWithRadius:0.16];SCNMaterial*hm=[SCNMaterial material];hm.lightingModelName=SCNLightingModelPhysicallyBased;hm.diffuse.contents=[UIColor colorWithRed:0.18 green:0.54 blue:0.3 alpha:1];h.materials=@[hm];SCNNode*hn=[SCNNode nodeWithGeometry:h];hn.position=SCNVector3Make(0,0.25,0.42);[t addChildNode:hn];return t;}
-(SCNNode*)ring{SCNTorus*r=[SCNTorus torusWithRingRadius:0.4 pipeRadius:0.04];SCNMaterial*m=[SCNMaterial material];m.lightingModelName=SCNLightingModelConstant;m.diffuse.contents=[UIColor colorWithRed:1 green:0.85 blue:0.1 alpha:1];m.emission.contents=[UIColor colorWithRed:0.5 green:0.4 blue:0 alpha:1];r.materials=@[m];SCNNode*n=[SCNNode nodeWithGeometry:r];n.eulerAngles=SCNVector3Make(M_PI_2,0,0);return n;}
-(SCNNode*)heart{SCNNode*h=[SCNNode node];SCNSphere*s=[SCNSphere sphereWithRadius:0.18];SCNMaterial*m=[SCNMaterial material];m.diffuse.contents=[UIColor redColor];m.emission.contents=[UIColor colorWithRed:0.3 green:0 blue:0 alpha:1];s.materials=@[m];SCNNode*n1=[SCNNode nodeWithGeometry:s];n1.position=SCNVector3Make(-0.13,0,0);SCNNode*n2=[SCNNode nodeWithGeometry:s];n2.position=SCNVector3Make(0.13,0,0);[h addChildNode:n1];[h addChildNode:n2];return h;}
-(SCNNode*)coin{SCNNode*c=[SCNNode node];SCNCylinder*b=[SCNCylinder cylinderWithRadius:0.3 height:0.06];SCNMaterial*cm=[SCNMaterial material];cm.lightingModelName=SCNLightingModelPhysicallyBased;cm.diffuse.contents=[UIColor colorWithRed:1 green:0.75 blue:0.1 alpha:1];cm.roughness.contents=@0.15;cm.metalness.contents=@1;b.materials=@[cm];SCNNode*bn=[SCNNode nodeWithGeometry:b];bn.eulerAngles=SCNVector3Make(M_PI_2,0,0);[c addChildNode:bn];SCNTorus*r=[SCNTorus torusWithRingRadius:0.33 pipeRadius:0.02];SCNMaterial*rm=[SCNMaterial material];rm.lightingModelName=SCNLightingModelConstant;rm.diffuse.contents=[UIColor colorWithRed:1 green:0.9 blue:0.2 alpha:1];r.materials=@[rm];SCNNode*rn=[SCNNode nodeWithGeometry:r];rn.eulerAngles=SCNVector3Make(M_PI_2,0,0);[c addChildNode:rn];return c;}
-(SCNNode*)bullet{SCNSphere*s=[SCNSphere sphereWithRadius:0.08];SCNMaterial*m=[SCNMaterial material];m.lightingModelName=SCNLightingModelConstant;m.diffuse.contents=[UIColor yellowColor];m.emission.contents=[UIColor colorWithRed:1 green:0.7 blue:0 alpha:1];s.materials=@[m];return [SCNNode nodeWithGeometry:s];}

// ─── SAFE DISPATCH (no retain cycle) ─────────
-(void)safeAfter:(float)sec block:(void(^)(void))block{
    __weak __typeof__(self) ws=self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,sec*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        __strong __typeof__(ws) ss=ws;if(ss)block();
    });
}

// ═══════════════ HUD GLASSMORPHISM ═══════════
-(void)setupHUD{
    float sw=self.view.bounds.size.width,sh=self.view.bounds.size.height;
    // ─── TOP-LEFT HUD pills ───
    _hudWrap=[[UIView alloc]initWithFrame:CGRectMake(8,40,MIN(230*1.4*0.7,sw-16),0)];_hudWrap.backgroundColor=[UIColor clearColor];[self.view addSubview:_hudWrap];
    float y=0,gap=8,pillH=32,pw=_hudWrap.frame.size.width;
    
    _scorePill=glassPill(CGRectMake(0,y,pw,pillH));[_hudWrap addSubview:_scorePill];
    _scoreVal=[self pillLabel:CGRectMake(36,0,pw-44,pillH) text:@"0" emoji:@"🏆"];[_scorePill addSubview:_scoreVal];
    y+=pillH+gap;
    
    _coinPill=glassPill(CGRectMake(0,y,pw,pillH));[_hudWrap addSubview:_coinPill];
    _coinVal=[self pillLabel:CGRectMake(36,0,pw-44,pillH) text:@"0" emoji:@"🪙"];[_coinPill addSubview:_coinVal];
    y+=pillH+gap;
    
    _ringPill=glassPill(CGRectMake(0,y,pw,pillH));[_hudWrap addSubview:_ringPill];
    _ringVal=[self pillLabel:CGRectMake(36,0,pw-44,pillH) text:@"0" emoji:@"💍"];[_ringPill addSubview:_ringVal];
    y+=pillH+gap;
    
    _lifePill=glassPill(CGRectMake(0,y,pw,pillH));[_hudWrap addSubview:_lifePill];
    _lifeVal=[self pillLabel:CGRectMake(36,0,pw-44,pillH) text:@"❤️❤️❤️" emoji:@""];[_lifePill addSubview:_lifeVal];
    y+=pillH+gap;
    
    _boostPill=glassPill(CGRectMake(0,y,pw,pillH));[_hudWrap addSubview:_boostPill];
    UILabel*bl=[self pillLabel:CGRectMake(8,0,pw-16,pillH) text:@"" emoji:@""];bl.textColor=[UIColor orangeColor];bl.font=[UIFont systemFontOfSize:12 weight:UIFontWeightBlack];[_boostPill addSubview:bl];_boostPill.tag=999;_boostPill.hidden=YES;
    
    // ─── TOP-RIGHT: Home + Settings ───
    UIView *tr=[[UIView alloc]initWithFrame:CGRectMake(sw-80,40,72,32)];tr.backgroundColor=[UIColor clearColor];[self.view addSubview:tr];
    UIView *hp=glassPill(CGRectMake(0,0,32,32));[tr addSubview:hp];
    UIButton *hb=[UIButton buttonWithType:UIButtonTypeSystem];hb.frame=CGRectMake(0,0,32,32);[hb setTitle:@"🏠" forState:UIControlStateNormal];hb.titleLabel.font=[UIFont systemFontOfSize:16];[hb addTarget:self action:@selector(tgMenu) forControlEvents:UIControlEventTouchUpInside];[hp addSubview:hb];
    UIView *sp=glassPill(CGRectMake(40,0,32,32));[tr addSubview:sp];
    UIButton *sb=[UIButton buttonWithType:UIButtonTypeSystem];sb.frame=CGRectMake(0,0,32,32);[sb setTitle:@"⚙️" forState:UIControlStateNormal];sb.titleLabel.font=[UIFont systemFontOfSize:16];[sb addTarget:self action:@selector(tgSettings) forControlEvents:UIControlEventTouchUpInside];[sp addSubview:sb];
    
    // ─── FPS (bottom-right) ───
    _fpsLbl=[[UILabel alloc]initWithFrame:CGRectMake(sw-60,sh-30,50,20)];_fpsLbl.text=@"60";_fpsLbl.textColor=[UIColor greenColor];_fpsLbl.font=[UIFont systemFontOfSize:11 weight:UIFontWeightBold];_fpsLbl.textAlignment=NSTextAlignmentRight;[self.view addSubview:_fpsLbl];
    
    // ─── BOTTOM BUTTONS ───
    float bw=60,bh=44,by=sh-70;
    UIView *bb=[[UIView alloc]initWithFrame:CGRectMake(sw/2-100,by,200,bh)];bb.backgroundColor=[UIColor clearColor];[self.view addSubview:bb];
    UIView *bp1=glassPill(CGRectMake(0,0,bw,bh));[bb addSubview:bp1];
    UIButton *b1=[UIButton buttonWithType:UIButtonTypeSystem];b1.frame=CGRectMake(0,0,bw,bh);[b1 setTitle:@"⚡" forState:UIControlStateNormal];b1.titleLabel.font=[UIFont systemFontOfSize:18];[b1 addTarget:self action:@selector(useBoost) forControlEvents:UIControlEventTouchUpInside];[bp1 addSubview:b1];
    UIView *bp2=glassPill(CGRectMake(70,0,bw,bh));[bb addSubview:bp2];
    UIButton *b2=[UIButton buttonWithType:UIButtonTypeSystem];b2.frame=CGRectMake(0,0,bw,bh);[b2 setTitle:@"💃" forState:UIControlStateNormal];b2.titleLabel.font=[UIFont systemFontOfSize:18];[b2 addTarget:self action:@selector(useDance) forControlEvents:UIControlEventTouchUpInside];[bp2 addSubview:b2];
    UIView *bp3=glassPill(CGRectMake(140,0,bw,bh));[bb addSubview:bp3];
    UIButton *b3=[UIButton buttonWithType:UIButtonTypeSystem];b3.frame=CGRectMake(0,0,bw,bh);[b3 setTitle:@"🔫" forState:UIControlStateNormal];b3.titleLabel.font=[UIFont systemFontOfSize:18];[b3 addTarget:self action:@selector(useShoot) forControlEvents:UIControlEventTouchUpInside];[bp3 addSubview:b3];
    
    _lf=CACurrentMediaTime();
}
-(UILabel*)pillLabel:(CGRect)frame text:(NSString*)t emoji:(NSString*)e{
    UILabel*l=[[UILabel alloc]initWithFrame:frame];l.text=e.length?[NSString stringWithFormat:@"%@ %@",e,t]:t;l.textColor=[UIColor colorWithRed:0.92 green:0.95 blue:1 alpha:1];l.font=[UIFont systemFontOfSize:13 weight:UIFontWeightBlack];return l;
}

// ─── LOG ─────────────────────────────────────
-(void)setupLog{_logVis=NO;
    _lo=[[UIView alloc]initWithFrame:self.view.bounds];_lo.backgroundColor=[[UIColor blackColor]colorWithAlphaComponent:0.92];_lo.hidden=YES;[self.view addSubview:_lo];
    _ltv=[[UITextView alloc]initWithFrame:CGRectMake(10,50,self.view.bounds.size.width-20,self.view.bounds.size.height-110)];_ltv.backgroundColor=[UIColor clearColor];_ltv.textColor=[UIColor greenColor];_ltv.font=[UIFont fontWithName:@"Menlo" size:10];_ltv.editable=NO;[_lo addSubview:_ltv];
    UIButton*cb=[UIButton buttonWithType:UIButtonTypeSystem];cb.frame=CGRectMake(10,8,80,36);cb.backgroundColor=[[UIColor whiteColor]colorWithAlphaComponent:0.15];cb.layer.cornerRadius=6;[cb setTitle:@"📋 Copy" forState:UIControlStateNormal];cb.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightBold];[cb addTarget:self action:@selector(cpLog) forControlEvents:UIControlEventTouchUpInside];[_lo addSubview:cb];
    UIButton*cl=[UIButton buttonWithType:UIButtonTypeSystem];cl.frame=CGRectMake(100,8,80,36);cl.backgroundColor=[[UIColor redColor]colorWithAlphaComponent:0.3];cl.layer.cornerRadius=6;[cl setTitle:@"🗑 Clear" forState:UIControlStateNormal];cl.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightBold];[cl addTarget:self action:@selector(clLog) forControlEvents:UIControlEventTouchUpInside];[_lo addSubview:cl];
    UIButton*xl=[UIButton buttonWithType:UIButtonTypeSystem];xl.frame=CGRectMake(self.view.bounds.size.width-60,8,50,36);xl.backgroundColor=[[UIColor whiteColor]colorWithAlphaComponent:0.15];xl.layer.cornerRadius=6;[xl setTitle:@"✕" forState:UIControlStateNormal];[xl addTarget:self action:@selector(tgLog) forControlEvents:UIControlEventTouchUpInside];[_lo addSubview:xl];
    _logBtn=[UIButton buttonWithType:UIButtonTypeSystem];_logBtn.frame=CGRectMake(self.view.bounds.size.width-70,self.view.bounds.size.height-100,60,36);_logBtn.backgroundColor=[[UIColor blackColor]colorWithAlphaComponent:0.7];_logBtn.layer.cornerRadius=8;[_logBtn setTitle:@"📋 LOG" forState:UIControlStateNormal];_logBtn.titleLabel.font=[UIFont systemFontOfSize:10 weight:UIFontWeightBold];[_logBtn addTarget:self action:@selector(tgLog) forControlEvents:UIControlEventTouchUpInside];[self.view addSubview:_logBtn];
}
-(void)tgLog{_logVis=!_logVis;_lo.hidden=!_logVis;if(_logVis){_ltv.text=_lbuf;[_ltv scrollRangeToVisible:NSMakeRange(_lbuf.length-1,0)];}}
-(void)cpLog{[[UIPasteboard generalPasteboard]setString:_lbuf];LOG(@"📋 Copied");}
-(void)clLog{[_lbuf setString:@""];_ltv.text=@"";LOG(@"🗑 Cleared");}

// ─── MENU ────────────────────────────────────
-(void)setupMenu{
    _menu=[[UIView alloc]initWithFrame:self.view.bounds];_menu.backgroundColor=[[UIColor blackColor]colorWithAlphaComponent:0.85];_menu.hidden=YES;[self.view addSubview:_menu];
    UILabel*t=[[UILabel alloc]initWithFrame:CGRectMake(0,100,self.view.bounds.size.width,40)];t.text=@"🏃 JUNGLE RUNNER";t.textColor=[UIColor greenColor];t.textAlignment=NSTextAlignmentCenter;t.font=[UIFont systemFontOfSize:28 weight:UIFontWeightBlack];[_menu addSubview:t];
    float y=170;for(int i=0;i<5;i++){NSString*title;int tag;switch(i){case 0:title=@"▶️  PLAY";tag=1;break;case 1:title=@"⚙️  SETTINGS";tag=2;break;case 2:title=@"🛒  SHOP";tag=3;break;case 3:title=@"💃  DANCE";tag=4;break;case 4:title=@"📋  LOG";tag=5;break;}
        UIView*pill=glassPill(CGRectMake(50,y,self.view.bounds.size.width-100,50));[_menu addSubview:pill];
        UIButton*b=[UIButton buttonWithType:UIButtonTypeSystem];b.frame=CGRectMake(0,0,self.view.bounds.size.width-100,50);b.tag=tag;[b setTitle:title forState:UIControlStateNormal];[b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];b.titleLabel.font=[UIFont systemFontOfSize:18 weight:UIFontWeightBold];[b addTarget:self action:@selector(menuAct:) forControlEvents:UIControlEventTouchUpInside];[pill addSubview:b];y+=65;
    }
}
-(void)tgMenu{_menuVis=!_menuVis;_menu.hidden=!_menuVis;_pa=_menuVis;LOG(@"📋 Menu %@",_menuVis?@"OPEN":@"CLOSED");}
-(void)tgSettings{/* placeholder */LOG(@"⚙️ Settings");}
-(void)menuAct:(UIButton*)b{switch(b.tag){case 1:[self tgMenu];_gs=YES;_pa=NO;_go=NO;[self anim:@"run"];LOG(@"▶️ PLAY");break;case 2:[self tgSettings];break;case 3:LOG(@"🛒 Shop");break;case 4:[self tgMenu];_gs=YES;_pa=NO;_go=NO;[self anim:@"spin"];LOG(@"💃 DANCE");break;case 5:[self tgMenu];[self tgLog];break;}}

// ─── BOTTOM BUTTON ACTIONS ───────────────────
-(void)useBoost{if(_go||_pa)return;if(!_hfb&&_co>=15){_co-=15;_hfb=YES;_fbt=8;LOG(@"🍕 BOOST! (cost 15💰, balance %d)",_co);}}
-(void)useDance{if(_go||_pa)return;NSArray*d=@[@"spin",@"macarena",@"tut",@"hiphop"];[self anim:d[arc4random_uniform(4)]];LOG(@"💃 Dance!");}
-(void)useShoot{if(_go||_pa||!_hfb||_bul<=0)return;_bul--;SCNNode*b=[self bullet];b.position=SCNVector3Make(_pn.position.x,_py+0.8,_pn.position.z-1);[_sv.scene.rootNode addChildNode:b];NSMutableDictionary*d=[@{@"n":b,@"z":@(_pn.position.z-1)}mutableCopy];[_proj addObject:d];LOG(@"🔫 Bullet! %d left",_bul);}

// ─── GESTURES ────────────────────────────────
-(void)setupGestures{for(int d=0;d<4;d++){UISwipeGestureRecognizer*sw=[[UISwipeGestureRecognizer alloc]initWithTarget:self action:@selector(swipe:)];sw.direction=1<<d;[_sv addGestureRecognizer:sw];}UITapGestureRecognizer*t=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(tap)];[_sv addGestureRecognizer:t];}
-(void)swipe:(UISwipeGestureRecognizer*)s{if(_go||_pa||_menuVis)return;if(s.direction==UISwipeGestureRecognizerDirectionLeft&&_ln>-1){_ln--;_lx=LX(_ln);}if(s.direction==UISwipeGestureRecognizerDirectionRight&&_ln<1){_ln++;_lx=LX(_ln);}if(s.direction==UISwipeGestureRecognizerDirectionUp&&!_jp&&!_sl){_jp=1;_jv=7.5;[self anim:@"jump"];[[AudioEngine shared]playJump];}if(s.direction==UISwipeGestureRecognizerDirectionDown&&!_jp&&!_sl){_sl=1;_st=0.7;_pmn.scale=SCNVector3Make(1,0.4,1);_py=0.5;[self anim:@"slide"];[[AudioEngine shared]playSlide];}}
-(void)tap{if(_go){[self restart];}}

// ═══════════════ GAME LOOP ═══════════════════
-(void)renderer:(id)s updateAtTime:(NSTimeInterval)t{if(_go||_pa)return;_fc++;
    float dt=(_lt==0)?0.016666:MIN(0.05,t-_lt);_lt=t;float ddt=dt*(1+(_stb>0?0.5:0));
    if(_stb>0){_stb-=dt;if(_stb<=0)_stb=0;}_it=MAX(0,_it-dt);_fbt=MAX(0,_fbt-dt);if(_fbt<=0&&_hfb){_hfb=0;LOG(@"🍕 Boost ended");}_mt=MAX(0,_mt-dt);if(_mt<=0&&_hm){_hm=0;}
    _dist+=_sp*ddt;_sc=(int)_dist;_sp=10+_dist/100;if(_sp>40)_sp=40;
    // Player
    float cx=_pn.position.x;cx+=(_lx-cx)*MIN(1,12*ddt);_pn.position=SCNVector3Make(cx,_py,0);
    if(!_jp&&!_sl){_pmn.position=SCNVector3Make(0,sin(_dist*5)*0.06,0);if(![_ca isEqualToString:@"run"])[self anim:@"run"];}
    if(_jp){_jv-=20*dt;_py+=_jv*ddt;if(_py<=1){_py=1;_jp=0;_jv=0;_pmn.position=SCNVector3Make(0,0,0);[self anim:@"run"];SCNParticleSystem*ip=[ParticleSystem impactDirt];SCNNode*in=[SCNNode node];[in addParticleSystem:ip];in.position=SCNVector3Make(0,0.1,0);[_pn addChildNode:in];[self safeAfter:1 block:^{[in removeFromParentNode];}];}_pn.position=SCNVector3Make(_pn.position.x,_py,_pn.position.z);}
    if(_sl){_st-=dt;if(_st<=0){_sl=0;_pmn.scale=SCNVector3Make(1,1,1);_py=1;[self anim:@"run"];}}
    _stp+=ddt;if(!_jp&&!_sl&&_stp>0.35){_stp=0;[[AudioEngine shared]playFootstep];}
    // Road
    for(SCNNode*ti in _rt){ti.position=SCNVector3Make(ti.position.x,ti.position.y,ti.position.z+_sp*ddt);if(ti.position.z>TL)ti.position=SCNVector3Make(ti.position.x,ti.position.y,ti.position.z-NT*TL);}
    // Spawns
    _ntz+=_sp*ddt;if(_ntz>0&&_tr.count<35){_ntz=-14-drand48()*20;SCNNode*tree=[self tree];int si=(drand48()<0.5)?-1:1;tree.position=SCNVector3Make(si*(3.2+drand48()*5.5),0,_pn.position.z-35);[_sv.scene.rootNode addChildNode:tree];[_tr addObject:tree];}[self rec:_tr dt:ddt lz:8];
    _nrz+=_sp*ddt;if(_nrz>0&&_rk.count<8){_nrz=-18-drand48()*30;int rl=(int)(drand48()*3)-1;SCNNode*rk=[self rock];rk.position=SCNVector3Make(LX(rl),0.25,_pn.position.z-35);[_sv.scene.rootNode addChildNode:rk];[_rk addObject:rk];}
    _ntz2+=_sp*ddt;if(_ntz2>0&&_tu.count<4){_ntz2=-35-drand48()*25;int tl=(int)(drand48()*3)-1;SCNNode*tu=[self turtle];tu.position=SCNVector3Make(LX(tl),0.3,_pn.position.z-40);[_sv.scene.rootNode addChildNode:tu];[_tu addObject:tu];}
    _nriz+=_sp*ddt;if(_nriz>0&&_rio.count<8){_nriz=-8-drand48()*12;int rl=(int)(drand48()*3)-1;SCNNode*r=[self ring];r.position=SCNVector3Make(LX(rl),1,_pn.position.z-30);[_sv.scene.rootNode addChildNode:r];[_rio addObject:r];}
    _nhez+=_sp*ddt;if(_nhez>0&&_heo.count<3){_nhez=-60-drand48()*40;int hl=(int)(drand48()*3)-1;SCNNode*h=[self heart];h.position=SCNVector3Make(LX(hl),1.2,_pn.position.z-50);[_sv.scene.rootNode addChildNode:h];[_heo addObject:h];}
    // Monkey Car
    if(_hfb&&!_mca&&_dist>30){_mcz=-8;_mcn=[SCNNode node];SCNBox*bo=[SCNBox boxWithWidth:1.2 height:0.5 length:2 chamferRadius:0.1];SCNMaterial*m=[SCNMaterial material];m.lightingModelName=SCNLightingModelPhysicallyBased;m.diffuse.contents=[UIColor yellowColor];m.roughness.contents=@0.3;m.metalness.contents=@0.5;bo.materials=@[m];[_mcn setGeometry:bo];[_sv.scene.rootNode addChildNode:_mcn];_mca=1;LOG(@"🚗 Monkey Car");}
    if(_mca){_mcz+=_sp*ddt*1.05;_mcn.position=SCNVector3Make(LX(1),0.3,_mcz);if(_mcz>8||_fbt<=0){[_mcn removeFromParentNode];_mca=0;}}
    // Recycle + Collisions
    [self rec:_rk dt:ddt lz:5];[self rec:_tu dt:ddt lz:5];[self rec:_rio dt:ddt lz:5];[self rec:_heo dt:ddt lz:5];
    [self colPool:_rk isRock:YES];[self colPool:_tu isRock:NO];
    // Coins
    _ncz+=_sp*ddt;if(_ncz>0&&_coo.count<12){_ncz=-4-drand48()*10;int cl=(int)(drand48()*3)-1;SCNNode*c=[self coin];c.position=SCNVector3Make(LX(cl),1.2,_pn.position.z-28);[_sv.scene.rootNode addChildNode:c];[_coo addObject:c];}
    NSMutableArray*dc=[NSMutableArray array];for(SCNNode*c in _coo){c.position=SCNVector3Make(c.position.x,c.position.y,c.position.z+_sp*ddt);c.rotation=SCNVector4Make(0,1,0,c.rotation.w+dt*5);if(c.position.z>5){[dc addObject:c];continue;}float dx=fabsf(c.position.x-_pn.position.x),dz=fabsf(c.position.z);if(dx<(_hm?3:0.7)&&dz<(_hm?3:0.7)){_co++;[[AudioEngine shared]playCoin];SCNParticleSystem*bu=[ParticleSystem coinBurst];SCNNode*bn=[SCNNode node];[bn addParticleSystem:bu];bn.position=c.position;[_sv.scene.rootNode addChildNode:bn];[self safeAfter:1 block:^{[bn removeFromParentNode];}];[c removeFromParentNode];[_coo removeObject:c];if(_co>0&&_co%30==0&&!_hfb){_hfb=1;_fbt=8;LOG(@"🍕 FOOD BOOST!");}}}
    for(SCNNode*c in dc){[c removeFromParentNode];[_coo removeObject:c];}
    // Rings
    NSMutableArray*dr2=[NSMutableArray array];for(SCNNode*r in _rio){r.position=SCNVector3Make(r.position.x,r.position.y,r.position.z+_sp*ddt);r.rotation=SCNVector4Make(1,0,0,r.rotation.w+dt*4);if(r.position.z>5){[dr2 addObject:r];continue;}if(fabsf(r.position.x-_pn.position.x)<0.7&&fabsf(r.position.z)<0.7){_ri++;[[AudioEngine shared]playCoin];[r removeFromParentNode];[_rio removeObject:r];}}for(SCNNode*r in dr2){[r removeFromParentNode];[_rio removeObject:r];}
    // Hearts
    NSMutableArray*dh=[NSMutableArray array];for(SCNNode*h in _heo){h.position=SCNVector3Make(h.position.x,h.position.y,h.position.z+_sp*ddt);h.rotation=SCNVector4Make(0,1,0,h.rotation.w+dt*3);if(h.position.z>5){[dh addObject:h];continue;}if(fabsf(h.position.x-_pn.position.x)<0.7&&fabsf(h.position.z)<0.7&&_li<5){_li++;[[AudioEngine shared]playCoin];[h removeFromParentNode];[_heo removeObject:h];}}for(SCNNode*h in dh){[h removeFromParentNode];[_heo removeObject:h];}
    // Bullets
    NSMutableArray*torem=[NSMutableArray array];for(NSMutableDictionary*d in _proj){SCNNode*b=d[@"n"];float bz=[d[@"z"]floatValue];bz-=_sp*ddt*2;d[@"z"]=@(bz);b.position=SCNVector3Make(b.position.x,b.position.y,bz);if(bz<-20){[b removeFromParentNode];[torem addObject:d];continue;}for(SCNNode*tu in _tu){if(fabsf(b.position.x-tu.position.x)<0.6&&fabsf(bz-tu.position.z)<0.6){LOG(@"💥 Turtle killed!");SCNParticleSystem*xp=[ParticleSystem impactDirt];xp.birthRate=50;SCNNode*xn=[SCNNode node];[xn addParticleSystem:xp];xn.position=tu.position;[_sv.scene.rootNode addChildNode:xn];[self safeAfter:0.8 block:^{[xn removeFromParentNode];}];[tu removeFromParentNode];[_tu removeObject:tu];[b removeFromParentNode];[torem addObject:d];break;}}}for(id td in torem)[_proj removeObject:td];
    // HUD
    _scoreVal.text=[NSString stringWithFormat:@"🏆 %d",_sc];_coinVal.text=[NSString stringWithFormat:@"🪙 %d",_co];_ringVal.text=[NSString stringWithFormat:@"💍 %d",_ri];
    NSMutableString*he=[NSMutableString string];for(int i=0;i<_li;i++)[he appendString:@"❤️"];if(_it>0&&fmod(t,0.2)<0.1)he=[NSMutableString string];_lifeVal.text=he;
    if(_hfb){UILabel*bl=(UILabel*)[_boostPill viewWithTag:999];bl.text=[NSString stringWithFormat:@"🍕 BOOST %.1fs",_fbt];_boostPill.hidden=NO;}else _boostPill.hidden=YES;
    _de.hidden=_jp;SCNParticleSystem*du=_de.particleSystems.firstObject;du.birthRate=_sl?60:25;
    [self updFPS:t];
}

// ─── HELPERS ─────────────────────────────────
-(void)rec:(NSMutableArray*)p dt:(float)dt lz:(float)lz{NSMutableArray*r=[NSMutableArray array];for(SCNNode*n in p){n.position=SCNVector3Make(n.position.x,n.position.y,n.position.z+_sp*dt);if(n.position.z>lz)[r addObject:n];}for(SCNNode*n in r){[n removeFromParentNode];[p removeObject:n];}}
-(void)colPool:(NSMutableArray*)pool isRock:(BOOL)isRock{for(SCNNode*obj in pool){if(obj.position.z>5)continue;float ht=_sl?0.45:0.65;if(fabsf(obj.position.x-_pn.position.x)<ht&&fabsf(obj.position.z)<0.6&&_it<=0&&!_jp&&_py<1.2){_li--;_it=1.5;[[AudioEngine shared]playHit];NSString*tn=isRock?@"🪨":@"🐢";LOG(@"💥 %@! Lives:%d",tn,_li);[self hitFX:obj.position];if(_li<=0){LOG(@"💀 GAME OVER %dpts %d💰 %d💍",_sc,_co,_ri);[self go];return;}[obj removeFromParentNode];[pool removeObject:obj];}}}
-(void)hitFX:(SCNVector3)pos{SCNParticleSystem*hf=[ParticleSystem impactDirt];SCNNode*hn=[SCNNode node];[hn addParticleSystem:hf];hn.position=pos;[_sv.scene.rootNode addChildNode:hn];[self safeAfter:1.5 block:^{[hn removeFromParentNode];}];SCNAction*fl=[SCNAction sequence:@[[SCNAction fadeOpacityTo:0.3 duration:0.06],[SCNAction fadeOpacityTo:1 duration:0.06],[SCNAction fadeOpacityTo:0.3 duration:0.06],[SCNAction fadeOpacityTo:1 duration:0.06]]];[_pmn runAction:fl];}
-(void)updFPS:(NSTimeInterval)t{_fpc++;if(t-_lf>=0.5){int fps=(int)(_fpc/(t-_lf));_fpsLbl.text=[NSString stringWithFormat:@"%d",fps];_fpsLbl.textColor=fps>50?[UIColor greenColor]:(fps>30?[UIColor yellowColor]:[UIColor redColor]);_fpc=0;_lf=t;}}
-(void)go{_go=1;[self anim:@"die"];[[AudioEngine shared]playDeath];SCNParticleSystem*dp=[ParticleSystem impactDirt];dp.birthRate=80;SCNNode*dn=[SCNNode node];[dn addParticleSystem:dp];dn.position=SCNVector3Make(0,0.8,0);[_pn addChildNode:dn];
    UIView*gover=glassPill(CGRectMake(self.view.bounds.size.width/2-100,self.view.bounds.size.height/2-40,200,80));[self.view addSubview:gover];gover.tag=777;
    UILabel*gl=[[UILabel alloc]initWithFrame:CGRectMake(0,10,200,30)];gl.text=@"GAME OVER";gl.textColor=[UIColor redColor];gl.textAlignment=NSTextAlignmentCenter;gl.font=[UIFont systemFontOfSize:22 weight:UIFontWeightBlack];[gover addSubview:gl];
    UILabel*rl=[[UILabel alloc]initWithFrame:CGRectMake(0,40,200,30)];rl.text=@"Tap to restart ⟳";rl.textColor=[UIColor whiteColor];rl.textAlignment=NSTextAlignmentCenter;rl.font=[UIFont systemFontOfSize:14];[gover addSubview:rl];
}
-(void)restart{for(SCNNode*n in _rk)[n removeFromParentNode];[_rk removeAllObjects];for(SCNNode*c in _coo)[c removeFromParentNode];[_coo removeAllObjects];for(SCNNode*t in _tu)[t removeFromParentNode];[_tu removeAllObjects];for(SCNNode*r in _rio)[r removeFromParentNode];[_rio removeAllObjects];for(SCNNode*h in _heo)[h removeFromParentNode];[_heo removeAllObjects];for(NSDictionary*d in _proj)[d[@"n"]removeFromParentNode];[_proj removeAllObjects];if(_mca){[_mcn removeFromParentNode];_mca=0;}
    [[self.view viewWithTag:777]removeFromSuperview];
    [self initState];_pn.position=SCNVector3Make(0,1,0);_pmn.scale=SCNVector3Make(1,1,1);_pmn.position=SCNVector3Make(0,0,0);[self anim:@"idle"];_fc=0;LOG(@"🔄 RESTARTED");
}
-(void)viewDidLayoutSubviews{_sv.frame=self.view.bounds;}
-(BOOL)prefersStatusBarHidden{return YES;}
@end
