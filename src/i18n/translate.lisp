(in-package #:shiso/i18n)

(defparameter *warn-missing-translations* nil
  "When true, WARN on a missing catalog entry after fallback.")

(defun plist-without (plist key)
  (loop :for (k v) :on plist :by #'cddr
        :unless (eq k key)
          :collect k :and :collect v))

(defun stringify-id (id)
  (etypecase id
    (string id)
    (symbol (string-downcase (symbol-name id)))))

(defun fluent-id-p (string)
  "True if STRING is a legal Fluent message identifier."
  (and (stringp string)
       (plusp (length string))
       (alpha-char-p (char string 0))
       (every (lambda (c)
                (or (alphanumericp c)
                    (char= c #\-)
                    (char= c #\_)))
              string)))

(defun message-id (model-name field-name &optional suffix)
  "Derived Fluent id for a model field: QUESTION + QUESTION-TEXT
-> \"question-question-text\". Optional SUFFIX (e.g. \"help\") is
appended with a hyphen."
  (format nil "~(~a~)-~(~a~)~@[-~a~]"
          model-name field-name suffix))

(defun resolve-in-locale (locale id inputs)
  "Resolve ID in LOCALE only. Does not use Fluent's built-in fallback
(its recursive RESOLVE-WITH currently mis-applies &rest inputs).
Returns NIL if the locale or line is missing."
  (ensure-localisations)
  (unless *fluent*
    (return-from resolve-in-locale nil))
  (let* ((locale (canonicalize-locale locale))
         (locs (fluent:fluent-locs *fluent*)))
    (unless (gethash locale locs)
      (return-from resolve-in-locale nil))
    ;; Isolate fallback so a missing line signals MISSING-LINE instead
    ;; of taking Fluent's buggy recursive path.
    (let ((ctx (fluent:fluent locs :locale locale :fallback locale)))
      (handler-case
          (apply #'fluent:resolve-with
                 ctx locale (locale-lang locale) id inputs)
        (fluent:missing-line () nil)
        (fluent:unknown-locale () nil)
        (fluent:missing-input () nil)))))

(defun translate (id &rest args)
  "Look up ID in the current locale.

Keyword arguments other than :DEFAULT are passed to Fluent as named
placeholders ({ $n }, etc.). If the id is missing in *LOCALE*, try
*FALLBACK-LOCALE*. If still missing, return :DEFAULT if supplied,
otherwise ID itself. Never signals for a missing translation."
  (let* ((id (stringify-id id))
         (default (getf args :default))
         (has-default (not (eq (getf args :default :absent) :absent)))
         (inputs (plist-without args :default))
         (found (or (resolve-in-locale *locale* id inputs)
                    (unless (eq (canonicalize-locale *locale*)
                                (canonicalize-locale *fallback-locale*))
                      (resolve-in-locale *fallback-locale* id inputs)))))
    (cond (found found)
          (t
           (when *warn-missing-translations*
             (warn "Missing translation ~S for locale ~S" id *locale*))
           (if has-default default id)))))
