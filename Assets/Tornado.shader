Shader "Custom/Tornado"
{
    Properties
    {
		_MainTex("Main Texture",2D) = "white"{}
		_CloudColor("CloudColor", Color) = (1,1,1,1)
		_LightColor("LightColor", Color) = (1,1,1,1)
		_Radius("Storm Radius",Range(0,100)) = 50//暴风半径
		_Thickness("Thickness",Range(0,200)) = 30//有起伏的云层的厚度
		_Top("Storm Top",Range(0,300)) = 200//云的最高点
		_Bottom("Storm Bottom",Range(0,-300)) = -200//云的最低点

		_Noise("Noise",2D) = "white"{}//噪声贴图
		_Shape("Shape",2D) = "white"{}//云的起伏形状
		_Noise3D("noise 3d",3D) = "white"{}//云的细节
		_Noise3D_Detail("noise 3d detail",3D) = "white"{}//云的边缘的形状
		_Edge("Edge",Range(0,1)) = 0.2//云边缘形状侵蚀程度
		_UVScale("UV Scale",FLOAT) = 0.02//云细节的UV伸缩
		_LightPos("LightPos",FLOAT) = -100//光源位置
		_LightFadeOut("light fade out",FLOAT) = 300//低于光源的云的变暗

		_Absorption("Absorption",Range(0,1)) = 0.3
		_G("G",Range(0,1)) = 0.3
		_Curl("curl",Range(0,7)) = 0.2//云的旋转度
    }
    SubShader
    {
		CGINCLUDE
		float random(float x) {
			return frac(sin(x*127.1452)*43758.5453123);
		}
		float noise(float x)
		{
			float i = floor(x);
			float f = frac(x);  
			float y = random(i);
			y = lerp(random(i), random(i + 1.0), smoothstep(0.,1.,f));
			return y;
		}
		float4x4 _InvVP;
		float4 GetWorldPositionFromDepth(float2 uv,float depth)
		{
			float4 wpos = mul(_InvVP, float4(uv * 2 - 1, depth, 1));
			wpos /= wpos.w;
			return wpos;
		}
		float remap(float original_value, float original_min, float original_max, float new_min, float new_max)
		{
			return new_min + (((original_value - original_min) / (original_max - original_min)) * (new_max - new_min));
		}
		float SignedAngle(float3 from, float3 to)
		{
			float pi = 3.14159;
			float angle = acos(dot(normalize(from), normalize(to)));
			if (cross(to, from).y < 0)
			{
				return pi * 2 - angle;
			}
			return angle;
		}
		//卷曲uv
		float2 computeCurl(float2 st)
		{
			float x = st.x; float y = st.y;
			float h = 0.0001;
			float n, n1, n2, a, b;

			n = random(float2(x, y));
			n1 = random(float2(x, y - h));
			n2 = random(float2(x - h, y));
			a = (n - n1) / h;
			b = (n - n2) / h;

			return float2(a, -b);
		}
		//射线与圆柱相交检测
		bool rayCastCircle(float3 rayStart,float3 dir,float radius,out float2 dis)
		{
			float2 p = rayStart.xz;
			float2 d = dir.xz;
			float r = radius;
			float a = dot(d, d) + 1.0E-10;/// A in quadratic formula , with a small constant to avoid division by zero issue
			float det, b;
			b = -dot(p, d); /// -B/2 in quadratic formula
			/// AC = (p.x*p.x + p.y*p.y + p.z*p.z)*dd + r*r*dd 
			det = (b*b) - dot(p, p)*a + r * r*a;/// B^2/4 - AC = determinant / 4
			if (det < 0.0) {
				return false;
			}
			det = sqrt(det); /// already divided by 2 here
			float min_dist = (b - det) / a; /// still needs to be divided by A
			float max_dist = (b + det) / a;
			dis = float2(min_dist, max_dist);
			/*if (max_dist > 0.0) {
				return true;
			}
			else {
				return false;
			}*/
			return true;
		}
		//射线与平面相交检测
		bool rayCastPlane(float3 start, float3 dir, float3 o, float3 normal,out float dis)
		{
			float div = dot(dir, normal);
			if (div >= 0)
				return false;
			dis = (dot(o, normal) - dot(start, normal)) / div;
			if (dis < 0)
				return false;
			return true;
		}
		ENDCG

        Tags { "RenderType"="Transparent" }
        LOD 200
		Pass
		{
			Blend SrcAlpha OneMinusSrcAlpha
			ZWrite Off
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#include "UnityCG.cginc"
			#include "Lighting.cginc"
			#include "Autolight.cginc"

			struct appdata
			{
				float4 vertex:POSITION;
				float2 uv:TEXCOORD;
			};
			struct v2f
			{
				float4 pos:POSITION;
				float2 uv:TEXCOORD;
				float4 worldPos:TEXCOORD1;
				float3 uv3:TEXCOORD2;
			};
			float _Radius;
			float _Top;
			float _Bottom;
			float _Edge;
			float _Absorption;
			float _G;
			float _Thickness;
			float _LightPos;
			float _LightFadeOut;
			sampler2D _CameraDepthTexture;
			sampler2D _Noise;
			sampler2D _Shape;
			float4 _Shape_ST;
			sampler2D _MainTex;
			float4 _CloudColor;
			float4 _LightColor;
			sampler3D _Noise3D; 
			sampler3D _Noise3D_Detail;
			float _UVScale;
			float _Curl;
			v2f vert(appdata i)
			{
				v2f o;
				o.pos = UnityObjectToClipPos(i.vertex);
				o.uv = i.uv;
				o.worldPos = mul(unity_ObjectToWorld, i.vertex);
				o.uv3 = i.vertex.xyz;
				return o;
			}
			float fbm(float2 st) {
				float value = 0.0;
				float amplitude = .5;

				for (int k = 0; k < 3; k++) {
					value += amplitude * tex2Dlod(_Noise,float4(st,0,0));
					st *= 2.;
					amplitude *= .5;
				}
				return value;
			}
			//
			float2 curlUV(float2 st)
			{
				st.x += st.y * _Curl;
				return st;
			}
			//将点映射为圆柱采样的UV
			float2 circleUV(float3 p)
			{
				float3 h = float3(p.x, 0, p.z);
				float3 f = float3(0, 0, 1);
				return float2(SignedAngle(f, h) / 2 / 3.14159, ((p.y - _Bottom) / (_Top-_Bottom)));
			}

			//光线向前散射的概率
			float HenyeyGreenstein(float cosine)
			{
				float coeff = _G;
				float g2 = coeff * coeff;
				return (1 - g2) / (4 * 3.1415*pow(1 + g2 - 2 * coeff * cosine, 1.5));
			}
			//光穿过云的衰减
			float Beer(float depth)
			{
				return exp(-_Absorption * depth);
			}
			//光在云中的折射，糖分效应
			float BeerPowder(float depth)
			{
				float e = 1;
				return exp(-e * depth) * (1 - exp(-e * 2 * depth));
			}
			//云的采样
			float4 sampleCloud(float3 p)
			{
				float hPercent = saturate((p.y - _Bottom) / (_Top - _Bottom));
				//旋转动画
				float den = hPercent;
				float angAnim = den + 0.1*_Time.w;
				float co = cos(angAnim);
				float si = sin(angAnim);
				p.xz = mul(float2x2(co, -si, si, co), p.xz);
				p.y += _Time.y;

				//旋转度从低到高递减
				float ang = _Curl * (1 - hPercent);
				si = sin(ang);
				co = cos(ang);
				float2x2 rotation = float2x2(co, -si, si, co);
				p.xz = mul(rotation, p.xz);

				float2 uv = circleUV(p);
				//FBM,扭曲uv，让云的运动更自然
				float2 q = float2(0, 0);
				q.x = fbm(uv);
				q.y = fbm(uv + 1);
				float2 r = float2(0,0);
				r.x = fbm(uv + q + float2(1.7, 9.2) + 0.015*_Time.w)*0.15;
				r.y = fbm(uv + q + float2(8.3, 2.8) + 0.0126*_Time.w)*0.07;
				uv += r;

				float l = length(float2(p.x, p.z)) - _Radius;
				float thickPercent = 1 - (l / _Thickness);
				float4 shape = tex2Dlod(_Shape,float4( uv*_Shape_ST.xy + _Shape_ST.zw,0,0));//越靠风暴中心，云的起伏形状程度越高

				float heightFra = saturate(remap(thickPercent, 0, shape.x, 1, 0));
				if (heightFra < 0.01)
					return 0;
				float4 noise3 = tex3Dlod(_Noise3D, float4(p*_UVScale, 0));

				//云的边缘，增加一些旋转的细节
				float2 curl_noise = normalize(curlUV(uv));
				p.xy += curl_noise.xy *(1-thickPercent);
				float4 highFrequency = tex3Dlod(_Noise3D_Detail, float4(p,0));
				return saturate(remap(noise3 * heightFra, highFrequency*_Edge, 1, 0, 1));
			}
			//云的光照
			float lightEnergy(float3 start)
			{
				float3 lightPos = float3(0, _LightPos, 0);
				float3 lightDir = start- lightPos;
				lightDir = normalize(lightDir);
				fixed stepCount = 3;

				float2 minMax = float2(0, 0);
				float dis = 0;
				if (!rayCastCircle(start, lightDir, _Radius, minMax))
				{
					dis =abs( minMax.y);
				}
				dis = abs(minMax.y);
				float stepSize = dis / (stepCount - 1);
				float3 samplePos = start;
				float density = 0;
				for (fixed j = 0; j < stepCount; j++)
				{
					float d = sampleCloud(samplePos).x;

					density += d * stepSize;
					samplePos = start + lightDir * stepSize*(j + random(samplePos.z));
					//samplePos += lightDir * stepSize;
					if (density < 0.01)
						break;
				}
				return Beer(density*0.15);
			}

			//云的光线步进
			float4 rayMarch(float3 start, float3 dir)
			{
				fixed stepCount = 32;
				float density = 1;
				float3 lightPos = float3(0, _LightPos, 0);
				float3 lightDir = start - lightPos;
				float d = dot(normalize(lightDir.xyz), normalize(dir));
				float hg = HenyeyGreenstein(d);

				float2 minMax2 = float2(0, 0);
				if (!rayCastCircle(start, dir, _Radius+_Thickness+20, minMax2))
				{
					return float4(0, 0, 0, 0);
				}
				float dis = minMax2.y;

				float stepSize = dis / stepCount;

				float3 samplePos = start;
				float light = 0;
				for (fixed i = 0; i < stepCount; i++)
				{
					float d = sampleCloud(samplePos).x;
					float lightDen = lightEnergy(samplePos);

					light += lightDen*d*stepSize*BeerPowder(density);
					density *= Beer(d *stepSize);
					samplePos = start + dir * stepSize*(i + random(samplePos.z));
					//samplePos += dir * stepSize;
					if (density < 0.01)
						break;
				}
				light = saturate(light * (hg + 0.45))*(1 - saturate((_Bottom - start.y) / _LightFadeOut));
				density =1 - density;
				float3 col = lerp(_CloudColor.rgb, _LightColor.rgb,light);
				//return light;
				
				return float4(col,density);
			}
			float lightningFBM(float2 st) {
				float value = 0.0;
				float amplitude = .2;
				float frequency = 0.;
				for (int k = 0; k < 6; k++) {
					value += amplitude * tex2Dlod(_Noise, float4(st, 0, 0));
					st *= 2.;
					amplitude *= .1;
				}
				return value;
			}
			//闪电
			float4 lightning(float3 p,float3 dir)
			{
				float3 planeNormal = -normalize(float3(dir.x, 0, dir.z));
				float dis = 0;
				if (!rayCastPlane(p, dir, float3(0, 0, 0), planeNormal,dis))
				{
					return 0;
				}
				float3 castP = p + dir*dis;
				if (castP.y < _Bottom || castP.y>_Top)
					return 0;
				fixed uvDir = 1;//判断交点在原点的左右，用来保证uv0~1
				if (cross(castP, planeNormal).y < 0)
				{
					uvDir = -1;
				}
				float projDis = length(castP.xz);
				float lightWidth = 10;
				if (projDis > lightWidth)
				{
					return 0;
				}
				//计算绘制闪电的平面的uv
				float2 st = float2(((length(castP.xz)*uvDir / lightWidth)+1)/2, ((castP.y - _Bottom) / (_Top - _Bottom))*6);

				//对uv的x进行fbm
				st.x += lightningFBM(st + _Time.z)*2*st.x;
				st.x *= st.x;
				//将0~1变为0~1~0
				st.x = (0.5 - abs(st.x - 0.5)) * 2 * 5 - 4;
				return lerp(float4(_LightColor.rgb,0), _LightColor, saturate(st.x));
			}
			//光球
			float4 lightSphere(float3 p, float3 dir)
			{
				float3 planeNormal = -dir;
				float dis = 0;
				float3 o = float3(0, _Bottom, 0);
				if (!rayCastPlane(p, dir, o, planeNormal, dis))
				{
					return 0;
				}
				
				float3 castP = p + dir * dis;
				float t = length(castP - o) / _Radius;
				float glow = (0.7 - saturate(t - 0.3)) / 0.7;
				if (glow < 0||glow >1)
					return 0;
				return lerp(float4(_LightColor.rgb, 0), _LightColor, glow);
			}

			float4 frag(v2f i):SV_TARGET
			{
				float4 col = tex2D(_MainTex,i.uv);
				float4 cloud = float4(0, 0, 0, 0);
				float depth = UNITY_SAMPLE_DEPTH(tex2D(_CameraDepthTexture, i.uv));
				float linearDepth = Linear01Depth(depth);
				float3 rayEnd = GetWorldPositionFromDepth(i.uv, depth).xyz;
				float3 camPos = _WorldSpaceCameraPos.xyz;
				float3 dir = normalize(rayEnd - camPos);
				float2 minMax1 = float2(0, 0);
				if (rayCastCircle(camPos, dir, _Radius, minMax1))
				{
					if (minMax1.y < length(camPos-rayEnd))
					{
						float3 castPos = camPos + dir * minMax1.y;
						cloud = rayMarch(castPos, dir);
					}
				}
				col.rgb = lerp(col.rgb, cloud.rgb, cloud.a);
				float4 lightningCol = lightning(camPos, dir);
				col.rgb = lerp(col.rgb, lightningCol.rgb, lightningCol.a);
				float4 sphereCol = lightSphere(camPos, dir);
				col.rgb = lerp(col.rgb, sphereCol.rgb, sphereCol.a);

				//col = lightningCol;
				clip(col.a); 
				//return float4( _WorldSpaceLightPos0.xyz/10,1);
				return col;
			}
			ENDCG
		}
    }
    FallBack "Diffuse"
}
