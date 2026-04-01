(defpackage #:shiso/forms/rendering
  (:use #:cl)
  (:local-nicknames (#:fields #:shiso/forms/fields)
                    (#:form #:shiso/forms/form)
                    (#:ah #:almighty-html))
  (:export
   #:render-field
   #:render-form))

(in-package #:shiso/forms/rendering)

(defgeneric render-field (field &key value errors)
  (:documentation "Render a form field to an almighty-html element."))

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

(defmethod render-field ((field fields:char-field) &key value errors)
  (let ((name-str (field-name-str field))
        (css-class (if errors "form-group has-errors" "form-group"))
        (val (or value "")))
    (ah:</>
     (div :class css-class
       (ah:</> (label :for name-str (fields:field-label field)))
       (ah:</> (input :type "text" :name name-str :id name-str :value val))
       (render-help-text field)
       (render-errors errors)))))

(defmethod render-field ((field fields:text-field) &key value errors)
  (let ((name-str (field-name-str field))
        (css-class (if errors "form-group has-errors" "form-group"))
        (val (or value "")))
    (ah:</>
     (div :class css-class
       (ah:</> (label :for name-str (fields:field-label field)))
       (ah:</> (textarea :name name-str :id name-str val))
       (render-help-text field)
       (render-errors errors)))))

(defmethod render-field ((field fields:integer-field) &key value errors)
  (let ((name-str (field-name-str field))
        (css-class (if errors "form-group has-errors" "form-group"))
        (val (if value (princ-to-string value) "")))
    (ah:</>
     (div :class css-class
       (ah:</> (label :for name-str (fields:field-label field)))
       (ah:</> (input :type "number" :name name-str :id name-str :value val))
       (render-help-text field)
       (render-errors errors)))))

(defmethod render-field ((field fields:boolean-field) &key value errors)
  (let ((name-str (field-name-str field))
        (css-class (if errors "form-group has-errors" "form-group")))
    (ah:</>
     (div :class css-class
       (ah:</> (label
                 (ah:</> (input :type "checkbox" :name name-str :id name-str
                           :checked value))
                 (fields:field-label field)))
       (render-help-text field)
       (render-errors errors)))))

(defmethod render-field ((field fields:choice-field) &key value errors)
  (let ((name-str (field-name-str field))
        (css-class (if errors "form-group has-errors" "form-group"))
        (option-elements
          (mapcar (lambda (choice)
                    (let* ((val (string-downcase (symbol-name (car choice))))
                           (display (cdr choice))
                           (selectedp (string-equal val
                                                    (if (keywordp value)
                                                        (symbol-name value)
                                                        (princ-to-string value)))))
                      (if selectedp
                          (ah:</> (option :value val :selected t display))
                          (ah:</> (option :value val display)))))
                  (fields:field-choices field))))
    (ah:</>
     (div :class css-class
       (ah:</> (label :for name-str (fields:field-label field)))
       (ah:</> (select :name name-str :id name-str
                 (ah:</> (option :value "" "---"))
                 option-elements))
       (render-help-text field)
       (render-errors errors)))))

(defmethod render-field ((field fields:email-field) &key value errors)
  (let ((name-str (field-name-str field))
        (css-class (if errors "form-group has-errors" "form-group"))
        (val (or value "")))
    (ah:</>
     (div :class css-class
       (ah:</> (label :for name-str (fields:field-label field)))
       (ah:</> (input :type "email" :name name-str :id name-str :value val))
       (render-help-text field)
       (render-errors errors)))))

#+nil
(local-time:format-timestring t (local-time:now) :format '(:year "-" :month "-" :day))

(defun format-datetime-local (timestamp)
  "Format a local-time:timestamp for HTML datetime-local input (no timezone offset)."
  (local-time:format-timestring
   nil timestamp
   :format '(:year "-" (:month 2) "-" (:day 2) "T" (:hour 2) ":" (:min 2) ":" (:sec 2))))

(defmethod render-field ((field fields:date-field) &key value errors)
  (let ((name-str (field-name-str field))
        (css-class (if errors "form-group has-errors" "form-group"))
        (val (if (typep value 'local-time:timestamp)
                 (format-datetime-local value)
                 (or value ""))))
    (ah:</>
     (div :class css-class
       (ah:</> (label :for name-str (fields:field-label field)))
       (ah:</> (input :type "datetime-local" :name name-str :id name-str :value val))
       (render-help-text field)
       (render-errors errors)))))

(defmethod render-field ((field fields:form-field) &key value errors)
  (let ((name-str (field-name-str field))
        (css-class (if errors "form-group has-errors" "form-group"))
        (val (or value "")))
    (ah:</>
     (div :class css-class
       (ah:</> (label :for name-str (fields:field-label field)))
       (ah:</> (input :type "text" :name name-str :id name-str :value val))
       (render-help-text field)
       (render-errors errors)))))

(defun render-form (form &key (action "") (method "POST") (submit-label "Submit"))
  "Render an entire form to an almighty-html element."
  (let ((field-elements
          (mapcar (lambda (field)
                    (let* ((name (fields:field-name field))
                           (value (or (cdr (assoc name (form:form-data form)
                                                  :test #'string-equal))
                                      (fields:field-initial field)))
                           (field-errors (gethash name (form:form-errors form))))
                      (render-field field :value value :errors field-errors)))
                  (form:form-fields form))))
    (ah:</>
     (form :action action :method method
       field-elements
       (ah:</> (button :type "submit" submit-label))))))
