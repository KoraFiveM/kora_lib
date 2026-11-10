# Converted from the communitybot legacy tests by kora-qa-panel/scripts/convert-legacy.mjs.
# The """ block under each Scenario is the original test text, verbatim. Review before applying.
Feature: kora_lib — game tests

  @kora_lib @legacy:lib-launcher @target:3
  Scenario: Launcher: HOME or F6 opens and closes it
    """
    1. Press HOME (or F6).
    2. Look at the list, then press the same key again.
    Expect: a launcher opens with sections such as Blips, Entities, Zones, NUI, Minigames and Networking; the second press closes it and your mouse and camera control come back.
    """
    When I press the "HOME" key
    Then I confirm: a launcher opens with sections such as Blips, Entities, Zones, NUI, Minigames and Networking
    When I press the "HOME" key
    Then I confirm: the launcher closes and my mouse and camera control come back

  @kora_lib @legacy:lib-keybind-listed @target:3 @manual
  Scenario: Keybind: playground key is rebindable
    """
    1. Open Settings > Key Bindings > FiveM.
    2. Find "Server test playground: open launcher".
    Expect: the entry exists with HOME as its key and F6 as the second key. Rebind it to another key and that key now opens the launcher.
    """
    When I manually: open Settings > Key Bindings > FiveM
    And I manually: find "Server test playground: open launcher"
    Then I confirm: the entry exists with HOME as its key and F6 as the second key
    When I manually: rebind it to another key and press that key
    Then I confirm: the new key opens the launcher

  @kora_lib @legacy:lib-notify-send @target:3 @checklist @checklist:kora_lib:notifications @cat:core-and-libraries
  Scenario: Notify: toast shows title, text and success style
    """
    1. Type /testnotify in chat.
    Expect: a toast appears top right titled "Test Notification" with the text "This is a test notification from kora_lib-playground." in the success style, and it goes away after about 4 seconds.
    Also checklist kora_lib:notifications (Notifications): Trigger any notify (e.g. admin /announce or buy at shop); toast shows with correct title/type and theme.
    """
    When I run the command "/testnotify"
    Then I should see a notification titled "Test Notification"
    And I should see a notification containing "This is a test notification from kora_lib-playground."
    And I should see a success notification
    And I confirm: the toast appears top right
    And I confirm: the toast goes away after about 4 seconds

  @kora_lib @legacy:lib-progress-run @target:3
  Scenario: Progress bar: fills and completes
    """
    1. Type /testprogressbar and wait.
    2. Open F8.
    Expect: a bar labelled "Testing progress bar..." fills over about 8 seconds, then disappears, and F8 shows "[kora_lib-playground] progressbar_start completed".
    """
    When I run the command "/testprogressbar"
    Then a progress bar labelled "Testing progress bar..." should run
    When I wait 8 seconds
    Then I confirm: the bar filled over about 8 seconds and then disappeared
    When the F8 console should show "[kora_lib-playground] progressbar_start completed"

  @kora_lib @legacy:lib-progress-controls @target:3
  Scenario: Progress bar: blocks move, combat and driving
    """
    1. Start /testprogressbar.
    2. While it runs try to walk, punch or aim, and (if in a car) drive.
    3. Wait for the end and try again.
    Expect: movement, combat and vehicle driving are blocked while the bar runs and work normally again as soon as it finishes.
    """
    When I run the command "/testprogressbar"
    And I manually: while the bar runs, try to walk, punch or aim, and drive if in a car
    Then I confirm: movement, combat and vehicle driving are blocked while the bar runs
    When I wait 8 seconds
    And I manually: try to walk, punch or aim, and drive if in a car again
    Then I confirm: movement, combat and vehicle driving work normally again

  @kora_lib @legacy:lib-progress-cancel-key @target:3
  Scenario: Progress bar: X or Escape cancels it
    """
    1. Start /testprogressbar.
    2. After 2 seconds press X (or Escape).
    3. Check F8.
    Expect: the bar closes early, you can move again, and F8 shows "[kora_lib-playground] progressbar_start cancelled".
    """
    When I run the command "/testprogressbar"
    And I wait 2 seconds
    And I press the "X" key
    Then I confirm: the bar closes early and I can move again
    When the F8 console should show "[kora_lib-playground] progressbar_start cancelled"

  @kora_lib @legacy:lib-menu-select @target:3
  Scenario: Menu: pick an option
    """
    1. Type /testmenu.
    2. Click "Option Two".
    Expect: a menu titled "Test Menu" lists "Option One" and "Option Two" with their descriptions. After the click it closes, the mouse cursor goes away, and F8 shows "[kora_lib-playground] menu selected: two".
    """
    When I run the command "/testmenu"
    Then a menu titled "Test Menu" opens
    And I confirm: the menu lists "Option One" and "Option Two" with their descriptions
    When I manually: click "Option Two"
    Then I confirm: the menu closes and the mouse cursor goes away
    When the F8 console should show "[kora_lib-playground] menu selected: two"

  @kora_lib @legacy:lib-menu-cancel @target:3
  Scenario: Menu: Escape cancels and frees controls
    """
    1. Type /testmenu.
    2. Press Escape.
    Expect: the menu closes, F8 shows "[kora_lib-playground] menu cancelled", and you can look around and move again with no stuck cursor.
    """
    When I run the command "/testmenu"
    And I manually: press Escape
    Then I confirm: the menu closes
    When the F8 console should show "[kora_lib-playground] menu cancelled"
    Then I confirm: I can look around and move again with no stuck cursor

  @kora_lib @legacy:lib-menu-nested @target:3
  Scenario: Menu: nested submenus and Back
    """
    1. Type /testnested.
    2. Open Vehicle, then Doors, then pick Lock.
    3. Run it again and use Back after opening Vehicle.
    Expect: Doors is two levels deep and Back returns one level. Picking Lock prints "[kora_lib-playground] selected 'lock' via path: vehicle > doors > lock".
    """
    When I run the command "/testnested"
    And I manually: open Vehicle, then Doors, then pick Lock
    Then I confirm: Doors is two levels deep
    When the F8 console should show "[kora_lib-playground] selected 'lock' via path: vehicle > doors > lock"
    And I run the command "/testnested"
    And I manually: open Vehicle, then use Back
    Then I confirm: Back returns one level

  @kora_lib @legacy:lib-menu-path @target:3
  Scenario: Menu: same id in two branches gives different paths
    """
    1. Type /testnested, open Vehicle and pick Remove.
    2. Run it again, open Player and pick Remove.
    Expect: F8 shows "selected 'remove' via path: vehicle > remove" the first time and "selected 'remove' via path: player > remove" the second.
    """
    When I run the command "/testnested"
    And I manually: open Vehicle and pick Remove
    And the F8 console should show "selected 'remove' via path: vehicle > remove"
    And I run the command "/testnested"
    And I manually: open Player and pick Remove
    And the F8 console should show "selected 'remove' via path: player > remove"

  @kora_lib @legacy:lib-radial-basic @target:3
  Scenario: Radial: pick a wedge
    """
    1. Type /testradial.
    2. Click the Phone wedge.
    Expect: a ring with Inventory, Vehicle, Phone and Settings appears centred on screen. After the click it closes and F8 shows "[kora_lib-playground] radial menu selected: phone".
    """
    When I run the command "/testradial"
    Then I confirm: a ring with Inventory, Vehicle, Phone and Settings appears centred on screen
    When I manually: click the Phone wedge
    Then I confirm: the ring closes
    When the F8 console should show "[kora_lib-playground] radial menu selected: phone"

  @kora_lib @legacy:lib-radial-cancel @target:3
  Scenario: Radial: Escape cancels
    """
    1. Type /testradial.
    2. Press Escape.
    Expect: the ring closes, F8 shows "[kora_lib-playground] radial menu cancelled" and controls come back.
    """
    When I run the command "/testradial"
    And I manually: press Escape
    Then I confirm: the ring closes
    When the F8 console should show "[kora_lib-playground] radial menu cancelled"
    Then I confirm: controls come back

  @kora_lib @legacy:lib-radial-nested @target:3
  Scenario: Radial: submenus and Back
    """
    1. Type /testradial_nested.
    2. Open Vehicle, then Windows, then pick Roll up.
    3. Run it again and use the centre Back control.
    Expect: each submenu replaces the ring and the centre Back goes up one level. Picking Roll up prints "nested radial menu selected 'window_up' via path: vehicle > windows > window_up".
    """
    When I run the command "/testradial_nested"
    And I manually: open Vehicle, then Windows, then pick Roll up
    Then I confirm: each submenu replaced the ring
    When the F8 console should show "nested radial menu selected 'window_up' via path: vehicle > windows > window_up"
    And I run the command "/testradial_nested"
    And I manually: open a submenu and use the centre Back control
    Then I confirm: the centre Back goes up one level

  @kora_lib @legacy:lib-radial-paged @target:3
  Scenario: Radial: More wedge pages and disabled option
    """
    1. Type /testradial_paged.
    2. Click the More wedge until you pass the last page.
    3. Try to click Option 8.
    Expect: seven options show per page plus a More wedge. After the last page More wraps back to the first page. Option 8 is shown disabled and cannot be selected.
    """
    When I run the command "/testradial_paged"
    Then I confirm: seven options show per page plus a More wedge
    When I manually: click the More wedge until I pass the last page
    Then I confirm: after the last page More wraps back to the first page
    When I manually: try to click Option 8
    Then I confirm: Option 8 is shown disabled and cannot be selected

  @kora_lib @legacy:lib-input-fields @target:3
  Scenario: Input dialog: every field type
    """
    1. Type /testinput.
    Expect: a dialog titled "Every field type" shows nine fields: Name (required), Text (optional), PIN, Notes (textarea), Amount (1-10), two Range sliders, a Checkbox that starts ticked, and a Select that starts on Red.
    """
    When I run the command "/testinput"
    Then I confirm: a dialog titled "Every field type" shows nine fields
    And I confirm: the fields are Name (required), Text (optional), PIN, Notes (textarea), Amount (1-10), two Range sliders, a Checkbox that starts ticked, and a Select that starts on Red

  @kora_lib @legacy:lib-input-required @target:3
  Scenario: Input dialog: required Name gates Confirm
    """
    1. Type /testinput.
    2. Leave Name empty and look at Confirm.
    3. Type a name.
    Expect: Confirm is disabled while Name is empty and shows an error; it becomes enabled once Name has text (and every other field is valid).
    """
    When I run the command "/testinput"
    And I manually: leave Name empty and look at Confirm
    Then I confirm: Confirm is disabled and shows an error while Name is empty
    When I manually: type a name in Name
    Then I confirm: Confirm becomes enabled once Name has text and every other field is valid

  @kora_lib @legacy:lib-input-pin @target:3
  Scenario: Input dialog: PIN must be 4 digits
    """
    1. Type /testinput and fill Name.
    2. Type 123 in PIN, then 1234.
    Expect: with 3 digits PIN shows an error and Confirm is disabled; with exactly 4 digits the error clears and Confirm is enabled.
    """
    When I run the command "/testinput"
    And I manually: fill Name
    And I manually: type 123 in PIN
    Then I confirm: PIN shows an error and Confirm is disabled
    When I manually: replace the PIN with 1234
    Then I confirm: the PIN error clears and Confirm is enabled

  @kora_lib @legacy:lib-input-confirm @target:3
  Scenario: Input dialog: Confirm returns the values
    """
    1. Type /testinput, fill Name and PIN 1234, change Select to Blue.
    2. Click Confirm and open F8.
    Expect: the dialog closes and F8 shows "[kora_lib-playground] input values:" followed by the entered values (name, plain, pin, notes, amount, volume, fine, agree, colour) with colour set to blue.
    """
    When I run the command "/testinput"
    And I manually: fill Name and PIN 1234, and change Select to Blue
    And I manually: click Confirm
    Then I confirm: the dialog closes
    When the F8 console should show "[kora_lib-playground] input values:"
    Then I confirm: F8 lists name, plain, pin, notes, amount, volume, fine, agree and colour with colour set to blue

  @kora_lib @legacy:lib-input-cancel @target:3
  Scenario: Input dialog: Escape cancels
    """
    1. Type /testinput.
    2. Press Escape.
    Expect: the dialog closes without sending anything and F8 shows "[kora_lib-playground] input cancelled".
    """
    When I run the command "/testinput"
    And I manually: press Escape
    Then I confirm: the dialog closes without sending anything
    When the F8 console should show "[kora_lib-playground] input cancelled"

  @kora_lib @legacy:lib-alert-confirm @target:3
  Scenario: Alert: confirm and cancel buttons
    """
    1. Type /testalert.
    2. Click Delete.
    3. Run it again and click Keep it.
    Expect: an alert titled "Delete everything?" has buttons "Delete" and "Keep it". F8 shows "alert answered: confirmed=true" for Delete and "confirmed=false" for Keep it.
    """
    When I run the command "/testalert"
    Then I confirm: an alert titled "Delete everything?" has buttons "Delete" and "Keep it"
    When I manually: click Delete
    And the F8 console should show "alert answered: confirmed=true"
    And I run the command "/testalert"
    And I manually: click Keep it
    And the F8 console should show "confirmed=false"

  @kora_lib @legacy:lib-alert-escape @target:3
  Scenario: Alert: Escape and backdrop count as Cancel
    """
    1. Type /testalert and press Escape.
    2. Run it again and click outside the box.
    Expect: both times the alert closes and F8 shows "alert answered: confirmed=false".
    """
    When I run the command "/testalert"
    And I press the "Escape" key
    Then I confirm: the alert closes
    When the F8 console should show "alert answered: confirmed=false"
    And I run the command "/testalert"
    And I manually: click outside the alert box
    Then I confirm: the alert closes
    When the F8 console should show "alert answered: confirmed=false"

  @kora_lib @legacy:lib-alert-ack @target:3
  Scenario: Alert: acknowledge-only cannot be dismissed
    """
    1. Type /testalert_ack.
    2. Press Escape and click outside the box.
    3. Click Understood.
    Expect: the alert "Acknowledge" has only the "Understood" button; Escape and the backdrop do nothing. The button closes it and F8 shows "acknowledge-only alert answered: confirmed=true".
    """
    When I run the command "/testalert_ack"
    Then I confirm: the alert "Acknowledge" has only the "Understood" button
    When I press the "Escape" key
    And I manually: click outside the alert box
    Then I confirm: Escape and the backdrop do nothing and the alert stays open
    When I manually: click Understood
    Then I confirm: the alert closes
    When the F8 console should show "acknowledge-only alert answered: confirmed=true"

  @kora_lib @legacy:lib-clipboard @target:3
  Scenario: Clipboard: copy text
    """
    1. Type /testclipboard.
    2. Open chat and paste with Ctrl+V.
    Expect: F8 shows "[kora_lib-playground] copied text to clipboard" and the pasted text is "Hello from kora_lib-playground!".
    """
    When I run the command "/testclipboard"
    And the F8 console should show "[kora_lib-playground] copied text to clipboard"
    And I manually: open chat and paste with Ctrl+V
    Then I confirm: the pasted text is "Hello from kora_lib-playground!"

  @kora_lib @legacy:lib-interact-open @target:3
  Scenario: Interact selector: Up/Down and E
    """
    1. Type /testinteract.
    2. Press Up and Down, then E (or Enter) on Inspect vehicle.
    3. Move the mouse.
    Expect: a selector lists "Inspect vehicle" and "Open storage"; "Unavailable row" cannot be selected. There is no mouse cursor and the camera still turns. Selecting prints "[kora_lib-playground] interact selected: Inspect vehicle".
    """
    When I run the command "/testinteract"
    Then I confirm: a selector lists "Inspect vehicle" and "Open storage"
    When I press the "Up" key
    And I press the "Down" key
    And I manually: select Inspect vehicle with E or Enter
    Then I confirm: "Unavailable row" cannot be selected
    When the F8 console should show "[kora_lib-playground] interact selected: Inspect vehicle"
    And I manually: move the mouse
    Then I confirm: there is no mouse cursor and the camera still turns

  @kora_lib @legacy:lib-interact-cancel @target:3
  Scenario: Interact selector: Escape closes it
    """
    1. Type /testinteract.
    2. Press Escape.
    Expect: the selector closes and nothing is printed as selected.
    """
    When I run the command "/testinteract"
    And I press the "Escape" key
    Then I confirm: the selector closes
    And I confirm: nothing is printed as selected in F8

  @kora_lib @legacy:lib-interact-zone @target:3
  Scenario: Interact selector: opens when entering a zone
    """
    1. Type /testinteract_zone.
    2. Walk more than 3 m away and back in.
    3. Select Use test zone.
    Expect: a debug circle is drawn. Walking back in opens a selector with "Use test zone" and "Check zone details"; selecting prints "[kora_lib-playground] interact zone selected: Use test zone".
    """
    When I run the command "/testinteract_zone"
    Then I confirm: a debug circle is drawn
    When I manually: walk more than 3 m away and back in
    Then I confirm: a selector opens with "Use test zone" and "Check zone details"
    When I manually: select Use test zone
    And the F8 console should show "[kora_lib-playground] interact zone selected: Use test zone"

  @kora_lib @legacy:lib-interact-clear @target:3
  Scenario: Interact selector: clear test zone
    """
    1. Create the zone with /testinteract_zone.
    2. Type /testinteract_clear, then walk out and in.
    3. Run /testinteract_clear again.
    Expect: the circle is removed, the selector closes and no longer opens on entry; F8 shows "interact test zone removed" first and "no interact test zone was active" the second time.
    """
    When I run the command "/testinteract_zone"
    And I run the command "/testinteract_clear"
    And I manually: walk out of the zone and back in
    Then I confirm: the circle is removed, the selector closes and no longer opens on entry
    When the F8 console should show "interact test zone removed"
    And I run the command "/testinteract_clear"
    And the F8 console should show "no interact test zone was active"

  @kora_lib @legacy:lib-zone-box @target:3
  Scenario: Zone: box enter and exit
    """
    1. Type /testzone.
    2. Walk out of the drawn box and back in. Watch F8.
    Expect: a 4x4x3 box outline is drawn at your feet, rotated to your heading. F8 shows "[kora_lib-playground] ENTERED box zone <id>" when you enter and "EXITED box zone <id>" when you leave.
    """
    When I run the command "/testzone"
    Then I confirm: a 4x4x3 box outline is drawn at my feet, rotated to my heading
    When I manually: walk out of the drawn box and back in while watching F8
    And the F8 console should show "ENTERED box zone"
    And the F8 console should show "EXITED box zone"

  @kora_lib @legacy:lib-zone-sphere @target:3
  Scenario: Zone: sphere enter and exit
    """
    1. Type /testzone_sphere.
    2. Walk out about 4 m and back in.
    Expect: a sphere of radius 3 is drawn; F8 prints ENTERED sphere zone on entry and EXITED sphere zone on exit.
    """
    When I run the command "/testzone_sphere"
    Then I confirm: a sphere of radius 3 is drawn
    When I manually: walk out about 4 m and back in
    And the F8 console should show "ENTERED sphere zone"
    And the F8 console should show "EXITED sphere zone"

  @kora_lib @legacy:lib-zone-poly @target:3
  Scenario: Zone: polygon follows its real edges
    """
    1. Type /testzone_poly.
    2. Walk to a corner of the five-sided outline and cross an edge near it.
    Expect: a five-sided footprint is drawn. Enter and exit lines print exactly where you cross the drawn edges, not a bigger rectangle around it.
    """
    When I run the command "/testzone_poly"
    Then I confirm: a five-sided footprint is drawn
    When I manually: walk to a corner of the five-sided outline and cross an edge near it
    Then I confirm: enter and exit lines print exactly where I cross the drawn edges, not a bigger rectangle around it

  @kora_lib @legacy:lib-zone-inside @target:3
  Scenario: Zone: /testzone_inside lists current zones
    """
    1. Stand outside zones and run /testzone_inside.
    2. Create /testzone and /testzone_sphere at the same spot and run it again.
    Expect: first F8 shows "you are not inside any zone right now"; then it lists each zone like "inside box zone <id> (owned by kora_lib-playground)".
    """
    When I manually: stand outside any zones
    And I run the command "/testzone_inside"
    And the F8 console should show "you are not inside any zone right now"
    And I run the command "/testzone"
    And I run the command "/testzone_sphere"
    And I run the command "/testzone_inside"
    And the F8 console should show "(owned by kora_lib-playground)"
    Then I confirm: F8 lists each zone like "inside box zone <id> (owned by kora_lib-playground)"

  @kora_lib @legacy:lib-zone-remove @target:3
  Scenario: Zone: remove the last zone
    """
    1. Create two zones.
    2. Run /testzone_remove twice, then once more.
    Expect: each run removes the newest zone and F8 shows "removed <shape> zone <id> (n still active)" and its outline disappears; with none left F8 says "no zones to remove".
    """
    When I run the command "/testzone"
    And I run the command "/testzone_sphere"
    And I run the command "/testzone_remove"
    Then I confirm: the newest zone's outline disappears
    When the F8 console should show "still active)"
    And I run the command "/testzone_remove"
    Then I confirm: the next newest zone's outline disappears
    When the F8 console should show "still active)"
    And I run the command "/testzone_remove"
    And the F8 console should show "no zones to remove"

  @kora_lib @legacy:lib-zone-clear @target:3
  Scenario: Zone: clear all zones
    """
    1. Create three zones.
    2. Run /testzone_clear, then again.
    Expect: all outlines disappear and F8 shows "cleared 3 zone(s)"; the second run shows "no zones to clear".
    """
    When I run the command "/testzone"
    And I run the command "/testzone_sphere"
    And I run the command "/testzone_poly"
    And I run the command "/testzone_clear"
    Then I confirm: all outlines disappear
    When the F8 console should show "cleared 3 zone(s)"
    And I run the command "/testzone_clear"
    And the F8 console should show "no zones to clear"

  @kora_lib @legacy:lib-zone-debug @target:3 @checklist @checklist:kora_lib:zone-debug @cat:core-and-libraries
  Scenario: Zone: /kora_zonedebug toggles outlines
    """
    1. Create a zone with /testzone.
    2. Run /kora_zonedebug off, then /kora_zonedebug on, then /kora_zonedebug with no argument, then /kora_zonedebug maybe.
    Expect: off hides the outline and F8 shows "zone debug drawing disabled for every registered zone."; on shows it again; no argument flips the state; "maybe" prints "unrecognised argument 'maybe'".
    Note: /kora_zonedebug was called /kora_zonedebug.
    Also checklist kora_lib:zone-debug (Zone debug (/kora_zonedebug)): Run /kora_zonedebug to draw zone outlines in the world. Note: /kora_zonedebug was called /kora_zonedebug.
    """
    When I run the command "/testzone"
    And I run the command "/kora_zonedebug off"
    Then I confirm: the outline is hidden
    When the F8 console should show "zone debug drawing disabled for every registered zone."
    And I run the command "/kora_zonedebug on"
    Then I confirm: the outline is shown again
    When I run the command "/kora_zonedebug"
    Then I confirm: the outline state is flipped
    When I run the command "/kora_zonedebug maybe"
    And the F8 console should show "unrecognised argument 'maybe'"

  @kora_lib @legacy:lib-zonecreate-pick @target:3
  Scenario: Zone creator: shape picker
    """
    1. Type /testzone_create.
    2. Look at the dialog, then press Escape.
    Expect: a dialog "In-world zone creator" has a required Zone shape select with Box, Sphere and Poly (Box is the default). Escape closes it and F8 shows "zone creator cancelled at the shape picker".
    """
    When I run the command "/testzone_create"
    Then I confirm: a dialog "In-world zone creator" shows a required Zone shape select with Box, Sphere and Poly, and Box is the default
    When I press the "Escape" key
    Then I confirm: the dialog closes
    When the F8 console should show "zone creator cancelled at the shape picker"

  @kora_lib @legacy:lib-zonecreate-box @target:3
  Scenario: Zone creator: place a box and confirm
    """
    1. Run /testzone_create and pick Box.
    2. Aim at the ground and press E, scroll to change size, press Tab to switch parameter.
    3. Press Enter.
    Expect: the camera flies freely, a preview box follows your aim, and Enter opens a summary with a Lua snippet and a copy button. F8 shows "box zone definition captured; no live zone was registered" and no zone exists afterwards.
    """
    When I run the command "/testzone_create"
    And I manually: pick Box in the shape picker
    And I manually: aim at the ground and press E, scroll to change size, press Tab to switch parameter
    Then I confirm: the camera flies freely and a preview box follows my aim
    When I press the "Enter" key
    Then I confirm: a summary opens with a Lua snippet and a copy button
    When the F8 console should show "box zone definition captured; no live zone was registered"
    Then I confirm: no zone exists afterwards

  @kora_lib @legacy:lib-zonecreate-cancel @target:3
  Scenario: Zone creator: X cancels
    """
    1. Run /testzone_create, pick Sphere and press E.
    2. Press X.
    Expect: the creator ends, the camera blends back to normal play, controls return, and F8 shows "zone creator cancelled, or failed to start".
    """
    When I run the command "/testzone_create"
    And I manually: pick Sphere and press E
    And I press the "X" key
    Then I confirm: the creator ends, the camera blends back to normal play and controls return
    When the F8 console should show "zone creator cancelled, or failed to start"

  @kora_lib @legacy:lib-zonecreate-poly @target:3
  Scenario: Zone creator: poly points and Backspace
    """
    1. Run /testzone_create and pick Poly.
    2. Press E at three or more spots.
    3. Press Backspace once, then Enter.
    Expect: each E adds a point, Backspace removes the last point, and Enter confirms once there are at least 3 points, showing a snippet with the remaining points.
    """
    When I run the command "/testzone_create"
    And I manually: pick Poly in the shape picker
    And I manually: press E at three or more spots
    Then I confirm: each E adds a point
    When I press the "Backspace" key
    Then I confirm: the last point is removed
    When I press the "Enter" key
    Then I confirm: the creator confirms with at least 3 points and shows a snippet with the remaining points

  @kora_lib @legacy:lib-zonecreate-cmd @target:3 @needs:admin
  Scenario: Zone creator: /kora_zonecreator command
    """
    1. As an editor (ACE kora_lib.editor) run /kora_zonecreator sphere.
    2. Run /kora_zonecreator foo.
    3. Without the ACE run /kora_zonecreator.
    Expect: sphere starts the creator. "foo" shows an error toast "Usage: /kora_zonecreator [box|sphere|poly]". Without access an error toast says "You do not have access to the developer editors."
    Note: /kora_zonecreator was called /kora_zonecreator.
    """
    When I manually: as an editor (ACE kora_lib.editor) run /kora_zonecreator sphere
    Then I confirm: the zone creator starts
    When I manually: run /kora_zonecreator foo
    Then I should see an error notification
    And I should see a notification containing "Usage: /kora_zonecreator [box|sphere|poly]"
    When I manually: without the ACE run /kora_zonecreator
    Then I should see a notification containing "You do not have access to the developer editors."

  @kora_lib @legacy:lib-place-start @target:3 @needs:admin @manual
  Scenario: Placement: /kora_place preview and controls
    """
    1. As an editor run /kora_place prop_bin_08.
    2. Fly with mouse and WASD, move with arrow keys and Page Up / Page Down, press Tab and [ or ] to rotate.
    Expect: a see-through bin preview appears on the surface under your crosshair and moves/rotates as you press the keys. Nothing solid is created for other players.
    Note: /kora_place was called /kora_place.
    """
    When I manually: as an editor run /kora_place prop_bin_08
    Then I confirm: a see-through bin preview appears on the surface under my crosshair
    When I manually: fly with mouse and WASD, move with arrow keys and Page Up / Page Down, press Tab and [ or ] to rotate
    Then I confirm: the preview moves and rotates as I press the keys
    And I confirm: nothing solid is created for other players

  @kora_lib @legacy:lib-place-confirm @target:3
  Scenario: Placement: Enter shows summary, X cancels
    """
    1. Run /kora_place prop_bin_08 and press Enter.
    2. Close the summary, run it again and press X.
    Expect: Enter shows a summary with the model, coords, heading and rotation and a Lua snippet; the preview is deleted afterwards. X cancels with no summary and the preview is deleted.
    Note: /kora_place was called /kora_place.
    """
    When I run the command "/kora_place prop_bin_08"
    And I press the "Enter" key
    Then I confirm: a summary shows the model, coords, heading and rotation and a Lua snippet
    And I confirm: the preview prop is deleted afterwards
    When I manually: close the summary
    And I run the command "/kora_place prop_bin_08"
    And I press the "X" key
    Then I confirm: placement is cancelled with no summary shown
    And I confirm: the preview prop is deleted

  @kora_lib @legacy:lib-place-usage @target:3
  Scenario: Placement: usage message
    """
    1. Run /kora_place with no model.
    Expect: an error toast titled "kora_lib editor" says "Usage: /kora_place <model>".
    Note: /kora_place was called /kora_place.
    """
    When I run the command "/kora_place"
    Then I should see a notification containing "Usage: /kora_place <model>"
    And I should see an error notification
    And I should see a notification titled "kora_lib editor"

  @kora_lib @legacy:lib-blip-create @target:3
  Scenario: Blip: create with route and detail panel
    """
    1. Type /testblip.
    2. Open the pause map, find "Test Blip" in the legend and hover it on the map.
    Expect: a blip with a route line exists at your position and F8 shows "[kora_lib-playground] created blip". Hovering it on the map shows a panel titled "Blip detail test" with "Purpose: Pause-map panel preview".
    """
    When I run the command "/testblip"
    And I manually: open the pause map, find "Test Blip" in the legend and hover it on the map
    Then I confirm: a blip with a route line exists at my position
    When the F8 console should show "[kora_lib-playground] created blip"
    Then I confirm: hovering the blip shows a panel titled "Blip detail test" with "Purpose: Pause-map panel preview"

  @kora_lib @legacy:lib-blip-replace @target:3
  Scenario: Blip: creating again replaces the old one
    """
    1. Type /testblip, move away and type /testblip again.
    2. Check the map.
    Expect: only one "Test Blip" exists, at the new position.
    """
    When I run the command "/testblip"
    And I manually: move away from my position
    And I run the command "/testblip"
    And I manually: open the pause map
    Then I confirm: only one "Test Blip" exists, at the new position

  @kora_lib @legacy:lib-blip-remove @target:3
  Scenario: Blip: remove
    """
    1. Create a blip, then run /testblip_remove twice.
    Expect: the blip and route disappear and F8 shows "removed blip"; the second run shows "no blip to remove -- run /testblip first".
    """
    When I run the command "/testblip"
    And I run the command "/testblip_remove"
    Then I confirm: the blip and route disappear
    When the F8 console should show "removed blip"
    And I run the command "/testblip_remove"
    And the F8 console should show "no blip to remove -- run /testblip first"

  @kora_lib @legacy:lib-blip-settings @target:3 @checklist @checklist:kora_lib:blips-command @cat:core-and-libraries
  Scenario: Blips: /blips settings screen
    """
    1. Type /blips.
    2. Hide a category, then look at the map.
    3. Close with X or Escape.
    Expect: a settings screen lists the blip categories with their blips; hiding a category hides those blips at once on your map and showing it brings them back. Typing /blips while it is open closes it.
    Also checklist kora_lib:blips-command (Blip category settings (/blips)): Run /blips to open the blip settings panel, toggle categories and see map blips hide/show; X or Escape closes.
    """
    When I run the command "/blips"
    Then the "kora_lib:blips" app opens
    And I confirm: a settings screen lists the blip categories with their blips
    When I manually: hide a category and look at the map
    Then I confirm: the blips of that category are hidden at once on my map
    When I manually: show the category again
    Then I confirm: the blips come back
    When I manually: close the screen with X or Escape
    And I run the command "/blips"
    And I run the command "/blips"
    Then I confirm: typing /blips while the screen is open closes it

  @kora_lib @legacy:lib-entity-create @target:3
  Scenario: Entity: spawn and replace a prop
    """
    1. Type /testentity.
    2. Move and type /testentity again.
    Expect: a beach parasol appears at your feet and F8 shows "[kora_lib-playground] created entity"; the second run leaves only one parasol.
    """
    When I run the command "/testentity"
    Then I confirm: a beach parasol appears at my feet
    When the F8 console should show "[kora_lib-playground] created entity"
    And I manually: move a few metres away
    And I run the command "/testentity"
    Then I confirm: only one parasol exists

  @kora_lib @legacy:lib-entity-remove @target:3
  Scenario: Entity: remove the prop
    """
    1. Run /testentity_remove after creating one.
    2. Run it again.
    Expect: the parasol disappears with F8 "removed entity"; the second run shows "no entity to remove -- run /testentity first".
    """
    When I run the command "/testentity"
    And I run the command "/testentity_remove"
    Then I confirm: the parasol disappears
    When the F8 console should show "removed entity"
    And I run the command "/testentity_remove"
    And the F8 console should show "no entity to remove -- run /testentity first"

  @kora_lib @legacy:lib-cache @target:3
  Scenario: Cache: built-ins and change listener
    """
    1. Type /testcache twice.
    2. Check F8, and note your server id.
    Expect: F8 prints ped, vehicle, seat, weapon, playerId and serverId (serverId equals your id) and, on the second run, exactly one "cache 'playground:test' changed" line with old and new values, not duplicates.
    """
    When I run the command "/id"
    And I run the command "/testcache"
    And I run the command "/testcache"
    Then I confirm: F8 prints ped, vehicle, seat, weapon, playerId and serverId
    And I confirm: serverId equals my server id
    And I confirm: on the second run F8 shows exactly one "cache 'playground:test' changed" line with old and new values, not duplicates

  @kora_lib @legacy:lib-raycast @target:3
  Scenario: Raycast: from camera
    """
    1. Aim at a nearby wall and type /testraycast.
    2. Aim at the open sky and type it again.
    Expect: the first shows "[kora_lib-playground] raycast hit entity <n> at x, y, z" with coordinates on what you aimed at; the second shows "raycast: no hit within 10m".
    """
    When I manually: aim at a nearby wall
    And I run the command "/testraycast"
    And the F8 console should show "[kora_lib-playground] raycast hit entity"
    Then I confirm: the F8 coordinates are on what I aimed at
    When I manually: aim at the open sky
    And I run the command "/testraycast"
    And the F8 console should show "raycast: no hit within 10m"

  @kora_lib @legacy:lib-mg-lockpick @target:3
  Scenario: Minigame: lockpick
    """
    1. Type /testminigame_lockpick.
    2. Press Space when the indicator is in the highlighted zone, for each pin.
    Expect: a lockpick overlay appears; each good press locks a pin and moving on until all are done. F8 shows "[kora_lib-playground] lockpick succeeded after 1 attempt(s)".
    """
    When I run the command "/testminigame_lockpick"
    Then I confirm: a lockpick overlay appears
    When I manually: press Space when the indicator is in the highlighted zone, for each pin
    Then I confirm: each good press locks a pin and moves on until all are done
    When the F8 console should show "[kora_lib-playground] lockpick succeeded after 1 attempt(s)"

  @kora_lib @legacy:lib-mg-timeout @target:3
  Scenario: Minigame: timeout fails and reshuffles
    """
    1. Type /testminigame_lockpick.
    2. Press nothing until the time runs out.
    Expect: the round counts as a failed attempt and a new, different puzzle appears in the same overlay while attempts remain; after the last attempt F8 shows "lockpick failed after 3 attempt(s)".
    """
    When I run the command "/testminigame_lockpick"
    And I manually: press nothing until the time runs out
    Then I confirm: the round counts as a failed attempt
    And I confirm: a new, different puzzle appears in the same overlay while attempts remain
    When I manually: keep pressing nothing until the last attempt ends
    And the F8 console should show "lockpick failed after 3 attempt(s)"

  @kora_lib @legacy:lib-mg-cancel @target:3
  Scenario: Minigame: Escape cancels and can restart
    """
    1. Type /testminigame_lockpick and press Esc.
    2. Straight away type /testminigame_lockpick again.
    Expect: the overlay closes (F8 may print a lockpick failed line); the second start works immediately with no "already in progress" error.
    """
    When I run the command "/testminigame_lockpick"
    And I press the "Escape" key
    Then I confirm: the overlay closes (F8 may print a lockpick failed line)
    When I run the command "/testminigame_lockpick"
    Then I confirm: the second start works immediately with no "already in progress" error

  @kora_lib @legacy:lib-mg-skillbar @target:3
  Scenario: Minigame: skillbar
    """
    1. Type /testminigame_skillbar.
    2. Press Space when the moving indicator is inside the zone.
    Expect: in-zone press succeeds (F8 "skillbar succeeded after 1 attempt(s)"); a press outside the zone fails the attempt.
    """
    When I run the command "/testminigame_skillbar"
    And I manually: press Space when the moving indicator is inside the zone
    Then I confirm: the in-zone press succeeds
    When the F8 console should show "skillbar succeeded after 1 attempt(s)"
    And I run the command "/testminigame_skillbar"
    And I manually: press Space when the indicator is outside the zone
    Then I confirm: the press outside the zone fails the attempt

  @kora_lib @legacy:lib-mg-circuit @target:3
  Scenario: Minigame: circuit
    """
    1. Type /testminigame_circuit.
    2. Click an input, then the output with the same colour, for every pair.
    Expect: matching pairs connect; connecting every pair ends the game and F8 shows "circuit succeeded after 1 attempt(s)".
    """
    When I run the command "/testminigame_circuit"
    And I manually: click an input, then the output with the same colour, for every pair
    Then I confirm: matching pairs connect
    And I confirm: connecting every pair ends the game
    When the F8 console should show "circuit succeeded after 1 attempt(s)"

  @kora_lib @legacy:lib-mg-mash @target:3
  Scenario: Minigame: mash key
    """
    1. Type /testminigame_mash.
    2. Press Space repeatedly.
    Expect: a counter climbs as "n / required"; reaching the required presses before the time ends succeeds (F8 "mash succeeded"), and not reaching it fails.
    """
    When I run the command "/testminigame_mash"
    And I manually: press Space repeatedly
    Then I confirm: a counter climbs as "n / required"
    And I confirm: reaching the required presses before the time ends succeeds
    When the F8 console should show "mash succeeded"
    And I run the command "/testminigame_mash"
    And I manually: press Space fewer times than required until time runs out
    Then I confirm: not reaching the required presses fails

  @kora_lib @legacy:lib-net-callback @target:3 @needs:admin
  Scenario: Callback: client to server round trip
    """
    1. Type /testcallback.
    2. Check F8 and the server console.
    Expect: F8 shows "[kora_lib-playground] callback resolved: pong: hello from client" and the server console shows "callback 'playground:ping' called by <your id> with: hello from client".
    """
    When I run the command "/testcallback"
    And the F8 console should show "[kora_lib-playground] callback resolved: pong: hello from client"
    Then the server console should show "callback 'playground:ping' called by"
    And I confirm: the server console line ends with my server id and "with: hello from client"

  @kora_lib @legacy:lib-net-event @target:3 @needs:admin
  Scenario: Event: secure event and push ack
    """
    1. Type /testevent.
    2. Check F8 and the server console.
    Expect: F8 shows "event sent, waiting for ack..." then "event ack received: server got your event"; the server console shows "event 'playground:event' received from <your id>: hello from client".
    """
    When I run the command "/testevent"
    And the F8 console should show "event sent, waiting for ack..."
    And the F8 console should show "event ack received: server got your event"
    Then the server console should show "event 'playground:event' received from"
    And I confirm: the server console line shows my server id and "hello from client"

  @kora_lib @legacy:lib-discord-sync @target:3 @needs:admin @checklist @checklist:kora_lib:discord-sync @cat:core-and-libraries @manual
  Scenario: Discord: kora_lib_discord_sync from console
    """
    1. In the server console run kora_lib_discord_sync.
    Expect: with no bot token the console says "bot disabled; set kora_lib_discord_bot_token and restart kora_lib."; with a token it prints "role sync started..." then "synced N guild roles and X/Y online members" with skipped and error counts.
    Also checklist kora_lib:discord-sync (Discord role sync command): Console: kora_lib_discord_sync resyncs Discord roles used for staff permission grants.
    """
    When I manually: run kora_lib_discord_sync in the server console
    Then I confirm: with no bot token the console says "bot disabled; set kora_lib_discord_bot_token and restart kora_lib."
    And I confirm: with a token it prints "role sync started..." then "synced N guild roles and X/Y online members" with skipped and error counts

  @kora_lib @legacy:lib-discord-sync-ingame @target:3
  Scenario: Discord: sync command is console-only
    """
    1. In the in-game chat type /kora_lib_discord_sync.
    Expect: nothing happens and no role information is shown to you; the server console prints no sync output for it.
    """
    When I run the command "/kora_lib_discord_sync"
    Then I confirm: nothing happens and no role information is shown to me
    And I confirm: the server console prints no sync output for it
