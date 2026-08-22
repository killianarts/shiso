(defpackage #:shiso/server
  (:use #:cl)
  (:local-nicknames (#:session #:shiso/auth/session)
                    (#:i18n #:shiso/i18n))
  (:export
   #:*server-connection*
   #:start
   #:stop
   #:wrap-app))

(in-package #:shiso/server)

(defparameter *server-connection* nil)

(defun %log-timestamp ()
  "ISO-8601-ish UTC timestamp for log lines."
  (multiple-value-bind (s m h d mo y)
      (decode-universal-time (get-universal-time) 0)
    (format nil "~4,'0D-~2,'0D-~2,'0D ~2,'0D:~2,'0D:~2,'0DZ" y mo d h m s)))

(defun wrap-error-logging (inner-app)
  "Outermost middleware: when a request handler signals an unhandled error,
print a timestamped line — method, URI, the condition, and a full backtrace —
to *error-output* (captured by journald under systemd, or whatever the process
stderr is redirected to), then let the error keep propagating so the server
still renders its 500. Without this an unhandled controller error yields a bare
500 with nothing recorded server-side.

Uses `handler-bind' (not `handler-case') so it observes the error without
unwinding: any inner `handler-case' still takes precedence, so only genuinely
unhandled errors are logged. Covers errors raised while building the response;
errors inside a streaming/SSE body fire later, outside this dynamic extent, and
are not caught here."
  (lambda (env)
    (handler-bind
        ((error
           (lambda (c)
             (ignore-errors
              (format *error-output*
                      "~&[~A] ERROR ~A ~A~%  ~A~%~A~%"
                      (%log-timestamp)
                      (getf env :request-method)
                      (getf env :request-uri)
                      c
                      (with-output-to-string (s)
                        (uiop:print-condition-backtrace c :stream s)))
              (force-output *error-output*)))))
      (funcall inner-app env))))

(defun wrap-app (inner-app)
  "Wrap INNER-APP with the standard shiso middleware stack: error logging
(outermost, so it also catches errors raised inside session/CSRF handling),
then session (DB-backed via Mito's connection) and CSRF protection. The session
middleware must precede CSRF so that the CSRF middleware can find the
session in env."
  (wrap-error-logging
   (funcall lack/middleware/session:*lack-middleware-session*
            (i18n:wrap-locale
             (funcall lack/middleware/csrf:*lack-middleware-csrf*
                      inner-app))
            :store (session:make-store))))

(defmacro start (app &rest args &key (host "127.0.0.1") (port 5000) (debugp t))
  (declare (ignore host port debugp))
  (let ((app-sym (shiso/routing:to-symbol-form app)))
    `(%start ,app-sym ,@args)))

(defun %start (app-symbol &key (host "127.0.0.1") (port 5000) (debugp t))
  (when *server-connection*
    (restart-case (error "Server is already running.")
      (restart-server ()
        :report "Restart the server"
        (stop))))
  (i18n:ensure-localisations)
  (let ((wrapped (wrap-app (symbol-value app-symbol))))
    (setf *server-connection*
          (clack:clackup (lambda (env) (funcall wrapped env))
                         :server :woo :address host :port port :debug debugp))))

(defun stop ()
  (prog1
      (clack:stop *server-connection*)
    (setf *server-connection* nil)))
