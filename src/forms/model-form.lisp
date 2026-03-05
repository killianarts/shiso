(defpackage #:shiso/forms/model-form
  (:use #:cl)
  (:local-nicknames (#:fields #:shiso/forms/fields)
                    (#:form #:shiso/forms/form)
                    (#:models #:shiso/models)
                    (#:val #:shiso/validators))
  (:export
   #:make-model-form
   #:save-form
   #:model-form
   #:model-form-model-name))

(in-package #:shiso/forms/model-form)

(defclass model-form (form:form)
  ((model-name :initarg :model-name :reader model-form-model-name)))

(defun make-model-form (model-name &key fields exclude instance data)
  "Create a form instance from a model definition.

MODEL-NAME -- symbol naming a registered model.
FIELDS     -- explicit list of field names to include (nil = all editable).
EXCLUDE    -- list of field names to exclude.
INSTANCE   -- existing model instance (for edit forms).
DATA       -- submitted form data (alist of (name . string-value))."
  (let* ((all-meta (models:model-fields model-name))
         (filtered (remove-if-not
                    (lambda (m)
                      (and (models:field-editablep m)
                           (or (null fields)
                               (member (models:field-name m) fields))
                           (not (member (models:field-name m) exclude))))
                    all-meta))
         (form-fields (mapcar (lambda (m) (metadata-to-form-field m instance))
                              filtered)))
    (make-instance 'model-form
                   :model-name model-name
                   :fields form-fields
                   :instance instance
                   :data data)))

(defun metadata-to-form-field (meta instance)
  "Convert a slot-metadata struct to a form-field instance."
  (let* ((name (models:field-name meta))
         (col-type (models:field-col-type meta))
         (class (if (models:field-choices meta)
                    'fields:choice-field
                    (fields:col-type-to-field-class col-type)))
         (initargs (list :name name
                         :label (models:field-verbose-name meta)
                         :help-text (models:field-help-text meta)
                         :requiredp (not (models:field-blankp meta))
                         :validators (models:field-validators meta)
                         :widget (models:field-widget meta))))
    ;; Add type-specific initargs
    (when (subtypep class 'fields:char-field)
      (when (and (listp col-type) (eq (car col-type) :varchar))
        (setf (getf initargs :max-length) (second col-type))))
    (when (subtypep class 'fields:choice-field)
      (setf (getf initargs :choices) (models:field-choices meta)))
    ;; Set initial value from instance
    (when instance
      (setf (getf initargs :initial)
            (and (slot-boundp instance name)
                 (slot-value instance name))))
    (apply #'make-instance class initargs)))

(defun save-form (form)
  "Persist a validated model form. Creates or updates based on instance."
  (let ((cleaned (form:form-cleaned-data form))
        (model-class (models:model-class (model-form-model-name form))))
    (if (form:form-instance form)
        ;; Update existing
        (let ((obj (form:form-instance form)))
          (maphash (lambda (k v) (setf (slot-value obj k) v)) cleaned)
          (mito:save-dao obj))
        ;; Create new
        (apply #'mito:create-dao model-class
               (loop for k being the hash-keys of cleaned using (hash-value v)
                     append (list (intern (symbol-name k) :keyword) v))))))
