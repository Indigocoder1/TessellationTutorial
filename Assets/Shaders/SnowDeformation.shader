Shader "Custom/SnowDeformation"
{
    Properties
    {
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        [MainTexture] _BaseMap("Base Map", 2D) = "white"
        _Tessellation ("Tessellation Value", Float) = 1
        _MaxTessellationDist ("Max Tess Distance", Float) = 50
        _HeightDeformation ("Height Deformation", Float) = 1
        _RotationIterations ("Rotation Iterations", Integer) = 2
        _CheckDistance ("UV Check Distance", Float) = 0.1
        _MinTess ("Minimum Tessellation", Float) = 1
        _ProximityTessellation ("Proximity Tessellation", Float) = 3
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            HLSLPROGRAM

            #pragma vertex dummyVert
            #pragma fragment frag
            #pragma hull hull
            #pragma domain domain

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normal : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float4 _BaseMap_ST;
                float _Tessellation;
                float _MaxTessellationDist;
                float _HeightDeformation;
                float _MinTess;
                float _CheckDistance;
                float _ProximityTessellation;
                int _RotationIterations;
            CBUFFER_END

            struct TessellationFactors {
                float edge[3] : SV_TessFactor;
                float inside : SV_InsideTessFactor;
            };
            
            [patchconstantfunc("patchConstantFunction")]
            [domain("tri")]
            [outputcontrolpoints(3)]
            [outputtopology("triangle_cw")]
            [partitioning("fractional_odd")]
            Attributes hull(InputPatch<Attributes, 3> patch, uint id : SV_OutputControlPointID)
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
                    float tessellationFactor = invLerp(0, 1, delta) * _ProximityTessellation ;
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
            
            TessellationFactors DistanceBasedTess(Attributes vertex0, Attributes vertex1, Attributes vertex2)
            {
                float3 vertexTessFactors;
                float3 positionWS0 = TransformObjectToWorld(vertex0.positionOS);
                float3 positionWS1 = TransformObjectToWorld(vertex1.positionOS);
                float3 positionWS2 = TransformObjectToWorld(vertex2.positionOS);
                
                vertexTessFactors.x = CalcDistanceTessFactor(positionWS0) * CalculateTextureChangeTessFactor(vertex0.uv);
                vertexTessFactors.y = CalcDistanceTessFactor(positionWS1) * CalculateTextureChangeTessFactor(vertex1.uv);
                vertexTessFactors.z = CalcDistanceTessFactor(positionWS2) * CalculateTextureChangeTessFactor(vertex2.uv);
                
                return CalcTriEdgeTessFactors(vertexTessFactors);
            }
            
            TessellationFactors patchConstantFunction(InputPatch<Attributes, 3> patch)
            {
	            return DistanceBasedTess(patch[0], patch[1], patch[2]);
            }
            
            Attributes dummyVert(Attributes IN)
            {
                return IN;
            }
            
            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                float3 objectPos = IN.positionOS.xyz;
                
                float textureValue = SAMPLE_TEXTURE2D_LOD(_BaseMap, sampler_BaseMap, IN.uv, 0).r;
                objectPos += IN.normal * -_HeightDeformation * textureValue;
                
                OUT.positionHCS = TransformObjectToHClip(objectPos);
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                return OUT;
            }
            
            #define INTERPOLATE(fieldName) data.fieldName = \
		        patch[0].fieldName * barycentricCoordinates.x + \
		        patch[1].fieldName * barycentricCoordinates.y + \
		        patch[2].fieldName * barycentricCoordinates.z;
            
            [domain("tri")]
            Varyings domain(TessellationFactors factors, OutputPatch<Attributes, 3> patch, float3 barycentricCoordinates : SV_DomainLocation)
            {
                Attributes data;
                INTERPOLATE(positionOS)
                INTERPOLATE(uv)
                INTERPOLATE(normal)
                
                return vert(data);
            }

            half4 frag(Varyings IN) : SV_Target
            {
                half4 color = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;
                return 1 - color;
            }
            ENDHLSL
        }
    }
}
