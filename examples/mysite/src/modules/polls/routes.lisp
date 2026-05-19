(defpackage #:polls/routes
  (:use #:cl)
  (:local-nicknames (#:s #:shiso)
                    (#:controllers #:polls/controllers)))

(in-package #:polls/routes)

(s:define-module polls
  (:urls (:GET  "/"            'controllers:index   "index")
         (:GET  "/:id"         'controllers:detail  "detail")
         (:GET  "/:id/results" 'controllers:results "results")
         (:POST "/:id/vote"    'controllers:vote    "vote")))
