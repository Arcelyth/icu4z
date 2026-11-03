#include <unicode/utypes.h>
#if U_ICU_VERSION_MAJOR_NUM < 68
#error "ICU4Z requires ICU 68 or later"
#endif
#include <unicode/uversion.h>
#include <unicode/uchar.h>
#include <unicode/ustring.h>
#include <unicode/uidna.h>
#include <unicode/unorm2.h>
#include <unicode/utext.h>
#include <unicode/ubrk.h>
#include <unicode/ucol.h>

/* Let ICU's headers provide the exact suffix, including custom library suffixes. */
#define ICU4Z_STRINGIFY_INNER(x) #x
#define ICU4Z_STRINGIFY(x) ICU4Z_STRINGIFY_INNER(x)
#if U_DISABLE_RENAMING
static const char icu4z_symbol_suffix[] = "";
#else
static const char icu4z_symbol_suffix[] = ICU4Z_STRINGIFY(U_ICU_ENTRY_POINT_RENAME());
#endif
