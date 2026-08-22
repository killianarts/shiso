(defpackage #:shiso/validators
  (:use #:cl)
  (:local-nicknames (#:i18n #:shiso/i18n))
  (:export
   ;; Resolver and runner
   #:resolve-validator
   #:run-validators
   ;; Built-in validators
   #:not-blank
   #:max-length
   #:min-length
   #:min-value
   #:max-value
   #:matches-pattern
   #:valid-email
   #:one-of))

(in-package #:shiso/validators)

(defun resolve-validator (designator)
  "Turn a validator designator into a callable function."
  (etypecase designator
    (function designator)
    (symbol (fdefinition designator))
    (list (apply (fdefinition (car designator)) (cdr designator)))))

(defun run-validators (validators value)
  "Run all VALIDATORS on VALUE, return list of error message strings.
VALIDATORS is a list of validator designators."
  (loop for v in validators
        for fn = (resolve-validator v)
        for error = (funcall fn value)
        when error collect error))

(defun not-blank (value)
  "Validate that VALUE is not empty."
  (when (or (null value)
            (and (stringp value) (string= value "")))
    (i18n:translate "validators-not-blank"
                    :default "This field is required.")))

(defun max-length (n)
  "Return a validator that checks string length <= N."
  (lambda (value)
    (when (and (stringp value) (> (length value) n))
      (i18n:translate "validators-max-length"
                      :n n
                      :default (format nil "Must be ~D characters or fewer." n)))))

(defun min-length (n)
  "Return a validator that checks string length >= N."
  (lambda (value)
    (when (and (stringp value) (< (length value) n))
      (i18n:translate "validators-min-length"
                      :n n
                      :default (format nil "Must be at least ~D characters." n)))))

(defun min-value (n)
  "Return a validator that checks numeric value >= N."
  (lambda (value)
    (when (and (numberp value) (< value n))
      (i18n:translate "validators-min-value"
                      :n n
                      :default (format nil "Must be at least ~D." n)))))

(defun max-value (n)
  "Return a validator that checks numeric value <= N."
  (lambda (value)
    (when (and (numberp value) (> value n))
      (i18n:translate "validators-max-value"
                      :n n
                      :default (format nil "Must be at most ~D." n)))))

(defun matches-pattern (regex)
  "Return a validator that checks a string matches REGEX (CL-PPCRE)."
  (lambda (value)
    (when (and (stringp value)
               (not (cl-ppcre:scan regex value)))
      (i18n:translate "validators-matches-pattern"
                      :default "Does not match the expected pattern."))))

(defun valid-email (value)
  "Basic email format validation."
  (when (and (stringp value)
             (not (cl-ppcre:scan "^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$" value)))
    (i18n:translate "validators-valid-email"
                    :default "Enter a valid email address.")))

(defun one-of (choices)
  "Return a validator that checks value is a member of CHOICES."
  (lambda (value)
    (unless (member value choices :test #'equal)
      (i18n:translate "validators-one-of"
                      :choices (format nil "~{~A~^, ~}" choices)
                      :default (format nil "Must be one of: ~{~A~^, ~}." choices)))))
