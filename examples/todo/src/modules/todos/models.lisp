(defpackage #:todos/models
  (:use #:cl)
  (:export
   ;; Accessors
   #:title
   #:done
   ;; Helpers
   #:all-todos
   #:find-todo
   #:create-todo
   #:toggle-todo
   #:delete-todo))

(in-package #:todos/models)

(shiso:define-model todo
    ((title :field-type :char
            :max-length 200
            :verbose-name "Title"
            :help-text "What needs doing."
            :accessor title)
     (done :field-type :boolean
           :default nil
           :verbose-name "Done?"
           :accessor done)))

(shiso/admin:define-admin todo
  (:list-display title done))

(defun all-todos ()
  "All todos, newest first."
  (mito:select-dao (shiso/models:model-class 'todo)
    (sxql:order-by (:desc :id))))

(defun find-todo (id)
  (when id
    (mito:find-dao (shiso/models:model-class 'todo) :id id)))

(defun create-todo (title-string)
  (mito:create-dao (shiso/models:model-class 'todo)
                   :title title-string
                   :done nil))

(defun toggle-todo (todo)
  (setf (done todo) (not (done todo)))
  (mito:save-dao todo))

(defun delete-todo (todo)
  (mito:delete-dao todo))
