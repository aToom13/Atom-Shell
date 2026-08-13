-- Optional user overrides and plugin examples.

-------------------------------
-- Dynamic Cursors Plugin
-- https://github.com/VirtCode/hypr-dynamic-cursors
-------------------------------
if hl.plugin.dynamic_cursors then
    hl.config { plugin = { dynamic_cursors = {

        enabled   = true,
        mode      = "tilt",       -- stretch, rotate, tilt, none
        threshold = 2,

        tilt = {
            limit      = 2000,    -- default: 5000
            activation = "negative_quadratic",  -- negative_quadratic
            window     = 200,
            full       = 60,
        },

	stretch = {

        limit = 1000,

        -- relationship between speed and stretch amount, supports these values:
        -- linear             - a linear function is used
        -- quadratic          - a quadratic function is used
        -- negative_quadratic - negative version of the quadratic one, feels more aggressive
        -- see `activation` in `src/mode/utils.cpp` for how exactly the calculation is done
        activation = "quadratic",

        -- time window (ms) over which the speed is calculated
        -- higher values will make slow motions smoother but more delayed
        window = 100,
    },

        rotate = {

        -- length in px of the simulated stick used to rotate the cursor
        -- most realistic if this is your actual cursor size
        length = 70,

        -- clockwise offset applied to the angle in degrees
        -- this will apply to ALL shapes
        offset = 0.0,
    },


        shake = { enabled = false },

        hyprcursor = {
            enabled    = true,
            nearest    = 1,
            resolution = -1,
            fallback   = "clientside",
        },
    }}}

    -- Shape rules
    hl.plugin.dynamic_cursors.shape_rule { shape = "text", rotate = { offset = 90.0 } }
    hl.plugin.dynamic_cursors.shape_rule { shape = "grab", mode = "stretch", stretch = { limit = 2000 } }
end
