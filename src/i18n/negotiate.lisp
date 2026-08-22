(in-package #:shiso/i18n)

(defun parse-accept-language (header)
  "Parse an Accept-Language header into a list of (locale . q) sorted
by q descending. HEADER may be NIL."
  (unless (and header (plusp (length header)))
    (return-from parse-accept-language nil))
  (let ((parts (mapcar (lambda (s) (string-trim '(#\Space #\Tab) s))
                       (uiop:split-string header :separator ",")))
        (result '()))
    (dolist (part parts)
      (when (plusp (length part))
        (let* ((semi (position #\; part))
               (tag (string-trim '(#\Space #\Tab)
                                 (if semi (subseq part 0 semi) part)))
               (q 1.0))
          (when (and semi (< (1+ semi) (length part)))
            (let ((rest (string-trim '(#\Space #\Tab) (subseq part (1+ semi)))))
              (when (and (> (length rest) 2)
                         (char-equal (char rest 0) #\q)
                         (char= (char rest 1) #\=))
                (setf q (or (ignore-errors
                             (let (*read-eval*)
                               (read-from-string (subseq rest 2))))
                            0.0)))))
          (when (and (plusp (length tag)) (not (string= tag "*")))
            (push (cons (canonicalize-locale tag) q) result)))))
    (sort result #'> :key #'cdr)))

(defun cookie-header-value (env name)
  "Return the raw cookie named NAME from a Clack ENV, or NIL."
  (let* ((headers (getf env :headers))
         ;; The branches have to be exclusive. Written as an `or' over a
         ;; hash-table arm and a plist arm, a hash-table carrying no cookie
         ;; key falls out of the first arm and into `getf' — on the
         ;; hash-table — which is a type error rather than a miss. Clack
         ;; always hands us a hash-table, so that was every request that
         ;; sent no Cookie header, i.e. every visitor's first one.
         (cookie (cond ((null headers) nil)
                       ((hash-table-p headers)
                        (or (gethash "cookie" headers)
                            (gethash :cookie headers)))
                       (t (getf headers :cookie)))))
    (when cookie
      (dolist (part (uiop:split-string cookie :separator ";"))
        (let* ((piece (string-trim '(#\Space #\Tab) part))
               (eq-pos (position #\= piece)))
          (when (and eq-pos
                     (string-equal name (subseq piece 0 eq-pos)))
            (return (subseq piece (1+ eq-pos)))))))))

(defun env-accept-language (env)
  "The Accept-Language header from ENV, or NIL."
  (let ((headers (getf env :headers)))
    (cond ((null headers) nil)
          ((hash-table-p headers)
           (or (gethash "accept-language" headers)
               (gethash :accept-language headers)))
          (t (getf headers :accept-language)))))

(defun match-available (wanted available)
  "Match WANTED against AVAILABLE: exact, then same language."
  (let ((wanted (canonicalize-locale wanted)))
    (or (find wanted available :test #'eq)
        (find (locale-lang wanted) available :key #'locale-lang :test #'eq))))

(defun best-locale (env &optional (available (available-locales)))
  "Pick a locale for ENV: cookie, then Accept-Language, then default."
  (let ((available (or available (list *default-locale*))))
    (or (let ((raw (cookie-header-value env *language-cookie-name*)))
          (and raw (match-available raw available)))
        (dolist (pair (parse-accept-language (env-accept-language env))
                      nil)
          (let ((matched (match-available (car pair) available)))
            (when matched (return matched))))
        (canonicalize-locale *default-locale*))))

(defun set-language-cookie-header (locale)
  "Value of a Set-Cookie header that persists LOCALE."
  (format nil "~A=~A; Path=/; Max-Age=31536000; SameSite=Lax"
          *language-cookie-name*
          (locale-cookie-value locale)))
