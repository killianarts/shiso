(defpackage #:todos/routes
  (:use #:cl)
  (:local-nicknames (#:s #:shiso)
                    (#:controllers #:todos/controllers)))

(in-package #:todos/routes)

(s:define-module todos
  (:urls (:GET  "/"            'controllers:index  "index")
         (:POST "/"            'controllers:create "create")
         (:GET  "/:id/edit"    'controllers:edit   "edit")
         (:POST "/:id/edit"    'controllers:update "update")
         (:POST "/:id/toggle"  'controllers:toggle "toggle")
         (:POST "/:id/delete"  'controllers:destroy "delete")))
