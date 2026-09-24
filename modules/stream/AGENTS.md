# streaming module guide

## Purpose
This module provides model-streaming helpers for loading and validating game models before use.

## Public API
- `QB.stream.loadModel(model, cb)`
  - Loads a model by string or hash.
  - Validates the model before loading.
  - Calls the optional callback after the model has loaded.
  - Returns the model hash, or `false, error` if the load timed out.
- `QB.stream.loadPtfx(fxName, cb, options?)` / `loadAnimDict(animDict, cb, options?)` / `loadAnimSet(animSet, cb, options?)` / `loadClipSet(clipSet, cb, options?)` / `loadIpl(iplName, cb, options?)` / `loadScaleformMovie(scaleformName, cb, options?)` / `loadTextureDict(textureDict, cb, isAdditionalTextures)` / `loadWeaponAsset(weapon, cb, weaponResourceFlags, extraWeaponComponentFlags)` / `loadAudioBank(audioBank, cb)`
  - Same request → poll-until-loaded → run callback → release lifecycle as `loadModel`, one per FiveM streaming asset type.
  - Each returns its loaded identifier (the input name/hash, except `loadScaleformMovie` which returns the scaleform handle), or `false, error`.
- `QB.stream.loadCollision(coords, cb, entity)`
  - The one loader NOT on the shared driver — see the implementation note below.
  - Returns `true`, or `false, error` if collision never loaded.

## Implementation notes
- Strings are converted with `joaat()` before validation.
- `assert(IsModelValid(model), ...)` is used to fail fast on bad input.
- An already-loaded model short-circuits the polling loop.
- `RequestModel` is issued once, then `QB.loops.controlled` polls
  `HasModelLoaded` once per frame with a 10 second timeout. Streaming is a
  latency-sensitive render-path dependency; exponential sleeps can add almost
  a full second after the asset is already ready.
- A timed-out load releases the request and returns `false` without invoking the callback.
- The callback runs under `pcall` so `SetModelAsNoLongerNeeded(model)` is reached
  even when the callback errors; the error is then re-raised to the caller.
- All 9 loaders — `loadModel` included — share a private `loadStreamingAsset(request, hasLoaded, remove, key, cb, identifierFromRequest)` helper that implements the request/poll/cleanup shape once, parameterized per native triad. `loadModel` keeps its own `joaat`/`IsModelValid` preamble and then delegates to the helper like everything else.
- **`loadAudioBank` passes the same function as both `request` and `hasLoaded`.** That isn't a mistake: audio banks have no `HasScriptAudioBankLoaded` native — `RequestScriptAudioBank` returns true once the bank is in memory. It composes correctly because `loadStreamingAsset` calls `hasLoaded` *before* `request`, so an already-loaded bank short-circuits exactly like every other type.
- **`loadCollision` deliberately bypasses `loadStreamingAsset`.** Collision has no identifier-keyed request/has-loaded/release triad to plug in: `RequestCollisionAtCoord` must be re-issued on every poll (one call isn't sticky), readiness is reported per *entity* rather than for the requested point, and there is no release native — collision unloads on its own. Forcing it through the shared driver would have meant faking two of the three natives, so it polls `QB.loops.controlled` directly instead and returns a plain boolean rather than an identifier.
- `identifierFromRequest` exists solely for `loadScaleformMovie`: unlike every other type (checked/cleaned-up by the input name), a scaleform's `HasScaleformMovieLoaded`/`SetScaleformMovieAsNoLongerNeeded` need the handle `RequestScaleformMovie` returns, not the name.
- Every loader releases its asset immediately after the callback returns (or immediately on timeout) — see each function's doc comment for the auto-cleanup timing tradeoff this implies for assets used beyond the callback's synchronous scope (e.g. an anim dict unloaded right after `TaskPlayAnim` fires, before playback finishes).

## Best practices
- Keep callbacks optional and non-blocking.
- Validate model references before long-running requests.
- Ensure any loaded models are cleaned up when no longer needed.
- Check the return value when calling without a callback — the caller owns cleanup.
- Prefer descriptive callback arguments and avoid side effects outside the load lifecycle.
