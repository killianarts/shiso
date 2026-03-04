(defpackage #:shiso/admin/routes
  (:use #:cl)
  (:local-nicknames (#:routing #:shiso/routing)
                    (#:controllers #:shiso/admin/controllers)))

(in-package #:shiso/admin/routes)

(routing:define-module shiso-admin
  (:urls
   (:GET       "/"                  'controllers:index                            "index")
   (:GET       "/:model"            'controllers:model-instance-list              "model-instance-list")
   (:GET       "/:model/build"      'controllers:model-instance-build             "model-instance-build")
   (:POST      "/:model/persist"    'controllers:model-instance-persist           "model-instance-persist")
   (:GET       "/:model/:id"        'controllers:model-instance-rebuild           "model-instance-rebuild")
   (:POST      "/:model/:id"        'controllers:model-instance-repersist         "model-instance-repersist")
   (:POST      "/:model/:id/delete" 'controllers:model-instance-delete            "model-instance-delete")))
