(defpackage #:shiso/t/forms
  (:use #:cl #:lisp-unit2))

(in-package #:shiso/t/forms)

(defun fresh-registry ()
  (clrhash shiso/models:*model-registry*))

(defmacro with-fresh-registry (&body body)
  (let ((saved (gensym "SAVED")))
    `(let ((,saved (alexandria:copy-hash-table shiso/models:*model-registry*)))
       (fresh-registry)
       (unwind-protect (progn ,@body)
         (setf shiso/models:*model-registry* ,saved)))))

(define-test integer-field-parses-string ()
  (let ((field (make-instance 'shiso/forms:integer-field :name 'age :label "Age")))
    (assert-eql 42 (shiso/forms:parse-field-value field "42"))))

(define-test integer-field-returns-nil-for-empty ()
  (let ((field (make-instance 'shiso/forms:integer-field :name 'age :label "Age")))
    (assert-false (shiso/forms:parse-field-value field ""))))

(define-test boolean-field-parses-on ()
  (let ((field (make-instance 'shiso/forms:boolean-field :name 'active :label "Active")))
    (assert-true (shiso/forms:parse-field-value field "on"))))

(define-test boolean-field-returns-nil-for-empty ()
  (let ((field (make-instance 'shiso/forms:boolean-field :name 'active :label "Active")))
    (assert-false (shiso/forms:parse-field-value field ""))))

(define-test choice-field-parses-keyword ()
  (let ((field (make-instance 'shiso/forms:choice-field
                              :name 'status :label "Status"
                              :choices '((:draft . "Draft") (:published . "Published")))))
    (assert-eq :DRAFT (shiso/forms:parse-field-value field "draft"))))

(define-test varchar-maps-to-char-field ()
  (assert-eq 'shiso/forms:char-field
             (shiso/forms:col-type-to-field-class '(:varchar 200))))

(define-test text-maps-to-text-field ()
  (assert-eq 'shiso/forms:text-field
             (shiso/forms:col-type-to-field-class :text)))

(define-test integer-maps-to-integer-field ()
  (assert-eq 'shiso/forms:integer-field
             (shiso/forms:col-type-to-field-class :integer)))

(define-test boolean-maps-to-boolean-field ()
  (assert-eq 'shiso/forms:boolean-field
             (shiso/forms:col-type-to-field-class :boolean)))

(define-test make-model-form-creates-fields ()
  (with-fresh-registry
    (eval '(shiso/models:define-model form-gen-test
            ((title   :col-type (:varchar 200) :verbose-name "Title")
             (content :col-type :text))))
    (let* ((form (shiso/forms:make-model-form 'form-gen-test))
           (fields (shiso/forms:form-fields form)))
      (assert-eql 2 (length fields)
                  "Should create two form fields"))))

(define-test make-model-form-respects-exclude ()
  (with-fresh-registry
    (eval '(shiso/models:define-model exclude-test
            ((title   :col-type (:varchar 200))
             (secret  :col-type :text))))
    (let* ((form (shiso/forms:make-model-form 'exclude-test :exclude '(secret)))
           (fields (shiso/forms:form-fields form)))
      (assert-eql 1 (length fields)
                  "Excluded field should not appear"))))

(define-test make-model-form-respects-editablep ()
  (with-fresh-registry
    (eval '(shiso/models:define-model editable-test
            ((title   :col-type (:varchar 200))
             (slug    :col-type (:varchar 200) :editablep nil))))
    (let* ((form (shiso/forms:make-model-form 'editable-test))
           (fields (shiso/forms:form-fields form)))
      (assert-eql 1 (length fields)
                  "Non-editable field should be excluded"))))

(define-test make-model-form-creates-choice-field-for-choices ()
  (with-fresh-registry
    (eval '(shiso/models:define-model choice-form-test
            ((status :col-type (:varchar 20)
                     :choices ((:draft . "Draft") (:published . "Published"))))))
    (let* ((form (shiso/forms:make-model-form 'choice-form-test))
           (field (first (shiso/forms:form-fields form))))
      (assert-true (typep field 'shiso/forms:choice-field)
                   "Choices field should produce a choice-field"))))

(define-test make-model-form-sets-char-field-max-length ()
  (with-fresh-registry
    (eval '(shiso/models:define-model maxlen-form-test
            ((title :col-type (:varchar 200)))))
    (let* ((form (shiso/forms:make-model-form 'maxlen-form-test))
           (field (first (shiso/forms:form-fields form))))
      (assert-eql 200 (shiso/forms:field-max-length field)
                  "char-field should have max-length from varchar"))))

(define-test validate-form-passes-with-valid-data ()
  (with-fresh-registry
    (eval '(shiso/models:define-model valid-form-test
            ((title :col-type (:varchar 200)))))
    (let ((form (shiso/forms:make-model-form 'valid-form-test
                                             :data '((title . "Hello")))))
      (assert-true (shiso/forms:validate-form form)
                   "Form with valid data should pass"))))

(define-test validate-form-fails-on-required-blank ()
  (with-fresh-registry
    (eval '(shiso/models:define-model blank-form-test
            ((title :col-type (:varchar 200)))))
    (let ((form (shiso/forms:make-model-form 'blank-form-test
                                             :data '((title . "")))))
      (assert-false (shiso/forms:validate-form form)
                    "Blank required field should fail")
      (assert-true (gethash 'title (shiso/forms:form-errors form))
                   "Errors should contain title"))))

(define-test validate-form-allows-blank-when-blankp ()
  (with-fresh-registry
    (eval '(shiso/models:define-model blankp-form-test
            ((bio :col-type :text :blankp t))))
    (let ((form (shiso/forms:make-model-form 'blankp-form-test
                                             :data '((bio . "")))))
      (assert-true (shiso/forms:validate-form form)
                   "Blank-allowed field should pass when empty"))))

(define-test validate-form-no-duplicate-errors ()
  (with-fresh-registry
    (eval '(shiso/models:define-model dup-err-test
            ((title :col-type (:varchar 200)
               :validators (shiso/validators:not-blank)))))
    (let ((form (shiso/forms:make-model-form 'dup-err-test
                                             :data '((title . "")))))
      (shiso/forms:validate-form form)
      (let ((errs (gethash 'title (shiso/forms:form-errors form))))
        (assert-eql 1 (length errs)
                    "Should not duplicate not-blank from auto and explicit")))))

(define-test render-form-produces-html-string ()
  (with-fresh-registry
    (eval '(shiso/models:define-model render-test
            ((title :col-type (:varchar 200) :verbose-name "Title"))))
    (let* ((form (shiso/forms:make-model-form 'render-test))
           (html (almighty-html:render-to-string
                  (shiso/forms:render-form form))))
      (assert-true (search "<form" html)
                   "Should contain form tag")
      (assert-true (search "name=\"title\"" html)
                   "Should contain input with name=title")
      (assert-true (search "<label" html)
                   "Should contain a label")
      (assert-true (search "<button" html)
                   "Should contain a submit button"))))

(define-test render-form-shows-errors ()
  (with-fresh-registry
    (eval '(shiso/models:define-model render-err-test
            ((title :col-type (:varchar 200)))))
    (let ((form (shiso/forms:make-model-form 'render-err-test
                                             :data '((title . "")))))
      (shiso/forms:validate-form form)
      (let ((html (almighty-html:render-to-string
                   (shiso/forms:render-form form))))
        (assert-true (search "has-errors" html)
                     "Should have error class on field group")
        (assert-true (search "field-error" html)
                     "Should contain error message element")))))

(define-test render-textarea-for-text-field ()
  (with-fresh-registry
    (eval '(shiso/models:define-model textarea-test
            ((content :col-type :text :verbose-name "Content"))))
    (let* ((form (shiso/forms:make-model-form 'textarea-test))
           (html (almighty-html:render-to-string
                  (shiso/forms:render-form form))))
      (assert-true (search "<textarea" html)
                   "Text field should render as textarea"))))

(define-test render-select-for-choice-field ()
  (with-fresh-registry
    (eval '(shiso/models:define-model select-test
            ((status :col-type (:varchar 20)
                     :choices ((:draft . "Draft") (:published . "Published"))))))
    (let* ((form (shiso/forms:make-model-form 'select-test))
           (html (almighty-html:render-to-string
                  (shiso/forms:render-form form))))
      (assert-true (search "<select" html)
                   "Choice field should render as select")
      (assert-true (search "Draft" html)
                   "Should contain choice labels"))))

;;; Headless context + widget resolution

(define-test field-context-exposes-sticky-value-and-widget ()
  (with-fresh-registry
    (eval '(shiso/models:define-model ctx-test
            ((title :col-type (:varchar 200) :verbose-name "Title")
             (body  :col-type :text :verbose-name "Body"))))
    (let* ((form (shiso/forms:make-model-form 'ctx-test
                                              :data '(("title" . "Hello"))))
           (title-ctx (shiso/forms:field-context form 'title))
           (body-ctx (shiso/forms:field-context form 'body)))
      (assert-equal "Hello" (getf title-ctx :value))
      (assert-equal "title" (getf title-ctx :name-string))
      (assert-equal "Title" (getf title-ctx :label))
      (assert-eq :text-input (getf title-ctx :widget)
                 "char-field without explicit widget defaults to :text-input")
      (assert-eq :textarea (getf body-ctx :widget)
                 "text-field resolves to :textarea"))))

#+nil
(with-fresh-registry
  (shiso/models:define-model ctx-test
      ((title :col-type (:varchar 200) :verbose-name "The Title")
       (body :col-type :text :verbose-name "The Body")))
  (let* ((form (shiso/forms:make-model-form 'ctx-test :data '(("title" . "Sup dawg")
                                                              ("body" . "Nothin' much."))))
         (title-ctx (shiso/forms:field-context form 'title))
         (body-ctx (shiso/forms:field-context form 'body)))
    (shiso/forms:render-fields form)))
(define-test field-context-carries-errors-after-validate ()
  (with-fresh-registry
    (eval '(shiso/models:define-model ctx-err-test
            ((title :col-type (:varchar 200)))))
    (let ((form (shiso/forms:make-model-form 'ctx-err-test
                                             :data '(("title" . "")))))
      (assert-false (shiso/forms:validate-form form))
      (let ((ctx (shiso/forms:field-context form 'title)))
        (assert-true (getf ctx :errors)
                     "Failed validation should surface on field-context")))))

(define-test resolve-widget-honours-explicit-widget ()
  (let ((field (make-instance 'shiso/forms:char-field
                              :name 'password
                              :label "Password"
                              :widget :password)))
    (assert-eq :password (shiso/forms:resolve-widget field))))

(define-test widget-selects-email-field-class ()
  (with-fresh-registry
    (eval '(shiso/models:define-model email-widget-test
            ((addr :field-type :email :verbose-name "Email"))))
    (let* ((form (shiso/forms:make-model-form 'email-widget-test))
           (field (first (shiso/forms:form-fields form)))
           (html (almighty-html:render-to-string
                  (shiso/forms:render-form form))))
      (assert-true (typep field 'shiso/forms:email-field)
                   ":email widget/field-type should produce email-field")
      (assert-true (search "type=\"email\"" html)
                   "email-field should render type=email"))))

(define-test password-widget-renders-password-input ()
  (let* ((form (make-instance 'shiso/forms:form
                              :fields (list (make-instance 'shiso/forms:char-field
                                                           :name 'password
                                                           :label "Password"
                                                           :widget :password))
                              :data '(("password" . "secret"))))
         (html (almighty-html:render-to-string
                (shiso/forms:render-form form))))
    (assert-true (search "type=\"password\"" html)
                 "password widget should render type=password")
    (assert-false (search "secret" html)
                  "password inputs must not echo submitted values")))

(define-test date-field-parses-date-and-datetime-local ()
  (let ((field (make-instance 'shiso/forms:date-field :name 'when :label "When")))
    (assert-true (typep (shiso/forms:parse-field-value field "2024-06-01")
                        'local-time:timestamp)
                 "HTML date input YYYY-MM-DD should parse")
    (assert-true (typep (shiso/forms:parse-field-value field "2024-06-01T14:30")
                        'local-time:timestamp)
                 "datetime-local without seconds should parse")
    (assert-false (shiso/forms:parse-field-value field "")
                  "blank date should parse to NIL")))

(define-test render-fields-emits-form-row-ids ()
  (with-fresh-registry
    (eval '(shiso/models:define-model row-id-test
            ((title :col-type (:varchar 200) :verbose-name "Title"))))
    (let* ((form (shiso/forms:make-model-form 'row-id-test))
           (html (almighty-html:render-to-string
                  (almighty-html:</>
                   (div (shiso/forms:render-fields form))))))
      (assert-true (search "id=\"form-row-title\"" html)
                   "Each field row should carry form-row-<name> id")
      (assert-false (search "<form" html)
                    "render-fields should not wrap in a form tag"))))

(define-test cleaned-value-matches-by-name-string ()
  (with-fresh-registry
    (eval '(shiso/models:define-model cleaned-test
            ((title :col-type (:varchar 200)))))
    (let ((form (shiso/forms:make-model-form 'cleaned-test
                                             :data '(("title" . "Hi")))))
      (assert-true (shiso/forms:validate-form form))
      (assert-equal "Hi" (shiso/forms:cleaned-value form "title"))
      (assert-equal "Hi" (shiso/forms:cleaned-value form 'title)))))

(define-test form-field-by-name-finds-field ()
  (with-fresh-registry
    (eval '(shiso/models:define-model by-name-test
            ((title :col-type (:varchar 200))
             (body  :col-type :text))))
    (let* ((form (shiso/forms:make-model-form 'by-name-test))
           (field (shiso/forms:form-field-by-name form "title")))
      (assert-true field)
      (assert-equal "TITLE" (symbol-name (shiso/forms:field-name field))))))
