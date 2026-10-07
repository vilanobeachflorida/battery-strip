#include "SMC.h"

#include <math.h>
#include <string.h>
#include <IOKit/IOKitLib.h>

// The SMC (System Management Controller) protocol isn't documented, but this layout has been
// stable for well over a decade and is what every Mac sensor app uses. Reading needs no privileges.

typedef struct { char major, minor, build, reserved; UInt16 release; } SMCVersion;
typedef struct { UInt16 version, length; UInt32 cpuPLimit, gpuPLimit, memPLimit; } SMCPowerLimit;
typedef struct { UInt32 dataSize, dataType; char dataAttributes; } SMCKeyInfo;
typedef struct {
    UInt32 key;
    SMCVersion version;
    SMCPowerLimit powerLimit;
    SMCKeyInfo keyInfo;
    char result, status, command;
    UInt32 data32;
    unsigned char bytes[32];
} SMCParam;

enum { kSMCUserClientSelector = 2, kSMCReadBytes = 5, kSMCReadKeyInfo = 9 };

static UInt32 FourCC(const char *s) {
    return ((UInt32)s[0] << 24) | ((UInt32)s[1] << 16) | ((UInt32)s[2] << 8) | (UInt32)s[3];
}

static kern_return_t Call(io_connect_t connection, SMCParam *input, SMCParam *output) {
    size_t outputSize = sizeof(SMCParam);
    return IOConnectCallStructMethod(connection, kSMCUserClientSelector, input, sizeof(SMCParam), output, &outputSize);
}

static io_connect_t Open(void) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return 0;
    io_connect_t connection = 0;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &connection);
    IOObjectRelease(service);
    return result == KERN_SUCCESS ? connection : 0;
}

/// Reads a key's raw bytes (at most 32) and its four-character data type.
static int ReadKey(io_connect_t connection, const char *key, UInt32 *type, unsigned char *bytes, UInt32 *size) {
    SMCParam input = {0}, output = {0};
    input.key = FourCC(key);
    input.command = kSMCReadKeyInfo;
    if (Call(connection, &input, &output) != KERN_SUCCESS || output.result != 0) return -1;

    SMCKeyInfo info = output.keyInfo;
    memset(&output, 0, sizeof output);
    input.keyInfo.dataSize = info.dataSize;
    input.command = kSMCReadBytes;
    if (Call(connection, &input, &output) != KERN_SUCCESS || output.result != 0) return -1;

    *type = info.dataType;
    *size = info.dataSize > 32 ? 32 : info.dataSize;
    memcpy(bytes, output.bytes, *size);
    return 0;
}

static double ReadTemperature(io_connect_t connection, const char *key) {
    UInt32 type = 0, size = 0;
    unsigned char bytes[32];
    if (ReadKey(connection, key, &type, bytes, &size) != 0) return NAN;
    if (type == FourCC("flt ") && size == 4) {
        float value;
        memcpy(&value, bytes, sizeof value);
        return value;
    }
    if (type == FourCC("sp78") && size == 2) {
        return (signed char)bytes[0] + bytes[1] / 256.0;
    }
    return NAN;
}

double BSReadBatteryTemperature(void) {
    io_connect_t connection = Open();
    if (!connection) return NAN;
    const char *keys[] = { "TB0T", "TB1T", "TB2T" };
    double sum = 0;
    int count = 0;
    for (int i = 0; i < 3; i++) {
        double value = ReadTemperature(connection, keys[i]);
        if (value > 0 && value < 100) {
            sum += value;
            count++;
        }
    }
    IOServiceClose(connection);
    return count ? sum / count : NAN;
}

int BSReadSMCText(const char *key, char *buffer, int capacity) {
    if (capacity <= 0) return -1;
    io_connect_t connection = Open();
    if (!connection) return -1;
    UInt32 type = 0, size = 0;
    unsigned char bytes[32];
    int result = ReadKey(connection, key, &type, bytes, &size);
    IOServiceClose(connection);
    if (result != 0) return -1;

    int length = 0;
    for (UInt32 i = 0; i < size && length < capacity - 1 && bytes[i] != 0; i++) {
        buffer[length++] = (char)bytes[i];
    }
    buffer[length] = 0;
    return length;
}
