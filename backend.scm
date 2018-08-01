(include "debug.scm")
(include "locations.scm")
(include "nonblocking-ports.scm")
(include "concurrency.scm")

(module backend (run)
(import
  (except scheme
          string-length string-ref string-set! make-string string substring
          string->list list->string string-fill! write-char read-char display)
  (except chicken
          reverse-list->string print print*)
  (except data-structures
          ->string conc string-chop string-split string-translate
          substring=? substring-ci=? substring-index substring-index-ci)
  ports files posix srfi-1 extras miscmacros irregex
  concurrency debug locations nonblocking-ports)

(use utf8 utf8-srfi-13 vector-lib uri-common openssl
     intarweb (except medea read-json) cjson
     rest-bind (prefix http-client http:)
     sandbox srfi-71)

(define +ensemble-version+ "dev")

(define rpc-env (make-safe-environment name: 'rpc-environment
                                       mutable: #f
                                       extendable: #f))

(include "matrix.scm")
(include "client.scm")

(define (run)
  (current-error-port (open-output-file "backend.log"))
  (current-input-port (open-input-file*/nonblocking 0))
  (current-output-port (open-output-file*/nonblocking 1))
  ;; Enable server certificate validation for https URIs.
  (http:server-connector
    (make-ssl-server-connector
      (ssl-make-client-context* verify?: (not (member "--no-ssl-verify"
                                                      (command-line-arguments))))))
  (load-profile)
  (defer 'rpc read)
  (main-loop))

(define ((make-ssl-server-connector ctx) uri proxy)
  (let ((remote-end (or proxy uri)))
    (if (eq? 'https (uri-scheme remote-end))
        (ssl-connect (uri-host remote-end)
                     (uri-port remote-end)
                     ctx)
        (http:default-server-connector uri proxy))))

(define (load-profile)
  (let ((uri (config-ref 'server-uri)))
    (when uri (init! uri))
    (access-token (config-ref 'access-token))
    (mxid (config-ref 'mxid))))

(define (main-loop)
  (let ((th (receive-defered)))
    (receive (who datum) (thread-join-protected! th)
      (case who
        ((sync) (defer 'sync sync timeout: 30000 since: (handle-sync datum)))
        ((rpc) (handle-rpc datum) (defer 'rpc read))
        ((hole-messages) (apply fill-hole datum))
        (else  (info "Unknown defered procedure: ~a ~s~%" who datum))
      )))
  (main-loop))

(define (handle-rpc exp)
  (info "received: ~s" exp)
  (set! *frontend-idling* #f)
  (if (eof-object? exp)
      (exit)
      (let ((res (safe-eval exp environment: rpc-env)))
        (unless (eqv? res +delayed-reply-marker+)
          (info "replied: ~s" res)
          (write res)
          (newline)))))



;; RPC Procedures
;; ==============

(define *frontend-idling* #f)
(define *frontend-idle-msgs* '())
(define +delayed-reply-marker+ (gensym 'delayed-reply))

(define (notify-frontend type)
  (if *frontend-idling*
      (begin
        (info "replied: ~s" type)
        (print type))
      (unless (memv type *frontend-idle-msgs*)
        (push! type *frontend-idle-msgs*)))
  (set! *frontend-idling* #f))

(safe-environment-set!
  rpc-env 'idle
  (lambda ()
    (if (null? *frontend-idle-msgs*)
        (begin
          (set! *frontend-idling* #t)
          +delayed-reply-marker+)
        (pop! *frontend-idle-msgs*))))

(safe-environment-set!
  rpc-env 'stop (lambda () 'stopped))


(define (find-room regex)
  (define (searched-string ctx)
    (or (room-name ctx)
        (json-true? (mref '(("" . m.room.canonical_alias) alias) ctx))
        (and-let* ((v (json-true? (mref '(("" . m.room.aliases) aliases) ctx))))
             (vector-ref v 0))
        (string-join
         (filter-map (lambda (p)
                       (and (equal? (cdar p) 'm.room.member)
                            (or (member-displayname (caar p) ctx)
                                (caar p))))
                     ctx))
        ""))
  (find (lambda (room-id)
          (irregex-search (irregex regex 'i)
                          (searched-string (room-context room-id))))
        (joined-rooms)))

(safe-environment-set!
  rpc-env 'find-room find-room)


(safe-environment-set!
  rpc-env 'connect
  (lambda ()
    (let ((next-batch (sync since: (config-ref 'next-batch))))
      (defer 'sync sync timeout: 30000 since: (handle-sync next-batch))
      #t)))

(safe-environment-set!
  rpc-env 'fetch-events
  (lambda (room-id)
    (let* ((ptr (get room-id 'frontend-pointer))
           (tl (room-timeline room-id))
           (_ after (if ptr (split-timeline tl ptr) (values '() tl))))
      (put! room-id 'frontend-pointer (car tl))
      after)))

(safe-environment-set!
  rpc-env 'any-room any-room)

(safe-environment-set!
  rpc-env 'message:text
  (lambda (room-id str)
    (message:text room-id str)
    #t))

(safe-environment-set!
  rpc-env 'message:emote
  (lambda (room-id str)
    (message:emote room-id str)
    #t))

(safe-environment-set!
  rpc-env 'fetch-notifications
  (lambda ()
    (filter (lambda (r)
              (let ((n (get r 'notifications)))
                (and n (not (zero? n)))))
            *rooms*)))

(safe-environment-set!
  rpc-env 'fetch-highlights
  (lambda ()
    (filter (lambda (r)
              (let ((n (get r 'highlights)))
                (and n (not (zero? n)))))
            *rooms*)))

(safe-environment-set!
  rpc-env 'room-display-name room-display-name)

(safe-environment-set!
  rpc-env 'mark-last-message-as-read
  (lambda (id)
    (mark-last-message-as-read id)
    #t))

(run)
) ;; backend module