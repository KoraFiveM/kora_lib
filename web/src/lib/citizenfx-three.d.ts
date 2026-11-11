// @citizenfx/three is FiveM's CfxTexture-enabled fork of Three r100. The
// package predates bundled TypeScript declarations; kora_lib uses only this tiny
// runtime surface for the headless game-view capture component.
declare module "@citizenfx/three" {
    export const OrthographicCamera: any
    export const Scene: any
    export const WebGLRenderTarget: any
    export const LinearFilter: any
    export const NearestFilter: any
    export const RGBAFormat: any
    export const UnsignedByteType: any
    export const CfxTexture: any
    export const ShaderMaterial: any
    export const PlaneBufferGeometry: any
    export const Mesh: any
    export const WebGLRenderer: any
}
