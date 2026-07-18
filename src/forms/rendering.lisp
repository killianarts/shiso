(defpackage #:shiso/forms/rendering
  (:use #:cl)
  (:local-nicknames (#:fields #:shiso/forms/fields)
                    (#:form #:shiso/forms/form)
                    (#:context #:shiso/forms/context)
                    (#:ah #:almighty-html))
  (:export
   #:render-field
   #:render-fields
   #:render-form))

(in-package #:shiso/forms/rendering)

;;;; Default form markup. Rendering is dispatched through the generic
;;;; function `render-field' on a STYLE designator plus the field, so an
;;;; application can define its own styles (EQL methods on its own
;;;; keywords) without ever affecting other consumers — the admin renders
;;;; with STYLE :admin, which falls through to the built-in defaults
;;;; unless :admin methods are explicitly defined.
;;;;
;;;; Apps that want full control of markup usually skip this layer
;;;; entirely and build their own components over `field-context'.

;;; ----------------------------------------------------------------------
;;; Shared pieces.

(defun render-errors (errors)
  "Render a list of error strings as an almighty-html ul."
  (when errors
    (let ((items (mapcar (lambda (err)
                           (ah:</> (li :class "field-error" err)))
                         errors)))
      (ah:</> (ul :class "field-errors" items)))))

(defun render-help-text (field)
  "Render field help text if present."
  (let ((text (fields:field-help-text field)))
    (when text
      (ah:</> (p :class "help-text" text)))))

(defun field-name-str (field)
  (string-downcase (symbol-name (fields:field-name field))))

(defun format-datetime-local (timestamp)
  "Format a local-time:timestamp for HTML datetime-local input (no timezone offset)."
  (local-time:format-timestring
   nil timestamp
   :format '(:year "-" (:month 2) "-" (:day 2) "T" (:hour 2) ":" (:min 2) ":" (:sec 2))))

(defun display-value (widget value)
  "Coerce VALUE to the string an input's value= attribute should carry."
  (typecase value
    (null "")
    (string value)
    (local-time:timestamp
     (if (eq widget :date)
         (local-time:format-timestring
          nil value :format '(:year "-" (:month 2) "-" (:day 2)))
         (format-datetime-local value)))
    (t (princ-to-string value))))

(defun widget-input-type (widget)
  "The <input type=…> for simple input widgets."
  (case widget
    (:email          "email")
    (:url            "url")
    (:number         "number")
    (:date           "date")
    (:datetime-local "datetime-local")
    (:password       "password")
    (:hidden         "hidden")
    (t               "text")))

(defun render-select-control (field name-str value)
  (let ((option-elements
          (mapcar (lambda (choice)
                    (let* ((val (string-downcase (symbol-name (car choice))))
                           (display (cdr choice))
                           (selectedp (and value
                                           (string-equal
                                            val
                                            (if (keywordp value)
                                                (symbol-name value)
                                                (princ-to-string value))))))
                      (if selectedp
                          (ah:</> (option :value val :selected t display))
                          (ah:</> (option :value val display)))))
                  (fields:field-choices field))))
    (ah:</> (select :name name-str :id name-str
              (ah:</> (option :value "" "---"))
              option-elements))))

(defun render-control (field widget name-str value)
  "Build the bare form control for FIELD according to WIDGET."
  (case widget
    (:textarea
     (let ((val (display-value widget value)))
       (ah:</> (textarea :name name-str :id name-str val))))
    (:checkbox
     (ah:</> (input :type "checkbox" :name name-str :id name-str
               :checked value)))
    (:select
     (render-select-control field name-str value))
    (:password
     ;; Never echo a submitted password back into the page.
     (ah:</> (input :type "password" :name name-str :id name-str)))
    (t
     (let ((val (display-value widget value)))
       (ah:</> (input :type (widget-input-type widget)
                 :name name-str :id name-str :value val))))))

;;; ----------------------------------------------------------------------
;;; The style-dispatched renderer.

(defgeneric render-field (style field &key value errors)
  (:documentation "Render FIELD to an almighty-html element in STYLE.
STYLE is a designator applications may EQL-specialize on to supply their
own field markup; the built-in default handles (STYLE t) and honours the
field's resolved widget (see `shiso/forms/context:resolve-widget'). The
admin renders with STYLE :admin, so app-defined styles can never change
admin pages."))

(defmethod render-field ((style t) (field fields:form-field) &key value errors)
  (let* ((name-str (field-name-str field))
         (widget (context:resolve-widget field))
         (row-id (concatenate 'string "form-row-" name-str))
         (css-class (if errors "form-group has-errors" "form-group"))
         (control (render-control field widget name-str value))
         (help (render-help-text field))
         (errs (render-errors errors)))
    (case widget
      ;; Hidden inputs carry no chrome.
      (:hidden control)
      ;; Checkboxes wrap the control inside the label, after it.
      (:checkbox
       (let ((labelled (ah:</> (label control (fields:field-label field)))))
         (ah:</> (div :class css-class :id row-id
                   labelled
                   help
                   errs))))
      (t
       (let ((label-el (ah:</> (label :for name-str (fields:field-label field)))))
         (ah:</> (div :class css-class :id row-id
                   label-el
                   control
                   help
                   errs)))))))

;;; ----------------------------------------------------------------------
;;; Form-level conveniences.

(defun render-fields (form &key (style t))
  "Render each of FORM's fields via `render-field' and return the list of
elements, in declaration order. Emits no <form> wrapper — compose the
result inside your own form tag; `render-form' is the packaged version."
  (mapcar (lambda (field)
            (let ((ctx (context:field-context form field)))
              (render-field style field
                            :value (getf ctx :value)
                            :errors (getf ctx :errors))))
          (form:form-fields form)))

(defun csrf-token-input ()
  "Render a hidden `_csrf_token' input for the current request's session,
or NIL when there is no live request/session (e.g. unit tests that
render forms outside an HTTP cycle)."
  (when shiso/requests:*request*
    (let ((token (shiso/utils:csrf-token-value)))
      (when token
        (ah:</> (input :type "hidden" :name "_csrf_token" :value token))))))

(defun render-form (form &key (action "") (method "POST")
                              (submit-label "Submit") (style t))
  "Render an entire form to an almighty-html element. State-changing
methods (anything but GET) get a hidden CSRF token input prepended so
the Lack CSRF middleware accepts the submission."
  (let* ((field-elements (render-fields form :style style))
         (csrfp (not (string-equal method "GET")))
         (csrf-input (and csrfp (csrf-token-input))))
    (ah:</>
     (form :action action :method method
       csrf-input
       field-elements
       (ah:</> (button :type "submit" submit-label))))))
