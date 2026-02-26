(defpackage #:<% @var project-name %>/modules/<% @var module-name %>)
(in-package )

(defun index ()
  (s:http-response "Welcome to <% @var name %>"))
