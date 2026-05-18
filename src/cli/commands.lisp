(defpackage #:shiso/cli/commands
  (:use #:cl)
  (:local-nicknames (#:render #:shiso/cli/render))
  (:export #:new-application
           #:new-module))
(in-package #:shiso/cli/commands)

(defun shiso-home ()
  "Return the directory where Shiso is installed (and where templates live).
Honors $SHISO_HOME if set; otherwise falls back to ~/common-lisp/shiso/."
  (uiop:ensure-directory-pathname
   (or (uiop:getenv "SHISO_HOME")
       (merge-pathnames "common-lisp/shiso/" (user-homedir-pathname)))))

(defun template-dir (kind)
  "Return the source directory for a template KIND (:app or :module)."
  (let ((subpath (ecase kind
                   (:app "skeleton/app/")
                   (:module "skeleton/module/"))))
    (merge-pathnames subpath (shiso-home))))

(defun new-application (name)
  "Scaffold a new Shiso application in ./<name>/."
  (let ((source (template-dir :app))
        (target (merge-pathnames (concatenate 'string name "/")
                                 (uiop:getcwd))))
    (unless (uiop:directory-exists-p source)
      (format *error-output*
              "Cannot find application template at ~A.~%~
               Set SHISO_HOME to a Shiso checkout, or install Shiso with `make install`.~%"
              source)
      (uiop:quit 1))
    (when (uiop:directory-exists-p target)
      (format *error-output* "Refusing to overwrite existing directory: ~A~%" target)
      (uiop:quit 1))
    (render:render-template source target `(("name" . ,name)))
    (format t "Application scaffolded at ~A~%~%" target)
    (format t "Next steps:~%")
    (format t "  cd ~A~%" name)
    (format t "  vend get~%")
    (format t "  make~%")
    (format t "  ./~A~%" name)))

(defun new-module (name)
  "Scaffold a new module under ./src/modules/<name>/ in the current application."
  (let ((source (template-dir :module))
        (target (merge-pathnames (concatenate 'string "src/modules/" name "/")
                                 (uiop:getcwd))))
    (unless (uiop:directory-exists-p source)
      (format *error-output*
              "Cannot find module template at ~A.~%~
               Set SHISO_HOME to a Shiso checkout, or install Shiso with `make install`.~%"
              source)
      (uiop:quit 1))
    (when (uiop:directory-exists-p target)
      (format *error-output* "Refusing to overwrite existing directory: ~A~%" target)
      (uiop:quit 1))
    (ensure-directories-exist target)
    (render:render-template source target `(("name" . ,name)))
    (format t "Module scaffolded at src/modules/~A/.~%~%" name)
    (format t "Add it to your application's .asd by including ~S in :depends-on,~%" name)
    (format t "then mount it in src/routes.lisp:~%~%")
    (format t "  (s:define-application application ()~%")
    (format t "    (:modules~%")
    (format t "     (\"/~A\" ~A)~%" name name)
    (format t "     ...))~%")))
