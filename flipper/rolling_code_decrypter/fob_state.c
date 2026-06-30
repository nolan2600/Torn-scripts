#include "fob_state.h"
#include "gm_protocol.h"

#include <furi.h>
#include <storage/storage.h>
#include <flipper_format/flipper_format.h>
#include <furi_string.h>

#include <string.h>
#include <stdio.h>

static const char* FOB_FILETYPE = "Flipper Rolling Fob State";
static const uint32_t FOB_VERSION = 1;

bool fob_state_load(FobState* state) {
    if(!state) return false;

    Storage*       storage = furi_record_open(RECORD_STORAGE);
    FlipperFormat* ff      = flipper_format_buffered_file_alloc(storage);
    FuriString*    str     = furi_string_alloc();
    bool           ok      = false;

    do {
        if(!flipper_format_buffered_file_open_existing(ff, FOB_STATE_PATH)) break;

        uint32_t version = 0;
        if(!flipper_format_read_header(ff, str, &version)) break;
        if(furi_string_cmp_str(str, FOB_FILETYPE) != 0) break;

        uint32_t tmp32 = 0;
        if(!flipper_format_read_uint32(ff, "Serial", &tmp32, 1)) break;
        state->serial = tmp32;

        uint32_t key_hi = 0, key_lo = 0;
        if(!flipper_format_read_uint32(ff, "KeyHi", &key_hi, 1)) break;
        if(!flipper_format_read_uint32(ff, "KeyLo", &key_lo, 1)) break;
        state->device_key = ((uint64_t)key_hi << 32) | key_lo;

        if(!flipper_format_read_uint32(ff, "Frequency", &tmp32, 1)) break;
        state->frequency_hz = tmp32;

        if(!flipper_format_read_uint32(ff, "Protocol", &tmp32, 1)) break;
        state->protocol = (uint8_t)tmp32;

        /* Read per-button counters */
        uint32_t counters[FOB_MAX_BUTTONS] = {0};
        if(!flipper_format_read_uint32(ff, "Counters", counters, FOB_MAX_BUTTONS)) break;
        for(int i = 0; i < FOB_MAX_BUTTONS; i++)
            state->counter[i] = counters[i];

        state->valid = true;
        ok = true;
    } while(false);

    furi_string_free(str);
    flipper_format_free(ff);
    furi_record_close(RECORD_STORAGE);
    return ok;
}

bool fob_state_save(const FobState* state) {
    if(!state) return false;

    Storage*       storage = furi_record_open(RECORD_STORAGE);
    FlipperFormat* ff      = flipper_format_buffered_file_alloc(storage);
    bool           ok      = false;

    do {
        if(!flipper_format_buffered_file_open_always(ff, FOB_STATE_PATH)) break;
        if(!flipper_format_write_header_cstr(ff, FOB_FILETYPE, FOB_VERSION)) break;

        uint32_t tmp = state->serial;
        if(!flipper_format_write_uint32(ff, "Serial", &tmp, 1)) break;

        uint32_t key_hi = (uint32_t)(state->device_key >> 32);
        uint32_t key_lo = (uint32_t)(state->device_key & 0xFFFFFFFFu);
        if(!flipper_format_write_uint32(ff, "KeyHi", &key_hi, 1)) break;
        if(!flipper_format_write_uint32(ff, "KeyLo", &key_lo, 1)) break;

        tmp = state->frequency_hz;
        if(!flipper_format_write_uint32(ff, "Frequency", &tmp, 1)) break;

        tmp = state->protocol;
        if(!flipper_format_write_uint32(ff, "Protocol", &tmp, 1)) break;

        uint32_t counters[FOB_MAX_BUTTONS];
        for(int i = 0; i < FOB_MAX_BUTTONS; i++)
            counters[i] = state->counter[i];
        if(!flipper_format_write_uint32(ff, "Counters", counters, FOB_MAX_BUTTONS)) break;

        ok = true;
    } while(false);

    flipper_format_free(ff);
    furi_record_close(RECORD_STORAGE);
    return ok;
}

void fob_state_init_gm(FobState* state, uint32_t serial) {
    memset(state, 0, sizeof(*state));
    state->serial       = serial & 0x0FFFFFFFu; /* 28-bit */
    state->frequency_hz = 315000000u;
    state->protocol     = FOB_PROTOCOL_GM_OUC;
    state->device_key   = 0; /* set after BCM programming + key derivation */
    state->valid        = false;
}

bool fob_state_bump_counter(FobState* state, FobButton button) {
    if(!state || button >= FOB_MAX_BUTTONS) return false;
    state->counter[button]++;
    return fob_state_save(state);
}
