(defpackage #:shiso/models/metadata
  (:use #:cl)
  (:export
   ;; Slot metadata
   #:slot-metadata
   #:make-slot-metadata
   #:slot-metadata-name
   #:slot-metadata-col-type
   #:slot-metadata-verbose-name
   #:slot-metadata-help-text
   #:slot-metadata-validators
   #:slot-metadata-choices
   #:slot-metadata-blankp
   #:slot-metadata-editablep
   #:slot-metadata-widget
   ;; Model metadata
   #:model-metadata
   #:make-model-metadata
   #:model-metadata-class
   #:model-metadata-fields))

(in-package #:shiso/models/metadata)

(defstruct slot-metadata
  "Metadata for a single model field, extracted from define-model slot options."
  name          ; symbol -- the slot name
  col-type      ; Mito column type, e.g. (:varchar 200), :text, :integer
  verbose-name  ; string -- human-readable label, or nil (auto-derived from name)
  help-text     ; string -- help text for forms, or nil
  validators    ; list of validator designators
  choices       ; alist of (keyword . "Display Label") pairs, or nil
  (blankp nil)  ; t = field may be blank; nil = required
  (editablep t) ; nil = excluded from forms entirely
  widget)       ; keyword override for rendering (:textarea, :hidden, etc.)

(defstruct model-metadata
  "Metadata for a model: its CLOS class and ordered field definitions."
  class         ; the CLOS class object
  fields)       ; list of slot-metadata, in declaration order
