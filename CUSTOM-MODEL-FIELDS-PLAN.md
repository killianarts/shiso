# Custom Model Fields Plan

In Django, it is possible to create a custom model field that actually adds
another field via the `contribute_to_class()` method. For example, the Django
Money library has this code in its `models/fields.py` file:

```python
class CurrencyField(models.CharField):
    description = "A field which stores currency."

    def __init__(self, price_field=None, default=DEFAULT_CURRENCY, **kwargs):
        if isinstance(default, Currency):
            default = default.code
        kwargs.setdefault("max_length", CURRENCY_CODE_MAX_LENGTH)
        self.price_field = price_field
        super().__init__(default=default, **kwargs)

    def contribute_to_class(self, cls, name):
        if name not in [f.name for f in cls._meta.fields]:
            super().contribute_to_class(cls, name)


class MoneyField(models.DecimalField):
    description = "A field which stores both the currency and amount of money."
    ...
    
    def contribute_to_class(self, cls, name):
        cls._meta.has_money_field = True

        # Note the discussion about whether or not the currency field should be added in migrations:
        # https://github.com/django-money/django-money/issues/725
        # https://github.com/django-money/django-money/pull/726
        # https://github.com/django-money/django-money/issues/731
        if not hasattr(self, "_currency_field"):
            self.add_currency_field(cls, name)

        super().contribute_to_class(cls, name)

        setattr(cls, self.name, self.money_descriptor_class(self))

    def add_currency_field(self, cls, name):
        """
        Adds CurrencyField instance to a model class.
        """
        currency_field = CurrencyField(
            price_field=self,
            max_length=self.currency_max_length,
            default=self.default_currency,
            editable=False,
            choices=self.currency_choices,
            null=self.null,
        )
        currency_field.creation_counter = self.creation_counter - 1
        currency_field_name = get_currency_field_name(name, self)
        cls.add_to_class(currency_field_name, currency_field)
        self._currency_field = currency_field
...
```

This effectively means that a user of the Django Money library only needs to add
a `MoneyField` to their model, but the actual DB table will have two columns:
one that's a decimal value for the Money amount, and one that's a char field
with the currency value.

Mito doesn't provide the ability to create custom "fields"--mito doesn't even
have a concept of "fields", only Common Lisp slots and SQL table columns. Thus,
if we want to handle money in our DB table, we need to define a model/table like
this:

```lisp
(mito:deftable leg ()
  ((account :col-type account)
   (side :col-type :integer)
   ;; Use LEG-ENTRY to access ENTRY-AMOUNT and ENTRY-CURRENCY as an
   ;; ALMIGHTY-MONEY:MONEY object.
   (entry-amount :col-type :integer)    ; ALMIGHTY-MONEY:MONEY object AMOUNT.
   (entry-currency :col-type :text) ; ALMIGHTY-MONEY:MONEY object CURRENCY-CODE.
   (transaction :col-type (or transaction :null)))
  (:table-name "almighty_leg"))
  
(defgeneric leg-entry (leg)
  (:documentation "A function for getting the ENTRY-AMOUNT and ENTRY-CURRENCY of a LEG object and returning a MONEY object.")
  (:method ((this leg))
    (am:make-money (leg-entry-amount this) (leg-entry-currency this))))

```

That's not really a big deal, but if there is a way to create a simple API for
adding custom model fields, that would be great.
