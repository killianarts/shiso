(defpackage #:shiso/i18n
  (:use #:cl)
  (:local-nicknames (#:modules #:shiso/modules)
                    (#:utils #:shiso/utils)
                    (#:routing #:shiso/routing))
  (:export
   ;; Locale binding
   #:*locale*
   #:*default-locale*
   #:*fallback-locale*
   #:*language-cookie-name*
   #:with-locale
   #:current-locale
   #:canonicalize-locale
   #:locale-lang
   #:locale-html-lang
   ;; Catalogs
   #:load-localisations
   #:ensure-localisations
   #:available-locales
   ;; Lookup
   #:translate
   #:message-id
   #:fluent-id-p
   ;; HTTP
   #:best-locale
   #:parse-accept-language
   #:wrap-locale
   #:set-language-cookie-header))

(in-package #:shiso/i18n)
