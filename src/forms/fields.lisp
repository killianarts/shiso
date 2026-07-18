(defpackage #:shiso/forms/fields
  (:use #:cl)
  (:export
   ;; Base class and accessors
   #:form-field
   #:field-name
   #:field-label
   #:field-help-text
   #:field-requiredp
   #:field-validators
   #:field-initial
   #:field-widget
   ;; Field types
   #:char-field
   #:field-max-length
   #:text-field
   #:integer-field
   #:boolean-field
   #:choice-field
   #:field-choices
   #:date-field
   #:email-field
   ;; Parsing
   #:parse-field-value
   ;; Mapping
   #:col-type-to-field-class
   #:register-widget-field-class
   #:widget-field-class))

(in-package #:shiso/forms/fields)

(defclass form-field ()
  ((name       :initarg :name       :reader field-name)
   (label      :initarg :label      :reader field-label)
   (help-text  :initarg :help-text  :reader field-help-text  :initform nil)
   (requiredp  :initarg :requiredp  :reader field-requiredp  :initform t)
   (validators :initarg :validators :reader field-validators  :initform nil)
   (initial    :initarg :initial    :reader field-initial     :initform nil)
   (widget     :initarg :widget     :reader field-widget      :initform nil)))

(defclass char-field (form-field)
  ((max-length :initarg :max-length :reader field-max-length :initform nil)))

(defclass text-field (form-field) ())

(defclass integer-field (form-field) ())

(defclass boolean-field (form-field)
  ()
  (:default-initargs :requiredp nil))

(defclass choice-field (form-field)
  ((choices :initarg :choices :reader field-choices)))

(defclass date-field (form-field) ())

(defclass email-field (char-field) ())

(defgeneric parse-field-value (field raw-value)
  (:documentation "Parse a raw string VALUE into the appropriate type for FIELD."))

(defmethod parse-field-value ((field form-field) raw-value)
  raw-value)

(defmethod parse-field-value ((field integer-field) raw-value)
  (when (and raw-value (stringp raw-value) (plusp (length raw-value)))
    (parse-integer raw-value :junk-allowed t)))

(defmethod parse-field-value ((field boolean-field) raw-value)
  ;; HTML checkboxes send "on" when checked, nothing when unchecked
  (and raw-value (not (string= raw-value "")) t))

(defmethod parse-field-value ((field choice-field) raw-value)
  ;; Convert string back to keyword if choices are keywords
  (when (and raw-value (plusp (length raw-value)))
    (let ((choices (field-choices field)))
      (if (and choices (keywordp (car (first choices))))
          (intern (string-upcase raw-value) :keyword)
          raw-value))))

(defmethod parse-field-value ((field date-field) raw-value)
  ;; HTML date inputs send "YYYY-MM-DD"; datetime-local sends
  ;; "YYYY-MM-DDTHH:MM" (with seconds only when the control had them).
  ;; A blank or absent value parses to NIL rather than erroring.
  (when (and (stringp raw-value) (plusp (length raw-value)))
    (let ((value (if (= 1 (count #\: raw-value))
                     ;; Minutes but no seconds — local-time needs them.
                     (concatenate 'string raw-value ":00")
                     raw-value)))
      (local-time:parse-timestring value))))

(defun col-type-to-field-class (col-type)
  "Map a Mito column type keyword to a form-field class symbol."
  (cond
    ((and (listp col-type) (eq (car col-type) :varchar))
     'char-field)
    ((eq col-type :text)     'text-field)
    ((eq col-type :integer)  'integer-field)
    ((eq col-type :boolean)  'boolean-field)
    ((member col-type '(:timestamp :timestamptz :date))
     'date-field)
    (t 'char-field)))

(defvar *widget-field-classes* (make-hash-table :test 'eq)
  "Maps widget keywords to form-field class names. Consulted by model-form
generation before `col-type-to-field-class', so a widget can select a
field class the col-type alone cannot imply (e.g. :email on a varchar).
This is the forms-side half of a custom field type: pair a
`define-field-type' that sets :widget with a registration here plus a
`parse-field-value' method when the type needs its own coercion.")

(defun register-widget-field-class (widget class-name)
  "Register CLASS-NAME (a form-field class symbol) as the field class for
fields whose model metadata declares :widget WIDGET."
  (setf (gethash widget *widget-field-classes*) class-name))

(defun widget-field-class (widget)
  "Return the form-field class registered for WIDGET, or NIL."
  (and widget (gethash widget *widget-field-classes*)))

(register-widget-field-class :email 'email-field)
