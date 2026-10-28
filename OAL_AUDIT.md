# OAL compatibility audit

`use_experimental_fxv2_oal` changes Lua native argument marshalling. It is an
opt-in performance feature, not a framework default: vectors cannot be passed
as one unpacked native argument and inaccurate/undocumented native signatures
can fail at runtime. Every manifest change below therefore requires both the
static check and an in-game regression pass.

| Resource | Status | Reason |
|---|---|---|
| `kora_smallresources` | enabled | Small, explicit native surface. All native coordinates are scalar arguments; the sole frame task is required weapon-wheel suppression. |
| `kora_hud` | enabled | NUI/cache/voice consumer with no vector-native invocation. |
| `kora_loading` | enabled | NUI/theme consumer with no vector-native invocation. |
| `kora_admin` | excluded | Administrative teleport/noclip surface needs its own full native audit. |
| `kora_ambulance` | excluded | Death, stretcher and active animation/native flows are gameplay-critical. |
| `kora_clothing` | excluded | Camera and ped-clothing native surface needs dedicated visual regression. |
| `kora_core` | excluded | Framework compatibility surface includes legacy vector-native usage and broad public contracts. |
| `kora_drugs` | excluded | Gameplay resource; no current native-call performance case justifies experimental risk. |
| `kora_inventory` | excluded | Server-authoritative compatibility provider with vehicle/drop/container native paths. |
| `kora_lib` | excluded | Shared provider; a native marshalling regression would affect every consumer. |
| `kora_lib-playground` | excluded | Development-only command harness; no production benefit. |
| `kora_multichar` | excluded | Spawn/teleport flow is sensitive and must be audited separately. |
| `kora_police` | excluded | Broad entity, evidence, vehicle and duty native surface. |
| `kora_sql` | excluded | Database provider has no client-native hot path to benefit. |
| `kora_target` | excluded | Raycast/targeting precision and compatibility outweigh marginal native-call savings. |

## Re-audit rule

Any added native call, manifest change, or FiveM artifact upgrade requires a
fresh audit of the affected resource. Remove the OAL manifest entry immediately
if a staging test reports a native error, changed return value, or gameplay
regression.
