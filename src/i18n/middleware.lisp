(in-package #:shiso/i18n)

(defun wrap-locale (app)
  "Lack middleware: bind *LOCALE* for the request from cookie,
Accept-Language, or *DEFAULT-LOCALE*."
  (lambda (env)
    (ensure-localisations)
    (let ((*locale* (best-locale env)))
      (funcall app env))))
