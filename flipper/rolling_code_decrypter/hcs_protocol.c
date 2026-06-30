#include "hcs_protocol.h"
#include <string.h>
#include <stdio.h>

bool hcs_frame_unpack(const uint8_t* raw9, HCSFrame* out) {
    if(!raw9 || !out) return false;
    /*
     * Bit layout in raw9[] (66 bits, MSB first):
     * raw9[0] bit7..bit2 = frame bits 65..60
     * raw9[0] bit1..bit0 + raw9[1] = frame bits 59..52
     * ...continuing LSB-first packing
     * Frame bit N is at byte index (65-N)/8, bit offset (65-N)%8 from MSB.
     *
     * We reconstruct by assembling the fields directly.
     */
    uint64_t hi = 0;
    uint32_t lo = 0;

    /* Assemble bits 65..34 (ciphertext) into hi, bits 33..0 into lo */
    for(int i = 65; i >= 34; i--) {
        int byte_idx = (65 - i) / 8;
        int bit_idx  = 7 - (65 - i) % 8;
        uint64_t bit = (raw9[byte_idx] >> bit_idx) & 1u;
        hi = (hi << 1) | bit;
    }
    for(int i = 33; i >= 0; i--) {
        int byte_idx = (65 - i) / 8;
        int bit_idx  = 7 - (65 - i) % 8;
        uint32_t bit = (raw9[byte_idx] >> bit_idx) & 1u;
        lo = (lo << 1) | bit;
    }

    out->ciphertext = (uint32_t)(hi & 0xFFFFFFFFu);
    out->serial     = (lo >> 6) & 0x0FFFFFFFu;
    out->button     = (lo >> 2) & 0x0Fu;
    out->repeat     = (lo >> 1) & 1u;
    out->low_bat    = (lo >> 0) & 1u;
    return true;
}

bool hcs_frame_unpack64(uint64_t raw, HCSFrame* out) {
    if(!out) return false;
    /*
     * Flipper stores the 66-bit KeeLoq frame as a hex string in .sub files.
     * The 66-bit value is packed as:
     *   bits [65:34] = ciphertext (32 bits)
     *   bits [33:6]  = serial     (28 bits)
     *   bits [5:2]   = button     (4 bits)
     *   bits [1:0]   = status     (2 bits)
     *
     * Flipper's Key field holds this as an 8-byte (64-bit) value where the
     * top 2 bits of the frame are encoded in the least-significant bits of
     * the first byte — i.e., the 66-bit frame is right-aligned in the
     * 8-byte field with 2 zero-padding bits at the top.
     *
     * So raw[63:32] = ciphertext[31:0] shifted right by 2,
     * which means:  ciphertext = (raw >> 34) & 0xFFFFFFFF
     *               serial     = (raw >>  6) & 0xFFFFFFF
     *               button     = (raw >>  2) & 0xF
     *               status     = raw & 0x3
     */
    out->ciphertext = (uint32_t)((raw >> 34) & 0xFFFFFFFFu);
    out->serial     = (uint32_t)((raw >>  6) & 0x0FFFFFFFu);
    out->button     = (uint8_t)((raw  >>  2) & 0x0Fu);
    out->repeat     = (raw >> 1) & 1u;
    out->low_bat    = (raw >> 0) & 1u;
    return true;
}

void hcs_plaintext_decode(uint32_t plaintext, HCSPlaintext* out) {
    out->function = (plaintext >> 28) & 0x0Fu;
    out->ovr_cnt  = (plaintext >> 16) & 0x0FFFu;
    out->sync_cnt = (plaintext >>  0) & 0xFFFFu;
    out->full_cnt = ((uint32_t)out->ovr_cnt << 16) | out->sync_cnt;
}

void hcs_frame_format(const HCSFrame* f, const HCSPlaintext* pt,
                      bool decrypted, char* buf, uint32_t buf_size) {
    char tmp[256];
    int  offset = 0;

    offset += snprintf(tmp + offset, sizeof(tmp) - (size_t)offset,
        "Serial:  %07lX\n"
        "Button:  %X\n"
        "Repeat:  %s\n"
        "Bat Low: %s\n"
        "Cipher:  %08lX\n",
        (unsigned long)f->serial,
        f->button,
        f->repeat  ? "Yes" : "No",
        f->low_bat ? "Yes" : "No",
        (unsigned long)f->ciphertext);

    if(decrypted && pt) {
        offset += snprintf(tmp + offset, sizeof(tmp) - (size_t)offset,
            "Counter: %lu\n"
            "Fn Code: %X",
            (unsigned long)pt->full_cnt,
            pt->function);
    } else {
        offset += snprintf(tmp + offset, sizeof(tmp) - (size_t)offset,
            "[Key needed to decrypt]");
    }

    (void)offset;
    /* safe copy */
    uint32_t len = (uint32_t)strlen(tmp);
    if(len >= buf_size) len = buf_size - 1;
    memcpy(buf, tmp, len);
    buf[len] = '\0';
}
