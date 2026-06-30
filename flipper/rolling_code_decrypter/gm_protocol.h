#pragma once
#include <stdint.h>
#include <stdbool.h>
#include "fob_state.h"

/*
 * GM keyless entry rolling-code protocol — 2007+ GMT900 platform
 * (Silverado/Sierra/Tahoe/Yukon/Suburban — OUC60270 family fobs)
 *
 * Physical layer
 * ─────────────
 * Frequency  : 315.000 MHz
 * Modulation : OOK (On-Off Keying / AM)
 * Encoding   : Pulse-Width Modulation (PWM), similar to HCS but different TE
 *
 * Timing (µs) — derived from FCC test scope captures of OUC60270:
 *   TE         ≈ 200 µs  (short element)
 *   Preamble   : 18 × TE alternating pulses
 *   Sync gap   : 10 × TE low
 *   "0" bit    : 1×TE high + 2×TE low  (600 µs total)
 *   "1" bit    : 2×TE high + 1×TE low  (600 µs total)
 *   Guard      : ≥ 20×TE low after last bit
 *
 * NOTE: These timings are derived from FCC test-report scope captures and
 * community captures of OUC60270 fobs.  Verify with a RAW Sub-GHz capture
 * before relying on them.  The TE for KOBGT04A (GMT800 fobs) is closer to
 * 400 µs — different chip, different timing.
 *
 * Frame structure (40 bits, MSB first)
 * ─────────────────────────────────────
 *  [39:12] = 28-bit fixed serial (programmed into BCM)
 *  [11:8]  = 4-bit button code
 *  [7:0]   = 8-bit rolling counter (low byte of full counter)
 *
 * The full counter is 32 bits internally, but only the low 8 bits are
 * transmitted.  The BCM maintains the high bits and accepts codes within
 * a ±256 window.
 *
 * Button codes (bitmask — multiple buttons can be held):
 *   Lock   = 0x1
 *   Unlock = 0x2
 *   Trunk  = 0x4
 *   Panic  = 0x8
 *
 * IMPORTANT CAVEAT
 * ─────────────────
 * GM's exact rolling code encryption for this platform has not been fully
 * published.  The counter byte may be passed through a simple transform
 * (XOR, addition) or a proprietary cipher.  The fields above are based on
 * analysis of captured signals; the exact counter-encryption step is marked
 * TODO and should be confirmed by comparing Flipper capture output against
 * a known-good fob transmission.
 *
 * In BCM programming mode the receiver accepts any serial + counter during
 * the learn window, so the encryption is not required for the initial
 * programming step.
 */

/* Protocol identifiers stored in FobState */
#define FOB_PROTOCOL_GM_OUC   0x01  /* OUC60270 — 2007+ GMT900          */
#define FOB_PROTOCOL_GM_KOBT  0x02  /* KOBGT04A — 2003–2006 GMT800       */
#define FOB_PROTOCOL_HCS301   0x03  /* Generic KeeLoq / HCS301           */

/* Timing constants in µs for FOB_PROTOCOL_GM_OUC */
#define GM_OUC_TE_US          200u
#define GM_OUC_PREAMBLE_PULSES 18u
#define GM_OUC_SYNC_LOW_TE   10u
#define GM_OUC_GUARD_TE      20u

/* Timing constants for FOB_PROTOCOL_GM_KOBT (older trucks) */
#define GM_KOBT_TE_US         400u
#define GM_KOBT_PREAMBLE_PULSES 12u

#define GM_FRAME_BITS         40u

typedef struct {
    /* Pulse/gap timing array — sized for worst case:
     * preamble (2 * 18) + sync (1) + data (2 * 40) + guard (1) = 118 entries */
    int32_t  timings[128];
    uint32_t count;
} GmRawFrame;

/**
 * Build the 40-bit GM frame word from fob state + button.
 * @param state   Current fob state (serial, counter)
 * @param button  Button being pressed
 * @return        40-bit frame (bits 39..0)
 */
uint64_t gm_frame_build(const FobState* state, FobButton button);

/**
 * Encode a 40-bit frame into a PWM timing stream ready for Sub-GHz TX.
 * Timings are in µs; positive = pulse (TX on), negative = gap (TX off).
 */
void gm_frame_encode(uint64_t frame, uint8_t protocol, GmRawFrame* out);

/**
 * Decode a raw timing stream back into a 40-bit frame word.
 * Returns false if no valid GM frame is found in the stream.
 */
bool gm_frame_decode(const int32_t* timings, uint32_t count,
                     uint8_t protocol, uint64_t* frame_out);

/** Extract fields from a decoded 40-bit frame. */
void gm_frame_parse(uint64_t frame, uint32_t* serial,
                    uint8_t* button, uint8_t* counter_lo);

/** Format a decoded frame as a human-readable string. */
void gm_frame_format(uint64_t frame, char* buf, uint32_t buf_size);
