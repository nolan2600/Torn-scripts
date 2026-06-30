#include "rolling_code_app.h"
#include "keeloq.h"
#include "hcs_protocol.h"
#include "signal_decoder.h"
#include "known_keys.h"
#include "gm_protocol.h"
#include "fob_state.h"
#include "fob_tx.h"

#include <furi.h>
#include <gui/gui.h>
#include <gui/view_port.h>
#include <gui/canvas.h>
#include <gui/elements.h>
#include <input/input.h>
#include <storage/storage.h>
#include <flipper_format/flipper_format.h>
#include <furi_hal_subghz.h>

#include <string.h>
#include <stdio.h>
#include <stdlib.h>

/* ------------------------------------------------------------------ */
/* Helpers                                                              */
/* ------------------------------------------------------------------ */

#define SUBGHZ_DIR "EXT:/subghz"

static bool app_scan_files(RollingCodeApp* app) {
    Storage*  storage = furi_record_open(RECORD_STORAGE);
    File*     dir     = storage_file_alloc(storage);
    FileInfo  fi;
    char      fname[64];

    app->file_count = 0;

    if(!storage_dir_open(dir, SUBGHZ_DIR)) {
        storage_file_free(dir);
        furi_record_close(RECORD_STORAGE);
        return false;
    }

    while(storage_dir_read(dir, &fi, fname, sizeof(fname))) {
        if(fi.flags & FSF_DIRECTORY) continue;
        /* Only show .sub files */
        uint32_t len = (uint32_t)strlen(fname);
        if(len < 5) continue;
        if(fname[len - 4] != '.' ||
           fname[len - 3] != 's' ||
           fname[len - 2] != 'u' ||
           fname[len - 1] != 'b') continue;

        if(app->file_count >= RC_MAX_FILES) break;
        snprintf(app->files[app->file_count], RC_PATH_LEN,
                 SUBGHZ_DIR "/%s", fname);
        app->file_count++;
    }

    storage_dir_close(dir);
    storage_file_free(dir);
    furi_record_close(RECORD_STORAGE);
    return app->file_count > 0;
}

/* ------------------------------------------------------------------ */
/* .sub file loader — supports both decoded KeeLoq and RAW formats     */
/* ------------------------------------------------------------------ */

/* Buffer for RAW_Data timing values (lives on heap, not stack) */
#define RAW_TIMING_MAX 4096

static bool app_load_sub_file(RollingCodeApp* app, const char* path) {
    Storage*        storage = furi_record_open(RECORD_STORAGE);
    FlipperFormat*  ff      = flipper_format_buffered_file_alloc(storage);
    bool            ok      = false;
    FuriString*     str     = furi_string_alloc();

    app->frame_valid = false;
    app->decrypted   = false;
    snprintf(app->status_msg, sizeof(app->status_msg), "Loading...");

    if(!flipper_format_buffered_file_open_existing(ff, path)) {
        snprintf(app->status_msg, sizeof(app->status_msg), "Cannot open file");
        goto cleanup;
    }

    /* Check filetype header */
    if(!flipper_format_read_header(ff, str, NULL)) {
        snprintf(app->status_msg, sizeof(app->status_msg), "Bad file header");
        goto cleanup;
    }

    /* --- Try KeeLoq decoded format first --- */
    if(furi_string_cmp_str(str, "Flipper SubGhz Key File") == 0) {
        FuriString* proto = furi_string_alloc();
        if(flipper_format_read_string(ff, "Protocol", proto) &&
           furi_string_cmp_str(proto, "KeeLoq") == 0) {
            uint32_t count_val = 0;
            uint64_t key_val   = 0;

            /* "Key" field holds the 66-bit raw frame packed in 8 bytes */
            uint8_t key_bytes[8] = {0};
            if(flipper_format_read_hex(ff, "Key", key_bytes, 8)) {
                for(int i = 0; i < 8; i++)
                    key_val = (key_val << 8) | key_bytes[i];
                ok = hcs_frame_unpack64(key_val, &app->frame);
            }
            flipper_format_read_uint32(ff, "Count", &count_val, 1);
            (void)count_val;
        }
        furi_string_free(proto);

    /* --- Fall back to RAW file decode --- */
    } else if(furi_string_cmp_str(str, "Flipper SubGhz RAW File") == 0) {
        FuriString* raw_line = furi_string_alloc();
        bool found_raw = false;

        /* Scan for RAW_Data line */
        while(!found_raw) {
            FuriString* key = furi_string_alloc();
            if(!flipper_format_get_value_from_file(ff, "RAW_Data", raw_line)) {
                furi_string_free(key);
                break;
            }
            furi_string_free(key);
            found_raw = true;
        }

        if(found_raw) {
            int32_t* timings = malloc(RAW_TIMING_MAX * sizeof(int32_t));
            if(timings) {
                uint32_t count = signal_parse_raw_line(
                    furi_string_get_cstr(raw_line), timings, RAW_TIMING_MAX);

                RawSignal sig   = {.timings = timings, .count = count};
                DecodedFrame df = {0};

                if(signal_decode_hcs(&sig, &df)) {
                    ok = hcs_frame_unpack(df.bits, &app->frame);
                    if(ok)
                        snprintf(app->status_msg, sizeof(app->status_msg),
                                 "RAW decoded (TE=%luus)", (unsigned long)df.te_us);
                } else {
                    snprintf(app->status_msg, sizeof(app->status_msg),
                             "No HCS frame in signal");
                }
                free(timings);
            }
        }
        furi_string_free(raw_line);
    } else {
        snprintf(app->status_msg, sizeof(app->status_msg), "Unknown file type");
    }

    if(ok) {
        app->frame_valid = true;
        hcs_frame_format(&app->frame, NULL, false,
                         app->result_text, RC_RESULT_LEN);
        snprintf(app->status_msg, sizeof(app->status_msg), "Decoded OK");
    }

cleanup:
    furi_string_free(str);
    flipper_format_free(ff);
    furi_record_close(RECORD_STORAGE);
    return ok;
}

/* ------------------------------------------------------------------ */
/* Try all known keys and fill result_text if any match looks valid    */
/* ------------------------------------------------------------------ */

static void app_try_known_keys(RollingCodeApp* app) {
    if(!app->frame_valid) {
        snprintf(app->result_text, RC_RESULT_LEN, "No frame loaded.\nLoad a .sub file first.");
        return;
    }

    char buf[RC_RESULT_LEN];
    int  offset = 0;
    bool found  = false;

    for(uint32_t i = 0; i < KNOWN_KEYS_COUNT; i++) {
        /* Try the known manufacturer key directly */
        uint32_t pt_direct = keeloq_decrypt(app->frame.ciphertext, KNOWN_KEYS[i].key);

        /* Also try the derived per-device key */
        uint64_t derived = keeloq_derive_key(KNOWN_KEYS[i].key, app->frame.serial);
        uint32_t pt_derived = keeloq_decrypt(app->frame.ciphertext, derived);

        /*
         * Validate plaintext: the top nibble of the plaintext (bits 31:28)
         * should match the transmitted button code.  This is a heuristic —
         * a matching discrimination value suggests the key is correct.
         */
        bool direct_match  = ((pt_direct  >> 28) & 0xF) == app->frame.button;
        bool derived_match = ((pt_derived >> 28) & 0xF) == app->frame.button;

        if(direct_match || derived_match) {
            uint32_t pt = direct_match ? pt_direct : pt_derived;
            HCSPlaintext plain;
            hcs_plaintext_decode(pt, &plain);

            offset += snprintf(buf + offset, sizeof(buf) - (size_t)offset,
                "[MATCH] %s\n"
                "Counter: %lu\n"
                "Fn: %X\n\n",
                KNOWN_KEYS[i].name,
                (unsigned long)plain.full_cnt,
                plain.function);
            found = true;

            /* Store the first successful decryption in app state */
            if(!app->decrypted) {
                app->decrypted = true;
                app->plaintext = plain;
                hcs_frame_format(&app->frame, &app->plaintext, true,
                                 app->result_text, RC_RESULT_LEN);
            }
        } else {
            offset += snprintf(buf + offset, sizeof(buf) - (size_t)offset,
                "[MISS]  %s\n", KNOWN_KEYS[i].name);
        }
        if((size_t)offset >= sizeof(buf) - 1) break;
    }

    if(!found) {
        offset += snprintf(buf + offset, sizeof(buf) - (size_t)offset,
            "\nNo key matched.\nAdd keys to known_keys.h");
    }

    uint32_t len = (uint32_t)strlen(buf);
    if(len >= RC_RESULT_LEN) len = RC_RESULT_LEN - 1;
    memcpy(app->result_text, buf, len);
    app->result_text[len] = '\0';
}

/* ------------------------------------------------------------------ */
/* Draw callbacks                                                       */
/* ------------------------------------------------------------------ */

#define SCREEN_W 128
#define SCREEN_H  64
#define LINE_H     10

static void draw_header(Canvas* canvas, const char* title) {
    canvas_set_font(canvas, FontPrimary);
    canvas_draw_str(canvas, 2, 10, title);
    canvas_draw_line(canvas, 0, 12, SCREEN_W, 12);
}

static void draw_scrollable_text(Canvas* canvas, const char* text,
                                  uint8_t scroll_offset) {
    canvas_set_font(canvas, FontSecondary);
    const char* p   = text;
    uint8_t     row = 0;
    char        line[32];

    while(*p) {
        /* Extract one line */
        uint8_t col = 0;
        while(*p && *p != '\n' && col < sizeof(line) - 1)
            line[col++] = *p++;
        line[col] = '\0';
        if(*p == '\n') p++;

        if(row >= scroll_offset) {
            int y = 22 + (int)(row - scroll_offset) * LINE_H;
            if(y > SCREEN_H - 2) break;
            canvas_draw_str(canvas, 2, y, line);
        }
        row++;
    }
}

static void draw_list(Canvas* canvas, const char* const* items,
                      uint8_t count, uint8_t cursor, uint8_t y_start) {
    canvas_set_font(canvas, FontSecondary);
    for(uint8_t i = 0; i < count && (y_start + i * LINE_H) < SCREEN_H; i++) {
        int y = y_start + i * LINE_H;
        if(i == cursor) {
            canvas_draw_box(canvas, 0, y - 8, SCREEN_W, LINE_H);
            canvas_invert_color(canvas);
        }
        canvas_draw_str(canvas, 2, y, items[i]);
        if(i == cursor) canvas_invert_color(canvas);
    }
}

/* ------------------------------------------------------------------ */
/* Main draw dispatch                                                   */
/* ------------------------------------------------------------------ */

static void draw_fob_main(Canvas* canvas, RollingCodeApp* app) {
    draw_header(canvas, "My Fob  315MHz");
    canvas_set_font(canvas, FontSecondary);

    if(!app->fob.valid) {
        canvas_draw_str(canvas, 2, 25, "No fob programmed.");
        canvas_draw_str(canvas, 2, 35, "Use 'Program BCM'");
        canvas_draw_str(canvas, 2, 45, "to set up first.");
        return;
    }

    char serial_str[24];
    snprintf(serial_str, sizeof(serial_str), "ID: %07lX  Cnt:%lu",
             (unsigned long)app->fob.serial,
             (unsigned long)app->fob.counter[FobButtonLock]);
    canvas_draw_str(canvas, 2, 22, serial_str);
    canvas_draw_str(canvas, 2, 34, app->tx_status[0] ? app->tx_status : "Ready");

    /* Button legend */
    canvas_draw_str(canvas, 2,  48, "Up=Lock");
    canvas_draw_str(canvas, 2,  58, "Dn=Unlock");
    canvas_draw_str(canvas, 66, 48, "L=Trunk");
    canvas_draw_str(canvas, 66, 58, "R=Panic");
}

static void draw_fob_program(Canvas* canvas, RollingCodeApp* app) {
    draw_header(canvas, "Program BCM");
    canvas_set_font(canvas, FontSecondary);

    /* Multi-line step text */
    const char* step_text = PROGRAM_STEPS[app->program_step];
    uint8_t row = 0;
    char line[32];
    const char* p = step_text;
    while(*p && row < 4) {
        uint8_t col = 0;
        while(*p && *p != '\n' && col < sizeof(line) - 1)
            line[col++] = *p++;
        line[col] = '\0';
        if(*p == '\n') p++;
        canvas_draw_str(canvas, 2, 22 + row * 10, line);
        row++;
    }

    if(app->program_step == PROGRAM_STEP_COUNT - 1) {
        /* Final step — show OK prompt */
        canvas_draw_str(canvas, 2, 58, "OK=Send  Back=Cancel");
    } else {
        canvas_draw_str(canvas, 2, 58, "OK=Next  Back=Cancel");
    }
}

static void draw_fob_capture(Canvas* canvas, RollingCodeApp* app) {
    (void)app;
    draw_header(canvas, "Capture Fob");
    canvas_set_font(canvas, FontSecondary);
    canvas_draw_str(canvas, 2, 22, "Press button on OEM");
    canvas_draw_str(canvas, 2, 32, "fob near Flipper.");
    canvas_draw_str(canvas, 2, 42, "Listening 315MHz...");
    canvas_draw_str(canvas, 2, 56, "Back=Cancel");
}

static void app_draw_cb(Canvas* canvas, void* ctx) {
    RollingCodeApp* app = ctx;
    canvas_clear(canvas);

    switch(app->state) {

    case AppStateMenu:
        draw_header(canvas, "Rolling Code");
        draw_list(canvas, MENU_ITEMS, MENU_ITEM_COUNT, app->menu_cursor, 20);
        break;

    case AppStateFobMain:
        draw_fob_main(canvas, app);
        break;

    case AppStateFobProgram:
        draw_fob_program(canvas, app);
        break;

    case AppStateFobCapture:
        draw_fob_capture(canvas, app);
        break;

    case AppStateFileList:
        draw_header(canvas, "Select .sub File");
        if(app->file_count == 0) {
            canvas_set_font(canvas, FontSecondary);
            canvas_draw_str(canvas, 2, 28, "No files in");
            canvas_draw_str(canvas, 2, 38, SUBGHZ_DIR);
        } else {
            const char* ptrs[RC_MAX_FILES];
            for(uint8_t i = 0; i < app->file_count; i++) {
                const char* slash = strrchr(app->files[i], '/');
                ptrs[i] = slash ? slash + 1 : app->files[i];
            }
            uint8_t start = app->file_cursor > 3 ? app->file_cursor - 3 : 0;
            uint8_t shown = app->file_count - start;
            if(shown > 4) shown = 4;
            draw_list(canvas, ptrs + start, shown,
                      app->file_cursor - start, 20);
        }
        break;

    case AppStateLoading:
        draw_header(canvas, "Decoding");
        canvas_set_font(canvas, FontSecondary);
        canvas_draw_str(canvas, 2, 35, app->status_msg);
        break;

    case AppStateResult:
        draw_header(canvas, app->decrypted ? "Decrypted" : "Frame Info");
        draw_scrollable_text(canvas, app->result_text, app->result_scroll);
        canvas_set_font(canvas, FontSecondary);
        if(app->result_scroll > 0)
            canvas_draw_str(canvas, 120, 20, "^");
        canvas_draw_str(canvas, 120, 62, "v");
        break;

    case AppStateKeyList:
        draw_header(canvas, "Try Known Keys");
        draw_scrollable_text(canvas, app->result_text, app->result_scroll);
        canvas_set_font(canvas, FontSecondary);
        canvas_draw_str(canvas, 120, 62, "v");
        break;

    case AppStateAbout:
        canvas_set_font(canvas, FontPrimary);
        canvas_draw_str(canvas, 2, 12, "Rolling Code Tool v1.1");
        canvas_set_font(canvas, FontSecondary);
        canvas_draw_str(canvas, 2, 24, "KeeLoq + GM OUC/KOBT");
        canvas_draw_str(canvas, 2, 34, "315 MHz Unleashed TX");
        canvas_draw_str(canvas, 2, 44, "Sub files: SD:/subghz/");
        canvas_draw_str(canvas, 2, 54, "Back=exit");
        break;
    }
}

/* ------------------------------------------------------------------ */
/* Input handler                                                        */
/* ------------------------------------------------------------------ */

static void app_input_cb(InputEvent* event, void* ctx) {
    furi_assert(event);
    furi_assert(ctx);
    FuriMessageQueue* queue = ctx;
    furi_message_queue_put(queue, event, FuriWaitForever);
}

static void app_fob_tx(RollingCodeApp* app, FobButton button) {
    FobTxResult result;
    fob_tx_press(&app->fob, button, &result);
    if(result.success) {
        snprintf(app->tx_status, sizeof(app->tx_status),
                 "Sent x%lu  Cnt:%lu",
                 (unsigned long)result.frames_sent,
                 (unsigned long)app->fob.counter[button]);
    } else {
        snprintf(app->tx_status, sizeof(app->tx_status),
                 "ERR: %s", result.error_msg);
    }
}

static bool app_handle_input(RollingCodeApp* app, InputEvent* ev) {
    if(ev->type != InputTypeShort && ev->type != InputTypeRepeat) return true;

    InputKey key = ev->key;

    switch(app->state) {

    /* ---- Main menu ---- */
    case AppStateMenu:
        if(key == InputKeyUp   && app->menu_cursor > 0) app->menu_cursor--;
        if(key == InputKeyDown && app->menu_cursor < MENU_ITEM_COUNT - 1) app->menu_cursor++;
        if(key == InputKeyBack) return false;
        if(key == InputKeyOk) {
            switch(app->menu_cursor) {
            case 0: /* My Fob TX */
                app->state = AppStateFobMain;
                break;
            case 1: /* Program BCM */
                app->program_step = 0;
                app->state = AppStateFobProgram;
                break;
            case 2: /* Capture fob signal */
                app->state = AppStateFobCapture;
                break;
            case 3: /* Decode .sub file */
                app_scan_files(app);
                app->file_cursor = 0;
                app->state = AppStateFileList;
                break;
            case 4: /* Try known keys */
                app->result_scroll = 0;
                app_try_known_keys(app);
                app->state = AppStateKeyList;
                break;
            case 5: /* About */
                app->state = AppStateAbout;
                break;
            }
        }
        break;

    /* ---- My Fob transmit screen ---- */
    case AppStateFobMain:
        if(key == InputKeyBack)  { app->state = AppStateMenu; break; }
        if(key == InputKeyUp)    app_fob_tx(app, FobButtonLock);
        if(key == InputKeyDown)  app_fob_tx(app, FobButtonUnlock);
        if(key == InputKeyLeft)  app_fob_tx(app, FobButtonTrunk);
        if(key == InputKeyRight) app_fob_tx(app, FobButtonPanic);
        break;

    /* ---- BCM programming wizard ---- */
    case AppStateFobProgram:
        if(key == InputKeyBack) { app->state = AppStateMenu; break; }
        if(key == InputKeyOk) {
            if(app->program_step < PROGRAM_STEP_COUNT - 1) {
                app->program_step++;
            } else {
                /* Final step: transmit programming frame to BCM */
                if(!app->fob.valid)
                    fob_state_init_gm(&app->fob, 0x1234567u);
                bool ok = fob_tx_program_bcm(&app->fob);
                if(ok) {
                    app->fob.valid = true;
                    fob_state_save(&app->fob);
                    snprintf(app->tx_status, sizeof(app->tx_status),
                             "BCM programmed OK!");
                } else {
                    snprintf(app->tx_status, sizeof(app->tx_status),
                             "TX failed — retry");
                }
                app->state = AppStateFobMain;
            }
        }
        break;

    /* ---- Capture fob signal ---- */
    case AppStateFobCapture:
        if(key == InputKeyBack) { app->state = AppStateMenu; break; }
        snprintf(app->result_text, RC_RESULT_LEN,
            "Use Flipper built-in\n"
            "Sub-GHz > Read RAW\n"
            "at 315 MHz, capture\n"
            "3 button presses.\n"
            "Then use Decode .sub\n"
            "to analyse the file.");
        app->result_scroll = 0;
        app->state = AppStateResult;
        break;

    /* ---- File list ---- */
    case AppStateFileList:
        if(key == InputKeyBack)  { app->state = AppStateMenu; break; }
        if(key == InputKeyUp   && app->file_cursor > 0) app->file_cursor--;
        if(key == InputKeyDown && app->file_cursor < app->file_count - 1) app->file_cursor++;
        if(key == InputKeyOk && app->file_count > 0) {
            app->state = AppStateLoading;
            bool ok = app_load_sub_file(app, app->files[app->file_cursor]);
            app->result_scroll = 0;
            if(!ok) {
                snprintf(app->result_text, RC_RESULT_LEN,
                         "Error: %s", app->status_msg);
            }
            app->state = AppStateResult;
        }
        break;

    /* ---- Result / key-list screens ---- */
    case AppStateResult:
    case AppStateKeyList:
        if(key == InputKeyBack)  { app->state = AppStateMenu; break; }
        if(key == InputKeyUp   && app->result_scroll > 0) app->result_scroll--;
        if(key == InputKeyDown && app->result_scroll < 20) app->result_scroll++;
        if(key == InputKeyOk && app->state == AppStateResult && !app->decrypted) {
            app->result_scroll = 0;
            app_try_known_keys(app);
            app->state = AppStateKeyList;
        }
        break;

    /* ---- About ---- */
    case AppStateAbout:
        if(key == InputKeyBack) app->state = AppStateMenu;
        break;

    default:
        break;
    }
    return true;
}

/* ------------------------------------------------------------------ */
/* Entry point                                                          */
/* ------------------------------------------------------------------ */

int32_t rolling_code_app(void* p) {
    UNUSED(p);

    RollingCodeApp* app = malloc(sizeof(RollingCodeApp));
    furi_assert(app);
    memset(app, 0, sizeof(*app));
    app->state = AppStateMenu;

    /* Restore saved fob state (counter must survive reboots) */
    if(fob_state_load(&app->fob)) {
        snprintf(app->tx_status, sizeof(app->tx_status),
                 "Fob loaded ID:%07lX", (unsigned long)app->fob.serial);
    } else {
        snprintf(app->tx_status, sizeof(app->tx_status), "No fob — use Program BCM");
    }

    FuriMessageQueue* event_queue = furi_message_queue_alloc(8, sizeof(InputEvent));

    ViewPort* view_port = view_port_alloc();
    view_port_draw_callback_set(view_port, app_draw_cb, app);
    view_port_input_callback_set(view_port, app_input_cb, event_queue);

    Gui* gui = furi_record_open(RECORD_GUI);
    gui_add_view_port(gui, view_port, GuiLayerFullscreen);

    InputEvent event;
    bool running = true;

    while(running) {
        if(furi_message_queue_get(event_queue, &event, 100) == FuriStatusOk) {
            running = app_handle_input(app, &event);
        }
        view_port_update(view_port);
    }

    gui_remove_view_port(gui, view_port);
    furi_record_close(RECORD_GUI);
    view_port_free(view_port);
    furi_message_queue_free(event_queue);
    free(app);

    return 0;
}
