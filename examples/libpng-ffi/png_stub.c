#include <limits.h>
#include <stdint.h>
#include <string.h>

#include "moonbit.h"
#include <png.h>

static int prepare_write(png_image *image, int32_t width, int32_t height,
                         moonbit_bytes_t pixels) {
  if (width <= 0 || height <= 0) {
    return 0;
  }
  uint64_t size = (uint64_t)width * (uint64_t)height * 4;
  if (size > INT32_MAX || size != (uint64_t)Moonbit_array_length(pixels)) {
    return 0;
  }
  memset(image, 0, sizeof(*image));
  image->version = PNG_IMAGE_VERSION;
  image->width = (png_uint_32)width;
  image->height = (png_uint_32)height;
  image->format = PNG_FORMAT_RGBA;
  return 1;
}

MOONBIT_FFI_EXPORT int32_t moonpkg_png_size(
    int32_t width, int32_t height, moonbit_bytes_t pixels) {
  png_image image;
  if (!prepare_write(&image, width, height, pixels)) {
    return -1;
  }
  png_alloc_size_t written = 0;
  int ok = png_image_write_to_memory(&image, NULL, &written, 0, pixels, 0, NULL);
  png_image_free(&image);
  return ok && written <= INT32_MAX ? (int32_t)written : -2;
}

MOONBIT_FFI_EXPORT int32_t moonpkg_png_encode(
    int32_t width, int32_t height, moonbit_bytes_t pixels,
    moonbit_bytes_t destination) {
  png_image image;
  if (!prepare_write(&image, width, height, pixels)) {
    return -1;
  }
  png_alloc_size_t written = (png_alloc_size_t)Moonbit_array_length(destination);
  int ok = png_image_write_to_memory(&image, destination, &written, 0, pixels, 0, NULL);
  png_image_free(&image);
  return ok && written <= INT32_MAX ? (int32_t)written : -2;
}

MOONBIT_FFI_EXPORT int32_t moonpkg_png_decode(
    moonbit_bytes_t encoded, int32_t length, int32_t width, int32_t height,
    moonbit_bytes_t destination) {
  if (length <= 0 || length > Moonbit_array_length(encoded) ||
      width <= 0 || height <= 0) {
    return -1;
  }
  png_image image;
  memset(&image, 0, sizeof(image));
  image.version = PNG_IMAGE_VERSION;
  if (!png_image_begin_read_from_memory(&image, encoded, (png_alloc_size_t)length)) {
    png_image_free(&image);
    return -2;
  }
  if (image.width != (png_uint_32)width || image.height != (png_uint_32)height) {
    png_image_free(&image);
    return -3;
  }
  image.format = PNG_FORMAT_RGBA;
  uint64_t size = (uint64_t)image.width * (uint64_t)image.height * 4;
  if (size > INT32_MAX || size > (uint64_t)Moonbit_array_length(destination)) {
    png_image_free(&image);
    return -4;
  }
  int ok = png_image_finish_read(&image, NULL, destination, 0, NULL);
  png_image_free(&image);
  return ok ? (int32_t)size : -2;
}
