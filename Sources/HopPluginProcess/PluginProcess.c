#include "HopPluginProcess.h"
#include <sys/event.h>
#include <unistd.h>
#include <errno.h>

int hop_plugin_watch_start(int pid) {
    int descriptor = kqueue();
    if (descriptor < 0) return -errno;
    struct kevent event;
    EV_SET(&event, pid, EVFILT_PROC, EV_ADD | EV_ENABLE | EV_ONESHOT,
           NOTE_EXIT | NOTE_EXITSTATUS, 0, NULL);
    if (kevent(descriptor, &event, 1, NULL, 0, NULL) < 0) {
        int error = errno;
        close(descriptor);
        return -error;
    }
    return descriptor;
}

long hop_plugin_watch_exit(int descriptor) {
    struct kevent event;
    int result;
    do { result = kevent(descriptor, NULL, 0, &event, 1, NULL); } while (result < 0 && errno == EINTR);
    int error = errno;
    close(descriptor);
    if (result != 1) return result == 0 ? -EINVAL : -error;
    if ((event.fflags & NOTE_EXITSTATUS) == 0) return -1;
    return event.data;
}
