#ifndef SMC_h
#define SMC_h

/// The battery's temperature in °C, averaged across the SMC's battery sensors, or NAN if unavailable.
double BSReadBatteryTemperature(void);

/// Copies a text value from the SMC, such as the battery's build date ("BMDT"), into `buffer`.
/// Returns the text's length, or -1 if the key can't be read.
int BSReadSMCText(const char *key, char *buffer, int capacity);

#endif
