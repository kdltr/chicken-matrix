(load "low-level")

(use clojurian-syntax)

;; Helper procedures
;; =================

(define (mref keys alist)
  (if (null? keys)
      alist
      (and-let* ((o (alist-ref (car keys) alist)))
           (mref (cdr keys) o))))

(define (mupdate keys val alist)
  (if (null? (cdr keys))
      (alist-update (car keys) val alist)
      (alist-update (car keys)
                    (mupdate (cdr keys) val (or (alist-ref (car keys) alist) '()))
                    alist)))

(define (mdelete keys alist)
  (if (null? (cdr keys))
      (alist-delete (car keys) alist)
      (alist-update (car keys)
                    (mdelete (cdr keys) (or (alist-ref (car keys) alist) '()))
                    alist)))

;; High level API
;; ==============

(define transaction-id (make-parameter 0))
(define (new-txnid)
  (transaction-id (add1 (transaction-id))))

(define (password-login user password)
  (->> (login `((type . "m.login.password")
                (user . ,user)
                (password . ,password)))
       (alist-ref 'access_token)
       (access-token)))

;; TODO do that properly when low-level is a module
(define logout
  (let ((old-logout logout))
    (lambda () (old-logout '()))))


(define (message:text room text)
  (room-send room
             'm.room.message
             (new-txnid)
             `((msgtype . "m.text")
               (body . ,text))))

(define (message:emote room text)
  (room-send room
             'm.room.message
             (new-txnid)
             `((msgtype . "m.emote")
               (body . ,text))))

