#ifndef FLUTTER_MY_APPLICATION_H_
#define FLUTTER_MY_APPLICATION_H_

#if __has_include(<gtk/gtk.h>)

#include <gtk/gtk.h>

G_DECLARE_FINAL_TYPE(MyApplication, my_application, MY, APPLICATION,
                     GtkApplication)

MyApplication* my_application_new();

#endif  // __has_include(<gtk/gtk.h>)

#endif  // FLUTTER_MY_APPLICATION_H_
