# Template Plan

## Problem: Data mismatch between DB, CL, and HTML

In a previous task, you added some code to the form rendering logic in
shiso/forms/rendering.lisp:

```lisp
(defmethod render-field ((field fields:choice-field) &key value errors)
  (let ((name-str (field-name-str field))
        (css-class (if errors "form-group has-errors" "form-group"))
        (option-elements
          (mapcar (lambda (choice)
                    (let* ((val (string-downcase (symbol-name (car choice))))
                           (display (cdr choice))
                           ;; You added this so that the choice keyword could be
                           ;; compared to the string value returned by Mito
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
       
(defun format-datetime-local (timestamp)
  "Format a local-time:timestamp for HTML datetime-local input (no timezone offset)."
  (local-time:format-timestring
   nil timestamp
   :format '(:year "-" (:month 2) "-" (:day 2) "T" (:hour 2) ":" (:min 2) ":" (:sec 2))))

(defmethod render-field ((field fields:date-field) &key value errors)
  (let ((name-str (field-name-str field))
        (css-class (if errors "form-group has-errors" "form-group"))
        ;; You added the formatting here so that the form input field would
        ;; properly show the value returned by mito in model-instance-rebuild
        (val (if (typep value 'local-time:timestamp)
                 (format-datetime-local value)
                 (or value ""))))
    (ah:</>
     (div :class css-class
       (ah:</> (label :for name-str (fields:field-label field)))
       (ah:</> (input :type "datetime-local" :name name-str :id name-str :value val))
       (render-help-text field)
       (render-errors errors)))))
```

These modifications are necessary because of data mismatch between the data
returned by Mito from the SQL table, Common Lisp, and the data formatting used
by HTML. We have the following model in
`almightylisp/src/modules/books/models.lisp`:
```lisp
(shiso:define-model book
    ((title :initarg :title
       :col-type (:varchar 200)
       :verbose-name "Book Title"
       :help-text "The full title of the book"
       :validators ((validators:max-length 200)))
     (description :initarg :description
                  :col-type :text
                  :verbose-name "Description"
                  :blankp t
                  :widget :textarea)
     (status :initarg :status
             :col-type (:varchar 20)
             :choices ((:draft . "Draft")
                       (:published . "Published")
                       (:archived . "Archived"))
             :initform "draft")
     ;; If I add this, the column
     (published-at :initarg :published-at
                   :col-type :timestamptz
                   :initform (local-time:now))))
```

### Data mismatch example 1: choice field/keywords
Currently, we use `mito` as our ORM. Mito has an inflate/deflate functionality
for serializing data between the DB and Common Lisp. Our model has a `status`
field/slot with an alist with for `:choices`. However, in the `render-field`
above for the choice-field, we use the `symbol-name` of the keyword and compare
strings. This is because Mito doesn't serialize a "choice-field" value to a
keyword when returning data from the DB. Thus, we never actually compare
keywords--we compare strings.

### Data mismatch example 2: timestamps and HTML date input elements
When rendering Common Lisp objects to HTML using `almighty-html`, currently the
default behavior of almighty-html is to simply try to return the object.

```lisp
;; From shiso/vendored/almighty-html/src/element.lisp
(defmethod render-children ((element tag))
  (mapcar (lambda (child)
            (if (stringp child)
                (escape-html-text-content child)
                ;; If the child isn't a string, just return it.
                child))
          (element-children element)))
```

I believe this is okay for `local-time:timestamp` objects returned by Mito
because local-time defines a `print-object` method on timestamps, and
`almighty-html` will use that method to print the value of the timestamp.
(Please correct me if I am wrong and explain why.)

What this means is that if our ORM serializes to a Common Lisp object type that
doesn't have a `print-object` method specialized to it, it can't render the
object. This means, for example, that hash-tables don't get rendered (actually,
I only ever see a # character in the rendered HTML). The same is true of
structs.

Additionally, we hardcode the formatting of `local-time:timestamp` objects in
the `render-field` method for `fields:date-field` objects because if we don't
then the HTML date input element won't properly render a date/timestamp.

## How things work in Django

In Django, I believe the templating system will serialize Python values to
HTML-compatible values when passed in as context to template files. This means
that in components, templates, etc we don't need to have conditional statements
for every kind of data passed to the template; Django just takes care of
serializing values for us.

Additionally, inside the template, if we know that a certain value is a Python
`datetime` object, we can modify the display rendering of the object via
template filters (see:
https://docs.djangoproject.com/en/6.0/ref/templates/builtins/#date ) in the
template. I believe probably we don't need such filters since we can simply run
`local-time:format-timestring` on `local-time:timestamp`.


## An Idea on how to improve ergonomics
I want to improve the ergonomics of rendering common lisp objects in templates
and to improve compatibility between Common Lisp and SQL data returned by Mito.

### SQL <-> Common Lisp data mismatch fix idea
For mismatches like the status slot/field where Mito returns a string when we
really want a keyword value, maybe we can automatically add the necessary Mito
inflate/deflate options? From the mito README:

```lisp
(mito:deftable user-report ()
  ((title :col-type (:varchar 100))
   (body :col-type :text
         :initform "")
   (reported-at :col-type :timestamp
                :initform (local-time:now)
                :inflate #'local-time:universal-to-timestamp
                :deflate #'local-time:timestamp-to-universal))
  (:conc-name report-))
```

Maybe we could have simple `keyword-to-string` and `string-to-keyword` deflation
and inflation functions and set those automatically if a slot has a :choices alist?

### Common Lisp <-> HTML data mismatch fix idea
One way I've considered fixing the mismatch between common lisp and HTML is by modifying the `almighty-html` code:

```lisp
(defgeneric render-almighty-object (standard-object)
  (:documentation "Render an object defined via defclass."))

(defmethod render-children ((element tag))
  (mapcar (lambda (child)
            (cond ((stringp child) (escape-html-text-content child))
                  ((typep child 'standard-object) (render-almighty-object child))
                  (t child))
            (if (stringp child)
                (escape-html-text-content child)
                child))
          (element-children element)))
```

Then any object that is an instance of some class defined by `defclass` can have
a `render-almighty-object` method specialized on it. A developer that wants to
nicely render some data without explicitly calling a function to format it every
time he returns it as a child in an `almighty-html` template could
define a `render-almighty-object` once and let `almighty-html` handle the
rendering. This could be used, for example, for creating an HTML-compatible rendered
value for use in form input fields, etc.

## Critique and Improve

Please critique my ideas and offer any suggestions for improvement. Remember
that we want to keep things simple and direct and use Common Lisp idiomatic
style, but if we need some extra layers of abstraction to get powerful
extensibility then let's do that.
