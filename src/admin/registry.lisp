(defpackage #:shiso/admin/registry
  (:use #:cl)
  (:local-nicknames (#:models #:shiso/models))
  (:export
   #:admin-config
   #:admin-model-name
   #:admin-list-display
   #:admin-list-filter
   #:admin-search-fields
   #:admin-fieldsets
   #:admin-fields
   #:admin-exclude
   #:admin-readonly
   #:admin-per-page
   #:admin-ordering
   #:*admin-registry*
   #:register-admin
   #:get-admin
   #:all-registered-admins
   #:define-admin))

(in-package #:shiso/admin/registry)

(defclass admin-config ()
  ((model-name   :initarg :model-name   :reader admin-model-name)
   (list-display :initarg :list-display :reader admin-list-display :initform nil)
   (list-filter  :initarg :list-filter  :reader admin-list-filter  :initform nil)
   (search-fields :initarg :search-fields :reader admin-search-fields :initform nil)
   (fieldsets    :initarg :fieldsets    :reader admin-fieldsets    :initform nil)
   (fields       :initarg :fields       :reader admin-fields       :initform nil)
   (exclude      :initarg :exclude      :reader admin-exclude      :initform nil)
   (readonly     :initarg :readonly     :reader admin-readonly     :initform nil)
   (per-page     :initarg :per-page     :reader admin-per-page     :initform 25)
   (ordering     :initarg :ordering     :reader admin-ordering     :initform nil)))

(defparameter *admin-registry* (make-hash-table :test 'eq)
  "Maps model name symbols to admin-config instances.")

(defun resolve-admin-name (name)
  "Resolve NAME (symbol or string) to the canonical model name symbol.
Signals an error if no model with that name is registered."
  (or (models:get-model-name name)
      (error "No model named ~A is registered; define the model with ~
              define-model before registering an admin for it."
             name)))

(defun register-admin (model-name &rest initargs)
  "Register a model for admin CRUD with optional configuration.
The model must already be defined via define-model."
  (let ((canonical (resolve-admin-name model-name)))
    (setf (gethash canonical *admin-registry*)
          (apply #'make-instance 'admin-config
                 :model-name canonical initargs))))

(defun get-admin (model-name)
  "Return the admin-config for MODEL-NAME, or signal an error."
  (let ((canonical (resolve-admin-name model-name)))
    (or (gethash canonical *admin-registry*)
        (error "No admin registered for model ~A" model-name))))

#+nil
(get-admin 'book)

(defun all-registered-admins ()
  "Return a list of all registered admin model names as strings."
  (loop :for name :being :the :hash-keys :of *admin-registry* :collect name))

#+nil
(all-registered-admins)
                                        ; => (ARTICLES/MODELS::ARTICLE)

(defmacro define-admin (model-name &body options)
  "Register a model for admin with customization options.

OPTIONS may include:
  (:list-display field1 field2 ...)
  (:list-filter field1 field2 ...)
  (:search-fields field1 field2 ...)
  (:fieldsets (\"Group\" (field1 field2)) ...)
  (:fields field1 field2 ...)
  (:exclude field1 field2 ...)
  (:readonly field1 field2 ...)
  (:per-page n)
  (:ordering field-or-minus-field)

The model must already be defined (and its defining file loaded) before
the define-admin form is loaded; otherwise registration signals an error."
  (let ((initargs nil))
    (dolist (opt options)
      (destructuring-bind (key &rest vals) opt
        (case key
          (:per-page
           (push :per-page initargs)
           (push (first vals) initargs))
          (:ordering
           (push :ordering initargs)
           (push `',(first vals) initargs))
          (:fieldsets
           (push :fieldsets initargs)
           (push `',vals initargs))
          (otherwise
           (push key initargs)
           (push `',vals initargs)))))
    `(register-admin ',model-name ,@(nreverse initargs))))
