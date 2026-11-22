#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shobjidl.h>

#include <cwchar>

#include "flutter_window.h"
#include "utils.h"

// Velopack runs the installed exe once at install, update and uninstall with
// --veloapp-install / --veloapp-updated / --veloapp-obsolete / --veloapp-uninstall
// <version> and waits a few seconds for it to exit. An app that does not answer
// is killed and Setup reports "Install Partially Succeeded". NaviVibe has
// nothing to do in these hooks, so it exits 0 before creating a window.
static bool IsVelopackHook(const wchar_t *command_line) {
  return command_line != nullptr && wcsstr(command_line, L"--veloapp-") != nullptr;
}

// A second copy would double every connection and poll and fight the first for
// the media session. If NaviVibe is already running, bring its window forward
// (it may be minimised or hidden in the tray) and let this copy exit.
static bool ActivateRunningInstance() {
  HWND existing = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"NaviVibe");
  if (existing == nullptr) {
    return false;
  }
  ::ShowWindow(existing, ::IsIconic(existing) ? SW_RESTORE : SW_SHOW);
  ::SetForegroundWindow(existing);
  return true;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  if (IsVelopackHook(command_line)) {
    return EXIT_SUCCESS;
  }

#ifdef NDEBUG
  // Debug runs (flutter run) may sit beside an installed copy, and a profile
  // run can too with --allow-multiple.
  const bool allow_multiple =
      command_line != nullptr && wcsstr(command_line, L"--allow-multiple") != nullptr;
  HANDLE single_instance =
      allow_multiple ? nullptr : ::CreateMutexW(nullptr, TRUE, L"Local\\NaviVibeSingleInstance");
  if (single_instance != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    ActivateRunningInstance();
    ::CloseHandle(single_instance);
    return EXIT_SUCCESS;
  }
#endif

  // One stable identity for the taskbar, the volume flyout (SMTC) and toasts.
  // Must match AppNotifier._aumid in Dart, and be set before any window exists.
  ::SetCurrentProcessExplicitAppUserModelID(L"NaviVibe");

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");
  // Skia, not Impeller: measured on the profile build, the window idles at about
  // 430 MB instead of 850 MB. Nothing here needs Impeller's extras.
  project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"NaviVibe", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
