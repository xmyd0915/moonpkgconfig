#include "moonbit.h"
#include <expat.h>

MOONBIT_FFI_EXPORT int32_t project_xml_valid(moonbit_bytes_t input) {
  XML_Parser parser = XML_ParserCreate(NULL);
  if (parser == NULL) {
    return 0;
  }
  int valid = XML_Parse(parser, (const char *)input, Moonbit_array_length(input), 1) == XML_STATUS_OK;
  XML_ParserFree(parser);
  return valid;
}

MOONBIT_FFI_EXPORT int32_t project_expat_configuration(void) {
  return PROJECT_EXPAT;
}
