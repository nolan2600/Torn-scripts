#include "keeloq.h"

/*
 * The NLF (Non-Linear Function) is a 5-input Boolean function encoded as a
 * 32-bit lookup table.  Inputs are specific bits of the current NLFSR state:
 *   a = r[1], b = r[9], c = r[20], d = r[26], e = r[31]
 * Index = a | (b<<1) | (c<<2) | (d<<3) | (e<<4)
 * Output = (0x3A5C742E >> index) & 1
 */
#define NLF(r) \
    ((KEELOQ_NLF >> \
        ((((r) >> 1)  & 1u)       | \
         (((r) >> 9)  & 1u) << 1  | \
         (((r) >> 20) & 1u) << 2  | \
         (((r) >> 26) & 1u) << 3  | \
         (((r) >> 31) & 1u) << 4)) & 1u)

uint32_t keeloq_encrypt(uint32_t data, uint64_t key) {
    uint32_t r = data;
    for(uint32_t i = 0; i < 528; i++) {
        uint32_t key_bit = (uint32_t)((key >> (i & 63u)) & 1u);
        uint32_t lin     = (r ^ (r >> 16)) & 1u;  /* r[0] XOR r[16] */
        uint32_t new_bit = lin ^ NLF(r) ^ key_bit;
        r = (r >> 1) | (new_bit << 31);
    }
    return r;
}

uint32_t keeloq_decrypt(uint32_t data, uint64_t key) {
    uint32_t r = data;
    /*
     * Reverse each encryption round.  After encryption round i:
     *   r_new[k] = r_old[k+1]  for k = 0..30
     *   r_new[31] = BIT (the computed bit)
     *
     * NLF was evaluated on r_old, so inputs in terms of r_new are:
     *   r_old[1]  = r_new[0], r_old[9]  = r_new[8],
     *   r_old[20] = r_new[19], r_old[26] = r_new[25], r_old[31] = r_new[30]
     *
     * Recovering r_old[0]:
     *   BIT = (r_old[0] XOR r_old[16]) XOR NLF(r_old) XOR key_bit
     *   r_old[16] = r_new[15]
     *   => r_old[0] = r_new[31] XOR r_new[15] XOR NLF_using_new_indices XOR key_bit
     */
#define NLF_DEC(r) \
    ((KEELOQ_NLF >> \
        ((((r) >> 0)  & 1u)       | \
         (((r) >> 8)  & 1u) << 1  | \
         (((r) >> 19) & 1u) << 2  | \
         (((r) >> 25) & 1u) << 3  | \
         (((r) >> 30) & 1u) << 4)) & 1u)

    for(int32_t i = 527; i >= 0; i--) {
        uint32_t key_bit = (uint32_t)((key >> ((uint32_t)i & 63u)) & 1u);
        uint32_t nl      = NLF_DEC(r);
        uint32_t old_r0  = ((r >> 31) ^ (r >> 15) ^ nl ^ key_bit) & 1u;
        r = (r << 1) | old_r0;
    }
#undef NLF_DEC
    return r;
}

uint64_t keeloq_derive_key(uint64_t manuf_key, uint32_t serial) {
    /*
     * "Normal Learning" key derivation (Microchip AN636).
     * The 28-bit serial is split into two 16-bit seeds; each seed is
     * KeeLoq-encrypted with the manufacturer key to produce half-keys
     * that are then mixed with the serial.
     */
    uint32_t seed_lo = serial & 0xFFFFu;
    uint32_t seed_hi = (serial >> 16) & 0x0FFFu;

    uint32_t k_lo = keeloq_encrypt(seed_lo, manuf_key);
    uint32_t k_hi = keeloq_encrypt(seed_hi, manuf_key);

    /* Build 64-bit device key: interleave serial with half-key material */
    uint64_t device_key =
        ((uint64_t)((serial ^ k_hi) & 0xFFFFu) << 48) |
        ((uint64_t)((serial ^ k_lo) & 0xFFFFu) << 32) |
        ((uint64_t)((serial ^ k_hi) & 0xFFFFu) << 16) |
        ((uint64_t)((serial ^ k_lo) & 0xFFFFu));

    return device_key;
}
