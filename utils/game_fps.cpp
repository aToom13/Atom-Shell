// Count the selected application's XPresent pixmaps, never screen captures or HUD redraws.
#include <X11/Xlib.h>
#include <X11/extensions/Xpresent.h>
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <poll.h>
#include <unordered_map>
#include <unordered_set>

using Clock = std::chrono::steady_clock;
int ignoreError(Display*, XErrorEvent*) { return 0; } // A game may destroy a window between queries.

void watch(Display* d, Window w, unsigned long pid, bool child, Atom pidAtom,
           std::unordered_set<Window>& watched, unsigned depth = 0) {
    if (depth > 64) return;
    Atom type; int format; unsigned long count, remaining; unsigned char* data = nullptr;
    if (!child && XGetWindowProperty(d, w, pidAtom, 0, 1, False, AnyPropertyType,
            &type, &format, &count, &remaining, &data) == Success && data) {
        child = format == 32 && count == 1 && *reinterpret_cast<unsigned long*>(data) == pid;
        XFree(data);
    }
    if (child && watched.insert(w).second) {
        XPresentSelectInput(d, w, PresentCompleteNotifyMask);
        XSelectInput(d, w, StructureNotifyMask);
    }
    Window root, parent, *children = nullptr; unsigned n = 0;
    if (XQueryTree(d, w, &root, &parent, &children, &n)) {
        for (unsigned i = 0; i < n; ++i) watch(d, children[i], pid, child, pidAtom, watched, depth + 1);
        if (children) XFree(children);
    }
}

int main(int argc, char** argv) {
    char* end = nullptr;
    const auto pid = argc == 2 ? std::strtoul(argv[1], &end, 10) : 0;
    if (!pid || !end || *end || pid > 2147483647) return 2;
    auto* d = XOpenDisplay(nullptr);
    if (!d) { puts("{\"fps\":null,\"error\":\"X11 bağlantısı yok\"}"); return 1; }
    XSetErrorHandler(ignoreError);
    int opcode, event, error;
    if (!XPresentQueryExtension(d, &opcode, &event, &error)) { XCloseDisplay(d); return 1; }
    const auto pidAtom = XInternAtom(d, "_NET_WM_PID", False);
    std::unordered_set<Window> watched;
    std::unordered_map<Window, unsigned> frames;
    bool measured = false;
    auto sample = Clock::now(), scan = sample - std::chrono::seconds(3);
    for (;;) {
        const auto now = Clock::now();
        if (now - scan >= std::chrono::seconds(2)) {
            watch(d, DefaultRootWindow(d), pid, false, pidAtom, watched);
            XFlush(d);
            scan = now;
        }
        while (XPending(d)) {
            XEvent e; XNextEvent(d, &e);
            if (e.type == DestroyNotify) { watched.erase(e.xdestroywindow.window); frames.erase(e.xdestroywindow.window); }
            if (e.type != GenericEvent || e.xcookie.extension != opcode || !XGetEventData(d, &e.xcookie)) continue;
            if (e.xcookie.evtype == PresentCompleteNotify) {
                const auto* p = static_cast<XPresentCompleteNotifyEvent*>(e.xcookie.data);
                if (watched.contains(p->window) && p->kind == PresentCompleteKindPixmap) {
                    // Skipped presents are still real application frames; generated overlay frames have a different PID.
                    ++frames[p->window]; measured = true;
                }
            }
            XFreeEventData(d, &e.xcookie);
        }
        const auto elapsed = std::chrono::duration<double>(Clock::now() - sample).count();
        if (elapsed >= 1) {
            unsigned count = 0;
            for (const auto& [window, n] : frames) count = std::max(count, n);
            // Use the busiest swapchain, avoiding double-counting auxiliary/child windows.
            if (measured) printf("{\"fps\":%.1f,\"source\":\"XPresent\"}\n", count / elapsed);
            else puts("{\"fps\":null,\"error\":\"Oyun henüz kare sunmadı\"}");
            fflush(stdout); frames.clear(); sample = Clock::now();
        }
        pollfd fd{ConnectionNumber(d), POLLIN, 0};
        if (poll(&fd, 1, 100) < 0 || (fd.revents & (POLLERR | POLLHUP | POLLNVAL))) break;
    }
    XCloseDisplay(d);
}
