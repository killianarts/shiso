(defpackage #:shiso/t/static
  (:use #:cl #:lisp-unit2))

(in-package #:shiso/t/static)

(defun write-text (path text)
  (ensure-directories-exist path)
  (with-open-file (out path :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
    (write-string text out)))

(defmacro with-temp-dir ((var) &body body)
  `(let* ((,var (uiop:ensure-directory-pathname
                 (merge-pathnames
                  (format nil "shiso-static-test-~A/" (get-universal-time))
                  (uiop:temporary-directory)))))
     (ensure-directories-exist ,var)
     (unwind-protect (progn ,@body)
       (uiop:delete-directory-tree ,var :validate t :if-does-not-exist :ignore))))

(defmacro with-clean-static-state (&body body)
  "Isolate manifest specials and the module registry."
  (let ((saved-manifest (gensym))
        (saved-path (gensym))
        (saved-warned (gensym))
        (saved-modules (gensym)))
    `(let ((,saved-manifest shiso/static::*static-manifest*)
           (,saved-path shiso/static::*static-manifest-path*)
           (,saved-warned shiso/static::*cached-static-warned*)
           (,saved-modules (alexandria:copy-hash-table shiso:*module-registry*)))
       (setf shiso/static::*static-manifest* :absent
             shiso/static::*static-manifest-path* nil
             shiso/static::*cached-static-warned* (make-hash-table :test #'equal))
       (clrhash shiso:*module-registry*)
       (unwind-protect (progn ,@body)
         (setf shiso/static::*static-manifest* ,saved-manifest
               shiso/static::*static-manifest-path* ,saved-path
               shiso/static::*cached-static-warned* ,saved-warned
               shiso:*module-registry* ,saved-modules)))))

(defun register-test-module (name static-root)
  (let ((mod (make-instance 'shiso:module
                            :routes (make-instance 'shiso:routes
                                                   :mapper (myway:make-mapper))
                            :static-root (namestring
                                          (uiop:ensure-directory-pathname static-root)))))
    (shiso:register-module name mod)
    mod))

(define-test hashed-filename-inserts-before-last-extension ()
  (assert-equal "bar.a3f19c2b4d5e.css"
                (shiso/static::hashed-filename "bar.css" "a3f19c2b4d5e"))
  (assert-equal "foo.min.deadbeef0123.js"
                (shiso/static::hashed-filename "foo.min.js" "deadbeef0123"))
  (assert-equal "README.aabbccddeeff"
                (shiso/static::hashed-filename "README" "aabbccddeeff")))

(define-test strip-content-hash-roundtrip ()
  (assert-equal "home/bar.css"
                (shiso/static::strip-content-hash "home/bar.a3f19c2b4d5e.css"))
  (assert-equal "x/foo.min.js"
                (shiso/static::strip-content-hash "x/foo.min.deadbeef0123.js"))
  (assert-false (shiso/static::strip-content-hash "home/bar.css"))
  (assert-false (shiso/static::strip-content-hash "home/bar.notahex.css"))
  ;; Too short / too long hex segment
  (assert-false (shiso/static::strip-content-hash "home/bar.abc.css"))
  (assert-false (shiso/static::strip-content-hash
                 "home/bar.0123456789abcdef.css")))

(define-test file-content-hash-is-stable ()
  (with-temp-dir (dir)
    (let ((f (merge-pathnames "x.css" dir)))
      (write-text f "body{color:red}")
      (let ((h1 (shiso/static::file-content-hash f))
            (h2 (shiso/static::file-content-hash f)))
        (assert-equal h1 h2)
        (assert-equal 12 (length h1))
        (assert-true (every (lambda (c)
                              (or (char<= #\0 c #\9)
                                  (char<= #\a c #\f)))
                            h1))))))

(define-test manifest-json-roundtrip ()
  (let ((table (make-hash-table :test #'equal)))
    (setf (gethash "home/bar.css" table) "home/bar.aabbccddeeff.css"
          (gethash "a/b.js" table) "a/b.0123456789ab.js")
    (let* ((json (shiso/static::encode-manifest-json table))
           (back (shiso/static::decode-manifest-json json)))
      (assert-equal "home/bar.aabbccddeeff.css"
                    (gethash "home/bar.css" back))
      (assert-equal "a/b.0123456789ab.js"
                    (gethash "a/b.js" back))
      (assert-equal 2 (hash-table-count back)))))

(define-test static-unchanged ()
  (assert-equal "/static/home/bar.css"
                (shiso:static "home/bar.css")))

(define-test collectstatic-without-hash-no-manifest ()
  (with-clean-static-state
    (with-temp-dir (dir)
      (let* ((mod-static (merge-pathnames "modstatic/" dir))
             (target (merge-pathnames "out/" dir)))
        (write-text (merge-pathnames "bar.css" mod-static) "a{}")
        (register-test-module :home mod-static)
        (shiso:collectstatic :target target)
        (assert-true (uiop:file-exists-p
                      (merge-pathnames "home/bar.css" target)))
        (assert-false (uiop:file-exists-p
                       (merge-pathnames "staticfiles.json" target)))
        ;; No hashed sibling
        (assert-equal 1
                      (length (uiop:directory-files
                               (merge-pathnames "home/" target))))))))

(define-test collectstatic-with-hash-writes-manifest ()
  (with-clean-static-state
    (with-temp-dir (dir)
      (let* ((mod-static (merge-pathnames "modstatic/" dir))
             (target (merge-pathnames "out/" dir))
             (src (merge-pathnames "bar.css" mod-static)))
        (write-text src "body{color:blue}")
        (write-text (merge-pathnames "img/logo.png" mod-static) "PNGDATA")
        (register-test-module :home mod-static)
        (shiso:collectstatic :target target :hash t)
        (let* ((hash (shiso/static::file-content-hash src))
               (hashed-name (shiso/static::hashed-filename "bar.css" hash))
               (hashed-path (merge-pathnames
                             (concatenate 'string "home/" hashed-name)
                             target))
               (manifest-path (merge-pathnames "staticfiles.json" target)))
          (assert-true (uiop:file-exists-p
                        (merge-pathnames "home/bar.css" target)))
          (assert-true (uiop:file-exists-p hashed-path))
          (assert-true (uiop:file-exists-p
                        (merge-pathnames "home/img/logo.png" target)))
          (assert-true (uiop:file-exists-p manifest-path))
          (let ((m (shiso/static::decode-manifest-json
                    (uiop:read-file-string manifest-path))))
            (assert-equal (concatenate 'string "home/" hashed-name)
                          (gethash "home/bar.css" m))
            (assert-true (gethash "home/img/logo.png" m))))))))

(define-test collectstatic-hash-changes-with-content ()
  (with-clean-static-state
    (with-temp-dir (dir)
      (let* ((mod-static (merge-pathnames "modstatic/" dir))
             (target (merge-pathnames "out/" dir))
             (src (merge-pathnames "bar.css" mod-static)))
        (write-text src "v1")
        (register-test-module :home mod-static)
        (shiso:collectstatic :target target :hash t)
        (let ((h1 (gethash "home/bar.css" shiso/static::*static-manifest*)))
          (write-text src "v2-changed")
          (shiso:collectstatic :target target :hash t)
          (let ((h2 (gethash "home/bar.css" shiso/static::*static-manifest*)))
            (assert-false (equal h1 h2))
            ;; Old hashed file still present (no prune)
            (assert-true (uiop:file-exists-p
                          (merge-pathnames h1 target)))
            (assert-true (uiop:file-exists-p
                          (merge-pathnames h2 target)))))))))

(define-test cached-static-with-manifest ()
  (with-clean-static-state
    (let ((table (make-hash-table :test #'equal)))
      (setf (gethash "home/bar.css" table) "home/bar.aabbccddeeff.css")
      (setf shiso/static::*static-manifest* table)
      (assert-equal "/static/home/bar.aabbccddeeff.css"
                    (shiso:cached-static "home/bar.css")))))

(define-test cached-static-unknown-path-falls-back ()
  (with-clean-static-state
    (let ((table (make-hash-table :test #'equal)))
      (setf shiso/static::*static-manifest* table)
      (handler-bind ((warning #'muffle-warning))
        (assert-equal "/static/missing/x.css"
                      (shiso:cached-static "missing/x.css"))))))

(define-test cached-static-dev-mtime-query ()
  (with-clean-static-state
    (with-temp-dir (dir)
      (let* ((mod-static (merge-pathnames "modstatic/" dir))
             (src (merge-pathnames "bar.css" mod-static)))
        (write-text src "body{}")
        (register-test-module :home mod-static)
        ;; Point project root lookup away from cwd static/ by using module roots only;
        ;; locate-static-file still searches default project static first — ensure
        ;; module registration is enough (path home/bar.css → module home).
        (let ((url (shiso:cached-static "home/bar.css")))
          (assert-true (search "/static/home/bar.css?v=" url)
                       url)
          (let ((mtime1 (parse-integer (subseq url (+ (search "?v=" url) 3)))))
            (sleep 1.1)
            (write-text src "body{color:red}")
            ;; Bump mtime: rewrite is enough on most FS after sleep.
            (let ((url2 (shiso:cached-static "home/bar.css")))
              (let ((mtime2 (parse-integer
                             (subseq url2 (+ (search "?v=" url2) 3)))))
                (assert-true (>= mtime2 mtime1))))))))))

(define-test locate-static-file-strips-hash ()
  (with-clean-static-state
    (with-temp-dir (dir)
      (let* ((project (merge-pathnames "static/" dir))
             (file (merge-pathnames "home/bar.css" project)))
        (write-text file "css")
        (let ((found (shiso/static::locate-static-file
                      "home/bar.a3f19c2b4d5e.css"
                      :project-root project
                      :module-roots nil)))
          (assert-true found)
          (assert-true (uiop:file-exists-p found))
          (assert-equal "bar.css" (file-namestring found)))))))
