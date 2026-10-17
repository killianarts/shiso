# explorations/forms-vs-validations

Design exploration (Grok / xAI): should Shiso treat **Forms** as a core app feature, or follow modern stacks and treat **request validation** as the primitive?

## Files

| File | Contents |
|------|----------|
| [`grok-todo-with-forms.lisp`](grok-todo-with-forms.lisp) | Todo **create** flow rewritten with Shiso Forms |
| [`grok-todo-with-validations.lisp`](grok-todo-with-validations.lisp) | Same flow with validation-first / clavier-style API |
| [`grok-assessment.md`](grok-assessment.md) | Strengths, weaknesses, recommendation |
| [`grok-README.md`](grok-README.md) | This index |

The sketches are **not** wired into `examples/todo/` and are not meant to load as a system. Compare them to the tutorial as shipped: `docs/tutorial/05-todo-app.org` and `examples/todo/` (which currently use neither Forms nor a named validator — only an inline blank check).

## Reading order

1. Skim both `.lisp` files (focus on `create` / form-or-validate setup).  
2. Read `grok-assessment.md`.
)
