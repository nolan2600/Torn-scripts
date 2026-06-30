#include "signal_decoder.h"
#include <stdlib.h>
#include <string.h>

/* Return absolute value of a timing (strip sign/direction) */
static inline uint32_t abs_t(int32_t v) {
    return v < 0 ? (uint32_t)(-v) : (uint32_t)v;
}

/* Check if a timing value is within ±tol% of expected */
static inline bool in_range(uint32_t val, uint32_t expected, uint32_t tol_pct) {
    uint32_t margin = expected * tol_pct / 100u;
    return val >= (expected - margin) && val <= (expected + margin);
}

/* Set bit N (0 = MSB) in packed byte array */
static inline void set_bit(uint8_t* bytes, uint32_t n, uint8_t val) {
    uint32_t byte_idx = n / 8;
    uint32_t bit_pos  = 7u - (n % 8u);
    if(val)
        bytes[byte_idx] |= (uint8_t)(1u << bit_pos);
    else
        bytes[byte_idx] &= (uint8_t)~(1u << bit_pos);
}

bool signal_decode_hcs(const RawSignal* sig, DecodedFrame* out) {
    if(!sig || !out || sig->count < (HCS_PREAMBLE_LEN * 2 + HCS_BITS * 2))
        return false;

    memset(out, 0, sizeof(*out));

    const int32_t* t = sig->timings;
    uint32_t       n = sig->count;

    for(uint32_t start = 0; start + HCS_PREAMBLE_LEN * 2 + HCS_BITS * 2 < n; start++) {

        /* --- Preamble detection ---
         * Look for HCS_PREAMBLE_LEN consecutive pairs of equal-length timings
         * (alternating pulse/gap each ≈ TE).
         */
        if(t[start] <= 0) continue; /* preamble starts with a pulse */

        uint32_t te = abs_t(t[start]);
        if(te < HCS_TE_MIN_US || te > HCS_TE_MAX_US) continue;

        bool preamble_ok = true;
        for(uint32_t p = 0; p < HCS_PREAMBLE_LEN * 2; p++) {
            if(!in_range(abs_t(t[start + p]), te, HCS_TOLERANCE)) {
                preamble_ok = false;
                break;
            }
        }
        if(!preamble_ok) continue;

        /* --- Header gap (≥ 4*TE gap after preamble) --- */
        uint32_t after_preamble = start + HCS_PREAMBLE_LEN * 2;
        if(t[after_preamble] >= 0) continue; /* must be a gap */
        if(abs_t(t[after_preamble]) < te * 3u) continue;

        /* --- Data decoding ---
         * Each bit occupies two timings (pulse + gap) totalling 3*TE.
         * "0": 1*TE pulse, 2*TE gap
         * "1": 2*TE pulse, 1*TE gap
         */
        uint32_t data_start = after_preamble + 1;
        if(data_start + HCS_BITS * 2 > n) continue;

        bool data_ok = true;
        for(uint32_t b = 0; b < HCS_BITS; b++) {
            int32_t pulse = t[data_start + b * 2];
            int32_t gap   = t[data_start + b * 2 + 1];

            if(pulse <= 0 || gap >= 0) { data_ok = false; break; }

            uint32_t p_us = abs_t(pulse);
            uint32_t g_us = abs_t(gap);
            uint32_t bit_val;

            if(in_range(p_us, te, HCS_TOLERANCE) &&
               in_range(g_us, te * 2u, HCS_TOLERANCE)) {
                bit_val = 0;
            } else if(in_range(p_us, te * 2u, HCS_TOLERANCE) &&
                      in_range(g_us, te, HCS_TOLERANCE)) {
                bit_val = 1;
            } else {
                data_ok = false;
                break;
            }
            set_bit(out->bits, b, (uint8_t)bit_val);
        }

        if(data_ok) {
            out->te_us = te;
            out->valid = true;
            return true;
        }
    }

    return false;
}

uint32_t signal_parse_raw_line(const char* data_str,
                               int32_t*    timings,
                               uint32_t    max_count) {
    if(!data_str || !timings || max_count == 0) return 0;

    uint32_t count = 0;
    const char* p  = data_str;
    char* end;

    while(*p && count < max_count) {
        /* Skip whitespace */
        while(*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') p++;
        if(*p == '\0') break;

        long val = strtol(p, &end, 10);
        if(end == p) break; /* no more numbers */
        timings[count++] = (int32_t)val;
        p = end;
    }
    return count;
}
