#include "my_application.h"

#include <cstdlib>

int main(int argc, char** argv) {
  // Mitigate Flutter Linux NVIDIA/Wayland GDK segfault on maximize/fullscreen
  // while falling back to Wayland when X11 is unavailable and respecting any
  // explicit user GDK_BACKEND override.
  if (std::getenv("GDK_BACKEND") == nullptr) {
    const char* display = std::getenv("DISPLAY");
    if (display != nullptr && display[0] != '\0') {
      setenv("GDK_BACKEND", "x11,wayland", 0);
    }
  }

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
