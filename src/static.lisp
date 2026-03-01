(defpackage #:shiso/static
  (:use #:cl)
  (:import-from #:lack/app/file
                #:lack-app-file
                #:should-handle
                #:serve-path)
  (:export
   #:collectstatic
   #:make-static-middleware
   #:module-static-roots))

(in-package #:shiso/static)

(defun module-static-roots ()
  "Build an alist of (module-name . static-root-path) from registered modules.
Each module's static/ dir is served under /static/<module-name>/."
  (let (roots)
    (maphash
     (lambda (name module)
       (let ((src (shiso/modules:module-static-root module)))
         (when src
           (push (cons (string-downcase (string name))
                       (pathname src))
                 roots))))
     shiso/modules:*module-registry*)
    roots))

(defun locate-in-roots (relative-path project-root module-roots)
  "Search for RELATIVE-PATH in PROJECT-ROOT first, then in module roots.
For module roots, if RELATIVE-PATH starts with a module name, strip it
and look in that module's static dir.
Returns the resolved pathname or NIL."
  ;; 1. Try project-wide static/ directory first
  (let ((project-file (merge-pathnames relative-path project-root)))
    (when (and (uiop:file-exists-p project-file)
               (not (uiop:directory-pathname-p project-file)))
      (return-from locate-in-roots project-file)))
  ;; 2. Try module roots: relative-path = "<module-name>/rest/of/path"
  (let ((slash-pos (position #\/ relative-path)))
    (when slash-pos
      (let* ((prefix (subseq relative-path 0 slash-pos))
             (rest (subseq relative-path (1+ slash-pos)))
             (entry (assoc prefix module-roots :test #'string=)))
        (when entry
          (let ((file (merge-pathnames rest (cdr entry))))
            (when (and (uiop:file-exists-p file)
                       (not (uiop:directory-pathname-p file)))
              file)))))))

(defun make-static-middleware (app &key (path "/static/") project-root module-roots)
  "Lack middleware that searches multiple roots for static files.
PROJECT-ROOT is the project-wide static/ directory.
MODULE-ROOTS is an alist of (module-name . pathname) from module-static-roots.

Request flow for /static/books/cover.png:
  1. Strip /static/ prefix → 'books/cover.png'
  2. Check project-root/books/cover.png (handles collectstatic case)
  3. Check module 'books' static dir for cover.png (handles dev case)
  4. Not found → pass to inner app"
  (let ((prefix-len (length path)))
    (lambda (env)
      (let ((request-path (getf env :path-info)))
        (if (and (>= (length request-path) prefix-len)
                 (string= path request-path :end2 prefix-len))
            (let* ((relative (subseq request-path prefix-len))
                   (file (locate-in-roots relative project-root module-roots)))
              (if file
                  ;; Use Lack's file serving with proper MIME types + caching
                  (let ((file-app (make-instance 'lack-app-file
                                                 :file file
                                                 :root (uiop:pathname-directory-pathname file))))
                    (serve-path file-app env file "utf-8"))
                  (funcall app env)))
            (funcall app env))))))

(defun collectstatic (&key (target (merge-pathnames "static/" (uiop:getcwd))))
  "Copy each registered module's static/ directory into TARGET/<module-name>/.
After running this, the project-wide static/ directory contains everything
and no module-root fallback is needed (production mode)."
  (maphash
   (lambda (name module)
     (let ((src (shiso/modules:module-static-root module)))
       (when src
         (let* ((mod-name (string-downcase (string name)))
                (src-path (pathname src))
                (dest (merge-pathnames
                       (make-pathname :directory `(:relative ,mod-name))
                       target)))
           (ensure-directories-exist dest)
           (dolist (file (uiop:directory-files src-path))
             (let ((target-file (merge-pathnames (file-namestring file) dest)))
               (uiop:copy-file file target-file)))
           ;; Also copy subdirectories recursively
           (uiop:collect-sub*directories
            src-path t t
            (lambda (subdir)
              (unless (equal subdir src-path)
                (let* ((rel (uiop:enough-pathname subdir src-path))
                       (target-subdir (merge-pathnames rel dest)))
                  (ensure-directories-exist target-subdir)
                  (dolist (file (uiop:directory-files subdir))
                    (let ((tf (merge-pathnames (file-namestring file) target-subdir)))
                      (uiop:copy-file file tf)))))))
           (format t "~A → ~A~%" mod-name dest)))))
   shiso/modules:*module-registry*)
  (format t "Done.~%"))
