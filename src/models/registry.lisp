(defpackage #:shiso/models/registry
  (:use #:cl)
  (:local-nicknames (#:meta #:shiso/models/metadata))
  (:export
   ;; Name normalization
   #:normalize-name
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
   #:field-widget))

(in-package #:shiso/models/registry)

(defun normalize-name (name)
  "Normalize a model name to a keyword symbol for registry lookup.
Accepts keywords, symbols, or strings."
  (etypecase name
    (keyword name)
    (symbol (intern (symbol-name name) :keyword))
    (string (intern (string-upcase name) :keyword))))

(defvar *model-registry* (make-hash-table :test 'eq)
  "Maps model name keywords to model-metadata structs.")

(defun register-model (name class fields)
  "Register a model's metadata.  Called by the define-model expansion."
  (setf (gethash (normalize-name name) *model-registry*)
        (meta:make-model-metadata :class class :fields fields)))

(defun model-fields (model-name)
  "Return the list of slot-metadata for MODEL-NAME, in declaration order."
  (let ((metadata (gethash (normalize-name model-name) *model-registry*)))
    (when metadata (meta:model-metadata-fields metadata))))

(defun model-field (model-name slot-name)
  "Return a single slot-metadata by name, or NIL."
  (find slot-name (model-fields model-name)
        :key #'meta:slot-metadata-name))

(defun model-class (model-name)
  "Return the CLOS class for MODEL-NAME."
  (let ((metadata (gethash (normalize-name model-name) *model-registry*)))
    (when metadata (meta:model-metadata-class metadata))))

(defun all-models ()
  "Return a list of all registered model name symbols."
  (loop for name being the hash-keys of *model-registry* collect name))

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
