#pragma once
#include <stdint.h>
#include <stdbool.h>

/*
 * HCS200 / HCS300 / HCS301 rolling-code frame format
 *
 * 66-bit OTA transmission (MSB first):
 *   [65:34]  Ciphertext     — 32 bits (KeeLoq-encrypted hop code)
 *   [33:6]   Serial         — 28 bits (device serial number, plain)
 *   [5:2]    Button         — 4  bits (function code, plain)
 *   [1]      S1             — repeat flag (0=first press, 1=repeated)
 *   [0]      S0             — low battery flag
 *
 * Plaintext (what the 32-bit ciphertext encodes):
 *   [31:28]  Function code  — mirrors the plain Button field
 *   [27:16]  OVR counter    — high 12 bits of 28-bit sync counter
 *   [15:0]   SYNC counter   — low 16 bits of 28-bit sync counter
 */

typedef struct {
    uint32_t ciphertext; /* 32-bit encrypted hop code */
    uint32_t serial;     /* 28-bit device serial */
    uint8_t  button;     /* 4-bit function code */
    bool     repeat;     /* S1: repeated press */
    bool     low_bat;    /* S0: low battery */
} HCSFrame;

typedef struct {
    uint8_t  function;  /* mirrored function code */
    uint16_t sync_cnt;  /* lower 16 bits of sync counter */
    uint16_t ovr_cnt;   /* upper 12 bits of sync counter */
    uint32_t full_cnt;  /* combined 28-bit counter */
} HCSPlaintext;

/**
 * Unpack a 66-bit raw frame word into an HCSFrame struct.
 * @param raw   66 bits packed into a uint8_t[9] array (MSB first, bit 65 = raw[0] bit 1)
 */
bool hcs_frame_unpack(const uint8_t* raw9, HCSFrame* out);

/**
 * Unpack a 66-bit frame already stored in two uint64_t halves (bits 65..2 in hi<<34|lo).
 * Flipper's KeeLoq decoder stores frames this way in .sub files.
 */
bool hcs_frame_unpack64(uint64_t raw, HCSFrame* out);

/** Decode plaintext after KeeLoq decryption. */
void hcs_plaintext_decode(uint32_t plaintext, HCSPlaintext* out);

/** Format frame summary into a caller-supplied buffer. */
void hcs_frame_format(const HCSFrame* f, const HCSPlaintext* pt,
                      bool decrypted, char* buf, uint32_t buf_size);
