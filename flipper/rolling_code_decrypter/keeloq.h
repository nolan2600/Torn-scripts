#pragma once
#include <stdint.h>
#include <stdbool.h>

/*
 * KeeLoq block cipher — Microchip Technology Inc.
 * 32-bit block / 64-bit key NLFSR-based cipher, 528 rounds.
 *
 * Used in HCS200/HCS300/HCS301 rolling-code transmitters and many
 * automotive / garage-door remote systems.
 */

#define KEELOQ_NLF 0x3A5C742EUL

/**
 * Encrypt a 32-bit plaintext block with a 64-bit key.
 * Runs the NLFSR forward for 528 rounds.
 */
uint32_t keeloq_encrypt(uint32_t data, uint64_t key);

/**
 * Decrypt a 32-bit ciphertext block with a 64-bit key.
 * Runs the NLFSR backward for 528 rounds.
 */
uint32_t keeloq_decrypt(uint32_t data, uint64_t key);

/**
 * Derive the per-device 64-bit key from the 64-bit manufacturer key
 * and the 28-bit device serial number using the "Normal Learning" method
 * documented in Microchip AN636.
 */
uint64_t keeloq_derive_key(uint64_t manuf_key, uint32_t serial);
