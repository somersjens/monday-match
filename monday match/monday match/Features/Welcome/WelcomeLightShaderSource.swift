/// Compiled by the system Metal driver once per process; no media assets.
enum WelcomeLightShaderSource {
    static let code = #"""
#include <metal_stdlib>
using namespace metal;

constant float tau = 6.28318530718;
constant uint samples = 512;
constant uint strands = 60;

struct WelcomeUniforms {
    float4 shape;       // continuous periodic deformation clock, heart, separation, continuous seconds
    float4 projection;  // radius x/y, rotation cosine/sine
    float4 viewport;    // drawable x/y, geometry scale, pixels per point
    float4 space;       // depth volume, center drift x/y
    float4 calibration; // measured projected size
    float4 entrance;    // head arc distance, inlet opacity, head glow, dust opacity
    float4 stream;      // material travel, carried weave strength, tail distance, starting u
};

struct RibbonVertex {
    float4 position [[position]];
    float distance;
    float depth;
    float intensity;
    float coreWidth;
    float3 color;
    float2 screen;
};

float2 heartEdge(float u, uint edge, device const float2 *controls) {
    float section = fract(u) * 32.0;
    uint segment = min(uint(section), 31u);
    float t = fract(section), v = 1.0 - t;
    uint i = edge * 128 + segment * 4;
    return v*v*v * controls[i] + 3*v*v*t * controls[i+1]
         + 3*v*t*t * controls[i+2] + t*t*t * controls[i+3];
}

float3 ribbonPoint(float u, uint instance, constant WelcomeUniforms &p, device const float2 *controls) {
    uint ring = instance / strands;
    uint strand = instance % strands;
    uint sheet = strand / 20;
    float lane = (float(strand % 20) / 19.0 - 0.5) * 2
        + 0.018*sin(float(strand)*7.31 + p.shape.x);
    float side = ring == 0 ? -1.0 : 1.0;
    float a = u * tau;
    float clock = p.shape.x;
    float heartFlow = smoothstep(0.15, 0.85, p.shape.y);
    float phase = float(sheet) * 2.15 + side * 1.25 + lane*(0.55 + heartFlow*0.50);
    float flowSpeed = sheet == 0 ? -3.0 : (sheet == 1 ? 2.0 : -2.0);
    float flow = 2*a + flowSpeed*clock + phase;
    float2 circle = float2(side * p.shape.z - sin(a)*p.projection.x, -cos(a)*p.projection.y);
    float2 base = mix(circle, heartEdge(u, instance, controls), p.shape.y);
    float2 radial = base - float2(side * p.shape.z * (1-p.shape.y), 0);

    // A sheet has width, torsion and local eddies. Threads slide through it
    // instead of all following one deformed outline or a rigid tube.
    float looseness = 0.045 + 0.065*p.shape.y;
    float radialWave = looseness * (0.85*sin(flow) + 0.35*sin(3*a-clock+phase));
    float spread = lane * (0.065 + 0.055*p.shape.y) * sin(2*a+clock+phase);
    float2 point = base + radial * (radialWave + spread) * (1-heartFlow);
    point += (1-heartFlow)*float2(0.022*sin(3*a-2*clock+phase), 0.020*cos(2*a+3*clock+phase));
    point.y += (1-heartFlow)*0.016*sin(clock+phase);

    // The traced edges define the whole heart, including its folds. A small
    // travelling displacement keeps those anchors alive without replacing the
    // reference silhouette with a procedural radial wave.
    point += heartFlow * float2(0.012*sin(3*a-2*clock+phase),
                                0.014*sin(4*a+clock+phase)) * sin(clock);
    point += heartFlow * side * 0.006 * float2(sin(2*a+phase), cos(3*a+phase));

    // Transport the weave along the path while it is being pulled into place.
    // This is moving geometry as well as moving light, not a frozen reveal.
    if (p.stream.y > 0.0001) {
        float2 tangent = heartEdge(u+0.002,instance,controls)-heartEdge(u-0.002,instance,controls);
        float2 normal = normalize(float2(-tangent.y,tangent.x)+float2(1e-7,0));
        float carried = sin((u-p.stream.w)*tau*3-p.stream.x*tau*3+phase+lane*0.8);
        point += normal*carried*0.025*p.stream.y;
    }

    // Depth stays bounded throughout the full rotation, including the return
    // to the heart, so the advancing waves do not turn into a tangled volume.
    float z = p.space.x * (0.78*sin(2*a-2*clock+phase) + lane*0.48*cos(3*a+clock+phase));
    float lag = (1-heartFlow)*(0.065*sin(clock+phase) + lane*0.020);
    float c = p.projection.z*cos(lag) - p.projection.w*sin(lag);
    float s = p.projection.w*cos(lag) + p.projection.z*sin(lag);
    float x = point.x*c + z*s;
    float depth = -point.x*s + z*c;
    float tilt = (1-heartFlow)*0.025*sin(clock+phase);
    float perspective = 1.0 / (1.0 + depth*0.12*(1-heartFlow*0.8));
    return float3((float2(x + point.y*tilt, point.y - x*tilt + depth*0.035*(1-heartFlow))*perspective*p.calibration.xy + p.space.yz), depth);
}

RibbonVertex lightVertex(float u, float3 point, float2 previous, float2 next,
                         float edge, uint instance, float travel, constant WelcomeUniforms &p) {
    float2 tangent = normalize(next - previous + float2(1e-7, 0));
    float2 normal = float2(-tangent.y, tangent.x);
    float halfWidth = 7.5 * p.viewport.w;
    float2 screen = p.viewport.xy*0.5 + point.xy*p.viewport.z + normal*edge*halfWidth;
    uint strand = instance % strands;
    uint sheet = strand / 20;
    float phase = float(sheet)*2.15 + float(instance/strands)*1.7;
    float lightClock = p.shape.w / 6.042 * tau;
    float heartFlow = smoothstep(0.15, 0.85, p.shape.y);
    float light = pow(0.5 + 0.5*sin(u*tau*2 - lightClock*3 + phase), 3.0);
    float highlight = (strand % 20 == 6 && sheet != 1) ? 1.0 : 0.0;
    float3 cyan = mix(float3(0.035, 0.63, 1.0), float3(0.22, 0.63, 0.88), heartFlow);
    float3 blue = float3(0.07, 0.18, 0.95);
    float3 pink = mix(float3(0.68, 0.085, 0.50), float3(0.56, 0.18, 0.80), heartFlow);
    float tint = pow(0.5 + 0.5*sin(u*tau + lightClock + phase), 3.0);
    float3 color = sheet == 0 ? mix(cyan, float3(0.27,0.62,1), tint*0.3)
                 : (sheet == 1 ? mix(blue, cyan, tint) : mix(float3(0.34,0.11,0.75), pink, tint));
    color = mix(color, float3(0.47,0.84,1), highlight*light*0.5);
    RibbonVertex out;
    out.position = float4(screen.x/p.viewport.x*2-1, 1-screen.y/p.viewport.y*2, 0, 1);
    out.distance = edge * halfWidth / p.viewport.w;
    out.depth = point.z;
    out.intensity = (0.022 + heartFlow*0.019 + (0.055 + heartFlow*0.015)*light + highlight*(0.22 + 0.65*light)*(1-heartFlow*0.34)) * (0.72 + 0.28*cos(u*tau + phase));
    // Finish the tiny soft reveal edge before closure; at head distance 1
    // every pixel already uses the ordinary loop, including the closing join.
    float visible = mix(smoothstep(-0.008,0.008,p.entrance.x-travel),1.0,
                        smoothstep(0.97,1.0,p.entrance.x));
    // The head rounds the final bend and continues along the closed path.
    // Near closure, stretch the leading glow along separate filaments and
    // blend it into their ordinary light. Its total energy falls as it spreads.
    float dissolve = smoothstep(0.68,1.05,p.entrance.x);
    float filamentLag = dissolve*0.032*(0.5+0.5*sin(float(strand)*1.71+phase));
    float headDistance = travel-p.entrance.x+filamentLag;
    if (travel >= 0 && p.entrance.x >= 0.95) headDistance -= round(headDistance);
    float headWidth = mix(0.018,0.065,dissolve);
    float head = exp(-pow(headDistance/headWidth,2.0))*p.entrance.z*mix(1.0,0.28,dissolve);
    float carried = pow(0.5+0.5*sin((travel-p.stream.x)*tau*3+phase),3.0);
    out.intensity *= visible*(1 + head*0.85)*mix(1.0,0.65+0.70*carried,p.stream.y);
    color = mix(color, float3(0.55,0.85,1), head*mix(0.5,0.12,dissolve));
    out.coreWidth = 1 + highlight*(1.3 - 0.45*heartFlow) + head*0.45;
    out.color = color;
    out.screen = screen;
    return out;
}

vertex RibbonVertex welcomeRibbonVertex(uint vertexID [[vertex_id]], uint instance [[instance_id]],
                                        constant WelcomeUniforms &p [[buffer(0)]],
                                        device const float2 *controls [[buffer(1)]],
                                        device const float *travel [[buffer(2)]]) {
    // Keep this vertex ordering after the entrance: no remesh at the handoff.
    float u = p.stream.w + float(vertexID / 2) / float(samples);
    float edge = (vertexID & 1) ? 1.0 : -1.0;
    float3 point = ribbonPoint(u, instance, p, controls);
    float2 previous = ribbonPoint(u - 0.5/float(samples), instance, p, controls).xy;
    float2 next = ribbonPoint(u + 0.5/float(samples), instance, p, controls).xy;
    return lightVertex(u, point, previous, next, edge, instance, travel[vertexID/2], p);
}

float2 entrancePoint(float t, float2 tip, float2 direction, uint instance, float transport) {
    float2 start = float2(-1.65,1.95), c1 = float2(-0.95,1.45);
    float2 c2 = tip-direction*0.65;
    float v = 1-t;
    float lane = float(instance%20)/19*2-1;
    uint sheet = (instance%strands)/20, ring = instance/strands;
    float phase = float(sheet)*2.15+float(ring)*1.7+lane*0.85;
    float flow = t*tau*1.4-transport*tau*2+phase;
    float cross = 0.065*sin(flow)+lane*0.055*cos(t*tau+phase)+0.020*sin(2*flow+phase);
    float along = 0.025*sin(t*tau*2-transport*tau*2+phase);
    float2 tangent = normalize(3*v*v*(c1-start)+6*v*t*(c2-c1)+3*t*t*(tip-c2));
    float2 normal = float2(-tangent.y,tangent.x);
    // Wide, travelling sheets match the heart's woven structure. The envelope
    // leaves the exact position and tangent at the heart join unchanged.
    float veil = pow(4*t*(1-t),2.0);
    return v*v*v*start+3*v*v*t*c1+3*v*t*t*c2+t*t*t*tip
         + veil*(normal*cross+tangent*along);
}

vertex RibbonVertex welcomeEntranceVertex(uint vertexID [[vertex_id]], uint instance [[instance_id]],
                                          constant WelcomeUniforms &p [[buffer(0)]],
                                          device const float2 *controls [[buffer(1)]],
                                          device const float *distance [[buffer(2)]]) {
    float t = float(vertexID/2)/128.0;
    float edge = (vertexID & 1) ? 1.0 : -1.0;
    float3 tip = ribbonPoint(p.stream.w, instance, p, controls);
    float2 direction = normalize(ribbonPoint(p.stream.w+0.001,instance,p,controls).xy
                               - ribbonPoint(p.stream.w-0.001,instance,p,controls).xy);
    float2 point = entrancePoint(t,tip.xy,direction,instance,p.stream.x);
    float2 previous = entrancePoint(t-0.5/128.0,tip.xy,direction,instance,p.stream.x);
    float2 next = entrancePoint(t+0.5/128.0,tip.xy,direction,instance,p.stream.x);
    float travel = distance[samples+1+vertexID/2];
    RibbonVertex out = lightVertex(p.stream.w+travel,float3(point,tip.z),previous,next,edge,instance,travel,p);
    // A finite thread is pulled in from its back end as the head advances.
    float tail = smoothstep(-0.012,0.012,travel-p.stream.z);
    out.intensity *= p.entrance.y*tail;
    return out;
}

fragment float4 welcomeRibbonFragment(RibbonVertex in [[stage_in]], constant WelcomeUniforms &p [[buffer(0)]]) {
    float d = in.distance;
    // Emission, a soft sheath, and wide bloom coexist per thread. Depth softens
    // distant strands rather than drawing every line equally sharp and bright.
    float focus = 1 + abs(in.depth)*0.65;
    float core = exp(-d*d / (2*0.16*0.16*focus*focus*in.coreWidth*in.coreWidth)) * 0.52;
    float sheath = exp(-d*d / (2*0.55*0.55*focus*focus*in.coreWidth)) * 0.12;
    float halo = exp(-d*d / (2*2.0*2.0)) * 0.012;
    float border = min(min(in.screen.x, p.viewport.x-in.screen.x), min(in.screen.y, p.viewport.y-in.screen.y));
    float energy = (core + sheath + halo) * in.intensity * 2.8 * smoothstep(0.0, p.viewport.w*9, border);
    float3 color = in.color * energy;
    return float4(color, 0);
}

struct DustVertex {
    float4 position [[position]];
    float2 offset;
    float opacity;
};

float noise(float seed) { return fract(sin(seed*127.1+311.7)*43758.5453); }

vertex DustVertex welcomeDustVertex(uint vertexID [[vertex_id]], uint instance [[instance_id]], constant WelcomeUniforms &p [[buffer(0)]]) {
    float seed = float(instance);
    float clock = p.shape.w / 6.042 * tau; // One full periodic cycle, with matching position and velocity at the seam.
    float angle = noise(seed+7)*tau + 0.035*sin(clock);
    float radius = sqrt(noise(seed+91))*1.10;
    float2 center = float2(cos(angle)*(radius + 0.014*sin(clock+seed)), sin(angle)*radius);
    float2 corner = float2((vertexID & 1) ? 1 : -1, (vertexID & 2) ? 1 : -1);
    float size = (1.8 + noise(seed+43)*0.8) * p.viewport.w;
    float2 screen = p.viewport.xy*0.5 + center*p.viewport.z + corner*size;
    DustVertex out;
    out.position = float4(screen.x/p.viewport.x*2-1, 1-screen.y/p.viewport.y*2, 0, 1);
    out.offset = corner;
    out.opacity = (0.035 + pow(0.5+0.5*sin(clock+seed*2.3), 3.0)*0.16)*p.entrance.w;
    return out;
}

fragment float4 welcomeDustFragment(DustVertex in [[stage_in]]) {
    float r = length(in.offset);
    float energy = (exp(-r*r*26) + exp(-r*r*4)*0.07) * in.opacity * 3.0;
    return float4(float3(0.10,0.35,1)*energy, 0);
}


struct CompositeVertex {
    float4 position [[position]];
    float2 uv;
};

vertex CompositeVertex welcomeCompositeVertex(uint id [[vertex_id]]) {
    float2 position = float2((id == 1) ? 3.0 : -1.0, (id == 2) ? -3.0 : 1.0);
    CompositeVertex out;
    out.position = float4(position, 0, 1);
    out.uv = float2(position.x*0.5+0.5, 0.5-position.y*0.5);
    return out;
}

fragment float4 welcomeCompositeFragment(CompositeVertex in [[stage_in]],
                                         constant WelcomeUniforms &p [[buffer(0)]],
                                         texture2d<float> emission [[texture(0)]]) {
    constexpr sampler linearSampler(filter::linear, address::clamp_to_zero);
    float3 core = emission.sample(linearSampler, in.uv).rgb;
    float3 nearGlow = 0, farGlow = 0, silkGlow = 0;
    float2 pixel = p.viewport.w / p.viewport.xy;
    for (uint i=0; i<8; i++) {
        float angle = float(i)*tau/8;
        float2 direction = float2(cos(angle), sin(angle));
        nearGlow += emission.sample(linearSampler, in.uv + direction*pixel*1.8).rgb;
        farGlow += emission.sample(linearSampler, in.uv + direction*pixel*5.5).rgb;
        silkGlow += emission.sample(linearSampler, in.uv + direction*pixel*11).rgb;
    }
    nearGlow /= 8;
    farGlow /= 8;
    float heartFlow = smoothstep(0.15, 0.85, p.shape.y);
    float3 light = core + nearGlow*0.72 + farGlow*0.55 + silkGlow/8*heartFlow*0.60;
    float3 radiance = 1 - exp(-light*1.8);
    float2 centered = (in.uv - 0.5)*p.viewport.xy / (min(p.viewport.x,p.viewport.y)*0.5);
    float haze = pow(max(0.0, 1-length(centered)), 1.7);
    float3 background = float3(0.008,0.012,0.035) + float3(0.005,0.012,0.125)*haze;
    // Fade every effect to the exact welcome background before the view edge.
    float2 screen = in.uv*p.viewport.xy;
    float border = min(min(screen.x,p.viewport.x-screen.x),min(screen.y,p.viewport.y-screen.y));
    return float4(background + radiance*smoothstep(0.0,p.viewport.w*10,border), 1);
}

"""#
}
