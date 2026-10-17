(defpackage #:errors-demo/demo
  (:use #:cl)
  (:local-nicknames (#:s #:shiso)
                    (#:ah #:almighty-html)
                    (#:layout #:errors-demo/layout))
  (:export #:note #:note-text #:page-bug #:quota-exceeded))

(in-package #:errors-demo/demo)

;;;; One module, one page per behaviour. Start at / for the guided tour.

;;; A model, for get-or-404 and the atomic POSTs.

(s:define-model note
    ((text :field-type :char
           :max-length 200
           :verbose-name "Text"
           :accessor note-text)))

;;; Conditions the app expects, mapped to statuses (Rails' rescue_responses).

(define-condition quota-exceeded (error)
  ((limit :initarg :limit :reader quota-limit)))

(defmethod s:condition-http-status ((c quota-exceeded))
  429)

(define-condition page-bug (error) ()
  (:documentation "Mapped to 500; the app's :5xx page fails on purpose for it,
to show the static static/errors/500.html fallback."))

(defmethod s:condition-http-status ((c page-bug))
  500)

;;; Helpers

(defun env ()
  (lack/request:request-env s:*request*))

(defun csrf-input ()
  (let ((token (s:csrf-token-value)))
    (when token
      (ah:</> (input :type "hidden" :name "_csrf_token" :value token)))))

(defun mode-box ()
  "What this request gets on an unexpected error, and why."
  (let* ((env (env))
         (mode (shiso/errors:debug-mode))
         (local (shiso/errors:local-request-p env))
         (editor (shiso/errors:editor-connected-p)))
    (ah:</>
     (div :class "mode"
       (p (b "Debug mode: ")
          (cond ((null mode) "off: unexpected errors get the app's 500 page.")
                ((not local) "on, but this request isn't from this machine, so it gets the normal pages.")
                ((and (eq mode :repl) editor) "REPL debugger: unexpected errors open SLY/SLIME's debugger with RETRY-REQUEST.")
                ((eq mode :repl) "REPL debugger requested, but no SLY/SLIME connection: the debug page instead.")
                (t "debug page: unexpected errors show the condition and backtrace; 404s list the routes tried.")))
       (p "Change it in the REPL: "
          (code "(errors-demo:restart-server :debugp nil)") ", "
          (code ":debugp t") " or " (code ":debugp :repl") ". "
          "Preview your own 404 page in debug mode with "
          (code "(setf shiso:*debug-404* nil)") ".")))))

(defun row (href label what)
  (ah:</> (tr (td (a :href href label)) (td what))))

;;; The tour

(defparameter *fetch-js* "
async function show(path, options) {
  const out = document.getElementById('out');
  out.textContent = '...';
  const r = await fetch(path, options || {});
  const allow = r.headers.get('allow');
  out.textContent = r.status + ' ' + (r.headers.get('content-type') || '(no content-type)')
    + (allow ? '\\nAllow: ' + allow : '') + '\\n\\n' + await r.text();
}
")

(defun fetch-button (label path options)
  (ah:</> (button :type "button"
                  :onclick (format nil "show('~A', ~A)" path options)
                  label)))

(defun index ()
  (layout:render
   "Shiso error handling"
   (ah:</> (h1 "Shiso error handling demo"))
   (ah:</> (p "Each link below triggers one behaviour. Watch the REPL or terminal too: errors are logged to "
              (code "*error-output*") "."))
   (mode-box)

   (ah:</> (h2 "Error pages"))
   (ah:</>
    (table
      (tbody
        (row "/nowhere" "/nowhere"
             "No route matches: the app's 404 page (error-pages.lisp), or in debug mode the list of routes tried. Followed from this page, it's a broken internal link, so it's logged.")
        (row "/forbidden" "/forbidden"
             "(s:abort-with 403 :message …): no 403 page is defined, so the app's :4xx page shows, with the message.")
        (row "/teapot" "/teapot" "(s:abort-with 418): the :4xx page again.")
        (row "/post-only" "/post-only"
             "The route only takes POST: 405 with an Allow header, not 404.")
        (row "/notes/" "/notes/" "Trailing slash: 301 to /notes."))))

   (ah:</> (h2 "Typed route parameters and get-or-404"))
   (ah:</>
    (table
      (tbody
        (row "/notes/1" "/notes/1"
             "The route is /notes/<int:id>, so the controller gets the integer 1. If note 1 exists it's shown (add one on /notes first).")
        (row "/notes/999999" "/notes/999999" "(s:get-or-404 'note :id 999999): no such row, so 404.")
        (row "/notes/abc" "/notes/abc" "The int converter rejects abc: the route doesn't match, so it's a routing 404, not a parse-integer 500."))))

   (ah:</> (h2 "Unexpected and mapped errors"))
   (ah:</>
    (table
      (tbody
        (row "/boom" "/boom"
             "(parse-integer \"twelve\") in the controller: a bug. Logged with its backtrace; then the app's 500 page, the debug page, or the REPL debugger, by mode.")
        (row "/quota" "/quota"
             "Signals QUOTA-EXCEEDED, which the app maps to 429 with a CONDITION-HTTP-STATUS method: an expected error, so no backtrace.")
        (row "/broken-error-page" "/broken-error-page"
             "The app's :5xx page itself fails for this one: Shiso serves static/errors/500.html instead (then plain text if that's missing)."))))

   (ah:</> (h2 "Atomic POSTs"))
   (ah:</> (p "On " (a :href "/notes" "/notes") ", one form adds a note; the other adds one and then fails. The failed request's insert is rolled back, so the count doesn't change."))

   (ah:</> (h2 "Other clients: JSON, HTMX, OPTIONS, CSRF"))
   (ah:</> (p "These use fetch() with the headers shown, and print the response below."))
   (ah:</>
    (div
      (fetch-button "404 as JSON" "/nowhere" "{headers: {'Accept': 'application/json'}}")
      (fetch-button "403 as JSON" "/forbidden" "{headers: {'Accept': 'application/json'}}")
      (fetch-button "500 as JSON" "/boom" "{headers: {'Accept': 'application/json'}}")
      (fetch-button "404 for HTMX" "/nowhere" "{headers: {'HX-Request': 'true'}}")
      (fetch-button "OPTIONS /notes" "/notes" "{method: 'OPTIONS'}")
      (fetch-button "POST without CSRF token" "/notes" "{method: 'POST'}")
      (fetch-button "HEAD /nowhere" "/nowhere" "{method: 'HEAD'}")))
   (ah:</> (pre :id "out" "Response appears here."))
   (ah:</> (script (raw! *fetch-js*)))))

;;; Notes: get-or-404 and atomic POSTs

(defun notes ()
  (let ((all (mito:select-dao 'note (sxql:order-by (:desc :id)))))
    (layout:render
     "Notes"
     (ah:</> (p (a :href "/" "← Back to the tour")))
     (ah:</> (h1 (format nil "Notes (~D)" (length all))))
     (ah:</>
      (form :method "post" :action "/notes"
        (csrf-input)
        (input :name "text" :placeholder "A note" :required t)
        (button :type "submit" "Add")))
     (ah:</>
      (form :method "post" :action "/notes/fail"
        (csrf-input)
        (input :type "hidden" :name "text" :value "This note should never be saved")
        (button :type "submit" "Add a note, then fail")
        (span " Inserts a row, then signals an error. The request's transaction rolls back.")))
     (ah:</>
      (ul
        (loop for n in all
              collect (ah:</>
                       (li (a :href (s:url "demo:note" :id (mito:object-id n))
                              (format nil "#~D " (mito:object-id n)))
                           (note-text n)))))))))

(defun note-detail (id)
  ;; ID is an integer: the route says <int:id>.
  (let ((note (s:get-or-404 'note :id id)))
    (layout:render
     (format nil "Note #~D" id)
     (ah:</> (p (a :href "/notes" "← All notes")))
     (ah:</> (h1 (format nil "Note #~D" id)))
     (ah:</> (p (note-text note)))
     (ah:</> (p "The controller received " (code (prin1-to-string id))
                ", an integer, not the string " (code (prin1-to-string (princ-to-string id)))
                ": the route is " (code "/notes/<int:id>") ".")))))

(defun submitted-text ()
  (let ((text (cdr (assoc :text (s:parse-body-params)))))
    (if (and text (plusp (length text))) text "(empty)")))

(defun create-note ()
  (mito:create-dao 'note :text (submitted-text))
  (s:redirect-response "/notes"))

(defun create-note-then-fail ()
  (mito:create-dao 'note :text (submitted-text))
  ;; The row is inserted; this error rolls the request's transaction back.
  (error "Failed after inserting a note. Check /notes: the count didn't change."))

;;; The rest of the tour

(defun forbidden ()
  (s:abort-with 403 :message "Members only. This text is ABORT-WITH's :message."))

(defun teapot ()
  (s:abort-with 418 :message "Short and stout."))

(defun boom ()
  ;; A plain bug: PARSE-ERROR isn't mapped to a status, so it's unexpected.
  (let ((count (parse-integer "twelve")))
    (layout:render "Unreachable" (ah:</> (p (princ-to-string count))))))

(defun quota ()
  (error 'quota-exceeded :limit 3))

(defun broken-error-page ()
  (error 'page-bug))

(defun post-only ()
  (layout:render "Posted" (ah:</> (p "POST accepted."))))

(s:define-module demo
  (:urls (:GET  "/"                  'index                 "index")
         (:GET  "/notes"             'notes                 "notes")
         (:POST "/notes"             'create-note           "create-note")
         (:POST "/notes/fail"        'create-note-then-fail "create-note-then-fail")
         (:GET  "/notes/<int:id>"    'note-detail           "note")
         (:GET  "/forbidden"         'forbidden             "forbidden")
         (:GET  "/teapot"            'teapot                "teapot")
         (:GET  "/boom"              'boom                  "boom")
         (:GET  "/quota"             'quota                 "quota")
         (:GET  "/broken-error-page" 'broken-error-page     "broken-error-page")
         (:POST "/post-only"         'post-only             "post-only")))
