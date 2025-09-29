// smoke.shader - 28 Sept 2025

OUT_IN vec4 iterated_color;

uniform float time;
uniform vec2 world_pos;



#define PI 3.14159265358979323846

float rand(vec2 c){
    return fract(sin(dot(c.xy ,vec2(12.9898,78.233))) * 43758.5453);
}

float noise(vec2 p, float freq ){
    float unit = 1920.0/freq;
    vec2 ij = floor(p/unit);
    vec2 xy = mod(p,unit)/unit;
    //xy = 3.*xy*xy-2.*xy*xy*xy;
    xy = .5*(1.-cos(PI*xy));
    float a = rand((ij+vec2(0.,0.)));
    float b = rand((ij+vec2(1.,0.)));
    float c = rand((ij+vec2(0.,1.)));
    float d = rand((ij+vec2(1.,1.)));
    float x1 = mix(a, b, xy.x);
    float x2 = mix(c, d, xy.x);
    return mix(x1, x2, xy.y);
}

float pNoise(vec2 p, int res){
    float persistance = .5;
    float n = 0.;
    float normK = 0.;
    float f = 4.;
    float amp = 1.;
    int iCount = 0;
    for (int i = 0; i<50; i++){
        n+=amp*noise(p, f);
        f*=2.;
        normK+=amp;
        amp*=persistance;
        if (iCount == res) break;
        iCount++;
    }
    float nf = n/normK;
    return nf*nf*nf*nf;
}




#ifdef VERTEX_SHADER
in vec4 vert_position;
in vec4 vert_color;

uniform mat4 projection;

//float rand(vec2 co) {
//    return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
//}

/*
float rand(float n){return fract(sin(n) * 43758.5453123);}

float noise(float p){
    float fl = floor(p);
    float fc = fract(p);
    return mix(rand(fl), rand(fl + 1.0), fc);
}
    
float noise(vec2 n) {
    const vec2 d = vec2(0.0, 1.0);
    vec2 b = floor(n), f = smoothstep(vec2(0.0), vec2(1.0), fract(n));
    return mix(mix(rand(b), rand(b + d.yx), f.x), mix(rand(b + d.xy), rand(b + d.yy), f.x), f.y);
}

*/


void main() {
    vec2 pos = vert_position.xy;
    gl_Position = projection * vec4(pos, 0.0, 1.0);

    //float r = pow(rand(pos), 1);
    //float r = rand(pos);
    //float r = noise(pos);
    
    //vec2 st = gl_FragCoord.xy/pos;
    //float r = pNoise(st);
    
    //float r = pNoise(pos, 5);
    //r *= abs(sin(time));
    //vec4 col = vert_color * r;
    iterated_color = vert_color;
    //iterated_color = vec4(vec3(r),1.0);
}
#endif // VERTEX_SHADER

#ifdef FRAGMENT_SHADER

out vec4 color;

void main () {
    color = iterated_color;
    for (int i = 0; i < 3; ++i) {
        vec2 st = gl_FragCoord.xy + world_pos;// * sin(time);
        st.x += sin(time) *(10*i); //* 400.0; //gl_FragCoord.x;
        st.y += cos(time) *(10*i); //* 400.0; //gl_FragCoord.x;
        float r = clamp(pow(pNoise(st, 25), 0.3) + (0.25), 0, 1.0);
        float t = clamp(time, 0.0, 1.0);
        color = iterated_color * t * r;
    }
    color.a = 1;
}
#endif // FRAGMENT_SHADER
