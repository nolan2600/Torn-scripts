#include "gm_protocol.h"
#include <string.h>
#include <stdio.h>

/* ------------------------------------------------------------------ */
/* Internal helpers                                                     */
/* ------------------------------------------------------------------ */

static inline uint32_t te_for_protocol(uint8_t protocol) {
    return (protocol == FOB_PROTOCOL_GM_KOBT) ? GM_KOBT_TE_US : GM_OUC_TE_US;
}

static inline uint32_t preamble_for_protocol(uint8_t protocol) {
    return (protocol == FOB_PROTOCOL_GM_KOBT)
               ? GM_KOBT_PREAMBLE_PULSES
               : GM_OUC_PREAMBLE_PULSES;
}

/* ------------------------------------------------------------------ */
/* Frame builder                                                        */
/* ------------------------------------------------------------------ */

uint64_t gm_frame_build(const FobState* state, FobButton button) {
    /*
     * 40-bit GM frame:
     *   [39:12] = serial (28 bits)
     *   [11:8]  = button code (4 bits)
     *   [7:0]   = rolling counter low byte
     *
     * TODO: apply GM counter transform here once the exact cipher is
     * confirmed from a capture comparison.  For now the counter byte
     * is transmitted as-is; this is sufficient for BCM programming
     * mode (where the BCM doesn't verify the counter) and may work
     * for normal operation depending on the BCM revision.
     */
    uint8_t  btn_code    = (uint8_t)(1u << (uint8_t)button);
    uint8_t  counter_lo  = (uint8_t)(state->counter[button] & 0xFFu);

    uint64_t frame =
        ((uint64_t)(state->serial & 0x0FFFFFFFu) << 12) |
        ((uint64_t)(btn_code & 0x0Fu) << 8) |
        (uint64_t)counter_lo;

    return frame;
}

/* ------------------------------------------------------------------ */
/* PWM encoder                                                          */
/* ------------------------------------------------------------------ */

void gm_frame_encode(uint64_t frame, uint8_t protocol, GmRawFrame* out) {
    uint32_t te        = te_for_protocol(protocol);
    uint32_t preamble  = preamble_for_protocol(protocol);
    uint32_t sync_low  = GM_OUC_SYNC_LOW_TE; /* same for both variants */
    uint32_t guard_low = GM_OUC_GUARD_TE;

    uint32_t idx = 0;

    /* Preamble: alternating TE pulses and gaps */
    for(uint32_t i = 0; i < preamble; i++) {
        out->timings[idx++] =  (int32_t)te;  /* pulse */
        out->timings[idx++] = -(int32_t)te;  /* gap   */
    }

    /* Sync gap */
    out->timings[idx++] = -(int32_t)(te * sync_low);

    /* Data bits MSB first */
    for(int bit = (int)(GM_FRAME_BITS - 1); bit >= 0; bit--) {
        uint32_t b = (uint32_t)((frame >> (uint32_t)bit) & 1u);
        if(b == 0) {
            /* "0": 1×TE pulse + 2×TE gap */
            out->timings[idx++] =  (int32_t)te;
            out->timings[idx++] = -(int32_t)(te * 2u);
        } else {
            /* "1": 2×TE pulse + 1×TE gap */
            out->timings[idx++] =  (int32_t)(te * 2u);
            out->timings[idx++] = -(int32_t)te;
        }
    }

    /* Guard / inter-frame gap */
    out->timings[idx++] = -(int32_t)(te * guard_low);

    out->count = idx;
}

/* ------------------------------------------------------------------ */
/* PWM decoder                                                          */
/* ------------------------------------------------------------------ */

static inline bool in_range_gm(int32_t v, uint32_t expected, uint32_t tol_pct) {
    uint32_t u   = v < 0 ? (uint32_t)(-v) : (uint32_t)v;
    uint32_t mar = expected * tol_pct / 100u;
    return u >= (expected - mar) && u <= (expected + mar);
}

bool gm_frame_decode(const int32_t* timings, uint32_t count,
                     uint8_t protocol, uint64_t* frame_out) {
    if(!timings || !frame_out || count < GM_FRAME_BITS * 2u) return false;

    uint32_t te       = te_for_protocol(protocol);
    uint32_t preamble = preamble_for_protocol(protocol);

    for(uint32_t start = 0; start + preamble * 2u + GM_FRAME_BITS * 2u < count; start++) {
        /* Look for preamble: N alternating pulses of ~TE */
        if(timings[start] <= 0) continue;
        uint32_t te_meas = (uint32_t)timings[start];
        if(te_meas < 50u || te_meas > 1000u) continue;

        bool preamble_ok = true;
        for(uint32_t p = 0; p < preamble * 2u; p++) {
            if(!in_range_gm(timings[start + p], te_meas, 40u)) {
                preamble_ok = false;
                break;
            }
        }
        if(!preamble_ok) continue;

        /* Sync gap — must be a large negative timing */
        uint32_t after = start + preamble * 2u;
        if(timings[after] >= 0) continue;
        if((uint32_t)(-timings[after]) < te_meas * 3u) continue;

        uint32_t data_start = after + 1u;
        if(data_start + GM_FRAME_BITS * 2u > count) continue;

        uint64_t frame   = 0;
        bool     data_ok = true;

        for(uint32_t b = 0; b < GM_FRAME_BITS; b++) {
            int32_t pulse = timings[data_start + b * 2u];
            int32_t gap   = timings[data_start + b * 2u + 1u];
            if(pulse <= 0 || gap >= 0) { data_ok = false; break; }

            uint32_t pu = (uint32_t)pulse;
            uint32_t gu = (uint32_t)(-gap);

            frame <<= 1;
            if(in_range_gm((int32_t)pu, te_meas, 40u) &&
               in_range_gm((int32_t)gu, te_meas * 2u, 40u)) {
                /* "0" bit */
            } else if(in_range_gm((int32_t)pu, te_meas * 2u, 40u) &&
                      in_range_gm((int32_t)gu, te_meas, 40u)) {
                frame |= 1u; /* "1" bit */
            } else {
                data_ok = false;
                break;
            }
            (void)gu;
        }

        if(data_ok) {
            *frame_out = frame;
            return true;
        }
    }
    return false;
}

/* ------------------------------------------------------------------ */
/* Field extraction and formatting                                      */
/* ------------------------------------------------------------------ */

void gm_frame_parse(uint64_t frame, uint32_t* serial,
                    uint8_t* button, uint8_t* counter_lo) {
    if(serial)     *serial     = (uint32_t)((frame >> 12) & 0x0FFFFFFFu);
    if(button)     *button     = (uint8_t)((frame >> 8) & 0x0Fu);
    if(counter_lo) *counter_lo = (uint8_t)(frame & 0xFFu);
}

void gm_frame_format(uint64_t frame, char* buf, uint32_t buf_size) {
    uint32_t serial;
    uint8_t  button, counter_lo;
    gm_frame_parse(frame, &serial, &button, &counter_lo);

    const char* btn_name = "?";
    switch(button) {
    case 0x1: btn_name = "Lock";   break;
    case 0x2: btn_name = "Unlock"; break;
    case 0x4: btn_name = "Trunk";  break;
    case 0x8: btn_name = "Panic";  break;
    }

    snprintf(buf, buf_size,
             "Protocol: GM OUC\n"
             "Serial:   %07lX\n"
             "Button:   %s (%X)\n"
             "Counter:  %02X",
             (unsigned long)serial, btn_name, button, counter_lo);
}
