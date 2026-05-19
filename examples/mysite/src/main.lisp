(in-package #:mysite)

(defun setup-database ()
  (ensure-directories-exist #P"db/")
  (mito:connect-toplevel :sqlite3 :database-name "db/mysite.db")
  (shiso/auth:ensure-tables)
  (dolist (name (shiso/models:all-models))
    (mito:ensure-table-exists (shiso/models:model-class name))))

(defun start (&key (host "127.0.0.1") (port 5000))
  (setup-database)
  (shiso:start mysite/routes:application :host host :port port))

(defun stop ()
  (shiso:stop))

(defun main ()
  (start)
  (loop (sleep 60)))
