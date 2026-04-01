(defpackage #:shiso/models/define-model
  (:use #:cl)
  (:local-nicknames (#:meta #:shiso/models/metadata)
                    (#:reg #:shiso/models/registry)
                    (#:ft #:shiso/models/field-types))
  (:export
   #:define-model
   #:*mito-slot-keys*
   #:*shiso-slot-keys*))

(in-package #:shiso/models/define-model)

(defparameter *mito-slot-keys*
  '(:col-type :initform :initarg :accessor :reader :writer
    :inflate :deflate :references :ghost :documentation
    :allocation :type)
  "Slot option keys that Mito/CLOS understand.  Everything else is shiso metadata.")

(defparameter *shiso-slot-keys*
  '(:verbose-name :help-text :validators :choices :blankp :editablep :widget :field-type)
  "Slot option keys that shiso extracts as field metadata.")

(defun strip-shiso-keys (slot-def)
  "Remove shiso-specific keys from a slot definition, keeping only Mito/CLOS keys.
SLOT-DEF is (name &rest plist)."
  (destructuring-bind (name &rest plist) slot-def
    (let ((cleaned nil))
      (loop for (key val) on plist by #'cddr
            when (member key *mito-slot-keys*)
              do (push key cleaned)
                 (push val cleaned))
      (cons name (nreverse cleaned)))))

(defun extract-metadata (slot-def)
  "Build a (make-slot-metadata ...) form from a slot definition.
Extracts shiso-specific keys and also captures :col-type for introspection."
  (destructuring-bind (name &rest plist) slot-def
    (let ((args nil))
      ;; Name is always first
      (push :name args)
      (push `',name args)
      ;; Always capture col-type for the introspection API
      (let ((col-type (getf plist :col-type)))
        (when col-type
          (push :col-type args)
          (push `',col-type args)))
      ;; Extract shiso-specific metadata
      ;; Use a sentinel to distinguish "not provided" from "provided as nil"
      (let ((sentinel (gensym)))
        (loop for key in *shiso-slot-keys*
              for val = (getf plist key sentinel)
              unless (eq val sentinel)
                do (case key
                     (:validators
                      (push key args)
                      (push `(list ,@(mapcar (lambda (v)
                                               (if (listp v)
                                                   `(list ',(car v) ,@(cdr v))
                                                   `',v))
                                             val))
                            args))
                     (:choices
                      (push key args)
                      (push `(list ,@(mapcar (lambda (c)
                                               ;; Support both (:key "Label") and (:key . "Label")
                                               (let ((label (if (consp (cdr c))
                                                                (cadr c)
                                                                (cdr c))))
                                                 `(cons ,(car c) ,label)))
                                             val))
                            args))
                     (otherwise
                      (push key args)
                      (push val args)))))
      `(meta:make-slot-metadata ,@(nreverse args)))))

(defmacro define-model (name slots &body options)
  "Define a model class with database backing and field metadata.

Each slot in SLOTS is (slot-name &rest plist) where the plist may contain
both Mito keys (:col-type, :initform, etc.) and shiso metadata keys
(:verbose-name, :help-text, :validators, :choices, :blankp, :editablep, :widget).

OPTIONS may include:
  (:module <module-name>) -- associate with a shiso module
  (:table-name <string>)  -- override the Mito table name"
  (declare (ignore options))
  (let* ((slots (mapcar #'ft:expand-field-type slots))
         (mito-slots (mapcar #'strip-shiso-keys slots))
         (meta-forms (mapcar #'extract-metadata slots))
         (registry-package (symbol-package 'reg:*model-registry*))
         (registered-name (intern (string-upcase name) registry-package)))
    `(progn
       (mito:deftable ,registered-name ()
         ,mito-slots)
       (reg:register-model ',registered-name
                           (find-class ',registered-name)
                           (list ,@meta-forms))
       ',registered-name)))
