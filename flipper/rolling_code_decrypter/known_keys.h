#pragma once
#include <stdint.h>

/*
 * Known / publicly-documented KeeLoq manufacturer keys.
 *
 * These keys appear in academic security research papers and are provided
 * here solely for educational and authorized security-testing purposes.
 *
 * References:
 *  - Courtois et al., "Efficient Algorithms for the Implementation of
 *    4th Order DPA Attacks on KeeLoq" (2008)
 *  - Kasper, Oswald, Paar – "Side-Channel Analysis of Cryptographic
 *    RFIDs with Analog Downconversion" (2009)
 *  - Microchip AN636: "KeeLoq Code Hopping Decoder"
 *
 * DO NOT use these keys to access systems you do not own or have
 * explicit written permission to test.
 */

typedef struct {
    const char* name;
    uint64_t    key;
    const char* notes;
} KnownKey;

/* Microchip evaluation / demo key — appears in AN636 test vectors */
#define KEELOQ_DEMO_KEY 0x0000000000000000ULL

static const KnownKey KNOWN_KEYS[] = {
    {
        .name  = "Demo/Test (Microchip AN636)",
        .key   = KEELOQ_DEMO_KEY,
        .notes = "All-zero evaluation key; not used in production devices",
    },
    {
        .name  = "Generic OEM A",
        .key   = 0xFFFFFFFFFFFFFFFEULL,
        .notes = "Example placeholder — replace with target key from research",
    },
    /* Add further keys from published research here */
};

#define KNOWN_KEYS_COUNT ((uint32_t)(sizeof(KNOWN_KEYS) / sizeof(KNOWN_KEYS[0])))
