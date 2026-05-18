(defpackage #:shiso/cli/render
  (:use #:cl)
  (:export #:render-template))
(in-package #:shiso/cli/render)

(defun substitute-bindings (string bindings)
  "Replace every <% @var KEY %> (cl-emb @var directive, whitespace-tolerant)
in STRING with the corresponding value from BINDINGS, an alist of
(key . value) strings."
  (let ((result string))
    (dolist (binding bindings result)
      (let ((pattern (concatenate 'string
                                  "<%\\s*@var\\s+"
                                  (cl-ppcre:quote-meta-chars (car binding))
                                  "\\s*%>")))
        (setf result (cl-ppcre:regex-replace-all pattern result (cdr binding)))))))

(defun render-one-file (source-file source-dir target-dir bindings)
  (let* ((relative (namestring (uiop:enough-pathname source-file source-dir)))
         (substituted (substitute-bindings relative bindings))
         (target-file (merge-pathnames substituted target-dir))
         (content (uiop:read-file-string source-file)))
    (ensure-directories-exist target-file)
    (with-open-file (out target-file
                         :direction :output
                         :if-does-not-exist :create
                         :if-exists :supersede)
      (write-string (substitute-bindings content bindings) out))))

(defun render-template (source-dir target-dir bindings)
  "Stamp SOURCE-DIR (a template tree) into TARGET-DIR, substituting
<% @var key %> placeholders in both file paths and file contents.

BINDINGS is an alist of (key . value) strings; values are inserted literally.

Errors if TARGET-DIR already exists and is non-empty."
  (let ((source-dir (uiop:ensure-directory-pathname source-dir))
        (target-dir (uiop:ensure-directory-pathname target-dir)))
    (unless (uiop:directory-exists-p source-dir)
      (error "Template source directory does not exist: ~A" source-dir))
    (when (and (uiop:directory-exists-p target-dir)
               (or (uiop:directory-files target-dir)
                   (uiop:subdirectories target-dir)))
      (error "Target directory already exists and is non-empty: ~A" target-dir))
    (uiop:collect-sub*directories
     source-dir t t
     (lambda (subdir)
       (dolist (file (uiop:directory-files subdir))
         (render-one-file file source-dir target-dir bindings))))))
