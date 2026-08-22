(in-package #:shiso/i18n)

(defun safe-next-url (raw)
  "Only honour local-path `next` values. Same rules as shiso-auth."
  (cond
    ((null raw) nil)
    ((and (stringp raw)
          (plusp (length raw))
          (char= (char raw 0) #\/)
          (not (and (> (length raw) 1) (char= (char raw 1) #\/))))
     (let* ((qpos (position #\? raw))
            (path (if qpos (subseq raw 0 qpos) raw))
            (qs (if qpos (subseq raw qpos) ""))
            (clean (routing:canonicalize-path path)))
       (concatenate 'string clean qs)))
    (t nil)))

(defun add-set-cookie (response locale)
  (destructuring-bind (status headers body) response
    (list status
          (append (list :set-cookie (set-language-cookie-header locale))
                  headers)
          body)))

(defun set-language ()
  "POST /set-language — persist LANGUAGE in a cookie and redirect."
  (unless (utils:post-request-p)
    (return-from set-language
      (utils:http-response "Method not allowed" :code 405)))
  (let* ((params (utils:parse-body-params))
         (raw (cdr (assoc :language params)))
         (available (available-locales))
         (locale (and raw (match-available (canonicalize-locale raw) available)))
         (next (safe-next-url (cdr (assoc :next params)))))
    (unless locale
      (setf locale (current-locale)))
    (add-set-cookie (utils:redirect-response (or next "/")) locale)))
