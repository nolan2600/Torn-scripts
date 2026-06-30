/*
 * Self-test for the KeeLoq encrypt/decrypt round-trip.
 * Compile and run standalone:
 *   gcc -o keeloq_test keeloq.c keeloq_test.c && ./keeloq_test
 */
#include "keeloq.h"
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

/* ------------------------------------------------------------------ */
/* Test vectors derived from Microchip's AN636 and published sources   */
/* ------------------------------------------------------------------ */

static const struct {
    uint32_t plaintext;
    uint64_t key;
    uint32_t ciphertext;
} VECTORS[] = {
    /*
     * All-zero key, plaintext = 0x00000001.
     * Cross-verified against Flipper Zero firmware reference implementation
     * (subghz/protocols/keeloq_common.c, upstream commit verified 2025-06).
     */
    { 0x00000001UL, 0x0000000000000000ULL, 0x2F197B2EUL },

    /*
     * key = 0x0102030405060708, plaintext = 0xDEADBEEF.
     * Cross-verified against same Flipper Zero reference.
     */
    { 0xDEADBEEFUL, 0x0102030405060708ULL, 0x8EBE8424UL },
};

#define VECTOR_COUNT ((int)(sizeof(VECTORS) / sizeof(VECTORS[0])))

static int test_round_trip(void) {
    printf("=== KeeLoq Round-trip Test ===\n");
    int pass = 0;
    for(uint32_t pt = 0; pt < 1000; pt++) {
        uint64_t key = ((uint64_t)pt * 0xDEADBEEFCAFEBABEULL) ^ 0xABCDABCDABCDABCDULL;
        uint32_t ct  = keeloq_encrypt(pt, key);
        uint32_t dec = keeloq_decrypt(ct, key);
        if(dec != pt) {
            printf("FAIL  pt=%08X key=%016llX ct=%08X dec=%08X\n",
                   pt, (unsigned long long)key, ct, dec);
            return 1;
        }
        pass++;
    }
    printf("PASS  %d round-trips verified\n", pass);
    return 0;
}

static int test_vectors(void) {
    printf("=== KeeLoq Known-Vector Test ===\n");
    for(int i = 0; i < VECTOR_COUNT; i++) {
        uint32_t ct  = keeloq_encrypt(VECTORS[i].plaintext, VECTORS[i].key);
        uint32_t dec = keeloq_decrypt(VECTORS[i].ciphertext, VECTORS[i].key);

        int enc_ok = (ct  == VECTORS[i].ciphertext);
        int dec_ok = (dec == VECTORS[i].plaintext);

        printf("Vector %d: enc=%s dec=%s\n", i,
               enc_ok ? "PASS" : "FAIL",
               dec_ok ? "PASS" : "FAIL");
        if(!enc_ok)
            printf("  Expected ct=%08lX, got=%08lX\n",
                   (unsigned long)VECTORS[i].ciphertext, (unsigned long)ct);
        if(!dec_ok)
            printf("  Expected pt=%08lX, got=%08lX\n",
                   (unsigned long)VECTORS[i].plaintext, (unsigned long)dec);
        if(!enc_ok || !dec_ok) return 1;
    }
    printf("All vectors passed\n");
    return 0;
}

static int test_hcs_frame(void) {
    printf("=== HCS Frame Format Test ===\n");
    /*
     * Build a synthetic HCS301-style plaintext:
     *   Function code: 0x1 (button 1)
     *   OVR_CNT:       0x000
     *   SYNC_CNT:      0x0042
     *
     * Encrypt with a known key, then decrypt and verify.
     */
    uint8_t   func     = 0x1;
    uint32_t  sync_cnt = 0x0042;
    uint32_t  ovr_cnt  = 0x000;
    uint32_t  plaintext = ((uint32_t)func << 28) |
                          ((uint32_t)ovr_cnt << 16) |
                          sync_cnt;

    uint64_t key  = 0x0102030405060708ULL;
    uint32_t ct   = keeloq_encrypt(plaintext, key);
    uint32_t dec  = keeloq_decrypt(ct, key);

    printf("  Plaintext:  0x%08lX\n", (unsigned long)plaintext);
    printf("  Ciphertext: 0x%08lX\n", (unsigned long)ct);
    printf("  Decrypted:  0x%08lX  %s\n", (unsigned long)dec,
           dec == plaintext ? "PASS" : "FAIL");

    if(dec != plaintext) return 1;

    /* Verify field extraction */
    uint8_t  dec_func = (dec >> 28) & 0xF;
    uint16_t dec_ovr  = (dec >> 16) & 0xFFF;
    uint16_t dec_sync = dec & 0xFFFF;
    printf("  Fn=%X OVR=%03X SYNC=%04X  %s\n",
           dec_func, dec_ovr, dec_sync,
           (dec_func == func && dec_ovr == ovr_cnt && dec_sync == sync_cnt)
           ? "PASS" : "FAIL");

    return (dec_func == func && dec_ovr == ovr_cnt && dec_sync == sync_cnt) ? 0 : 1;
}

int main(void) {
    int failures = 0;
    failures += test_vectors();
    failures += test_round_trip();
    failures += test_hcs_frame();
    printf("\n%s (%d failure(s))\n", failures ? "FAILED" : "ALL PASSED", failures);
    return failures ? 1 : 0;
}
