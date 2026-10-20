# Bundled shaders (VID-038, ADR-034)

Only MIT-licensed third-party shaders are bundled; LGPL shaders (NNEDI3, SSimSuperRes) are never bundled and can be added from a folder. The owner approved these downloads on 2026-10-20.

## Sources

- **Anime4K_*.glsl**: Anime4K v4.0.1 release zip `Anime4K_v4.0.zip` (https://github.com/bloc97/Anime4K/releases/download/v4.0.1/Anime4K_v4.0.zip, SHA-256 139cd282086457c5adc79caf7b75b8b825091d71c9b54958c18745fea62d7ed7); MIT, Copyright (c) 2019 bloc97. Only the files the built-in presets use are copied, byte for byte.
- **LICENSE-Anime4K.txt**: https://raw.githubusercontent.com/bloc97/Anime4K/v4.0.1/LICENSE (SHA-256 5bad448b737378e3d0c977ad0d0521fa37ad279a7e76ea9a31d9257eeb6953f5).
- **FSR.glsl**: AMD FidelityFX FSR 1.0.2 ported to mpv by agyild, https://gist.github.com/agyild/82219c545228d70c5604f865ce0b0ce5 (revision f1794d720013ccd9c5c86a0f20fddd71e0375f94, SHA-256 56d8597fc6b7bf6d13f8c3b2bdf1cdc43b06175d51746aab44cf1dca16929b9e); MIT, Copyright (c) 2021 Advanced Micro Devices, Inc.
- **LICENSE-FSR.txt**: the MIT notice from FSR.glsl's header.
- **Mediahro_FilmGrain.glsl**: Mediahro's own, under the app's licence (AGPL-3.0-or-later).

## Files

Stored with LF line endings (the repository normalises text). "As downloaded" is the upstream file's SHA-256 where it differs, which is only by line endings.

| File | SHA-256 | As downloaded |
|---|---|---|
| Anime4K_AutoDownscalePre_x2.glsl | `8c58291740146bd766a4d73f132775a797fe80f7d07919b5d767e27a5dc85656` | `9141668ced0b26512253e6396e805820716f35b57c92950d9da489f8b96a7ba4` |
| Anime4K_AutoDownscalePre_x4.glsl | `5af62d8cd844916dc1126613e13bad3beab195787f93a71200b47c6ec78f2e41` | `dadb7b713cfa1d810c55b5deff616072f3390e546fed1e6a54f80ea555f7b95d` |
| Anime4K_Clamp_Highlights.glsl | `a2a9bf7fbc1d75d09660ca2e701e4d7fb0cf5457b94da47e1825032fa2b3671a` | `8c5fb67c76bed3021f8a27b050c3b97a6ac1b284f9ce91c04189015c354c0217` |
| Anime4K_Restore_CNN_M.glsl | `67ea3ed26539e8de3b7d307688535d2ff17e8d147e11dda0247da7770dbecf41` | same |
| Anime4K_Restore_CNN_Soft_M.glsl | `a78a2c76898e08e09e442a9628c64208c26e8e15789649b8755223f009794c02` | same |
| Anime4K_Restore_CNN_Soft_VL.glsl | `094334b0e20c1a201fe4941c7c68de72451e5aee9efb5524d7fb82b12dca64b9` | same |
| Anime4K_Restore_CNN_VL.glsl | `35036722733305cd4d4e57660b883bbe2569ba2914033c254327107d7b77e35e` | same |
| Anime4K_Upscale_CNN_x2_M.glsl | `716e02098a68f0d648761f2b96b4dd139e1cb09b174bb369fca3aa34328fff7e` | same |
| Anime4K_Upscale_CNN_x2_S.glsl | `4c53ec2e287908f7ee7bcb266b0170421626d663576468b7d7dafc62962649a4` | same |
| Anime4K_Upscale_CNN_x2_VL.glsl | `5638fe31c37c151a3443fea3451a3ef91af073f4dbb9615f6c0d1e29db11493d` | same |
| Anime4K_Upscale_Denoise_CNN_x2_M.glsl | `8c72b042e2301fe66a45c3089720459148e2504cd72af16f9c0d5017ff14181e` | same |
| Anime4K_Upscale_Denoise_CNN_x2_VL.glsl | `359c48fe5a317fbc6b706ce368401eef496e84ed98abac7a43efebca2b65d79b` | same |
| FSR.glsl | `56d8597fc6b7bf6d13f8c3b2bdf1cdc43b06175d51746aab44cf1dca16929b9e` | same |
| LICENSE-Anime4K.txt | `5bad448b737378e3d0c977ad0d0521fa37ad279a7e76ea9a31d9257eeb6953f5` | same |
| LICENSE-FSR.txt | `9c17863e4763168c0b20cc1d058db025722fdfe2af9e5348be7fd205d7c81d22` | made from FSR.glsl's header |
| Mediahro_FilmGrain.glsl | `6c871f0a8655f74fe6f02603922ff9570ce5f3106c184401d34c185f1aad144b` | ours |
