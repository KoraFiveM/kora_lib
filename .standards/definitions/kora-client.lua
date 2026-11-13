---@meta
-- Kora Framework integration. Copyright © 2026 Kora Framework.
-- Snapshot of kora_lib/types.lua, filtered by documented realm markers.
-- Annotation-only kora_lib public API. This file is shipped for LuaLS indexing
-- but is never loaded as a client, server, or shared runtime script.

---@class promise
---@field state string
---@field resolve fun(self: promise, value: any)
---@field reject fun(self: promise, error: any)
---@field next fun(self: promise, onResolved?: fun(value: any), onRejected?: fun(error: any)): promise
---@field catch fun(self: promise, onRejected: fun(error: any)): promise

---@class KoraCoords
---@field x number
---@field y number
---@field z number
---@field w? number
---@field heading? number

---@class KoraSpatialVector
---@field x number
---@field y number
---@field z? number
---@field w? number
---@field heading? number

---@class KoraRateLimit
---@field max integer Maximum accepted calls in the sliding window (1–10000).
---@field window integer Sliding-window length in milliseconds (1–86400000).

---@class KoraRandomPickOptions
---@field count? integer Number of independent picks. Defaults to 1.
---@field maxIndex? integer Highest eligible array index. Defaults to the array length.

---@alias KoraScreenshotEncoding 'jpg'|'png'|'webp'

---@class KoraScreenshotOptions
---@field encoding? KoraScreenshotEncoding Defaults to `Config.screenshot.defaultEncoding`.
---@field quality? number Image encoder quality from 0 to 1.
---@field maxWidth? integer|false Default output width ceiling; false leaves it unbounded.
---@field maxHeight? integer|false Default output height ceiling; false leaves it unbounded.
---@field includeNui? boolean Accepted for screenshot-basic compatibility; separate CEF layers cannot be captured.
---@field fileName? string Server-only destination path. Never accept this from a client event.
---@field timeout? integer Server-only request timeout in milliseconds; must be greater than 1000.

---@class KoraRegistrationOptions
---@field rateLimit? KoraRateLimit|false Client-to-server registrations only; omitted/false is unlimited.

---@class KoraResourcesRegistry
---@field track fun(resource: string, id: any)
---@field untrack fun(id: any): string?
---@field owner fun(id: any): string?

---@class KoraResourceAwaitOptions
---@field timeout? number Defaults to 10000 milliseconds.
---@field interval? number Defaults to 100 milliseconds.

---@class KoraCooldownHandle
---@field use fun(key: any): boolean
---@field remaining fun(key: any): integer
---@field reset fun(key?: any)

---@class KoraKeybindOptions
---@field name string Stable command name without whitespace.
---@field description string FiveM settings label.
---@field defaultKey? string Primary key, or empty for unbound.
---@field defaultMapper? string Defaults to `keyboard`.
---@field secondaryKey? string Alternate key registered as `~!+command`.
---@field secondaryMapper? string Defaults to the primary mapper.
---@field disabled? boolean Initial disabled state.
---@field onPressed? fun(handle: KoraKeybindHandle)
---@field onReleased? fun(handle: KoraKeybindHandle)

---@class KoraKeybindHandle
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

---@class KoraCommandSuggestion
---@field value string
---@field label? string
---@field help? string

---@class KoraCommandSuggestionContext
---@field command string
---@field argumentIndex integer
---@field query string
---@field args string[]

---@class KoraCommandArgument
---@field name string
---@field help string
---@field values? (string|number|KoraCommandSuggestion)[]
---@field provider? fun(source: integer, context: KoraCommandSuggestionContext): (string|number|KoraCommandSuggestion)[]

---@class KoraCommandKeybindOptions
---@field description? string Defaults to command help/name.
---@field defaultKey? string
---@field defaultMapper? string Defaults to `keyboard`.
---@field secondaryKey? string
---@field secondaryMapper? string

---@class KoraCommandOptions
---@field permission? string Defaults to `user`.
---@field checkPermission? fun(source: integer, permission: string): boolean
---@field notify? fun(source: integer, message: string, type: string)
---@field resource? string
---@field keybind? KoraCommandKeybindOptions

---@class KoraCommandInfo
---@field name string
---@field help string
---@field permission string
---@field keybind? KoraCommandKeybindOptions

---@class KoraVehicleDeleteOptions
---@field timeout? integer Network-control timeout in milliseconds; defaults to 1000.

---@class KoraVehicleNormalizePlateOptions
---@field maxLength? integer Defaults to 8.
---@field whitespace? 'collapse'|'remove'|'preserve'
---@field characters? 'alphanumeric'|'any'

---@class KoraCleanTextOptions
---@field maxLength? integer
---@field whitespace? 'collapse'|'preserve'
---@field controlCharacters? 'remove'|'preserve'
---@field empty? 'nil'|'allow'

---@class KoraNearestOptions
---@field coordsOf fun(entry: any): KoraSpatialVector
---@field radius? number Maximum distance to count as a match. Unbounded if omitted.
---@field bucketOf? fun(entry: any): any
---@field bucket? any Value `bucketOf` must match. Required alongside `bucketOf`.

---@class KoraRateLimiter
---@field consume fun(self: KoraRateLimiter, key: any, now: number): boolean, number?

---@class KoraStreamLoadOptions
---@field timeout? integer Defaults to 10000 milliseconds.
---@field shouldContinue? fun(): boolean Cancels the wait when it returns false.

---@class KoraVehicleSetPropertiesOptions
---@field timeout? integer Network-control timeout in milliseconds; defaults to 1000.

---@class KoraVehicleProperties
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

---@alias KoraTextUIPosition 'left-center'|'right-center'|'top-center'|'bottom-center'

---@class KoraStateChange
---@field entity integer Entity resolved from the bag name, or 0 for global/player/unavailable bags.
---@field bagName string
---@field key string
---@field value any
---@field reserved integer
---@field replicated boolean

---@alias KoraWorldEntityType 'ped'|'vehicle'|'object'|'player'

---@class KoraWorldMatch
---@field entity integer
---@field coords KoraCoords
---@field distance number

---@class KoraWorldGroundOptions
---@field height? number
---@field attempts? integer
---@field retryDelay? integer

---@class KoraWorldNearbyPlayerOptions
---@field maxDistance number
---@field sameBucket? boolean
---@field allowSelf? boolean

---@class KoraTeleportOptions
---@field fade? boolean|number

---@class KoraWaypointTeleportOptions: KoraTeleportOptions
---@field entity? integer
---@field launchHeight? number
---@field collisionTimeout? integer
---@field groundAttempts? integer
---@field groundRetryDelay? integer

---@class KoraBlipsCreateOptions
---@field sprite? integer
---@field color? integer
---@field scale? number
---@field name? string Location/name shown after GTA's native category heading.
---@field label? string Backwards-compatible explicit map-label override.
---@field shortRange? boolean
---@field category? integer|string Fixed category name/legacy alias or numeric native category. Defaults to Other.
---@field display? integer Native display mode restored after show. Defaults to Config.blips.defaultDisplay.
---@field route? boolean
---@field info? KoraBlipInfo

---@class KoraBlipCategory
---@field key string Canonical fixed category key/name, or `native:<id>` for a numeric compatibility category.
---@field name string Canonical category name, or `Category <id>` for a numeric compatibility category.
---@field label string Pause-map/UI category label.
---@field id integer Native SetBlipCategory id.
---@field visible boolean Player's persisted client visibility preference.
---@field count integer Number of currently registered kora_lib blips in the category.

---@class KoraRegisteredBlip
---@field handle integer Actual native blip handle returned by Kora.blips.create.
---@field resource string Resource that created the blip.
---@field category integer Native category id.
---@field categoryKey string Canonical fixed category key/name, or `native:<id>` for a numeric compatibility category.
---@field name string Normalized location/name within the category.
---@field label string Location label passed to GTA, or an explicit legacy override.
---@field sprite integer
---@field color integer
---@field display integer Configured display mode restored after show.
---@field route boolean
---@field visible boolean Effective visibility after individual/category state.

---@class KoraBlipInfoRow
---@field kind 'text'|'icon'|'name'|'header'|'wrappedText'
---@field label? string|number Left-hand text. Omit for a wrapped-text row.
---@field value? string|number Right-hand or wrapped text.
---@field icon? integer Icon id for an `icon` row.
---@field color? integer Icon color for an `icon` row.
---@field checked? boolean Whether an `icon` row is checked.

---@class KoraBlipInfo
---@field title string
---@field verified? boolean Display the verified title mark.
---@field image? {dictionary: string, texture: string} Pause-menu texture dictionary and texture name.
---@field rp? string|number Optional RP title metadata.
---@field money? string|number Optional money title metadata.
---@field rows? KoraBlipInfoRow[] Detail rows displayed below the title.

---@class KoraControlsOptions
---@field inputGroup? integer
---@field disablePlayerFiring? boolean
---@field ignoreWeaponWheel? boolean

---@class KoraControlLease
---@field inputGroup integer
---@field controls integer[]
---@field disablePlayerFiring boolean

---@class KoraEntitiesCreateOptions
---@field preset? 'frozen'|'static'|'invincible'
---@field heading? number
---@field freeze? boolean
---@field blockNonTempEvents? boolean
---@field invincible? boolean

---@class KoraEntitiesScopedOptions : KoraEntitiesCreateOptions
---@field radius number Spawn radius in metres; must be greater than zero.

---@class KoraScopedEntityHandle
---@field id integer Stable scoped-registration id.
---@field resource string Resource that created the scoped entity.
---@field entity? integer Current local entity handle, or nil while outside the scope.
---@field remove fun() Deletes the active entity and unregisters the scope.
---@field isSpawned fun(): boolean Whether the scope currently owns a live entity.

---@class KoraAnimPlayOptions
---@field duration? integer
---@field flag? integer
---@field blendInSpeed? number
---@field blendOutSpeed? number
---@field playbackRate? number
---@field lockX? boolean
---@field lockY? boolean
---@field lockZ? boolean
---@field onFinish? fun(entity: integer)

---@class KoraAnimHandle
---@field entity integer
---@field dict string
---@field clip string
---@field generation integer

---@class KoraAnimAttachOptions
---@field softPin? boolean
---@field collision? boolean
---@field vertexIndex? integer
---@field fixedRot? boolean

---@class KoraFxPtfxDef
---@field dict string
---@field name string
---@field bone? string
---@field entity? integer
---@field coords? KoraCoords
---@field offset? KoraCoords
---@field rot? KoraCoords
---@field scale? number
---@field duration? integer
---@field looped? boolean

---@class KoraFxPtfxHandle
---@field looped boolean
---@field particleId? integer

---@class KoraFxScreenHandle
---@field id integer
---@field name string

---@class KoraProgressBarDisable
---@field move? boolean
---@field moveMode? 'freeze'|'controls' Defaults to Config.progressbar.defaultMoveMode ('controls'); controls matches ox_lib movement blocking, freeze uses FreezeEntityPosition (skipped while airborne).
---@field controlProfile? 'kora_lib'|'ox' Exact disabled-control set; defaults to kora_lib.
---@field sprint? boolean
---@field combat? boolean
---@field car? boolean
---@field mouse? boolean

---@class KoraProgressBarAnim
---@field dict string
---@field clip string
---@field flag? integer
---@field blendIn? number
---@field blendOut? number
---@field stopBlendOut? number Cleanup blend-out override for compatibility providers.
---@field duration? integer
---@field playbackRate? number
---@field lockX? boolean
---@field lockY? boolean
---@field lockZ? boolean

---@class KoraProgressBarScenario
---@field name string
---@field playEnter? boolean

---@class KoraProgressBarProp
---@field model string|integer
---@field bone? string|integer
---@field offset? KoraCoords
---@field coords? KoraCoords Legacy `prop`/`proptwo` attachment offset.
---@field rotation? KoraCoords
---@field softPinning? boolean
---@field collision? boolean
---@field rotationOrder? integer
---@field syncRotation? boolean

---@class KoraProgressBarPayload
---@field label string
---@field duration integer
---@field maxDuration? integer|false Override duration cap; false allows any positive duration.
---@field canCancel? boolean Enables cancellation with X or Escape (Config.progressbar.cancelControls).
---@field cancelControls? integer[]|false Override local cancel controls; false delegates cancellation to a compatibility command.
---@field useWhileDead? boolean
---@field allowRagdoll? boolean
---@field allowCuffed? boolean
---@field allowFalling? boolean
---@field allowSwimming? boolean
---@field presentation? 'bar'|'circle'
---@field position? 'middle'|'bottom'
---@field disable? KoraProgressBarDisable
---@field anim? KoraProgressBarAnim
---@field strictAnim? boolean Raise when the animation dictionary cannot load; used by strict compatibility providers.
---@field scenario? KoraProgressBarScenario
---@field props? KoraProgressBarProp[]
---@field prop? KoraProgressBarProp
---@field proptwo? KoraProgressBarProp
---@field emote? string
---@field maxProps? integer|false Override local prop cap; false allows all validated props.

---@class KoraActionsResult
---@field token any
---@field completed boolean
---@field proof? string
---@field authorization? string

---@class KoraActionsOptions
---@field begin fun(...: any): any, string?, string? Returns action token, optional failure reason, and optional minigame proof authorization.
---@field complete fun(result: KoraActionsResult, ...: any): any
---@field label string
---@field duration? integer
---@field minigame? KoraMinigameType
---@field canCancel? boolean
---@field disable? KoraProgressBarDisable
---@field anim? KoraProgressBarAnim

---@class KoraNotifyPayload
---@field title? string
---@field message? string At least one of title or message is required.
---@field type? 'success'|'error'|'warning'|'info'
---@field duration? integer
---@field position? 'top-left'|'top-center'|'top-right'|'bottom-left'|'bottom-center'|'bottom-right'|'center-left'|'center-right'|'top'|'bottom'
---@field icon? string
---@field id? string|number Replaces an existing toast with the same id.
---@field iconColor? string CSS icon colour.
---@field iconAnimation? 'spin'|'spinPulse'|'spinReverse'|'pulse'|'beat'|'fade'|'beatFade'|'bounce'|'shake'
---@field alignIcon? 'top'|'center'
---@field style? table<string, any> Trusted scalar root styles and vetted title/description child styles.
---@field showDuration? boolean Set false to hide the lifetime indicator.

---@class KoraDrawingTextOptions
---@field font? integer
---@field scale? number
---@field color? {r: integer, g: integer, b: integer, a: integer}
---@field maxDistance? number
---@field outline? boolean

---@class KoraMenuItem
---@field id string
---@field label string
---@field description? string
---@field icon? string
---@field image? string
---@field disabled? boolean
---@field values? (string|{label: string, description?: string})[] Side-scroll values.
---@field defaultIndex? integer One-based selected value.
---@field checked? boolean Render as a checkable row.
---@field progress? number Progress from 0 through 100.
---@field colorScheme? string Progress colour.
---@field iconColor? string Icon CSS colour.
---@field iconAnimation? 'spin'|'spinPulse'|'spinReverse'|'pulse'|'beat'|'fade'|'beatFade'|'bounce'|'shake'
---@field iconWidth? number Percentage width used by radial icons.
---@field iconHeight? number Percentage height used by radial icons.
---@field readOnly? boolean Keep an informational row non-interactive.
---@field arrow? boolean Show or suppress a navigation affordance.
---@field metadata? (string|{label: string, value?: any, progress?: number, colorScheme?: string})[]
---@field close? boolean Keep the menu open after confirmation when false.
---@field submenu? {title?: string, items: KoraMenuItem[]}

---@class KoraMenuResult
---@field selectedId? string
---@field path? string[]
---@field valueIndex? integer One-based selected side-scroll value.
---@field checked? boolean Current checked state.
---@field cancelled? boolean
---@field keyPressed? 'Escape'|'Backspace' Root-level dismissal key.

---@class KoraRadialMenuOptions
---@field radius? number

---@class KoraAlertOptions
---@field message string
---@field title? string
---@field image? string
---@field confirmLabel? string
---@field cancelLabel? string
---@field cancellable? boolean
---@field showCancel? boolean Show the Cancel button independently of Escape dismissal.
---@field showClose? boolean Show the corner close control.
---@field dismissOnBackdrop? boolean Allow backdrop dismissal.
---@field destructive? boolean
---@field centered? boolean
---@field size? 'xs'|'sm'|'md'|'lg'|'xl'
---@field overflow? boolean

---@class KoraAlertResult
---@field confirmed boolean

---@alias KoraInputType 'text'|'password'|'textarea'|'number'|'checkbox'|'select'|'multiselect'|'range'|'combobox'|'date'|'date-range'|'time'|'color'
---@class KoraInputOption
---@field value string|number
---@field label string
---@field disabled? boolean

---@class KoraInputField
---@field id string
---@field label string
---@field type KoraInputType
---@field description? string
---@field placeholder? string
---@field default? any
---@field required? boolean
---@field disabled? boolean
---@field min? number
---@field max? number
---@field minLength? integer
---@field maxLength? integer
---@field pattern? string
---@field dateMin? string|number Minimum date/date-range constraint accepted by `Date`.
---@field dateMax? string|number Maximum date/date-range constraint accepted by `Date`.
---@field returnString? boolean Keep date values as ISO strings; false returns local epoch milliseconds.
---@field dateFormat? string Date output pattern when returnString is true.
---@field precision? integer Number decimal precision.
---@field colorFormat? 'hex'|'hexa'|'rgb'|'rgba'|'hsl'|'hsla'
---@field timeFormat? '12'|'24'
---@field clearable? boolean
---@field searchable? boolean
---@field maxSelectedValues? integer
---@field autosize? boolean
---@field minRows? integer
---@field maxRows? integer
---@field icon? string
---@field iconColor? string
---@field step? number Number/range increment; defaults to 1.
---@field copyButton? boolean|{label?: string} text fields only: show a "Copy Text" button right of the input.
---@field keypad? boolean Render a compact numeric keypad for textual PIN entry.
---@field numericOnly? boolean Strip non-digit input in the browser.
---@field presets? {label?: string, value: number}[] Quick amount values.
---@field rows? integer
---@field options? KoraInputOption[]
---@field optionsByValue? table<string, KoraInputOption[]> Select options keyed by dependsOn's selected value.
---@field dependsOn? string Id of the select field that controls optionsByValue.
---@field visibleWhen? {fieldId: string, equals: string|number|boolean} Render only when another field equals this value.

---@class KoraInputResult
---@field values? table<string, any>
---@field cancelled? boolean

---@alias KoraAppTone 'neutral'|'primary'|'success'|'warning'|'destructive'
---@alias KoraAppActionVariant 'primary'|'secondary'|'outline'|'ghost'|'destructive'

---@class KoraAppAction
---@field id string
---@field label string
---@field icon? string
---@field variant? KoraAppActionVariant
---@field state? boolean Current boolean state for a toggle action, rendered as an On/Off indicator.
---@field disabled? boolean
---@field data? any
---@field fields? KoraInputField[] Fields collected inline by AppShell before this action runs.
---@field confirm? string Acknowledgement shown before submitting this action.
---@field closeBeforeAction? boolean Close and release AppShell before invoking the action handler.
---@field hold? boolean Press-and-hold button: onAction runs with context.hold = 'start' on press and 'end' on release (also when the app closes mid-hold); no click is sent.

---@class KoraAppStat
---@field label string
---@field value string|number
---@field description? string
---@field icon? string
---@field tone? KoraAppTone

---@class KoraAppProgressItem
---@field label string
---@field value number Current value, from zero through max.
---@field max number Positive maximum value.
---@field description? string
---@field detail? string Secondary value copy, for example "1,240 / 2,000 XP".
---@field icon? string
---@field tone? KoraAppTone

---@class KoraAppTableColumn
---@field key string
---@field label string
---@field align? 'left'|'center'|'right'
---@field sortable? boolean

---@class KoraAppRichValue
---@field value? string|number|boolean
---@field label? string
---@field description? string
---@field icon? string
---@field tone? KoraAppTone
---@field badge? boolean

---@alias KoraAppTableValue string|number|boolean|KoraAppRichValue

---@class KoraAppMetadataItem
---@field label string
---@field value string|number|boolean
---@field tone? KoraAppTone

---@alias KoraAppImageAspect 'square'|'wide'
---@alias KoraAppImageFit 'cover'|'contain'|'fill'|'none'|'scale-down'

---@class KoraAppListItem
---@field id string
---@field label string
---@field description? string
---@field icon? string
---@field badge? string|number
---@field tone? KoraAppTone
---@field action? string|KoraAppAction Action routed to the registered onAction handler.
---@field data? any
---@field image? string
---@field imageFit? KoraAppImageFit Overrides the list block image fit.
---@field imageAspect? KoraAppImageAspect Overrides the list block image aspect.
---@field metadata? KoraAppMetadataItem[]
---@field actions? KoraAppAction[]
---@field children? KoraAppListItem[]

---@class KoraAppDetailItem
---@field label string
---@field value? string|number|boolean
---@field description? string
---@field icon? string
---@field tone? KoraAppTone

---@class KoraAppTimelineItem
---@field id string
---@field title string
---@field description? string
---@field timestamp? string
---@field icon? string
---@field tone? KoraAppTone
---@field metadata? KoraAppMetadataItem[]
---@field actions? KoraAppAction[]

---@class KoraAppPoint
---@field x number
---@field y number

---@class KoraAppMapCalibrationPoint
---@field world KoraAppPoint
---@field image KoraAppPoint

---@class KoraAppMapTiles
---@field url string URL template containing {z}, {x}, and {y}; cross-resource cfx-nui URLs are supported.
---@field tileSize? number Defaults to 256.
---@field grid? KoraAppPoint Tile counts at maxZoom.
---@field calibration? {a: KoraAppMapCalibrationPoint, b: KoraAppMapCalibrationPoint} Two-point world-to-image calibration.

---@class KoraAppMapMarker: KoraAppPoint
---@field id string
---@field label string
---@field description? string
---@field heading? number
---@field tone? KoraAppTone
---@field icon? string
---@field action? string
---@field data? any
---@field expiresAt? number
---@field fadeDuration? number Marker-specific fade window before expiresAt; overrides the block default.

---@alias KoraAppBlockType 'text'|'stats'|'progress'|'table'|'list'|'actions'|'form'|'details'|'timeline'|'map'|'empty'|'chat'

---@class KoraAppBlock
---@field type KoraAppBlockType
---@field title? string
---@field text? string Text block body.
---@field description? string Form or empty-state description.
---@field icon? string Empty-state icon.
---@field items? KoraAppStat[]|KoraAppProgressItem[]|KoraAppListItem[]|KoraAppDetailItem[]|KoraAppTimelineItem[] Block items.
---@field actions? KoraAppAction[] Action-block buttons.
---@field columns? KoraAppTableColumn[]|integer Table columns, 1-3 details columns, or 1-4 maximum list grid columns.
---@field rows? table<string, KoraAppTableValue>[] Table rows.
---@field empty? string Empty list/table label.
---@field action? string|KoraAppAction Table/map action id, or the always-visible form action.
---@field idKey? string Table row key copied into action context.itemId.
---@field id? string Stable block identity used for drafts and local collection state.
---@field layout? 'list'|'grid'|'cards' List presentation.
---@field cardStyle? 'compact'|'media' Grid/card presentation; compact is the default, media uses a full-width image above the content.
---@field imageFit? KoraAppImageFit List image fit; defaults to cover, individual items may override it.
---@field imageAspect? KoraAppImageAspect List thumbnail shape; defaults to 'square', 'wide' shows a 16:9 thumbnail (compact list/grid rows only), individual items may override it.
---@field searchable? boolean Enable client-side filtering.
---@field searchPlaceholder? string
---@field pageSize? integer Enable client-side paging when positive.
---@field scrollable? boolean Let a list block own vertical overflow inside fixed content.
---@field fields? KoraInputField[] Always-visible form fields.
---@field submitLabel? string Always-visible form submit label.
---@field tiles? KoraAppMapTiles Map tile URL/projection definition.
---@field markers? KoraAppMapMarker[] Map markers.
---@field selectedId? string Selected map marker.
---@field minZoom? number
---@field maxZoom? number
---@field initialZoom? number
---@field follow? boolean
---@field captureWheel? boolean Mouse wheel zooms the map and does not scroll the page behind it. Default true.
---@field recenter? KoraAppPoint
---@field now? number
---@field fadeDuration? number
---@field messages? KoraAppChatMessage[] Chat block messages, oldest first.
---@field composer? KoraAppChatComposer Chat block message box; omit for a read-only conversation.

---@class KoraAppChatMessage
---@field id string Stable message id (used for scroll and unread tracking).
---@field author string
---@field text string Rendered as plain text, never HTML.
---@field timestamp? string
---@field mine? boolean Right-aligned bubble for the viewer's own messages.
---@field unread? boolean A "New" divider is drawn before the first unread message.
---@field status? 'sent'|'delivered'|'seen' Delivery ticks, shown on `mine` messages only: one tick sent, two delivered, two in the brand colour seen.
---@field badge? string Small label next to the author (for example 'Staff').
---@field tone? KoraAppTone

---@class KoraAppChatComposer
---@field action KoraAppAction Plain action; onAction gets context.value = { message = string }.
---@field placeholder? string
---@field maxLength? integer
---@field disabled? boolean
---@field note? string Shown instead of the input when disabled (for example 'This report is closed.').

---@class KoraAppContent
---@field title? string
---@field description? string
---@field actions? KoraAppAction[]
---@field blocks? KoraAppBlock[]
---@field scrollable? boolean Set false to keep the content frame fixed.

---@class KoraAppTab
---@field id string
---@field label string
---@field badge? string|number
---@field content? KoraAppContent

---@class KoraAppNavigationItem
---@field id string
---@field label string
---@field description? string
---@field icon? string
---@field badge? string|number
---@field group? string
---@field disabled? boolean
---@field defaultTab? string
---@field tabs? KoraAppTab[]
---@field content? KoraAppContent

---@class KoraAppDefinition
---@field id string Namespaced stable id.
---@field title string
---@field description? string
---@field icon? string
---@field navigation KoraAppNavigationItem[]
---@field layout? 'standard'|'compact'
---@field defaultView? string
---@field width? number Pixels; clamped to 720-1600 in standard layout and 420-1600 in compact layout.
---@field height? number Pixels; clamped to 420-960.
---@field footer? string
---@field draggable? boolean The header is a drag handle; the panel is clamped to the screen and double-clicking the header resets it. Defaults to Config.ui.apps.draggableDefault (false).
---@field rememberPosition? boolean Remember the dragged position per player in NUI localStorage (draggable apps only).
---@field positionKey? string Storage key suffix for the remembered position; defaults to the app id.
---@field accent? string #RRGGBB primary colour applied while this app is open; omitted apps retain the player's /theme colour.
---@field onAction? fun(actionId: string, context: KoraAppActionContext): KoraAppActionResult?
---@field onChange? fun(actionId: string, context: KoraAppActionContext): table? Receives form drafts; returns a partial definition update without submitting.

---@class KoraAppOpenOptions
---@field data? any Private session data supplied back to onAction/onChange; not rendered.
---@field viewId? string
---@field tabId? string

---@class KoraAppActionContext
---@field appId string
---@field viewId? string
---@field tabId? string
---@field itemId? string
---@field value? any
---@field data? any The data supplied to openApp.
---@field hold? 'start'|'end' Set only for `hold = true` actions; the handler's return value is ignored.

---@class KoraAppActionResult
---@field update? table Partial KoraAppDefinition to merge and render immediately.
---@field close? boolean Close the app after the action.
---@field navigate? {viewId: string, tabId?: string, replace?: boolean} Navigate without rebuilding the definition.
---@field notice? {tone: KoraAppTone, message: string} Show an in-shell notice (or a notification when the action closes AppShell).

---@class KoraAppResult
---@field closed boolean
---@field reason string
---@field viewId? string
---@field tabId? string

---@class KoraInteractOption
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

---@class KoraInteractTargetOptions
---@field options KoraInteractOption[]
---@field distance? number

---@class KoraInteractSize
---@field x number
---@field y number
---@field z number

---@class KoraZoneCommonOptions
---@field debug? boolean
---@field data? any Arbitrary caller-owned passthrough.
---@field onEnter? fun(zone: KoraZoneHandle)
---@field onExit? fun(zone: KoraZoneHandle)
---@field inside? fun(zone: KoraZoneHandle, coords: KoraCoords)
---@field trackPlayer? boolean Set false for predicate-only zones that use contains() but do not need enter/exit tracking.

---@class KoraZoneBoxOptions : KoraZoneCommonOptions
---@field coords KoraCoords
---@field size KoraInteractSize|KoraCoords
---@field rotation? number Degrees around the Z axis.
---@field ignoreZ? boolean Ignore the box Z extent. Defaults false.

---@class KoraZoneSphereOptions : KoraZoneCommonOptions
---@field coords KoraCoords
---@field radius number
---@field includeBoundary? boolean Defaults true.

---@class KoraZoneCircleOptions : KoraZoneSphereOptions

---@class KoraZonePointOptions : KoraZoneCommonOptions
---@field coords KoraCoords
---@field radius? number Defaults to Config.zones.defaultPointRadius.
---@field includeBoundary? boolean Defaults true.

---@class KoraZonePolyOptions : KoraZoneCommonOptions
---@field points KoraCoords[]
---@field thickness? number
---@field minZ? number Poly floor; must be supplied with maxZ.
---@field maxZ? number Poly ceiling; must be supplied with minZ.
---@field ignoreZ? boolean Ignore the poly height band. Defaults false.

---@alias KoraZoneOptions KoraZoneBoxOptions|KoraZoneSphereOptions|KoraZoneCircleOptions|KoraZonePointOptions|KoraZonePolyOptions
---@alias KoraZoneCreatorOptions KoraZoneBoxOptions|KoraZoneSphereOptions|KoraZonePolyOptions

---@class KoraZoneHandle
---@field id integer
---@field type 'box'|'sphere'|'circle'|'poly'
---@field resource string
---@field data any Caller-supplied opts.data value.
---@field remove fun(): boolean
---@field contains fun(coords: KoraCoords): boolean
---@field isInside fun(): boolean
---@field setDebug fun(enabled: boolean): boolean

---@class KoraZoneCreatorResult
---@field type 'box'|'sphere'|'poly'
---@field opts KoraZoneCreatorOptions

---@class KoraRewardItem
---@field chance? number
---@field amount? number|{min: number, max: number}

---@class KoraRewardOptions
---@field mode? 'weighted'|'percent'
---@field rolls? integer
---@field allowNone? boolean

---@alias KoraMinigameType 'lockpick'|'skillbar'|'circuit'|'mash'|'fishing'|'pinpad'|'quiz'|'wordguess'|'wordscramble'|'keys'|'hacking'
---@class KoraMinigameOptions
---@field duration? integer
---@field difficulty? number|string
---@field rounds? integer
---@field [string] any Game-specific fields are documented in modules/minigames/docs.md.

---@class KoraMinigameResult
---@field success boolean
---@field attempts integer
---@field proof? string
---@field cancelled? true
---@field faults? integer
---@field reason? string

---@class KoraStatusEffectDef
---@field duration? integer
---@field stacking? 'replace'|'extend'|'stack'
---@field severityLevels? integer
---@field fx? {screen?: string, ptfx?: KoraFxPtfxDef}
---@field anim? {dict: string, clip: string}
---@field movement? {speedMultiplier?: number}

---@class KoraStatusApplyOptions
---@field duration? integer
---@field severity? integer

---@class KoraStatusActiveEntry
---@field name string
---@field severity? integer
---@field expiresAt? integer

---@class KoraDiscordResponse
---@field status integer
---@field body? string
---@field headers? table<string, string>
---@field data? any
---@field error? string

---@alias KoraDiscordCallback fun(ok: boolean, response: KoraDiscordResponse)

---@class KoraDiscordEmbedField
---@field name string
---@field value string
---@field inline? boolean

---@class KoraDiscordEmbedOptions
---@field title? string
---@field description? string
---@field url? string
---@field color? integer|string
---@field timestamp? boolean|integer|string
---@field footer? string|{text: string, icon_url?: string}
---@field author? string|{name: string, url?: string, icon_url?: string}
---@field image? string|{url: string}
---@field thumbnail? string|{url: string}
---@field fields? KoraDiscordEmbedField[]

---@class KoraStreamResult
---@field [integer] any

---@alias KoraLookupNamespace 'vehicle'|'ped'|'object'|'weapon'|'weapon_component'|'pickup'
---@alias KoraLookupModelNamespace 'vehicle'|'ped'|'object'
---@alias KoraLookupFailure 'catalog_pending'|'not_found'|'ambiguous'
---@alias KoraLookupSource 'base'|'custom'|'base+custom'

---@class KoraLookupMetadata
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

---@class KoraLookupRecord
---@field namespace KoraLookupNamespace
---@field hash integer Unsigned 32-bit hash.
---@field signedHash integer Signed 32-bit representation.
---@field hexHash string Eight-digit hexadecimal representation.
---@field name string Canonical spawn/archetype/hash-key name.
---@field label? string English display label.
---@field labelKey? string GXT label key.
---@field category? string
---@field dlc? string
---@field source KoraLookupSource
---@field resources? string[] Sorted custom resources contributing this entry.
---@field metadata? KoraLookupMetadata Namespace-specific curated metadata.

---@class KoraLibCompat
---@field provideExport fun(providedResource: string, exportName: string, func: function|table) [shared]

---@class kora_lib
---@field actions KoraLibActions
---@field anim KoraLibAnim
---@field blips KoraLibBlips
---@field camera KoraLibCamera
---@field cache KoraLibCache
---@field callback KoraLibCallback
---@field compat KoraLibCompat
---@field closest KoraLibClosest
---@field commands KoraLibCommands
---@field config KoraLibConfig
---@field controls KoraLibControls
---@field discord KoraLibDiscord
---@field distance KoraLibDistance
---@field drawing KoraLibDrawing
---@field entities KoraLibEntities
---@field freecam KoraLibFreecam
---@field events KoraLibEvents
---@field fx KoraLibFx
---@field interact KoraLibInteract
---@field instructional KoraLibInstructional
---@field keybind KoraLibKeybind
---@field logging KoraLibLogging
---@field lookup KoraLibLookup
---@field loops KoraLibLoops
---@field minigames KoraLibMinigames
---@field notify KoraLibNotify
---@field nui KoraLibNui
---@field ox KoraLibOx Private provider for the optional ox_lib bridge; native resources should use Kora.nui.
---@field permissions KoraLibPermissions
---@field placement KoraLibPlacement
---@field print KoraLibPrint
---@field progressbar KoraLibProgressbar
---@field qa KoraLibQa
---@field raycast KoraLibRaycast
---@field random KoraLibRandom
---@field require KoraLibRequire
---@field resources KoraLibResources
---@field rewards KoraLibRewards
---@field screenshot KoraLibScreenshot
---@field sound KoraLibSound
---@field skills KoraLibSkills
---@field state KoraLibState
---@field status KoraLibStatus
---@field stream KoraLibStream
---@field teleport KoraLibTeleport
---@field textui KoraLibTextUI
---@field theme KoraLibTheme
---@field timers KoraLibTimers
---@field util KoraLibUtil
---@field vehicle KoraLibVehicle
---@field visuals KoraLibVisuals
---@field world KoraLibWorld
---@field zones KoraLibZones
---@field lang fun(key: string, ...: any): string [shared]
---@field locale KoraLibLocale

---@class KoraLibLocale
---@field getLanguage fun(): string [shared]
---@field getLanguages fun(): string[] [shared]
---@field setLanguage fun(language: string): boolean, string|nil [client]
---@field translate fun(resource: string, key: string, ...: any): any [shared]

---@class KoraLibActions
---@field run fun(options: KoraActionsOptions, ...: any): boolean, any [client]
---@field isActive fun(): boolean [client]

---@class KoraLibAnim
---@field play fun(entity: integer, dict: string, clip: string, opts?: KoraAnimPlayOptions): KoraAnimHandle|false, string? [client]
---@field stop fun(entity: integer, blendOutSpeed?: number): boolean [client]
---@field stopHandle fun(handle: KoraAnimHandle, blendOutSpeed?: number): boolean [client]
---@field isPlaying fun(entity: integer): boolean [client]
---@field attachProp fun(entity: integer, model: string|integer, bone: string|integer, offset?: KoraCoords, rotation?: KoraCoords, opts?: KoraAnimAttachOptions): integer|false, string? [client]
---@field detachProp fun(prop: integer): boolean, string? [client]
---@field playScenario fun(entity: integer, scenario: string, enterVehicle?: boolean) [client]
---@field clear fun(entity: integer, immediate?: boolean) [client]

---@class KoraLibBlips
---@field getCategoryIds fun(): table<string, integer> [shared]
---@field create fun(coords: KoraCoords, options?: KoraBlipsCreateOptions): integer|false, string? [client]
---@field remove fun(blip: integer): boolean, string? [client]
---@field setInfo fun(blip: integer, info: KoraBlipInfo): boolean, string? [client]
---@field clearInfo fun(blip: integer): boolean, string? [client]
---@field getCategories fun(): KoraBlipCategory[] [client]
---@field getCategory fun(category: string|integer): KoraBlipCategory [client]
---@field getRegistered fun(): KoraRegisteredBlip[] [client]
---@field isCategoryVisible fun(category: string|integer): boolean [client]
---@field hideCategory fun(category: string|integer): boolean [client; returns whether preference changed]
---@field showCategory fun(category: string|integer): boolean [client; returns whether preference changed]
---@field hide fun(blip: integer): boolean, string? [client]
---@field show fun(blip: integer): boolean, string? [client]

---@class KoraCameraDefinition
---@field label? string
---@field location? string
---@field coords KoraCoords Camera position.
---@field target? KoraCoords Point the lens at this world position.
---@field rotation? KoraCoords Camera rotation in degrees.
---@field fov? number

---@class KoraCameraOptions
---@field mode? 'cctv'|'recording'|'helicam'|'operator'
---@field title? string
---@field subtitle? string
---@field cameraLabel? string
---@field cameras? KoraCameraDefinition[]
---@field camera? KoraCameraDefinition
---@field recording? boolean
---@field controls? boolean
---@field timestamp? boolean
---@field viewMode? integer GTA follow-camera mode to restore on close.

---@class KoraLibCamera
---@field open fun(options: KoraCameraOptions): boolean [client]
---@field close fun(reason?: string): boolean [client]
---@field isOpen fun(): boolean [client]
---@field next fun(): boolean [client]
---@field previous fun(): boolean [client]
---@field setRecording fun(recording: boolean): boolean [client]

---@class KoraConfigFieldOptions
---@field label? string
---@field description? string
---@field scope? 'shared'|'client'|'server'
---@field live? boolean
---@field min? number
---@field max? number
---@field step? number
---@field minLength? integer
---@field maxLength? integer
---@field pattern? string
---@field options? table[]
---@field sensitive? boolean Excluded from kora_lib's in-game editor.

---@class KoraLibConfig
---@field define fun(values: table, options?: {scope?: 'shared'|'client'|'server', fileName?: string}): table [shared; consumer-local]
---@field adopt fun(values: table, options?: {scope?: 'shared'|'client'|'server', fileName?: string}): table [shared; consumer-local]
---@field extend fun(values: table, options?: {scope?: 'shared'|'client'|'server'}): table [shared; consumer-local]
---@field onChange fun(path: string, handler: fun(value: any, previous: any): boolean?|nil) [client/server; consumer-local]
---@field boolean fun(value: boolean, options?: KoraConfigFieldOptions): table [shared]
---@field string fun(value: string, options?: KoraConfigFieldOptions): table [shared]
---@field integer fun(value: integer, options?: KoraConfigFieldOptions): table [shared]
---@field number fun(value: number, options?: KoraConfigFieldOptions): table [shared]
---@field enum fun(value: string|number, options: KoraConfigFieldOptions): table [shared]
---@field color fun(value: string, options?: KoraConfigFieldOptions): table [shared]
---@field vector2 fun(value: any, options?: KoraConfigFieldOptions): table [shared]
---@field vector3 fun(value: any, options?: KoraConfigFieldOptions): table [shared]
---@field vector4 fun(value: any, options?: KoraConfigFieldOptions): table [shared]
---@field object fun(value: table, options?: KoraConfigFieldOptions): table [shared]
---@field list fun(value: table, item?: table, options?: KoraConfigFieldOptions): table [shared]
---@field map fun(value: table, item?: table, options?: KoraConfigFieldOptions): table [shared]
---@field optional fun(value: any, inner: table, options?: KoraConfigFieldOptions): table [shared]
---@field get fun(resource?: string, path?: string|string[]): any, string? [client/server; consumer-local]
---@field bind fun(resource: string, path: string|string[]|nil, handler: fun(value: any, previous: any, change: table)): fun() [client/server; consumer-local]
---@field whenReady fun(resources: string[], handler: fun()) [client/server; consumer-local]
---@field onValidate fun(handler: fun(proposed: table, previous: table, path: string[]): boolean?, string?) [server; consumer-local]
---@field onApply fun(handler: fun(configured: table, active: table, path: string[]): boolean?) [server; consumer-local]
---@field register fun(definition: table): boolean [server; kora_lib internal]
---@field open fun(resource?: string) [client]

---@class KoraLibCache
---@field get fun(key: string): any [client]
---@field set fun(key: string, value: any) [client]
---@field onChange fun(key: string, handler: fun(newValue: any, oldValue: any)) [client]
---@field offChange fun(key: string) [client]
---@field playerId fun(): integer [client]
---@field serverId fun(): integer [client]
---@field ped fun(): integer [client]
---@field coords fun(): KoraCoords [client]
---@field vehicle fun(): integer|false [client]
---@field seat fun(): integer|false [client]
---@field enteringVehicle fun(): integer|false [client]
---@field enteringSeat fun(): integer|false [client]
---@field weapon fun(): integer [client]
---@field health fun(): integer [client]
---@field isDead fun(): boolean [client]
---@field armour fun(): integer [client]
---@field stamina fun(): number [client]

---@class KoraLibCallback
---@field assertName fun(name: string) [shared]
---@field register fun(name: string, handler: fun(...: any): any, opts?: KoraRegistrationOptions) [client/server; opts is server client-to-server only]
---@field unregister fun(name: string): boolean [client/server]
---@field trigger fun(targetOrName: integer|string, nameOrArg?: any, ...: any): any [client: name,...; server: target,name,...]
---@field triggerPacked fun(...: any): { n: integer, [integer]: any } Internal: the envelope form of trigger used by the consumer proxy in init.lua.

---@class KoraLibClosest
---@field player fun(srcOrCoords: integer|KoraCoords, coordsOrDistance?: KoraCoords|number, distance?: number): {id: integer?, distance: number?} [client/server]
---@field vehicle fun(srcOrCoords: integer|KoraCoords, coordsOrDistance?: KoraCoords|number, distance?: number): {id: integer?, distance: number?} [client/server]
---@field ped fun(srcOrCoords: integer|KoraCoords, coordsOrDistance?: KoraCoords|number, distance?: number): {id: integer?, distance: number?} [client/server]
---@field object fun(srcOrCoords: integer|KoraCoords, coordsOrDistance?: KoraCoords|number, distance?: number): {id: integer?, distance: number?} [client/server]

---@class KoraLibCommands

---@class KoraLibControls
---@field acquire fun(controlIds: integer[], options?: KoraControlsOptions): integer [client]
---@field release fun(leaseId: integer): boolean [client]

---@class KoraLibDiscord

---@class KoraLibDistance
---@field player fun(srcOrCoords: integer|KoraCoords, coordsOrDistance?: KoraCoords|number, distance?: number): boolean [client/server]
---@field coords fun(coords1: KoraCoords, coords2: KoraCoords, distance: number): boolean [client/server]
---@field entity fun(srcOrEntity: integer, entityOrDistance: integer|number, distance?: number): boolean [client/server]
---@field x fun(srcOrPoint: integer|KoraCoords, pointOrDistance: KoraCoords|number, distance?: number): boolean [client/server]
---@field y fun(srcOrPoint: integer|KoraCoords, pointOrDistance: KoraCoords|number, distance?: number): boolean [client/server]
---@field xy fun(srcOrPoint: integer|KoraCoords, pointOrDistance: KoraCoords|number, distance?: number): boolean [client/server]

---@class KoraLibDrawing
---@field text3d fun(coords: KoraCoords, text: string, options?: KoraDrawingTextOptions): boolean [client]

---@class KoraLibEntities
---@field create fun(model: string|integer, coords: KoraCoords, options?: KoraEntitiesCreateOptions): integer|false, string? [client]
---@field createScoped fun(model: string|integer, coords: KoraCoords, options: KoraEntitiesScopedOptions): KoraScopedEntityHandle [client]
---@field remove fun(entity: integer): boolean, string? [client]
---@field requestControl fun(entity: integer, timeout?: integer): boolean, string? [client]
---@field delete fun(entity: integer, timeout?: integer): boolean, string? [client]

---@class KoraLibEvents
---@field assertName fun(name: string) [shared]
---@field trigger fun(name: string, ...: any): boolean, string? [client]
---@field onPush fun(name: string, handler: fun(...: any)) [client]
---@field offPush fun(name: string): boolean [client]

---@class KoraLibFx
---@field playPtfx fun(def: KoraFxPtfxDef): KoraFxPtfxHandle|false, string? [client]
---@field stop fun(handle: KoraFxPtfxHandle|false): boolean [client]
---@field screenEffect fun(name: string, duration?: integer, looped?: boolean): KoraFxScreenHandle [client]
---@field stopScreenEffect fun(handle: KoraFxScreenHandle|false): boolean [client]

---@class KoraLibInteract
---@field open fun(options: KoraInteractOption[]): boolean [client]
---@field close fun() [client]
---@field isActive fun(): boolean [client]
---@field addCircleZone fun(name: string, coords: KoraCoords, radius: number, targetOptions: KoraInteractTargetOptions|KoraInteractOption[], debug?: boolean): KoraZoneHandle [client]
---@field addBoxZone fun(name: string, coords: KoraCoords, size: KoraInteractSize|KoraCoords, targetOptions: KoraInteractTargetOptions|KoraInteractOption[], debug?: boolean): KoraZoneHandle [client]
---@field removeZone fun(name: string): boolean [client]
---@field addTargetModel fun(models: string|integer|(string|integer)[], size: KoraInteractSize|KoraCoords, targetOptions: KoraInteractTargetOptions|KoraInteractOption[], debug?: boolean): KoraZoneHandle[] [client]
---@field addTargetEntity fun(entity: integer, size: KoraInteractSize|KoraCoords, targetOptions: KoraInteractTargetOptions|KoraInteractOption[], debug?: boolean): KoraZoneHandle [client]
---@field addEntity fun(entity: integer, options: KoraInteractOption[], distance?: number): integer [client]
---@field removeEntity fun(entity: integer, id?: integer): boolean [client]
---@field addModel fun(model: string|integer, options: KoraInteractOption[], distance?: number): integer [client]
---@field removeModel fun(model: string|integer, id?: integer): boolean [client]

---@class KoraLibKeybind
---@field add fun(options: KoraKeybindOptions): KoraKeybindHandle [client]
---@field remove fun(name: string): boolean [client]
---@field list fun(): table[] [client]

---@class KoraLibLogging
---@field _internal table Private implementation; not an export.
---@field trace fun(eventName: string, message: string, fields?: table): boolean Both realms; does not yield.
---@field debug fun(eventName: string, message: string, fields?: table): boolean Both realms; does not yield.
---@field info fun(eventName: string, message: string, fields?: table): boolean Both realms; does not yield.
---@field warn fun(eventName: string, message: string, fields?: table): boolean Both realms; does not yield.
---@field error fun(eventName: string, message: string, fields?: table): boolean Both realms; does not yield.
---@field fatal fun(eventName: string, message: string, fields?: table): boolean Both realms; does not yield.
---@field isEnabled fun(level: string): boolean
---@field nui fun(level: string, eventName: string, message: string, fields?: table): boolean NUI bridge. [client]
---@field getCapture fun(): table Capture snapshot. [client]
---@field getStats fun(): table [shared]

---@class KoraLibLookup
---@field get fun(namespace: KoraLookupNamespace, value: integer|string): KoraLookupRecord?, KoraLookupFailure?, KoraLookupRecord[]? [shared]
---@field model fun(value: integer|string, kind?: KoraLookupModelNamespace): KoraLookupRecord?, KoraLookupFailure?, KoraLookupRecord[]? [shared]
---@field weapon fun(value: integer|string): KoraLookupRecord?, KoraLookupFailure?, KoraLookupRecord[]? [shared]
---@field weaponComponent fun(value: integer|string): KoraLookupRecord?, KoraLookupFailure?, KoraLookupRecord[]? [shared]
---@field pickup fun(value: integer|string): KoraLookupRecord?, KoraLookupFailure?, KoraLookupRecord[]? [shared]
---@field preload fun(namespaces?: KoraLookupNamespace|KoraLookupNamespace[]): boolean [shared]
---@field ready fun(): boolean [shared]
---@field awaitReady fun(timeout?: integer): boolean, string? [shared]

---@class KoraLibLoops
---@field controlled fun(call: fun(): any, tries?: integer|false, timeout?: integer|false, backoff?: boolean|integer): any, string? [shared]

---@class KoraLibMinigames
---@field play fun(gameType: KoraMinigameType, opts?: KoraMinigameOptions, authorization?: string, owner?: string): KoraMinigameResult [client; waits for the round to finish]
---@field playAsync fun(gameType: KoraMinigameType, opts?: KoraMinigameOptions, authorization?: string, owner?: string): promise [client; internal composition primitive]
---@field cancel fun(): boolean [client]
---@field playSkillCheck fun(skill: string, gameType: KoraMinigameType, opts?: KoraMinigameOptions, authorization?: string): KoraMinigameResult [client; waits for the round to finish]
---@field triangleWave fun(elapsedMs: number, speedHz: number): number [shared]

---@class KoraLibNotify
---@field send fun(payloadOrSource: KoraNotifyPayload|integer, payload?: KoraNotifyPayload) [client/server]
---@field assert fun(payload: KoraNotifyPayload) [shared]
---@field withDefaults fun(payload: KoraNotifyPayload): KoraNotifyPayload [shared]
---@field normalizeType fun(notifyType: any): any [shared]
---@field normalize fun(payload: KoraNotifyPayload): KoraNotifyPayload [shared]

---@class KoraMenuPosition
---@field horizontal? 'left'|'center'|'right'
---@field vertical? 'top'|'center'|'bottom'
---@field offsetX? positive integer Pixels from the selected horizontal edge.
---@field offsetY? positive integer Pixels from the selected vertical edge.

---@class KoraMenuOptions
---@field position? KoraMenuPosition
---@field maxWidth? positive integer Pixels.
---@field maxHeight? positive integer Pixels.
---@field canClose? boolean Set false to prevent Escape/backdrop dismissal.
---@field startIndex? positive integer Initially selected one-based row.
---@field presentation? 'dialog'|'panel' Panel is compact and non-modal.

---@class KoraLibNui
---@field send fun(action: string, data?: any) [client]
---@field setDispatchFeed fun(payload: table|false): boolean [client]
---@field setFocus fun(mouse: boolean, keyboard: boolean) [client]
---@field acquireFocus fun(mouse: boolean, keyboard: boolean, keepInput?: boolean, owner?: string): function [client; internal composition primitive]
---@field releaseFocus fun(release: function) [client; internal composition primitive]
---@field withFocus fun(mouse: boolean, keyboard: boolean, fn: fun(): any): any [client]
---@field registerCallback fun(name: string, handler: fun(data: any): any) [client]
---@field request fun(action: string, data?: any, timeout?: integer|false): promise|any [client]
---@field requestAsync fun(action: string, data?: any, timeout?: integer|false, owner?: string, focused?: boolean, onEvent?: fun(event: string, data: any)): promise [client; internal composition primitive]
---@field cancelRequest fun(request: promise, result?: any, rejection?: string): boolean [client; internal composition primitive]
---@field updateRequest fun(request: promise, action: string, data: any): boolean [client; internal composition primitive]
---@field copyToClipboard fun(text: string): promise|boolean [client] true when copied, false on failure
---@field openMenu fun(items: KoraMenuItem[], title?: string, opts?: KoraMenuOptions): KoraMenuResult|promise [client]
---@field openContextMenu fun(items: KoraMenuItem[], x?: number, y?: number): KoraMenuResult|promise [client]
---@field openRadialMenu fun(items: KoraMenuItem[], opts?: KoraRadialMenuOptions): KoraMenuResult|promise [client]
---@field openAlert fun(opts: KoraAlertOptions): KoraAlertResult|promise [client]
---@field openInputDialog fun(fields: KoraInputField[], title?: string, description?: string): KoraInputResult|promise [client]
---@field registerApp fun(definition: KoraAppDefinition): string [client]
---@field supportsAppTableHeaderControls fun(): boolean [client]
---@field unregisterApp fun(id: string): boolean [client]
---@field openApp fun(id: string, opts?: KoraAppOpenOptions): KoraAppResult|promise [client]
---@field updateApp fun(id: string, update: table): boolean [client]
---@field closeApp fun(id?: string): boolean [client]
---@field isAppOpen fun(id?: string): boolean [client]

---@class KoraLibOx
---@field alertDialog fun(data: table, timeout: integer|false|nil, owner: string): 'confirm'|'cancel'|nil [client; ox_lib provider]
---@field closeAlertDialog fun(reason: string|nil, owner: string) [client; ox_lib provider]
---@field setClipboard fun(value: string, owner: string) [client; ox_lib provider]
---@field registerContext fun(context: table|table[], owner: string) [client; ox_lib provider]
---@field showContext fun(id: string, owner: string) [client; ox_lib provider]
---@field getOpenContextMenu fun(owner: string): string? [client; ox_lib provider]
---@field hideContext fun(onExit: boolean|nil, owner: string) [client; ox_lib provider]
---@field inputDialog fun(heading: string, rows: table[], options: table|nil, owner: string): any[]? [client; ox_lib provider]
---@field closeInputDialog fun(owner: string) [client; ox_lib provider]
---@field setNuiFocus fun(allowInput: boolean|nil, disableCursor: boolean|nil, owner: string) [client; ox_lib provider]
---@field resetNuiFocus fun(owner: string) [client; ox_lib provider]
---@field registerMenu fun(data: table, callback: function|nil, owner: string) [client; ox_lib provider]
---@field showMenu fun(id: string, startIndex: integer|nil, owner: string) [client; ox_lib provider]
---@field hideMenu fun(onExit: boolean|nil, owner: string) [client; ox_lib provider]
---@field setMenuOptions fun(id: string, options: table, index: integer|nil, owner: string) [client; ox_lib provider]
---@field getOpenMenu fun(owner: string): string? [client; ox_lib provider]
---@field notify fun(data: table, owner: string) [client; ox_lib provider]
---@field defaultNotify fun(data: table, owner: string) [client; ox_lib provider]
---@field progressBar fun(data: table, owner: string): boolean [client; ox_lib provider]
---@field progressCircle fun(data: table, owner: string): boolean [client; ox_lib provider]
---@field cancelProgress fun(owner: string) [client; ox_lib provider]
---@field progressActive fun(owner: string): boolean [client; ox_lib provider]
---@field registerRadial fun(radial: table, owner: string) [client; ox_lib provider]
---@field getCurrentRadialId fun(owner: string): string? [client; ox_lib provider]
---@field hideRadial fun(owner: string) [client; ox_lib provider]
---@field addRadialItem fun(items: table|table[], parentMenuId: string|nil, owner: string) [client; ox_lib provider]
---@field removeRadialItem fun(id: string, parentMenuId: string|nil, owner: string) [client; ox_lib provider]
---@field clearRadialItems fun(owner: string) [client; ox_lib provider]
---@field disableRadial fun(state: boolean, owner: string) [client; ox_lib provider]
---@field showRadialMenu fun(id: string, owner: string) [client; ox_lib provider]
---@field skillCheck fun(difficulty: string|table|table[], inputs: string[]|nil, owner: string): boolean [client; ox_lib provider]
---@field cancelSkillCheck fun(owner: string) [client; ox_lib provider]
---@field skillCheckActive fun(owner: string): boolean [client; ox_lib provider]
---@field showTextUI fun(text: string, options: table|nil, owner: string) [client; ox_lib provider]
---@field hideTextUI fun(owner: string) [client; ox_lib provider]
---@field isTextUIOpen fun(owner: string): boolean, string? [client; ox_lib provider]
---@field getLocaleKey fun(owner?: string): string [shared; ox_lib provider]
---@field setLocale fun(key: string, localeData?: table|string, owner?: string) [client; ox_lib provider; string second arg preserves the legacy owner form]
---@field disposeOwner fun(owner: string) [client,server; ox_lib provider]

---@class KoraLibSkills
---@field isAvailable fun(): boolean [client,server]
---@field get fun(...: any): table|nil [client: (skill?: string); server: (src: integer, skill?: string)]
---@field getAll fun(...: any): table|nil [client: (); server: (src: integer)]
---@field hasLevel fun(...: any): boolean [client: (skill: string, level: integer); server: (src: integer, skill: string, level: integer)]
---@field adjustMinigame fun(...: any): table|nil [client: (skill: string, gameType: string, options?: table); server: (src: integer, skill: string, gameType: string, resolvedOptions: table)]

---@class KoraPermissionOptions
---@field prefix? string ACE object prefix, such as `kora_core` for `kora_core.admin`.
---@field discordRoles? table<string, string|string[]> Permission/level to Discord role name/ID mappings.

---@class KoraPermissionCheck
---@field level string The level this ACE object would grant.
---@field object string The ACE object passed to IsPlayerAceAllowed.
---@field raw string tostring() of what the native returned, so a non-boolean is visible.
---@field type string type() of what the native returned.
---@field allowed boolean Normalized result.

---@class KoraLibQa
---@field mark fun(name: string, data?: table, target?: integer) [shared] Records a named point in the active kora_qa run; no-op when nobody is testing. `target` is server-only.
---@field active fun(src?: integer): boolean [shared] Client: local player has an active run. Server: `src` (or anyone) has one.
---@field onEvent fun(fn: function): integer [shared] kora_qa: receive QA events (server `fn(src, event)`, client `fn(event)`).
---@field offEvent fun(id: integer): boolean [shared] Removes an onEvent handler.
---@field setActive fun(srcOrState: integer|boolean, state?: boolean): boolean [shared] kora_qa only: client `setActive(state)`, server `setActive(src, state)`.

---@class KoraLibPermissions
---@field explain fun(src: integer, levels: string[], prefixOrOptions?: string|KoraPermissionOptions): KoraPermissionCheck[], string [server] -- diagnostics only; nothing gates on this

---@class KoraPlacementRotation
---@field pitch number
---@field roll number
---@field yaw number

---@class KoraPlacementResult
---@field model string|integer
---@field coords KoraCoords
---@field heading number
---@field rotation KoraPlacementRotation

---@class KoraLibPlacement
---@field cancel fun(): boolean, string? [client] Cancels only the invoking resource's placement; settles its pending result as nil.
---@field start fun(model: string|integer, options?: KoraPlacementOptions): KoraPlacementResult|promise|nil [client]
---@field isActive fun(): boolean [client]
---@field generateSnippet fun(result: KoraPlacementResult): string [client]

---@class KoraPlacementOptions
---@field coords? KoraCoords Initial transform for moving an existing placement.
---@field rotation? KoraPlacementRotation
---@field bounds? {points: KoraCoords[], minZ: number, maxZ: number} Allowed polygon; local placement is constrained but the server must validate again.
---@field raycast? boolean Enables surface snapping from the scripted camera; R toggles it and manual movement disables it.
---@field numericInput? boolean N opens shared numeric position/rotation fields.
---@field copy? boolean Defaults to true; false uses a gameplay confirmation without copying a Lua snippet.

---@class KoraFreecamOptions
---@field coords? KoraCoords
---@field rotation? KoraCoords
---@field fov? number
---@field maxDistance? number Radius centred on the initial freecam position.
---@field zone? KoraZoneHandle
---@field focusCoords? KoraCoords
---@field movementMode? 'camera'|'grid'
---@field moveSpeed? number Metres per second before the fast multiplier.
---@field lookSensitivity? number Degrees per raw mouse-look unit.
---@field fastMultiplier? number Movement multiplier while sprint is held.
---@field transitionMs? number Script-camera blend duration.
---@field upControl? integer Optional GTA control ID for direct vertical movement.
---@field downControl? integer Optional GTA control ID for direct vertical movement.
---@field freezePlayer? boolean Defaults to true.

---@class KoraFreecamHandle
---@field stop fun(reason?: string): boolean
---@field isActive fun(): boolean
---@field getCoords fun(): KoraCoords|nil
---@field getRotation fun(): {pitch: number, roll: number, yaw: number}|nil
---@field getCamera fun(): integer|nil Native scripted-camera handle for raycasts and other camera natives.
---@field getMovementMode fun(): 'camera'|'grid'|nil
---@field setMovementMode fun(mode: 'camera'|'grid'): boolean
---@field setFocus fun(coords: KoraCoords|nil): boolean

---@class KoraLibFreecam
---@field start fun(options?: KoraFreecamOptions): KoraFreecamHandle|false, string? [client]
---@field isActive fun(): boolean [client]

---@class KoraInstructionalButton
---@field label string
---@field group? string rows sharing a group collapse into one row labelled by the group
---@field control? integer
---@field command? string
---@field keybind? KoraKeybindHandle

---@class KoraInstructionalHandle
---@field setButtons fun(buttons: KoraInstructionalButton[]): boolean
---@field hide fun(): boolean
---@field isVisible fun(): boolean

---@class KoraLibInstructional
---@field show fun(buttons: KoraInstructionalButton[]): KoraInstructionalHandle [client]

---@class KoraLibPrint
---@field debug fun(...: any) [shared]
---@field info fun(...: any) [shared]
---@field error fun(...: any) [shared]
---@field warn fun(...: any) [shared]
---@field success fun(...: any) [shared]

---@class KoraLibProgressbar
---@field validate fun(payload: KoraProgressBarPayload): true [client; validates without starting a bar]
---@field start fun(payload: KoraProgressBarPayload, owner?: string): boolean, string? [client]
---@field cancel fun(): boolean [client]
---@field isActive fun(): boolean [client]

---@class KoraLibRaycast
---@field fromCoords fun(startCoords: KoraCoords, endCoords: KoraCoords, flags?: integer, ignoreEntity?: integer): boolean, KoraCoords?, integer?, KoraCoords? [client; returns hit, coords, entityHit, surfaceNormal]
---@field fromCamera fun(maxDistance: number, flags?: integer, ignoreEntity?: integer): boolean, KoraCoords?, integer?, KoraCoords? [client; kora_lib order differs from ox_lib]
---@field fromCam fun(cam: integer, maxDistance: number, flags?: integer, ignoreEntity?: integer): boolean, KoraCoords?, integer?, KoraCoords? [client]
---@field getCoords fun(data?: KoraRaycastCoordsOptions): KoraRaycastCoordsResult? [client; blocks until confirmed or cancelled]
---@field start fun(startCoords: KoraCoords, endCoords: KoraCoords, flags?: integer, ignoreEntity?: integer): integer [client; returns a ray handle for await/poll]
---@field startFromCamera fun(maxDistance: number, flags?: integer, ignoreEntity?: integer): integer [client; returns a ray handle for await/poll]
---@field await fun(rayHandle: integer): boolean, KoraCoords?, integer?, KoraCoords? [client]
---@field poll fun(rayHandle: integer): boolean, boolean, KoraCoords?, integer?, KoraCoords? [client; settled, hit, coords, entityHit, surfaceNormal]

---@class KoraRaycastCoordsOptions
---@field type? 'object' Omit for the default orb marker.
---@field object? string|integer Preview model; required when type is object.
---@field heading? number Initial preview heading. Defaults to 180.
---@field maxDistance? number Maximum camera ray distance. Defaults to 50 metres.
---@field flags? integer Shape-test flags. Defaults to all intersections.

---@class KoraRaycastCoordsResult
---@field coords { x: number, y: number, z: number, w?: number } Two-decimal coordinates; w is present for object previews.
---@field object string|integer|false Preview model, or false for the orb picker.

---@class KoraLibRandom
---@field pick fun(list: any[], options?: KoraRandomPickOptions): any|any[] [shared]

---@class KoraLibRequire
---@field load fun(resource: string, paths: string|string[]): any [shared; an array returns one value per path]
---@field current fun(paths: string|string[]): any [shared; an array returns one value per path]
---@field ["local"] fun(paths: string|string[]): any [shared; bracket-form alias of current]

---@class KoraLibResources
---@field isStarted fun(resourceName: string): boolean [shared]
---@field awaitStarted fun(resourceName: string, options?: KoraResourceAwaitOptions): boolean, string? [shared]
---@field registry fun(onDispose: fun(id: any)): KoraResourcesRegistry [client]

---@class KoraLibRewards
---@field generate fun(items: KoraRewardItem[], opts?: KoraRewardOptions): table[] [shared]

---@class KoraLibScreenshot
---@field capture fun(options?: KoraScreenshotOptions, timeout?: integer): promise|any [client] Resolves to a data URI.
---@field upload fun(url: string, field?: string, options?: KoraScreenshotOptions, timeout?: integer): promise|any [client] Captures then uploads the image.
---@field requestScreenshot fun(options?: KoraScreenshotOptions|fun(data: string?), callback?: fun(data: string?)) [client] screenshot-basic-compatible callback export.
---@field requestScreenshotUpload fun(url: string, field: string, options?: KoraScreenshotOptions|fun(response: string?), callback?: fun(response: string?)) [client] screenshot-basic-compatible callback export.
---@field requestClient fun(player: integer, options?: KoraScreenshotOptions, callback?: fun(err: string|false, result?: string)): string [server] Requests a one-time client upload.

---@class KoraSoundOptions
---@field network? boolean Play for nearby players too, rather than only locally. Defaults to false.
---@field range? number Audible range in metres, world sounds only. Defaults to Config.sound.defaultRange.
---@field bank? string Audio bank to request (and wait for) before playing.
---@field releaseAfter? number Milliseconds before the sound id is auto-released. Defaults to Config.sound.defaultReleaseAfter.

---@class KoraLibSound
---@field playFrontend fun(name: string, set: string, options?: KoraSoundOptions): number|false, string? [client]
---@field playFromCoords fun(coords: KoraCoords, name: string, set: string, options?: KoraSoundOptions): number|false, string? [client]
---@field playFromEntity fun(entity: number, name: string, set: string, options?: KoraSoundOptions): number|false, string? [client]
---@field stop fun(soundId: number): boolean, string? [client]
---@field isLive fun(soundId: number): boolean [client]

---@class KoraLibState
---@field awaitGlobal fun(key: string, timeoutMs?: integer, pollIntervalMs?: integer): any, string? [shared]
---@field onChange fun(keyFilter: string?, bagFilter: string?, handler: fun(change: KoraStateChange)): integer [client/server]
---@field offChange fun(listenerId: integer): boolean [client/server]

---@class KoraLibStatus
---@field assertName fun(name: string) [shared]
---@field registerEffect fun(name: string, def: KoraStatusEffectDef) [shared]
---@field getEffectDef fun(name: string): KoraStatusEffectDef? [shared]
---@field apply fun(targetOrName: integer|string, nameOrOpts?: string|KoraStatusApplyOptions, opts?: KoraStatusApplyOptions): boolean, string? [client/server]
---@field remove fun(targetOrName: integer|string, name?: string): boolean [client/server]
---@field isActive fun(targetOrName: integer|string, name?: string): boolean [client/server]
---@field getActive fun(target?: integer): KoraStatusActiveEntry[] [client/server]
---@field onChange fun(handler: fun(name: string, applied: boolean)): integer [client]
---@field offChange fun(listenerId: integer) [client]

---@class KoraLibStream
---@field loadModel fun(model: string|integer, cb?: fun(hash: integer), options?: KoraStreamLoadOptions): integer|false, string? [client]
---@field loadPtfx fun(fxName: string, cb?: fun(name: string), options?: KoraStreamLoadOptions): string|false, string? [client]
---@field loadAnimDict fun(animDict: string, cb?: fun(name: string), options?: KoraStreamLoadOptions): string|false, string? [client]
---@field loadAnimSet fun(animSet: string, cb?: fun(name: string), options?: KoraStreamLoadOptions): string|false, string? [client]
---@field loadClipSet fun(clipSet: string, cb?: fun(name: string), options?: KoraStreamLoadOptions): string|false, string? [client]
---@field loadIpl fun(iplName: string, cb?: fun(name: string), options?: KoraStreamLoadOptions): string|false, string? [client]
---@field loadScaleformMovie fun(scaleformName: string, cb?: fun(handle: integer), options?: KoraStreamLoadOptions): integer|false, string? [client]
---@field loadTextureDict fun(textureDict: string, cb?: fun(name: string), isAdditionalTextures?: boolean): string|false, string? [client]
---@field loadAudioBank fun(audioBank: string, cb?: fun(name: string)): string|false, string? [client]
---@field loadCollision fun(coords: KoraCoords, cb?: fun(), entity?: integer): boolean, string? [client]
---@field loadWeaponAsset fun(weapon: string|integer, cb?: fun(hash: integer), weaponResourceFlags?: integer, extraWeaponComponentFlags?: integer): integer|false, string? [client]

---@class KoraLibTeleport
---@field entity fun(entity: integer, coords: KoraCoords, opts?: KoraTeleportOptions): boolean [client]
---@field player fun(coords: KoraCoords, opts?: KoraTeleportOptions): boolean [client]
---@field toWaypoint fun(opts?: KoraWaypointTeleportOptions): boolean, string? [client]

---@class KoraLibTextUI
---@field show fun(text: string, opts?: KoraTextUIOptions, owner?: string): integer [client]
---@field update fun(id: integer, text: string, opts?: KoraTextUIOptions): boolean [client]
---@field hide fun(id: integer): boolean [client]
---@field isOpen fun(id?: integer): boolean [client]
---@field isVisible fun(id: integer): boolean [client]

---@class KoraLibTheme
---@field accentColor fun(): string [shared] Forwarded to kora_theme:getPrimaryColor().
---@field tokens fun(overrides?: string|table<string, string>): table<string, string> [shared] Forwarded to kora_theme:getTokens().
---@field push fun(): table<string, string> [client] Reapplies kora_theme to kora_lib's NUI.
---@field getFonts fun(): { body: KoraLibThemeFont, heading: KoraLibThemeFont, mono: KoraLibThemeFont } [shared] Forwarded to kora_theme:getFonts().
---@field onFontsChanged fun(handler: fun(fonts: table)): fun() [client] Runs handler after an admin changes the server fonts; returns an unsubscribe function.

---@class KoraLibThemeFont
---@field id string Catalog id (`poppins`), `default` or `custom`.
---@field label string Display name.
---@field stack string Resolved CSS font-family stack.
---@field source 'config'|'theme.json'|'default' Where the choice came from.

---@class KoraDebounced
---@field cancel fun(): boolean Drops a pending run without firing it.
---@field isPending fun(): boolean

---@class KoraThrottled
---@field reset fun() Clears the cooldown so the next call passes through.
---@field remaining fun(): integer Milliseconds until the next call is allowed; 0 when ready.

---@class KoraLibTimers
---@field setInterval fun(fn: fun(), interval: integer): integer [shared]
---@field setTimeout fun(fn: fun(), delay: integer): integer [shared]
---@field clearInterval fun(id: integer): boolean [shared]
---@field clearTimeout fun(id: integer): boolean [shared]
---@field debounce fun(fn: fun(...), wait: integer): KoraDebounced [shared]
---@field throttle fun(fn: fun(...), interval: integer): KoraThrottled [shared]
---@field cooldown fun(interval: integer): KoraCooldownHandle [shared]
---@field count fun(): integer [shared]

---@class KoraLibUtil
---@field deepClone fun(value: any): any [shared]
---@field fnv1a fun(value: string): string [shared]
---@field isCallable fun(value: any): boolean [shared]
---@field trim fun(value: any): any [shared]
---@field cleanText fun(value: any, options?: KoraCleanTextOptions): string|nil, string? [shared]
---@field truncateUtf8 fun(value: string, maximum: integer): string|nil, string? [shared]
---@field isFiniteNumber fun(value: any): boolean [shared]
---@field isInteger fun(value: any): boolean [shared]
---@field decodeJson fun(value: string): any, string? [shared]
---@field clamp fun(value: number, min: number, max: number): number [shared]
---@field round fun(value: number, decimals?: integer): number [shared]
---@field randomFloat fun(min: number, max: number): number [shared]
---@field weightedChoice fun(list: {[1]: any, [2]: number}[]): any [shared]
---@field tableContains fun(t: table, value: any): boolean [shared]
---@field lerp fun(a: number, b: number, t: number): number [shared]
---@field vecAdd fun(a: KoraSpatialVector, b: KoraSpatialVector): KoraCoords [shared]
---@field vecSub fun(a: KoraSpatialVector, b: KoraSpatialVector): KoraCoords [shared]
---@field vecScale fun(v: KoraSpatialVector, scalar: number): KoraCoords [shared]
---@field vecLength fun(v: KoraSpatialVector): number [shared]
---@field vecDistance fun(a: KoraSpatialVector, b: KoraSpatialVector): number [shared]
---@field vecDistance2d fun(a: KoraSpatialVector, b: KoraSpatialVector): number [shared]
---@field vecNormalize fun(v: KoraSpatialVector): KoraCoords [shared]
---@field headingToDirection fun(heading: number): KoraCoords [shared]
---@field directionToHeading fun(v: KoraSpatialVector): number [shared]
---@field bearing fun(origin: KoraSpatialVector, target: KoraSpatialVector): number [shared]
---@field nearest fun(list: any[], position: KoraSpatialVector, opts: KoraNearestOptions): any, number? [shared]
---@field rateLimiter fun(max: integer, window: number): KoraRateLimiter [shared]
---@field worldToScreen fun(coords: KoraCoords): number, number, boolean [client]
---@field worldToScreenPixels fun(coords: KoraCoords): number, number, boolean [client]

---@class KoraLibVehicle
---@field normalizePlate fun(value: any, options?: KoraVehicleNormalizePlateOptions): string|nil, string? [shared]
---@field requestControl fun(entity: integer, timeout?: integer): boolean, string? [client]
---@field delete fun(vehicle: integer, options?: KoraVehicleDeleteOptions): boolean, string? [client]
---@field isDriver fun(vehicle: integer): boolean [client]
---@field model fun(vehicle: integer): integer|false [client]
---@field plate fun(vehicle: integer): string|false [client]
---@field label fun(vehicle: integer): string|false [client]
---@field getProperties fun(vehicle: integer): KoraVehicleProperties|false, string? [client]
---@field setProperties fun(vehicle: integer, properties: KoraVehicleProperties, opts?: KoraVehicleSetPropertiesOptions): boolean, string? [client]

---@class KoraLibVisuals
---@field fade fun(duration?: number|string|KoraCoords, fn?: fun()|table|number|string) [client]
---@field trevor fun(duration?: number|string) [client]
---@field meth fun(duration?: number|string) [client]
---@field ecstacy fun(duration?: number|string) [client]
---@field alien fun(duration?: number|string) [client]
---@field crack fun(duration?: number|string) [client]
---@field coke fun(duration?: number|string) [client]

---@class KoraLibWorld
---@field getNearbyEntities fun(entityType: KoraWorldEntityType, coords: KoraCoords, radius: number, options?: KoraWorldQueryOptions): KoraWorldMatch[] [client/server]
---@field getClosestEntity fun(entityType: KoraWorldEntityType, coords: KoraCoords, options?: KoraWorldQueryOptions): integer|false, KoraCoords?, number? [client/server]
---@field getGroundCoords fun(coords: KoraCoords, options?: KoraWorldGroundOptions): KoraCoords|false, string? [client]
---@field getStreetNames fun(coords?: KoraCoords): string, string? [client]
---@field getZoneName fun(coords?: KoraCoords): string, string [client]
---@field getCardinalDirection fun(value?: number, options?: {entity?: boolean}): 'N'|'NW'|'W'|'SW'|'S'|'SE'|'E'|'NE' [client]
---@field getWaypointCoords fun(): KoraCoords|false, string? [client]
---@field isSpawnClear fun(coords: KoraCoords, radius: number, options?: KoraWorldQueryOptions): boolean [client/server]

---@class KoraLibZones
---@field box fun(opts: KoraZoneBoxOptions): KoraZoneHandle [client]
---@field sphere fun(opts: KoraZoneSphereOptions): KoraZoneHandle [client]
---@field circle fun(opts: KoraZoneCircleOptions): KoraZoneHandle [client]
---@field poly fun(opts: KoraZonePolyOptions): KoraZoneHandle [client]
---@field point fun(opts: KoraZonePointOptions): KoraZoneHandle [client]
---@field getInside fun(resource?: string): KoraZoneHandle[] [client]
---@field setDebug fun(id: integer|nil, enabled: boolean): boolean [client]
---@field generateSnippet fun(zoneType: 'box'|'sphere'|'poly', opts: KoraZoneCreatorOptions): string [client]
---@field startCreator fun(zoneType: 'box'|'sphere'|'poly', existingOpts?: KoraZoneCreatorOptions): promise|KoraZoneCreatorResult|nil [client]
---@field isCreatorActive fun(): boolean [client]
---@field edit fun(handle: KoraZoneHandle, opts?: KoraZoneOptions): KoraZoneHandle|nil, string? [client]

---@class KoraDrawingText3DOptions
---@field font? integer
---@field scale? number
---@field color? {r: integer, g: integer, b: integer, a: integer}
---@field maxDistance? number Meters from PlayerPedId(); beyond this, every native call is skipped.
---@field outline? boolean

---@alias KoraEntitiesType "ped" | "object" | "vehicle"
---@alias KoraEntitiesPreset "static"

---@alias KoraServerVehicleType "automobile" | "bike" | "boat" | "heli" | "plane" | "submarine" | "trailer" | "train"

---@alias KoraNotifyType "info" | "success" | "warning" | "error"
---@alias KoraNotifyPosition "top-left" | "top-center" | "top-right" | "bottom-left" | "bottom-center" | "bottom-right" | "center-left" | "center-right" | "top" | "bottom"

---@class KoraWaypointTeleportOptions : KoraTeleportOptions
---@field entity? number Entity to move. Defaults to the current vehicle when driving, otherwise the player ped.
---@field launchHeight? number Initial Z used while collision is loaded.
---@field collisionTimeout? integer Maximum milliseconds to wait for world collision.
---@field groundAttempts? integer Maximum ground probes.
---@field groundRetryDelay? integer Milliseconds between ground probes.

---@class KoraTextUIOptions
---@field key? string Short key/control label displayed beside the text.
---@field icon? string Lucide icon name.
---@field position? KoraTextUIPosition Defaults to `right-center`.
---@field iconColor? string CSS colour applied to the icon.
---@field iconAnimation? 'spin'|'spinPulse'|'spinReverse'|'pulse'|'beat'|'fade'|'beatFade'|'bounce'|'shake'
---@field alignIcon? 'top'|'center' Defaults to `center`.
---@field style? string|table<string, string|number> Scoped CSS declarations or properties applied to the prompt surface.

---@class KoraVisualsStaminaEffectOptions
---@field prefix string playDrugEffect prefix (`<prefix>In`/`<prefix>`/`<prefix>Out`).
---@field multiplier number Sprint multiplier applied for the duration of the effect.
---@field ticks integer Number of 1-second stamina ticks the effect runs for.
---@field restoreChance integer Chance out of 100, rolled each tick, to restore stamina.
---@field replayChance integer Chance, rolled each tick against replayScale, to replay the drug screen effect.
---@field replayScale? integer Denominator replayChance is rolled against. Default 100 -- coke uses 300, preserve exactly.
---@field replayExtraWait? {min: integer, max: integer} Extra Wait(math.random(min,max)) after a successful replay (coke only).
---@field perTickRagdoll? {chance: integer, minTime: integer, maxTime: integer} Chance out of 100, each tick, to ragdoll if running.
---@field finalRagdoll? {minTime: integer, maxTime: integer} Ragdoll unconditionally once the tick loop ends.

---@class KoraWorldQueryOptions
---@field models? (number|string)[] Restrict to these models. Strings are joaat-hashed. Ignored for "player".
---@field predicate? fun(entity: number, coords: table, distance: number): boolean Runs last, after the cheaper filters below.
---@field includeInvisible? boolean Include entities IsEntityVisible reports as hidden. Defaults to false.
---@field includeOwnPed? boolean Include the local player's own ped/player entry. Defaults to false.
---@field excludeEntities? number[] Entity handles to skip outright.
---@field radius? number getClosestEntity only -- search radius, meters. Defaults to Config.world.defaultRadius.

---@class KoraWorldNetworkEntityOptions
---@field entityType? "ped" | "vehicle" | "object" Required live entity type.
---@field maxDistance? number Maximum distance from the player's ped in metres.
---@field sameBucket? boolean Require the entity and player to share a routing bucket. Defaults to true.
---@field requireDriver? boolean Require the player's ped to occupy the vehicle's driver seat.

---@class KoraZoneEditOptions
---@field coords? any New center coordinates. Only supported by box and sphere zones.
---@field onEnter? fun(zone: table)|false New enter callback, or false to remove it.
---@field onExit? fun(zone: table)|false New exit callback, or false to remove it.

---@class KoraWorkspace: kora_lib
---@field shared KoraSharedRegistry
---@type KoraWorkspace
Kora = {}
