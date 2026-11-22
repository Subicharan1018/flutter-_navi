#ifndef RUNNER_OPEN_FILES_H_
#define RUNNER_OPEN_FILES_H_

#include <windows.h>

// Identifies the WM_COPYDATA a second NaviVibe launch sends to the running one
// (see ActivateRunningInstance in main.cpp, FlutterWindow::MessageHandler).
constexpr ULONG_PTR kOpenFilesCopyData = 0x4E564F46;  // "NVOF"

#endif  // RUNNER_OPEN_FILES_H_
