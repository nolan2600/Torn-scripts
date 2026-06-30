#pragma once
#include <stdint.h>
#include <stdbool.h>

/*
 * Persistent fob state saved to SD card.
 * The counter MUST survive reboots — if it resets to 0 while the BCM
 * has advanced its window, the Flipper fob will be desynced.
 *
 * File location: SD:/subghz/rolling_fob.ini
 */

#define FOB_STATE_PATH "EXT:/subghz/rolling_fob.ini"
#define FOB_MAX_BUTTONS 4

typedef enum {
    FobButtonLock   = 0,
    FobButtonUnlock = 1,
    FobButtonPanic  = 2,
    FobButtonTrunk  = 3,
} FobButton;

typedef struct {
    /* Identity */
    uint32_t serial;       /* 28-bit device serial programmed into BCM */
    uint64_t device_key;   /* 64-bit encryption key (0 = unknown/unencrypted) */

    /* Rolling state — one counter per button channel */
    uint32_t counter[FOB_MAX_BUTTONS];

    /* Protocol parameters */
    uint32_t frequency_hz; /* e.g. 315000000 */
    uint8_t  protocol;     /* see FobProtocol enum in gm_protocol.h */

    bool     valid;        /* false until successfully saved/loaded */
} FobState;

/**
 * Load fob state from SD card.
 * Returns false if file doesn't exist or is corrupt.
 */
bool fob_state_load(FobState* state);

/**
 * Save fob state to SD card.
 * Call after every counter increment.
 */
bool fob_state_save(const FobState* state);

/**
 * Initialise a new fob state with sane defaults for a GM 315 MHz device.
 * Does NOT save — call fob_state_save() after programming.
 */
void fob_state_init_gm(FobState* state, uint32_t serial);

/** Increment the counter for a given button and save. */
bool fob_state_bump_counter(FobState* state, FobButton button);
