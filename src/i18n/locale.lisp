(in-package #:shiso/i18n)

(defparameter *default-locale* :en-us
  "Locale used when the request does not pick one.")

(defparameter *fallback-locale* :en-us
  "Locale tried when a message is missing from the active locale.")

(defvar *locale* :en-us
  "Request- (or with-locale-) scoped active locale. Never SETF this
across requests on a multithreaded server; bind it with WITH-LOCALE
or the locale middleware.")

(defparameter *language-cookie-name* "shiso_language"
  "Cookie that persists the user's language choice.")

(defun canonicalize-locale (locale)
  "Turn LOCALE (keyword, string, or symbol) into a keyword like :EN-US.
Accepts en-US, en_US, en-us, :en-us."
  (etypecase locale
    (null *default-locale*)
    (keyword locale)
    (symbol (intern (substitute #\- #\_ (string-upcase (symbol-name locale)))
                    :keyword))
    (string
     (let ((s (string-trim '(#\Space #\Tab #\Newline #\Return) locale)))
       (if (zerop (length s))
           *default-locale*
           (intern (substitute #\- #\_ (string-upcase s)) :keyword))))))

(defun locale-lang (locale)
  "Language portion of a locale: :JA-JP -> :JA, :EN -> :EN."
  (let* ((name (string (canonicalize-locale locale)))
         (dash (position #\- name)))
    (intern (if dash (subseq name 0 dash) name) :keyword)))

(defun locale-html-lang (locale)
  "BCP 47 language subtag for an HTML lang attribute, e.g. \"ja\"."
  (string-downcase (symbol-name (locale-lang locale))))

(defun locale-cookie-value (locale)
  "Canonical lowercase hyphenated tag for cookies, e.g. \"ja-jp\"."
  (string-downcase (symbol-name (canonicalize-locale locale))))

(defmacro with-locale (locale &body body)
  "Bind *LOCALE* to LOCALE for the dynamic extent of BODY."
  `(let ((*locale* (canonicalize-locale ,locale)))
     ,@body))

(defun current-locale ()
  "The locale in effect for this request (or WITH-LOCALE)."
  *locale*)
