(defpackage #:shiso/models/shortcuts
  (:use #:cl)
  (:local-nicknames (#:errors #:shiso/errors))
  (:export
   #:get-or-404
   #:found-or-404))

(in-package #:shiso/models/shortcuts)

;;;; Django's get_object_or_404: turn "no such row" into a 404 at the call,
;;;; where it's known that the lookup came from the URL. Shiso doesn't map
;;;; "not found" globally, so a lookup your own code gets wrong is still a 500.

(defun get-or-404 (class &rest find-args)
  "Like MITO:FIND-DAO, but signals SHISO:NOT-FOUND instead of returning NIL.
  (s:get-or-404 'question :id id)"
  (or (apply #'mito:find-dao class find-args)
      ;; The message names the model and lookup, so it's only set in debug
      ;; mode: the default 404 page shows a 404's message.
      (errors:abort-with
       404 :message (when (errors:debug-mode)
                      (format nil "No ~A matching ~S"
                              (if (typep class 'class) (class-name class) class)
                              find-args)))))

(defun found-or-404 (value)
  "VALUE, or signal SHISO:NOT-FOUND when it is NIL. For lookups that aren't
MITO:FIND-DAO."
  (or value (errors:abort-with 404)))
