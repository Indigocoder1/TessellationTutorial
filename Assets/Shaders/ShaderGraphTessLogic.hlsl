struct TessellationFactors {
    float edge[3] : SV_TessFactor;
    float inside : SV_InsideTessFactor;
};

[patchconstantfunc("patchConstantFunction")]
[domain("tri")]
[outputcontrolpoints(3)]
[outputtopology("triangle_cw")]
[partitioning("fractional_odd")]
PackedVaryings hull(InputPatch<PackedVaryings, 3> patch, uint id : SV_OutputControlPointID)
{
    return patch[id];
}

float CalcDistanceTessFactor(float3 worldPosition)
{
    const float minDist = 2;
    float dist = distance(worldPosition, _WorldSpaceCameraPos);
    float factor = clamp(1 - (dist - minDist) / (_MaxTessellationDist - minDist), 0.01, 1);
    
    return clamp(factor * _Tessellation, 0, _Tessellation);
}

float invLerp(float from, float to, float value)
{
   return (value - from) / (to - from);
}

float CalculateTextureChangeTessFactor(float2 uv)
{
    const float pi = 3.14159;
    
    float4 sampleCenter = SAMPLE_TEXTURE2D_LOD(_BaseMap, sampler_BaseMap, uv, 0);
    float maxFactor = _MinTess;

    float degreeIncrement = 2 * pi / _RotationIterations;
    for (int i = 0; i < _RotationIterations; ++i)
    {
        float radians = degreeIncrement * i;
        half2 offset = half2(cos(radians), sin(radians)) * _CheckDistance;
        
        float4 sample = SAMPLE_TEXTURE2D_LOD(_BaseMap, sampler_BaseMap, uv + offset, 0);
        float delta = length(sampleCenter - sample);
        float tessellationFactor = invLerp(0, 1, delta) * _ProximityTessellation;
        maxFactor = max(tessellationFactor, maxFactor);
    }
    
    return maxFactor;
}

TessellationFactors CalcTriEdgeTessFactors(float3 vertexTessFactors)
{
    TessellationFactors tess;
    
    tess.edge[0] = 0.5 * (vertexTessFactors.y + vertexTessFactors.z);
    tess.edge[1] = 0.5 * (vertexTessFactors.x + vertexTessFactors.z);
    tess.edge[2] = 0.5 * (vertexTessFactors.x + vertexTessFactors.y);
    tess.inside = (vertexTessFactors.x + vertexTessFactors.y + vertexTessFactors.z) / 3.0f;
    
    return tess;
}

TessellationFactors DistanceBasedTess(PackedVaryings vertex0, PackedVaryings vertex1, PackedVaryings vertex2)
{
    float3 vertexTessFactors;
    
    vertexTessFactors.x = CalcDistanceTessFactor(vertex0.positionWS) * CalculateTextureChangeTessFactor(vertex0.texCoord0);
    vertexTessFactors.y = CalcDistanceTessFactor(vertex1.positionWS) * CalculateTextureChangeTessFactor(vertex1.texCoord0);
    vertexTessFactors.z = CalcDistanceTessFactor(vertex2.positionWS) * CalculateTextureChangeTessFactor(vertex2.texCoord0);
    
    return CalcTriEdgeTessFactors(vertexTessFactors);
}

TessellationFactors patchConstantFunction(InputPatch<PackedVaryings, 3> patch)
{
	return DistanceBasedTess(patch[0], patch[1], patch[2]);
}

void vertTess(inout PackedVaryings IN)
{    
    float textureValue = SAMPLE_TEXTURE2D_LOD(_BaseMap, sampler_BaseMap, IN.texCoord0, 0).r;
    IN.positionWS += IN.normalWS * -_HeightDeformation * textureValue;
    
    float3 objectPos = TransformWorldToObject(IN.positionWS);
    #if (SHADERPASS == SHADERPASS_SHADOWCASTER)
    // object to clip space, this doesn't take into account the adjustments for some reason
    IN.positionCS = TransformObjectToHClip(objectPos);
    #else
    // object to clip space
    IN.positionCS = TransformObjectToHClip(objectPos);
    #endif
}

#define INTERPOLATE(fieldName) data.fieldName = \
	patch[0].fieldName * barycentricCoordinates.x + \
	patch[1].fieldName * barycentricCoordinates.y + \
	patch[2].fieldName * barycentricCoordinates.z;

[domain("tri")]
PackedVaryings domain(TessellationFactors factors, OutputPatch<PackedVaryings, 3> patch, float3 barycentricCoordinates : SV_DomainLocation)
{
    PackedVaryings data;
    ZERO_INITIALIZE(PackedVaryings, data);
    
    INTERPOLATE(positionCS)
    INTERPOLATE(normalWS)
    INTERPOLATE(tangentWS)
    INTERPOLATE(texCoord0)
    INTERPOLATE(positionWS)
    
    vertTess(data);
    
    return data;
}