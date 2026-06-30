#pragma once
#include <stdint.h>
#include <stdbool.h>
#include "hcs_protocol.h"
#include "fob_state.h"

/* Maximum number of .sub files shown in the file-list screen */
#define RC_MAX_FILES   32
#define RC_PATH_LEN   128
#define RC_RESULT_LEN 512

typedef enum {
    AppStateMenu = 0,
    AppStateFileList,
    AppStateLoading,
    AppStateResult,
    AppStateKeyList,
    AppStateFobMain,       /* "My Fob" transmit screen          */
    AppStateFobProgram,    /* BCM programming wizard            */
    AppStateFobCapture,    /* Capture an existing fob's signal  */
    AppStateAbout,
} AppState;

typedef struct {
    /* --- UI state --- */
    AppState state;
    uint8_t  menu_cursor;      /* which menu item is highlighted */
    uint8_t  file_cursor;      /* which file is highlighted */
    uint8_t  file_count;       /* number of .sub files found */
    uint8_t  key_cursor;       /* which known-key is highlighted */
    uint8_t  result_scroll;    /* line offset for result text */
    uint8_t  program_step;     /* step in BCM programming wizard */

    /* --- File list --- */
    char files[RC_MAX_FILES][RC_PATH_LEN];

    /* --- Decoded frame (analysis mode) --- */
    HCSFrame      frame;
    bool          frame_valid;

    /* --- Decryption state --- */
    bool          decrypted;
    HCSPlaintext  plaintext;

    /* --- Fob (transmitter) state --- */
    FobState      fob;
    char          tx_status[64]; /* last TX result message */

    /* --- Display buffer --- */
    char result_text[RC_RESULT_LEN];
    char status_msg[64];
} RollingCodeApp;

/* Menu item labels */
static const char* const MENU_ITEMS[] = {
    "My Fob (TX)",
    "Program BCM",
    "Capture Fob Signal",
    "Decode .sub File",
    "Try Known Keys",
    "About",
};
#define MENU_ITEM_COUNT 6

/* BCM programming wizard step labels */
static const char* const PROGRAM_STEPS[] = {
    "Step 1/4: Close all\ndoors. Key in ignition.",
    "Step 2/4: Hold door\nLOCK button...",
    "Step 3/4: Cycle key\nOFF->RUN x5 (10s).\nRelease LOCK.\nDoors lock = ready.",
    "Step 4/4: Press OK\nto transmit fob ID\nto BCM now.",
};
#define PROGRAM_STEP_COUNT 4

/* Entry point declared for application.fam */
int32_t rolling_code_app(void* p);
