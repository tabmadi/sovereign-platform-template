package money

import (
	"database/sql/driver"
	"encoding/json"
	"fmt"
)

// The database and wire surfaces, per ADR-0100 and ADR-0303. Both carry the amount as a string and never a float.
// The scanned value has no currency, because a Postgres numeric holds only the amount. The caller adds the
// currency to the result of [Amount.Scan] with [Amount.WithCurrency].

// Value implements driver.Valuer. It returns the amount as a decimal string, and pgx
// sends that to a numeric column with no float in between.
func (a Amount) Value() (driver.Value, error) {
	if !a.Valid() {
		return nil, nil //nolint:nilnil // a NULL numeric column is the zero Amount
	}
	return a.String(), nil
}

// Scan implements sql.Scanner for a numeric column. The result carries no currency.
// Add it with [Amount.WithCurrency].
func (a *Amount) Scan(src any) error {
	switch v := src.(type) {
	case nil:
		*a = Amount{}
		return nil
	case string:
		return a.scanString(v)
	case []byte:
		return a.scanString(string(v))
	case float64:
		// This runs only if a column is float8 and not numeric, which ADR-0100 forbids.
		// The scan fails here on purpose. Accepting it hides the schema defect until a
		// total comes out wrong.
		return fmt.Errorf("money: refusing to scan float64 %v: the column must be numeric, not float8", v)
	default:
		return fmt.Errorf("money: cannot scan %T", src)
	}
}

func (a *Amount) scanString(s string) error {
	// The code uses a placeholder currency, because Parse needs one and the column
	// does not carry it. WithCurrency replaces it before the value is used.
	parsed, err := Parse(s, "XXX")
	if err != nil {
		return fmt.Errorf("money: scan %q: %w", s, err)
	}
	*a = parsed
	return nil
}

// WithCurrency returns the amount with its currency set. A store uses it to build
// a value from the amount and currency columns.
func (a Amount) WithCurrency(currency string) (Amount, error) {
	err := ValidateCurrency(currency)
	if err != nil {
		return Amount{}, err
	}
	return Amount{units: a.units, currency: currency}, nil
}

// wire is the JSON shape, matching the Money component in
// tools/codegen/shared-components.yaml.
type wire struct {
	Amount   string `json:"amount"`
	Currency string `json:"currency"`
}

// MarshalJSON writes `{"amount": "1299.00", "currency": "EUR"}`. The amount is a string, because a TypeScript client
// reads a JSON number as an IEEE-754 double.
func (a Amount) MarshalJSON() ([]byte, error) {
	if !a.Valid() {
		return []byte("null"), nil
	}
	data, err := json.Marshal(wire{Amount: a.String(), Currency: a.currency})
	if err != nil {
		return nil, fmt.Errorf("money: marshal: %w", err)
	}
	return data, nil
}

// UnmarshalJSON reads the same shape and rejects any JSON number. Accepting one
// takes the precision loss that the string form prevents, with no error.
func (a *Amount) UnmarshalJSON(data []byte) error {
	if string(data) == "null" {
		*a = Amount{}
		return nil
	}
	var w wire
	err := json.Unmarshal(data, &w)
	if err != nil {
		return fmt.Errorf("money: unmarshal: %w", err)
	}
	parsed, err := Parse(w.Amount, w.Currency)
	if err != nil {
		return err
	}
	*a = parsed
	return nil
}
