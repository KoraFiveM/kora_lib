# Converted from the communitybot legacy tests by kora-qa-panel/scripts/convert-legacy.mjs.
# The """ block under each Scenario is the original test text, verbatim. Review before applying.
Feature: kora_lib — Core & Libraries

  @kora_lib @checklist @checklist:kora_lib:progress-bar @cat:core-and-libraries
  Scenario: Progress bar with cancel
    """
    Checklist test: Perform a timed action (repair, treatment, ATM access); bar fills, can be cancelled, and animation plays.
    """
    When I run the command "/testprogressbar"
    Then a progress bar should run
    And I confirm: the progress bar fills and completes
    When I run the command "/testprogressbar"
    And I press the "X" key
    Then I confirm: the progress bar is cancelled
    And I confirm: the animation plays during the action

  @kora_lib @checklist @checklist:kora_lib:nui-menus-appshell @cat:core-and-libraries
  Scenario: NUI menus and AppShell apps
    """
    Checklist test: Open any app (e.g. /admin, /cards, bank); navigation, forms, tables, focus release on close all work.
    """
    When I run the command "/cards"
    And I manually: navigate the app, fill any forms and view any tables
    Then I confirm: navigation, forms and tables all work
    When I manually: close the app
    Then I confirm: focus is released on close and I can move and use controls normally

  @kora_lib @checklist @checklist:kora_lib:textui @cat:core-and-libraries @manual
  Scenario: Text UI prompts
    """
    Checklist test: Walk into a prompt zone (death timer, hints); text UI shows and hides correctly.
    """
    When I manually: walk into a prompt zone such as a hint zone
    Then I confirm: the text UI prompt shows while I am inside the zone
    When I manually: walk out of the prompt zone
    Then I confirm: the text UI prompt hides

  @kora_lib @checklist @checklist:kora_lib:keybinds @cat:core-and-libraries @manual
  Scenario: Rebindable keybinds
    """
    Checklist test: Check Settings > Key Bindings > FiveM lists Kora keybinds (e.g. openInv, hotbar) and rebinding works.
    """
    When I manually: open Settings > Key Bindings > FiveM
    Then I confirm: the Kora keybinds such as openInv and hotbar are listed
    When I manually: rebind one Kora keybind and press the new key in game
    Then I confirm: the rebound key triggers the action

  @kora_lib @checklist @checklist:kora_lib:interact-targets @cat:core-and-libraries
  Scenario: Interact zones and target options
    """
    Checklist test: Use ALT-aim target options on peds, vehicles, props and box zones; canInteract and job filters apply.
    """
    Given a "shopkeeper" ped is spawned in front of me
    And a "bench" prop is spawned in front of me
    And a "test_car" is spawned in front of me
    When I manually: hold ALT and aim at the ped, the vehicle, the prop and a box zone in turn
    Then I confirm: target options appear on each of them
    And I confirm: options with canInteract or job filters only show when the condition is met

  @kora_lib @checklist @checklist:kora_lib:radial-menu @cat:core-and-libraries
  Scenario: Radial menu (Z)
    """
    Checklist test: Press Z (ox_lib-radial): radial menu opens only when a resource has registered items; select and back work.
    """
    When I press the "Z" key
    Then I confirm: the radial menu opens only when a resource has registered items, otherwise nothing opens
    When I run the command "/testradial"
    And I manually: select a wedge
    Then I confirm: the selection works
    When I run the command "/testradial_nested"
    And I manually: open a submenu and select Back
    Then I confirm: Back returns to the previous menu

  @kora_lib @checklist @checklist:kora_lib:config-editor @cat:core-and-libraries @needs:admin
  Scenario: Config editor (/config)
    """
    Checklist test: As permitted staff run /config [resource] to open the config editor; edit and save a value and check it applies.
    """
    When I run the command "/config"
    Then the "kora_lib:config" app opens
    And I confirm: the config editor opens only for permitted staff; otherwise a no-permission message shows
    When I manually: edit a value and save it
    Then I confirm: the setting saves and applies live

  @kora_lib @checklist @checklist:kora_lib:zone-creator @cat:core-and-libraries @needs:admin
  Scenario: Zone creator (/kora_zonecreator)
    """
    Checklist test: With editor permission run /kora_zonecreator [box|sphere|poly]; place points, confirm output; TAB conflict with inventory is vetoed. Note: /kora_zonecreator was called /kora_zonecreator.
    """
    When I manually: run /kora_zonecreator box with editor permission
    And I manually: place the points and confirm
    Then I confirm: the zone output is shown
    When I press the "TAB" key
    Then I confirm: TAB does not open the inventory (the conflict is vetoed)
    When I manually: repeat with /kora_zonecreator sphere and /kora_zonecreator poly
    Then I confirm: each shape can be placed and confirmed

  @kora_lib @checklist @checklist:kora_lib:placement-editor @cat:core-and-libraries @needs:admin
  Scenario: Prop placement (/kora_place <model>)
    """
    Checklist test: Run /kora_place <model>: preview object, cycle with TAB, confirm RETURN, cancel X; permission denied otherwise. Note: /kora_place was called /kora_place.
    """
    When I manually: run /kora_place prop_bench_01a with editor permission
    Then I confirm: a preview object appears
    When I press the "TAB" key
    Then I confirm: the preview cycles
    When I press the "RETURN" key
    Then I confirm: the confirm summary shows
    When I manually: run /kora_place prop_bench_01a again and press X
    Then I confirm: placement is cancelled
    When I manually: run /kora_place prop_bench_01a as a player without permission
    Then I confirm: permission is denied

  @kora_lib @checklist @checklist:kora_lib:minigames @cat:core-and-libraries
  Scenario: Skill-check and hacking minigames
    """
    Checklist test: Start a job needing a minigame (e.g. recycle prep, /cctvhack): server-authorised puzzle shows; success/failure reported.
    """
    When I run the command "/cctvhack"
    Then I confirm: a server-authorised puzzle shows
    When I manually: complete or fail the puzzle
    Then I confirm: success or failure is reported

  @kora_lib @checklist @checklist:kora_lib:commands-help @cat:core-and-libraries
  Scenario: Chat command suggestions and permissions
    """
    Checklist test: Type / in chat: registered commands show suggestions; protected commands deny users without permission.
    """
    When I manually: type / in chat
    Then I confirm: registered commands show as suggestions
    When I run the command "/setjob"
    Then I should see a notification containing "You do not have permission for this command."

  @kora_lib @checklist @checklist:kora_lib:screenshot-module @cat:core-and-libraries @manual
  Scenario: Screenshot capture module
    """
    Checklist test: Resource requests a screenshot (e.g. card studio shutter); capture completes and is stored without error.
    """
    When I manually: trigger a screenshot request such as the card studio shutter
    Then I confirm: the capture completes and is stored without error
    When the F8 console should show no errors

  @kora_lib @checklist @checklist:kora_lib:freecam-camera @cat:core-and-libraries @needs:admin
  Scenario: Camera/freecam and raycast tools
    """
    Checklist test: Use entity picker/camera tools (admin Development > Inspect Entity): raycast identifies model names under the crosshair.
    """
    When I run the command "/entitypicker"
    And I manually: aim the crosshair at an object or vehicle
    Then I confirm: the raycast identifies the model name under the crosshair

  @kora_lib @checklist @checklist:kora_lib:ox-compat-ui @cat:core-and-libraries @manual
  Scenario: ox_lib compatible UI calls
    """
    Checklist test: Run a legacy ox_lib resource: lib.notify, progressCircle, inputDialog, contextMenu, alertDialog render through Kora.
    """
    When I manually: run a legacy ox_lib resource that calls lib.notify
    Then I confirm: the notification renders through Kora
    When I manually: trigger progressCircle, inputDialog, contextMenu and alertDialog
    Then I confirm: each of them renders through Kora and works
