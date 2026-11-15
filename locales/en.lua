return {
    Compat = {
        input = {
            warning_icons = "[qb-input-bridge] WARNING: input 'icon' fields (Font Awesome classes) have no equivalent on Kora.nui.openInputDialog's fields -- icons are dropped. Only shown once per session.",
            warning_type = '[qb-input-bridge] WARNING: input type %q is not recognized -- falling back to a plain text field. Only shown once per type per session.',
            name_required = "qb-input compat: every input needs a string 'name'.",
        },
        menu = {
            give_focus = 'Give Menu Focus',
        },
        minigames = {
            skillbar_valid_keys = "^3[qb-minigames compat]^7 Skillbar's validKeys has no equivalent in kora_lib's skillbar minigame -- ignored.",
        },
        progress = {
            callback_not_callable = 'Progressbar callbacks must be callable.',
            owner_invalid = 'Progressbar owner must be a resource name.',
        },
        radial = {
            warning_icons = "[qb-radialmenu-bridge] WARNING: option 'icon' fields (Font Awesome classes) are not translated to Kora.nui's lucide icon names -- icons are dropped. Only shown once per session.",
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
