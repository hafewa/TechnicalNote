﻿Shader "Unlit/PBR"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _LightFactor ("Light Factor",Range(0,10)) = 1
        _MainCol ("Main Color",Color) = (1,1,1,1)
        _NormalTex ("Normal Texture", 2D) = "bump"{}
        _NormalScale ("Normal Scale", float) = 1
        _MetalicTex ("Metalic Texture",2D) = "white"{}
        _SpecularColor ("Specular Color", Color) = (1,1,1,1)
        _Smoothness ("Smoothness",Range(0,1)) = 1
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "LightMode" = "ForwardBase"}
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"
            #include "AnisotropicPBR.cginc"
            #include "AutoLight.cginc"
            #include "Lighting.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
                float4 tan : TANGENT;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float4 TtoW0 : TEXCOORD1;
                float4 TtoW1 : TEXCOORD2;
                float4 TtoW2 : TEXCOORD3;
                SHADOW_COORDS(4)
                float3 worldPos : TEXCOORD5;

            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            float _LightFactor;
            sampler2D _NormalTex;
            float4 _NormalTex_ST;
            float _NormalScale;
            sampler2D _MetalicTex;
            float4 _MetalicTex_ST;
            float4 _MainCol;
            float4 _SpecularColor;
            float _Smoothness;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                float3 worldPos = mul(unity_ObjectToWorld,v.vertex).xyz;
                float3 worldNoraml = UnityObjectToWorldNormal(v.normal);
                float3 worldTangent = UnityObjectToWorldDir(v.tan.xyz);
                float3 worldBinormal = cross(worldNoraml,worldTangent) * v.tan.w;
                o.TtoW0 = float4(worldTangent.x,worldBinormal.x,worldNoraml.x,worldPos.x);
                o.TtoW1 = float4(worldTangent.y,worldBinormal.y,worldNoraml.y,worldPos.y);
                o.TtoW2 = float4(worldTangent.z,worldBinormal.z,worldNoraml.z,worldPos.z);
                o.worldPos = worldPos;
                TRANSFER_SHADOW(o);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                // sample the texture
                float4 col = tex2D(_MainTex, i.uv);
                UNITY_LIGHT_ATTENUATION(atten,i,i.worldPos);
                float4 Metalness = tex2D(_MetalicTex,i.uv);//r通道表示金属度，a通道表示光滑度
                float smoothness = Metalness.a * _Smoothness;
                float roughness = 1 - smoothness;
                float3 worldPos = float3(i.TtoW0.w,i.TtoW1.w,i.TtoW2.w);
                float3 viewDir = normalize(UnityWorldSpaceViewDir(worldPos));
                float3 lightDir = normalize(UnityWorldSpaceLightDir(worldPos));
                float3 halfDir = normalize(viewDir + lightDir);
                //normal in tangent space
                float3 normal = UnpackNormal(tex2D(_NormalTex,i.uv));
                normal.xy *= _NormalScale;
                normal.z = sqrt(1 - saturate(dot(normal.xy,normal.xy)));
                //normal in world space
                float3 normalWorld = normalize(float3(dot(i.TtoW0.xyz,normal),dot(i.TtoW1.xyz,normal),dot(i.TtoW2.xyz,normal)));
                
                float NdotL = saturate(dot(normalWorld,lightDir));
                float NdotV = saturate(dot(normalWorld,viewDir));
                float VdotH = saturate(dot(viewDir,halfDir));
                float NdotH = saturate(dot(normalWorld,halfDir));
                float LdotH = saturate(dot(lightDir,halfDir));

                //direct light part
                float4 ambient = UNITY_LIGHTMODEL_AMBIENT * _MainCol * col * _LightFactor;
                float4 diffuse = OneMinusReflectivityFromMetallic(Metalness.r) * _MainCol * col / UNITY_PI;
                float3 F0 = lerp(unity_ColorSpaceDielectricSpec.rgb,col.rgb,Metalness.r);//区分金属非金属
                float4 specular = CookTorranceBRDF(NdotH,NdotL,NdotV,VdotH,roughness,float4(F0,1) * _SpecularColor);                
                
                //indirect light part
                float3 reflectDir = normalize(reflect(-viewDir,normalWorld));
                float percetualRoughness = roughness * (1.7 - 0.7 * roughness);
                float mip = percetualRoughness * 6;
                float4 envMap = UNITY_SAMPLE_TEXCUBE_LOD(unity_SpecCube0,reflectDir,mip);
                float grazing = saturate((1 - roughness) + 1 - OneMinusReflectivityFromMetallic(Metalness.r));
                float surfaceReduction = 1 / (pow2(roughness) + 1);
                float4 indirectSpecualr = surfaceReduction * envMap * FresnelLerp(float4(F0,1) * _SpecularColor,grazing,NdotV);

                return ambient + (diffuse + specular) * _LightColor0 * UNITY_PI * NdotL * atten + indirectSpecualr;
            }
            ENDCG
        }
    }
}