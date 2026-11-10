#version 450
// Sky (Vulkan_SkyBox.pas): a day and a night panorama blended by the sun's
// height, with twilight, the sun and the moon drawn on top.
//
// Sky space is (east, up, north).  The panoramas are equirectangular: north
// in the middle, east to its right, the zenith along the top edge.

layout(set = 1, binding = 0) uniform sampler2D DaySky;
layout(set = 1, binding = 1) uniform sampler2D NightSky;

layout(location = 0) in vec2 fragNDC;
layout(location = 1) flat in vec3 fragRow0;
layout(location = 2) flat in vec3 fragRow1;
layout(location = 3) flat in vec3 fragRow2;
layout(location = 4) flat in vec3 fragRow3;
layout(location = 5) flat in vec4 fragParams;    // day factor, Z-up, sun visible, moon visible
layout(location = 6) flat in vec3 fragSunDir;
layout(location = 7) flat in vec3 fragMoonDir;
layout(location = 8) flat in vec3 fragSizes;     // brightness, sun size, moon size (degrees)

layout(location = 0) out vec4 outColor;

const float PI = 3.14159265358979;

float hash(vec2 p)
{
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float valueNoise(vec2 p)
{
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
               mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void main()
{
    // The direction d whose point at infinity lands on this pixel:
    // (row0 . d) / (row3 . d) = x and (row1 . d) / (row3 . d) = y, so d is
    // perpendicular to both (row0 - x row3) and (row1 - y row3).
    vec3 d = cross(fragRow0 - fragNDC.x * fragRow3, fragRow1 - fragNDC.y * fragRow3);
    // Of the two answers, the one in front of the camera: positive w for a
    // perspective, increasing depth for an orthographic view (row3 is zero).
    float front = dot(fragRow3, d);
    if (dot(fragRow3, fragRow3) < 1e-12)
        front = dot(fragRow2, d);
    if (front < 0.0)
        d = -d;
    float len = length(d);
    d = (len > 0.0) ? d / len : vec3(0.0, 1.0, 0.0);

    // World to sky space: Z-up is (east, north, up), Y-up has north along -Z.
    vec3 sky = (fragParams.y > 0.5) ? vec3(d.x, d.z, d.y) : vec3(d.x, d.y, -d.z);

    float dayF       = clamp(fragParams.x, 0.0, 1.0);
    float sunVis     = fragParams.z;
    float moonVis    = fragParams.w;
    vec3  sun        = normalize(fragSunDir);
    vec3  moon       = normalize(fragMoonDir);
    float above      = smoothstep(-0.015, 0.01, sky.y);     // not through the ground

    // No mip level may be picked from the derivative: it jumps at the seam.
    vec2 uv = vec2(atan(sky.x, sky.z) / (2.0 * PI) + 0.5,
                   0.5 - asin(clamp(sky.y, -1.0, 1.0)) / PI);
    vec3 day   = textureLod(DaySky,   uv, 0.0).rgb;
    vec3 night = textureLod(NightSky, uv, 0.0).rgb;

    // A low sun dims and warms the day sky.
    float high = smoothstep(0.0, 0.35, sun.y);
    day *= mix(vec3(0.62, 0.52, 0.52), vec3(1.0), mix(1.0, high, sunVis));

    vec3 col = mix(night, day, dayF);

    // Twilight: a warm band along the horizon, strongest towards the sun,
    // while the sun is near the horizon - fading sooner once it is below.
    float twilight = sunVis * ((sun.y >= 0.0) ? 1.0 - smoothstep(0.0, 0.32, sun.y)
                                              : 0.75 * (1.0 - smoothstep(0.0, 0.22, -sun.y)));
    if (twilight > 0.0)
    {
        vec2  sh     = sun.xz;
        float shl    = length(sh);
        float toward = 0.5;
        float hl     = length(sky.xz);
        if (shl > 1e-4 && hl > 1e-4)
            toward = dot(sky.xz / hl, sh / shl) * 0.5 + 0.5;
        float band = exp(-max(sky.y, 0.0) * 5.5) * smoothstep(-0.09, 0.0, sky.y);
        vec3  glow = mix(vec3(1.00, 0.36, 0.12), vec3(1.00, 0.70, 0.40), smoothstep(-0.12, 0.25, sun.y));
        col += glow * twilight * band * (0.18 + 0.82 * pow(toward, 3.0)) * 0.85;
    }

    // Sun: a disc with a tight and a wide halo, reddening as it sets.
    if (sunVis > 0.0)
    {
        float c      = dot(sky, sun);
        float r      = radians(max(fragSizes.y, 0.05)) * 0.5;
        float disc   = smoothstep(cos(r * 1.12), cos(r * 0.92), c);
        float halo   = pow(max(c, 0.0), 420.0) * 0.55 + pow(max(c, 0.0), 14.0) * 0.16;
        vec3  sunCol = mix(vec3(1.00, 0.45, 0.16), vec3(1.00, 0.97, 0.90), smoothstep(0.0, 0.30, sun.y));
        col = mix(col, sunCol * 1.25, disc * sunVis * above);
        col += sunCol * halo * sunVis * above * smoothstep(-0.10, 0.05, sun.y);
    }

    // Moon: a sphere lit from the sun's direction, so its phase is right
    // for wherever the two are.
    if (moonVis > 0.0)
    {
        float r  = radians(max(fragSizes.z, 0.05)) * 0.5;
        float c  = dot(sky, moon);
        float sr = sin(r);
        vec3  q  = (sky - moon * c) / sr;             // across the disc, length 0 .. 1
        float q2 = dot(q, q);
        if (c > 0.0 && q2 < 1.0)
        {
            vec3  n    = normalize(q - moon * sqrt(1.0 - q2));
            float lit  = smoothstep(-0.05, 0.25, dot(n, sun));
            // Maria: darker patches, fixed to the disc.
            vec3  ref  = (abs(moon.y) < 0.95) ? vec3(0, 1, 0) : vec3(1, 0, 0);
            vec3  tx   = normalize(cross(ref, moon));
            vec3  ty   = cross(moon, tx);
            vec2  p    = vec2(dot(q, tx), dot(q, ty));
            float mare = valueNoise(p * 2.6 + 7.0) * 0.6 + valueNoise(p * 6.5 + 3.0) * 0.4;
            vec3  surf = vec3(0.96, 0.94, 0.88) * (0.72 + 0.28 * smoothstep(0.35, 0.65, mare));
            vec3  mc   = surf * (0.035 + lit);
            float edge = 1.0 - smoothstep(0.90, 1.0, q2);
            // By day only the lit part shows, and faintly.
            float a    = edge * moonVis * above * mix(1.0, 0.55 * lit, dayF);
            col = mix(col, mix(mc, col + mc * 0.5, dayF), a);
        }
        col += vec3(0.55, 0.62, 0.80) * pow(max(c, 0.0), 900.0) * 0.20 * moonVis * above * (1.0 - dayF);
    }

    outColor = vec4(col * fragSizes.x, 1.0);
}
