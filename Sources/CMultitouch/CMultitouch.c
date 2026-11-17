#include "CMultitouch.h"

#include <dlfcn.h>
#include <pthread.h>
#include <stdatomic.h>

#define MULTITOUCH_PATH "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

typedef int (*MTContactCallback)(OGMTDeviceRef, OGMTContact *, int32_t, double, int32_t);

static struct {
    CFMutableArrayRef (*createList)(void);
    void (*registerCallback)(OGMTDeviceRef, MTContactCallback);
    void (*unregisterCallback)(OGMTDeviceRef, MTContactCallback);
    void (*start)(OGMTDeviceRef, int32_t);
    void (*stop)(OGMTDeviceRef);
    int32_t (*getFamilyID)(OGMTDeviceRef, int32_t *);
    int32_t (*getDeviceID)(OGMTDeviceRef, uint64_t *);
    bool (*isBuiltIn)(OGMTDeviceRef);
    int32_t (*getSurfaceDimensions)(OGMTDeviceRef, int32_t *, int32_t *);
    CFTypeRef (*actuatorCreate)(uint64_t);
    int32_t (*actuatorOpen)(CFTypeRef);
    int32_t (*actuatorActuate)(CFTypeRef, int32_t, uint32_t, float, float);
    bool available;
} mt;

static pthread_once_t loadOnce = PTHREAD_ONCE_INIT;

static void load(void) {
    void *handle = dlopen(MULTITOUCH_PATH, RTLD_LAZY);
    if (handle == NULL) {
        return;
    }
    mt.createList = dlsym(handle, "MTDeviceCreateList");
    mt.registerCallback = dlsym(handle, "MTRegisterContactFrameCallback");
    mt.unregisterCallback = dlsym(handle, "MTUnregisterContactFrameCallback");
    mt.start = dlsym(handle, "MTDeviceStart");
    mt.stop = dlsym(handle, "MTDeviceStop");
    mt.getFamilyID = dlsym(handle, "MTDeviceGetFamilyID");
    mt.getDeviceID = dlsym(handle, "MTDeviceGetDeviceID");
    mt.isBuiltIn = dlsym(handle, "MTDeviceIsBuiltIn");
    mt.getSurfaceDimensions = dlsym(handle, "MTDeviceGetSensorSurfaceDimensions");
    mt.actuatorCreate = dlsym(handle, "MTActuatorCreateFromDeviceID");
    mt.actuatorOpen = dlsym(handle, "MTActuatorOpen");
    mt.actuatorActuate = dlsym(handle, "MTActuatorActuate");
    mt.available = mt.createList && mt.registerCallback && mt.unregisterCallback && mt.start && mt.stop;
}

bool OGMTIsAvailable(void) {
    pthread_once(&loadOnce, load);
    return mt.available;
}

CFArrayRef OGMTCopyDevices(void) {
    if (!OGMTIsAvailable()) {
        return NULL;
    }
    return mt.createList();
}

static _Atomic(OGMTFrameHandler) frameHandler;
static _Atomic(void *) frameHandlerContext;

static int trampoline(OGMTDeviceRef device, OGMTContact *contacts, int32_t count, double timestamp, int32_t frame) {
    (void)frame;
    OGMTFrameHandler handler = atomic_load(&frameHandler);
    if (handler != NULL) {
        handler(atomic_load(&frameHandlerContext), device, contacts, count, timestamp);
    }
    return 0;
}

void OGMTSetFrameHandler(OGMTFrameHandler handler, void *context) {
    atomic_store(&frameHandlerContext, context);
    atomic_store(&frameHandler, handler);
}

void OGMTStartDevice(OGMTDeviceRef device) {
    if (!OGMTIsAvailable()) {
        return;
    }
    mt.registerCallback(device, trampoline);
    mt.start(device, 0);
}

void OGMTStopDevice(OGMTDeviceRef device) {
    if (!OGMTIsAvailable()) {
        return;
    }
    mt.unregisterCallback(device, trampoline);
    mt.stop(device);
}

int32_t OGMTDeviceFamilyID(OGMTDeviceRef device) {
    int32_t family = 0;
    if (OGMTIsAvailable() && mt.getFamilyID != NULL) {
        mt.getFamilyID(device, &family);
    }
    return family;
}

uint64_t OGMTDeviceID(OGMTDeviceRef device) {
    uint64_t identifier = 0;
    if (OGMTIsAvailable() && mt.getDeviceID != NULL) {
        mt.getDeviceID(device, &identifier);
    }
    return identifier;
}

bool OGMTDeviceIsBuiltIn(OGMTDeviceRef device) {
    return OGMTIsAvailable() && mt.isBuiltIn != NULL && mt.isBuiltIn(device);
}

bool OGMTDeviceSurfaceSize(OGMTDeviceRef device, double *width, double *height) {
    if (!OGMTIsAvailable() || mt.getSurfaceDimensions == NULL) {
        return false;
    }
    int32_t w = 0, h = 0;
    if (mt.getSurfaceDimensions(device, &w, &h) != 0 || w <= 0 || h <= 0) {
        return false;
    }
    // Reported in hundredths of a millimetre.
    *width = w / 100.0;
    *height = h / 100.0;
    return true;
}

#define ACTUATOR_CACHE_SIZE 8

static struct {
    uint64_t deviceID;
    CFTypeRef actuator;
} actuators[ACTUATOR_CACHE_SIZE];
static pthread_mutex_t actuatorLock = PTHREAD_MUTEX_INITIALIZER;

static CFTypeRef actuatorForDevice(uint64_t deviceID) {
    for (int i = 0; i < ACTUATOR_CACHE_SIZE; i++) {
        if (actuators[i].actuator != NULL && actuators[i].deviceID == deviceID) {
            return actuators[i].actuator;
        }
    }
    CFTypeRef actuator = mt.actuatorCreate(deviceID);
    if (actuator == NULL) {
        return NULL;
    }
    if (mt.actuatorOpen(actuator) != 0) {
        CFRelease(actuator);
        return NULL;
    }
    for (int i = 0; i < ACTUATOR_CACHE_SIZE; i++) {
        if (actuators[i].actuator == NULL) {
            actuators[i].deviceID = deviceID;
            actuators[i].actuator = actuator;
            break;
        }
    }
    return actuator;
}

bool OGMTActuate(uint64_t deviceID, int32_t actuation) {
    if (!OGMTIsAvailable() || mt.actuatorCreate == NULL || mt.actuatorOpen == NULL || mt.actuatorActuate == NULL) {
        return false;
    }
    pthread_mutex_lock(&actuatorLock);
    CFTypeRef actuator = actuatorForDevice(deviceID);
    bool ok = actuator != NULL && mt.actuatorActuate(actuator, actuation, 0, 0.0f, 0.0f) == 0;
    pthread_mutex_unlock(&actuatorLock);
    return ok;
}

typedef void (*DockSendNotification)(CFStringRef, int32_t);
static DockSendNotification dockSendNotification;
static pthread_once_t dockOnce = PTHREAD_ONCE_INIT;

static void loadDock(void) {
    dockSendNotification = (DockSendNotification)dlsym(RTLD_DEFAULT, "CoreDockSendNotification");
}

bool OGDockSendNotification(CFStringRef name) {
    pthread_once(&dockOnce, loadDock);
    if (dockSendNotification == NULL) {
        return false;
    }
    // The second argument is required on current macOS releases; calls without
    // it are silently ignored by the Dock.
    dockSendNotification(name, 0);
    return true;
}

static atomic_bool scrollClaimed = false;

void OGSetScrollClaimed(bool claimed) {
    atomic_store_explicit(&scrollClaimed, claimed, memory_order_relaxed);
}

bool OGIsScrollClaimed(void) {
    return atomic_load_explicit(&scrollClaimed, memory_order_relaxed);
}

static atomic_int touchingDevices = 0;

void OGSetTouchingDevices(int devices) {
    atomic_store_explicit(&touchingDevices, devices, memory_order_relaxed);
}

int OGTouchingDevices(void) {
    return atomic_load_explicit(&touchingDevices, memory_order_relaxed);
}
