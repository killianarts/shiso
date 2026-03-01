(defpackage #:shiso/admin/components
  (:use #:cl)
  (:local-nicknames (#:ah #:almighty-html)
                    (#:models #:shiso/models))
  (:export
   #:ac-admin-page
   #:ac-admin-table
   #:ac-admin-nav
   #:ac-admin-flash))

(in-package #:shiso/admin/components)

(ah:define-component ac-admin-nav (&key model-names admin-prefix)
  (ah:</>
   (nav :class "admin-nav"
     (div :class "admin-nav-header"
       (a :href admin-prefix
         (strong "Admin")))
     (ul :class "admin-nav-list"
       (loop :for name :in model-names
             :for href = (shiso/utils:url (format nil "~A/~(~A~)" admin-prefix name))
             :for label = (string-capitalize (symbol-name name))
             :collect (ah:</> (li (a :href href label ))))))))

(ah:define-component ac-admin-page (&key title admin-prefix model-names children)
  (let ((prefix (or admin-prefix "/admin"))
        (names (or model-names nil)))
    (ah:</>
     (html :lang "en"
       (head
         (meta :charset "utf-8")
         (meta :name "viewport"
           :content "width=device-width, initial-scale=1")
         (title (format nil "~A — Admin" title))
         (style "
body { font-family: system-ui, sans-serif; margin: 0; display: flex; min-height: 100vh; }
.admin-nav { width: 220px; background: #1a1a2e; color: #eee; padding: 1rem; flex-shrink: 0; }
.admin-nav-header { margin-bottom: 1.5rem; }
.admin-nav-header a { color: #eee; text-decoration: none; font-size: 1.25rem; }
.admin-nav-list { list-style: none; padding: 0; margin: 0; }
.admin-nav-list li { margin-bottom: 0.5rem; }
.admin-nav-list a { color: #ccc; text-decoration: none; }
.admin-nav-list a:hover { color: #fff; }
.admin-content { flex: 1; padding: 2rem; }
.admin-header { margin-bottom: 1.5rem; display: flex; justify-content: space-between; align-items: center; }
.admin-header h1 { margin: 0; }
table.admin-table { width: 100%; border-collapse: collapse; }
.admin-table th, .admin-table td { padding: 0.5rem 1rem; text-align: left; border-bottom: 1px solid #ddd; }
.admin-table th { background: #f5f5f5; font-weight: 600; }
.admin-table tr:hover { background: #fafafa; }
.form-group { margin-bottom: 1rem; }
.form-group label { display: block; font-weight: 600; margin-bottom: 0.25rem; }
.form-group input, .form-group textarea, .form-group select { width: 100%; padding: 0.5rem; border: 1px solid #ccc; border-radius: 4px; box-sizing: border-box; }
.form-group textarea { min-height: 120px; }
.has-errors input, .has-errors textarea, .has-errors select { border-color: #e53e3e; }
.field-errors { list-style: none; padding: 0; margin: 0.25rem 0 0; color: #e53e3e; font-size: 0.875rem; }
.help-text { color: #666; font-size: 0.875rem; margin: 0.25rem 0 0; }
.btn { display: inline-block; padding: 0.5rem 1rem; border: none; border-radius: 4px; cursor: pointer; text-decoration: none; font-size: 0.875rem; }
.btn-primary { background: #3b82f6; color: #fff; }
.btn-primary:hover { background: #2563eb; }
.btn-danger { background: #e53e3e; color: #fff; }
.btn-danger:hover { background: #c53030; }
.flash-success { background: #c6f6d5; color: #22543d; padding: 0.75rem 1rem; border-radius: 4px; margin-bottom: 1rem; }
.flash-error { background: #fed7d7; color: #742a2a; padding: 0.75rem 1rem; border-radius: 4px; margin-bottom: 1rem; }
.admin-actions { display: flex; gap: 0.5rem; }
.delete-form { display: inline; }
"))
       (body
         (ac-admin-nav :model-names names :admin-prefix prefix)
         (div :class "admin-content"
           (div :class "admin-header"
             (h1 title))
           children))))))

(ah:define-component ac-admin-table-column-headers (&key columns children)
  (loop :for col :in columns
        :for label := (string-capitalize
                       (substitute #\Space #\-
                                   (string-downcase
                                    (symbol-name col))))
        :collect (ah:</> (th label))))

(ah:define-component ac-admin-table-rows (&key columns items model-name admin-prefix children)
  (loop :for item :in items
        :for id := (mito:object-id item)
        :for cells := (loop :for col :in columns
                            :for val := (if (slot-boundp item col)
                                            (slot-value item col)
                                            "")
                            :collect (ah:</> (td (princ-to-string val))))
        :for edit-href := (format nil "~A/~(~A~)/~A" admin-prefix model-name id)
        :collect (ah:</>
                  (tr cells (td (a :href edit-href :class "btn btn-primary" "Edit"))))))

(ah:define-component ac-admin-table (&key columns items model-name admin-prefix children)
  (ah:</>
   (table :class "admin-table"
     (thead (tr (ac-admin-table-column-headers :columns columns) (th "Actions")))
     (tbody (ac-admin-table-rows :columns columns :items items :model-name model-name :admin-prefix admin-prefix)))))

(ah:define-component ac-admin-flash (&key message type)
  (let ((css-class (if (eq type :error) "flash-error" "flash-success")))
    (when message
      (ah:</> (div :class css-class message)))))
