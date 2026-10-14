#include "taskbar_badge.h"

#include <cstdint>

TaskbarBadge::~TaskbarBadge() { Release(); }

void TaskbarBadge::Release() {
  if (icon_) {
    ::DestroyIcon(icon_);
    icon_ = nullptr;
  }
  if (taskbar_) {
    taskbar_->Release();
    taskbar_ = nullptr;
  }
}

static std::wstring WideFromUtf8(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }
  int length = ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(),
                                     static_cast<int>(utf8.size()), nullptr, 0);
  if (length <= 0) {
    return std::wstring();
  }
  std::wstring wide(static_cast<size_t>(length), wchar_t{});
  ::MultiByteToWideChar(CP_UTF8, 0, utf8.data(), static_cast<int>(utf8.size()),
                        wide.data(), length);
  return wide;
}

bool TaskbarBadge::Set(HWND hwnd, const std::string& utf8_label) {
  if (!hwnd || !EnsureTaskbar()) {
    return false;
  }
  const std::wstring label = WideFromUtf8(utf8_label);
  HICON icon = label.empty() ? nullptr : RenderIcon(label);
  if (!label.empty() && !icon) {
    return false;
  }
  HRESULT hr = taskbar_->SetOverlayIcon(hwnd, icon,
                                        icon ? label.c_str() : nullptr);
  if (icon_) {
    ::DestroyIcon(icon_);
  }
  icon_ = icon;
  return SUCCEEDED(hr);
}

bool TaskbarBadge::EnsureTaskbar() {
  if (taskbar_) {
    return true;
  }
  if (FAILED(::CoCreateInstance(CLSID_TaskbarList, nullptr,
                                CLSCTX_INPROC_SERVER,
                                IID_PPV_ARGS(&taskbar_)))) {
    taskbar_ = nullptr;
    return false;
  }
  if (FAILED(taskbar_->HrInit())) {
    taskbar_->Release();
    taskbar_ = nullptr;
    return false;
  }
  return true;
}

HICON TaskbarBadge::RenderIcon(const std::wstring& label) {
  int size = ::GetSystemMetrics(SM_CXSMICON);
  if (size <= 0) {
    size = 16;
  }

  BITMAPINFO info = {};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = size;
  info.bmiHeader.biHeight = -size;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;

  HDC screen = ::GetDC(nullptr);
  HDC dc = ::CreateCompatibleDC(screen);
  void* bits = nullptr;
  HBITMAP color =
      ::CreateDIBSection(dc, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
  if (!color || !bits) {
    if (color) {
      ::DeleteObject(color);
    }
    ::DeleteDC(dc);
    ::ReleaseDC(nullptr, screen);
    return nullptr;
  }
  HGDIOBJ previous_bitmap = ::SelectObject(dc, color);

  HBRUSH fill = ::CreateSolidBrush(RGB(0xE5, 0x39, 0x35));
  HGDIOBJ previous_brush = ::SelectObject(dc, fill);
  HGDIOBJ previous_pen = ::SelectObject(dc, ::GetStockObject(NULL_PEN));
  ::Ellipse(dc, 0, 0, size + 1, size + 1);

  const int percent = label.size() >= 3 ? 50 : (label.size() == 2 ? 62 : 75);
  HFONT font = ::CreateFontW(-(size * percent / 100), 0, 0, 0, FW_BOLD, FALSE,
                             FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                             CLIP_DEFAULT_PRECIS, ANTIALIASED_QUALITY,
                             DEFAULT_PITCH | FF_SWISS, L"Segoe UI");
  HGDIOBJ previous_font = ::SelectObject(dc, font);
  ::SetBkMode(dc, TRANSPARENT);
  ::SetTextColor(dc, RGB(0xFF, 0xFF, 0xFF));
  RECT bounds = {0, 0, size, size};
  ::DrawTextW(dc, label.c_str(), -1, &bounds,
              DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
  ::GdiFlush();

  auto* pixels = static_cast<uint32_t*>(bits);
  for (int i = 0; i < size * size; ++i) {
    if (pixels[i] & 0x00FFFFFF) {
      pixels[i] |= 0xFF000000;
    }
  }

  ::SelectObject(dc, previous_font);
  ::SelectObject(dc, previous_pen);
  ::SelectObject(dc, previous_brush);
  ::SelectObject(dc, previous_bitmap);
  ::DeleteObject(font);
  ::DeleteObject(fill);

  HBITMAP mask = ::CreateBitmap(size, size, 1, 1, nullptr);
  ICONINFO icon_info = {};
  icon_info.fIcon = TRUE;
  icon_info.hbmMask = mask;
  icon_info.hbmColor = color;
  HICON icon = ::CreateIconIndirect(&icon_info);

  ::DeleteObject(mask);
  ::DeleteObject(color);
  ::DeleteDC(dc);
  ::ReleaseDC(nullptr, screen);
  return icon;
}
