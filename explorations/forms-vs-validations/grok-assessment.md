# Forms vs validations for Shiso (todo tutorial)

**Author:** Grok (xAI)  
**Scope:** The create-todo flow from `docs/tutorial/05-todo-app.org` / `examples/todo/`.  
**Artifacts:**

| File | Role |
|------|------|
| `grok-todo-with-forms.lisp` | Create flow rewritten around Shiso Forms (`make-todo-form`, `validate-form`, `render-form`) |
| `grok-todo-with-validations.lisp` | Same flow with a validation-first API (clavier-style / `shiso/validators`) |
| `grok-assessment.md` | This document |

---

## Context: what the tutorial actually does today

The shipped todo app **does not use Shiso Forms**. `examples/todo/.../forms.lisp` is an empty package. Create looks like:

```lisp
(defun create ()
  (let* ((body (s:parse-body-params))
         (title (cdr (assoc :title body))))
    (when (and title (plusp (length (string-trim '(#\Space #\Tab) title))))
      (models:create-todo (string-trim '(#\Space #\Tab) title)))
    (s:redirect-response (s:url "todos:index"))))
```

That is already closer to “validate request data” than to Django-style forms:

- Markup is hand-written in the controller.
- Validation is an inline predicate (non-blank after trim).
- Invalid input is **silently ignored** (still redirects; no error UI).
- Toggle/delete carry no domain fields — only CSRF + id in the path.

So the question is not “tutorial Forms vs tutorial validations.” It is:

> If we want structured validation and error re-display for create, is the cost of a **Form object** (fields + render + cleaned-data) worth it, or is a **validation function over params** enough?

Modern web stacks increasingly pick the second answer for app code, while keeping form-like machinery only where codegen pays off (admin, large multi-field screens).

---

## Side-by-side sketch of the two explorations

### Forms version (Django / WTForms lineage)

```
define form fields (name, widget, validators, label)
        │
        ├─► render-form  ──► HTML (+ CSRF)
        │
        └─► validate-form ──► cleaned-data | field errors
                    │
                    └─► create-todo / re-render form
```

One object owns:

1. Field inventory  
2. Coercion (`parse-field-value`)  
3. Validation  
4. Default HTML rendering  
5. Bound state for re-display  

### Validations version (clavier / Laravel / “validate the request”)

```
parse-body-params ──► validate-create-todo(params)
                              │
                    (cleaned, nil) | (nil, errors)
                              │
              create-todo / hand-render with errors
```

Validation is a pure function of data. Rendering stays in the view layer. CSRF stays middleware + a hidden input helper.

---

## Strengths and weaknesses

### Shiso Forms

| Strengths                                                                                                                       | Weaknesses                                                                                                                                                                                                                         |
|---------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Single definition** of label, help text, max-length, required, validators — used by validation and (if you use it) rendering. | **Weight for small forms.** Todo create is one string field; a form class + package + generic render is a lot of machinery for five lines of real logic.                                                                           |
| **`make-model-form`** can derive fields from `define-model` metadata — admin and public UI can share one source of truth.       | **Render lock-in.** `render-form` produces generic `.form-group` markup. The tutorial’s compact flex “add bar” does not match; you either fight the renderer or dual-path (validate with form, render by hand — half the benefit). |
| **Error re-display is built in** if you re-render the same form object after `validate-form` fails.                             | **Coupling of concerns.** Widget choice, HTML, coercion, and validation live in one hierarchy. Changing only the look still touches form code.                                                                                     |
| **Admin ROI is high.** Generics list/create/edit over many models — forms earn their keep.                                      | **Key/type friction.** Params are keywords; field names are symbols; auth code already re-keys to strings. That complexity is a Forms-layer smell.                                                                                 |
| Familiar to Django users; matches the “model → form → admin” story Shiso sells.                                                 | **Toggle/delete don’t benefit.** Most of the todo UI is not field-bearing forms. Forms only touch the add path.                                                                                                                    |
| Auto-validators from field class (`requiredp` → `not-blank`, varchar → `max-length`).                                           | **Incomplete widgets.** Password (and other widgets) are stored as metadata but not fully honored in rendering — forces hand HTML for auth already.                                                                                |

### Validation-first (clavier-like / `shiso/validators` on params)

| Strengths                                                                                                                 | Weaknesses                                                                                                                                   |
|---------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------|
| **Matches modern defaults.** Validate maps/plists; render separately. Easy mental model for API + HTML dual frontends.    | **No free HTML.** Labels, error placement, `value=` re-fill, and CSS classes are manual every time.                                          |
| **Tiny surface for todo.** A `validate-create-todo` function + hand form is shorter than a form class and stays readable. | **Duplication with models.** `:max-length 200` on the model is restated on the validator list unless you write a bridge from model metadata. |
| **Pure and testable.** Unit tests call `validate-create-todo` with alists — no form instance, no request.                 | **Admin still needs a form-like path** (or stays as hand-rolled generic forms inside admin). Public and admin may diverge.                   |
| **Full layout control.** Tutorial CSS works as-is; HTMX fragments, JSON APIs, and CLI all reuse the same validator.       | **Multi-field UX is DIY.** Fieldset grouping, widgets, choices dropdowns, datetime formatting — all app code.                                |
| **Composability (clavier).** `&&`, `\|\|`, `~`, length, blank, etc. are orthogonal to HTTP.                               | **Structured multi-field errors** need a small house convention (`(values cleaned errors)`); libraries vary.                                 |
| **Orthogonal CSRF.** Hidden input helper + Lack middleware — no form framework required.                                  | **Coercion is separate.** Integer/boolean/date parsing is your job (or a thin parse layer), not `parse-field-value` on a field class.        |
| Closer to what the tutorial already teaches — extract the inline check, don’t introduce a parallel abstraction.           | Risk of **ad-hoc sprawl** if every controller invents its own error shape without a project convention.                                      |

---

## Complexity vs value on the todo app

Rough sense of “how much code cares about the framework feature”:

| Concern                            | Forms version                                      | Validations version          | Tutorial today                |
|------------------------------------|----------------------------------------------------|------------------------------|-------------------------------|
| Create validation                  | form fields + `validate-form`                      | `validate-create-todo`       | 1 inline `when`               |
| Error messages on bad title        | automatic via `render-form`                        | manual in `add-form`         | none (silent drop)            |
| Markup for add                     | `render-form` (generic)                            | hand HTML (exact CSS)        | hand HTML                     |
| Shared with admin                  | possible via `make-model-form`                     | only if you share validators | admin uses its own forms path |
| Toggle / delete                    | hand HTML                                          | hand HTML                    | hand HTML                     |
| New concepts for a tutorial reader | form class, cleaned-data, field types, render-form | validate fn, errors alist    | params + trim                 |

For **this** app, Forms does not pay for itself:

1. One field.  
2. Custom layout that fights the stock renderer.  
3. Most “forms” on the page are CSRF shells, not data entry.  
4. The tutorial’s value is PRG + CSRF + model CRUD, not model-form generation.

Forms **would** pay off if the todo grew into something like:

- Multi-field create/edit (title, due date, priority, project, tags).  
- Shared public edit + admin with the same field set.  
- Heavy re-display of many field errors after partial submits.

Until then, a validation function is the better fit — and it is what many “modern” frameworks standardized on for *application* code, while reserving form objects for admin/scaffolded UIs.

---

## How this maps onto Shiso’s architecture

Shiso already has **both** layers:

| Layer      | Package            | Role                                                               |
|------------|--------------------|--------------------------------------------------------------------|
| Validators | `shiso/validators` | Pure designators + `run-validators` — same idea as a light clavier |
| Forms      | `shiso/forms/*`    | Fields, form object, model-form, rendering                         |
| Admin      | `shiso/admin/*`    | Heavy consumer of model-form + render                              |

So the design tension is real product strategy, not a missing library:

1. **Keep validators as the primitive** everyone can use without forms.  
2. **Treat forms as optional sugar** for multi-field HTML + admin, not as the only blessed path.  
3. **Document the validation-first pattern** for app controllers (todo-style), and Forms for admin / large forms.  
4. Optionally add a thin helper:

   ```lisp
   (validate-params params
     (:title (not-blank) (max-length 200)))
   ;; => (values cleaned errors)
   ```

   That would be “clavier ergonomics” on top of existing `shiso/validators` without pulling in form classes.

### If Forms stay

Worth investing only if they stay **valuable when you skip `render-form`**:

- First-class “validate only” path (form as schema + cleaner, not HTML).  
- Stable param key convention (always keywords or always strings).  
- Widget metadata that render actually uses (or drop unused widget options).  
- Model metadata → validator list without requiring a full form instance (so validation-first can share max-length with `define-model`).

### If Forms shrink

- Admin can keep an internal form/render stack (or even stay as-is).  
- Public API emphasizes `parse-body-params` + validators (+ optional schema macro).  
- Delete or demote `render-form` from the “hello world” path so tutorials don’t force Django muscle memory where it hurts.

---

## Recommendation (for Shiso, informed by the todo exercise)

1. **For the todo tutorial:** keep validation-first. Improve it slightly: extract `validate-create-todo`, re-render with an error message instead of silent drop. Do **not** introduce Forms in that tutorial — it teaches the wrong cost model for the problem size.  

2. **For the framework story:** position Forms as **admin + multi-field HTML**, not as mandatory for every POST. Market validators as the default for request data.  

3. **For “is Forms complexity worth it?”:**  
   - **Worth it** when many fields, shared model-driven UI, and/or admin reuse dominate.  
   - **Not worth it** when the UI is custom, fields are few, or the same validators must serve HTML + JSON + jobs.  

4. **Middle path (best fit for Shiso’s size):** strengthen `shiso/validators` with multi-field `validate-params` / error alists; keep Forms, but make them optional consumers of the same validators and model metadata rather than a parallel universe.

---

## Quick decision table

| Situation                                           | Prefer                                                                    |
|-----------------------------------------------------|---------------------------------------------------------------------------|
| One–three fields, custom HTML (todo add bar)        | Validations                                                               |
| JSON API / HTMX partial with no form framework      | Validations                                                               |
| Admin auto-CRUD over registered models              | Forms (or admin-internal forms)                                           |
| Large multi-field create/edit with error re-display | Forms *or* validations + component library; Forms wins if markup is stock |
| Need one source of truth with `define-model`        | Model metadata → validators; Forms only if you also want stock widgets    |
| Teaching CSRF + PRG + Mito in a short tutorial      | Validations (or even inline), not Forms                                   |

---

## Bottom line

The doubt that came up while testing Forms is justified for **app-facing** pages like the todo create form. Modern practice — and clavier’s design — centers **validating data**, not **form objects**. Shiso’s Forms layer still makes sense as **higher-level glue** for admin and large HTML forms, but it should not be the only or primary way to handle POST bodies. The todo tutorial already votes with its feet: empty `forms.lisp`, five lines of param checks. A named validation function is the natural next step; a full Form class is not.
)
