(module (ensemble interface console) (run)
(import
  scheme
  (chicken base)
  (chicken condition)
  (chicken file)
  (chicken format)
  (chicken irregex)
  (chicken pathname)
  (chicken plist)
  (chicken process-context)
  (chicken process)
  (chicken process signal)
  (chicken repl)
  srfi-1
  srfi-18
  srfi-71
  gochan
  utf8
  utf8-srfi-13
  utf8-srfi-14
  unicode-char-sets
  ioctl
  ncurses
  miscmacros
  (ensemble libs concurrency)
  (ensemble libs debug)
  (ensemble libs locations))

;; TODO “markup” for events
;; TODO persistent room numbering (irssi-like)
;; TODO special “log” room for backend informations / errors
;; TODO history navigation
;; TODO read marker
;; TODO support for multiple profiles/backends

(include-relative "input.scm")

(define +backend-executable+ "ensemble.backend.matrix")

(define tty-fileno 0)
(define rows)
(define cols)
(define inputwin)
(define statuswin)
(define messageswin)

(define worker)
(define *user-channel* (gochan 0))
(define *worker-channel* (gochan 0))

(define (worker-read-loop wrk)
  (let ((exp (worker-receive wrk)))
    (gochan-send *worker-channel* exp)
    (unless (eof-object? exp) (worker-read-loop wrk))))

(define (user-read-loop)
  (gochan-send *user-channel* (get-input))
  (user-read-loop))

(define (ipc-send . args)
  (info "Sending IPC: ~s" args)
  (worker-send worker args))


(define *query-number* 0)
(define *queries* '())

(define (ipc-query . args)
  (apply ipc-send 'query (inc! *query-number*) args)
  (call/cc
    (lambda (k)
      (push! (cons *query-number* k)
             *queries*)
      (main-loop))))

(define (handle-query-response id datum)
  (info "Queries waiting: ~a" (length *queries*))
  (and-let* ((pair (assoc id *queries*))
             (task (cdr pair)))
       (set! *queries* (delete! pair *queries*))
       (task datum)))

(define *notifications* '())
(define *highlights* '())
(define *read-marker* #f)

(define *rooms-offset* '())


;; Windows
;; =======

;; each window must have:
;; - an associated room id
;; - an associated worker/backend/profile
;; - a text / ID
;; - a notification and highlight count

;; except for a special frontend window and special backend/profile windows

(define *current-window* 'ensemble)
(define *special-windows* '(ensemble backend))
(define *room-windows* '())
(define *free-window-number* 0)

;; TODO remove
(define (current-room)
  (window-room *current-window*))

(define (special-window-log win)
  (or (get win 'log) '()))

(define (special-window-write id fmt . args)
  (assert (special-window? id))
  (let* ((str (sprintf "~?" fmt args)))
    (put! id 'log (cons str (special-window-log id)))
    (when (eqv? id *current-window*)
      (maybe-newline)
      (wprintw messageswin "~a" str))))

(define (special-window? id)
  (memv id *special-windows*))

(define (room-window? id)
  (not (special-window? id)))

(define (window-room win)
  (get win 'room-id))

(define (window-name win)
  (cond ((special-window? win)
         (symbol->string win))
        (else
          (room-display-name (window-room win)))))

(define (add-room-window room-id)
  (let ((id (string->symbol (->string (inc! *free-window-number*)))))
    (put! id 'room-id room-id)
    (put! id 'profile 'default) ;; TODO change that when multiple profiles are there
    (set! *room-windows*
      (append! *room-windows* (list id)))))

(define (rename-window from to)
  (let ((plist (symbol-plist from)))
    (cond ((special-window? from)
           (special-window-write 'ensemble
                                 "You can’t rename the special window: ~a"
                                 from))
          (else
            (set! (symbol-plist to) plist)
            (set! (symbol-plist from) '())
            (set! *room-windows*
              (cons to (delete! from *room-windows*)))
            (switch-window to)))))

(define (switch-window id)
  (cond ((special-window? id)
         (switch-special-window id))
        (else
          (switch-room-window id))))

(define (switch-special-window id)
  (set! *current-window* id)
  (refresh-statuswin)
  (refresh-current-window))

(define (switch-room-window id)
  (let ((current-room-id (window-room *current-window*))
        (room-id (window-room id)))
    (cond (room-id
           (when current-room-id
             (ipc-send 'unsubscribe current-room-id))
           (set! *current-window* id)
           (ipc-send 'subscribe id)
           (refresh-statuswin)
           (refresh-current-window))
          (else
            (special-window-write 'ensemble "No such room exist: ~a" id)))))

(define (refresh-current-window)
  (cond ((special-window? *current-window*)
         (refresh-special-window *current-window*))
        (else
          (refresh-room-window *current-window*))))

(define (refresh-room-window id)
  (maybe-newline)
  (wprintw messageswin "Loading…~%")
  (let ((room-id (window-room id)))
    (ipc-send 'fetch-events room-id rows
            (room-offset room-id))))

(define (refresh-special-window id)
  (wclear messageswin)
  (for-each
    (lambda (str)
      (maybe-newline)
      (wprintw messageswin "~a" str))
    (reverse (special-window-log id))))



;; DB Replacement
;; ==============

(define (room-display-name id)
  (ipc-query 'room-display-name id))


;; TUI
;; ===

(define (start-interface)
  ;; Make ncurses wait less time when receiving an ESC character
  (set-environment-variable! "ESCDELAY" "20")

  (initscr)
  (noecho)
  (cbreak)
  (start_color)
  (set!-values (rows cols) (getmaxyx (stdscr)))

  (set! messageswin (newwin (- rows 2) cols 0 0))
  (scrollok messageswin #t)
  (idlok messageswin #t)

  (set! inputwin (newwin 1 cols (- rows 1) 0))
  (keypad inputwin #t)
  (set! statuswin (newwin 1 cols (- rows 2) 0))
  (init_pair 1 COLOR_BLACK COLOR_WHITE)
  (init_pair 2 COLOR_BLUE COLOR_WHITE)
  (init_pair 3 COLOR_CYAN COLOR_BLACK)
  (wbkgdset statuswin (COLOR_PAIR 1))
  (special-window-write 'ensemble "Loading…"))

(define (waddstr* win str)
  (handle-exceptions exn #t
    (waddstr win str)))

(define (refresh-statuswin)
  (let* ((room-name (window-name *current-window*)))
    (werase statuswin)
    (waddstr* statuswin (sprintf "Room: ~a | " room-name))
    (for-each
      (lambda (win)
        (waddstr* statuswin
                  (if (eqv? win *current-window*)
                      (sprintf "[~a] " win)
                      (sprintf "~a " win))))
      (append *special-windows* *room-windows*))))

(define (room-offset room-id)
  (alist-ref room-id *rooms-offset* equal? 0))

(define (room-offset-set! room-id offset)
  (set! *rooms-offset*
    (alist-update! room-id offset *rooms-offset* equal?)))

(define (room-offset-delete! room-id)
  (set! *rooms-offset*
    (alist-delete! room-id *rooms-offset* equal?)))

(define (maybe-newline)
  (let ((l c (getyx messageswin)))
    (unless (zero? c) (wprintw messageswin "~%"))))



(define (run)
  (set! (signal-handler signal/winch)
    (lambda (_)
      (thread-start!
        (lambda ()
          (gochan-send *user-channel* 'resize)))))
  (set! (signal-handler signal/int)
    (lambda (_) (reset)))
  (cond-expand (debug (info-port (open-output-file "frontend.log"))) (else))
  (load-config)
  (on-exit save-config)
  (start-interface)
  (special-window-write 'ensemble "Starting backend…")
  (set! worker
    (start-worker 'default
      (lambda ()
        (or (process-execute* +backend-executable+ '("default"))
            (process-execute* (make-pathname (current-directory)
                                             +backend-executable+)
                              '("default"))))))
  (thread-start! user-read-loop)
  (thread-start! (lambda () (worker-read-loop worker)))
  (ipc-send 'connect)
  (let ((joined-rooms (ipc-query 'joined-rooms)))
    (special-window-write 'ensemble "Rooms joined: ~s" joined-rooms)
    (for-each add-room-window joined-rooms))
  (main-loop))

(define (load-config)
  (void))

(define (save-config)
  (void))


(define (process-execute* exec args)
  (handle-exceptions exn #f
    (process-execute exec args)))

(define (main-loop)
  (info "INTERFACE REFRESH")
  (wnoutrefresh messageswin)
  (wnoutrefresh statuswin)
  (wnoutrefresh inputwin)
  (doupdate)
  (gochan-select
    ((*worker-channel* -> msg fail)
     (handle-backend-response msg))
    ((*user-channel* -> msg fail)
     (if (eqv? msg 'resize)
         (resize-terminal)
         (handle-input msg))))
  (main-loop))

(define (get-input)
  (thread-wait-for-i/o! tty-fileno #:input)
  (wget_wch inputwin))

(define (resize-terminal)
  (let ((rows+cols (ioctl-winsize tty-fileno)))
    (set! rows (car rows+cols))
    (set! cols (cadr rows+cols))
    (move-extent cursor-pos) ;; input line cursor
    (resizeterm rows cols)
    (wresize messageswin (- rows 2) cols)
    (mvwin messageswin 0 0)
    (wresize statuswin 1 cols)
    (mvwin statuswin (- rows 2) 0)
    (wresize inputwin 1 cols)
    (mvwin inputwin (- rows 1) 0)
    (refresh-current-window)
    (refresh-statuswin)
    (refresh-inputwin)))

(define (handle-backend-response msg)
  (info "Recvd from backend: ~s" msg)
  (if (eof-object? msg)
      (handle-backend-disconnection worker)
      (case (car msg)
        ((bundle-start)
         (for-each
           handle-backend-response
           (collect-bundle-messages)))
        ((notifications)
         (set! *highlights* (cadr msg))
         (set! *notifications* (caddr msg))
         (refresh-statuswin))
        ((clear)
         (when (equal? (cadr msg) (current-room))
           (werase messageswin)))
        ((refresh)
         (when (equal? (cadr msg) (window-room *current-window*))
           (refresh-current-window)))
        ((response)
         (apply handle-query-response (cdr msg)))
        ((read-marker)
         (when (equal? (cadr msg) (current-room))
           (set! *read-marker* (symbol->string (caddr msg)))
           (refresh-current-window)))
        ((message)
         (when (equal? (cadr msg) (current-room))
           (maybe-newline)
           (when (alist-ref 'highlight (caddr msg))
             (wcolor_set messageswin 3 #f))
           (wprintw messageswin "~A"
                    (alist-ref 'formated (caddr msg)))
           (wcolor_set messageswin 0 #f)
           (when (equal? (alist-ref 'event_id (caddr msg))
                         *read-marker*)
             (wprintw messageswin "~A" (make-string cols #\-)))
           ))
        ((info)
         (special-window-write 'backend "~a" (cadr msg)))
        (else (info "Unknown message from backend: ~a" msg))
        )))

(define (handle-backend-disconnection worker)
  (error "Backend disconnected"))

(define (collect-bundle-messages)
  (let ((msg (gochan-recv *worker-channel*)))
    (if (equal? msg '(bundle-end))
        '()
        (cons msg (collect-bundle-messages)))))

) ;; tui module
