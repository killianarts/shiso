(defpackage #:todos/routes
  (:use #:cl)
  (:local-nicknames (#:s #:shiso)
                    (#:controllers #:todos/controllers)))

(in-package #:todos/routes)

(s:define-module todos
  (:urls (:GET  "/"            'controllers:index  "index")
         (:POST "/"            'controllers:create "create")
         (:POST "/:id/toggle"  'controllers:toggle "toggle")
         (:POST "/:id/delete"  'controllers:destroy "delete")))
