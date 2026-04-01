(defpackage #:shiso/models/field-types
  (:use #:cl)
  (:local-nicknames (#:validators #:shiso/validators))
  (:export
   #:*field-types*
   #:define-field-type
   #:expand-field-type))

(in-package #:shiso/models/field-types)

(defvar *field-types* (make-hash-table :test 'eq)
  "Maps field-type keywords to (expander-fn . consumed-keys) conses.
Each expander receives (slot-name &key ...consumed-options...) and returns
a plist of slot-option defaults.")

(defmacro define-field-type (name (slot-name &rest params) &body body)
  "Register a field type expander.
SLOT-NAME is bound to the slot name symbol at expansion time.
PARAMS are keyword parameters consumed by this field type (include &key).
BODY returns a plist of slot-option defaults."
  (let* ((key-params (if (eq (car params) '&key)
                         (cdr params)
                         params))
         (consumed (mapcar (lambda (p)
                             (intern (symbol-name (if (listp p) (car p) p))
                                     :keyword))
                           key-params)))
    `(setf (gethash ,name *field-types*)
           (cons (lambda (,slot-name &key ,@key-params)
                   (declare (ignorable ,slot-name))
                   ,@body)
                 ',consumed))))

(defun field-type-consumed-keys (ft-name)
  "Return the keyword parameter names consumed by field type FT-NAME."
  (cdr (gethash ft-name *field-types*)))

(defun plist-remove-keys (plist keys)
  "Return a fresh plist with KEYS removed."
  (loop for (k v) on plist by #'cddr
        unless (member k keys)
          append (list k v)))

(defun merge-field-options (defaults user-plist consumed-keys)
  "Merge field-type DEFAULTS with USER-PLIST.
- Remove :field-type and CONSUMED-KEYS from user plist
- Translate :default to :initform
- User options win over defaults
- :validators append (defaults first, then user)"
  (let* ((skip-keys (list* :field-type :default consumed-keys))
         ;; Clean user plist: remove consumed keys, translate :default
         (user (plist-remove-keys user-plist skip-keys))
         (user (if (and (getf user-plist :default)
                        (not (getf user-plist :initform)))
                   (list* :initform (getf user-plist :default) user)
                   user))
         ;; Prepend validators from defaults before user validators
         (user (let ((default-vals (getf defaults :validators))
                     (user-vals    (getf user :validators)))
                 (if default-vals
                     (list* :validators (append default-vals user-vals)
                            (plist-remove-keys user '(:validators)))
                     user))))
    ;; Fill in remaining defaults where user didn't specify
    (loop for (key val) on defaults by #'cddr
          unless (or (eq key :validators) (getf user key))
            do (setf user (list* key val user)))
    user))

(defun expand-field-type (slot-def)
  "If SLOT-DEF has :field-type, expand it using the registered expander.
The expander receives the slot name as first positional arg plus consumed
keyword options. Returns the expanded slot def with merged options.
Raw slots (no :field-type) pass through unchanged."
  (destructuring-bind (name &rest plist) slot-def
    (let ((ft-name (getf plist :field-type)))
      (if (null ft-name)
          slot-def
          (let ((entry (gethash ft-name *field-types*)))
            (unless entry
              (error "Unknown field type: ~A" ft-name))
            (let* ((expander (car entry))
                   (consumed-keys (cdr entry))
                   ;; Build keyword args for the expander from user plist
                   (expander-args
                     (loop for key in consumed-keys
                           for val = (getf plist key '%not-found%)
                           unless (eq val '%not-found%)
                             append (list key val)))
                   (defaults (apply expander name expander-args))
                   (merged (merge-field-options defaults plist consumed-keys)))
              (cons name merged)))))))

;;; ---------------------------------------------------------------
;;; Built-in field types
;;; ---------------------------------------------------------------

(define-field-type :char (name &key max-length)
  (list :col-type `(:varchar ,max-length)
        :initarg (intern (symbol-name name) :keyword)
        :validators `((validators:max-length ,max-length))))

(define-field-type :text (name &key)
  (list :col-type :text
        :initarg (intern (symbol-name name) :keyword)
        :widget :textarea))

(define-field-type :integer (name &key)
  (list :col-type :integer
        :initarg (intern (symbol-name name) :keyword)))

(define-field-type :boolean (name &key)
  (list :col-type :boolean
        :initarg (intern (symbol-name name) :keyword)
        :widget :checkbox))

(define-field-type :choice (name &key)
  (list :col-type '(:varchar 50)
        :initarg (intern (symbol-name name) :keyword)))

(define-field-type :email (name &key)
  (list :col-type '(:varchar 254)
        :initarg (intern (symbol-name name) :keyword)
        :validators '((validators:valid-email))
        :widget :email))

(define-field-type :slug (name &key)
  (list :col-type '(:varchar 200)
        :initarg (intern (symbol-name name) :keyword)
        :validators '((validators:matches-pattern "^[a-z0-9-]+$"))))

(define-field-type :url (name &key)
  (list :col-type '(:varchar 2000)
        :initarg (intern (symbol-name name) :keyword)
        :validators '((validators:matches-pattern "^https?://"))
        :widget :url))

(define-field-type :datetime (name &key)
  (list :col-type :timestamptz
        :initarg (intern (symbol-name name) :keyword)
        :widget :datetime-local))

(define-field-type :date (name &key)
  (list :col-type :date
        :initarg (intern (symbol-name name) :keyword)
        :widget :date))

(define-field-type :decimal (name &key precision scale)
  (list :col-type `(:numeric ,precision ,scale)
        :initarg (intern (symbol-name name) :keyword)))
