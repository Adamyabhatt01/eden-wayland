// SPDX-FileCopyrightText: Copyright 2026 Eden Wayland Project
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Read-only probe for the Qt Wayland native-resource assumptions used by
// src/qt_common/qt_common.cpp and src/yuzu/bootmanager.cpp:
//   - nativeResourceForWindow("display") is the wl_display;
//   - nativeResourceForWindow("surface") is the wl_surface;
//   - a child widget with WA_NativeWindow/WA_PaintOnScreen/WA_DontCreateNativeAncestors
//     produces its own surface (Qt uses wl_subsurface internally).
//
// On X11 the "surface" resource is intentionally null: Eden uses winId().
//
// Build (private QPA headers are required):
//   inc=$(pkg-config --variable=includedir Qt6Gui)
//   ver=$(qmake6 -query QT_VERSION)
//   c++ -std=c++20 -O2 -fPIC -I"$inc/QtGui/$ver/QtGui" \
//       -o /tmp/qt-wl-native-probe tools/wayland/qt-wl-native-probe.cpp \
//       $(pkg-config --cflags --libs Qt6Gui Qt6Widgets)
//
// Run:
//   QT_QPA_PLATFORM=wayland /tmp/qt-wl-native-probe
//   QT_QPA_PLATFORM=xcb /tmp/qt-wl-native-probe
// Add WAYLAND_DEBUG=client to observe wl_subcompositor/wl_subsurface.

#include <QApplication>
#include <QTimer>
#include <QWidget>
#include <QWindow>
#include <qpa/qplatformnativeinterface.h>

#include <cstdio>

namespace {

struct Handles {
    void* display;
    void* surface;
};

Handles query(QWindow* window) {
    QPlatformNativeInterface* pni = QGuiApplication::platformNativeInterface();
    if (pni == nullptr || window == nullptr) {
        return {nullptr, nullptr};
    }
    return {pni->nativeResourceForWindow("display", window),
            pni->nativeResourceForWindow("surface", window)};
}

void print(const char* name, QWindow* window) {
    const Handles handles = query(window);
    std::printf("%s: window=%p display=%p surface=%p dpr=%.2f size=%dx%d\n", name,
                static_cast<void*>(window), handles.display, handles.surface,
                window ? window->devicePixelRatio() : 0.0, window ? window->width() : 0,
                window ? window->height() : 0);
}

} // Anonymous namespace

int main(int argc, char** argv) {
    QApplication app(argc, argv);
    const QString platform = QGuiApplication::platformName();

    QWidget top;
    top.setWindowTitle(QStringLiteral("qt-wl-native-probe"));
    top.resize(400, 300);

    auto* child = new QWidget(&top);
    child->setAttribute(Qt::WA_NativeWindow);
    child->setAttribute(Qt::WA_PaintOnScreen);
    child->setAttribute(Qt::WA_DontCreateNativeAncestors);
    child->setGeometry(10, 10, 320, 240);

    top.show();
    if (child->windowHandle() != nullptr) {
        child->windowHandle()->create();
    }
    QCoreApplication::processEvents();

    print("top-level", top.windowHandle());
    print("child", child->windowHandle());
    std::printf("platform=%s\n", qPrintable(platform));

    const Handles top_shown = query(top.windowHandle());
    const Handles child_shown = query(child->windowHandle());

    QTimer::singleShot(500, &app, &QCoreApplication::quit);
    app.exec();

    const bool wayland = platform.startsWith(QStringLiteral("wayland"));
    if (top_shown.display == nullptr || (wayland && top_shown.surface == nullptr) ||
        (wayland && child_shown.surface == nullptr)) {
        std::fprintf(stderr, "FAIL: required native handles are null\n");
        return 1;
    }
    if (!wayland) {
        std::printf("note: non-Wayland platform; Eden uses winId() for the render surface\n");
    }
    std::printf("PASS\n");
    return 0;
}
