(defsystem "mysite"
  :description "mysite — the Django-poll-style Shiso tutorial app"
  :version "0.1"
  :depends-on (:shiso
               :polls)
  :build-operation "program-op"
  :build-pathname "mysite"
  :entry-point "mysite:main"
  :components ((:module "src"
                :serial t
                :components ((:file "package")
                             (:file "routes")
                             (:file "main"))))
  :in-order-to ((test-op (test-op "mysite/tests"))))

(defsystem "mysite/tests"
  :depends-on (:mysite :lisp-unit2 :alexandria)
  :components ((:module "t"
                :serial t
                :components ((:file "polls-models")
                             (:file "polls-routes"))))
  :perform (test-op (o s)
                    (uiop:symbol-call :lisp-unit2 :run-tests
                                      :package :mysite/t/polls-models)
                    (uiop:symbol-call :lisp-unit2 :run-tests
                                      :package :mysite/t/polls-routes)))
