(defpackage #:todos/forms
  (:use #:cl)
  (:local-nicknames (#:s #:shiso)
                    (#:models #:todos/models))
  (:export #:make-add-form
           #:make-edit-form))

(in-package #:todos/forms)

(defun make-add-form (&key data)
  "Add form exposes only TITLE; DONE stays at its model default."
  (s:make-model-form 'todo
                     :fields (list 'models:title)
                     :data data))

(defun make-edit-form (todo &key data)
  "Edit form exposes every editable field (TITLE and DONE).
Initial values come from the instance when DATA is nil."
  (s:make-model-form 'todo :instance todo :data data))
