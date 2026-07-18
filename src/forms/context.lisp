(defpackage #:shiso/forms/context
  (:use #:cl)
  (:local-nicknames (#:fields #:shiso/forms/fields)
                    (#:form #:shiso/forms/form)
                    (#:req #:lack/request))
  (:export
   #:field-context
   #:form-field-by-name
   #:cleaned-value
   #:resolve-widget
   #:request-form-data))

(in-package #:shiso/forms/context)

;;;; The headless half of the forms feature: everything a page needs to
;;;; render a field — sticky value, errors, label, widget — as plain data,
;;;; with no opinion about markup. `render-fields'/`render-form' consume
;;;; this too, but so can hand-written pages and app-defined components.

(defun resolve-widget (field)
  "Return a concrete widget keyword for FIELD.
The explicit :widget from model metadata (or the field-type default merged
into it) wins; otherwise a default is derived from the field's class. Every
field therefore always has a widget — including fields built from raw
col-types that never passed through a field-type expander."
  (or (fields:field-widget field)
      (typecase field
        ;; email-field before char-field: it is a subclass.
        (fields:email-field   :email)
        (fields:text-field    :textarea)
        (fields:boolean-field :checkbox)
        (fields:integer-field :number)
        (fields:choice-field  :select)
        (fields:date-field    :datetime-local)
        (t                    :text-input))))

(defun form-field-by-name (form name)
  "Find a field of FORM by NAME (a symbol or string), matched by symbol name."
  (find (string name) (form:form-fields form)
        :key (lambda (f) (symbol-name (fields:field-name f)))
        :test #'string-equal))

(defun sticky-value (form field)
  "The value a re-rendered field should display: the submitted value from
form data when present, otherwise the field's initial value (e.g. from a
bound model instance)."
  (or (cdr (assoc (fields:field-name field) (form:form-data form)
                  :test #'string-equal))
      (fields:field-initial field)))

(defun field-context (form field-designator)
  "Return a plist describing FIELD-DESIGNATOR's render state within FORM.

FIELD-DESIGNATOR is a form-field object, or a symbol/string naming one.
Keys:
  :name        slot-name symbol
  :name-string downcased name, for name=/id= attributes
  :label       human label
  :help-text   help text or NIL
  :value       sticky value (submitted data, else initial)
  :errors      list of error strings for this field, or NIL
  :requiredp   T when the field must not be blank
  :widget      concrete widget keyword (see `resolve-widget')
  :choices     alist of (value . label) for choice fields, else NIL
  :max-length  varchar limit for char fields, else NIL"
  (let* ((field (if (typep field-designator 'fields:form-field)
                    field-designator
                    (or (form-field-by-name form field-designator)
                        (error "No field named ~A in ~A." field-designator form))))
         (name (fields:field-name field)))
    (list :name name
          :name-string (string-downcase (symbol-name name))
          :label (fields:field-label field)
          :help-text (fields:field-help-text field)
          :value (sticky-value form field)
          :errors (gethash name (form:form-errors form))
          :requiredp (fields:field-requiredp field)
          :widget (resolve-widget field)
          :choices (when (typep field 'fields:choice-field)
                     (fields:field-choices field))
          :max-length (when (typep field 'fields:char-field)
                        (fields:field-max-length field)))))

(defun cleaned-value (form name)
  "Return the cleaned (validated, coerced) value of the field named NAME
(a symbol or string) after `validate-form'. The cleaned-data hash is
keyed by the field's name symbol, which lives in whatever package defined
the form — this accessor matches by name string so callers in other
packages don't silently miss."
  (let ((field (form-field-by-name form name)))
    (when field
      (gethash (fields:field-name field) (form:form-cleaned-data form)))))

(defun request-form-data ()
  "Read the current request's body parameters as canonical form data:
an alist of (downcased-string . value), suitable for a form's :data.
Signals an error outside a request cycle."
  (let ((request shiso/requests:*request*))
    (unless request
      (error "request-form-data called outside a request."))
    (mapcar (lambda (pair)
              (cons (string-downcase (car pair)) (cdr pair)))
            (req:request-body-parameters request))))
