#pragma once
#include <stdint.h>
#include <stdbool.h>

/*
 * PWM signal decoder for HCS-family rolling-code transmitters.
 *
 * Signal format (all timings in microseconds):
 *   Preamble : 12 alternating pulses, each ~TE wide
 *   Header   : ~10*TE gap (guard time separating preamble from data)
 *   Data     : 66 bits, each = 3*TE
 *                "0" → 1*TE pulse + 2*TE gap
 *                "1" → 2*TE pulse + 1*TE gap
 *
 * TE varies by crystal; typical values:
 *   455 kHz resonator → TE ≈ 400 µs
 *   Variable oscillator → 200–600 µs
 *
 * Timing tolerance: ±35% of TE.
 */

#define HCS_BITS          66
#define HCS_PREAMBLE_LEN  12
#define HCS_TE_MIN_US     100
#define HCS_TE_MAX_US     800
#define HCS_TOLERANCE     35   /* percent */

typedef struct {
    /* Raw timing stream: positive = pulse, negative = gap (µs) */
    const int32_t* timings;
    uint32_t       count;
} RawSignal;

typedef struct {
    uint8_t  bits[9]; /* 66 bits packed MSB-first into 9 bytes */
    uint32_t te_us;   /* estimated TE in microseconds */
    bool     valid;
} DecodedFrame;

/**
 * Scan a timing stream for HCS preamble patterns and decode the
 * first complete 66-bit data frame found.
 *
 * @param sig   Input raw timing stream
 * @param out   Decoded frame output
 * @return true if a valid frame was found
 */
bool signal_decode_hcs(const RawSignal* sig, DecodedFrame* out);

/**
 * Parse a Flipper Sub-GHz RAW file buffer into a RawSignal.
 * The buffer must contain only the RAW_Data line values (space-separated ints).
 *
 * @param data_str  Null-terminated string of space-separated timing values
 * @param timings   Caller-supplied array to fill
 * @param max_count Capacity of timings[]
 * @return Number of timing values parsed
 */
uint32_t signal_parse_raw_line(const char* data_str,
                               int32_t*    timings,
                               uint32_t    max_count);
