--[[
@version 1.6
@noindex
--]]

-- Constants for the Ambiance Creator
local Constants = {}

-- UI Constants
Constants.UI = {
    CONTAINER_INDENT = 20,              -- Indentation for containers in UI
    HELP_MARKER_TEXT_WRAP = 35.0,       -- Text wrap position for help markers
    PRESET_SELECTOR_WIDTH = 200,        -- Width of preset selector dropdowns
    BUTTON_WIDTH_STANDARD = 120,        -- Standard button width
    BUTTON_WIDTH_WIDE = 150,            -- Wide button width
    GROUP_DROP_ZONE_HEIGHT = 8,         -- Height of group drop zones
    CONTAINER_DROP_ZONE_HEIGHT = 6,     -- Height of container drop zones
    MIN_WINDOW_HEIGHT = 100,            -- Minimum window height
    MIN_WINDOW_WIDTH = 200,             -- Minimum window width
    LEFT_PANEL_DEFAULT_WIDTH = 0.35,    -- Default left panel width as percentage of window
    MIN_LEFT_PANEL_WIDTH = 150,         -- Minimum left panel width in pixels
    SPLITTER_WIDTH = 4,                 -- Width of the splitter/divider
}

-- Color Constants
Constants.COLORS = {
    ERROR_RED = 0xFF0000FF,             -- Red color for errors
    SUCCESS_GREEN = 0xFF4CAF50,         -- Green color for success
    WARNING_ORANGE = 0xFF8000FF,        -- Orange color for warnings
    DEFAULT_WHITE = 0xFFFFFFFF,         -- Default white color
}

-- Audio Constants
Constants.AUDIO = {
    DEFAULT_CROSSFADE_MARGIN = 0.1,     -- Default crossfade margin in seconds
    DEFAULT_FADE_SHAPE = 0,             -- Default fade shape
    VOLUME_RANGE_DB_MIN = -144,         -- Minimum volume range for sliders (dB, -inf)
    VOLUME_RANGE_DB_MAX = 24,           -- Maximum volume range for sliders (dB)
}

-- File System Constants
Constants.FILESYSTEM = {
    PRESET_CACHE_TTL = 3600,            -- Preset cache time-to-live in seconds
}

-- Track Constants
Constants.TRACKS = {
    FOLDER_START_DEPTH = 1,             -- Folder start depth value
    FOLDER_END_DEPTH = -1,              -- Folder end depth value
    NORMAL_TRACK_DEPTH = 0,             -- Normal track depth value
}

-- Trigger Mode Constants
Constants.TRIGGER_MODES = {
    ABSOLUTE = 0,                       -- Absolute interval mode
    RELATIVE = 1,                       -- Relative interval mode
    COVERAGE = 2,                       -- Coverage interval mode
    CHUNK = 3,                          -- Chunk mode: structured sound/silence periods
    NOISE = 4,                          -- Noise mode: placement based on noise function
    EUCLIDEAN = 5,                      -- Euclidean rhythm: mathematically optimal distribution
}

-- Noise Type Constants (curve shape)
Constants.NOISE_TYPES = {
    PERLIN = 0,                         -- Classic Perlin fBm: smooth organic curves
    RIDGED = 1,                         -- Ridged multifractal: sharp peaks, calm valleys
    WORLEY = 2,                         -- Worley/Cellular: burst clusters separated by silence
    SINE = 3,                           -- Sine wave: perfectly periodic pattern
}

-- Noise Algorithm Mode Constants
Constants.NOISE_ALGORITHMS = {
    PROBABILITY = 0,                    -- Probability test at intervals with jitter
    ACCUMULATION = 1,                   -- Probability accumulation until threshold
}

-- Noise Placement Anchor Constants
Constants.NOISE_PLACEMENT_ANCHORS = {
    START_TO_START = 0,                 -- Next item starts relative to previous start (allows overlap)
    END_TO_START = 1,                   -- Next item starts after previous ends (no overlap)
}

-- Channel Mode Constants
Constants.CHANNEL_MODES = {
    DEFAULT = 0,                        -- Standard stereo (1/2)
    QUAD = 1,                          -- 4.0: L, R, LS, RS
    FIVE_ZERO = 2,                     -- 5.0: L, R, C, LS, RS or L, C, R, LS, RS
    SEVEN_ZERO = 3                     -- 7.0: L, R, C, LS, RS, LB, RB or L, C, R, LS, RS, LB, RB
}

-- Channel Configuration Details
Constants.CHANNEL_CONFIGS = {
    [0] = {
        name = "Default (Stereo)",
        channels = 0,  -- No child tracks, generate on container
        totalChannels = 2,
        routing = nil,
        labels = nil
    },
    [1] = {
        name = "4.0 Quad",
        channels = 4,
        totalChannels = 4,
        routing = {1, 2, 3, 4},  -- Each track to single channel
        labels = {"L", "R", "LS", "RS"}
    },
    [2] = {
        name = "5.0",
        channels = 5,
        totalChannels = 5,
        hasVariants = true,
        variants = {
            [0] = {
                name = "Dolby/ITU (L R C LS RS)",
                routing = {1, 2, 3, 4, 5},
                labels = {"L", "R", "C", "LS", "RS"}
            },
            [1] = {
                name = "SMPTE (L C R LS RS)",
                routing = {1, 3, 2, 4, 5},  -- C in position 2
                labels = {"L", "C", "R", "LS", "RS"}
            }
        }
    },
    [3] = {
        name = "7.0",
        channels = 7,
        totalChannels = 7,
        hasVariants = true,
        variants = {
            [0] = {
                name = "Dolby/ITU (L R C LS RS LB RB)",
                routing = {1, 2, 3, 4, 5, 6, 7},
                labels = {"L", "R", "C", "LS", "RS", "LB", "RB"}
            },
            [1] = {
                name = "SMPTE (L C R LS RS LB RB)",
                routing = {1, 3, 2, 4, 5, 6, 7},  -- C in position 2
                labels = {"L", "C", "R", "LS", "RS", "LB", "RB"}
            }
        }
    }
}

-- Fade Shape Constants (Reaper API values)
Constants.FADE_SHAPES = {
    LINEAR = 0,                         -- Linear fade
    FAST_START = 1,                     -- Fast start (log)
    FAST_END = 2,                       -- Fast end (exp)
    FAST_START_END = 3,                 -- Fast start/end
    SLOW_START_END = 4,                 -- Slow start/end
    BEZIER = 5,                         -- Bezier curve
    S_CURVE = 6,                        -- S-curve
}

-- Pitch Mode Constants
Constants.PITCH_MODES = {
    PITCH = 0,                          -- Standard pitch shift (D_PITCH)
    STRETCH = 1,                        -- Time stretch (D_PLAYRATE)
}

-- Variation Direction Constants
Constants.VARIATION_DIRECTIONS = {
    NEGATIVE = 0,                       -- Negative only (←)
    BIPOLAR = 1,                        -- Bipolar (↔)
    POSITIVE = 2,                       -- Positive only (→)
}

-- Noise Generation Algorithm Constants
Constants.NOISE_GENERATION = {
    SELECTION_TIME_OFFSET = 0.123,      -- Time offset to decorrelate item selection noise
    SELECTION_SEED_OFFSET = 12345,      -- Seed offset for item selection noise
    SELECTION_FREQ_MULT = 1.23,         -- Frequency multiplier for item selection
    AREA_TIME_OFFSET = 0.456,           -- Time offset to decorrelate area selection noise
    AREA_SEED_OFFSET = 67890,           -- Seed offset for area selection noise
    AREA_FREQ_MULT = 0.87,              -- Frequency multiplier for area selection
}

-- Default Values
Constants.DEFAULTS = {
    TRIGGER_RATE = 10.0,                -- Default trigger rate
    TRIGGER_DRIFT = 30,                 -- Default trigger drift percentage
    TRIGGER_DRIFT_DIRECTION = 1,        -- Default trigger drift direction (BIPOLAR)
    PITCH_MODE = 0,                     -- Default pitch mode (PITCH)
    PITCH_RANGE_MIN = -3,               -- Default min pitch range
    PITCH_RANGE_MAX = 3,                -- Default max pitch range
    VOLUME_RANGE_MIN = -3,              -- Default min volume range (dB)
    VOLUME_RANGE_MAX = 3,               -- Default max volume range (dB)
    PAN_RANGE_MIN = -100,               -- Default min pan range
    PAN_RANGE_MAX = 100,                -- Default max pan range
    CONTAINER_VOLUME_DEFAULT = 0.0,     -- Default container track volume (dB)
    FOLDER_VOLUME_DEFAULT = 0.0,        -- Default folder track volume (dB)
    UI_SCALE = 1.0,                     -- Default UI scale factor (1.0 = 100%)
    -- Chunk Mode defaults
    CHUNK_DURATION = 10.0,              -- Default chunk duration in seconds
    CHUNK_SILENCE = 5.0,                -- Default silence duration in seconds
    CHUNK_DURATION_VARIATION = 20,      -- Default chunk duration variation percentage
    CHUNK_DURATION_VAR_DIRECTION = 1,   -- Default chunk duration variation direction (BIPOLAR)
    CHUNK_SILENCE_VARIATION = 20,       -- Default silence duration variation percentage
    CHUNK_SILENCE_VAR_DIRECTION = 1,    -- Default silence variation direction (BIPOLAR)
    -- Noise Mode defaults
    NOISE_SEED_MIN = 1,                 -- Minimum seed value
    NOISE_SEED_MAX = 999999,            -- Maximum seed value
    NOISE_FREQUENCY = 0.1,              -- Default noise frequency (Hz) — real Hz after /10.0 removal
    NOISE_AMPLITUDE = 100.0,            -- Default noise amplitude (%)
    NOISE_OCTAVES = 2,                  -- Default number of octaves
    NOISE_PERSISTENCE = 0.5,            -- Default persistence (amplitude decrease per octave)
    NOISE_LACUNARITY = 2.0,             -- Default lacunarity (frequency increase per octave)
    NOISE_DENSITY = 50.0,               -- Default average density percentage
    NOISE_THRESHOLD = 0.0,              -- Default minimum noise value to place item
    NOISE_TYPE = 0,                     -- Default noise type (PERLIN)
    NOISE_ALGORITHM = 0,                -- Default algorithm (PROBABILITY)
    NOISE_RESOLUTION = 10,              -- Default noise resolution (samples per second)
    NOISE_RESOLUTION_MIN = 1,           -- Minimum noise resolution
    NOISE_RESOLUTION_MAX = 100,         -- Maximum noise resolution
    NOISE_PLACEMENT_ANCHOR = 0,         -- Default placement anchor (START_TO_START)
    -- Euclidean Mode defaults
    EUCLIDEAN_MODE = 0,                 -- Default mode (0=Tempo-Based, 1=Fit-to-Selection)
    EUCLIDEAN_TEMPO = 120,              -- Default tempo (BPM)
    EUCLIDEAN_USE_PROJECT_TEMPO = false, -- Default use project tempo
    EUCLIDEAN_PULSES = 8,               -- Default number of pulses (hits)
    EUCLIDEAN_STEPS = 16,               -- Default number of steps (subdivisions)
    EUCLIDEAN_ROTATION = 0,             -- Default rotation offset (0 = no rotation)
    EUCLIDEAN_SELECTED_LAYER = 1,       -- Default selected layer index
    EUCLIDEAN_SELECTED_BINDING_INDEX = 1, -- Default selected binding index (auto-bind mode)
}

-- Euclidean Rhythm Pattern Presets
Constants.EUCLIDEAN_PATTERNS = {
    {
        category = "Famous Traditional Patterns",
        patterns = {
            {name = "Conga (Afro-Cuban)", pulses = 2, steps = 3, description = "Common Afro-Cuban drum pattern, Swing Tumbao (6/8)"},
            {name = "Cumbia (Colombian)", pulses = 3, steps = 4, description = "Traditional Colombian rhythm"},
            {name = "Bembé (West African)", pulses = 2, steps = 5, description = "Traditional African bell pattern"},
            {name = "Korean (Chang-dan)", pulses = 3, steps = 5, description = "Traditional Korean rhythm"},
            {name = "Albanian", pulses = 5, steps = 6, description = "Traditional Albanian rhythm"},
            {name = "Persian (Rucak)", pulses = 3, steps = 7, description = "Rucak rhythm"},
            {name = "Rag-time (American)", pulses = 4, steps = 7, description = "Common rag-time bass drum pattern"},
            {name = "Persian (Nawakhat)", pulses = 5, steps = 7, description = "Persian Nawakhat rhythm"},
            {name = "Tresillo (Cuban/Habanera)", pulses = 3, steps = 8, description = "Famous Cuban rhythm, used in rockabilly, Elvis 'Hound Dog'"},
            {name = "Cinquillo (Cuban)", pulses = 5, steps = 8, description = "Cuban cinquillo, used in jazz and rockabilly"},
            {name = "Cuban 7/8", pulses = 7, steps = 8, description = "Cuban rhythm pattern"},
            {name = "Aksak (Turkish)", pulses = 4, steps = 9, description = "Turkish Aksak rhythm"},
            {name = "Agsag-Samai (Arab)", pulses = 5, steps = 9, description = "Arab rhythm"},
            {name = "Frank Zappa", pulses = 4, steps = 11, description = "Used by Frank Zappa"},
            {name = "Moussorgsky", pulses = 5, steps = 11, description = "Used in Moussorgsky's 'Pictures at an Exhibition'"},
            {name = "Fandango (Spanish)", pulses = 4, steps = 12, description = "Flamenco clapping pattern (12/8)"},
            {name = "Bossa Nova (Brazilian)", pulses = 5, steps = 12, description = "Traditional Brazilian bossa nova rhythm"},
            {name = "Balkan (7+5)", pulses = 7, steps = 12, description = "Balkan rhythm (7+5)"},
            {name = "Bossa Nova 16 (Brazilian)", pulses = 5, steps = 16, description = "Variation of Brazilian bossa nova"},
            {name = "Brazilian Samba", pulses = 7, steps = 16, description = "Brazilian samba pattern"},
            {name = "Rag-time Complex (American)", pulses = 9, steps = 16, description = "Complex rag-time pattern"},
            {name = "Aka Pygmy 11/24", pulses = 11, steps = 24, description = "Traditional Aka Pygmy rhythm"},
            {name = "Aka Pygmy 13/24", pulses = 13, steps = 24, description = "Traditional Aka Pygmy rhythm"},
        }
    },
    {
        category = "Simple Patterns (n ≤ 8)",
        patterns = {
            {name = "E(1,3)", pulses = 1, steps = 3, description = "Regular - [x . .]"},
            {name = "E(2,3)", pulses = 2, steps = 3, description = "Simple - [x . x]"},
            {name = "E(1,4)", pulses = 1, steps = 4, description = "Regular - [x . . .]"},
            {name = "E(2,4)", pulses = 2, steps = 4, description = "Regular - [x . x .]"},
            {name = "E(3,4)", pulses = 3, steps = 4, description = "Simple - [x . x x]"},
            {name = "E(1,5)", pulses = 1, steps = 5, description = "Regular - [x . . . .]"},
            {name = "E(2,5)", pulses = 2, steps = 5, description = "Complex - [x . x . .]"},
            {name = "E(3,5)", pulses = 3, steps = 5, description = "Complex - [x . x . x]"},
            {name = "E(4,5)", pulses = 4, steps = 5, description = "Simple - [x . x x x]"},
            {name = "E(1,6)", pulses = 1, steps = 6, description = "Regular - [x . . . . .]"},
            {name = "E(2,6)", pulses = 2, steps = 6, description = "Regular - [x . x . . .]"},
            {name = "E(3,6)", pulses = 3, steps = 6, description = "Regular - [x . x . x .]"},
            {name = "E(4,6)", pulses = 4, steps = 6, description = "Complex - [x . x . x x]"},
            {name = "E(5,6)", pulses = 5, steps = 6, description = "Simple - [x . x x x x]"},
            {name = "E(1,7)", pulses = 1, steps = 7, description = "Regular - [x . . . . . .]"},
            {name = "E(2,7)", pulses = 2, steps = 7, description = "Complex - [x . x . . . .]"},
            {name = "E(3,7)", pulses = 3, steps = 7, description = "Complex - [x . x . x . .]"},
            {name = "E(4,7)", pulses = 4, steps = 7, description = "Complex - [x . x . x . x]"},
            {name = "E(5,7)", pulses = 5, steps = 7, description = "Complex - [x . x . x x x]"},
            {name = "E(6,7)", pulses = 6, steps = 7, description = "Simple - [x . x x x x x]"},
            {name = "E(1,8)", pulses = 1, steps = 8, description = "Regular - [x . . . . . . .]"},
            {name = "E(2,8)", pulses = 2, steps = 8, description = "Regular - [x . x . . . . .]"},
            {name = "E(3,8)", pulses = 3, steps = 8, description = "Complex - [x . x . x . . .]"},
            {name = "E(4,8)", pulses = 4, steps = 8, description = "Regular - [x . x . x . x .]"},
            {name = "E(5,8)", pulses = 5, steps = 8, description = "Complex - [x . x . x . x x]"},
            {name = "E(6,8)", pulses = 6, steps = 8, description = "Complex - [x . x . x x x x]"},
            {name = "E(7,8)", pulses = 7, steps = 8, description = "Simple - [x . x x x x x x]"},
        }
    },
    {
        category = "Medium Patterns (9 ≤ n ≤ 16)",
        patterns = {
            {name = "E(1,9)", pulses = 1, steps = 9, description = "Regular"},
            {name = "E(2,9)", pulses = 2, steps = 9, description = "Complex"},
            {name = "E(3,9)", pulses = 3, steps = 9, description = "Regular"},
            {name = "E(4,9)", pulses = 4, steps = 9, description = "Complex"},
            {name = "E(5,9)", pulses = 5, steps = 9, description = "Complex"},
            {name = "E(6,9)", pulses = 6, steps = 9, description = "Complex"},
            {name = "E(7,9)", pulses = 7, steps = 9, description = "Complex"},
            {name = "E(8,9)", pulses = 8, steps = 9, description = "Simple"},
            {name = "E(1,10)", pulses = 1, steps = 10, description = "Regular"},
            {name = "E(2,10)", pulses = 2, steps = 10, description = "Regular"},
            {name = "E(3,10)", pulses = 3, steps = 10, description = "Complex"},
            {name = "E(4,10)", pulses = 4, steps = 10, description = "Complex"},
            {name = "E(5,10)", pulses = 5, steps = 10, description = "Regular"},
            {name = "E(6,10)", pulses = 6, steps = 10, description = "Complex"},
            {name = "E(7,10)", pulses = 7, steps = 10, description = "Complex"},
            {name = "E(8,10)", pulses = 8, steps = 10, description = "Complex"},
            {name = "E(9,10)", pulses = 9, steps = 10, description = "Simple"},
            {name = "E(1,11)", pulses = 1, steps = 11, description = "Regular"},
            {name = "E(2,11)", pulses = 2, steps = 11, description = "Complex"},
            {name = "E(3,11)", pulses = 3, steps = 11, description = "Complex"},
            {name = "E(4,11)", pulses = 4, steps = 11, description = "Complex"},
            {name = "E(5,11)", pulses = 5, steps = 11, description = "Complex"},
            {name = "E(6,11)", pulses = 6, steps = 11, description = "Complex"},
            {name = "E(7,11)", pulses = 7, steps = 11, description = "Complex"},
            {name = "E(8,11)", pulses = 8, steps = 11, description = "Complex"},
            {name = "E(9,11)", pulses = 9, steps = 11, description = "Complex"},
            {name = "E(10,11)", pulses = 10, steps = 11, description = "Simple"},
            {name = "E(1,12)", pulses = 1, steps = 12, description = "Regular"},
            {name = "E(2,12)", pulses = 2, steps = 12, description = "Regular"},
            {name = "E(3,12)", pulses = 3, steps = 12, description = "Regular"},
            {name = "E(4,12)", pulses = 4, steps = 12, description = "Regular"},
            {name = "E(5,12)", pulses = 5, steps = 12, description = "Complex"},
            {name = "E(6,12)", pulses = 6, steps = 12, description = "Regular"},
            {name = "E(7,12)", pulses = 7, steps = 12, description = "Complex"},
            {name = "E(8,12)", pulses = 8, steps = 12, description = "Complex"},
            {name = "E(9,12)", pulses = 9, steps = 12, description = "Complex"},
            {name = "E(10,12)", pulses = 10, steps = 12, description = "Complex"},
            {name = "E(11,12)", pulses = 11, steps = 12, description = "Simple"},
            {name = "E(1,13)", pulses = 1, steps = 13, description = "Regular"},
            {name = "E(2,13)", pulses = 2, steps = 13, description = "Complex"},
            {name = "E(3,13)", pulses = 3, steps = 13, description = "Complex"},
            {name = "E(4,13)", pulses = 4, steps = 13, description = "Complex"},
            {name = "E(5,13)", pulses = 5, steps = 13, description = "Complex"},
            {name = "E(6,13)", pulses = 6, steps = 13, description = "Complex"},
            {name = "E(7,13)", pulses = 7, steps = 13, description = "Complex"},
            {name = "E(8,13)", pulses = 8, steps = 13, description = "Complex"},
            {name = "E(9,13)", pulses = 9, steps = 13, description = "Complex"},
            {name = "E(10,13)", pulses = 10, steps = 13, description = "Complex"},
            {name = "E(11,13)", pulses = 11, steps = 13, description = "Complex"},
            {name = "E(12,13)", pulses = 12, steps = 13, description = "Simple"},
            {name = "E(1,14)", pulses = 1, steps = 14, description = "Regular"},
            {name = "E(2,14)", pulses = 2, steps = 14, description = "Regular"},
            {name = "E(3,14)", pulses = 3, steps = 14, description = "Complex"},
            {name = "E(4,14)", pulses = 4, steps = 14, description = "Complex"},
            {name = "E(5,14)", pulses = 5, steps = 14, description = "Complex"},
            {name = "E(6,14)", pulses = 6, steps = 14, description = "Complex"},
            {name = "E(7,14)", pulses = 7, steps = 14, description = "Regular"},
            {name = "E(8,14)", pulses = 8, steps = 14, description = "Complex"},
            {name = "E(9,14)", pulses = 9, steps = 14, description = "Complex"},
            {name = "E(10,14)", pulses = 10, steps = 14, description = "Complex"},
            {name = "E(11,14)", pulses = 11, steps = 14, description = "Complex"},
            {name = "E(12,14)", pulses = 12, steps = 14, description = "Complex"},
            {name = "E(1,15)", pulses = 1, steps = 15, description = "Regular"},
            {name = "E(2,15)", pulses = 2, steps = 15, description = "Complex"},
            {name = "E(3,15)", pulses = 3, steps = 15, description = "Regular"},
            {name = "E(4,15)", pulses = 4, steps = 15, description = "Complex"},
            {name = "E(5,15)", pulses = 5, steps = 15, description = "Regular"},
            {name = "E(6,15)", pulses = 6, steps = 15, description = "Complex"},
            {name = "E(7,15)", pulses = 7, steps = 15, description = "Complex"},
            {name = "E(8,15)", pulses = 8, steps = 15, description = "Complex"},
            {name = "E(9,15)", pulses = 9, steps = 15, description = "Complex"},
            {name = "E(10,15)", pulses = 10, steps = 15, description = "Complex"},
            {name = "E(11,15)", pulses = 11, steps = 15, description = "Complex"},
            {name = "E(12,15)", pulses = 12, steps = 15, description = "Complex"},
            {name = "E(1,16)", pulses = 1, steps = 16, description = "Regular"},
            {name = "E(2,16)", pulses = 2, steps = 16, description = "Regular"},
            {name = "E(3,16)", pulses = 3, steps = 16, description = "Complex"},
            {name = "E(4,16)", pulses = 4, steps = 16, description = "Regular"},
            {name = "E(5,16)", pulses = 5, steps = 16, description = "Complex"},
            {name = "E(6,16)", pulses = 6, steps = 16, description = "Complex"},
            {name = "E(7,16)", pulses = 7, steps = 16, description = "Complex"},
            {name = "E(8,16)", pulses = 8, steps = 16, description = "Regular"},
            {name = "E(9,16)", pulses = 9, steps = 16, description = "Complex"},
            {name = "E(10,16)", pulses = 10, steps = 16, description = "Complex"},
            {name = "E(11,16)", pulses = 11, steps = 16, description = "Complex"},
            {name = "E(12,16)", pulses = 12, steps = 16, description = "Complex"},
        }
    },
    {
        category = "Extended Patterns (17 ≤ n ≤ 32)",
        patterns = {
            {name = "E(2,17)", pulses = 2, steps = 17, description = "[x . x . . . . . . . . . . . . . .]"},
            {name = "E(3,17)", pulses = 3, steps = 17, description = "[x . x . x . . . . . . . . . . . .]"},
            {name = "E(5,17)", pulses = 5, steps = 17, description = "[x . x . x . x . x . . . . . . . .]"},
            {name = "E(7,17)", pulses = 7, steps = 17, description = "[x . x . x . x . x . x . x . . . .]"},
            {name = "E(11,17)", pulses = 11, steps = 17, description = "[x . x . x . x . x . x . x x x x x]"},
            {name = "E(13,17)", pulses = 13, steps = 17, description = "[x . x . x . x . x x x x x x x x x]"},
            {name = "E(2,18)", pulses = 2, steps = 18, description = "[x . x . . . . . . . . . . . . . . .]"},
            {name = "E(3,18)", pulses = 3, steps = 18, description = "[x . x . x . . . . . . . . . . . . .]"},
            {name = "E(5,18)", pulses = 5, steps = 18, description = "[x . x . x . x . x . . . . . . . . .]"},
            {name = "E(7,18)", pulses = 7, steps = 18, description = "[x . x . x . x . x . x . x . . . . .]"},
            {name = "E(11,18)", pulses = 11, steps = 18, description = "[x . x . x . x . x . x . x . x x x x]"},
            {name = "E(13,18)", pulses = 13, steps = 18, description = "[x . x . x . x . x . x x x x x x x x]"},
            {name = "E(2,19)", pulses = 2, steps = 19, description = "Extended pattern"},
            {name = "E(3,19)", pulses = 3, steps = 19, description = "Extended pattern"},
            {name = "E(5,19)", pulses = 5, steps = 19, description = "Extended pattern"},
            {name = "E(7,19)", pulses = 7, steps = 19, description = "Extended pattern"},
            {name = "E(11,19)", pulses = 11, steps = 19, description = "Extended pattern"},
            {name = "E(13,19)", pulses = 13, steps = 19, description = "Extended pattern"},
            {name = "E(2,20)", pulses = 2, steps = 20, description = "Extended pattern"},
            {name = "E(3,20)", pulses = 3, steps = 20, description = "Extended pattern"},
            {name = "E(5,20)", pulses = 5, steps = 20, description = "Extended pattern"},
            {name = "E(7,20)", pulses = 7, steps = 20, description = "Extended pattern"},
            {name = "E(11,20)", pulses = 11, steps = 20, description = "Extended pattern"},
            {name = "E(13,20)", pulses = 13, steps = 20, description = "Extended pattern"},
            {name = "E(2,21)", pulses = 2, steps = 21, description = "Extended pattern"},
            {name = "E(3,21)", pulses = 3, steps = 21, description = "Extended pattern"},
            {name = "E(5,21)", pulses = 5, steps = 21, description = "Extended pattern"},
            {name = "E(7,21)", pulses = 7, steps = 21, description = "Extended pattern"},
            {name = "E(11,21)", pulses = 11, steps = 21, description = "Extended pattern"},
            {name = "E(13,21)", pulses = 13, steps = 21, description = "Extended pattern"},
            {name = "E(2,22)", pulses = 2, steps = 22, description = "Extended pattern"},
            {name = "E(3,22)", pulses = 3, steps = 22, description = "Extended pattern"},
            {name = "E(5,22)", pulses = 5, steps = 22, description = "Extended pattern"},
            {name = "E(7,22)", pulses = 7, steps = 22, description = "Extended pattern"},
            {name = "E(11,22)", pulses = 11, steps = 22, description = "Extended pattern"},
            {name = "E(13,22)", pulses = 13, steps = 22, description = "Extended pattern"},
            {name = "E(2,23)", pulses = 2, steps = 23, description = "Extended pattern"},
            {name = "E(3,23)", pulses = 3, steps = 23, description = "Extended pattern"},
            {name = "E(5,23)", pulses = 5, steps = 23, description = "Extended pattern"},
            {name = "E(7,23)", pulses = 7, steps = 23, description = "Extended pattern"},
            {name = "E(11,23)", pulses = 11, steps = 23, description = "Extended pattern"},
            {name = "E(13,23)", pulses = 13, steps = 23, description = "Extended pattern"},
            {name = "E(2,24)", pulses = 2, steps = 24, description = "Extended pattern"},
            {name = "E(3,24)", pulses = 3, steps = 24, description = "Extended pattern"},
            {name = "E(5,24)", pulses = 5, steps = 24, description = "Extended pattern"},
            {name = "E(7,24)", pulses = 7, steps = 24, description = "Extended pattern"},
            {name = "E(11,24)", pulses = 11, steps = 24, description = "Extended pattern"},
            {name = "E(13,24)", pulses = 13, steps = 24, description = "Extended pattern"},
            {name = "E(2,25)", pulses = 2, steps = 25, description = "Extended pattern"},
            {name = "E(3,25)", pulses = 3, steps = 25, description = "Extended pattern"},
            {name = "E(5,25)", pulses = 5, steps = 25, description = "Extended pattern"},
            {name = "E(7,25)", pulses = 7, steps = 25, description = "Extended pattern"},
            {name = "E(11,25)", pulses = 11, steps = 25, description = "Extended pattern"},
            {name = "E(13,25)", pulses = 13, steps = 25, description = "Extended pattern"},
            {name = "E(2,26)", pulses = 2, steps = 26, description = "Extended pattern"},
            {name = "E(3,26)", pulses = 3, steps = 26, description = "Extended pattern"},
            {name = "E(5,26)", pulses = 5, steps = 26, description = "Extended pattern"},
            {name = "E(7,26)", pulses = 7, steps = 26, description = "Extended pattern"},
            {name = "E(11,26)", pulses = 11, steps = 26, description = "Extended pattern"},
            {name = "E(13,26)", pulses = 13, steps = 26, description = "Extended pattern"},
            {name = "E(2,27)", pulses = 2, steps = 27, description = "Extended pattern"},
            {name = "E(3,27)", pulses = 3, steps = 27, description = "Extended pattern"},
            {name = "E(5,27)", pulses = 5, steps = 27, description = "Extended pattern"},
            {name = "E(7,27)", pulses = 7, steps = 27, description = "Extended pattern"},
            {name = "E(11,27)", pulses = 11, steps = 27, description = "Extended pattern"},
            {name = "E(13,27)", pulses = 13, steps = 27, description = "Extended pattern"},
            {name = "E(2,28)", pulses = 2, steps = 28, description = "Extended pattern"},
            {name = "E(3,28)", pulses = 3, steps = 28, description = "Extended pattern"},
            {name = "E(5,28)", pulses = 5, steps = 28, description = "Extended pattern"},
            {name = "E(7,28)", pulses = 7, steps = 28, description = "Extended pattern"},
            {name = "E(11,28)", pulses = 11, steps = 28, description = "Extended pattern"},
            {name = "E(13,28)", pulses = 13, steps = 28, description = "Extended pattern"},
            {name = "E(2,29)", pulses = 2, steps = 29, description = "Extended pattern"},
            {name = "E(3,29)", pulses = 3, steps = 29, description = "Extended pattern"},
            {name = "E(5,29)", pulses = 5, steps = 29, description = "Extended pattern"},
            {name = "E(7,29)", pulses = 7, steps = 29, description = "Extended pattern"},
            {name = "E(11,29)", pulses = 11, steps = 29, description = "Extended pattern"},
            {name = "E(13,29)", pulses = 13, steps = 29, description = "Extended pattern"},
            {name = "E(2,30)", pulses = 2, steps = 30, description = "Extended pattern"},
            {name = "E(3,30)", pulses = 3, steps = 30, description = "Extended pattern"},
            {name = "E(5,30)", pulses = 5, steps = 30, description = "Extended pattern"},
            {name = "E(7,30)", pulses = 7, steps = 30, description = "Extended pattern"},
            {name = "E(11,30)", pulses = 11, steps = 30, description = "Extended pattern"},
            {name = "E(13,30)", pulses = 13, steps = 30, description = "Extended pattern"},
            {name = "E(2,31)", pulses = 2, steps = 31, description = "Extended pattern"},
            {name = "E(3,31)", pulses = 3, steps = 31, description = "Extended pattern"},
            {name = "E(5,31)", pulses = 5, steps = 31, description = "Extended pattern"},
            {name = "E(7,31)", pulses = 7, steps = 31, description = "Extended pattern"},
            {name = "E(11,31)", pulses = 11, steps = 31, description = "Extended pattern"},
            {name = "E(13,31)", pulses = 13, steps = 31, description = "Extended pattern"},
            {name = "E(2,32)", pulses = 2, steps = 32, description = "Extended pattern"},
            {name = "E(3,32)", pulses = 3, steps = 32, description = "Extended pattern"},
            {name = "E(5,32)", pulses = 5, steps = 32, description = "Extended pattern"},
            {name = "E(7,32)", pulses = 7, steps = 32, description = "Extended pattern"},
            {name = "E(11,32)", pulses = 11, steps = 32, description = "Extended pattern"},
            {name = "E(13,32)", pulses = 13, steps = 32, description = "Extended pattern"},
        }
    },
}

Constants.GENERATION_DEFAULTS = {
    -- Fade defaults
    FADE_IN_ENABLED = true,             -- Default fade in state
    FADE_OUT_ENABLED = true,            -- Default fade out state
    FADE_IN_DURATION = 0.0,             -- Default fade in duration (seconds)
    FADE_OUT_DURATION = 0.0,            -- Default fade out duration (seconds)
    FADE_IN_USE_PERCENTAGE = true,      -- Use percentage by default
    FADE_OUT_USE_PERCENTAGE = true,     -- Use percentage by default
    FADE_IN_SHAPE = 0,                  -- Default to linear fade
    FADE_OUT_SHAPE = 0,                 -- Default to linear fade
    FADE_IN_CURVE = 0.0,                -- Default curve control
    FADE_OUT_CURVE = 0.0,               -- Default curve control
}

-- Export Feature Constants
Constants.EXPORT = {
    INSTANCE_MIN = 1,                   -- Minimum instance amount
    INSTANCE_MAX = 100,                 -- Maximum instance amount
    INSTANCE_DEFAULT = 1,               -- Default instance amount
    SPACING_MIN = 0,                    -- Minimum spacing in seconds
    SPACING_MAX = 60,                   -- Maximum spacing in seconds
    SPACING_DEFAULT = 1.0,              -- Default spacing (1 second)
    ALIGN_TO_SECONDS_DEFAULT = true,    -- Default align to whole seconds
    PRESERVE_PAN_DEFAULT = true,        -- Default preserve pan state
    PRESERVE_VOLUME_DEFAULT = true,     -- Default preserve volume state
    PRESERVE_PITCH_DEFAULT = true,      -- Default preserve pitch/stretch state
    -- Export methods
    METHOD_CURRENT_TRACK = 0,           -- Place on existing container track
    METHOD_NEW_TRACK = 1,               -- Create new track for export
    METHOD_DEFAULT = 0,                 -- Default export method
    -- Region Creation
    CREATE_REGIONS_DEFAULT = false,     -- Default state for region creation
    REGION_PATTERN_DEFAULT = "$container", -- Default region naming pattern
    -- Pool & Loop (v2)
    MAX_POOL_ITEMS_DEFAULT = 0,         -- Default max pool items (0 = export all)
    LOOP_MODE_AUTO = "auto",            -- Auto-detect loop from container interval
    LOOP_MODE_ON = "on",                -- Force loop on
    LOOP_MODE_OFF = "off",              -- Force loop off
    LOOP_MODE_DEFAULT = "auto",         -- Default loop mode
    LOOP_ZERO_CROSSING_WINDOW = 0.05,   -- Zero crossing search window (50ms)
    -- Loop Duration & Interval (v2 - Story 3.1)
    LOOP_DURATION_MIN = 5,              -- Minimum loop duration (seconds)
    LOOP_DURATION_MAX = 300,            -- Maximum loop duration (seconds)
    LOOP_DURATION_DEFAULT = 30,         -- Default loop duration (seconds)
    LOOP_INTERVAL_MIN = -10,            -- Minimum interval (negative = overlap)
    LOOP_INTERVAL_MAX = 10,             -- Maximum interval (positive = gap)
    LOOP_INTERVAL_DEFAULT = 0,          -- Default interval (seconds)
    LOOP_MAX_ITERATIONS = 10000,        -- Safety limit for loop mode placement iterations
    LOOP_CROSSFADE_DEFAULT = 2.0,       -- Default crossfade duration (seconds) for single-item seamless loops
    -- Multichannel Export Mode (Story 5.2)
    MULTICHANNEL_EXPORT_MODE_FLATTEN = "flatten",   -- All items on first child track
    MULTICHANNEL_EXPORT_MODE_PRESERVE = "preserve",  -- Distribute items across child tracks
    MULTICHANNEL_EXPORT_MODE_DEFAULT = "flatten",    -- Default mode for multichannel containers
}

return Constants