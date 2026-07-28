(defpackage #:shiso/static
  (:use #:cl)
  (:import-from #:lack/app/file
                #:lack-app-file
                #:should-handle
                #:serve-path)
  (:export
   #:collectstatic
   #:make-static-middleware
   #:module-static-roots
   #:cached-static
   #:reload-manifest))

(in-package #:shiso/static)

;;; Content hashing ------------------------------------------------------------

(defparameter *hash-length* 12
  "Number of hex characters taken from the SHA-256 digest for fingerprinted names.")

(defun file-content-hash (pathname)
  "Return the first *HASH-LENGTH* hex characters of the SHA-256 of PATHNAME."
  (let* ((digest (ironclad:digest-file :sha256 pathname))
         (hex (ironclad:byte-array-to-hex-string digest)))
    (subseq hex 0 *hash-length*)))

(defun hashed-filename (filename hash)
  "Insert HASH before the last extension of FILENAME.
   \"bar.css\" + \"a3f19c2b4d5e\" → \"bar.a3f19c2b4d5e.css\"
   \"foo.min.js\" → \"foo.min.<hash>.js\"
   \"README\" → \"README.<hash>\""
  (let ((dot (position #\. filename :from-end t)))
    (if dot
        (format nil "~A.~A.~A"
                (subseq filename 0 dot)
                hash
                (subseq filename (1+ dot)))
        (format nil "~A.~A" filename hash))))

(defun strip-content-hash (relative-path)
  "If RELATIVE-PATH basename looks like stem.<8-12 hex>.ext, return the path
with the hex segment removed. Otherwise return NIL.
   \"home/bar.a3f19c2b4d5e.css\" → \"home/bar.css\""
  (let* ((slash (position #\/ relative-path :from-end t))
         (dir (if slash (subseq relative-path 0 (1+ slash)) ""))
         (base (if slash (subseq relative-path (1+ slash)) relative-path))
         (dot1 (position #\. base :from-end t)))
    (when dot1
      (let* ((ext (subseq base (1+ dot1)))
             (stem+hash (subseq base 0 dot1))
             (dot2 (position #\. stem+hash :from-end t)))
        (when dot2
          (let ((maybe-hash (subseq stem+hash (1+ dot2)))
                (stem (subseq stem+hash 0 dot2)))
            (when (and (<= 8 (length maybe-hash) 12)
                       (every (lambda (c)
                                (or (char<= #\0 c #\9)
                                    (char<= #\a c #\f)
                                    (char<= #\A c #\F)))
                              maybe-hash)
                       (plusp (length stem))
                       (plusp (length ext)))
              (concatenate 'string dir stem "." ext))))))))

;;; Manifest -------------------------------------------------------------------

(defvar *static-manifest* nil
  "NIL = not yet loaded; :ABSENT = no file / empty; hash-table of logical→hashed.")

(defvar *static-manifest-path* nil
  "Pathname last used (or attempted) for the manifest. NIL means default.")

(defvar *cached-static-warned* (make-hash-table :test #'equal)
  "Logical paths that have already triggered a missing-asset warning.")

(defun default-manifest-path ()
  (merge-pathnames "static/staticfiles.json" (uiop:getcwd)))

(defun encode-manifest-json (table)
  "Encode a string→string hash-table as a flat JSON object."
  (with-output-to-string (out)
    (write-char #\{ out)
    (let ((first t))
      (maphash
       (lambda (k v)
         (unless first (write-char #\, out))
         (setf first nil)
         (format out "~S:~S" k v))
       table))
    (write-char #\} out)))

(defun decode-manifest-json (string)
  "Parse a flat JSON object of string keys/values into a hash-table.
Only the simple shape produced by ENCODE-MANIFEST-JSON is supported."
  (let ((table (make-hash-table :test #'equal))
        (i 0)
        (len (length string)))
    (labels ((skip-ws ()
               (loop while (and (< i len)
                                (member (char string i) '(#\Space #\Tab #\Newline #\Return)))
                     do (incf i)))
             (parse-string ()
               (skip-ws)
               (unless (and (< i len) (char= (char string i) #\"))
                 (error "Expected string in staticfiles.json at position ~D" i))
               (incf i)
               (with-output-to-string (s)
                 (loop
                   (when (>= i len)
                     (error "Unterminated string in staticfiles.json"))
                   (let ((c (char string i)))
                     (cond
                       ((char= c #\")
                        (incf i)
                        (return))
                       ((char= c #\\)
                        (incf i)
                        (when (>= i len)
                          (error "Trailing escape in staticfiles.json"))
                        (write-char (char string i) s)
                        (incf i))
                       (t
                        (write-char c s)
                        (incf i))))))))
      (skip-ws)
      (unless (and (< i len) (char= (char string i) #\{))
        (error "staticfiles.json must start with '{'"))
      (incf i)
      (skip-ws)
      (when (and (< i len) (char= (char string i) #\}))
        (return-from decode-manifest-json table))
      (loop
        (let ((key (parse-string)))
          (skip-ws)
          (unless (and (< i len) (char= (char string i) #\:))
            (error "Expected ':' after key in staticfiles.json"))
          (incf i)
          (let ((val (parse-string)))
            (setf (gethash key table) val)))
        (skip-ws)
        (cond
          ((and (< i len) (char= (char string i) #\,))
           (incf i)
           (skip-ws))
          ((and (< i len) (char= (char string i) #\}))
           (return table))
          (t
           (error "Expected ',' or '}' in staticfiles.json at position ~D" i)))))
    table))

(defun write-manifest (path table)
  "Write TABLE as staticfiles.json to PATH."
  (ensure-directories-exist path)
  (with-open-file (out path :direction :output
                            :if-exists :supersede
                            :if-does-not-exist :create)
    (write-string (encode-manifest-json table) out)
    (terpri out))
  path)

(defun load-manifest (&optional (path (or *static-manifest-path*
                                          (default-manifest-path))))
  "Load staticfiles.json from PATH into *STATIC-MANIFEST*.
Returns the hash-table, or :ABSENT if the file is missing."
  (setf *static-manifest-path* path)
  (if (uiop:file-exists-p path)
      (let* ((text (uiop:read-file-string path))
             (table (decode-manifest-json text)))
        (setf *static-manifest* table))
      (setf *static-manifest* :absent)))

(defun reload-manifest (&optional (path (or *static-manifest-path*
                                            (default-manifest-path))))
  "Force-reload the staticfiles manifest from PATH (or the default).
Intended for REPL use after re-running collectstatic in a live image."
  (setf *static-manifest* nil)
  (load-manifest path))

(defun ensure-manifest ()
  "Lazily load the manifest once. Returns a hash-table or :ABSENT."
  (unless *static-manifest*
    (load-manifest))
  *static-manifest*)

(defun manifest-lookup (logical-path)
  "Return the hashed relative path for LOGICAL-PATH, or NIL."
  (let ((m (ensure-manifest)))
    (when (hash-table-p m)
      (gethash logical-path m))))

(defun warn-missing-static (path reason)
  "Warn once per PATH about a missing/unknown static asset."
  (unless (gethash path *cached-static-warned*)
    (setf (gethash path *cached-static-warned*) t)
    (warn "shiso:cached-static: ~A (~A); falling back to unversioned URL"
          path reason)))

;;; Roots / lookup -------------------------------------------------------------

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

(defun locate-static-file (relative-path &key
                           (project-root (merge-pathnames "static/" (uiop:getcwd)))
                           (module-roots (module-static-roots)))
  "Locate RELATIVE-PATH for URL building (mtime) and middleware.
Tries the exact path, then a content-hash-stripped form."
  (or (locate-in-roots relative-path project-root module-roots)
      (let ((stripped (strip-content-hash relative-path)))
        (when stripped
          (locate-in-roots stripped project-root module-roots)))))

(defun make-static-middleware (app &key (path "/static/") project-root module-roots)
  "Lack middleware that searches multiple roots for static files.
PROJECT-ROOT is the project-wide static/ directory.
MODULE-ROOTS is an alist of (module-name . pathname) from module-static-roots.

Request flow for /static/books/cover.png:
  1. Strip /static/ prefix → 'books/cover.png'
  2. Check project-root/books/cover.png (handles collectstatic case)
  3. Check module 'books' static dir for cover.png (handles dev case)
  4. If path looks hashed (stem.<hex>.ext), strip hash and retry
  5. Not found → pass to inner app"
  (let ((prefix-len (length path)))
    (lambda (env)
      (let ((request-path (getf env :path-info)))
        (if (and (>= (length request-path) prefix-len)
                 (string= path request-path :end2 prefix-len))
            (let* ((relative (subseq request-path prefix-len))
                   (file (locate-static-file relative
                                             :project-root project-root
                                             :module-roots module-roots)))
              (if file
                  ;; Use Lack's file serving with proper MIME types + caching
                  (let ((file-app (make-instance 'lack-app-file
                                                 :file file
                                                 :root (uiop:pathname-directory-pathname file))))
                    (serve-path file-app env file "utf-8"))
                  (funcall app env)))
            (funcall app env))))))

;;; collectstatic --------------------------------------------------------------

(defun copy-one-static-file (src-file dest-file &key hash manifest-table logical-key)
  "Copy SRC-FILE to DEST-FILE. When HASH is true, also write a hashed sibling
and record LOGICAL-KEY → hashed-relative in MANIFEST-TABLE."
  (ensure-directories-exist dest-file)
  (uiop:copy-file src-file dest-file)
  (when hash
    (let* ((digest (file-content-hash src-file))
           (hashed-name (hashed-filename (file-namestring dest-file) digest))
           (hashed-file (merge-pathnames hashed-name
                                         (uiop:pathname-directory-pathname dest-file)))
           ;; logical-key is under target; hashed relative keeps the same directory.
           (slash (position #\/ logical-key :from-end t))
           (prefix (if slash (subseq logical-key 0 (1+ slash)) ""))
           (hashed-rel (concatenate 'string prefix hashed-name)))
      (uiop:copy-file src-file hashed-file)
      (when manifest-table
        (setf (gethash logical-key manifest-table) hashed-rel))
      hashed-rel)))

(defun collect-module-static (src-path dest mod-name &key hash manifest-table)
  "Copy SRC-PATH (a module static root) into DEST, optionally hashing."
  (labels ((rel-key (file base)
             (let* ((rel (namestring (uiop:enough-pathname file base)))
                    (normalized (substitute #\/ #\\ rel)))
               (concatenate 'string mod-name "/" normalized)))
           (process-file (file base dest-dir)
             (let* ((name (file-namestring file))
                    (target-file (merge-pathnames name dest-dir))
                    (key (rel-key file base)))
               (copy-one-static-file file target-file
                                     :hash hash
                                     :manifest-table manifest-table
                                     :logical-key key))))
    (ensure-directories-exist dest)
    (dolist (file (uiop:directory-files src-path))
      (process-file file src-path dest))
    (uiop:collect-sub*directories
     src-path t t
     (lambda (subdir)
       (unless (equal subdir src-path)
         (let* ((rel (uiop:enough-pathname subdir src-path))
                (target-subdir (merge-pathnames rel dest)))
           (ensure-directories-exist target-subdir)
           (dolist (file (uiop:directory-files subdir))
             (process-file file src-path target-subdir))))))))

(defun collectstatic (&key (target (merge-pathnames "static/" (uiop:getcwd)))
                           (hash nil))
  "Copy each registered module's static/ directory into TARGET/<module-name>/.
After running this, the project-wide static/ directory contains everything
and no module-root fallback is needed (production mode).

When :HASH is true, also write content-hashed copies (stem.<hash>.ext)
alongside the unhashed files and emit TARGET/staticfiles.json mapping
logical paths to hashed paths. Old hashed files are left in place
(rolling-deploy safe). Nested CSS url() references are not rewritten."
  (let ((manifest (when hash (make-hash-table :test #'equal))))
    (maphash
     (lambda (name module)
       (let ((src (shiso/modules:module-static-root module)))
         (when src
           (let* ((mod-name (string-downcase (string name)))
                  (src-path (pathname src))
                  (dest (merge-pathnames
                         (make-pathname :directory `(:relative ,mod-name))
                         target)))
             (collect-module-static src-path dest mod-name
                                    :hash hash
                                    :manifest-table manifest)
             (format t "~A → ~A~%" mod-name dest)))))
     shiso/modules:*module-registry*)
    (when hash
      (let ((manifest-path (merge-pathnames "staticfiles.json" target)))
        (write-manifest manifest-path manifest)
        ;; Keep runtime in sync if collectstatic runs in a live image.
        (setf *static-manifest* manifest
              *static-manifest-path* manifest-path)
        (format t "Manifest → ~A (~D entries)~%"
                manifest-path
                (hash-table-count manifest))))
    (format t "Done.~%")
    target))

;;; cached-static --------------------------------------------------------------

(defun plain-static-url (path)
  (concatenate 'string "/static/" path))

(defun cached-static (path)
  "Return a cache-busting URL for static PATH (e.g. \"home/bar.css\").

With a staticfiles.json manifest (production after collectstatic :hash t):
  look up PATH and return \"/static/<hashed>\". Unknown paths fall back to
  the unversioned URL and warn once.

Without a manifest (development):
  return \"/static/<path>?v=<mtime>\" when the file is found under the
  project static/ tree or a module static root. Missing files fall back
  to the unversioned URL and warn once.

Unlike SHISO:STATIC this may touch the filesystem. Prefer STATIC when you
do not need cache busting."
  (let ((manifest (ensure-manifest)))
    (cond
      ((hash-table-p manifest)
       (let ((hashed (gethash path manifest)))
         (if hashed
             (plain-static-url hashed)
             (progn
               (warn-missing-static path "not in staticfiles.json")
               (plain-static-url path)))))
      (t
       ;; No manifest — dev query-string busting via mtime.
       (let ((file (locate-static-file path)))
         (if file
             (let ((mtime (or (ignore-errors (file-write-date file)) 0)))
               (format nil "/static/~A?v=~D" path mtime))
             (progn
               (warn-missing-static path "file not found")
               (plain-static-url path))))))))
