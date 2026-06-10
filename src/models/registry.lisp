(defpackage #:shiso/models/registry
  (:use #:cl)
  (:local-nicknames (#:meta #:shiso/models/metadata))
  (:export
   ;; Registry
   #:*model-registry*
   #:register-model
   ;; Introspection -- model level
   #:model-fields
   #:model-field
   #:model-class
   #:all-models
   ;; Introspection -- field level (convenience wrappers)
   #:field-name
   #:field-col-type
   #:field-verbose-name
   #:field-help-text
   #:field-validators
   #:field-choices
   #:field-blankp
   #:field-editablep
   #:field-widget
   #:field-foreign-key
   #:get-model-name))

(in-package #:shiso/models/registry)

(defparameter *model-registry* (make-hash-table :test 'eq)
  "Maps model name symbols to model-metadata structs.")

(defparameter *model-name-index* (make-hash-table :test 'equal)
  "Maps model name strings (upcased) to model name symbols.  Lets the admin
and other string-driven callers (e.g. URL segments) find a model without
knowing which package its name symbol lives in.")

(defun register-model (name class fields)
  "Register a model's metadata.  Called by the define-model expansion.
Model names must be unique across packages: registering a different symbol
with the same name signals a continuable error."
  (let ((existing (gethash (symbol-name name) *model-name-index*)))
    (when (and existing
               (not (eq existing name))
               (nth-value 1 (gethash existing *model-registry*)))
      (cerror "Replace the existing model."
              "Cannot register model ~S: a model named ~A is already ~
               registered as ~S.  Model names must be unique across packages."
              name (symbol-name name) existing)))
  (setf (gethash (symbol-name name) *model-name-index*) name)
  (setf (gethash name *model-registry*)
        (meta:make-model-metadata :class class :fields fields)))

(defun resolve-model-name (name)
  "Resolve NAME (symbol or string) to the canonical registered name symbol.
A symbol that is itself a registry key is returned as-is; otherwise the
name is looked up by string in the name index.  Returns NIL if no model
with that name is registered."
  (let ((key (etypecase name
               (string (string-upcase name))
               (symbol (if (nth-value 1 (gethash name *model-registry*))
                           (return-from resolve-model-name name)
                           (symbol-name name))))))
    (let ((found (gethash key *model-name-index*)))
      (when (and found (nth-value 1 (gethash found *model-registry*)))
        found))))

(defun get-model-name (model-name-str)
  (resolve-model-name model-name-str))

#+nil
(get-model-name "book")

(defun model-fields (model-name)
  "Return the list of slot-metadata for MODEL-NAME, in declaration order."
  (let ((metadata (gethash (resolve-model-name model-name) *model-registry*)))
    (when metadata (meta:model-metadata-fields metadata))))

(defun model-field (model-name slot-name)
  "Return a single slot-metadata by name, or NIL."
  (find slot-name (model-fields model-name)
        :key #'meta:slot-metadata-name
        :test (lambda (a b) (string= (symbol-name a) (symbol-name b)))))

(defun model-class (model-name)
  "Return the CLOS class for MODEL-NAME."
  (let ((metadata (gethash (resolve-model-name model-name) *model-registry*)))
    (when metadata (meta:model-metadata-class metadata))))

(defun all-models ()
  "Return a list of all registered model name symbols."
  (loop :for name :being :the :hash-keys :of *model-registry* :collect name))
#+nil
(all-models)

(defun field-name (f)
  (meta:slot-metadata-name f))

(defun field-col-type (f)
  (meta:slot-metadata-col-type f))

(defun field-verbose-name (f)
  "Return the verbose name, or auto-derive one from the slot name."
  (or (meta:slot-metadata-verbose-name f)
      (string-capitalize
       (substitute #\Space #\-
                   (string-downcase (symbol-name (meta:slot-metadata-name f)))))))

(defun field-help-text (f)
  (meta:slot-metadata-help-text f))

(defun field-validators (f)
  (meta:slot-metadata-validators f))

(defun field-choices (f)
  (meta:slot-metadata-choices f))

(defun field-blankp (f)
  (meta:slot-metadata-blankp f))

(defun field-editablep (f)
  (meta:slot-metadata-editablep f))

(defun field-widget (f)
  (meta:slot-metadata-widget f))

(defun field-foreign-key (f)
  "Return the target-model name string for an FK column, or NIL."
  (meta:slot-metadata-foreign-key f))
