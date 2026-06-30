#pragma once
#include <stdint.h>
#include <stdbool.h>
#include "hcs_protocol.h"

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

    /* --- File list --- */
    char files[RC_MAX_FILES][RC_PATH_LEN];

    /* --- Decoded frame --- */
    HCSFrame      frame;
    bool          frame_valid;

    /* --- Decryption state --- */
    bool          decrypted;
    HCSPlaintext  plaintext;

    /* --- Display buffer --- */
    char result_text[RC_RESULT_LEN];
    char status_msg[64];
} RollingCodeApp;

/* Menu item labels */
static const char* const MENU_ITEMS[] = {
    "Decode .sub File",
    "Try Known Keys",
    "About",
};
#define MENU_ITEM_COUNT 3

/* Entry point declared for application.fam */
int32_t rolling_code_app(void* p);
