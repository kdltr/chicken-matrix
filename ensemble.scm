(include "debug.scm")
(include "locations.scm")
(include "nonblocking-ports.scm")
(include "concurrency.scm")
(include "tui/base.scm")

(module main ()
(import
  scheme
  (chicken base)
  (chicken condition)
  (chicken foreign)
  (chicken format)
  ncurses
  tui)

(foreign-declare "#include <locale.h>")
(foreign-code "setlocale(LC_ALL, \"C.UTF-8\");")

(handle-exceptions exn
  (begin
    (on-exit void)
    ;; Disable ncurses before printing the error message and call trace
    (endwin)
    (fprintf (current-error-port) "Exception caught: ~s" exn)
    (signal exn))
  (on-exit endwin)
  (run)))
