(defpackage #:shiso/admin/routes
  (:use #:cl)
  (:local-nicknames (#:s #:shiso)
                    (#:views #:shiso/admin/views)))

(in-package #:shiso/admin/routes)

(s:define-module shiso-admin
  (:urls
    (:GET          "/"                  'views:dashboard-view "dashboard")
    (:GET          "/:model"            'views:list-view      "list")
    (:GET          "/:model/create"     'views:create-view    "create-form")
    (:POST         "/:model/create"     'views:create-view    "create-submit")
    (:GET          "/:model/:id"        'views:edit-view      "edit-form")
    (:POST         "/:model/:id"        'views:edit-view      "edit-submit")
    (:POST         "/:model/:id/delete" 'views:delete-view    "delete")))
