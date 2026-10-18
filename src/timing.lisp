(defpackage #:shiso/timing
  (:use #:cl)
  (:local-nicknames (#:settei #:almighty-settei)
                    (#:errors #:shiso/errors))
  (:export
   #:wrap-request-timing
   #:with-timing
   #:note-route
   #:*timing*
   #:*access-log-stream*
   #:*repeated-query-threshold*
   ;; The record of one request
   #:timing
   #:timing-db-count
   #:timing-db-usec
   #:timing-phases
   #:timing-route
   #:timing-queries))

(in-package #:shiso/timing)

;;;; Request timing: how long each request took in Lisp, and where the time
;;;; went (the database, garbage collection, phases the application names).
;;;; The outermost middleware measures it, sends it to the browser in a
;;;; Server-Timing header, and writes an access-log line. See
;;;; shiso-performance-plan.org, M1, M2 and M4.

;;; Settings

(settei:define-setting :server/timing-header settei:choice-setting
  "How much of a request's timing the Server-Timing header shows. TOTAL is
the time in Lisp only; FULL adds the database, garbage collection and the
phases WITH-TIMING names. Debug mode shows FULL to requests from this
machine. OFF sends no header."
  :options '(:total :full :off)
  :default :total)

(settei:define-setting :server/access-log settei:choice-setting
  "The access log: one line per request, with its status, time and
database queries. LOGFMT is key=value pairs; JSON is one object per line."
  :options '(:logfmt :json :off)
  :default :logfmt)

(settei:define-setting :server/slow-request-ms settei:integer-setting
  "A request that takes at least this many milliseconds in Lisp is logged
with its SQL statements and their times. 0 turns this off."
  :minimum 0
  :default 500)

;;; Tunables

(defvar *access-log-stream* nil
  "Where access-log lines go. NIL means *STANDARD-OUTPUT*, which systemd
sends to the journal.")

(defvar *repeated-query-threshold* 10
  "In debug mode, a request that runs the same SQL more than this many times
gets a warning in the log: usually an N+1 query.")

(defvar *max-recorded-queries* 200
  "The most SQL statements a request keeps for the slow-request log and the
repeated-query warning. All of them are counted.")

;;; The record of one request

(defstruct (timing (:constructor make-timing ()))
  (start (get-internal-real-time))
  (gc-start (gc-run-time))
  (db-usec 0)
  (db-count 0)
  ;; (SQL . MICROSECONDS-OR-NIL), newest first.
  (queries '())
  (recorded 0)
  ;; (NAME . MILLISECONDS), newest first, one per name.
  (phases '())
  ;; "module:name" of the route that answered, if any.
  (route nil))

(defvar *timing* nil
  "The TIMING of the request this thread is serving, or NIL.")

(defun gc-run-time ()
  #+sbcl sb-ext:*gc-run-time*
  #-sbcl 0)

(defun ms-between (start end)
  "Milliseconds between two GET-INTERNAL-REAL-TIME values."
  (/ (- end start) (/ internal-time-units-per-second 1000d0)))

;;; Recording

(defun record-sql (sql params row-count took-usec)
  "A cl-dbi SQL hook: count the statement, and its time, in the current
request. cl-dbi reports no time for BEGIN, COMMIT and ROLLBACK."
  (declare (ignore params row-count))
  (let ((timing *timing*))
    (when timing
      (incf (timing-db-count timing))
      (when took-usec
        (incf (timing-db-usec timing) took-usec))
      (when (< (timing-recorded timing) *max-recorded-queries*)
        (push (cons sql took-usec) (timing-queries timing))
        (incf (timing-recorded timing))))))

(pushnew 'record-sql dbi:*sql-execution-hooks*)

(defun note-route (label)
  "Record LABEL, \"module:name\", as the route answering this request."
  (let ((timing *timing*))
    (when timing
      (setf (timing-route timing) label))))

(defun phase-name (name)
  "NAME as a Server-Timing metric name: lowercase, with only letters, digits,
- and _."
  (let ((string (string-downcase (string name))))
    (substitute-if #\- (lambda (c) (not (or (alphanumericp c) (find c "-_"))))
                   string)))

(defun add-phase (timing name ms)
  (let* ((name (phase-name name))
         (entry (assoc name (timing-phases timing) :test #'string=)))
    (if entry
        (incf (cdr entry) ms)
        (push (cons name ms) (timing-phases timing)))))

(defun call-with-timing (name thunk)
  (let ((timing *timing*))
    (if (null timing)
        (funcall thunk)
        (let ((start (get-internal-real-time)))
          (unwind-protect (funcall thunk)
            (add-phase timing name (ms-between start (get-internal-real-time))))))))

(defmacro with-timing ((name) &body body)
  "Run BODY and record its time under NAME, a keyword or string, in the
current request's Server-Timing header and access-log line. Times add up
when NAME is used more than once. Outside a request, run BODY and record
nothing."
  `(call-with-timing ,name (lambda () ,@body)))

;;; The Server-Timing header

(defun full-timing-p (env)
  (case (ignore-errors (settei:setting :server/timing-header))
    (:full t)
    (:off nil)
    (t (and (errors:debug-mode) (errors:local-request-p env)))))

(defun server-timing-value (timing total-ms gc-ms full)
  (with-output-to-string (s)
    (format s "total;dur=~,1F" total-ms)
    (when full
      (format s ", db;dur=~,1F;desc=\"~D quer~:@P\""
              (/ (timing-db-usec timing) 1000d0) (timing-db-count timing))
      (format s ", gc;dur=~,1F" gc-ms)
      (loop for (name . ms) in (reverse (timing-phases timing))
            do (format s ", ~A;dur=~,1F" name ms)))))

(defun add-header (headers name value)
  "HEADERS with NAME set to VALUE, appended to a value already there. A new
list: a controller's headers may be a literal."
  (let ((existing (getf headers name)))
    (list* name (if existing (format nil "~A, ~A" existing value) value)
           (if existing
               (loop for (k v) on headers by #'cddr
                     unless (eq k name) append (list k v))
               headers))))

;;; The access log

(defun body-bytes (headers body)
  "The response's length in bytes, when it can be known without sending it."
  (let ((length (getf headers :content-length)))
    (cond (length length)
          ((and (listp body) (every (lambda (x) (or (stringp x) (vectorp x))) body))
           (loop for part in body
                 sum (if (stringp part)
                         (trivial-utf-8:utf-8-byte-length part)
                         (length part))))
          (t nil))))

(defun timestamp ()
  (multiple-value-bind (s m h d mo y) (decode-universal-time (get-universal-time) 0)
    (format nil "~4,'0D-~2,'0D-~2,'0DT~2,'0D:~2,'0D:~2,'0DZ" y mo d h m s)))

(defun request-path (env)
  "The path the client asked for, without its query string: a query string
can hold a token."
  (let* ((uri (or (getf env :request-uri) (getf env :path-info) "/"))
         (end (position #\? uri)))
    (subseq uri 0 end)))

(defun logfmt-value (value)
  (let ((string (princ-to-string value)))
    (if (or (zerop (length string))
            (find-if (lambda (c) (or (char<= c #\Space) (find c "\"=\\"))) string))
        (with-output-to-string (s)
          (write-char #\" s)
          (loop for c across string
                do (case c
                     (#\" (write-string "\\\"" s))
                     (#\\ (write-string "\\\\" s))
                     (#\Newline (write-string "\\n" s))
                     (t (write-char c s))))
          (write-char #\" s))
        string)))

(defun json-value (value)
  (if (realp value)
      (princ-to-string value)
      (with-output-to-string (s)
        (write-char #\" s)
        (loop for c across (princ-to-string value)
              do (cond ((char= c #\") (write-string "\\\"" s))
                       ((char= c #\\) (write-string "\\\\" s))
                       ((char< c #\Space) (format s "\\u~4,'0X" (char-code c)))
                       (t (write-char c s))))
        (write-char #\" s))))

(defun log-fields (env status bytes timing total-ms gc-ms)
  "The access-log line's fields, as (NAME VALUE) pairs, without the empty
ones."
  (remove nil
          (list (list "time" (timestamp))
                (list "method" (getf env :request-method))
                (list "path" (request-path env))
                (list "status" status)
                (list "ms" (format nil "~,1F" total-ms))
                (list "db_ms" (format nil "~,1F" (/ (timing-db-usec timing) 1000d0)))
                (list "queries" (timing-db-count timing))
                (list "gc_ms" (format nil "~,1F" gc-ms))
                (and bytes (list "bytes" bytes))
                (and (timing-route timing) (list "route" (timing-route timing))))
          :test #'eq))

(defun write-line-to-log (text)
  (ignore-errors
   (let ((stream (or *access-log-stream* *standard-output*)))
     (write-string text stream)
     (force-output stream))))

(defun format-log-line (format fields)
  (ecase format
    (:logfmt (format nil "~{~A~^ ~}~%"
                     (loop for (name value) in fields
                           collect (format nil "~A=~A" name (logfmt-value value)))))
    (:json (format nil "{~{~A~^,~}}~%"
                   (loop for (name value) in fields
                         collect (format nil "\"~A\":~A" name
                                         (json-value (if (realp value) value
                                                         (princ-to-string value)))))))))

(defun one-line (sql &optional (limit 300))
  "SQL on one line, cut to LIMIT characters."
  (let ((text (string-trim " " (substitute-if #\Space (lambda (c) (char< c #\Space)) sql))))
    (if (> (length text) limit)
        (concatenate 'string (subseq text 0 limit) "…")
        text)))

(defun slow-request-text (env timing total-ms)
  (with-output-to-string (s)
    (format s "slow request: ~A ~A took ~,1F ms, ~D quer~:@P in ~,1F ms~%"
            (getf env :request-method) (request-path env) total-ms
            (timing-db-count timing) (/ (timing-db-usec timing) 1000d0))
    (loop for (sql . usec) in (reverse (timing-queries timing))
          do (format s "  ~:[     -~;~:*~6,1F~] ms  ~A~%"
                     (and usec (/ usec 1000d0)) (one-line sql)))
    (when (> (timing-db-count timing) (timing-recorded timing))
      (format s "  … and ~D more~%" (- (timing-db-count timing) (timing-recorded timing))))))

(defun repeated-queries (timing)
  "(COUNT . SQL) for each statement run more than *REPEATED-QUERY-THRESHOLD*
times, most first. Transaction statements aren't counted."
  (let ((counts (make-hash-table :test 'equal)))
    (loop for (sql) in (timing-queries timing)
          unless (member sql '("BEGIN TRANSACTION" "COMMIT TRANSACTION" "ROLLBACK TRANSACTION")
                         :test #'string-equal)
            do (incf (gethash sql counts 0)))
    (sort (loop for sql being the hash-keys of counts using (hash-value n)
                when (> n *repeated-query-threshold*) collect (cons n sql))
          #'> :key #'car)))

(defun log-request (env status headers body timing total-ms gc-ms)
  (let ((format (ignore-errors (settei:setting :server/access-log))))
    (when (member format '(:logfmt :json))
      (write-line-to-log
       (format-log-line format (log-fields env status (body-bytes headers body)
                                           timing total-ms gc-ms)))))
  (let ((slow (ignore-errors (settei:setting :server/slow-request-ms))))
    (when (and slow (plusp slow) (>= total-ms slow))
      (write-line-to-log (slow-request-text env timing total-ms))))
  (when (errors:debug-mode)
    (loop for (n . sql) in (repeated-queries timing)
          do (write-line-to-log
              (format nil "repeated query: ~D times in ~A ~A: ~A~%  Usually an N+1 query: load the rows in one query instead.~%"
                      n (getf env :request-method) (request-path env) (one-line sql))))))

;;; The middleware

(defun setting-header-value (env timing total-ms gc-ms)
  (unless (eq (ignore-errors (settei:setting :server/timing-header)) :off)
    (server-timing-value timing total-ms gc-ms (full-timing-p env))))

(defun finish (response env timing)
  "RESPONSE with its Server-Timing header, after logging the request."
  (let* ((total-ms (ms-between (timing-start timing) (get-internal-real-time)))
         (gc-ms (ms-between (timing-gc-start timing) (gc-run-time)))
         (header (ignore-errors (setting-header-value env timing total-ms gc-ms))))
    (destructuring-bind (status headers &optional (body nil body-p)) response
      (ignore-errors (log-request env status headers body timing total-ms gc-ms))
      (let ((headers (if header (add-header headers :server-timing header) headers)))
        (if body-p
            (list status headers body)
            (list status headers))))))

(defun wrap-request-timing (app)
  "Outermost middleware: time each request, add a Server-Timing header,
and log it (:server/access-log, :server/slow-request-ms). A delayed response
is timed until it calls its responder: a streaming body's time isn't
included."
  (lambda (env)
    (let* ((timing (make-timing))
           (response (let ((*timing* timing))
                       (funcall app env))))
      (flet ((finish-safely (response)
               ;; Timing must never cost a response.
               (or (ignore-errors (finish response env timing)) response)))
        (if (functionp response)
            (lambda (responder)
              (let ((*timing* timing))
                (funcall response
                         (lambda (result)
                           (funcall responder (finish-safely result))))))
            (finish-safely response))))))
