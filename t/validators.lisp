(defpackage #:shiso/t/validators
  (:use #:cl #:lisp-unit2))

(in-package #:shiso/t/validators)

(define-test not-blank-rejects-nil ()
  (assert-true (stringp (shiso/validators:not-blank nil))
               "nil should be rejected"))

(define-test not-blank-rejects-empty-string ()
  (assert-true (stringp (shiso/validators:not-blank ""))
               "Empty string should be rejected"))

(define-test not-blank-accepts-non-empty ()
  (assert-false (shiso/validators:not-blank "hello")
                "Non-empty string should pass"))

(define-test max-length-rejects-long-string ()
  (let ((v (shiso/validators:max-length 5)))
    (assert-true (stringp (funcall v "toolong"))
                 "String exceeding max should be rejected")))

(define-test max-length-accepts-short-string ()
  (let ((v (shiso/validators:max-length 5)))
    (assert-false (funcall v "ok")
                  "Short string should pass")))

(define-test max-length-accepts-exact-length ()
  (let ((v (shiso/validators:max-length 5)))
    (assert-false (funcall v "exact")
                  "String at exact limit should pass")))

(define-test min-length-rejects-short-string ()
  (let ((v (shiso/validators:min-length 3)))
    (assert-true (stringp (funcall v "ab"))
                 "Too-short string should be rejected")))

(define-test min-length-accepts-long-enough ()
  (let ((v (shiso/validators:min-length 3)))
    (assert-false (funcall v "abc")
                  "String at minimum should pass")))

(define-test min-value-rejects-too-small ()
  (let ((v (shiso/validators:min-value 10)))
    (assert-true (stringp (funcall v 5))
                 "Value below minimum should be rejected")))

(define-test min-value-accepts-at-minimum ()
  (let ((v (shiso/validators:min-value 10)))
    (assert-false (funcall v 10)
                  "Value at minimum should pass")))

(define-test max-value-rejects-too-large ()
  (let ((v (shiso/validators:max-value 100)))
    (assert-true (stringp (funcall v 101))
                 "Value above maximum should be rejected")))

(define-test max-value-accepts-at-maximum ()
  (let ((v (shiso/validators:max-value 100)))
    (assert-false (funcall v 100)
                  "Value at maximum should pass")))

(define-test valid-email-rejects-no-at ()
  (assert-true (stringp (shiso/validators:valid-email "notanemail"))
               "String without @ should be rejected"))

(define-test valid-email-accepts-valid ()
  (assert-false (shiso/validators:valid-email "user@example.com")
                "Valid email should pass"))

(define-test one-of-rejects-unknown ()
  (let ((v (shiso/validators:one-of '(:draft :published))))
    (assert-true (stringp (funcall v :archived))
                 "Value not in choices should be rejected")))

(define-test one-of-accepts-known ()
  (let ((v (shiso/validators:one-of '(:draft :published))))
    (assert-false (funcall v :draft)
                  "Value in choices should pass")))

(define-test matches-pattern-rejects-no-match ()
  (let ((v (shiso/validators:matches-pattern "^\\d+$")))
    (assert-true (stringp (funcall v "abc"))
                 "Non-matching string should be rejected")))

(define-test matches-pattern-accepts-match ()
  (let ((v (shiso/validators:matches-pattern "^\\d+$")))
    (assert-false (funcall v "123")
                  "Matching string should pass")))

(define-test resolve-validator-resolves-symbol ()
  (let ((fn (shiso/validators:resolve-validator 'shiso/validators:not-blank)))
    (assert-true (functionp fn)
                 "Symbol should resolve to a function")))

(define-test resolve-validator-resolves-factory-list ()
  (let ((fn (shiso/validators:resolve-validator '(shiso/validators:max-length 10))))
    (assert-true (functionp fn)
                 "Factory list should resolve to a function")
    (assert-false (funcall fn "short")
                  "Resolved validator should work")))

(define-test resolve-validator-passes-through-function ()
  (let* ((orig (lambda (v) (declare (ignore v)) nil))
         (fn (shiso/validators:resolve-validator orig)))
    (assert-true (eq orig fn)
                 "Function should pass through unchanged")))

(define-test run-validators-returns-empty-on-valid ()
  (let ((errors (shiso/validators:run-validators
                 '(shiso/validators:not-blank)
                 "hello")))
    (assert-false errors "No errors expected for valid input")))

(define-test run-validators-collects-all-errors ()
  (let ((errors (shiso/validators:run-validators
                 (list 'shiso/validators:not-blank
                       (list 'shiso/validators:min-length 10))
                 "")))
    (assert-eql 2 (length errors)
                "Both validators should fail on empty string")))
