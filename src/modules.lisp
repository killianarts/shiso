(defpackage #:shiso/modules
  (:use #:cl)
  (:export
   #:module
   #:module-routes
   #:module-prefix
   #:module-static-root
   #:*module-registry*
   #:register-module
   #:get-module))

(in-package #:shiso/modules)

(defclass module (lack/component::lack-component)
  ((routes :initarg :routes :accessor module-routes)
   (prefix :initarg :prefix :accessor module-prefix :initform "")
   (static-root :initarg :static-root :accessor module-static-root :initform nil)))

(defvar *module-registry* (make-hash-table :test 'eq)
  "Global registry of defined modules, keyed by module name (keyword).")

(defun register-module (name module)
  (setf (gethash name *module-registry*) module))

(defun get-module (name)
  (or (gethash name *module-registry*)
      (error "Module ~A is not registered." name)))
