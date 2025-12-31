
#include "ShaderGraphTessLogic.hlsl"

#pragma require tessellation
#pragma hull hull
#pragma domain domain

void ForceTess_float(in float2 UV, in float3 WorldPos, in float3 worldNormal, out float Dummy)
{
    Dummy = 0;
}