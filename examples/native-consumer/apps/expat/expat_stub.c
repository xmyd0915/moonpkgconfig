#include <stdint.h>
#include <string.h>

#include "moonbit.h"
#include <expat.h>

typedef struct {
  uint32_t elements;
  uint32_t attributes;
  uint32_t text_bytes;
} xml_counts;

static void XMLCALL start_element(void *user, const XML_Char *name,
                                  const XML_Char **attributes) {
  xml_counts *counts = user;
  (void)name;
  counts->elements++;
  for (int i = 0; attributes[i]; i += 2) {
    counts->attributes++;
  }
}

static void XMLCALL character_data(void *user, const XML_Char *text, int length) {
  xml_counts *counts = user;
  (void)text;
  counts->text_bytes += (uint32_t)length;
}

static void store_u32(moonbit_bytes_t destination, int offset, uint32_t value) {
  for (int i = 0; i < 4; i++) {
    destination[offset + i] = (uint8_t)(value >> (i * 8));
  }
}

/* The example deliberately bounds input, counters and the output record. */
MOONBIT_FFI_EXPORT int32_t moonpkg_expat_parse(
    moonbit_bytes_t input, int32_t length, int32_t chunk_size,
    moonbit_bytes_t summary) {
  if (length < 0 || length > Moonbit_array_length(input) || length > 1048576 ||
      chunk_size <= 0 || Moonbit_array_length(summary) < 24) {
    return -1;
  }
  XML_Parser parser = XML_ParserCreate(NULL);
  if (!parser) {
    return -2;
  }
  xml_counts counts = {0, 0, 0};
  XML_SetUserData(parser, &counts);
  XML_SetElementHandler(parser, start_element, NULL);
  XML_SetCharacterDataHandler(parser, character_data);
  XML_SetParamEntityParsing(parser, XML_PARAM_ENTITY_PARSING_NEVER);
  enum XML_Status status = XML_STATUS_OK;
  if (length == 0) {
    status = XML_Parse(parser, "", 0, XML_TRUE);
  }
  for (int32_t offset = 0; offset < length && status == XML_STATUS_OK;) {
    int32_t count = length - offset;
    if (count > chunk_size) {
      count = chunk_size;
    }
    status = XML_Parse(parser, (const char *)input + offset, count,
                       offset + count == length);
    offset += count;
  }
  store_u32(summary, 0, counts.elements);
  store_u32(summary, 4, counts.attributes);
  store_u32(summary, 8, counts.text_bytes);
  store_u32(summary, 12, (uint32_t)XML_GetErrorCode(parser));
  store_u32(summary, 16, (uint32_t)XML_GetCurrentLineNumber(parser));
  store_u32(summary, 20, (uint32_t)XML_GetCurrentColumnNumber(parser));
  XML_ParserFree(parser);
  return status == XML_STATUS_OK ? 1 : 0;
}
