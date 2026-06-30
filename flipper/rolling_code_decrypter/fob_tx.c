#include "fob_tx.h"
#include "gm_protocol.h"
#include "fob_state.h"

#include <furi.h>
#include <furi_hal_subghz.h>
#include <furi_hal_gpio.h>

#include <string.h>
#include <stdio.h>

/* ------------------------------------------------------------------ */
/* Sub-GHz HAL wrappers                                                 */
/* ------------------------------------------------------------------ */

/*
 * The Flipper Sub-GHz TX API at the HAL level:
 *
 *   furi_hal_subghz_reset()
 *   furi_hal_subghz_load_preset(FuriHalSubGhzPreset)
 *   furi_hal_subghz_set_frequency_and_path(uint32_t hz)
 *   furi_hal_subghz_tx()            — put CC1101 in TX mode
 *   furi_hal_subghz_async_tx_start(SubGhzDeviceAsyncTxCallback, void*)
 *   furi_hal_subghz_async_tx_stop()
 *   furi_hal_subghz_idle()
 *
 * The async TX callback fills a DMA buffer with timing values (µs).
 * For simplicity we use a synchronous busy-wait approach here, which
 * is acceptable for short (<500 ms) transmissions.
 */

/* State shared between main function and (future) async callback */
typedef struct {
    const GmRawFrame* frame;
    uint32_t          idx;
    bool              done;
} TxCtx;

/*
 * Synchronous OOK transmission using GPIO bit-banging.
 *
 * The CC1101 in OOK mode gates its carrier on the GDO0 signal.
 * We drive GDO0 directly from the MCU to produce the desired timing.
 *
 * Accuracy: furi_delay_us has jitter of a few µs at most, which is
 * well within the ±40% timing tolerance of GM's BCM receiver.
 */
static bool tx_raw_sync(const GmRawFrame* raw_frame, uint32_t frequency_hz) {
    furi_hal_subghz_reset();
    furi_hal_subghz_load_preset(FuriHalSubGhzPresetOok270Async);
    furi_hal_subghz_set_frequency_and_path(frequency_hz);

    furi_hal_subghz_tx();

    for(uint32_t i = 0; i < raw_frame->count; i++) {
        int32_t t = raw_frame->timings[i];
        if(t > 0) {
            /* Carrier on */
            furi_hal_subghz_set_async_mirror_pin(&gpio_ext_pc3);
            furi_hal_gpio_write(&gpio_ext_pc3, true);
            furi_delay_us((uint32_t)t);
        } else {
            /* Carrier off */
            furi_hal_gpio_write(&gpio_ext_pc3, false);
            furi_delay_us((uint32_t)(-t));
        }
    }

    /* Ensure carrier ends low */
    furi_hal_gpio_write(&gpio_ext_pc3, false);
    furi_hal_subghz_idle();
    return true;
}

/* ------------------------------------------------------------------ */
/* Public API                                                           */
/* ------------------------------------------------------------------ */

bool fob_tx_raw(const GmRawFrame* frame, uint32_t frequency_hz) {
    if(!frame || frame->count == 0) return false;
    return tx_raw_sync(frame, frequency_hz);
}

void fob_tx_press(FobState* state, FobButton button, FobTxResult* result) {
    if(!state || !result) return;

    memset(result, 0, sizeof(*result));

    if(!state->valid) {
        snprintf(result->error_msg, sizeof(result->error_msg),
                 "Fob not programmed");
        return;
    }

    GmRawFrame encoded;
    uint64_t   frame_word = gm_frame_build(state, button);
    gm_frame_encode(frame_word, state->protocol, &encoded);

    for(uint32_t rep = 0; rep < FOB_TX_REPEAT_COUNT; rep++) {
        if(!tx_raw_sync(&encoded, state->frequency_hz)) {
            snprintf(result->error_msg, sizeof(result->error_msg),
                     "TX failed at repeat %lu", (unsigned long)rep);
            return;
        }
        result->frames_sent++;
        if(rep < FOB_TX_REPEAT_COUNT - 1)
            furi_delay_ms(FOB_TX_REPEAT_DELAY);
    }

    /* Persist incremented counter */
    if(!fob_state_bump_counter(state, button)) {
        snprintf(result->error_msg, sizeof(result->error_msg),
                 "Counter save failed");
        /* TX succeeded even if save failed — don't report as TX failure */
    }

    result->success = true;
}

bool fob_tx_program_bcm(FobState* state) {
    if(!state) return false;

    /*
     * BCM programming mode: transmit a single LOCK frame.
     * The BCM in learn mode accepts any well-formed frame and stores
     * the serial number, then syncs its counter to whatever value
     * it receives (typically 0 for a new fob).
     *
     * Do NOT increment the counter — the BCM will set its window
     * to [counter .. counter+256], so we want the first real press
     * (counter = 0) to be within that window.
     *
     * Transmit 3 times to ensure the BCM sees at least one frame
     * cleanly.
     */
    GmRawFrame encoded;
    uint64_t   frame_word = gm_frame_build(state, FobButtonLock);
    gm_frame_encode(frame_word, state->protocol, &encoded);

    bool ok = true;
    for(uint32_t rep = 0; rep < 3; rep++) {
        ok = tx_raw_sync(&encoded, state->frequency_hz);
        if(!ok) break;
        furi_delay_ms(100);
    }

    return ok;
}
