/* Declarations for the generated build/bundle_data.c (see tools/gen_bundle.lua). */
#ifndef G2H_BUNDLE_DATA_H
#define G2H_BUNDLE_DATA_H

#include <stddef.h>

typedef struct {
    const char *name;
    const unsigned char *data;
    size_t len;
} g2h_embedded_file;

extern const g2h_embedded_file g2h_modules[];
extern const size_t g2h_modules_count;

extern const g2h_embedded_file g2h_themes[];
extern const size_t g2h_themes_count;

extern const unsigned char *g2h_main;
extern const size_t g2h_main_len;

#endif
