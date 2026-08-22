(in-package #:shiso/i18n)

(defvar *fluent* nil
  "Process-wide Fluent context holding every loaded locale. Lookups pass
the request locale into RESOLVE-WITH; this struct's own locale slot is
not mutated per request.")

(defun shiso-locale-root ()
  "Shiso's own locale/ directory, if it exists."
  (let ((p (asdf:system-relative-pathname :shiso "locale/")))
    (when (uiop:directory-exists-p p)
      p)))

(defun module-locale-roots ()
  "Locale directories recorded on registered modules."
  (loop :for module :being :the :hash-values :of modules:*module-registry*
        :for root := (modules:module-locale-root module)
        :when (and root (uiop:directory-exists-p root))
          :collect root))

(defun merge-localisation-tables (base overlay)
  "Copy OVERLAY into BASE. On clashing locale+id, OVERLAY wins.
Returns BASE. Uses Fluent's fuse (overlay is the second table)."
  (maphash
   (lambda (locale loc)
     (let ((existing (gethash locale base)))
       (setf (gethash locale base)
             (if existing
                 (fluent::fuse-localisations existing loc)
                 loc))))
   overlay)
  base)

(defun read-locale-tree (root)
  "Read all per-locale .ftl files under ROOT. Empty/missing dirs yield
an empty hash table."
  (if (and root (uiop:directory-exists-p root))
      (fluent:read-all-localisations root)
      (make-hash-table :test #'eq)))

(defun env-locale (var)
  (let ((raw (uiop:getenv var)))
    (when (and raw (plusp (length raw)))
      (canonicalize-locale raw))))

(defun load-localisations (&key root
                               (default-locale nil)
                               (fallback-locale nil))
  "Load and merge locale trees into *FLUENT*.

ROOT is an optional application overlay (a pathname, or a list of
pathnames). Merge order, later wins on clashing ids:

  1. Shiso's own locale/
  2. Each registered module's locale/
  3. ROOT

DEFAULT-LOCALE and FALLBACK-LOCALE default to the current specials,
then SHISO_LOCALE / SHISO_FALLBACK_LOCALE env vars, then :EN-US.

Idempotent: replaces *FLUENT*. Safe to call from the REPL after
editing .ftl files."
  (let* ((default (or default-locale
                      (env-locale "SHISO_LOCALE")
                      *default-locale*
                      :en-us))
         (fallback (or fallback-locale
                       (env-locale "SHISO_FALLBACK_LOCALE")
                       *fallback-locale*
                       default))
         (roots (append (let ((s (shiso-locale-root)))
                          (when s (list s)))
                        (module-locale-roots)
                        (cond ((null root) nil)
                              ((listp root) root)
                              (t (list root)))))
         (locs (make-hash-table :test #'eq)))
    (dolist (r roots)
      (merge-localisation-tables locs (read-locale-tree r)))
    (setf *default-locale* (canonicalize-locale default)
          *fallback-locale* (canonicalize-locale fallback)
          *locale* *default-locale*
          *fluent* (fluent:fluent locs
                                  :locale *default-locale*
                                  :fallback *fallback-locale*))
    *fluent*))

(defun ensure-localisations ()
  "Load catalogs if they have not been loaded yet."
  (unless *fluent*
    (load-localisations))
  *fluent*)

(defun available-locales ()
  "Locales present in the loaded catalog, plus the default locale."
  (let ((seen (make-hash-table :test #'eq)))
    (setf (gethash (canonicalize-locale *default-locale*) seen) t)
    (when *fluent*
      (maphash (lambda (k v)
                 (declare (ignore v))
                 (setf (gethash k seen) t))
               (fluent:fluent-locs *fluent*)))
    (loop :for k :being :the :hash-keys :of seen :collect k)))
