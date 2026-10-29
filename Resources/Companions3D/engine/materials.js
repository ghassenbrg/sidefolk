// The body material every companion shares: three's physical material with a character's own
// surface written in GLSL (colours classified from Meshy's texture, fabric or plastic relief,
// glow), plus baked occlusion from the rig's vertex colours and a soft inner light.
import * as THREE from 'three';

const detail = (name) => {
  const t = new THREE.TextureLoader().load(new URL(`../assets/${name}`, import.meta.url).href);
  t.wrapS = t.wrapT = THREE.RepeatWrapping; t.anisotropy = 8;
  return t;
};
let shared;

/**
 * `surface` is GLSL run per pixel. It reads `tex` (texture colour, linear), `s` (the same in sRGB),
 * `p` and `nR` (rest-pose position and normal, model space) and may call `tri(map, p, n, scale)`
 * on `uPlush` or `uKnit`. It sets any of: `c` (colour), `rough`, `bumpH` (relief height),
 * `glow` (emitted light), `sheenTint`, `clear` (clearcoat amount), `inner` (inner light, 0…1),
 * `spec` (how much it reflects, 0…1: dark glass that mirrors the room looks lit from the front).
 */
export function bodyMaterial(body, { params = {}, surface = '', ao = [0.42, 0.3, 0.78], bump = 1, uniforms: own = {} } = {}) {
  shared ||= { uPlush: { value: detail('plush-height.png') }, uKnit: { value: detail('knit-height.png') } };
  const hasAO = !!body.geometry.attributes.color;
  const mat = new THREE.MeshPhysicalMaterial({
    map: body.material.map, color: 0xffffff, roughness: 0.78, metalness: 0,
    sheen: 1, sheenRoughness: 0.5, sheenColor: new THREE.Color(0xffffff), vertexColors: hasAO,
    clearcoat: 0, clearcoatRoughness: 0.12, ...params,
  });
  // A character's own uniforms (animated glow…) are declared for its surface and reachable as
  // material.userData.u.
  const uniforms = { ...shared, uBump: { value: bump }, ...own };
  mat.userData.u = uniforms;
  const decl = Object.entries(own).map(([k, u]) => `uniform ${typeof u.value === 'number' ? 'float' : 'vec3'} ${k};`).join('\n');
  mat.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, uniforms);
    sh.vertexShader = sh.vertexShader
      .replace('#include <common>', '#include <common>\nvarying vec3 vRest; varying vec3 vRestN;')
      .replace('#include <begin_vertex>', '#include <begin_vertex>\nvRest = position; vRestN = normal;');
    sh.fragmentShader = sh.fragmentShader
      .replace('#include <common>', `#include <common>
        varying vec3 vRest; varying vec3 vRestN;
        uniform sampler2D uPlush, uKnit; uniform float uBump;
        ${decl}
        // Relief projected from three sides of the rest pose: no UVs needed, moves with the skin.
        float tri(sampler2D tx, vec3 p, vec3 n, float sc) {
          vec3 w = pow(abs(n), vec3(4.0)); w /= (w.x + w.y + w.z);
          return texture2D(tx, p.zy * sc).r * w.x + texture2D(tx, p.xz * sc).r * w.y + texture2D(tx, p.xy * sc).r * w.z;
        }
        // Bump from screen-space height slopes (Mikkelsen), as three's bump maps do.
        vec3 reliefNormal(vec3 pos, vec3 n, float h, float faceDir) {
          vec2 dH = vec2(dFdx(h), dFdy(h));
          vec3 sx = dFdx(pos), sy = dFdy(pos);
          vec3 r1 = cross(sy, n), r2 = cross(n, sx);
          float det = dot(sx, r1) * faceDir;
          vec3 grad = sign(det) * (dH.x * r1 + dH.y * r2);
          return normalize(abs(det) * n - grad);
        }`)
      .replace('#include <map_fragment>', `#include <map_fragment>
        vec3 tex = diffuseColor.rgb;
        vec3 s = pow(max(tex, vec3(0.0)), vec3(1.0 / 2.2));
        vec3 p = vRest; vec3 nR = normalize(vRestN);
        vec3 c = tex; float rough = ${(params.roughness ?? 0.78).toFixed(3)}; float bumpH = 0.0;
        vec3 glow = vec3(0.0); vec3 sheenTint = vec3(1.0); float clear = 1.0; float inner = 1.0; float spec = 1.0;
        ${surface}
        diffuseColor.rgb = c;`)
      .replace('#include <roughnessmap_fragment>', '#include <roughnessmap_fragment>\nroughnessFactor = rough;')
      .replace('#include <color_fragment>', '')
      .replace('#include <normal_fragment_maps>', `#include <normal_fragment_maps>
        normal = reliefNormal(-vViewPosition, normal, bumpH * uBump, faceDirection);`)
      .replace('#include <aomap_fragment>', hasAO ? `#include <aomap_fragment>
        // Baked occlusion: bounce light fades into creases; the key light only a little, so
        // forms stay soft, never dirty.
        float bakedAO = pow(vColor.r, 0.8);
        reflectedLight.indirectDiffuse *= mix(${ao[0]}, 1.0, bakedAO);
        reflectedLight.indirectSpecular *= mix(${ao[1]}, 1.0, bakedAO);
        reflectedLight.directDiffuse *= mix(${ao[2]}, 1.0, bakedAO);` : '#include <aomap_fragment>')
      .replace('#include <aomap_fragment>', `#include <aomap_fragment>
        reflectedLight.directSpecular *= spec;
        reflectedLight.indirectSpecular *= spec;
        #ifdef USE_CLEARCOAT
          clearcoatSpecularDirect *= spec;
          clearcoatSpecularIndirect *= spec;
        #endif`)
      .replace('#include <lights_physical_fragment>', `#include <lights_physical_fragment>
        #ifdef USE_SHEEN
          material.sheenColor *= sheenTint;
        #endif
        #ifdef USE_CLEARCOAT
          material.clearcoat *= clear;
        #endif`)
      .replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
        // A little light scattered inside the surface: shadows stay soft and warm, never grey.
        totalEmissiveRadiance += diffuseColor.rgb * vec3(0.075, 0.068, 0.064) * inner + glow;`);
  };
  return mat;
}
