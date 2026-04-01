(defpackage #:shiso/models
  (:use #:cl)
  (:import-from #:shiso/models/metadata
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
                #:model-metadata
                #:make-model-metadata
                #:model-metadata-class
                #:model-metadata-fields)
  (:import-from #:shiso/models/registry
                #:*model-registry*
                #:register-model
                #:get-model-name
                #:model-fields
                #:model-field
                #:model-class
                #:all-models
                #:field-name
                #:field-col-type
                #:field-verbose-name
                #:field-help-text
                #:field-validators
                #:field-choices
                #:field-blankp
                #:field-editablep
                #:field-widget)
  (:import-from #:shiso/models/field-types
                #:*field-types*
                #:define-field-type
                #:expand-field-type)
  (:import-from #:shiso/models/define-model
                #:define-model)
  (:export
   ;; Structs
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
   #:model-metadata
   #:make-model-metadata
   #:model-metadata-class
   #:model-metadata-fields
   ;; Name normalization
   #:normalize-name
   ;; Registry
   #:*model-registry*
   #:register-model
   #:get-model-name
   ;; Introspection
   #:model-fields
   #:model-field
   #:model-class
   #:all-models
   ;; Field readers
   #:field-name
   #:field-col-type
   #:field-verbose-name
   #:field-help-text
   #:field-validators
   #:field-choices
   #:field-blankp
   #:field-editablep
   #:field-widget
   ;; Field types
   #:*field-types*
   #:define-field-type
   #:expand-field-type
   ;; Macro
   #:define-model))
