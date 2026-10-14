#ifndef RUNNER_TASKBAR_BADGE_H_
#define RUNNER_TASKBAR_BADGE_H_

#include <shobjidl.h>
#include <windows.h>

#include <string>

class TaskbarBadge {
 public:
  TaskbarBadge() = default;
  ~TaskbarBadge();

  TaskbarBadge(const TaskbarBadge&) = delete;
  TaskbarBadge& operator=(const TaskbarBadge&) = delete;

  bool Set(HWND hwnd, const std::string& utf8_label);

  void Release();

 private:
  bool EnsureTaskbar();
  static HICON RenderIcon(const std::wstring& label);

  ITaskbarList3* taskbar_ = nullptr;
  HICON icon_ = nullptr;
};

#endif  // RUNNER_TASKBAR_BADGE_H_
