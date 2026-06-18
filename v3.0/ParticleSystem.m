#import "ParticleSystem.h"

@implementation ParticleSystem

+ (SCNParticleSystem *)dustTrail {
    SCNParticleSystem *ps = [SCNParticleSystem particleSystem];
    ps.birthRate = 30;
    ps.particleLifeSpan = 1.2;
    ps.particleSize = 0.15;
    ps.particleColor = [UIColor colorWithRed:0.5 green:0.4 blue:0.3 alpha:1.0];
    ps.particleColorVariation = SCNVector4Make(0.1, 0.1, 0.05, 0.0);
    ps.emissionDuration = 0;
    ps.loops = YES;
    ps.spreadingAngle = 25;
    ps.emitterShape = [SCNSphere sphereWithRadius:0.1];
    ps.speedFactor = 0.8;
    ps.particleVelocity = 0.3;
    ps.particleVelocityVariation = 0.15;
    ps.particleSizeVariation = 0.3;
    ps.stretchFactor = 0.8;
    ps.particleMass = 0.01;
    ps.affectedByGravity = NO;
    ps.acceleration = SCNVector3Make(0, 0.5, 0.2);
    ps.dampingFactor = 2.0;
    ps.particleLifeSpanVariation = 0.5;
    ps.blendMode = SCNParticleBlendModeAlpha;
    ps.sortingMode = SCNParticleSortingModeDistance;
    return ps;
}

+ (SCNParticleSystem *)impactDirt {
    SCNParticleSystem *ps = [SCNParticleSystem particleSystem];
    ps.birthRate = 50;
    ps.particleLifeSpan = 0.8;
    ps.emissionDuration = 0.05;
    ps.loops = NO;
    ps.particleSize = 0.12;
    ps.particleColor = [UIColor colorWithRed:0.45 green:0.35 blue:0.25 alpha:1.0];
    ps.particleColorVariation = SCNVector4Make(0.15, 0.1, 0.05, 0.0);
    ps.spreadingAngle = 80;
    ps.emitterShape = [SCNSphere sphereWithRadius:0.3];
    ps.speedFactor = 1.2;
    ps.particleVelocity = 2.5;
    ps.particleVelocityVariation = 1.5;
    ps.particleSizeVariation = 0.6;
    ps.affectedByGravity = YES;
    ps.acceleration = SCNVector3Make(0, -4, 0);
    ps.dampingFactor = 2.5;
    ps.stretchFactor = 0.5;
    ps.blendMode = SCNParticleBlendModeAlpha;
    return ps;
}

+ (SCNParticleSystem *)coinBurst {
    SCNParticleSystem *ps = [SCNParticleSystem particleSystem];
    ps.birthRate = 20;
    ps.particleLifeSpan = 0.6;
    ps.emissionDuration = 0.03;
    ps.loops = NO;
    ps.particleSize = 0.06;
    ps.particleColor = [UIColor colorWithRed:1.0 green:0.85 blue:0.1 alpha:1.0];
    ps.particleColorVariation = SCNVector4Make(0.0, 0.1, 0.05, 0.0);
    ps.spreadingAngle = 120;
    ps.emitterShape = [SCNSphere sphereWithRadius:0.2];
    ps.speedFactor = 2.5;
    ps.particleVelocity = 3.0;
    ps.particleVelocityVariation = 2.0;
    ps.affectedByGravity = YES;
    ps.acceleration = SCNVector3Make(0, 2, 0);
    ps.dampingFactor = 1.0;
    ps.blendMode = SCNParticleBlendModeAdditive;
    ps.sortingMode = SCNParticleSortingModeDistance;
    return ps;
}

+ (SCNParticleSystem *)leavesRustle {
    SCNParticleSystem *ps = [SCNParticleSystem particleSystem];
    ps.birthRate = 5;
    ps.particleLifeSpan = 2.5;
    ps.emissionDuration = 0;
    ps.loops = YES;
    ps.particleSize = 0.1;
    ps.particleColor = [UIColor colorWithRed:0.15 green:0.55 blue:0.1 alpha:0.8];
    ps.particleColorVariation = SCNVector4Make(0.1, 0.2, 0.05, 0.1);
    ps.spreadingAngle = 40;
    ps.emitterShape = [SCNSphere sphereWithRadius:1.5];
    ps.speedFactor = 0.3;
    ps.particleVelocity = 0.5;
    ps.particleVelocityVariation = 0.4;
    ps.particleSizeVariation = 0.5;
    ps.affectedByGravity = YES;
    ps.acceleration = SCNVector3Make(0, -1.5, 0);
    ps.dampingFactor = 0.5;
    ps.blendMode = SCNParticleBlendModeAlpha;
    ps.sortingMode = SCNParticleSortingModeDistance;
    return ps;
}

@end
