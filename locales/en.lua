return {
    Local = {
        Callback = {
            name_must_be_string = 'Callback name must be a string.',
            name_must_not_be_empty = 'Callback name must not be empty.',
            name_too_long = 'Callback name must be at most %d bytes.',
            handler_must_be_function = 'Callback handler must be a function.',
            registration_options_must_be_table = 'Callback registration options must be a table.',
            rate_limit_table_or_false = 'Callback rateLimit must be a table or false.',
            rate_limit_max = 'Callback rateLimit.max must be a positive integer no greater than %d.',
            rate_limit_window = 'Callback rateLimit.window must be a positive integer no greater than %d milliseconds.',
            target_positive_server_id = 'target must be a positive finite player server ID.',
            timed_out = 'Callback timed out.',
            handshake_timeout = 'Callback handshake did not complete in time.',
            player_disconnected = 'Player disconnected before answering the callback.',
            not_registered = "Callback '%s' is not registered on the server.",
            rate_limit_exceeded = 'Callback rate limit exceeded; retry in %dms.',
            overwritten = "[kora_lib:callback] '%s' was registered by '%s' "
                .. "and is being overwritten by '%s' -- namespace your callback names.",
            handler_errored = "[kora_lib:callback] handler for '%s' errored: %s",
            handler_errored_for_player = "[kora_lib:callback] handler for '%s' (player %d) errored: %s",
        },
        Events = {
            name_must_be_string = 'Event name must be a string.',
            name_must_not_be_empty = 'Event name must not be empty.',
            name_too_long = 'Event name must be at most %d bytes.',
            registration_options_must_be_table = 'Event registration options must be a table.',
            rate_limit_table_or_false = 'Event rateLimit must be a table or false.',
            rate_limit_max = 'Event rateLimit.max must be a positive integer no greater than %d.',
            rate_limit_window = 'Event rateLimit.window must be a positive integer no greater than %d milliseconds.',
            handler_must_be_function = 'Event handler must be a function.',
            push_handler_must_be_function = 'Push handler must be a function.',
            target_must_be_valid = 'target must be -1 or a positive finite player server ID.',
            handshake_timeout = 'Event handshake did not complete in time.',
            overwritten = "[kora_lib:events] '%s' was registered by '%s' "
                .. "and is being overwritten by '%s' -- namespace your event names.",
            push_handler_overwritten = "[kora_lib:events] push handler '%s' was registered by '%s' "
                .. "and is being overwritten by '%s' -- namespace your push names.",
            handler_errored = "[kora_lib:events] handler for '%s' errored: %s",
            push_handler_errored = "[kora_lib:events] push handler for '%s' errored: %s",
        },
        Resources = {
            id_must_not_be_nil = 'Registry id must not be nil.',
            resource_name_invalid = 'Registry resource must be a non-empty string up to 256 bytes.',
            function_requires_resource_name = '%s requires a resource name up to 256 bytes.',
            client_registry_requires_callable = 'Kora.resources.registry requires a callable disposer.',
            server_registry_requires_callable = 'Kora.resources.serverRegistry requires a callable disposer.',
            cannot_track_while_stopping = 'Cannot track an id for a resource while it is stopping.',
            await_started_options_must_be_table = 'Kora.resources.awaitStarted options must be a table.',
            await_started_timeout_invalid = 'Kora.resources.awaitStarted timeout must be a non-negative finite number.',
            await_started_interval_invalid = 'Kora.resources.awaitStarted interval must be a non-negative finite '
                .. 'number.',
            client_cleanup_failed = '^3[kora_lib:resources]^7 cleanup for %s id %s failed: %s',
            server_cleanup_failed = '^3[kora_lib:resources]^7 cleanup for %s id %s failed: %s',
        },
    },
    Compat = {
        input = {
            warning_icons = "[qb-input-bridge] WARNING: input 'icon' fields (Font Awesome classes) "
                .. "have no equivalent on Kora.nui.openInputDialog's fields -- icons are dropped. "
                .. 'Only shown once per session.',
            warning_type = '[qb-input-bridge] WARNING: input type %q is not recognized -- falling back to a plain text '
                .. 'field. Only shown once per type per session.',
            name_required = "qb-input compat: every input needs a string 'name'.",
        },
        menu = {
            give_focus = 'Give Menu Focus',
        },
        minigames = {
            skillbar_valid_keys = "^3[qb-minigames compat]^7 Skillbar's validKeys has no equivalent in kora_lib's "
                .. 'skillbar minigame -- ignored.',
        },
        progress = {
            callback_not_callable = 'Progressbar callbacks must be callable.',
            owner_invalid = 'Progressbar owner must be a resource name.',
        },
        radial = {
            warning_icons = "[qb-radialmenu-bridge] WARNING: option 'icon' fields (Font Awesome classes) "
                .. "are not translated to Kora.nui's lucide icon names -- icons are dropped. "
                .. 'Only shown once per session.',
            on_select_error = '[qb-radialmenu-bridge] WARNING: onSelect for option %q errored: %s',
            add_option_required = 'qb-radialmenu compat: AddOption requires an option table.',
            open_menu = 'Open Radial Menu',
            driver_door = 'Driver Door',
            hood = 'Hood',
            passenger_door = 'Passenger Door',
            right_rear_door = 'Right Rear',
            trunk = 'Trunk',
            left_rear_door = 'Left Rear',
            driver_seat = 'Driver Seat',
            passenger_seat = 'Passenger Seat',
            rear_left_seat = 'Rear Left Seat',
            rear_right_seat = 'Rear Right Seat',
            flipping_vehicle = 'Flipping vehicle...',
            vehicle_doors = 'Vehicle Doors',
            extra = 'Extra %d',
            vehicle_extras = 'Vehicle Extras',
            flip_vehicle = 'Flip Vehicle',
            other_seat = 'Other Seat',
            vehicle_seats = 'Vehicle Seats',
            vehicle = 'Vehicle',
            work = 'Work',
        },
    },
}
