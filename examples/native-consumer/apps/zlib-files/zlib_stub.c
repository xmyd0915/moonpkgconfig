#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#endif

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#ifdef _WIN32
#include <io.h>
#include <windows.h>
#else
#include <unistd.h>
#endif

#include "moonbit.h"
#include <zlib.h>

/* Paths arrive as UTF-8; preserve Unicode filenames on both platforms. */
#ifdef _WIN32
typedef wchar_t native_char;
#else
typedef char native_char;
#endif

static native_char *native_path(moonbit_bytes_t path) {
  int32_t length = Moonbit_array_length(path);
  if (length == 0 || memchr(path, 0, (size_t)length) != NULL) {
    return NULL;
  }
#ifdef _WIN32
  int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                 (const char *)path, length, NULL, 0);
  if (count == 0) {
    return NULL;
  }
  wchar_t *result = malloc(((size_t)count + 1) * sizeof(wchar_t));
  if (result == NULL) {
    return NULL;
  }
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (const char *)path,
                          length, result, count) != count) {
    free(result);
    return NULL;
  }
  result[count] = 0;
#else
  char *result = malloc((size_t)length + 1);
  if (result == NULL) {
    return NULL;
  }
  memcpy(result, path, (size_t)length);
  result[length] = 0;
#endif
  return result;
}

/* status: 0 success, 1 I/O/allocation failure, 2 input exceeds limit. */
MOONBIT_FFI_EXPORT moonbit_bytes_t moonpkg_read_bounded(
    moonbit_bytes_t path, int32_t limit, int32_t *status) {
  status[0] = 1;
  native_char *name = native_path(path);
  if (name == NULL || limit < 0 || limit == INT32_MAX) {
    free(name);
    return moonbit_make_bytes(0, 0);
  }
#ifdef _WIN32
  FILE *input = _wfopen(name, L"rb");
#else
  FILE *input = fopen(name, "rb");
#endif
  free(name);
  if (input == NULL) {
    return moonbit_make_bytes(0, 0);
  }
  /* Avoid allocating for known oversized files. The bounded loop also covers
     file growth after this check and streams without a useful file size. */
#ifdef _WIN32
  struct _stat64 info;
  if (_fstat64(_fileno(input), &info) == 0 && info.st_size > limit) {
#else
  struct stat info;
  if (fstat(fileno(input), &info) == 0 && info.st_size > limit) {
#endif
    fclose(input);
    status[0] = 2;
    return moonbit_make_bytes(0, 0);
  }
  size_t maximum = (size_t)limit + 1;
  size_t capacity = maximum < 65536 ? maximum : 65536;
  size_t used = 0;
  unsigned char *buffer = malloc(capacity);
  if (buffer == NULL) {
    fclose(input);
    return moonbit_make_bytes(0, 0);
  }
  while (1) {
    if (used == capacity) {
      size_t next = capacity > maximum / 2 ? maximum : capacity * 2;
      unsigned char *grown = realloc(buffer, next);
      if (grown == NULL) {
        break;
      }
      buffer = grown;
      capacity = next;
    }
    size_t count = fread(buffer + used, 1, capacity - used, input);
    used += count;
    if (used > (size_t)limit) {
      status[0] = 2;
      break;
    }
    if (count == 0) {
      if (!ferror(input)) {
        status[0] = 0;
      }
      break;
    }
  }
  if (fclose(input) != 0 && status[0] == 0) {
    status[0] = 1;
  }
  moonbit_bytes_t result = moonbit_make_bytes(
      status[0] == 0 ? (int32_t)used : 0, 0);
  if (status[0] == 0 && used != 0) {
    memcpy(result, buffer, used);
  }
  free(buffer);
  return result;
}

/* status: 0 success, 1 output exists, 2 create/write failure. Never unlink a
   path after an error: it may now name another process's file. */
MOONBIT_FFI_EXPORT int32_t moonpkg_write_new(
    moonbit_bytes_t path, moonbit_bytes_t content) {
  native_char *name = native_path(path);
  if (name == NULL) {
    return 2;
  }
#ifdef _WIN32
  int descriptor = _wopen(name, _O_WRONLY | _O_CREAT | _O_EXCL | _O_BINARY,
                          _S_IREAD | _S_IWRITE);
#else
  int descriptor = open(name, O_WRONLY | O_CREAT | O_EXCL, 0600);
#endif
  int open_error = errno;
  free(name);
  if (descriptor == -1) {
    return open_error == EEXIST ? 1 : 2;
  }
#ifdef _WIN32
  FILE *output = _fdopen(descriptor, "wb");
#else
  FILE *output = fdopen(descriptor, "wb");
#endif
  if (output == NULL) {
#ifdef _WIN32
    _close(descriptor);
#else
    close(descriptor);
#endif
    return 2;
  }
  size_t length = (size_t)Moonbit_array_length(content);
  int failed = fwrite(content, 1, length, output) != length;
  if (fclose(output) != 0) {
    failed = 1;
  }
  return failed ? 2 : 0;
}

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
