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

#define LOG(fmt,...) [_log appendFormat:@"[%.0f] " fmt @"\n",_dist,##__VA_ARGS__]; if(_logVis){_ltv.text=_log;[_ltv scrollRangeToVisible:NSMakeRange(_log.length-1,0)];}

static SCNMaterial *pbr(NSString *s){
    SCNMaterial *m=[SCNMaterial material]; m.lightingModelName=SCNLightingModelPhysicallyBased;
    NSString *b=[NSString stringWithFormat:@"Assets/%@",s]; NSBundle *bu=[NSBundle mainBundle];
    m.diffuse.contents=[UIImage imageWithContentsOfFile:[bu pathForResource:[b stringByAppendingString:@"/diff.jpg"] ofType:nil]];
    m.roughness.contents=[UIImage imageWithContentsOfFile:[bu pathForResource:[b stringByAppendingString:@"/rough.jpg"] ofType:nil]];
    m.normal.contents=[UIImage imageWithContentsOfFile:[bu pathForResource:[b stringByAppendingString:@"/normal.jpg"] ofType:nil]];
    NSString *ao=[bu pathForResource:[b stringByAppendingString:@"/ao.jpg"] ofType:nil];
    if(ao)m.ambientOcclusion.contents=[UIImage imageWithContentsOfFile:ao];
    m.diffuse.wrapS=SCNWrapModeRepeat;m.diffuse.wrapT=SCNWrapModeRepeat;m.roughness.wrapS=SCNWrapModeRepeat;m.roughness.wrapT=SCNWrapModeRepeat;m.normal.wrapS=SCNWrapModeRepeat;m.normal.wrapT=SCNWrapModeRepeat;m.metalness.contents=@0.0;return m;
}

@interface GameViewController:UIViewController<SCNSceneRendererDelegate>
@end

@implementation GameViewController{
    SCNView *_sv;SCNNode *_cam,*_pn,*_pmn,*_rc;SCNNode *_sun,*_fill;
    int _ln;float _lx;BOOL _jp;float _jv,_py;BOOL _sl;float _st;
    int _sc,_li,_co,_ri;float _sp,_dist,_it;BOOL _go,_pa,_gs;
    float _fbt,_mt;BOOL _hfb,_hm;int _bullets;float _stb;
    NSMutableArray *_rt,*_tr,*_rk,*_coo,*_tu,*_rio,*_heo,*_proj;
    float _nrz,_ncz,_ntz,_ntz2,_nriz,_nhez;SCNNode *_de,*_mcn;float _mcz;BOOL _mca;
    SCNNode *_ai,*_ar,*_aj,*_as,*_ad,*_ahi,*_awi,*_afi,*_asp,*_ama,*_atu,*_ada;
    NSString *_ca;NSArray *_tna,*_rna;
    NSMutableString *_log;UIButton *_lb,*_cb,*_clb,*_xl;UIView *_lo;UITextView *_ltv;BOOL _logVis;int _fc;float _ct;
    SKView *_hv;SKScene *_hs;SKLabelNode *_slab,*_col,*_lil,*_fps,*_spd,*_ril,*_bol,*_bul;NSTimeInterval _lf;int _fpc;float _stp;NSTimeInterval _lt;
    UIView *_menu,*_set,*_shop;BOOL _menuVis,_setVis,_shopVis;float _vol;int _dbg;
}

- (void)viewDidLoad{[super viewDidLoad];
    _log=[NSMutableString string];LOG(@"🏁 Jungle Runner v10 — FULL NATIVE");
    _tna=@[@"tree_default",@"tree_detailed",@"tree_oak",@"tree_fat",@"tree_cone",@"tree_tall",@"tree_small",@"tree_thin",@"tree_simple",@"tree_blocks",@"tree_pineDefaultA",@"tree_pineDefaultB",@"tree_pineTallA",@"tree_pineTallC",@"tree_pineRoundA",@"tree_pineRoundC",@"tree_pineSmallA",@"tree_pineSmallC",@"tree_palmDetailedShort",@"tree_palmDetailedTall"];
    _rna=@[@"cliff_rock",@"cliff_large_rock",@"cliff_half_rock",@"cliff_corner_rock",@"cliff_block_rock"];
    SCNScene *sc=[SCNScene scene];sc.background.contents=[self sky];sc.fogColor=[UIColor colorWithRed:0.6 green:0.7 blue:0.8 alpha:1];sc.fogStartDistance=50;sc.fogEndDistance=200;
    _sv=[[SCNView alloc]initWithFrame:self.view.bounds];_sv.scene=sc;_sv.delegate=self;_sv.preferredFramesPerSecond=60;_sv.antialiasingMode=SCNAntialiasingModeMultisampling4X;[self.view addSubview:_sv];
    [self lights];
    SCNCamera *c=[SCNCamera camera];c.zNear=0.2;c.zFar=300;c.fieldOfView=65;c.wantsHDR=YES;c.wantsExposureAdaptation=YES;c.exposureOffset=0.3;c.bloomIntensity=0.4;c.bloomThreshold=0.85;c.bloomBlurRadius=10;
    _cam=[SCNNode node];_cam.camera=c;_cam.position=SCNVector3Make(0,5.5,7);_cam.eulerAngles=SCNVector3Make(-0.5,0,0);[sc.rootNode addChildNode:_cam];
    SCNFloor *fl=[SCNFloor floor];fl.reflectivity=0;fl.materials=@[pbr(@"ground")];SCNNode *fn=[SCNNode nodeWithGeometry:fl];fn.position=SCNVector3Make(0,-0.05,-80);[sc.rootNode addChildNode:fn];
    [self loadPlayer];[self road];
    _ln=0;_lx=0;_jp=0;_jv=0;_py=1;_sl=0;_st=0;_sc=0;_li=3;_co=0;_ri=0;_sp=10;_dist=0;_it=0;_go=0;_pa=0;_gs=0;_fbt=0;_mt=0;_hfb=0;_hm=0;_bullets=5;_stb=0;
    _rt=[NSMutableArray array];_tr=[NSMutableArray array];_rk=[NSMutableArray array];_coo=[NSMutableArray array];_tu=[NSMutableArray array];_rio=[NSMutableArray array];_heo=[NSMutableArray array];_proj=[NSMutableArray array];
    _nrz=-15;_ncz=-6;_ntz=-8;_ntz2=-30;_nriz=-10;_nhez=-50;_lt=0;_fc=0;_mca=0;_vol=0.7;_dbg=0;
    SCNParticleSystem *du=[ParticleSystem dustTrail];_de=[SCNNode node];[_de addParticleSystem:du];_de.position=SCNVector3Make(0,0.15,-0.3);[_pn addChildNode:_de];
    [self hud];[self gestures];[self logSys];[self setupMenu];[self setupSettings];[self setupShop];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,0.5*NSEC_PER_SEC),dispatch_get_main_queue(),^{[[AudioEngine shared]startAmbient];LOG(@"🔊 Audio on");});
}

// ─── SKY ────────────────────────────
-(id)sky{int h=256;CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();size_t bpr=h*4;uint8_t*d=(uint8_t*)malloc(h*bpr);for(int y=0;y<h;y++){float t=y/(float)h;for(int x=0;x<h;x++){int i=(y*h+x)*4;d[i]=(uint8_t)((0.35+t*0.3)*255);d[i+1]=(uint8_t)((0.55+t*0.25)*255);d[i+2]=(uint8_t)((0.75+t*0.2)*255);d[i+3]=255;}}CGContextRef ctx=CGBitmapContextCreate(d,h,h,8,bpr,cs,kCGImageAlphaPremultipliedLast);CGImageRef img=CGBitmapContextCreateImage(ctx);UIImage*ui=[UIImage imageWithCGImage:img];CGImageRelease(img);CGContextRelease(ctx);CGColorSpaceRelease(cs);free(d);return ui;}

// ─── LIGHTS ──────────────────────────
-(void)lights{SCNLight *s=[SCNLight light];s.type=SCNLightTypeDirectional;s.color=[UIColor colorWithRed:1 green:0.95 blue:0.85 alpha:1];s.intensity=1200;s.temperature=5500;s.castsShadow=YES;s.shadowRadius=2;s.shadowMapSize=CGSizeMake(SHADOW_SZ,SHADOW_SZ);s.shadowMode=SCNShadowModeForward;_sun=[SCNNode node];_sun.light=s;_sun.position=SCNVector3Make(8,25,-10);[_sv.scene.rootNode addChildNode:_sun];SCNLight*f=[SCNLight light];f.type=SCNLightTypeAmbient;f.color=[UIColor colorWithRed:0.45 green:0.55 blue:0.7 alpha:1];f.intensity=400;_fill=[SCNNode node];_fill.light=f;[_sv.scene.rootNode addChildNode:_fill];}

// ─── PLAYER ──────────────────────────
-(void)loadPlayer{_pn=[SCNNode node];_pn.position=SCNVector3Make(0,_py,0);[_sv.scene.rootNode addChildNode:_pn];_pmn=[SCNNode node];[_pn addChildNode:_pmn];
    _ai=[GLTFLoader loadModel:@"DwarfIdle"];_ahi=[GLTFLoader loadModel:@"HappyIdle"];_awi=[GLTFLoader loadModel:@"WarriorIdle"];
    _ar=[GLTFLoader loadModel:@"running"];_afi=[GLTFLoader loadModel:@"RunningForwardFlip"];
    _aj=[GLTFLoader loadModel:@"jump"];_as=[GLTFLoader loadModel:@"slide"];_ad=[GLTFLoader loadModel:@"SideHitDie"];
    _asp=[GLTFLoader loadModel:@"spin dance"];_ama=[GLTFLoader loadModel:@"macarena"];_atu=[GLTFLoader loadModel:@"tut dance"];
    _ada=[GLTFLoader loadModel:@"HipHopDance"];
    [self anim:@"idle"];LOG(@"👤 14 anims loaded");}
-(void)anim:(NSString*)n{if([_ca isEqualToString:n])return;_ca=n;for(SCNNode*c in _pmn.childNodes)[c removeFromParentNode];SCNNode*m=nil;
    if([n hasPrefix:@"idle"]){NSArray*a=@[_ai,_ahi,_awi];m=[a[arc4random_uniform(3)] clone];}
    else if([n isEqualToString:@"run"])m=[_ar clone];else if([n isEqualToString:@"jump"])m=[_aj clone];
    else if([n isEqualToString:@"slide"])m=[_as clone];else if([n isEqualToString:@"die"])m=[_ad clone];
    else if([n isEqualToString:@"flip"])m=[_afi clone];else if([n isEqualToString:@"spin"])m=[_asp clone];
    else if([n isEqualToString:@"macarena"])m=[_ama clone];else if([n isEqualToString:@"tut"])m=[_atu clone];
    else if([n isEqualToString:@"hiphop"])m=[_ada clone];
    if(m){m.scale=SCNVector3Make(0.8,0.8,0.8);[_pmn addChildNode:m];}}

// ─── ROAD ────────────────────────────
-(void)road{_rc=[SCNNode node];[_sv.scene.rootNode addChildNode:_rc];for(int i=0;i<NT;i++){SCNBox*b=[SCNBox boxWithWidth:RW height:0.15 length:TL chamferRadius:0.02];b.materials=@[pbr(@"road")];SCNNode*n=[SCNNode nodeWithGeometry:b];n.position=SCNVector3Make(0,-0.07,-i*TL);[_rc addChildNode:n];[_rt addObject:n];}LOG(@"🛤️ Road %d tiles",NT);}
-(SCNNode*)tree{NSString*n=_tna[arc4random_uniform((uint32_t)_tna.count)];SCNNode*t=[GLTFLoader loadModel:n];if(!t)t=[SCNNode node];t.scale=SCNVector3Make(0.7,0.7,0.7);return t;}
-(SCNNode*)rock{NSString*n=_rna[arc4random_uniform((uint32_t)_rna.count)];SCNNode*r=[GLTFLoader loadModel:n];if(!r)r=[SCNNode node];r.scale=SCNVector3Make(1.5,1,1.5);return r;}
-(SCNNode*)turtle{SCNNode*t=[SCNNode node];SCNSphere*s=[SCNSphere sphereWithRadius:0.35];SCNMaterial*m=[SCNMaterial material];m.lightingModelName=SCNLightingModelPhysicallyBased;m.diffuse.contents=[UIColor colorWithRed:0.12 green:0.42 blue:0.23 alpha:1];m.roughness.contents=@0.85;s.materials=@[m];SCNNode*sn=[SCNNode nodeWithGeometry:s];sn.scale=SCNVector3Make(1.2,0.75,1);sn.position=SCNVector3Make(0,0.35,0);[t addChildNode:sn];SCNSphere*h=[SCNSphere sphereWithRadius:0.16];SCNMaterial*hm=[SCNMaterial material];hm.lightingModelName=SCNLightingModelPhysicallyBased;hm.diffuse.contents=[UIColor colorWithRed:0.18 green:0.54 blue:0.3 alpha:1];h.materials=@[hm];SCNNode*hn=[SCNNode nodeWithGeometry:h];hn.position=SCNVector3Make(0,0.25,0.42);[t addChildNode:hn];return t;}
-(SCNNode*)ring{SCNTorus*r=[SCNTorus torusWithRingRadius:0.4 pipeRadius:0.04];SCNMaterial*m=[SCNMaterial material];m.lightingModelName=SCNLightingModelConstant;m.diffuse.contents=[UIColor colorWithRed:1 green:0.85 blue:0.1 alpha:1];m.emission.contents=[UIColor colorWithRed:0.5 green:0.4 blue:0 alpha:1];r.materials=@[m];SCNNode*n=[SCNNode nodeWithGeometry:r];n.eulerAngles=SCNVector3Make(M_PI_2,0,0);return n;}
-(SCNNode*)heart{SCNNode*h=[SCNNode node];SCNSphere*s=[SCNSphere sphereWithRadius:0.18];SCNMaterial*m=[SCNMaterial material];m.diffuse.contents=[UIColor redColor];m.emission.contents=[UIColor colorWithRed:0.3 green:0 blue:0 alpha:1];s.materials=@[m];SCNNode*n1=[SCNNode nodeWithGeometry:s];n1.position=SCNVector3Make(-0.13,0,0);SCNNode*n2=[SCNNode nodeWithGeometry:s];n2.position=SCNVector3Make(0.13,0,0);[h addChildNode:n1];[h addChildNode:n2];return h;}
-(SCNNode*)coin{SCNNode*c=[SCNNode node];SCNCylinder*b=[SCNCylinder cylinderWithRadius:0.3 height:0.06];SCNMaterial*cm=[SCNMaterial material];cm.lightingModelName=SCNLightingModelPhysicallyBased;cm.diffuse.contents=[UIColor colorWithRed:1 green:0.75 blue:0.1 alpha:1];cm.roughness.contents=@0.15;cm.metalness.contents=@1;b.materials=@[cm];SCNNode*bn=[SCNNode nodeWithGeometry:b];bn.eulerAngles=SCNVector3Make(M_PI_2,0,0);[c addChildNode:bn];SCNTorus*r=[SCNTorus torusWithRingRadius:0.33 pipeRadius:0.02];SCNMaterial*rm=[SCNMaterial material];rm.lightingModelName=SCNLightingModelConstant;rm.diffuse.contents=[UIColor colorWithRed:1 green:0.9 blue:0.2 alpha:1];r.materials=@[rm];SCNNode*rn=[SCNNode nodeWithGeometry:r];rn.eulerAngles=SCNVector3Make(M_PI_2,0,0);[c addChildNode:rn];return c;}
-(SCNNode*)bullet{SCNSphere*s=[SCNSphere sphereWithRadius:0.08];SCNMaterial*m=[SCNMaterial material];m.lightingModelName=SCNLightingModelConstant;m.diffuse.contents=[UIColor yellowColor];m.emission.contents=[UIColor colorWithRed:1 green:0.7 blue:0 alpha:1];s.materials=@[m];SCNNode*n=[SCNNode nodeWithGeometry:s];return n;}

// ─── LOG ─────────────────────────────
-(void)logSys{_logVis=0;_lb=[UIButton buttonWithType:UIButtonTypeSystem];_lb.frame=CGRectMake(self.view.bounds.size.width-70,self.view.bounds.size.height-90,60,36);_lb.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin|UIViewAutoresizingFlexibleTopMargin;_lb.backgroundColor=[[UIColor blackColor]colorWithAlphaComponent:0.7];_lb.layer.cornerRadius=8;[_lb setTitle:@"📋 LOG" forState:UIControlStateNormal];_lb.titleLabel.font=[UIFont systemFontOfSize:10 weight:UIFontWeightBold];[_lb addTarget:self action:@selector(tgLog) forControlEvents:UIControlEventTouchUpInside];[self.view addSubview:_lb];
    _lo=[[UIView alloc]initWithFrame:self.view.bounds];_lo.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;_lo.backgroundColor=[[UIColor blackColor]colorWithAlphaComponent:0.92];_lo.hidden=YES;[self.view addSubview:_lo];
    _ltv=[[UITextView alloc]initWithFrame:CGRectMake(10,50,self.view.bounds.size.width-20,self.view.bounds.size.height-110)];_ltv.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;_ltv.backgroundColor=[UIColor clearColor];_ltv.textColor=[UIColor greenColor];_ltv.font=[UIFont fontWithName:@"Menlo" size:10];_ltv.editable=NO;[_lo addSubview:_ltv];
    _cb=[UIButton buttonWithType:UIButtonTypeSystem];_cb.frame=CGRectMake(10,8,80,36);_cb.backgroundColor=[[UIColor whiteColor]colorWithAlphaComponent:0.15];_cb.layer.cornerRadius=6;[_cb setTitle:@"📋 Copy" forState:UIControlStateNormal];_cb.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightBold];[_cb addTarget:self action:@selector(cpLog) forControlEvents:UIControlEventTouchUpInside];[_lo addSubview:_cb];
    _clb=[UIButton buttonWithType:UIButtonTypeSystem];_clb.frame=CGRectMake(100,8,80,36);_clb.backgroundColor=[[UIColor redColor]colorWithAlphaComponent:0.3];_clb.layer.cornerRadius=6;[_clb setTitle:@"🗑 Clear" forState:UIControlStateNormal];_clb.titleLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightBold];[_clb addTarget:self action:@selector(clLog) forControlEvents:UIControlEventTouchUpInside];[_lo addSubview:_clb];
    _xl=[UIButton buttonWithType:UIButtonTypeSystem];_xl.frame=CGRectMake(self.view.bounds.size.width-60,8,50,36);_xl.autoresizingMask=UIViewAutoresizingFlexibleLeftMargin;_xl.backgroundColor=[[UIColor whiteColor]colorWithAlphaComponent:0.15];_xl.layer.cornerRadius=6;[_xl setTitle:@"✕" forState:UIControlStateNormal];_xl.titleLabel.font=[UIFont systemFontOfSize:16 weight:UIFontWeightBold];[_xl addTarget:self action:@selector(tgLog) forControlEvents:UIControlEventTouchUpInside];[_lo addSubview:_xl];
    LOG(@"📋 Log ready");}
-(void)tgLog{_logVis=!_logVis;_lo.hidden=!_logVis;if(_logVis){_ltv.text=_log;[_ltv scrollRangeToVisible:NSMakeRange(_log.length-1,0)];}}
-(void)cpLog{[[UIPasteboard generalPasteboard]setString:_log];LOG(@"📋 Copied %lu chars",(unsigned long)_log.length);}
-(void)clLog{[_log setString:@""];_ltv.text=@"";LOG(@"🗑 Cleared");}

// ─── MENU ────────────────────────────
-(UIButton*)mkBtn:(NSString*)t y:(float)y tag:(int)tag col:(UIColor*)col{
    UIButton*b=[UIButton buttonWithType:UIButtonTypeSystem];b.frame=CGRectMake(40,y,self.view.bounds.size.width-80,50);
    b.backgroundColor=col;b.layer.cornerRadius=12;b.tag=tag;[b setTitle:t forState:UIControlStateNormal];
    b.titleLabel.font=[UIFont systemFontOfSize:18 weight:UIFontWeightBold];[b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [b addTarget:self action:@selector(menuTap:) forControlEvents:UIControlEventTouchUpInside];return b;
}
-(void)setupMenu{_menu=[[UIView alloc]initWithFrame:self.view.bounds];_menu.backgroundColor=[[UIColor blackColor]colorWithAlphaComponent:0.85];_menu.hidden=YES;[self.view addSubview:_menu];
    UILabel*t=[[UILabel alloc]initWithFrame:CGRectMake(0,80,self.view.bounds.size.width,40)];t.text=@"🏃 JUNGLE RUNNER";t.textColor=[UIColor greenColor];t.textAlignment=NSTextAlignmentCenter;t.font=[UIFont systemFontOfSize:26 weight:UIFontWeightBlack];[_menu addSubview:t];
    [_menu addSubview:[self mkBtn:@"▶️  PLAY" y:150 tag:1 col:[[UIColor systemGreenColor]colorWithAlphaComponent:0.7]]];
    [_menu addSubview:[self mkBtn:@"⚙️  SETTINGS" y:215 tag:2 col:[[UIColor systemBlueColor]colorWithAlphaComponent:0.6]]];
    [_menu addSubview:[self mkBtn:@"🛒  SHOP" y:280 tag:3 col:[[UIColor systemOrangeColor]colorWithAlphaComponent:0.6]]];
    [_menu addSubview:[self mkBtn:@"💃  DANCE" y:345 tag:4 col:[[UIColor systemPurpleColor]colorWithAlphaComponent:0.6]]];
    UIButton*menuBtn=[UIButton buttonWithType:UIButtonTypeSystem];menuBtn.frame=CGRectMake(10,50,50,36);menuBtn.backgroundColor=[[UIColor blackColor]colorWithAlphaComponent:0.7];menuBtn.layer.cornerRadius=8;[menuBtn setTitle:@"☰" forState:UIControlStateNormal];menuBtn.titleLabel.font=[UIFont systemFontOfSize:20 weight:UIFontWeightBold];[menuBtn addTarget:self action:@selector(tgMenu) forControlEvents:UIControlEventTouchUpInside];[self.view addSubview:menuBtn];}
-(void)tgMenu{_menuVis=!_menuVis;_menu.hidden=!_menuVis;_pa=_menuVis;LOG(@"📋 Menu %@",_menuVis?@"OPEN":@"CLOSED");}
-(void)menuTap:(UIButton*)b{
    switch(b.tag){
        case 1:[self tgMenu];_gs=YES;_pa=NO;_go=NO;[self anim:@"run"];LOG(@"▶️ PLAY");break;
        case 2:_setVis=YES;_set.hidden=NO;LOG(@"⚙️ Settings open");break;
        case 3:_shopVis=YES;_shop.hidden=NO;[self updateShopLabels];LOG(@"🛒 Shop open");break;
        case 4:_gs=YES;_pa=NO;_go=NO;[self tgMenu];[self anim:@"spin"];LOG(@"💃 DANCE mode");break;
    }
}

// ─── SETTINGS ────────────────────────
-(void)setupSettings{
    _set=[[UIView alloc]initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,self.view.bounds.size.height)];_set.backgroundColor=[[UIColor blackColor]colorWithAlphaComponent:0.9];_set.hidden=YES;[self.view addSubview:_set];
    UILabel*t=[[UILabel alloc]initWithFrame:CGRectMake(0,50,self.view.bounds.size.width,30)];t.text=@"⚙️ SETTINGS";t.textColor=[UIColor whiteColor];t.textAlignment=NSTextAlignmentCenter;t.font=[UIFont systemFontOfSize:22 weight:UIFontWeightBold];[_set addSubview:t];
    UISlider*vol=[[UISlider alloc]initWithFrame:CGRectMake(40,100,self.view.bounds.size.width-80,30)];vol.value=_vol;[vol addTarget:self action:@selector(volChanged:) forControlEvents:UIControlEventValueChanged];[_set addSubview:vol];
    UILabel*vl=[[UILabel alloc]initWithFrame:CGRectMake(40,70,200,25)];vl.text=@"🔊 Volume";vl.textColor=[UIColor whiteColor];vl.font=[UIFont systemFontOfSize:14];[_set addSubview:vl];
    UISwitch*dbg=[[UISwitch alloc]initWithFrame:CGRectMake(40,150,50,30)];dbg.on=_dbg;[dbg addTarget:self action:@selector(dbgChanged:) forControlEvents:UIControlEventValueChanged];[_set addSubview:dbg];
    UILabel*dl=[[UILabel alloc]initWithFrame:CGRectMake(40,120,200,25)];dl.text=@"🐛 Debug mode";dl.textColor=[UIColor whiteColor];dl.font=[UIFont systemFontOfSize:14];[_set addSubview:dl];
    UIButton*close=[UIButton buttonWithType:UIButtonTypeSystem];close.frame=CGRectMake(self.view.bounds.size.width/2-50,200,100,40);[close setTitle:@"CLOSE" forState:UIControlStateNormal];close.backgroundColor=[UIColor systemBlueColor];close.layer.cornerRadius=8;[close addTarget:self action:@selector(closeSettings) forControlEvents:UIControlEventTouchUpInside];[_set addSubview:close];
}
-(void)volChanged:(UISlider*)s{_vol=s.value;LOG(@"🔊 Volume: %.0f%%",_vol*100);}
-(void)dbgChanged:(UISwitch*)s{_dbg=s.on;LOG(@"🐛 Debug: %@",_dbg?@"ON":@"OFF");}
-(void)closeSettings{_setVis=NO;_set.hidden=YES;LOG(@"⚙️ Settings closed");}

// ─── SHOP ────────────────────────────
-(void)setupShop{
    _shop=[[UIView alloc]initWithFrame:self.view.bounds];_shop.backgroundColor=[[UIColor blackColor]colorWithAlphaComponent:0.9];_shop.hidden=YES;[self.view addSubview:_shop];
    UILabel*t=[[UILabel alloc]initWithFrame:CGRectMake(0,50,self.view.bounds.size.width,30)];t.text=@"🛒 SHOP";t.textColor=[UIColor orangeColor];t.textAlignment=NSTextAlignmentCenter;t.font=[UIFont systemFontOfSize:22 weight:UIFontWeightBold];[_shop addSubview:t];
    [_shop addSubview:[self shopBtn:@"🧲 Magnet (5s)" y:100 tag:10 cost:15]];
    [_shop addSubview:[self shopBtn:@"🛡️ Shield (8s)" y:160 tag:11 cost:25]];
    [_shop addSubview:[self shopBtn:@"⚡ Speed (10s)" y:220 tag:12 cost:20]];
    [_shop addSubview:[self shopBtn:@"🔫 +5 Bullets" y:280 tag:13 cost:30]];
    UIButton*close=[UIButton buttonWithType:UIButtonTypeSystem];close.frame=CGRectMake(self.view.bounds.size.width/2-50,350,100,40);[close setTitle:@"CLOSE" forState:UIControlStateNormal];close.backgroundColor=[UIColor systemRedColor];close.layer.cornerRadius=8;[close addTarget:self action:@selector(closeShop) forControlEvents:UIControlEventTouchUpInside];[_shop addSubview:close];
}
-(UIButton*)shopBtn:(NSString*)t y:(float)y tag:(int)tag cost:(int)cost{
    UIButton*b=[UIButton buttonWithType:UIButtonTypeSystem];b.frame=CGRectMake(40,y,self.view.bounds.size.width-80,45);b.tag=tag;b.backgroundColor=[[UIColor whiteColor]colorWithAlphaComponent:0.15];b.layer.cornerRadius=10;[b setTitle:[NSString stringWithFormat:@"%@ — 💰%d",t,cost] forState:UIControlStateNormal];b.titleLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightBold];[b addTarget:self action:@selector(shopBuy:) forControlEvents:UIControlEventTouchUpInside];return b;
}
-(void)updateShopLabels{
    for(UIView*v in _shop.subviews)if([v isKindOfClass:[UIButton class]]&&v.tag>=10){
        UIButton*b=(UIButton*)v;int cost=0;
        switch(b.tag){case 10:cost=15;break;case 11:cost=25;break;case 12:cost=20;break;case 13:cost=30;break;}
        b.enabled=_co>=cost;b.alpha=b.enabled?1:0.4;
    }
}
-(void)shopBuy:(UIButton*)b{
    int cost=0;NSString*item=@"";
    switch(b.tag){case 10:cost=15;item=@"🧲 Magnet";break;case 11:cost=25;item=@"🛡️ Shield";break;case 12:cost=20;item=@"⚡ Speed";break;case 13:cost=30;item=@"🔫 Bullets";break;}
    if(_co>=cost){_co-=cost;LOG(@"🛒 Bought %@ for %d coins (balance: %d)",item,cost,_co);
        switch(b.tag){case 10:_hm=YES;_mt=5;break;case 11:_it=8;break;case 12:_stb=10;break;case 13:_bullets+=5;break;}
        [self updateShopLabels];
    }
}
-(void)closeShop{_shopVis=NO;_shop.hidden=YES;}

// ─── HUD ─────────────────────────────
-(void)hud{_hv=[[SKView alloc]initWithFrame:self.view.bounds];_hv.backgroundColor=[UIColor clearColor];_hv.allowsTransparency=YES;[self.view addSubview:_hv];_hs=[SKScene sceneWithSize:self.view.bounds.size];_hs.scaleMode=SKSceneScaleModeResizeFill;[_hv presentScene:_hs];
    CGSize s=_hs.size;float p=25;
    _slab=[self hl:@"0" sz:28 c:[SKColor whiteColor]];_slab.position=CGPointMake(p,s.height-45);_slab.horizontalAlignmentMode=SKLabelHorizontalAlignmentModeLeft;[_hs addChild:_slab];
    _col=[self hl:@"🪙 0" sz:22 c:[SKColor colorWithRed:1 green:0.85 blue:0.2 alpha:1]];_col.position=CGPointMake(p,s.height-75);_col.horizontalAlignmentMode=SKLabelHorizontalAlignmentModeLeft;[_hs addChild:_col];
    _ril=[self hl:@"💍 0" sz:22 c:[SKColor colorWithRed:0.2 green:0.7 blue:1 alpha:1]];_ril.position=CGPointMake(p,s.height-105);_ril.horizontalAlignmentMode=SKLabelHorizontalAlignmentModeLeft;[_hs addChild:_ril];
    _spd=[self hl:@"⚡ 10" sz:14 c:[SKColor colorWithRed:0.6 green:0.9 blue:1 alpha:1]];_spd.position=CGPointMake(p,s.height-128);_spd.horizontalAlignmentMode=SKLabelHorizontalAlignmentModeLeft;[_hs addChild:_spd];
    _bol=[self hl:@"" sz:16 c:[SKColor orangeColor]];_bol.position=CGPointMake(s.width/2,s.height-150);[_hs addChild:_bol];
    _bul=[self hl:@"" sz:14 c:[SKColor yellowColor]];_bul.position=CGPointMake(p,s.height-150);_bul.horizontalAlignmentMode=SKLabelHorizontalAlignmentModeLeft;[_hs addChild:_bul];
    _lil=[self hl:@"❤️❤️❤️" sz:22 c:[SKColor redColor]];_lil.position=CGPointMake(s.width-p,s.height-45);_lil.horizontalAlignmentMode=SKLabelHorizontalAlignmentModeRight;[_hs addChild:_lil];
    _fps=[self hl:@"60" sz:12 c:[SKColor greenColor]];_fps.position=CGPointMake(s.width-p,22);_fps.horizontalAlignmentMode=SKLabelHorizontalAlignmentModeRight;[_hs addChild:_fps];_lf=CACurrentMediaTime();}
-(SKLabelNode*)hl:(NSString*)t sz:(float)s c:(SKColor*)c{SKLabelNode*l=[SKLabelNode labelNodeWithFontNamed:@"HelveticaNeue-Bold"];l.text=t;l.fontSize=s;l.fontColor=c;return l;}

// ─── GESTURES ────────────────────────
-(void)gestures{for(int d=0;d<4;d++){UISwipeGestureRecognizer*sw=[[UISwipeGestureRecognizer alloc]initWithTarget:self action:@selector(swipe:)];sw.direction=1<<d;[_sv addGestureRecognizer:sw];}
    UITapGestureRecognizer*t=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(tap)];[_sv addGestureRecognizer:t];
    UILongPressGestureRecognizer*lp=[[UILongPressGestureRecognizer alloc]initWithTarget:self action:@selector(shoot)];lp.minimumPressDuration=0.3;[_sv addGestureRecognizer:lp];}
-(void)swipe:(UISwipeGestureRecognizer*)s{if(_go||_pa||_menuVis)return;
    if(s.direction==UISwipeGestureRecognizerDirectionLeft&&_ln>-1){_ln--;_lx=LX(_ln);LOG(@"⬅️ L%d",_ln);}
    if(s.direction==UISwipeGestureRecognizerDirectionRight&&_ln<1){_ln++;_lx=LX(_ln);LOG(@"➡️ L%d",_ln);}
    if(s.direction==UISwipeGestureRecognizerDirectionUp&&!_jp&&!_sl){_jp=1;_jv=7.5;[self anim:@"jump"];[[AudioEngine shared]playJump];LOG(@"🦘 JUMP");}
    if(s.direction==UISwipeGestureRecognizerDirectionDown&&!_jp&&!_sl){_sl=1;_st=0.7;_pmn.scale=SCNVector3Make(1,0.4,1);_py=0.5;[self anim:@"slide"];[[AudioEngine shared]playSlide];LOG(@"🛝 SLIDE");}}
-(void)tap{if(_go){[self restart];LOG(@"🔄 Restart");}}
-(void)shoot{if(!_hfb||_bullets<=0||_go||_pa)return;_bullets--;SCNNode*b=[self bullet];b.position=SCNVector3Make(_pn.position.x,_py+0.8,_pn.position.z-1);[_sv.scene.rootNode addChildNode:b];NSMutableDictionary*d=[@{@"n":b,@"z":@(_pn.position.z-1)}mutableCopy];[_proj addObject:d];LOG(@"🔫 Bullet! %d left",_bullets);}

// ═══════════════ LOOP ═══════════════
-(void)renderer:(id)s updateAtTime:(NSTimeInterval)t{if(_go||_pa)return;_fc++;
    float dt=(_lt==0)?0.016666:MIN(0.05,t-_lt);_lt=t;float ddt=dt*(1+(_stb>0?0.5:0));
    if(_stb>0){_stb-=dt;if(_stb<=0){_stb=0;LOG(@"⚡ Speed boost ended");}}
    [self updFPS:t];_dist+=_sp*ddt;_sc=(int)_dist;_sp=10+_dist/100;if(_sp>40)_sp=40;_it=MAX(0,_it-dt);
    _fbt=MAX(0,_fbt-dt);if(_fbt<=0&&_hfb){_hfb=0;LOG(@"🍕 Food boost ENDED");}
    _mt=MAX(0,_mt-dt);if(_mt<=0&&_hm){_hm=0;LOG(@"🧲 Magnet ENDED");}
    float cx=_pn.position.x;cx+=(_lx-cx)*MIN(1,12*ddt);_pn.position=SCNVector3Make(cx,_py,0);
    if(!_jp&&!_sl){_pmn.position=SCNVector3Make(0,sin(_dist*5)*0.06,0);if(![_ca isEqualToString:@"run"])[self anim:@"run"];}
    if(_jp){_jv-=20*dt;_py+=_jv*ddt;if(_py<=1){_py=1;_jp=0;_jv=0;_pmn.position=SCNVector3Make(0,0,0);[self anim:@"run"];SCNParticleSystem*ip=[ParticleSystem impactDirt];SCNNode*in=[SCNNode node];[in addParticleSystem:ip];in.position=SCNVector3Make(0,0.1,0);[_pn addChildNode:in];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1*NSEC_PER_SEC),dispatch_get_main_queue(),^{[in removeFromParentNode];});}_pn.position=SCNVector3Make(_pn.position.x,_py,_pn.position.z);}
    if(_sl){_st-=dt;if(_st<=0){_sl=0;_pmn.scale=SCNVector3Make(1,1,1);_py=1;[self anim:@"run"];}}
    _stp+=ddt;if(!_jp&&!_sl&&_stp>0.35){_stp=0;[[AudioEngine shared]playFootstep];}
    for(SCNNode*ti in _rt){ti.position=SCNVector3Make(ti.position.x,ti.position.y,ti.position.z+_sp*ddt);if(ti.position.z>TL)ti.position=SCNVector3Make(ti.position.x,ti.position.y,ti.position.z-NT*TL);}
    _ntz+=_sp*ddt;if(_ntz>0&&_tr.count<35){_ntz=-14-drand48()*20;SCNNode*tree=[self tree];int si=(drand48()<0.5)?-1:1;tree.position=SCNVector3Make(si*(3.2+drand48()*5.5),0,_pn.position.z-35);[_sv.scene.rootNode addChildNode:tree];[_tr addObject:tree];}
    [self rec:_tr dt:ddt lz:8];
    _nrz+=_sp*ddt;if(_nrz>0&&_rk.count<8){_nrz=-18-drand48()*30;int rl=(int)(drand48()*3)-1;SCNNode*rk=[self rock];rk.position=SCNVector3Make(LX(rl),0.25,_pn.position.z-35);[_sv.scene.rootNode addChildNode:rk];[_rk addObject:rk];}
    [self rec:_rk dt:ddt lz:5];
    _ntz2+=_sp*ddt;if(_ntz2>0&&_tu.count<4){_ntz2=-35-drand48()*25;int tl=(int)(drand48()*3)-1;SCNNode*tu=[self turtle];tu.position=SCNVector3Make(LX(tl),0.3,_pn.position.z-40);[_sv.scene.rootNode addChildNode:tu];[_tu addObject:tu];if(_tu.count==1)LOG(@"🐢 Turtle spawn L%d",tl);}
    [self rec:_tu dt:ddt lz:5];
    if(_hfb&&!_mca&&_dist>30){[self spawnMC];LOG(@"🚗 Monkey Car!");}
    if(_mca){_mcz+=_sp*ddt*1.05;_mcn.position=SCNVector3Make(LX(1),0.3,_mcz);if(_mcz>8||_fbt<=0){[_mcn removeFromParentNode];_mca=0;}}
    _nriz+=_sp*ddt;if(_nriz>0&&_rio.count<8){_nriz=-8-drand48()*12;int rl=(int)(drand48()*3)-1;SCNNode*r=[self ring];r.position=SCNVector3Make(LX(rl),1,_pn.position.z-30);[_sv.scene.rootNode addChildNode:r];[_rio addObject:r];}
    [self rec:_rio dt:ddt lz:5];
    _nhez+=_sp*ddt;if(_nhez>0&&_heo.count<3){_nhez=-60-drand48()*40;int hl=(int)(drand48()*3)-1;SCNNode*h=[self heart];h.position=SCNVector3Make(LX(hl),1.2,_pn.position.z-50);[_sv.scene.rootNode addChildNode:h];[_heo addObject:h];}
    [self rec:_heo dt:ddt lz:5];
    [self colRock];[self colTurtle];
    _ncz+=_sp*ddt;if(_ncz>0&&_coo.count<12){_ncz=-4-drand48()*10;int cl=(int)(drand48()*3)-1;SCNNode*c=[self coin];c.position=SCNVector3Make(LX(cl),1.2,_pn.position.z-28);[_sv.scene.rootNode addChildNode:c];[_coo addObject:c];}
    NSMutableArray*dc=[NSMutableArray array];for(SCNNode*c in _coo){c.position=SCNVector3Make(c.position.x,c.position.y,c.position.z+_sp*ddt);c.rotation=SCNVector4Make(0,1,0,c.rotation.w+dt*5);if(c.position.z>5){[dc addObject:c];continue;}float dx=fabsf(c.position.x-_pn.position.x),dz=fabsf(c.position.z);float pul=_hm?3:0.7;if(dx<pul&&dz<pul){_co++;if(_co%10==0)LOG(@"🪙 %d coins",_co);[[AudioEngine shared]playCoin];SCNParticleSystem*bu=[ParticleSystem coinBurst];SCNNode*bn=[SCNNode node];[bn addParticleSystem:bu];bn.position=c.position;[_sv.scene.rootNode addChildNode:bn];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1*NSEC_PER_SEC),dispatch_get_main_queue(),^{[bn removeFromParentNode];});[c removeFromParentNode];[_coo removeObject:c];if(_co>0&&_co%30==0&&!_hfb){_hfb=1;_fbt=8;LOG(@"🍕 FOOD BOOST 8s!");}}}
    for(SCNNode*c in dc){[c removeFromParentNode];[_coo removeObject:c];}
    NSMutableArray*dr2=[NSMutableArray array];for(SCNNode*r in _rio){r.position=SCNVector3Make(r.position.x,r.position.y,r.position.z+_sp*ddt);r.rotation=SCNVector4Make(1,0,0,r.rotation.w+dt*4);if(r.position.z>5){[dr2 addObject:r];continue;}float dx=fabsf(r.position.x-_pn.position.x),dz=fabsf(r.position.z);if(dx<0.7&&dz<0.7){_ri++;LOG(@"💍 Ring %d",_ri);[[AudioEngine shared]playCoin];[r removeFromParentNode];[_rio removeObject:r];}}
    for(SCNNode*r in dr2){[r removeFromParentNode];[_rio removeObject:r];}
    NSMutableArray*dh=[NSMutableArray array];for(SCNNode*h in _heo){h.position=SCNVector3Make(h.position.x,h.position.y,h.position.z+_sp*ddt);h.rotation=SCNVector4Make(0,1,0,h.rotation.w+dt*3);if(h.position.z>5){[dh addObject:h];continue;}float dx=fabsf(h.position.x-_pn.position.x),dz=fabsf(h.position.z);if(dx<0.7&&dz<0.7&&_li<5){_li++;LOG(@"❤️ +1 life (%d)",_li);[[AudioEngine shared]playCoin];[h removeFromParentNode];[_heo removeObject:h];}}
    for(SCNNode*h in dh){[h removeFromParentNode];[_heo removeObject:h];}
    // Bullets
    NSMutableArray*torem=[NSMutableArray array];for(NSMutableDictionary*d in _proj){SCNNode*b=d[@"n"];float bz=[d[@"z"] floatValue];bz-=_sp*ddt*2;d[@"z"]=@(bz);b.position=SCNVector3Make(b.position.x,b.position.y,bz);if(bz<-20){[b removeFromParentNode];[torem addObject:d];continue;}
        for(SCNNode*tu in _tu){float dx=fabsf(b.position.x-tu.position.x),dz=fabsf(bz-tu.position.z);if(dx<0.6&&dz<0.6){LOG(@"💥 Turtle killed!");SCNParticleSystem*xp=[ParticleSystem impactDirt];xp.birthRate=50;SCNNode*xn=[SCNNode node];[xn addParticleSystem:xp];xn.position=tu.position;[_sv.scene.rootNode addChildNode:xn];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,0.8*NSEC_PER_SEC),dispatch_get_main_queue(),^{[xn removeFromParentNode];});[tu removeFromParentNode];[_tu removeObject:tu];[b removeFromParentNode];[torem addObject:d];break;}}}
    for(id td in torem)[_proj removeObject:td];
    _slab.text=[NSString stringWithFormat:@"SCORE: %d",_sc];_col.text=[NSString stringWithFormat:@"🪙 %d",_co];_ril.text=[NSString stringWithFormat:@"💍 %d",_ri];_spd.text=[NSString stringWithFormat:@"⚡ %.0f m/s",_sp];
    _bol.text=_hfb?[NSString stringWithFormat:@"🍕 %.1fs",_fbt]:(_stb>0?[NSString stringWithFormat:@"⚡ %.1fs",_stb]:(_hm?[NSString stringWithFormat:@"🧲 %.1fs",_mt]:@""));
    _bul.text=_bullets>0?[NSString stringWithFormat:@"🔫 %d",_bullets]:@"";
    NSMutableString*he=[NSMutableString string];for(int i=0;i<_li;i++)[he appendString:@"❤️"];if(_it>0&&fmod(t,0.2)<0.1)he=[NSMutableString string];_lil.text=he;
    _de.hidden=_jp;SCNParticleSystem*du=_de.particleSystems.firstObject;du.birthRate=_sl?60:25;
    if(_dbg&&_fc%360==0)LOG(@"📊 F%d ⚡%.0f 🪙%d 💍%d ❤️%d 🐢%lu",_fc,_sp,_co,_ri,_li,(unsigned long)_tu.count);
}

// ─── HELPERS ─────────────────────────
-(void)rec:(NSMutableArray*)p dt:(float)dt lz:(float)lz{NSMutableArray*r=[NSMutableArray array];for(SCNNode*n in p){n.position=SCNVector3Make(n.position.x,n.position.y,n.position.z+_sp*dt);if(n.position.z>lz)[r addObject:n];}for(SCNNode*n in r){[n removeFromParentNode];[p removeObject:n];}}
-(void)colRock{NSMutableArray*r=[NSMutableArray array];for(SCNNode*rk in _rk){rk.position=SCNVector3Make(rk.position.x,rk.position.y,rk.position.z+_sp*MIN(0.05,_lt==0?0.016666:_lt-_lt));if(rk.position.z>5){[r addObject:rk];continue;}float ht=_sl?0.45:0.65;if(fabsf(rk.position.x-_pn.position.x)<ht&&fabsf(rk.position.z)<0.6&&_it<=0&&!_jp&&_py<1.2){_li--;_it=1.5;[[AudioEngine shared]playHit];LOG(@"💥 ROCK! Lives:%d",_li);[self hitFX:rk.position];if(_li<=0){LOG(@"💀 GAME OVER Score:%d 🪙%d 💍%d",_sc,_co,_ri);[self go];return;}[rk removeFromParentNode];[_rk removeObject:rk];}}for(SCNNode*rk in r){[rk removeFromParentNode];[_rk removeObject:rk];}}
-(void)colTurtle{NSMutableArray*r=[NSMutableArray array];for(SCNNode*tu in _tu){tu.position=SCNVector3Make(tu.position.x,tu.position.y,tu.position.z+_sp*MIN(0.05,_lt==0?0.016666:_lt-_lt));if(tu.position.z>5){[r addObject:tu];continue;}float ht=_sl?0.45:0.65;if(fabsf(tu.position.x-_pn.position.x)<ht&&fabsf(tu.position.z)<0.6&&_it<=0&&!_jp&&_py<1.2){_li--;_it=1.5;[[AudioEngine shared]playHit];LOG(@"💥 TURTLE! Lives:%d",_li);[self hitFX:tu.position];if(_li<=0){LOG(@"💀 GAME OVER");[self go];return;}[tu removeFromParentNode];[_tu removeObject:tu];}}for(SCNNode*tu in r){[tu removeFromParentNode];[_tu removeObject:tu];}}
-(void)hitFX:(SCNVector3)pos{SCNParticleSystem*hf=[ParticleSystem impactDirt];SCNNode*hn=[SCNNode node];[hn addParticleSystem:hf];hn.position=pos;[_sv.scene.rootNode addChildNode:hn];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1.5*NSEC_PER_SEC),dispatch_get_main_queue(),^{[hn removeFromParentNode];});SCNAction*fl=[SCNAction sequence:@[[SCNAction fadeOpacityTo:0.3 duration:0.06],[SCNAction fadeOpacityTo:1 duration:0.06],[SCNAction fadeOpacityTo:0.3 duration:0.06],[SCNAction fadeOpacityTo:1 duration:0.06]]];[_pmn runAction:fl];}
-(void)spawnMC{_mcz=-8;_mcn=[SCNNode node];SCNBox*bo=[SCNBox boxWithWidth:1.2 height:0.5 length:2 chamferRadius:0.1];SCNMaterial*m=[SCNMaterial material];m.lightingModelName=SCNLightingModelPhysicallyBased;m.diffuse.contents=[UIColor yellowColor];m.roughness.contents=@0.3;m.metalness.contents=@0.5;bo.materials=@[m];[_mcn setGeometry:bo];[_sv.scene.rootNode addChildNode:_mcn];_mca=1;}
-(void)updFPS:(NSTimeInterval)t{_fpc++;if(t-_lf>=0.5){int fps=(int)(_fpc/(t-_lf));_fps.text=[NSString stringWithFormat:@"%d FPS",fps];_fps.fontColor=fps>50?[SKColor greenColor]:(fps>30?[SKColor yellowColor]:[SKColor redColor]);_fpc=0;_lf=t;}}
-(void)go{_go=1;[self anim:@"die"];[[AudioEngine shared]playDeath];SCNParticleSystem*dp=[ParticleSystem impactDirt];dp.birthRate=80;SCNNode*dn=[SCNNode node];[dn addParticleSystem:dp];dn.position=SCNVector3Make(0,0.8,0);[_pn addChildNode:dn];[self goHUD];}
-(void)goHUD{SKLabelNode*gol=[SKLabelNode labelNodeWithFontNamed:@"HelveticaNeue-Bold"];gol.text=@"GAME OVER";gol.fontSize=42;gol.fontColor=[SKColor redColor];gol.position=CGPointMake(_hs.size.width/2,_hs.size.height/2);[_hs addChild:gol];SKLabelNode*rs=[SKLabelNode labelNodeWithFontNamed:@"HelveticaNeue"];rs.text=@"Tap to restart";rs.fontSize=18;rs.fontColor=[SKColor whiteColor];rs.position=CGPointMake(_hs.size.width/2,_hs.size.height/2-45);[_hs addChild:rs];}
-(void)restart{_li=3;_sc=0;_co=0;_ri=0;_dist=0;_sp=10;_ln=0;_lx=0;_py=1;_jp=0;_sl=0;_it=0;_go=0;_pa=0;_fbt=0;_mt=0;_hfb=0;_hm=0;_bullets=5;_stb=0;_pn.position=SCNVector3Make(0,1,0);_pmn.scale=SCNVector3Make(1,1,1);_pmn.position=SCNVector3Make(0,0,0);[self anim:@"idle"];for(SCNNode*n in _rk)[n removeFromParentNode];[_rk removeAllObjects];for(SCNNode*c in _coo)[c removeFromParentNode];[_coo removeAllObjects];for(SCNNode*t in _tu)[t removeFromParentNode];[_tu removeAllObjects];for(SCNNode*r in _rio)[r removeFromParentNode];[_rio removeAllObjects];for(SCNNode*h in _heo)[h removeFromParentNode];[_heo removeAllObjects];for(NSDictionary*d in _proj)[d[@"n"] removeFromParentNode];[_proj removeAllObjects];if(_mca){[_mcn removeFromParentNode];_mca=0;}[_hs removeAllChildren];[self hud];_nrz=-15;_ncz=-6;_ntz=-8;_ntz2=-30;_nriz=-10;_nhez=-50;_fc=0;LOG(@"🔄 RESTARTED");}
-(void)viewDidLayoutSubviews{_sv.frame=self.view.bounds;_hv.frame=self.view.bounds;_hs.size=self.view.bounds.size;}
-(BOOL)prefersStatusBarHidden{return YES;}
@end
