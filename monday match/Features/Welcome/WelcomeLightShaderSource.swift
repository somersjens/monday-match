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
    float4 lock;        // lock or helix progress, shackle lift, shake, 1 for the helix
    float4 code;        // progress from the helix to the QR code, modules per side
};

struct RibbonVertex {
    float4 position [[position]];
    float distance;
    float depth;
    float intensity;
    float coreWidth;
    float3 color;
    float2 screen;
    float2 local;       // position on the QR code's grid
    float code;         // how far this point belongs to the QR code
};

float2 heartEdge(float u, uint edge, device const float2 *controls) {
    float section = fract(u) * 32.0;
    uint segment = min(uint(section), 31u);
    float t = fract(section), v = 1.0 - t;
    uint i = edge * 128 + segment * 4;
    return v*v*v * controls[i] + 3*v*v*t * controls[i+1]
         + 3*v*t*t * controls[i+2] + t*t*t * controls[i+3];
}

// The padlock mirrors WelcomeLightLock in Swift. Every outline starts at its
// top centre and runs the same way round as the heart's traced edges.
struct LockSegment {
    float2 a;     // line start, or arc centre
    float2 b;     // line end, or arc start and end angles
    float radius; // zero for a line
};

LockSegment lockLine(float2 from, float2 to) { return {from, to, 0.0}; }
LockSegment lockArc(float2 center, float radius, float from, float to) { return {center, float2(from, to), radius}; }

float lockLength(LockSegment s) {
    return s.radius > 0 ? s.radius*abs(s.b.y - s.b.x) : distance(s.a, s.b);
}

float2 lockSegmentPoint(LockSegment s, float t) {
    if (s.radius <= 0) return mix(s.a, s.b, t);
    float angle = mix(s.b.x, s.b.y, t);
    return s.a + s.radius*float2(cos(angle), sin(angle));
}

float2 lockEvaluate(thread const LockSegment *segments, int count, float u) {
    float total = 0;
    for (int i = 0; i < count; i++) total += lockLength(segments[i]);
    float d = fract(u)*total;
    for (int i = 0; i < count - 1; i++) {
        float l = lockLength(segments[i]);
        if (d <= l) return lockSegmentPoint(segments[i], d/l);
        d -= l;
    }
    return lockSegmentPoint(segments[count - 1], min(d/lockLength(segments[count - 1]), 1.0));
}

constant float2 lockShackleCenter = float2(0, -0.44);
constant float lockOuterRadius = 0.42, lockInnerRadius = 0.26, lockJoint = 0.04;
constant float lockBodyTop = 0.30 - 0.47, lockBodyBottom = 0.30 + 0.47;
constant float lockBodySide = 0.70, lockCornerRadius = 0.18;

float2 lockSilhouette(float u) {
    const float2 c = lockShackleCenter;
    const float R = lockOuterRadius, j = lockJoint, r = lockCornerRadius;
    const float top = lockBodyTop, bottom = lockBodyBottom, side = lockBodySide, corner = side - r;
    const float pi = M_PI_F;
    LockSegment s[15] = {
        lockArc(c, R, -pi*0.5, -pi),
        lockLine(float2(-R, c.y), float2(-R, top - j)),
        lockArc(float2(-R - j, top - j), j, 0.0, pi*0.5),
        lockLine(float2(-R - j, top), float2(-corner, top)),
        lockArc(float2(-corner, top + r), r, -pi*0.5, -pi),
        lockLine(float2(-side, top + r), float2(-side, bottom - r)),
        lockArc(float2(-corner, bottom - r), r, pi, pi*0.5),
        lockLine(float2(-corner, bottom), float2(corner, bottom)),
        lockArc(float2(corner, bottom - r), r, pi*0.5, 0.0),
        lockLine(float2(side, bottom - r), float2(side, top + r)),
        lockArc(float2(corner, top + r), r, 0.0, -pi*0.5),
        lockLine(float2(corner, top), float2(R + j, top)),
        lockArc(float2(R + j, top - j), j, pi*0.5, pi),
        lockLine(float2(R, top - j), float2(R, c.y)),
        lockArc(c, R, 0.0, -pi*0.5),
    };
    return lockEvaluate(s, 15, u);
}

float2 lockOpening(float u) {
    const float2 c = lockShackleCenter;
    const float a = lockInnerRadius, j = lockJoint, top = lockBodyTop, pi = M_PI_F;
    LockSegment s[7] = {
        lockArc(c, a, -pi*0.5, -pi),
        lockLine(float2(-a, c.y), float2(-a, top - j)),
        lockArc(float2(-a + j, top - j), j, pi, pi*0.5),
        lockLine(float2(-a + j, top), float2(a - j, top)),
        lockArc(float2(a - j, top - j), j, pi*0.5, 0.0),
        lockLine(float2(a, top - j), float2(a, c.y)),
        lockArc(c, a, 0.0, -pi*0.5),
    };
    return lockEvaluate(s, 7, u);
}

float2 lockKeyhole(float u) {
    float angle = fract(u)*tau;
    float s = sin(angle), c = cos(angle);
    float tail = pow(max(0.0, -c), 6.0);
    return float2(-s*0.085*(1 - 0.55*tail), 0.22 - c*0.085 + tail*0.20);
}

float2 lockOutline(float u, uint ring, uint sheet) {
    if (sheet != 1) return lockSilhouette(u);
    return ring == 0 ? lockOpening(u) : lockKeyhole(u);
}

float3 lockPoint(float u, uint instance, constant WelcomeUniforms &p) {
    uint ring = instance / strands;
    uint strand = instance % strands;
    uint sheet = strand / 20;
    float lane = float(strand % 20)/19.0*2 - 1;
    bool detail = sheet == 1;
    float2 base = lockOutline(u, ring, sheet);
    float2 tangent = lockOutline(u + 0.002, ring, sheet) - lockOutline(u - 0.002, ring, sheet);
    float2 normal = float2(-tangent.y, tangent.x)/max(length(tangent), 1e-7);
    float a = u*tau;
    float seconds = p.shape.w;
    float phase = float(sheet)*2.1 + float(ring)*1.3;
    float width = detail ? 0.010 : 0.020;
    float weave = (detail ? 0.005 : 0.016)*sin(4*a + phase - seconds*0.9)
                + (detail ? 0.002 : 0.006)*sin(7*a - phase + seconds*1.4);
    float offset = lane*width + weave + (detail ? 0.0 : (float(sheet) - 1)*0.010);
    float2 q = base + normal*offset;
    // Only the shackle lifts and floats; the body stays put.
    float shackle = 1 - smoothstep(lockBodyTop - 0.18, lockBodyTop, base.y);
    q.y -= (p.lock.y + 0.010*sin(seconds*1.1))*shackle;
    float breathe = 1 + 0.012*sin(seconds*1.3);
    float yaw = 0.10*sin(seconds*0.55);
    float depth = -q.x*sin(yaw) + lane*0.04;
    q.x *= breathe*cos(yaw);
    q.y *= breathe;
    return float3(q.x + p.lock.z, q.y, depth);
}

// The double helix mirrors WelcomeLightHelix in Swift.
constant float helixRadius = 0.31, helixHalfHeight = 1.02, helixTwist = 5.5;
constant float helixSpin = 0.6, helixRungs = 10.0;

float3 helixPoint(float u, uint instance, constant WelcomeUniforms &p) {
    uint ring = instance / strands;
    uint strand = instance % strands;
    uint sheet = strand / 20;
    uint laneIndex = strand % 20;
    float lane = float(laneIndex)/19.0*2 - 1;
    float ringValue = float(ring), sheetValue = float(sheet);
    float seconds = p.shape.w;
    float phase = (u + 0.5)*tau;
    float h = asin(0.995*cos(phase))/asin(0.995);
    float envelope = sqrt(max(0.0, 1 - pow(abs(h), 4.0)));
    float axial = h*helixHalfHeight;
    float turn = helixTwist*axial + helixSpin*seconds;
    float swell = 1 + 0.03*sin(2.2*axial - 0.9*seconds);
    float seed = float(strand)*1.37 + ringValue*4.1;
    float y = axial;
    float r, theta;
    if (sheet == 1) {
        float offset = ring == 0 ? 0.0 : M_PI_F*0.5;
        float angle = helixRungs*phase + offset;
        float sweep = sin(angle);
        float middle = 1 - sweep*sweep;
        float center = (round(angle/M_PI_F)*M_PI_F - offset)/helixRungs;
        float level = axial + (asin(0.995*cos(center))/asin(0.995)*helixHalfHeight - axial)*smoothstep(0.0, 0.3, middle);
        float pass = 1.4*tanh(sin(phase)/0.05);
        r = (helixRadius - 0.02)*swell*sweep*envelope;
        theta = helixTwist*level + helixSpin*seconds + lane*0.04*middle;
        y = level + lane*(0.0015 + 0.006*middle*cos(4*sweep + 0.9*seconds + ringValue + pass))*envelope
          + 0.02*middle*sin(3.6*sweep + 1.2*seconds + pass*1.1 + ringValue)*envelope
          + 0.006*middle*sin(1.3*seconds + 5*level + ringValue*2.1);
    } else {
        float side = ring == 0 ? 1.0 : -1.0;
        float across = M_PI_F*0.5*tanh(sin(phase)/0.03)*side;
        theta = turn + M_PI_F*0.5 + across;
        float ply = 2.2*axial + 0.5*seconds;
        float plyOffset = 0.022*side;
        float torsion = 0.45*sin(1.6*axial + 0.5*seconds + ringValue*1.9 + sheetValue*1.3);
        float width = 0.06 + 0.02*sin(3.1*axial - 1.1*seconds + ringValue + sheetValue*0.7);
        float separation = (1 - sheetValue)*0.026*(1 + 0.5*sin(1.7*axial + 0.6*seconds + ringValue));
        float braid = 0.008*sin(9*axial + lane*2.4 - 1.7*seconds + sheetValue*2 + ringValue*3)
                    + 0.003*sin(seed + 0.8*seconds);
        float offset = lane*width + separation + braid;
        float taper = 0.35 + 0.65*envelope;
        r = helixRadius*swell*envelope + (offset*cos(torsion) + plyOffset*cos(ply))*taper;
        y += (offset*sin(torsion) + plyOffset*sin(ply))*taper;
        theta += lane*0.05*taper;
        if (laneIndex == 19) {
            r += (0.04 + 0.025*sin(2.3*axial + 0.7*seconds + ringValue*2))*envelope;
        }
    }
    float x = r*sin(theta), z = r*cos(theta);
    float2 q = float2(x, y)/(1 - z*0.30);
    return float3(q, (helixRadius - z)*0.8);
}

// The QR code mirrors WelcomeLightCode in Swift. Each loop runs across and
// back as two neighbouring lines; the fragment shader lights the dark modules.
constant float codeSide = 1.3, codeReach = 0.54, codeLines = 240.0;

float3 codePoint(float u, uint instance, constant WelcomeUniforms &p, thread float2 &local) {
    uint ring = instance / strands;
    uint strand = instance % strands;
    float phase = (u + 0.5)*tau;
    float h = asin(0.995*cos(phase))/asin(0.995);
    float pass = tanh(sin(phase)/0.04);
    float spacing = codeSide/codeLines;
    float pair = float(strand*2 + ring);
    local = float2(-h*codeSide*codeReach, -codeSide*0.5 + (2*pair + 1)*spacing - pass*spacing*0.5);
    float seconds = p.shape.w;
    float yaw = 0.16*sin(seconds*0.45);
    float pitch = 0.07*sin(seconds*0.33 + 1.1);
    float breathe = 1 + 0.01*sin(seconds*1.3);
    float z = local.x*sin(yaw) + local.y*sin(pitch);
    float perspective = breathe/(1 - z*0.30);
    return float3(local.x*cos(yaw)*perspective, local.y*cos(pitch)*perspective, 0.15 + z*0.8);
}

// Rows fill from the top down, each strand with its own small delay.
float codeAmount(float u, uint instance, constant WelcomeUniforms &p) {
    if (p.lock.w < 0.5 || p.code.x <= 0) return 0.0;
    uint ring = instance / strands;
    uint strand = instance % strands;
    float row = float(strand*2 + ring)/(codeLines*0.5 - 1);
    float jitter = 0.10*(0.5 + 0.5*sin(u*tau + float(instance)*0.37));
    float k = clamp(p.code.x*1.55 - 0.45*row - jitter, 0.0, 1.0);
    return k*k*k*(k*(k*6 - 15) + 10);
}

float3 ribbonPoint(float u, uint instance, constant WelcomeUniforms &p, device const float2 *controls);

// Strands leave the heart at slightly different moments, so the lock or helix
// forms as travelling silk rather than a crossfade. Zero leaves the heart untouched.
float3 lockedRibbonPoint(float u, uint instance, constant WelcomeUniforms &p, device const float2 *controls) {
    float3 heart = ribbonPoint(u, instance, p, controls);
    if (p.lock.x <= 0) return heart;
    float stagger = 0.35*(0.5 + 0.5*sin(u*tau + float(instance)*0.37));
    float k = clamp(p.lock.x*1.35 - stagger, 0.0, 1.0);
    k = k*k*k*(k*(k*6 - 15) + 10);
    float3 target = p.lock.w > 0.5 ? helixPoint(u, instance, p) : lockPoint(u, instance, p);
    float code = codeAmount(u, instance, p);
    if (code > 0) {
        float2 local;
        target = mix(target, codePoint(u, instance, p, local), code);
    }
    return mix(heart, target, k);
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
    // The helix always wears the finished heart's light, whatever the loop shows.
    float helix = p.lock.w > 0.5 ? p.lock.x : 0.0;
    float heartFlow = mix(smoothstep(0.15, 0.85, p.shape.y), 1.0, helix);
    float code = codeAmount(u, instance, p);
    float2 local = float2(0);
    if (code > 0) codePoint(u, instance, p, local);
    float light = pow(0.5 + 0.5*sin(u*tau*2 - lightClock*3 + phase), 3.0);
    float highlight = (strand % 20 == 6 && sheet != 1) ? 1.0 - code : 0.0;
    float3 cyan = mix(float3(0.035, 0.63, 1.0), float3(0.22, 0.63, 0.88), heartFlow);
    float3 blue = float3(0.07, 0.18, 0.95);
    float3 pink = mix(float3(0.68, 0.085, 0.50), float3(0.56, 0.18, 0.80), heartFlow);
    float tint = pow(0.5 + 0.5*sin(u*tau + lightClock + phase), 3.0);
    float3 color = sheet == 0 ? mix(cyan, float3(0.27,0.62,1), tint*0.3)
                 : (sheet == 1 ? mix(blue, cyan, tint) : mix(float3(0.34,0.11,0.75), pink, tint));
    // The helix leans deep blue and violet, with cyan carried by its crests.
    float3 helixColor = sheet == 0 ? mix(float3(0.10,0.32,1.0), float3(0.28,0.80,1.0), tint)
                      : (sheet == 1 ? mix(float3(0.40,0.22,0.95), float3(0.30,0.74,1.0), tint)
                                    : mix(float3(0.30,0.15,0.88), float3(0.52,0.24,0.98), tint));
    // The code runs from cyan through blue to violet, corner to corner.
    float diagonal = clamp((local.x + local.y)/(codeSide*2) + 0.5, 0.0, 1.0);
    float3 codeColor = mix(mix(float3(0.22,0.78,1.0), float3(0.12,0.36,1.0), smoothstep(0.0, 0.55, diagonal)),
                           float3(0.50,0.24,0.98), smoothstep(0.45, 1.0, diagonal));
    codeColor = mix(codeColor, float3(0.45,0.85,1.0), tint*0.25);
    helixColor = mix(helixColor, codeColor, code);
    color = mix(color, helixColor, helix);
    color = mix(color, float3(0.47,0.84,1), highlight*light*0.5);
    RibbonVertex out;
    out.position = float4(screen.x/p.viewport.x*2-1, 1-screen.y/p.viewport.y*2, 0, 1);
    out.distance = edge * halfWidth / p.viewport.w;
    out.depth = point.z;
    out.intensity = (0.022 + heartFlow*0.019 + (0.055 + heartFlow*0.015)*light + highlight*(0.22 + 0.65*light)*(1-heartFlow*0.34)) * (0.72 + 0.28*cos(u*tau + phase));
    // Finish the tiny soft reveal edge before closure; at head distance 1
    // every pixel already uses the ordinary loop, including the closing join.
    // The far side of the helix recedes, and its base pairs stay quieter
    // than the backbones.
    // Each band is translucent with bright edges. The far side recedes, the
    // base pairs stay finer than the backbones, and the ends dissolve.
    float back = clamp(point.z/0.55, 0.0, 1.0);
    float along = abs(asin(0.995*cos((u + 0.5)*tau))/asin(0.995));
    float rim = (sheet != 1 && (strand % 20 == 0 || strand % 20 == 18)) ? 1.0 : 0.0;
    float aura = (sheet != 1 && strand % 20 == 19) ? 1.0 : 0.0;
    float rungAngle = helixRungs*(u + 0.5)*tau + (instance/strands == 0 ? 0.0 : M_PI_F*0.5);
    float rungSpan = sheet == 1 ? 1.1*(1 - smoothstep(0.78, 0.94, abs(sin(rungAngle))))
                                    *(1 - smoothstep(0.5, 0.85, along))
                                    *smoothstep(0.25, 0.65, abs(tangent.x)) : 1.0;
    float helixLight = (0.55 + 1.1*rim - 0.25*aura)*(1 - 0.4*back)*(sheet == 0 ? 1.0 : 0.85)
                     *rungSpan*(1 - smoothstep(0.55, 0.95, along));
    helixLight = mix(helixLight, 1.7, code);
    out.intensity *= mix(1.0, helixLight, helix);
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
    out.coreWidth = (1 + highlight*(1.3 - 0.45*heartFlow) + head*0.45)*mix(1.0, 2.0, code*helix);
    out.color = color;
    out.screen = screen;
    out.local = local;
    out.code = code*helix;
    return out;
}

vertex RibbonVertex welcomeRibbonVertex(uint vertexID [[vertex_id]], uint instance [[instance_id]],
                                        constant WelcomeUniforms &p [[buffer(0)]],
                                        device const float2 *controls [[buffer(1)]],
                                        device const float *travel [[buffer(2)]]) {
    // Keep this vertex ordering after the entrance: no remesh at the handoff.
    float u = p.stream.w + float(vertexID / 2) / float(samples);
    float edge = (vertexID & 1) ? 1.0 : -1.0;
    float3 point = lockedRibbonPoint(u, instance, p, controls);
    float2 previous = lockedRibbonPoint(u - 0.5/float(samples), instance, p, controls).xy;
    float2 next = lockedRibbonPoint(u + 0.5/float(samples), instance, p, controls).xy;
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
    float3 tip = lockedRibbonPoint(p.stream.w, instance, p, controls);
    float2 direction = normalize(lockedRibbonPoint(p.stream.w+0.001,instance,p,controls).xy
                               - lockedRibbonPoint(p.stream.w-0.001,instance,p,controls).xy);
    float2 point = entrancePoint(t,tip.xy,direction,instance,p.stream.x);
    float2 previous = entrancePoint(t-0.5/128.0,tip.xy,direction,instance,p.stream.x);
    float2 next = entrancePoint(t+0.5/128.0,tip.xy,direction,instance,p.stream.x);
    float travel = distance[samples+1+vertexID/2];
    RibbonVertex out = lightVertex(p.stream.w+travel,float3(point,tip.z),previous,next,edge,instance,travel,p);
    // A finite thread is pulled in from its back end as the head advances.
    float tail = smoothstep(-0.012,0.012,travel-p.stream.z);
    out.intensity *= p.entrance.y*tail;
    out.code = 0;
    return out;
}

// Rounded modules with a fine gap, so the code reads as tiles of light.
float codeMask(float2 local, constant WelcomeUniforms &p, device const uchar *modules) {
    float n = p.code.y;
    float2 cell = (local/codeSide + 0.5)*n;
    if (n < 1 || any(cell < 0.0) || any(cell >= n)) return 0.0;
    uint size = uint(n);
    if (modules[uint(cell.y)*size + uint(cell.x)] == 0) return 0.0;
    float2 inside = abs(fract(cell) - 0.5);
    float corner = length(max(inside - (0.41 - 0.12), 0.0)) - 0.12;
    return 1 - smoothstep(-0.03, 0.01, corner);
}

fragment float4 welcomeRibbonFragment(RibbonVertex in [[stage_in]], constant WelcomeUniforms &p [[buffer(0)]],
                                      device const uchar *modules [[buffer(1)]]) {
    float d = in.distance;
    // Emission, a soft sheath, and wide bloom coexist per thread. Depth softens
    // distant strands rather than drawing every line equally sharp and bright.
    float focus = 1 + abs(in.depth)*0.65;
    float core = exp(-d*d / (2*0.16*0.16*focus*focus*in.coreWidth*in.coreWidth)) * 0.52;
    float sheath = exp(-d*d / (2*0.55*0.55*focus*focus*in.coreWidth)) * 0.12;
    float halo = exp(-d*d / (2*2.0*2.0)) * 0.012;
    float border = min(min(in.screen.x, p.viewport.x-in.screen.x), min(in.screen.y, p.viewport.y-in.screen.y));
    // Let the incoming light cross the actual edge without an inset fade.
    float edgeFade = mix(smoothstep(0.0, p.viewport.w*9, border),1.0,p.entrance.y);
    float energy = (core + sheath + halo) * in.intensity * 2.8 * edgeFade;
    // Lines sweep in whole and settle into modules as they arrive.
    if (in.code > 0.001) energy *= mix(1.0, codeMask(in.local, p, modules), smoothstep(0.5, 1.0, in.code));
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
    // The helix keeps its fine threads crisp, with less of the heart's mist.
    float helix = p.lock.w > 0.5 ? p.lock.x : 0.0;
    float heartFlow = mix(smoothstep(0.15, 0.85, p.shape.y), 1.0, helix);
    float3 light = core + nearGlow*0.72 + farGlow*mix(0.55, 0.42, helix) + silkGlow/8*heartFlow*mix(0.60, 0.25, helix);
    float3 radiance = 1 - exp(-light*1.8);
    float2 centered = (in.uv - 0.5)*p.viewport.xy / (min(p.viewport.x,p.viewport.y)*0.5);
    float haze = pow(max(0.0, 1-length(centered)), 1.7);
    float3 background = float3(0.008,0.012,0.035) + float3(0.005,0.012,0.125)*haze;
    // Keep the loop's edge treatment; let the entrance cross the screen edge.
    float2 screen = in.uv*p.viewport.xy;
    float border = min(min(screen.x,p.viewport.x-screen.x),min(screen.y,p.viewport.y-screen.y));
    float edgeFade = mix(smoothstep(0.0,p.viewport.w*10,border),1.0,p.entrance.y);
    return float4(background + radiance*edgeFade, 1);
}

"""#
}
