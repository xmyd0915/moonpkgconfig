#include "moonbit.h"
#include <zlib.h>

#ifndef METADATA_REVISION
#define METADATA_REVISION 0
#endif

MOONBIT_FFI_EXPORT uint32_t project_crc32(moonbit_bytes_t input) {
  return (uint32_t)crc32(0, input, (uInt)Moonbit_array_length(input));
}

MOONBIT_FFI_EXPORT int32_t project_zlib_configuration(void) {
  return PROJECT_ZLIB + METADATA_REVISION;
}
