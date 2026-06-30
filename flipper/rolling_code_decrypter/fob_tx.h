#pragma once
#include <stdint.h>
#include <stdbool.h>
#include "fob_state.h"
#include "gm_protocol.h"

/*
 * Sub-GHz transmitter wrapper.
 *
 * Wraps the Flipper Sub-GHz HAL to transmit a GmRawFrame at the
 * fob's configured frequency.  Requires Unleashed firmware — stock
 * firmware blocks 315 MHz TX.
 *
 * Transmission sequence:
 *   1. Build frame  (gm_frame_build)
 *   2. Encode frame (gm_frame_encode) → PWM timing stream
 *   3. Configure Sub-GHz radio at fob->frequency_hz with OOK preset
 *   4. Transmit timing stream via furi_hal_subghz_*
 *   5. Increment + persist counter (fob_state_bump_counter)
 *
 * Note on transmission count:
 *   Real key fobs transmit each button press 3–4 times in rapid succession
 *   (typically 3 repeats at ~100 ms intervals).  The BCM only needs one
 *   valid frame, but multiple sends improve reliability in noisy environments.
 */

#define FOB_TX_REPEAT_COUNT  3u   /* frames per button press */
#define FOB_TX_REPEAT_DELAY  100u /* ms between repeats      */

typedef struct {
    bool     success;
    uint32_t frames_sent;
    char     error_msg[64];
} FobTxResult;

/**
 * Transmit one button press.
 * Builds the frame, encodes it, transmits FOB_TX_REPEAT_COUNT times,
 * then increments and saves the counter.
 *
 * @param state   Fob state (must be valid and programmed into BCM)
 * @param button  Which button to press
 * @param result  Output — success flag and diagnostic info
 */
void fob_tx_press(FobState* state, FobButton button, FobTxResult* result);

/**
 * Transmit a raw GmRawFrame without modifying fob state.
 * Used for the BCM programming step (sends the frame once to teach
 * the BCM the serial, without incrementing the day-to-day counter).
 */
bool fob_tx_raw(const GmRawFrame* frame, uint32_t frequency_hz);

/**
 * Run the BCM programming sequence:
 *   - Transmits the LOCK code once to initiate learning
 *   - Returns true if transmission succeeded
 *   - Does NOT increment counter (counter stays at 0 for first real press)
 *
 * User must have already entered BCM programming mode via ignition
 * sequence or scan tool before calling this.
 */
bool fob_tx_program_bcm(FobState* state);
