-- Annotation-only qblib public API. This file is shipped for LuaLS indexing
-- but is never loaded as a client, server, or shared runtime script.

---@class promise
---@field state string
---@field resolve fun(self: promise, value: any)
---@field reject fun(self: promise, error: any)
---@field next fun(self: promise, onResolved?: fun(value: any), onRejected?: fun(error: any)): promise
---@field catch fun(self: promise, onRejected: fun(error: any)): promise

---@class QBCoords
---@field x number
---@field y number
---@field z number
---@field w? number
---@field heading? number

---@class QBRateLimit
---@field max integer Maximum accepted calls in the sliding window.
---@field window integer Sliding-window length in milliseconds.

---@class QBRegistrationOptions
---@field rateLimit? QBRateLimit|false Client-to-server registrations only; omitted/false is unlimited.

---@class QBResourcesRegistry
---@field track fun(resource: string, id: any)
---@field untrack fun(id: any): string?
---@field owner fun(id: any): string?

---@class QBKeybindOptions
---@field name string Stable command name without whitespace.
---@field description string FiveM settings label.
---@field defaultKey? string Primary key, or empty for unbound.
---@field defaultMapper? string Defaults to `keyboard`.
---@field secondaryKey? string Alternate key registered as `~!+command`.
---@field secondaryMapper? string Defaults to the primary mapper.
---@field disabled? boolean Initial disabled state.
---@field onPressed? fun(handle: QBKeybindHandle)
---@field onReleased? fun(handle: QBKeybindHandle)

---@class QBKeybindHandle
---@field name string
---@field description string
---@field defaultKey string
---@field defaultMapper string
---@field secondaryKey? string
---@field secondaryMapper string
---@field resource string
---@field disable fun(toggle: boolean): boolean
---@field isDisabled fun(): boolean
---@field isPressed fun(): boolean
---@field getCurrentBinding fun(): string?
---@field remove fun(): boolean

---@class QBCommandSuggestion
---@field value string
---@field label? string
---@field help? string

---@class QBCommandSuggestionContext
---@field command string
---@field argumentIndex integer
---@field query string
---@field args string[]

---@class QBCommandArgument
---@field name string
---@field help string
---@field values? (string|number|QBCommandSuggestion)[]
---@field provider? fun(source: integer, context: QBCommandSuggestionContext): (string|number|QBCommandSuggestion)[]

---@class QBCommandKeybindOptions
---@field description? string Defaults to command help/name.
---@field defaultKey? string
---@field defaultMapper? string Defaults to `keyboard`.
---@field secondaryKey? string
---@field secondaryMapper? string

---@class QBCommandOptions
---@field permission? string Defaults to `user`.
---@field checkPermission? fun(source: integer, permission: string): boolean
---@field notify? fun(source: integer, message: string, type: string)
---@field resource? string
---@field keybind? QBCommandKeybindOptions

---@class QBCommandInfo
---@field name string
---@field help string
---@field permission string
---@field keybind? QBCommandKeybindOptions

---@class QBVehicleDeleteOptions
---@field timeout? integer Network-control timeout in milliseconds; defaults to 1000.

---@class QBVehicleSetPropertiesOptions
---@field timeout? integer Network-control timeout in milliseconds; defaults to 1000.

---@class QBVehicleProperties
---@field model? integer
---@field plate? string
---@field plateIndex? integer
---@field bodyHealth? number
---@field engineHealth? number
---@field tankHealth? number
---@field fuelLevel? number
---@field dirtLevel? number
---@field oilLevel? number
---@field color1? integer|integer[]|{r: integer, g: integer, b: integer}
---@field color2? integer|integer[]|{r: integer, g: integer, b: integer}
---@field pearlescentColor? integer
---@field dashboardColor? integer
---@field wheelColor? integer
---@field wheels? integer
---@field wheelSize? number
---@field wheelWidth? number
---@field tireHealth? table<integer|string, number>
---@field tireBurstState? table<integer|string, boolean>
---@field tireBurstCompletely? table<integer|string, boolean>
---@field windowTint? integer
---@field windowStatus? table<integer|string, boolean>
---@field doorStatus? table<integer|string, boolean>
---@field neonEnabled? boolean[]
---@field neonColor? integer[]|{r: integer, g: integer, b: integer}
---@field interiorColor? integer
---@field extras? table<integer|string, boolean>
---@field tyreSmokeColor? integer[]|{r: integer, g: integer, b: integer}
---@field xenonColor? integer|integer[]|{r: integer, g: integer, b: integer}
---@field modTurbo? boolean
---@field modSmokeEnabled? boolean
---@field modXenon? boolean
---@field modFrontWheels? integer
---@field modBackWheels? integer
---@field modCustomTiresF? boolean
---@field modCustomTiresR? boolean
---@field modLivery? integer
---@field liveryRoof? integer
---@field modSpoilers? integer
---@field modFrontBumper? integer
---@field modRearBumper? integer
---@field modSideSkirt? integer
---@field modExhaust? integer
---@field modFrame? integer
---@field modGrille? integer
---@field modHood? integer
---@field modFender? integer
---@field modRightFender? integer
---@field modRoof? integer
---@field modEngine? integer
---@field modBrakes? integer
---@field modTransmission? integer
---@field modHorns? integer
---@field modSuspension? integer
---@field modArmor? integer
---@field modKit17? integer
---@field modKit19? integer
---@field modKit21? integer
---@field modPlateHolder? integer
---@field modVanityPlate? integer
---@field modTrimA? integer
---@field modOrnaments? integer
---@field modDashboard? integer
---@field modDial? integer
---@field modDoorSpeaker? integer
---@field modSeats? integer
---@field modSteeringWheel? integer
---@field modShifterLeavers? integer
---@field modAPlate? integer
---@field modSpeakers? integer
---@field modTrunk? integer
---@field modHydrolic? integer
---@field modEngineBlock? integer
---@field modAirFilter? integer
---@field modStruts? integer
---@field modArchCover? integer
---@field modAerials? integer
---@field modTrimB? integer
---@field modTank? integer
---@field modWindows? integer
---@field modKit47? integer
---@field modKit49? integer

---@alias QBTextUIPosition 'left-center'|'right-center'|'top-center'|'bottom-center'
---@class QBTextUIOptions
---@field key? string
---@field icon? string
---@field position? QBTextUIPosition

---@class QBStateChange
---@field entity integer Entity resolved from the bag name, or 0 for global/player/unavailable bags.
---@field bagName string
---@field key string
---@field value any
---@field reserved integer
---@field replicated boolean

---@alias QBWorldEntityType 'ped'|'vehicle'|'object'|'player'
---@class QBWorldQueryOptions
---@field models? (integer|string)[]
---@field predicate? fun(entity: integer, coords: QBCoords, distance: number): boolean
---@field includeInvisible? boolean Client only.
---@field includeOwnPed? boolean Client only.
---@field excludeEntities? integer[]
---@field radius? number Used by `getClosestEntity`.

---@class QBWorldMatch
---@field entity integer
---@field coords QBCoords
---@field distance number

---@class QBWorldGroundOptions
---@field height? number
---@field attempts? integer
---@field retryDelay? integer

---@class QBTeleportOptions
---@field fade? boolean|number

---@class QBWaypointTeleportOptions: QBTeleportOptions
---@field entity? integer
---@field launchHeight? number
---@field collisionTimeout? integer
---@field groundAttempts? integer
---@field groundRetryDelay? integer

---@class QBBlipsCreateOptions
---@field sprite? integer
---@field color? integer
---@field scale? number
---@field label? string
---@field shortRange? boolean
---@field category? integer
---@field route? boolean

---@class QBControlsOptions
---@field inputGroup? integer
---@field disablePlayerFiring? boolean

---@class QBControlLease
---@field inputGroup integer
---@field controls integer[]
---@field disablePlayerFiring boolean

---@class QBEntitiesCreateOptions
---@field preset? 'frozen'|'static'|'invincible'
---@field heading? number
---@field freeze? boolean
---@field blockNonTempEvents? boolean
---@field invincible? boolean

---@class QBAnimPlayOptions
---@field duration? integer
---@field flag? integer
---@field blendInSpeed? number
---@field blendOutSpeed? number
---@field playbackRate? number
---@field lockX? boolean
---@field lockY? boolean
---@field lockZ? boolean
---@field onFinish? fun(entity: integer)

---@class QBAnimHandle
---@field entity integer
---@field dict string
---@field clip string
---@field generation integer

---@class QBAnimAttachOptions
---@field softPin? boolean
---@field collision? boolean
---@field vertexIndex? integer
---@field fixedRot? boolean

---@class QBFxPtfxDef
---@field dict string
---@field name string
---@field bone? string
---@field entity? integer
---@field coords? QBCoords
---@field offset? QBCoords
---@field rot? QBCoords
---@field scale? number
---@field duration? integer
---@field looped? boolean

---@class QBFxPtfxHandle
---@field looped boolean
---@field particleId? integer

---@class QBFxScreenHandle
---@field name string

---@class QBProgressBarDisable
---@field move? boolean
---@field combat? boolean
---@field car? boolean

---@class QBProgressBarAnim
---@field dict string
---@field clip string
---@field flag? integer
---@field blendIn? number
---@field blendOut? number

---@class QBProgressBarScenario
---@field name string
---@field playEnter? boolean

---@class QBProgressBarProp
---@field model string|integer
---@field bone? string|integer
---@field offset? QBCoords
---@field rotation? QBCoords
---@field softPinning? boolean
---@field collision? boolean
---@field rotationOrder? integer
---@field syncRotation? boolean

---@class QBProgressBarPayload
---@field label string
---@field duration integer
---@field canCancel? boolean
---@field disable? QBProgressBarDisable
---@field anim? QBProgressBarAnim
---@field scenario? QBProgressBarScenario
---@field props? QBProgressBarProp[]

---@class QBActionsResult
---@field token any
---@field completed boolean
---@field proof? string
---@field authorization? string

---@class QBActionsOptions
---@field begin fun(...: any): any, string?, string? Returns action token, optional failure reason, and optional minigame proof authorization.
---@field complete fun(result: QBActionsResult, ...: any): any
---@field label string
---@field duration? integer
---@field minigame? QBMinigameType
---@field canCancel? boolean
---@field disable? QBProgressBarDisable
---@field anim? QBProgressBarAnim

---@class QBNotifyPayload
---@field title? string
---@field message string
---@field type? 'success'|'error'|'warning'|'info'
---@field duration? integer
---@field icon? string
---@field id? string

---@class QBDrawingTextOptions
---@field font? integer
---@field scale? number
---@field color? {r: integer, g: integer, b: integer, a: integer}
---@field maxDistance? number
---@field outline? boolean

---@class QBRaycastResult
---@field hit boolean
---@field coords QBCoords
---@field surfaceNormal QBCoords
---@field entity integer
---@field materialHash? integer

---@class QBMenuItem
---@field id string
---@field label string
---@field description? string
---@field icon? string
---@field image? string
---@field disabled? boolean
---@field submenu? {title?: string, items: QBMenuItem[]}

---@class QBMenuResult
---@field selectedId? string
---@field path? string[]
---@field cancelled? boolean

---@class QBRadialMenuOptions
---@field radius? number

---@class QBAlertOptions
---@field message string
---@field title? string
---@field image? string
---@field confirmLabel? string
---@field cancelLabel? string
---@field cancellable? boolean
---@field destructive? boolean

---@class QBAlertResult
---@field confirmed boolean

---@alias QBInputType 'text'|'password'|'textarea'|'number'|'checkbox'|'select'|'range'|'combobox'
---@class QBInputOption
---@field value string|number
---@field label string
---@field disabled? boolean

---@class QBInputField
---@field id string
---@field label string
---@field type QBInputType
---@field description? string
---@field placeholder? string
---@field default? any
---@field required? boolean
---@field min? number
---@field max? number
---@field pattern? string
---@field rows? integer
---@field options? QBInputOption[]

---@class QBInputResult
---@field values? table<string, any>
---@field cancelled? boolean

---@alias QBAppTone 'neutral'|'primary'|'success'|'warning'|'destructive'
---@alias QBAppActionVariant 'primary'|'secondary'|'outline'|'ghost'|'destructive'

---@class QBAppAction
---@field id string
---@field label string
---@field icon? string
---@field variant? QBAppActionVariant
---@field disabled? boolean
---@field data? any

---@class QBAppStat
---@field label string
---@field value string|number
---@field description? string
---@field icon? string
---@field tone? QBAppTone

---@class QBAppTableColumn
---@field key string
---@field label string
---@field align? 'left'|'center'|'right'

---@class QBAppListItem
---@field id string
---@field label string
---@field description? string
---@field icon? string
---@field badge? string|number
---@field tone? QBAppTone
---@field action? string Action id routed to the registered onAction handler.
---@field data? any

---@alias QBAppBlockType 'text'|'stats'|'table'|'list'|'actions'|'empty'

---@class QBAppBlock
---@field type QBAppBlockType
---@field title? string
---@field text? string Text block body.
---@field description? string Empty-state description.
---@field icon? string Empty-state icon.
---@field items? QBAppStat[]|QBAppListItem[] Stats/list items.
---@field actions? QBAppAction[] Action-block buttons.
---@field columns? QBAppTableColumn[] Table columns.
---@field rows? table<string, string|number|boolean>[] Table rows.
---@field empty? string Empty list/table label.
---@field action? string Action id emitted when a table row is selected.
---@field idKey? string Table row key copied into action context.itemId.

---@class QBAppContent
---@field title? string
---@field description? string
---@field actions? QBAppAction[]
---@field blocks? QBAppBlock[]

---@class QBAppTab
---@field id string
---@field label string
---@field badge? string|number
---@field content? QBAppContent

---@class QBAppNavigationItem
---@field id string
---@field label string
---@field description? string
---@field icon? string
---@field badge? string|number
---@field group? string
---@field disabled? boolean
---@field defaultTab? string
---@field tabs? QBAppTab[]
---@field content? QBAppContent

---@class QBAppDefinition
---@field id string Namespaced stable id.
---@field title string
---@field description? string
---@field icon? string
---@field navigation QBAppNavigationItem[]
---@field defaultView? string
---@field width? number Pixels; clamped to 720-1600.
---@field height? number Pixels; clamped to 480-960.
---@field footer? string
---@field onAction? fun(actionId: string, context: QBAppActionContext): QBAppActionResult?

---@class QBAppOpenOptions
---@field data? any Private session data supplied back to onAction; not rendered.
---@field viewId? string
---@field tabId? string

---@class QBAppActionContext
---@field appId string
---@field viewId? string
---@field tabId? string
---@field itemId? string
---@field value? any
---@field data? any The data supplied to openApp.

---@class QBAppActionResult
---@field update? table Partial QBAppDefinition to merge and render immediately.
---@field close? boolean Close the app after the action.

---@class QBAppResult
---@field closed boolean
---@field reason string
---@field viewId? string
---@field tabId? string

---@class QBInteractOption
---@field label string
---@field icon? string
---@field action? fun()
---@field event? string
---@field type? 'client'|'server'
---@field args? any[]
---@field canInteract? fun(): boolean
---@field job? string|string[]|table<string, integer>
---@field gang? string|string[]|table<string, integer>
---@field citizenid? string|string[]|table<string, boolean>
---@field item? string|string[]
---@field distance? number

---@class QBInteractTargetOptions
---@field options QBInteractOption[]
---@field distance? number

---@class QBInteractSize
---@field x number
---@field y number
---@field z number

---@class QBZoneOptions
---@field coords QBCoords
---@field radius? number
---@field size? QBInteractSize|QBCoords
---@field rotation? number|QBCoords
---@field points? QBCoords[]
---@field thickness? number
---@field debug? boolean
---@field onEnter? fun(zone: QBZoneHandle)
---@field onExit? fun(zone: QBZoneHandle)
---@field inside? fun(zone: QBZoneHandle)

---@class QBZoneHandle
---@field id integer
---@field type 'box'|'sphere'|'poly'|'point'
---@field resource string
---@field data QBZoneOptions
---@field remove fun(): boolean
---@field contains fun(coords: QBCoords): boolean
---@field isInside fun(): boolean

---@class QBRewardItem
---@field chance? number
---@field amount? number|{min: number, max: number}

---@class QBRewardOptions
---@field mode? 'weighted'|'percent'
---@field rolls? integer
---@field allowNone? boolean

---@alias QBMinigameType 'lockpick'|'skillbar'|'circuit'|'mash'|'pinpad'|'quiz'|'wordguess'|'wordscramble'|'keys'|'hacking'
---@class QBMinigameOptions
---@field duration? integer
---@field difficulty? number|string
---@field rounds? integer
---@field [string] any Game-specific fields are documented in modules/minigames/docs.md.

---@class QBMinigameResult
---@field success boolean
---@field attempts integer
---@field proof? string
---@field cancelled? true
---@field faults? integer
---@field reason? string

---@class QBStatusEffectDef
---@field duration? integer
---@field stacking? 'replace'|'extend'|'stack'
---@field severityLevels? integer
---@field fx? {screen?: string, ptfx?: QBFxPtfxDef}
---@field anim? {dict: string, clip: string}
---@field movement? {speedMultiplier?: number}

---@class QBStatusApplyOptions
---@field duration? integer
---@field severity? integer

---@class QBStatusActiveEntry
---@field name string
---@field severity? integer
---@field expiresAt? integer

---@class QBDiscordResponse
---@field status integer
---@field body? string
---@field headers? table<string, string>
---@field data? any
---@field error? string

---@alias QBDiscordCallback fun(ok: boolean, response: QBDiscordResponse)

---@class QBDiscordEmbedField
---@field name string
---@field value string
---@field inline? boolean

---@class QBDiscordEmbedOptions
---@field title? string
---@field description? string
---@field url? string
---@field color? integer|string
---@field timestamp? boolean|integer|string
---@field footer? string|{text: string, icon_url?: string}
---@field author? string|{name: string, url?: string, icon_url?: string}
---@field image? string|{url: string}
---@field thumbnail? string|{url: string}
---@field fields? QBDiscordEmbedField[]

---@class QBStreamResult
---@field [integer] any

---@alias QBLookupNamespace 'vehicle'|'ped'|'object'|'weapon'|'weapon_component'|'pickup'
---@alias QBLookupModelNamespace 'vehicle'|'ped'|'object'
---@alias QBLookupFailure 'catalog_pending'|'not_found'|'ambiguous'
---@alias QBLookupSource 'base'|'custom'|'base+custom'

---@class QBLookupMetadata
---@field class? string Vehicle class.
---@field manufacturer? string Vehicle manufacturer key.
---@field type? string Vehicle type.
---@field seats? integer Vehicle seat count.
---@field pedType? string Ped type.
---@field modelName? string Weapon or pickup model name.
---@field damageType? string Weapon damage type.
---@field weaponNames? string[] Weapons that own a component.
---@field componentType? string Weapon-component type.
---@field attachBone? string Weapon-component attachment bone.

---@class QBLookupRecord
---@field namespace QBLookupNamespace
---@field hash integer Unsigned 32-bit hash.
---@field signedHash integer Signed 32-bit representation.
---@field hexHash string Eight-digit hexadecimal representation.
---@field name string Canonical spawn/archetype/hash-key name.
---@field label? string English display label.
---@field labelKey? string GXT label key.
---@field category? string
---@field dlc? string
---@field source QBLookupSource
---@field resources? string[] Sorted custom resources contributing this entry.
---@field metadata? QBLookupMetadata Namespace-specific curated metadata.

---@class QBLib
---@field actions QBLibActions
---@field anim QBLibAnim
---@field blips QBLibBlips
---@field cache QBLibCache
---@field callback QBLibCallback
---@field closest QBLibClosest
---@field commands QBLibCommands
---@field controls QBLibControls
---@field discord QBLibDiscord
---@field distance QBLibDistance
---@field drawing QBLibDrawing
---@field entities QBLibEntities
---@field events QBLibEvents
---@field fx QBLibFx
---@field interact QBLibInteract
---@field keybind QBLibKeybind
---@field logging QBLibLogging
---@field lookup QBLibLookup
---@field loops QBLibLoops
---@field minigames QBLibMinigames
---@field notify QBLibNotify
---@field nui QBLibNui
---@field permissions QBLibPermissions
---@field placement QBLibPlacement
---@field print QBLibPrint
---@field progressbar QBLibProgressbar
---@field raycast QBLibRaycast
---@field require QBLibRequire
---@field resources QBLibResources
---@field rewards QBLibRewards
---@field sound QBLibSound
---@field state QBLibState
---@field status QBLibStatus
---@field stream QBLibStream
---@field teleport QBLibTeleport
---@field textui QBLibTextUI
---@field theme QBLibTheme
---@field timers QBLibTimers
---@field util QBLibUtil
---@field vehicle QBLibVehicle
---@field visuals QBLibVisuals
---@field world QBLibWorld
---@field zones QBLibZones
---@field lang fun(key: string, ...: any): string [shared]
---@field locale QBLibLocale

---@class QBLibLocale
---@field getLanguage fun(): string [shared]
---@field getLanguages fun(): string[] [shared]
---@field setLanguage fun(language: string): boolean, string|nil [client]
---@field translate fun(resource: string, key: string, ...: any): any [shared]

---@class QBLibActions
---@field run fun(options: QBActionsOptions, ...: any): boolean, any [client]
---@field isActive fun(): boolean [client]

---@class QBLibAnim
---@field play fun(entity: integer, dict: string, clip: string, opts?: QBAnimPlayOptions): QBAnimHandle|false, string? [client]
---@field stop fun(entity: integer, blendOutSpeed?: number): boolean [client]
---@field stopHandle fun(handle: QBAnimHandle, blendOutSpeed?: number): boolean [client]
---@field isPlaying fun(entity: integer): boolean [client]
---@field attachProp fun(entity: integer, model: string|integer, bone: string, offset?: QBCoords, rotation?: QBCoords, opts?: QBAnimAttachOptions): integer|false, string? [client]
---@field detachProp fun(prop: integer): boolean, string? [client]
---@field playScenario fun(entity: integer, scenario: string, enterVehicle?: boolean) [client]
---@field clear fun(entity: integer, immediate?: boolean) [client]

---@class QBLibBlips
---@field create fun(coords: QBCoords, options?: QBBlipsCreateOptions): integer|false, string? [client]
---@field remove fun(blip: integer): boolean, string? [client]

---@class QBLibCache
---@field get fun(key: string): any [client]
---@field set fun(key: string, value: any) [client]
---@field onChange fun(key: string, handler: fun(newValue: any, oldValue: any)) [client]
---@field offChange fun(key: string) [client]
---@field playerId fun(): integer [client]
---@field serverId fun(): integer [client]
---@field ped fun(): integer [client]
---@field coords fun(): QBCoords [client]
---@field vehicle fun(): integer|false [client]
---@field seat fun(): integer|false [client]
---@field enteringVehicle fun(): integer|false [client]
---@field enteringSeat fun(): integer|false [client]
---@field weapon fun(): integer [client]
---@field health fun(): integer [client]
---@field isDead fun(): boolean [client]
---@field armour fun(): integer [client]
---@field stamina fun(): number [client]

---@class QBLibCallback
---@field assertName fun(name: string) [shared]
---@field register fun(name: string, handler: fun(...: any): any, opts?: QBRegistrationOptions) [client/server; opts is server client-to-server only]
---@field unregister fun(name: string): boolean [client/server]
---@field trigger fun(targetOrName: integer|string, nameOrArg?: any, ...: any): any [client: name,...; server: target,name,...]

---@class QBLibClosest
---@field player fun(srcOrCoords: integer|QBCoords, coordsOrDistance?: QBCoords|number, distance?: number): {id: integer?, distance: number?} [client/server]
---@field vehicle fun(srcOrCoords: integer|QBCoords, coordsOrDistance?: QBCoords|number, distance?: number): {id: integer?, distance: number?} [client/server]
---@field ped fun(srcOrCoords: integer|QBCoords, coordsOrDistance?: QBCoords|number, distance?: number): {id: integer?, distance: number?} [client/server]
---@field object fun(srcOrCoords: integer|QBCoords, coordsOrDistance?: QBCoords|number, distance?: number): {id: integer?, distance: number?} [client/server]

---@class QBLibCommands
---@field add fun(name: string, help: string, args: QBCommandArgument[]?, argsRequired: boolean?, handler: fun(source: integer, args: string[], raw: string), opts?: QBCommandOptions) [server]
---@field remove fun(name: string) [server]
---@field refresh fun(src: integer) [server]
---@field list fun(): QBCommandInfo[] [server]
---@field suggest fun(src: integer, name: string, argumentIndex: integer, query?: string, parsedArgs?: string[]): QBCommandSuggestion[] [server]

---@class QBLibControls
---@field acquire fun(controlIds: integer[], options?: QBControlsOptions): integer [client]
---@field release fun(leaseId: integer): boolean [client]

---@class QBLibDiscord
---@field createEmbed fun(options: QBDiscordEmbedOptions): table [server]
---@field sendWebhook fun(url: string?, payload: string|table, callback?: QBDiscordCallback): boolean [server]
---@field botEnabled fun(): boolean [server]
---@field botRequest fun(method: string, route: string, payload?: table, callback?: QBDiscordCallback, auditReason?: string): boolean [server]
---@field getGuild fun(guildId: string, callback?: QBDiscordCallback): boolean [server]
---@field getMember fun(guildId: string, userId: string, callback?: QBDiscordCallback): boolean [server]
---@field updateMember fun(guildId: string, userId: string, attributes: table, callback?: QBDiscordCallback, auditReason?: string): boolean [server]
---@field fetchGuildRoles fun(guildId: string, callback?: QBDiscordCallback): boolean [server]
---@field setMemberRoles fun(guildId: string, userId: string, roleIds: string[], callback?: QBDiscordCallback, auditReason?: string): boolean [server]
---@field addMemberRole fun(guildId: string, userId: string, roleId: string, callback?: QBDiscordCallback, auditReason?: string): boolean [server]
---@field removeMemberRole fun(guildId: string, userId: string, roleId: string, callback?: QBDiscordCallback, auditReason?: string): boolean [server]
---@field createRole fun(guildId: string, role: table, callback?: QBDiscordCallback, auditReason?: string): boolean [server]
---@field updateRole fun(guildId: string, roleId: string, role: table, callback?: QBDiscordCallback, auditReason?: string): boolean [server]
---@field deleteRole fun(guildId: string, roleId: string, callback?: QBDiscordCallback, auditReason?: string): boolean [server]
---@field getChannels fun(guildId: string, callback?: QBDiscordCallback): boolean [server]
---@field getChannel fun(channelId: string, callback?: QBDiscordCallback): boolean [server]
---@field createChannel fun(guildId: string, channel: table, callback?: QBDiscordCallback, auditReason?: string): boolean [server]
---@field updateChannel fun(channelId: string, attributes: table, callback?: QBDiscordCallback, auditReason?: string): boolean [server]
---@field deleteChannel fun(channelId: string, callback?: QBDiscordCallback, auditReason?: string): boolean [server]
---@field sendMessage fun(channelId: string, payload: string|table, callback?: QBDiscordCallback): boolean [server]
---@field editMessage fun(channelId: string, messageId: string, payload: string|table, callback?: QBDiscordCallback): boolean [server]
---@field deleteMessage fun(channelId: string, messageId: string, callback?: QBDiscordCallback, auditReason?: string): boolean [server]
---@field getGuildRoles fun(guildId?: string): table<string, table> [server]
---@field getRole fun(role: string, guildId?: string): table? [server]
---@field refreshMember fun(id: integer|string, callback?: fun(ok: boolean, roles: string[]|string)): boolean [server]
---@field getRoles fun(id: integer|string): string[] [server]
---@field hasRole fun(id: integer|string, role: string): boolean [server]
---@field hasRoles fun(id: integer|string, roles: string[], requireAll?: boolean): boolean [server]
---@field hasAnyRole fun(id: integer|string, roles: string[]): boolean [server]
---@field hasAllRoles fun(id: integer|string, roles: string[]): boolean [server]
---@field giveRole fun(id: integer|string, role: string, callback?: QBDiscordCallback, auditReason?: string): boolean [server]
---@field removeRole fun(id: integer|string, role: string, callback?: QBDiscordCallback, auditReason?: string): boolean [server]
---@field syncRoles fun(callback?: fun(ok: boolean, result: any)): boolean [server]

---@class QBLibDistance
---@field player fun(srcOrCoords: integer|QBCoords, coordsOrDistance?: QBCoords|number, distance?: number): boolean [client/server]
---@field coords fun(coords1: QBCoords, coords2: QBCoords, distance: number): boolean [client/server]
---@field entity fun(srcOrEntity: integer, entityOrDistance: integer|number, distance?: number): boolean [client/server]
---@field x fun(srcOrPoint: integer|QBCoords, pointOrDistance: QBCoords|number, distance?: number): boolean [client/server]
---@field y fun(srcOrPoint: integer|QBCoords, pointOrDistance: QBCoords|number, distance?: number): boolean [client/server]
---@field xy fun(srcOrPoint: integer|QBCoords, pointOrDistance: QBCoords|number, distance?: number): boolean [client/server]

---@class QBLibDrawing
---@field text3d fun(coords: QBCoords, text: string, options?: QBDrawingTextOptions): boolean [client]

---@class QBLibEntities
---@field create fun(model: string|integer, coords: QBCoords, options?: QBEntitiesCreateOptions): integer|false, string? [client]
---@field remove fun(entity: integer): boolean, string? [client]
---@field requestControl fun(entity: integer, timeout?: integer): boolean, string? [client]
---@field delete fun(entity: integer, timeout?: integer): boolean, string? [client]

---@class QBLibEvents
---@field assertName fun(name: string) [shared]
---@field register fun(name: string, handler: fun(src: integer, ...: any), opts?: QBRegistrationOptions) [server]
---@field unregister fun(name: string): boolean [server]
---@field trigger fun(name: string, ...: any): boolean, string? [client]
---@field push fun(target: integer, name: string, ...: any) [server]
---@field onPush fun(name: string, handler: fun(...: any)) [client]
---@field offPush fun(name: string): boolean [client]

---@class QBLibFx
---@field playPtfx fun(def: QBFxPtfxDef): QBFxPtfxHandle|false, string? [client]
---@field stop fun(handle: QBFxPtfxHandle|false): boolean [client]
---@field screenEffect fun(name: string, duration?: integer, looped?: boolean): QBFxScreenHandle [client]
---@field stopScreenEffect fun(handle: QBFxScreenHandle|false): boolean [client]

---@class QBLibInteract
---@field open fun(options: QBInteractOption[]): boolean [client]
---@field close fun() [client]
---@field isActive fun(): boolean [client]
---@field addCircleZone fun(name: string, coords: QBCoords, radius: number, targetOptions: QBInteractTargetOptions, debug?: boolean): QBZoneHandle [client]
---@field addBoxZone fun(name: string, coords: QBCoords, size: QBInteractSize|QBCoords, targetOptions: QBInteractTargetOptions, debug?: boolean): QBZoneHandle [client]
---@field removeZone fun(name: string): boolean [client]
---@field addTargetModel fun(models: string|integer|(string|integer)[], size: QBInteractSize|QBCoords, targetOptions: QBInteractTargetOptions, debug?: boolean): QBZoneHandle[] [client]
---@field addTargetEntity fun(entity: integer, size: QBInteractSize|QBCoords, targetOptions: QBInteractTargetOptions, debug?: boolean): QBZoneHandle [client]
---@field addEntity fun(entity: integer, options: QBInteractOption[], distance?: number): integer [client]
---@field removeEntity fun(entity: integer, id?: integer): boolean [client]
---@field addModel fun(model: string|integer, options: QBInteractOption[], distance?: number): integer [client]
---@field removeModel fun(model: string|integer, id?: integer): boolean [client]

---@class QBLibKeybind
---@field add fun(options: QBKeybindOptions): QBKeybindHandle [client]
---@field remove fun(name: string): boolean [client]
---@field list fun(): table[] [client]

---@class QBLibLogging
---@field event fun(category: string, src: integer, data?: table) [server]
---@field getStats fun(): table [server]

---@class QBLibLookup
---@field get fun(namespace: QBLookupNamespace, value: integer|string): QBLookupRecord?, QBLookupFailure?, QBLookupRecord[]? [shared]
---@field model fun(value: integer|string, kind?: QBLookupModelNamespace): QBLookupRecord?, QBLookupFailure?, QBLookupRecord[]? [shared]
---@field weapon fun(value: integer|string): QBLookupRecord?, QBLookupFailure?, QBLookupRecord[]? [shared]
---@field weaponComponent fun(value: integer|string): QBLookupRecord?, QBLookupFailure?, QBLookupRecord[]? [shared]
---@field pickup fun(value: integer|string): QBLookupRecord?, QBLookupFailure?, QBLookupRecord[]? [shared]
---@field preload fun(namespaces?: QBLookupNamespace|QBLookupNamespace[]): boolean [shared]
---@field ready fun(): boolean [shared]
---@field awaitReady fun(timeout?: integer): boolean, string? [shared]

---@class QBLibLoops
---@field controlled fun(call: fun(): any, tries?: integer|false, timeout?: integer|false, backoff?: boolean): any, string? [shared]

---@class QBLibMinigames
---@field play fun(gameType: QBMinigameType, opts?: QBMinigameOptions, authorization?: string): QBMinigameResult|promise [client]
---@field authorizeProof fun(src: integer, gameType: QBMinigameType, trustedOpts?: QBMinigameOptions): string [server]
---@field consumeProof fun(src: integer, token: string, gameType: QBMinigameType, authorization: string): boolean [server]
---@field triangleWave fun(elapsedMs: number, speedHz: number): number [shared]

---@class QBLibNotify
---@field send fun(payloadOrSource: QBNotifyPayload|integer, payload?: QBNotifyPayload) [client/server]
---@field sendToAll fun(payload: QBNotifyPayload) [server]
---@field assert fun(payload: QBNotifyPayload) [shared]
---@field withDefaults fun(payload: QBNotifyPayload): QBNotifyPayload [shared]

---@class QBMenuPosition
---@field horizontal? 'left'|'center'|'right'
---@field vertical? 'top'|'center'|'bottom'
---@field offsetX? positive integer Pixels from the selected horizontal edge.
---@field offsetY? positive integer Pixels from the selected vertical edge.

---@class QBMenuOptions
---@field position? QBMenuPosition
---@field maxWidth? positive integer Pixels.
---@field maxHeight? positive integer Pixels.

---@class QBLibNui
---@field send fun(action: string, data?: any) [client]
---@field setFocus fun(mouse: boolean, keyboard: boolean) [client]
---@field withFocus fun(mouse: boolean, keyboard: boolean, fn: fun(): any): any [client]
---@field registerCallback fun(name: string, handler: fun(data: any): any) [client]
---@field request fun(action: string, data?: any, timeout?: integer|false): promise|any [client]
---@field copyToClipboard fun(text: string): promise|any [client]
---@field openMenu fun(items: QBMenuItem[], title?: string, opts?: QBMenuOptions): QBMenuResult|promise [client]
---@field openContextMenu fun(items: QBMenuItem[], x?: number, y?: number): QBMenuResult|promise [client]
---@field openRadialMenu fun(items: QBMenuItem[], opts?: QBRadialMenuOptions): QBMenuResult|promise [client]
---@field openAlert fun(opts: QBAlertOptions): QBAlertResult|promise [client]
---@field openInputDialog fun(fields: QBInputField[], title?: string, description?: string): QBInputResult|promise [client]
---@field registerApp fun(definition: QBAppDefinition): string [client]
---@field unregisterApp fun(id: string): boolean [client]
---@field openApp fun(id: string, opts?: QBAppOpenOptions): QBAppResult|promise [client]
---@field updateApp fun(id: string, update: table): boolean [client]
---@field closeApp fun(id?: string): boolean [client]
---@field isAppOpen fun(id?: string): boolean [client]

---@class QBPermissionOptions
---@field prefix? string ACE object prefix, such as `qbcore` for `qbcore.admin`.
---@field discordRoles? table<string, string|string[]> Permission/level to Discord role name/ID mappings.

---@class QBPermissionCheck
---@field level string The level this ACE object would grant.
---@field object string The ACE object passed to IsPlayerAceAllowed.
---@field raw string tostring() of what the native returned, so a non-boolean is visible.
---@field type string type() of what the native returned.
---@field allowed boolean Normalized result.

---@class QBLibPermissions
---@field getLevel fun(src: integer, levels: string[], prefixOrOptions?: string|QBPermissionOptions): string [server]
---@field hasLevel fun(src: integer, required: string, levels: string[], prefixOrOptions?: string|QBPermissionOptions): boolean [server]
---@field hasPermission fun(src: integer, permission: string, prefixOrOptions?: string|QBPermissionOptions): boolean [server]
---@field explain fun(src: integer, levels: string[], prefixOrOptions?: string|QBPermissionOptions): QBPermissionCheck[], string [server] -- diagnostics only; nothing gates on this

---@class QBPlacementRotation
---@field pitch number
---@field roll number
---@field yaw number

---@class QBPlacementResult
---@field model string|integer
---@field coords QBCoords
---@field heading number
---@field rotation QBPlacementRotation

---@class QBLibPlacement
---@field start fun(model: string|integer): QBPlacementResult|promise|nil [client]
---@field isActive fun(): boolean [client]
---@field generateSnippet fun(result: QBPlacementResult): string [client]

---@class QBLibPrint
---@field debug fun(...: any) [shared]
---@field info fun(...: any) [shared]
---@field error fun(...: any) [shared]
---@field warn fun(...: any) [shared]
---@field success fun(...: any) [shared]

---@class QBLibProgressbar
---@field start fun(payload: QBProgressBarPayload): boolean, string? [client]
---@field cancel fun(): boolean [client]
---@field isActive fun(): boolean [client]

---@class QBLibRaycast
---@field fromCoords fun(startCoords: QBCoords, endCoords: QBCoords, flags?: integer, ignoreEntity?: integer): QBRaycastResult [client]
---@field fromCamera fun(maxDistance?: number, flags?: integer, ignoreEntity?: integer): QBRaycastResult [client]
---@field fromCam fun(cam: integer, maxDistance?: number, flags?: integer, ignoreEntity?: integer): QBRaycastResult [client]
---@field start fun(startCoords: QBCoords, endCoords: QBCoords, flags?: integer, ignoreEntity?: integer): integer [client; returns a ray handle for await/poll]
---@field startFromCamera fun(maxDistance: number, flags?: integer, ignoreEntity?: integer): integer [client; returns a ray handle for await/poll]
---@field await fun(rayHandle: integer): QBRaycastResult [client]
---@field poll fun(rayHandle: integer): boolean, boolean, QBCoords?, integer?, QBCoords? [client; settled, hit, coords, entityHit, surfaceNormal]

---@class QBLibRequire
---@field load fun(resource: string, paths: string|string[]): any [shared; an array returns one value per path]
---@field current fun(paths: string|string[]): any [shared; an array returns one value per path]
---@field ["local"] fun(paths: string|string[]): any [shared; bracket-form alias of current]

---@class QBLibResources
---@field registry fun(onDispose: fun(id: any)): QBResourcesRegistry [client]
---@field serverRegistry fun(onDispose: fun(id: any)): QBResourcesRegistry [server]

---@class QBLibRewards
---@field generate fun(items: QBRewardItem[], opts?: QBRewardOptions): table[] [shared]

---@class QBSoundOptions
---@field network? boolean Play for nearby players too, rather than only locally. Defaults to false.
---@field range? number Audible range in metres, world sounds only. Defaults to Config.sound.defaultRange.
---@field bank? string Audio bank to request (and wait for) before playing.
---@field releaseAfter? number Milliseconds before the sound id is auto-released. Defaults to Config.sound.defaultReleaseAfter.

---@class QBLibSound
---@field playFrontend fun(name: string, set: string, options?: QBSoundOptions): number|false, string? [client]
---@field playFromCoords fun(coords: QBCoords, name: string, set: string, options?: QBSoundOptions): number|false, string? [client]
---@field playFromEntity fun(entity: number, name: string, set: string, options?: QBSoundOptions): number|false, string? [client]
---@field stop fun(soundId: number): boolean, string? [client]
---@field isLive fun(soundId: number): boolean [client]

---@class QBLibState
---@field onChange fun(keyFilter: string?, bagFilter: string?, handler: fun(change: QBStateChange)): integer [client/server]
---@field offChange fun(listenerId: integer): boolean [client/server]

---@class QBLibStatus
---@field registerEffect fun(name: string, def: QBStatusEffectDef) [shared]
---@field getEffectDef fun(name: string): QBStatusEffectDef? [shared]
---@field apply fun(targetOrName: integer|string, nameOrOpts?: string|QBStatusApplyOptions, opts?: QBStatusApplyOptions): boolean, string? [client/server]
---@field remove fun(targetOrName: integer|string, name?: string): boolean [client/server]
---@field isActive fun(targetOrName: integer|string, name?: string): boolean [client/server]
---@field getActive fun(target?: integer): QBStatusActiveEntry[] [client/server]
---@field onChange fun(handler: fun(name: string, applied: boolean)): integer [client]
---@field offChange fun(listenerId: integer) [client]

---@class QBLibStream
---@field loadModel fun(model: string|integer, cb?: fun(hash: integer)): integer|false, string? [client]
---@field loadPtfx fun(fxName: string, cb?: fun()): boolean, string? [client]
---@field loadAnimDict fun(animDict: string, cb?: fun()): boolean, string? [client]
---@field loadAnimSet fun(animSet: string, cb?: fun()): boolean, string? [client]
---@field loadClipSet fun(clipSet: string, cb?: fun()): boolean, string? [client]
---@field loadIpl fun(iplName: string, cb?: fun()): boolean, string? [client]
---@field loadScaleformMovie fun(scaleformName: string, cb?: fun(handle: integer)): integer|false, string? [client]
---@field loadTextureDict fun(textureDict: string, cb?: fun(), isAdditionalTextures?: boolean): boolean, string? [client]
---@field loadAudioBank fun(audioBank: string, cb?: fun()): boolean, string? [client]
---@field loadCollision fun(coords: QBCoords, cb?: fun(), entity?: integer): boolean, string? [client]
---@field loadWeaponAsset fun(weapon: string|integer, cb?: fun(hash: integer), weaponResourceFlags?: integer, extraWeaponComponentFlags?: integer): integer|false, string? [client]

---@class QBLibTeleport
---@field entity fun(entity: integer, coords: QBCoords, opts?: QBTeleportOptions): boolean [client]
---@field player fun(coords: QBCoords, opts?: QBTeleportOptions): boolean [client]
---@field toWaypoint fun(opts?: QBWaypointTeleportOptions): boolean, string? [client]

---@class QBLibTextUI
---@field show fun(text: string, opts?: QBTextUIOptions): integer [client]
---@field update fun(id: integer, text: string, opts?: QBTextUIOptions): boolean [client]
---@field hide fun(id: integer): boolean [client]
---@field isOpen fun(id?: integer): boolean [client]
---@field isVisible fun(id: integer): boolean [client]

---@class QBLibTheme
---@field accentColor fun(): string [shared] Forwarded to qbtheme:getPrimaryColor().
---@field tokens fun(overrides?: string|table<string, string>): table<string, string> [shared] Forwarded to qbtheme:getTokens().
---@field push fun(): table<string, string> [client] Reapplies qbtheme to qblib's NUI.

---@class QBDebounced
---@field cancel fun(): boolean Drops a pending run without firing it.
---@field isPending fun(): boolean

---@class QBThrottled
---@field reset fun() Clears the cooldown so the next call passes through.
---@field remaining fun(): integer Milliseconds until the next call is allowed; 0 when ready.

---@class QBLibTimers
---@field setInterval fun(fn: fun(), interval: number): integer [shared]
---@field setTimeout fun(fn: fun(), delay: number): integer [shared]
---@field clearInterval fun(id: integer): boolean [shared]
---@field clearTimeout fun(id: integer): boolean [shared]
---@field debounce fun(fn: fun(...), wait: number): QBDebounced [shared]
---@field throttle fun(fn: fun(...), interval: number): QBThrottled [shared]
---@field count fun(): integer [shared]

---@class QBLibUtil
---@field deepClone fun(value: any): any [shared]
---@field isFiniteNumber fun(value: any): boolean [shared]
---@field clamp fun(value: number, min: number, max: number): number [shared]
---@field round fun(value: number, decimals?: integer): number [shared]
---@field randomFloat fun(min: number, max: number): number [shared]
---@field weightedChoice fun(list: {[1]: any, [2]: number}[]): any [shared]
---@field tableContains fun(t: table, value: any): boolean [shared]
---@field lerp fun(a: number, b: number, t: number): number [shared]
---@field vecAdd fun(a: QBCoords, b: QBCoords): QBCoords [shared]
---@field vecSub fun(a: QBCoords, b: QBCoords): QBCoords [shared]
---@field vecScale fun(v: QBCoords, scalar: number): QBCoords [shared]
---@field vecLength fun(v: QBCoords): number [shared]
---@field vecDistance fun(a: QBCoords, b: QBCoords): number [shared]
---@field vecDistance2d fun(a: QBCoords, b: QBCoords): number [shared]
---@field vecNormalize fun(v: QBCoords): QBCoords [shared]
---@field headingToDirection fun(heading: number): QBCoords [shared]
---@field directionToHeading fun(v: QBCoords): number [shared]
---@field bearing fun(origin: QBCoords, target: QBCoords): number [shared]
---@field worldToScreen fun(coords: QBCoords): number, number, boolean [client]
---@field worldToScreenPixels fun(coords: QBCoords): number, number, boolean [client]

---@class QBLibVehicle
---@field requestControl fun(entity: integer, timeout?: integer): boolean, string? [client]
---@field delete fun(vehicle: integer, options?: QBVehicleDeleteOptions): boolean, string? [client]
---@field isDriver fun(vehicle: integer): boolean [client]
---@field model fun(vehicle: integer): integer|false [client]
---@field plate fun(vehicle: integer): string|false [client]
---@field label fun(vehicle: integer): string|false [client]
---@field getProperties fun(vehicle: integer): QBVehicleProperties|false, string? [client]
---@field setProperties fun(vehicle: integer, properties: QBVehicleProperties, opts?: QBVehicleSetPropertiesOptions): boolean, string? [client]

---@class QBLibVisuals
---@field fade fun(duration?: integer|QBCoords, fn?: fun()|integer) [client]
---@field trevor fun(duration?: integer) [client]
---@field meth fun(duration?: integer) [client]
---@field ecstacy fun(duration?: integer) [client]
---@field alien fun(duration?: integer) [client]
---@field crack fun(duration?: integer) [client]
---@field coke fun(duration?: integer) [client]

---@class QBLibWorld
---@field getNearbyEntities fun(entityType: QBWorldEntityType, coords: QBCoords, radius: number, options?: QBWorldQueryOptions): QBWorldMatch[] [client/server]
---@field getClosestEntity fun(entityType: QBWorldEntityType, coords: QBCoords, options?: QBWorldQueryOptions): integer|false, QBCoords?, number? [client/server]
---@field getGroundCoords fun(coords: QBCoords, options?: QBWorldGroundOptions): QBCoords|false, string? [client]
---@field getStreetNames fun(coords?: QBCoords): string, string? [client]
---@field getZoneName fun(coords?: QBCoords): string, string [client]
---@field getCardinalDirection fun(value?: number, options?: {entity?: boolean}): 'N'|'NW'|'W'|'SW'|'S'|'SE'|'E'|'NE' [client]
---@field getWaypointCoords fun(): QBCoords|false, string? [client]
---@field isSpawnClear fun(coords: QBCoords, radius: number, options?: QBWorldQueryOptions): boolean [client/server]

---@class QBLibZones
---@field box fun(opts: QBZoneOptions): QBZoneHandle [client]
---@field sphere fun(opts: QBZoneOptions): QBZoneHandle [client]
---@field poly fun(opts: QBZoneOptions): QBZoneHandle [client]
---@field point fun(opts: QBZoneOptions): QBZoneHandle [client]
---@field getInside fun(resource?: string): QBZoneHandle[] [client]
---@field setDebug fun(id: integer, enabled: boolean): boolean [client]
---@field generateSnippet fun(zoneType: 'box'|'sphere'|'poly'|'point', opts: QBZoneOptions): string [client]
---@field startCreator fun(zoneType: 'box'|'sphere'|'poly'|'point', existingOpts?: QBZoneOptions): QBZoneHandle|false, string? [client]
---@field isCreatorActive fun(): boolean [client]
---@field edit fun(handle: QBZoneHandle, opts?: QBZoneOptions): QBZoneHandle|false, string? [client]
