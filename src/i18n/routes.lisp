(in-package #:shiso/i18n)

(routing:define-module shiso-i18n
  (:urls
   (:POST "/set-language" 'set-language "set-language")))
