#include <limits.h>
#include <stdint.h>

#include "moonbit.h"
#include <zlib.h>

MOONBIT_FFI_EXPORT int32_t moonpkg_zlib_compress_bound(int32_t length) {
  if (length < 0) {
    return Z_STREAM_ERROR;
  }
  uLong bound = compressBound((uLong)length);
  return bound <= INT32_MAX ? (int32_t)bound : Z_BUF_ERROR;
}

MOONBIT_FFI_EXPORT int32_t moonpkg_zlib_compress(
    moonbit_bytes_t source, moonbit_bytes_t destination) {
  uLongf written = (uLongf)Moonbit_array_length(destination);
  int result = compress2(destination, &written, source,
                         (uLong)Moonbit_array_length(source), Z_BEST_SPEED);
  return result == Z_OK ? (int32_t)written : result;
}

MOONBIT_FFI_EXPORT int32_t moonpkg_zlib_decompress(
    moonbit_bytes_t source, int32_t length, moonbit_bytes_t destination) {
  if (length < 0 || length > Moonbit_array_length(source)) {
    return Z_STREAM_ERROR;
  }
  uLongf written = (uLongf)Moonbit_array_length(destination);
  int result = uncompress(destination, &written, source, (uLong)length);
  return result == Z_OK ? (int32_t)written : result;
}
