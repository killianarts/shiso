(defpackage #:shiso/scaffold
  (:use #:cl)
  (:export
   #:make-module))
(in-package #:shiso/scaffold)

(defvar *module-skeleton-directory*
  (asdf:system-relative-pathname :shiso #P"skeleton/module/"))

(defun make-module (system-name module-name)
  "Scaffold a new shiso module under src/modules/<module-name>/ of SYSTEM-NAME.
   Like Django's manage.py startapp — creates the directory structure
   with package, controllers, models, routes, forms, and components."
  (let* ((path (merge-pathnames (format nil "src/modules/~A/" module-name)
                                (asdf:system-source-directory system-name)))
         (path (uiop:ensure-directory-pathname path))
         (cl-project:*skeleton-directory* *module-skeleton-directory*))
    (cl-project:generate-skeleton
     *module-skeleton-directory*
     path
     :env (list :name module-name)
     :verbose t)))
