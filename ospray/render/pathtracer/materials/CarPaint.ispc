// ======================================================================== //
// Copyright 2009-2017 Intel Corporation                                    //
//                                                                          //
// Licensed under the Apache License, Version 2.0 (the "License");          //
// you may not use this file except in compliance with the License.         //
// You may obtain a copy of the License at                                  //
//                                                                          //
//     http://www.apache.org/licenses/LICENSE-2.0                           //
//                                                                          //
// Unless required by applicable law or agreed to in writing, software      //
// distributed under the License is distributed on an "AS IS" BASIS,        //
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. //
// See the License for the specific language governing permissions and      //
// limitations under the License.                                           //
// ======================================================================== //

#include "Material.ih"
#include "texture/TextureParam.ih"
//#include "render/pathtracer/bsdfs/MultiBSDF.ih"
//#include "../bsdfs/Lambert.ih"
//#include "../bsdfs/OrenNayar.ih"
#include "../bsdfs/Conductor.ih"
#include "../bsdfs/MicrofacetConductor.ih"
#include "../bsdfs/DielectricLayer.ih"
#include "../bsdfs/MicrofacetDielectricLayer.ih"
#include "../shaders/Flakes.ih"

// FIXME: add diffuse base, flake mask
struct CarPaint
{
  PathTraceMaterial super;
  
  float flakeScale;
  TextureParam flakeScaleMap;

  float flakeDensity;
  TextureParam flakeDensityMap;

  float flakeSpread;
  TextureParam flakeSpreadMap;

  float flakeRoughness; // in [0, 1]; 0==ideally smooth (mirror)
  TextureParam flakeRoughnessMap;
  
  float coat; // dielectric clear coat reflectivity in [0, 1]; coat = sqr((ior-1)/(ior+1))/0.08
  TextureParam coatMap;
  
  vec3f coatColor;
  TextureParam coatColorMap;
  
  float coatThickness;
  TextureParam coatThicknessMap;
  
  float coatRoughness;
  TextureParam coatRoughnessMap;

  TextureParam coatNormalMap;
  linear2f coatNormalRot;
  float coatNormalScale;
};

#define EPS 1e-5f

///////////////////////////////////////////////////////////////////////////////
// Implementation

const varying BSDF* varying CarPaint_getBSDF(const uniform PathTraceMaterial* uniform super,
                                             uniform ShadingContext* uniform ctx,
                                             const DifferentialGeometry& dg,
                                             const Ray& ray,
                                             const Medium& currentMedium)
{
  const uniform CarPaint* uniform self = (const uniform CarPaint* uniform)super;
  varying BSDF* varying bsdf;
    
  // metallic flake layer
  const float flakeScale = max(self->flakeScale * get1f(self->flakeScaleMap, dg.st, 1.f), 0.f);
  const float flakeDensity = clamp(self->flakeDensity * get1f(self->flakeDensityMap, dg.st, 1.f));
  const float flakeSpread = max(self->flakeSpread * get1f(self->flakeSpreadMap, dg.st, 1.f), 0.f);

  Flakes flakes;
  flakes.scale = flakeScale;
  flakes.density = flakeDensity;
  //flakes.layers = 1;
  flakes.spread = flakeSpread;
  flakes.jitter = 0.75f;

  const vec3f flakeN = Flakes_eval(&flakes, dg.P);
  varying linear3f* uniform flakeFrame = LinearSpace3f_create(ctx, makeShadingFrame(dg, flakeN));

  // flakes are made of aluminum
  const uniform vec3f flakeEta = make_vec3f(1.69700277f, 0.879832864f, 0.5301736f);
  const uniform vec3f flakeK = make_vec3f(9.30200672f, 6.27604008f, 4.89433956f);
  Fresnel* uniform flakeFresnel = FresnelConductorRGBUniform_create(ctx, flakeEta, flakeK);

  const float flakeRoughness = max(self->flakeRoughness * get1f(self->flakeRoughnessMap, dg.st, 1.f), 0.f);
  if (flakeRoughness < EPS)
    bsdf = Conductor_create(ctx, flakeFrame, flakeFresnel);
  else
    bsdf = MicrofacetConductor_create(ctx, flakeFrame, flakeFresnel, flakeRoughness);
 
  // clear coat
  const float coat = max(self->coat * get1f(self->coatMap, dg.st, 1.f), 0.f);

  if (coat > EPS) {
    const float coatIor = (2.f / (1.f - sqrt(0.08f * coat))) - 1.f;
    const vec3f coatColor = clamp(self->coatColor * get3f(self->coatColorMap, dg.st, make_vec3f(1.f)));
    const float coatThickness = max(self->coatThickness * get1f(self->coatThicknessMap, dg.st, 1.f), 0.f);
    const float coatRoughness = max(self->coatRoughness * get1f(self->coatRoughnessMap, dg.st, 1.f), 0.f);
    varying linear3f* uniform coatFrame =
      LinearSpace3f_create(ctx, makeShadingFrame(dg, self->coatNormalMap, self->coatNormalRot, self->coatNormalScale));
    
    if (coatRoughness < EPS)
      bsdf = DielectricLayer_create(ctx, coatFrame, bsdf, rcp(coatIor), coatColor, coatThickness);
    else
      bsdf = MicrofacetDielectricLayer_create(ctx, coatFrame, bsdf, rcp(coatIor), coatColor, coatThickness, coatRoughness);
  }

  return bsdf;
}

///////////////////////////////////////////////////////////////////////////////
// External API

export void* uniform PathTracer_CarPaint_set(void* uniform _self,
    uniform float flakeScale, void* uniform flakeScaleMap, const uniform affine2f& flakeScaleXform,
    uniform float flakeDensity, void* uniform flakeDensityMap, const uniform affine2f& flakeDensityXform,
    uniform float flakeSpread, void* uniform flakeSpreadMap, const uniform affine2f& flakeSpreadXform,
    uniform float flakeRoughness, void* uniform flakeRoughnessMap, const uniform affine2f& flakeRoughnessXform,
    uniform float coat, void* uniform coatMap, const uniform affine2f& coatXform,
    const uniform vec3f& coatColor, void* uniform coatColorMap, const uniform affine2f& coatColorXform,
    uniform float coatThickness, void* uniform coatThicknessMap, const uniform affine2f& coatThicknessXform,
    uniform float coatRoughness, void* uniform coatRoughnessMap, const uniform affine2f& coatRoughnessXform,
    void* uniform coatNormalMap, const uniform affine2f& coatNormalXform, const uniform linear2f& coatNormalRot, uniform float coatNormalScale)
{
  CarPaint* uniform self = (CarPaint* uniform)_self;

  self->flakeScale = flakeScale;
  self->flakeScaleMap = make_TextureParam((uniform Texture2D*)flakeScaleMap, flakeScaleXform);

  self->flakeDensity = flakeDensity;
  self->flakeDensityMap = make_TextureParam((uniform Texture2D*)flakeDensityMap, flakeDensityXform);

  self->flakeSpread = flakeSpread;
  self->flakeSpreadMap = make_TextureParam((uniform Texture2D*)flakeSpreadMap, flakeSpreadXform);

  self->flakeRoughness = flakeRoughness;
  self->flakeRoughnessMap = make_TextureParam((uniform Texture2D*)flakeRoughnessMap, flakeRoughnessXform);
  
  self->coat = coat;
  self->coatMap = make_TextureParam((uniform Texture2D*)coatMap, coatXform);
  
  self->coatColor = coatColor;
  self->coatColorMap = make_TextureParam((uniform Texture2D*)coatColorMap, coatColorXform);
  
  self->coatThickness = coatThickness;
  self->coatThicknessMap = make_TextureParam((uniform Texture2D*)coatThicknessMap, coatThicknessXform);
  
  self->coatRoughness = coatRoughness;
  self->coatRoughnessMap = make_TextureParam((uniform Texture2D*)coatRoughnessMap, coatRoughnessXform);

  self->coatNormalMap = make_TextureParam((uniform Texture2D*)coatNormalMap, coatNormalXform);
  self->coatNormalRot = coatNormalRot;
  self->coatNormalScale = coatNormalScale;
}

export void* uniform PathTracer_CarPaint_create()
{
  CarPaint* uniform self = uniform new CarPaint;

  PathTraceMaterial_Constructor(&self->super, CarPaint_getBSDF);

  uniform affine2f xform = make_AffineSpace2f_identity();
  PathTracer_CarPaint_set(self,
    0.f, NULL, xform,
    0.f, NULL, xform,
    0.f, NULL, xform,
    0.f, NULL, xform,
    0.f, NULL, xform,
    make_vec3f(1.f), NULL, xform,
    1.f, NULL, xform,
    0.f, NULL, xform,
    NULL, xform, make_LinearSpace2f_identity(), 1.f);

  return self;
}