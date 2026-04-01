(defpackage #:shiso/admin/controllers
  (:use #:cl)
  (:local-nicknames (#:ah #:almighty-html)
                    (#:reg #:shiso/admin/registry)
                    (#:comp #:shiso/admin/components)
                    (#:mw #:shiso/admin/middleware)
                    (#:models #:shiso/models)
                    (#:forms #:shiso/forms))
  (:import-from #:shiso/admin/components
                #:ac-admin-page
                #:ac-admin-table
                #:ac-admin-nav
                #:ac-admin-flash)
  (:export
   #:index
   #:model-instance-list
   #:model-instance-build
   #:model-instance-persist
   #:model-instance-rebuild
   #:model-instance-repersist
   #:model-instance-delete))

(in-package #:shiso/admin/controllers)

(defun render-page (title content)
  "Wrap content in the admin page skeleton."
  (let ((html (ah:render-to-string
               (ah:</>
                (ac-admin-page :title title
                  :model-names (reg:all-registered-admins)
                  content)))))
    (mw:http-response html)))

(defun model-name-from-string (str)
  "Convert a URL model name string to a symbol, e.g. \"article\" -> ARTICLE."
  (intern (string-upcase str)))

#+nil
(shiso/admin/registry::model-name-from-string "article")

(defun display-columns (model-name config)
  "Return the list of columns to display in the list controller."
  (or (reg:admin-list-display config)
      (mapcar #'models:field-name
              (remove-if-not #'models:field-editablep
                             (models:model-fields model-name)))))

(defun index ()
  "Render the admin dashboard with links to all registered models."
  (render-page
   "Dashboard"
   (ah:</> (ul :class "admin-model-list"
             (loop :for name :in (reg:all-registered-admins)
                   :for href := (shiso/utils:url "shiso-admin:model-instance-list" :model (string-downcase name))
                   :for label := (string-capitalize name)
                   :collect (ah:</> (li :class "admin-model-link" (a :href href label))))))))

#+nil
(model-name-from-string "article")
#+nil
(mito:select-dao "book")

(defun model-instance-list (model-name-str)
  "Render a table of all instances of a model."
  (let* ((model-name (models:get-model-name model-name-str))
         (config (reg:get-admin model-name))
         ;; model-class can take a string.
         (model-class (models:model-class model-name))
         (items (mito:select-dao model-class))
         (columns (display-columns model-name config))
         (create-href (shiso/utils:url "shiso-admin:model-instance-build" :model model-name-str))
         (title (format nil "~A List" (string-capitalize model-name-str))))
    (render-page title
                 (ah:</>
                  (div
                    (div :class "admin-actions"
                      (a :href create-href :class "btn btn-primary" "Add New"))
                    (ac-admin-table :columns columns
                      :items items
                      :model-name model-name-str))))))

(defun model-instance-build (model-name-str)
  "Render the create form, or handle POST to create a new instance."
  (let* ((model-name (models:get-model-name model-name-str))
         (config (reg:get-admin model-name))
         (is-post (mw:post-request-p))
         (data (when is-post (mw:parse-body-params)))
         (form (forms:make-model-form model-name
                                      :fields (reg:admin-fields config)
                                      :exclude (reg:admin-exclude config)
                                      :data data))
         (title (format nil "Create ~A" (string-capitalize model-name))))
    (render-page title
                 (forms:render-form form
                                    :action (shiso/utils:url "shiso-admin:model-instance-persist"
                                                             :model model-name-str)))))

(defun model-instance-persist (model-name-str)
  "Validate and create a new instance on POST."
  (let* ((model-name (models:get-model-name model-name-str))
         (config (reg:get-admin model-name))
         (data (mw:parse-body-params))
         (title (format nil "Create ~A" (string-capitalize model-name-str))))
    (let ((form (forms:make-model-form model-name
                                       :fields (reg:admin-fields config)
                                       :exclude (reg:admin-exclude config)
                                       :data data)))
      ;; TODO implement atomic operations
      (if (forms:validate-form form)
          (progn
            (forms:save-form form)
            (mw:redirect-response
             (shiso/utils:url "shiso-admin:model-instance-list" :model model-name-str)))
          (render-page title (forms:render-form form :action (shiso/utils:url "shiso-admin:model-instance-persist" :model model-name-str)))))))


(defun model-instance-rebuild (model-name-str id-str)
  "Render the edit form, or handle POST to update an existing instance."
  (let* ((model-name (models:get-model-name model-name-str))
         (config (reg:get-admin model-name))
         (model-class (models:model-class model-name))
         (id (parse-integer id-str))
         (instance (mito:find-dao model-class :id id))
         (is-post (mw:post-request-p))
         (data (when is-post (mw:parse-body-params)))
         (form (forms:make-model-form model-name
                                      :fields (reg:admin-fields config)
                                      :exclude (reg:admin-exclude config)
                                      :instance instance
                                      :data data))
         (title (format nil "Edit ~A #~A"
                        (string-capitalize (symbol-name model-name)) id)))
    (render-page title
                 (forms:render-form form
                                    :action (shiso/utils:url "shiso-admin:model-instance-repersist"
                                                             :model model-name-str
                                                             :id id-str)))))

(defun model-instance-repersist (model-name-str id-str)
  "Validate and update the instance on PATCH."
  (let* ((model-name (models:get-model-name model-name-str))
         (config (reg:get-admin model-name-str))
         (model-class (models:model-class model-name))
         (id (parse-integer id-str))
         (instance (mito:find-dao model-class :id id))
         (data (mw:parse-body-params))
         (form (forms:make-model-form model-name
                                      :fields (reg:admin-fields config)
                                      :exclude (reg:admin-exclude config)
                                      :instance instance
                                      :data data))
         (title (format nil "Edit ~A #~A"
                        (string-capitalize (symbol-name model-name)) id)))
    (if (forms:validate-form form)
        (progn
          (forms:save-form form)
          (mw:redirect-response
           (shiso/utils:url "shiso-admin:model-instance-list" :model model-name-str)))
        (render-page title
                     (forms:render-form form
                                        :action (shiso/utils:url "shiso-admin:model-instance-repersist"
                                                                 :model model-name-str
                                                                 :id id-str))))))

(defun model-instance-delete (model-name-str id-str)
  "Handle POST to delete a model instance."
  (let* ((model-name (model-name-from-string model-name-str))
         (model-class (models:model-class model-name))
         (id (parse-integer id-str))
         (instance (mito:find-dao model-class :id id)))
    (when instance
      (mito:delete-dao instance))
    (mw:redirect-response
     (shiso/utils:url "shiso-admin:model-instance-list" :model model-name-str))))
