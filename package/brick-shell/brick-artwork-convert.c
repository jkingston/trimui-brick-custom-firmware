// SPDX-License-Identifier: GPL-2.0-only
#include <png.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_INPUT_DIMENSION 4096u
#define MAX_OUTPUT_DIMENSION 480u

static void fail(const char *message) {
    fprintf(stderr, "brick-artwork-convert: %s\n", message);
    exit(1);
}

static uint8_t sample(const uint8_t *pixels, uint32_t width, uint32_t height,
                      uint32_t x, uint32_t y, uint32_t channel) {
    if (x >= width) x = width - 1;
    if (y >= height) y = height - 1;
    return pixels[((size_t)y * width + x) * 4 + channel];
}

int main(int argc, char **argv) {
    if (argc != 3) fail("usage: INPUT.png OUTPUT.brtx");
    FILE *input = fopen(argv[1], "rb");
    if (input == NULL) fail("cannot open input");
    uint8_t signature[8];
    if (fread(signature, 1, sizeof(signature), input) != sizeof(signature) ||
        png_sig_cmp(signature, 0, sizeof(signature)) != 0)
        fail("input is not PNG");

    png_structp png = png_create_read_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
    if (png == NULL) fail("PNG decoder allocation failed");
    png_infop info = png_create_info_struct(png);
    if (info == NULL) fail("PNG decoder allocation failed");
    if (setjmp(png_jmpbuf(png))) fail("invalid PNG");
    png_init_io(png, input);
    png_set_sig_bytes(png, sizeof(signature));
    png_read_info(png, info);
    uint32_t width = png_get_image_width(png, info);
    uint32_t height = png_get_image_height(png, info);
    if (width == 0 || height == 0 || width > MAX_INPUT_DIMENSION || height > MAX_INPUT_DIMENSION)
        fail("PNG dimensions are outside device limits");
    int color = png_get_color_type(png, info);
    int depth = png_get_bit_depth(png, info);
    if (depth == 16) png_set_strip_16(png);
    if (color == PNG_COLOR_TYPE_PALETTE) png_set_palette_to_rgb(png);
    if (color == PNG_COLOR_TYPE_GRAY && depth < 8) png_set_expand_gray_1_2_4_to_8(png);
    if (png_get_valid(png, info, PNG_INFO_tRNS)) png_set_tRNS_to_alpha(png);
    if (color == PNG_COLOR_TYPE_GRAY || color == PNG_COLOR_TYPE_GRAY_ALPHA) png_set_gray_to_rgb(png);
    if ((color & PNG_COLOR_MASK_ALPHA) == 0) png_set_add_alpha(png, 0xff, PNG_FILLER_AFTER);
    png_read_update_info(png, info);
    if (png_get_rowbytes(png, info) != (size_t)width * 4) fail("unsupported PNG layout");

    uint8_t *source = malloc((size_t)width * height * 4);
    png_bytep *rows = malloc((size_t)height * sizeof(*rows));
    if (source == NULL || rows == NULL) fail("image is too large");
    for (uint32_t y = 0; y < height; ++y) rows[y] = source + (size_t)y * width * 4;
    png_read_image(png, rows);
    png_read_end(png, NULL);
    png_destroy_read_struct(&png, &info, NULL);
    fclose(input);
    free(rows);

    uint32_t output_width = width;
    uint32_t output_height = height;
    if (output_width > MAX_OUTPUT_DIMENSION || output_height > MAX_OUTPUT_DIMENSION) {
        if (width >= height) {
            output_width = MAX_OUTPUT_DIMENSION;
            output_height = (height * MAX_OUTPUT_DIMENSION + width / 2) / width;
        } else {
            output_height = MAX_OUTPUT_DIMENSION;
            output_width = (width * MAX_OUTPUT_DIMENSION + height / 2) / height;
        }
    }
    uint8_t *scaled = malloc((size_t)output_width * output_height * 4);
    if (scaled == NULL) fail("output allocation failed");
    for (uint32_t y = 0; y < output_height; ++y) {
        uint32_t sy = output_height == 1 ? 0 : (uint32_t)(((uint64_t)y * (height - 1) << 16) / (output_height - 1));
        uint32_t y0 = sy >> 16, fy = sy & 0xffff;
        for (uint32_t x = 0; x < output_width; ++x) {
            uint32_t sx = output_width == 1 ? 0 : (uint32_t)(((uint64_t)x * (width - 1) << 16) / (output_width - 1));
            uint32_t x0 = sx >> 16, fx = sx & 0xffff;
            for (uint32_t c = 0; c < 4; ++c) {
                uint32_t a = sample(source, width, height, x0, y0, c);
                uint32_t b = sample(source, width, height, x0 + 1, y0, c);
                uint32_t d = sample(source, width, height, x0, y0 + 1, c);
                uint32_t e = sample(source, width, height, x0 + 1, y0 + 1, c);
                uint32_t top = a * (65536 - fx) + b * fx;
                uint32_t bottom = d * (65536 - fx) + e * fx;
                scaled[((size_t)y * output_width + x) * 4 + c] =
                    (uint8_t)(((uint64_t)top * (65536 - fy) + (uint64_t)bottom * fy) >> 32);
            }
        }
    }
    free(source);

    FILE *output = fopen(argv[2], "wb");
    if (output == NULL) fail("cannot open output");
    uint8_t header[8] = {'B', 'R', 'T', 'X', output_width & 0xff, output_width >> 8,
                         output_height & 0xff, output_height >> 8};
    if (fwrite(header, 1, sizeof(header), output) != sizeof(header)) fail("output write failed");
    for (size_t index = 0; index < (size_t)output_width * output_height; ++index) {
        uint8_t bgra[4] = {scaled[index * 4 + 2], scaled[index * 4 + 1],
                           scaled[index * 4], scaled[index * 4 + 3]};
        if (fwrite(bgra, 1, sizeof(bgra), output) != sizeof(bgra)) fail("output write failed");
    }
    free(scaled);
    if (fclose(output) != 0) fail("output close failed");
    return 0;
}
