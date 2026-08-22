(defpackage #:shiso/t/i18n
  (:use #:cl #:lisp-unit2)
  (:local-nicknames (#:i18n #:shiso/i18n)))

(in-package #:shiso/t/i18n)

(defmacro with-fresh-i18n (&body body)
  `(let ((i18n::*fluent* nil)
         (i18n:*locale* :en-us)
         (i18n:*default-locale* :en-us)
         (i18n:*fallback-locale* :en-us))
     ,@body))

(defun write-ftl (root locale filename contents)
  (let ((dir (merge-pathnames (format nil "~A/" locale) root)))
    (ensure-directories-exist dir)
    (with-open-file (out (merge-pathnames filename dir)
                         :direction :output
                         :if-exists :supersede
                         :if-does-not-exist :create)
      (write-string contents out))))

(defmacro with-temp-locale-root ((root-var) &body body)
  `(let ((,root-var (merge-pathnames
                     (format nil "shiso-i18n-~A/" (random 1000000000))
                     (uiop:temporary-directory))))
     (unwind-protect
          (progn
            (ensure-directories-exist ,root-var)
            ,@body)
       (when (uiop:directory-exists-p ,root-var)
         (uiop:delete-directory-tree ,root-var :validate t)))))

;;; ----------------------------------------------------------------------
;;; Locale helpers

(define-test canonicalize-locale-accepts-hyphen-and-underscore ()
  (assert-eq :en-us (i18n:canonicalize-locale "en-US"))
  (assert-eq :en-us (i18n:canonicalize-locale "en_us"))
  (assert-eq :ja-jp (i18n:canonicalize-locale :ja-jp)))

(define-test locale-lang-strips-region ()
  (assert-eq :ja (i18n:locale-lang :ja-jp))
  (assert-eq :en (i18n:locale-lang :en))
  (assert-equal "ja" (i18n:locale-html-lang :ja-jp)))

(define-test message-id-from-model-and-field ()
  (assert-equal "question-question-text"
                (i18n:message-id 'question 'question-text))
  (assert-equal "question-question-text-help"
                (i18n:message-id 'question 'question-text "help")))

(define-test fluent-id-p ()
  (assert-true (i18n:fluent-id-p "auth-email"))
  (assert-false (i18n:fluent-id-p "Question text"))
  (assert-false (i18n:fluent-id-p "1abc")))

(define-test with-locale-does-not-leak ()
  (let ((i18n:*locale* :en-us))
    (i18n:with-locale :ja-jp
      (assert-eq :ja-jp (i18n:current-locale)))
    (assert-eq :en-us (i18n:current-locale))))

;;; ----------------------------------------------------------------------
;;; Catalog lookup

(define-test translate-uses-catalog-and-args ()
  (with-fresh-i18n
    (with-temp-locale-root (root)
      (write-ftl root "en-US" "app.ftl"
                 "hello = Hello { $name }
items = { $count ->
    [one] { $count } item
   *[other] { $count } items
}
")
      (write-ftl root "ja-JP" "app.ftl"
                 "hello = こんにちは { $name }
")
      (i18n:load-localisations :root root
                               :default-locale :en-us
                               :fallback-locale :en-us)
      (i18n:with-locale :en-us
        (assert-equal "Hello world"
                      (i18n:translate "hello" :name "world"))
        (assert-equal "1 item"
                      (i18n:translate "items" :count 1))
        (assert-equal "3 items"
                      (i18n:translate "items" :count 3)))
      (i18n:with-locale :ja-jp
        (assert-equal "こんにちは world"
                      (i18n:translate "hello" :name "world"))))))

(define-test translate-falls-back-then-default ()
  (with-fresh-i18n
    (with-temp-locale-root (root)
      (write-ftl root "en-US" "app.ftl" "only-en = English only
")
      (write-ftl root "ja-JP" "app.ftl" "hello = こんにちは
")
      (i18n:load-localisations :root root
                               :default-locale :en-us
                               :fallback-locale :en-us)
      (i18n:with-locale :ja-jp
        (assert-equal "English only" (i18n:translate "only-en"))
        (assert-equal "missing-default"
                      (i18n:translate "no-such-key"
                                      :default "missing-default"))
        (assert-equal "no-such-key"
                      (i18n:translate "no-such-key"))))))

(define-test translate-without-catalog-returns-default ()
  (with-fresh-i18n
    (assert-equal "fallback-text"
                  (i18n:translate "definitely-missing-xyz"
                                  :default "fallback-text"))))

;;; ----------------------------------------------------------------------
;;; Accept-Language / cookie

(define-test parse-accept-language-orders-by-q ()
  (let ((parsed (i18n:parse-accept-language
                 "ja-JP,ja;q=0.9,en-US;q=0.8,en;q=0.7")))
    (assert-eq :ja-jp (car (first parsed)))
    (assert-eq :en-us (car (third parsed)))))

(define-test best-locale-prefers-cookie-then-header ()
  (with-fresh-i18n
    (with-temp-locale-root (root)
      (write-ftl root "en-US" "app.ftl" "x = x
")
      (write-ftl root "ja-JP" "app.ftl" "x = x
")
      (i18n:load-localisations :root root
                               :default-locale :en-us
                               :fallback-locale :en-us)
      (let ((headers (make-hash-table :test #'equal)))
        (setf (gethash "cookie" headers) "shiso_language=ja-jp")
        (setf (gethash "accept-language" headers) "en-US")
        (assert-eq :ja-jp
                   (i18n:best-locale (list :headers headers))))
      (let ((headers (make-hash-table :test #'equal)))
        (setf (gethash "accept-language" headers) "ja-JP,en;q=0.8")
        (assert-eq :ja-jp
                   (i18n:best-locale (list :headers headers))))
      (assert-eq :en-us
                 (i18n:best-locale (list :headers (make-hash-table :test #'equal)))))))

(define-test wrap-locale-binds-request-locale ()
  (with-fresh-i18n
    (with-temp-locale-root (root)
      (write-ftl root "en-US" "app.ftl" "x = x
")
      (write-ftl root "ja-JP" "app.ftl" "x = x
")
      (i18n:load-localisations :root root
                               :default-locale :en-us
                               :fallback-locale :en-us)
      (let* ((headers (make-hash-table :test #'equal))
             (seen nil)
             (app (lambda (env)
                    (declare (ignore env))
                    (setf seen i18n:*locale*)
                    '(200 () ("ok"))))
             (mw (i18n:wrap-locale app)))
        (setf (gethash "cookie" headers) "shiso_language=ja-jp")
        (funcall mw (list :headers headers :request-method :get :path-info "/"))
        (assert-eq :ja-jp seen)))))

(define-test validator-message-follows-locale ()
  (with-fresh-i18n
    (with-temp-locale-root (root)
      (write-ftl root "en-US" "app.ftl"
                 "validators-not-blank = This field is required.
")
      (write-ftl root "ja-JP" "app.ftl"
                 "validators-not-blank = このフィールドは必須です。
")
      (i18n:load-localisations :root root
                               :default-locale :en-us
                               :fallback-locale :en-us)
      (i18n:with-locale :en-us
        (assert-equal "This field is required."
                      (shiso/validators:not-blank nil)))
      (i18n:with-locale :ja-jp
        (assert-equal "このフィールドは必須です。"
                      (shiso/validators:not-blank nil))))))
