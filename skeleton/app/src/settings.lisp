(defpackage #:<% @var application-name %>/settings
  (:use #:cl))

(in-package #:<% @var application-name %>/settings)

;;;; The project's settings: Shiso's and every module's, in one place.
;;;;
;;;; What differs between machines goes in the environment, and in
;;;; development in the .env file; secrets always do. `<% @var application-name %> settings`
;;;; lists every setting, its value and where the value came from.

(defun database-path (configuration)
  "The SQLite file, under the user's data directory:
$XDG_DATA_HOME/<% @var application-name %>/<% @var application-name %>.db, or
~/.local/share/<% @var application-name %>/<% @var application-name %>.db. Worked out when the settings are
loaded, on the machine the program runs on."
  (declare (ignore configuration))
  (let* ((xdg (uiop:getenv "XDG_DATA_HOME"))
         (base (if (and xdg (plusp (length xdg)))
                   (uiop:ensure-directory-pathname xdg)
                   (merge-pathnames ".local/share/" (user-homedir-pathname)))))
    (namestring (merge-pathnames "<% @var application-name %>/<% @var application-name %>.db" base))))

(shiso:configure
  (:database :name #'database-path))
