// Thin C interface to MultitouchSupport.framework.
//
// MultitouchSupport is a private Apple framework. Its symbols are resolved at
// run time with dlopen/dlsym so that the binary still launches, and reports a
// clear error, if a future macOS release removes or renames them.

#ifndef CMULTITOUCH_H
#define CMULTITOUCH_H

#include <CoreFoundation/CoreFoundation.h>
#include <stdbool.h>
#include <stdint.h>

CF_ASSUME_NONNULL_BEGIN

typedef struct {
    float x;
    float y;
} OGMTPoint;

typedef struct {
    OGMTPoint position;
    OGMTPoint velocity;
} OGMTVector;

/// One contact as delivered by the framework. The layout has been stable since
/// macOS 10.6 and is 96 bytes on both x86_64 and arm64.
typedef struct {
    int32_t frame;
    double timestamp;
    int32_t identifier;
    int32_t state;
    int32_t fingerID;
    int32_t handID;
    OGMTVector normalized;
    float size;
    int32_t reserved1;
    float angle;
    float majorAxis;
    float minorAxis;
    OGMTVector millimeters;
    int32_t reserved2[2];
    float density;
} OGMTContact;

enum {
    OGMTContactStateNotTracking = 0,
    OGMTContactStateStartInRange = 1,
    OGMTContactStateHoverInRange = 2,
    OGMTContactStateMakeTouch = 3,
    OGMTContactStateTouching = 4,
    OGMTContactStateBreakTouch = 5,
    OGMTContactStateLingerInRange = 6,
    OGMTContactStateOutOfRange = 7,
};

typedef void *OGMTDeviceRef;

typedef void (*OGMTFrameHandler)(void *_Nullable context,
                                 OGMTDeviceRef device,
                                 const OGMTContact *_Nullable contacts,
                                 int32_t count,
                                 double timestamp);

/// Loads the framework. Returns false if any required symbol is missing.
bool OGMTIsAvailable(void);

/// Returns the multitouch devices currently attached, or NULL. The caller owns
/// the array and must keep it alive while any of its devices are running.
CFArrayRef _Nullable OGMTCopyDevices(void) CF_RETURNS_RETAINED;

/// Sets the function that receives every contact frame from every started
/// device. Frames arrive on a framework-owned thread.
void OGMTSetFrameHandler(OGMTFrameHandler _Nullable handler, void *_Nullable context);

void OGMTStartDevice(OGMTDeviceRef device);
void OGMTStopDevice(OGMTDeviceRef device);

int32_t OGMTDeviceFamilyID(OGMTDeviceRef device);
uint64_t OGMTDeviceID(OGMTDeviceRef device);
bool OGMTDeviceIsBuiltIn(OGMTDeviceRef device);

/// Writes the sensor surface size in millimetres. Returns false if unknown.
bool OGMTDeviceSurfaceSize(OGMTDeviceRef device, double *width, double *height);

/// Plays a haptic pulse on a Force Touch trackpad. Returns false if the device
/// has no actuator or the call failed.
bool OGMTActuate(uint64_t deviceID, int32_t actuation);

/// Posts a Dock notification such as "com.apple.expose.awake".
bool OGDockSendNotification(CFStringRef name);

/// Whether the trackpad is in the middle of a gesture that owns scrolling.
/// Written on the multitouch thread, read by the scroll event tap; a plain
/// atomic so neither side ever waits on the other.
void OGSetScrollClaimed(bool claimed);
bool OGIsScrollClaimed(void);

CF_ASSUME_NONNULL_END

#endif
