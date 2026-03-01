(defpackage #:shiso/admin/views
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
   #:dashboard-view
   #:list-view
   #:create-view
   #:edit-view
   #:delete-view
   #:*admin-prefix*))

(in-package #:shiso/admin/views)

(defvar *admin-prefix* "/admin"
  "URL prefix for the admin dashboard.  Set before mounting.")

(defun render-page (title content)
  "Wrap content in the admin page skeleton."
  (let ((html (ah:render-to-string
               (ah:</>
                (ac-admin-page :title title
                               :admin-prefix *admin-prefix*
                               :model-names (reg:all-registered-admins)
                               content)))))
    (mw:http-response html)))

(defun model-name-from-string (str)
  "Convert a URL model name string to a symbol, e.g. \"article\" -> ARTICLE."
  (intern (string-upcase str)))

(defun display-columns (model-name config)
  "Return the list of columns to display in the list view."
  (or (reg:admin-list-display config)
      (mapcar #'models:field-name
              (remove-if-not #'models:field-editablep
                             (models:model-fields model-name)))))

(defun dashboard-view ()
  "Render the admin dashboard with links to all registered models."
  (let ((links (mapcar (lambda (name)
                         (let ((href (format nil "~A/~(~A~)" *admin-prefix* name))
                               (label (string-capitalize (symbol-name name))))
                           (ah:</> (li :class "admin-model-link"
                                     (a :href href label)))))
                       (reg:all-registered-admins))))
    (render-page "Dashboard"
                 (ah:</> (ul :class "admin-model-list" links)))))

(defun list-view (model-name-str)
  "Render a table of all instances of a model."
  (let* ((model-name (model-name-from-string model-name-str))
         (config (reg:get-admin model-name))
         (model-class (models:model-class model-name))
         (items (mito:select-dao model-class))
         (columns (display-columns model-name config))
         (create-href (format nil "~A/~(~A~)/create" *admin-prefix* model-name))
         (title (format nil "~A List" (string-capitalize (symbol-name model-name)))))
    (render-page title
      (ah:</>
       (<>
         (ah:</> (div :class "admin-actions"
                   (ah:</> (a :href create-href :class "btn btn-primary" "Add New"))))
         (ah:</> (ac-admin-table :columns columns
                                 :items items
                                 :model-name model-name
                                 :admin-prefix *admin-prefix*)))))))

(defun create-view (model-name-str)
  "Render the create form, or handle POST to create a new instance."
  (let* ((model-name (model-name-from-string model-name-str))
         (config (reg:get-admin model-name))
         (is-post (mw:post-request-p))
         (data (when is-post (mw:parse-body-params)))
         (form (forms:make-model-form model-name
                 :fields (reg:admin-fields config)
                 :exclude (reg:admin-exclude config)
                 :data data))
         (title (format nil "Create ~A" (string-capitalize (symbol-name model-name)))))
    (if (and is-post (forms:validate-form form))
        (progn
          (forms:save-form form)
          (mw:redirect-response
           (format nil "~A/~(~A~)" *admin-prefix* model-name)))
        (render-page title
          (forms:render-form form
            :action (format nil "~A/~(~A~)/create" *admin-prefix* model-name))))))

(defun edit-view (model-name-str id-str)
  "Render the edit form, or handle POST to update an existing instance."
  (let* ((model-name (model-name-from-string model-name-str))
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
    (if (and is-post (forms:validate-form form))
        (progn
          (forms:save-form form)
          (mw:redirect-response
           (format nil "~A/~(~A~)" *admin-prefix* model-name)))
        (render-page title
          (forms:render-form form
            :action (format nil "~A/~(~A~)/~A"
                            *admin-prefix* model-name id))))))

(defun delete-view (model-name-str id-str)
  "Handle POST to delete a model instance."
  (let* ((model-name (model-name-from-string model-name-str))
         (model-class (models:model-class model-name))
         (id (parse-integer id-str))
         (instance (mito:find-dao model-class :id id)))
    (when instance
      (mito:delete-dao instance))
    (mw:redirect-response
     (format nil "~A/~(~A~)" *admin-prefix* model-name))))
