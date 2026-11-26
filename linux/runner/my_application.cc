#include "my_application.h"

#include <flutter_linux/flutter_linux.h>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr char kWindowChannelName[] = "com.loriek.onlystream/window";

enum class WindowAction {
  kMinimize,
  kMaximize,
  kUnmaximize,
  kSetFullscreen,
  kClose,
};

struct WindowActionData {
  MyApplication* app;
  WindowAction action;
  bool fullscreen;
};

}  // namespace

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  FlView* view;
  FlMethodChannel* window_channel;
  gboolean is_maximized;
  gboolean is_fullscreen;
  gboolean is_focused;
  guint last_button;
  gdouble last_x_root;
  gdouble last_y_root;
  guint32 last_event_time;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static FlValue* build_window_state_value(MyApplication* self) {
  FlValue* map = fl_value_new_map();
  fl_value_set_string_take(map, "isMaximized",
                           fl_value_new_bool(self->is_maximized));
  fl_value_set_string_take(map, "isFullscreen",
                           fl_value_new_bool(self->is_fullscreen));
  fl_value_set_string_take(map, "isFocused",
                           fl_value_new_bool(self->is_focused));
  return map;
}

static void emit_window_state(MyApplication* self) {
  if (self->window_channel == nullptr) {
    return;
  }
  g_autoptr(FlValue) state = build_window_state_value(self);
  fl_method_channel_invoke_method(self->window_channel, "onWindowStateChanged",
                                  state, nullptr, nullptr, nullptr);
}

static gboolean window_state_event_cb(GtkWidget* widget,
                                      GdkEventWindowState* event,
                                      gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gboolean next_maximized =
      (event->new_window_state & GDK_WINDOW_STATE_MAXIMIZED) != 0;
  const gboolean next_fullscreen =
      (event->new_window_state & GDK_WINDOW_STATE_FULLSCREEN) != 0;
  const gboolean next_focused =
      (event->new_window_state & GDK_WINDOW_STATE_FOCUSED) != 0;

  if (next_maximized != self->is_maximized ||
      next_fullscreen != self->is_fullscreen ||
      next_focused != self->is_focused) {
    self->is_maximized = next_maximized;
    self->is_fullscreen = next_fullscreen;
    self->is_focused = next_focused;
    emit_window_state(self);
  }
  return FALSE;
}

static gboolean view_button_press_cb(GtkWidget* widget,
                                     GdkEventButton* event,
                                     gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  self->last_button = event->button;
  self->last_x_root = event->x_root;
  self->last_y_root = event->y_root;
  self->last_event_time = event->time;
  return FALSE;
}

static void window_destroy_cb(GtkWidget* widget, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  self->window = nullptr;
  self->view = nullptr;
}

static gboolean perform_window_action_idle(gpointer user_data) {
  WindowActionData* data = static_cast<WindowActionData*>(user_data);
  MyApplication* self = data->app;

  if (self->window != nullptr && GTK_IS_WINDOW(self->window) &&
      gtk_widget_get_realized(GTK_WIDGET(self->window))) {
    switch (data->action) {
      case WindowAction::kMinimize:
        gtk_window_iconify(self->window);
        break;
      case WindowAction::kMaximize:
        if (self->is_fullscreen) {
          gtk_window_unfullscreen(self->window);
        }
        gtk_window_maximize(self->window);
        break;
      case WindowAction::kUnmaximize:
        if (self->is_fullscreen) {
          gtk_window_unfullscreen(self->window);
        }
        gtk_window_unmaximize(self->window);
        break;
      case WindowAction::kSetFullscreen:
        if (data->fullscreen) {
          gtk_window_fullscreen(self->window);
        } else {
          gtk_window_unfullscreen(self->window);
        }
        break;
      case WindowAction::kClose:
        gtk_window_close(self->window);
        break;
    }
  }

  g_object_unref(self);
  g_free(data);
  return G_SOURCE_REMOVE;
}

static void schedule_window_action(MyApplication* self,
                                   WindowAction action,
                                   bool fullscreen = false) {
  WindowActionData* data = g_new0(WindowActionData, 1);
  data->app = MY_APPLICATION(g_object_ref(self));
  data->action = action;
  data->fullscreen = fullscreen;
  g_idle_add(perform_window_action_idle, data);
}

static bool parse_resize_edge(const gchar* edge_name, GdkWindowEdge* out_edge) {
  if (edge_name == nullptr) {
    return false;
  }
  if (g_strcmp0(edge_name, "top") == 0) {
    *out_edge = GDK_WINDOW_EDGE_NORTH;
    return true;
  }
  if (g_strcmp0(edge_name, "bottom") == 0) {
    *out_edge = GDK_WINDOW_EDGE_SOUTH;
    return true;
  }
  if (g_strcmp0(edge_name, "left") == 0) {
    *out_edge = GDK_WINDOW_EDGE_WEST;
    return true;
  }
  if (g_strcmp0(edge_name, "right") == 0) {
    *out_edge = GDK_WINDOW_EDGE_EAST;
    return true;
  }
  if (g_strcmp0(edge_name, "topLeft") == 0) {
    *out_edge = GDK_WINDOW_EDGE_NORTH_WEST;
    return true;
  }
  if (g_strcmp0(edge_name, "topRight") == 0) {
    *out_edge = GDK_WINDOW_EDGE_NORTH_EAST;
    return true;
  }
  if (g_strcmp0(edge_name, "bottomLeft") == 0) {
    *out_edge = GDK_WINDOW_EDGE_SOUTH_WEST;
    return true;
  }
  if (g_strcmp0(edge_name, "bottomRight") == 0) {
    *out_edge = GDK_WINDOW_EDGE_SOUTH_EAST;
    return true;
  }
  return false;
}

static void window_channel_method_call_cb(FlMethodChannel* channel,
                                          FlMethodCall* method_call,
                                          gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (g_strcmp0(method, "getWindowState") == 0) {
    if (self->window != nullptr && GTK_IS_WINDOW(self->window)) {
      self->is_maximized = gtk_window_is_maximized(self->window);
      self->is_focused = gtk_window_is_active(self->window);
    }
    g_autoptr(FlValue) state = build_window_state_value(self);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(state));
  } else if (g_strcmp0(method, "minimize") == 0) {
    schedule_window_action(self, WindowAction::kMinimize);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "maximize") == 0) {
    schedule_window_action(self, WindowAction::kMaximize);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "unmaximize") == 0) {
    schedule_window_action(self, WindowAction::kUnmaximize);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "setFullscreen") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    bool fullscreen = false;
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_BOOL) {
      fullscreen = fl_value_get_bool(args);
    } else if (args != nullptr &&
               fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* flag = fl_value_lookup_string(args, "fullscreen");
      if (flag != nullptr && fl_value_get_type(flag) == FL_VALUE_TYPE_BOOL) {
        fullscreen = fl_value_get_bool(flag);
      }
    }
    schedule_window_action(self, WindowAction::kSetFullscreen, fullscreen);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "close") == 0) {
    schedule_window_action(self, WindowAction::kClose);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "startDragging") == 0) {
    if (self->window != nullptr && GTK_IS_WINDOW(self->window) &&
        gtk_widget_get_realized(GTK_WIDGET(self->window)) &&
        !self->is_fullscreen) {
      const guint button = self->last_button != 0 ? self->last_button : 1;
      const guint32 timestamp =
          self->last_event_time != 0 ? self->last_event_time : GDK_CURRENT_TIME;
      gtk_window_begin_move_drag(self->window, static_cast<gint>(button),
                                 static_cast<gint>(self->last_x_root),
                                 static_cast<gint>(self->last_y_root),
                                 timestamp);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else if (g_strcmp0(method, "startResizing") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    const gchar* edge_str = nullptr;
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_STRING) {
      edge_str = fl_value_get_string(args);
    } else if (args != nullptr &&
               fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      FlValue* edge_val = fl_value_lookup_string(args, "edge");
      if (edge_val != nullptr &&
          fl_value_get_type(edge_val) == FL_VALUE_TYPE_STRING) {
        edge_str = fl_value_get_string(edge_val);
      }
    }
    GdkWindowEdge edge = GDK_WINDOW_EDGE_SOUTH_EAST;
    if (parse_resize_edge(edge_str, &edge) && self->window != nullptr &&
        GTK_IS_WINDOW(self->window) &&
        gtk_widget_get_realized(GTK_WIDGET(self->window)) &&
        !self->is_maximized && !self->is_fullscreen) {
      const guint button = self->last_button != 0 ? self->last_button : 1;
      const guint32 timestamp =
          self->last_event_time != 0 ? self->last_event_time : GDK_CURRENT_TIME;
      gtk_window_begin_resize_drag(self->window, edge, static_cast<gint>(button),
                                   static_cast<gint>(self->last_x_root),
                                   static_cast<gint>(self->last_y_root),
                                   timestamp);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to respond to window channel call: %s", error->message);
  }
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;

  // Use custom client-side window chrome rendered by Flutter (DesktopWindowFrame).
  // Must be configured before realizing/showing the GTK window.
  gtk_window_set_decorated(window, FALSE);
  gtk_window_set_title(window, "OnlyStream");
  gtk_window_set_default_size(window, 1280, 720);

  GdkGeometry hints{};
  hints.min_width = 800;
  hints.min_height = 540;
  gtk_window_set_geometry_hints(window, nullptr, &hints, GDK_HINT_MIN_SIZE);

  g_autofree gchar* exe_path = g_file_read_link("/proc/self/exe", nullptr);
  if (exe_path != nullptr) {
    g_autofree gchar* exe_dir = g_path_get_dirname(exe_path);
    g_autofree gchar* icon_path = g_build_filename(
        exe_dir, "data", "flutter_assets", "assets", "logo.png", nullptr);
    if (g_file_test(icon_path, G_FILE_TEST_IS_REGULAR)) {
      gtk_window_set_icon_from_file(window, icon_path, nullptr);
    }
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);
  // Explicitly disable Impeller for Linux Mesa/NVIDIA resize & maximize stability.
  fl_dart_project_set_enable_impeller(project, FALSE);

  FlView* view = fl_view_new(project);
  self->view = view;
  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, "#0B0B0D");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_add_events(GTK_WIDGET(view), GDK_BUTTON_PRESS_MASK);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  g_signal_connect(window, "window-state-event",
                   G_CALLBACK(window_state_event_cb), self);
  g_signal_connect(window, "destroy", G_CALLBACK(window_destroy_cb), self);
  g_signal_connect(view, "button-press-event",
                   G_CALLBACK(view_button_press_cb), self);

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  FlEngine* engine = fl_view_get_engine(view);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->window_channel = fl_method_channel_new(messenger, kWindowChannelName,
                                               FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->window_channel, window_channel_method_call_cb, self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  if (self->window_channel != nullptr) {
    fl_method_channel_set_method_call_handler(self->window_channel, nullptr,
                                              nullptr, nullptr);
  }
  g_clear_object(&self->window_channel);
  self->window = nullptr;
  self->view = nullptr;
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->window = nullptr;
  self->view = nullptr;
  self->window_channel = nullptr;
  self->is_maximized = FALSE;
  self->is_fullscreen = FALSE;
  self->is_focused = TRUE;
  self->last_button = 1;
  self->last_x_root = 0;
  self->last_y_root = 0;
  self->last_event_time = GDK_CURRENT_TIME;
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
