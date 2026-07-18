;;;; Form components owned by the todo example.
;;;;
;;;; Same contract as the scaffolded skeleton/app form-components:
;;;; data from `shiso:field-context', markup here. Edit `ac-field' to
;;;; restyle every form field in this app.

(defpackage #:todos/hypermedia/form-components
  (:use #:cl)
  (:local-nicknames (#:ah #:almighty-html)
                    (#:s  #:shiso))
  (:export #:ac-csrf-input
           #:ac-field
           #:ac-fields))

(in-package #:todos/hypermedia/form-components)

(ah:define-component ac-csrf-input (&key children)
  "Hidden `_csrf_token' input for the current session."
  (declare (ignore children))
  (let ((token (and s:*request* (s:csrf-token-value))))
    (when token
      (ah:</> (input :type "hidden" :name "_csrf_token" :value token)))))

(defun field-value-string (widget value)
  (typecase value
    (null "")
    (string value)
    (local-time:timestamp
     (if (eq widget :date)
         (local-time:format-timestring
          nil value :format '(:year "-" (:month 2) "-" (:day 2)))
         (local-time:format-timestring
          nil value :format '(:year "-" (:month 2) "-" (:day 2) "T"
                              (:hour 2) ":" (:min 2) ":" (:sec 2)))))
    (t (princ-to-string value))))

(defun select-control (field-name value choices)
  (let ((opts (loop :for (choice-value . choice-label) :in choices
                    :for val := (string-downcase (symbol-name choice-value))
                    :for selectedp := (and value
                                           (string-equal
                                            val
                                            (if (keywordp value)
                                                (symbol-name value)
                                                (princ-to-string value))))
                    :collect (if selectedp
                                 (ah:</> (option :value val :selected t choice-label))
                                 (ah:</> (option :value val choice-label))))))
    (ah:</> (select :name field-name :id field-name
              (ah:</> (option :value "" "---"))
              opts))))

(ah:define-component ac-field (&key field children)
  "One form field from a `shiso:field-context' plist. CHILDREN replace the control."
  (let* ((field-name  (getf field :name-string))
         (label-text  (getf field :label))
         (help-text   (getf field :help-text))
         (errors      (getf field :errors))
         (value       (getf field :value))
         (widget      (getf field :widget))
         (row-id      (concatenate 'string "form-row-" field-name))
         (wrap-class  (if errors "field has-errors" "field"))
         (error-block (when errors
                        (ah:</> (ul :class "field-errors"
                                  (loop :for e :in errors
                                        :collect (ah:</> (li e)))))))
         (help-block  (when help-text
                        (ah:</> (p :class "help-text" help-text))))
         (control
           (or children
               (case widget
                 (:textarea
                  (ah:</> (textarea :name field-name :id field-name
                            (field-value-string widget value))))
                 (:checkbox
                  (ah:</> (input :type "checkbox" :name field-name
                            :id field-name :checked value)))
                 (:select
                  (select-control field-name value (getf field :choices)))
                 (:password
                  (ah:</> (input :type "password" :name field-name
                            :id field-name)))
                 (:hidden
                  (ah:</> (input :type "hidden" :name field-name
                            :id field-name
                            :value (field-value-string widget value))))
                 ((:email :url :number :date :datetime-local)
                  (ah:</> (input :type (string-downcase (symbol-name widget))
                            :name field-name :id field-name
                            :value (field-value-string widget value))))
                 (t
                  (ah:</> (input :type "text" :name field-name
                            :id field-name
                            :value (field-value-string widget value))))))))
    (case widget
      (:hidden (if children
                   (ah:</> (div :class wrap-class :id row-id
                             control error-block))
                   control))
      (:checkbox
       (let ((labelled (ah:</> (label control " " label-text))))
         (ah:</> (div :class wrap-class :id row-id
                   labelled
                   help-block
                   error-block))))
      (t
       (let ((label-el (ah:</> (label :for field-name label-text))))
         (ah:</> (div :class wrap-class :id row-id
                   label-el
                   control
                   help-block
                   error-block)))))))

(ah:define-component ac-fields (&key form children)
  "Every field of FORM, rendered with `ac-field' in declaration order."
  (declare (ignore children))
  (ah:</>
   (<>
     (loop :for f :in (s:form-fields form)
           :collect (ac-field :field (s:field-context form f))))))
