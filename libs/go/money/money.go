// Package money is the platform's monetary type (ADR-0100, ADR-0003).
package money

import (
	"errors"
	"fmt"
	"math/big"
	"regexp"
	"strings"
)

type Rounding int

const (
	// HalfEven — banker's rounding. The default for a monetary split because it does
	// not drift: half-up biases every tie upward, and across many rows that bias is
	// a real sum, not a rounding artefact.
	HalfEven Rounding = iota
	// HalfUp rounds a tie away from zero. Some tax and invoicing rules require it.
	HalfUp
	// Down truncates toward zero.
	Down
)

// scale is the number of decimal places held internally. Four covers unit prices
// and tax rates, which routinely need more precision than the two places a
// currency's minor unit has, while staying exact in the int64-backed big.Int.
const scale = 4

var scaleFactor = big.NewInt(10000) // 10^scale

// rateScale is finer than the amount scale: 0.00005 is a real tax rate, and parsing it at four places would reject it
// as excess precision.
const rateScale = 8

var rateScaleFactor = big.NewInt(100000000) // 10^rateScale

var (
	ErrCurrencyMismatch = errors.New("money: currency mismatch")
	ErrNoCurrency       = errors.New("money: missing currency")
	ErrBadCurrency      = errors.New("money: currency must be three uppercase letters")
	ErrBadAmount        = errors.New("money: not a decimal amount")
	ErrDivideByZero     = errors.New("money: divide by zero")
)

var (
	currencyPattern = regexp.MustCompile(`^[A-Z]{3}$`)
	amountPattern   = regexp.MustCompile(`^-?[0-9]+(\.[0-9]+)?$`)
)

// Amount is a monetary value: a fixed-point quantity and its currency. The zero value has no currency, so an
// amount cannot silently join a total it does not belong in.
//
//nolint:recvcheck // sql.Scanner and json.Unmarshaler require the pointer receiver
type Amount struct {
	units    big.Int // the amount scaled by 10^scale
	currency string  // ISO 4217 alphabetic, uppercase
}

func Parse(amount, currency string) (Amount, error) {
	err := ValidateCurrency(currency)
	if err != nil {
		return Amount{}, err
	}
	if !amountPattern.MatchString(amount) {
		return Amount{}, fmt.Errorf("%w: %q", ErrBadAmount, amount)
	}

	negative := strings.HasPrefix(amount, "-")
	digits := strings.TrimPrefix(amount, "-")
	whole, frac, _ := strings.Cut(digits, ".")

	// Pad or truncate the fraction to the internal scale. Truncation loses precision
	// the caller supplied, so it is rejected rather than silently applied.
	if len(frac) > scale {
		return Amount{}, fmt.Errorf("%w: more than %d decimal places in %q", ErrBadAmount, scale, amount)
	}
	frac += strings.Repeat("0", scale-len(frac))

	units, ok := new(big.Int).SetString(whole+frac, 10)
	if !ok {
		return Amount{}, fmt.Errorf("%w: %q", ErrBadAmount, amount)
	}
	if negative {
		units.Neg(units)
	}
	return Amount{units: *units, currency: currency}, nil
}

// MustParse is Parse for constants and tests, where a failure is a programming
// error rather than a runtime condition.
func MustParse(amount, currency string) Amount {
	v, err := Parse(amount, currency)
	if err != nil {
		panic(err)
	}
	return v
}

// FromMinorUnits builds an amount from a currency's smallest unit — cents, pence —
// which is how an integer column or a payment processor usually carries one.
// minorDigits is that currency's exponent: 2 for EUR, 0 for JPY.
func FromMinorUnits(value int64, minorDigits int, currency string) (Amount, error) {
	err := ValidateCurrency(currency)
	if err != nil {
		return Amount{}, err
	}
	if minorDigits < 0 || minorDigits > scale {
		return Amount{}, fmt.Errorf("%w: minor digits must be 0..%d", ErrBadAmount, scale)
	}
	units := big.NewInt(value)
	factor := new(big.Int).Exp(big.NewInt(10), big.NewInt(int64(scale-minorDigits)), nil)
	units.Mul(units, factor)
	return Amount{units: *units, currency: currency}, nil
}

func ValidateCurrency(currency string) error {
	if currency == "" {
		return ErrNoCurrency
	}
	if !currencyPattern.MatchString(currency) {
		return fmt.Errorf("%w: %q", ErrBadCurrency, currency)
	}
	return nil
}

func (a Amount) Currency() string { return a.currency }

// IsZero reports whether the amount is zero. A zero amount still carries its
// currency; the zero VALUE of the struct does not, and [Amount.Valid] separates them.
func (a Amount) IsZero() bool { return a.units.Sign() == 0 }

// Valid reports whether this is a usable amount rather than the struct's zero value.
func (a Amount) Valid() bool { return a.currency != "" }

func (a Amount) Sign() int { return a.units.Sign() }

// String is the wire and display form: a plain decimal with no separators and no trailing zeros.
func (a Amount) String() string {
	if a.currency == "" {
		return ""
	}
	units := new(big.Int).Abs(&a.units)
	whole := new(big.Int)
	frac := new(big.Int)
	whole.QuoRem(units, scaleFactor, frac)

	out := whole.String()
	fracStr := strings.TrimRight(fmt.Sprintf("%0*d", scale, frac), "0")
	if fracStr != "" {
		out += "." + fracStr
	}
	if a.units.Sign() < 0 {
		out = "-" + out
	}
	return out
}

// Add returns a+b, or an error when the currencies differ.
func (a Amount) Add(b Amount) (Amount, error) {
	err := a.sameCurrency(b)
	if err != nil {
		return Amount{}, err
	}
	var sum big.Int
	sum.Add(&a.units, &b.units)
	return Amount{units: sum, currency: a.currency}, nil
}

// Sub returns a-b, or an error when the currencies differ.
func (a Amount) Sub(b Amount) (Amount, error) {
	err := a.sameCurrency(b)
	if err != nil {
		return Amount{}, err
	}
	var diff big.Int
	diff.Sub(&a.units, &b.units)
	return Amount{units: diff, currency: a.currency}, nil
}

// Mul multiplies by an integer factor — a quantity, not a rate. It cannot change
// the currency and cannot lose precision, so it does not need a rounding mode.
func (a Amount) Mul(factor int64) Amount {
	var product big.Int
	product.Mul(&a.units, big.NewInt(factor))
	return Amount{units: product, currency: a.currency}
}

// MulRate multiplies by a decimal rate and rounds to the internal scale. The mode is a parameter because the correct
// one is a property of the calculation.
func (a Amount) MulRate(rate string, mode Rounding) (Amount, error) {
	rateUnits, err := parseRate(rate)
	if err != nil {
		return Amount{}, err
	}
	// The amount is scaled by 10^scale and the rate by 10^rateScale, so the product
	// carries both and the rate's factor is divided back out.
	var product big.Int
	product.Mul(&a.units, rateUnits)
	rounded := divRound(&product, rateScaleFactor, mode)
	return Amount{units: *rounded, currency: a.currency}, nil
}

// parseRate reads a decimal rate at rateScale precision.
func parseRate(rate string) (*big.Int, error) {
	if !amountPattern.MatchString(rate) {
		return nil, fmt.Errorf("%w: %q", ErrBadAmount, rate)
	}
	negative := strings.HasPrefix(rate, "-")
	whole, frac, _ := strings.Cut(strings.TrimPrefix(rate, "-"), ".")
	if len(frac) > rateScale {
		return nil, fmt.Errorf("%w: more than %d decimal places in rate %q", ErrBadAmount, rateScale, rate)
	}
	frac += strings.Repeat("0", rateScale-len(frac))

	units, ok := new(big.Int).SetString(whole+frac, 10)
	if !ok {
		return nil, fmt.Errorf("%w: %q", ErrBadAmount, rate)
	}
	if negative {
		units.Neg(units)
	}
	return units, nil
}

// Div divides into n equal parts, rounding each. Prefer [Amount.Split] when the parts must sum back: the remainder is
// money.
func (a Amount) Div(n int64, mode Rounding) (Amount, error) {
	if n == 0 {
		return Amount{}, ErrDivideByZero
	}
	quotient := divRound(&a.units, big.NewInt(n), mode)
	return Amount{units: *quotient, currency: a.currency}, nil
}

// Split divides into n parts that sum exactly back to the original, distributing the indivisible remainder one
// minor unit at a time. Splitting 10.00 three ways gives 9.99, and the missing cent has to land somewhere.
func (a Amount) Split(n int) ([]Amount, error) {
	if n <= 0 {
		return nil, ErrDivideByZero
	}
	parts := make([]Amount, n)
	divisor := big.NewInt(int64(n))

	base := new(big.Int)
	remainder := new(big.Int)
	base.QuoRem(&a.units, divisor, remainder)

	// QuoRem truncates toward zero, so a negative amount leaves a negative
	// remainder; the leading parts then absorb it in the same direction.
	step := big.NewInt(1)
	if remainder.Sign() < 0 {
		step = big.NewInt(-1)
		remainder.Neg(remainder)
	}

	for i := range parts {
		units := new(big.Int).Set(base)
		if int64(i) < remainder.Int64() {
			units.Add(units, step)
		}
		parts[i] = Amount{units: *units, currency: a.currency}
	}
	return parts, nil
}

func (a Amount) Cmp(b Amount) (int, error) {
	err := a.sameCurrency(b)
	if err != nil {
		return 0, err
	}
	return a.units.Cmp(&b.units), nil
}

// Equal reports exact equality, currency included. Two amounts in different
// currencies are never equal, and this is the one comparison that does not error
// on a mismatch — the answer is simply false.
func (a Amount) Equal(b Amount) bool {
	return a.currency == b.currency && a.units.Cmp(&b.units) == 0
}

func (a Amount) Neg() Amount {
	var negated big.Int
	negated.Neg(&a.units)
	return Amount{units: negated, currency: a.currency}
}

func (a Amount) Abs() Amount {
	var abs big.Int
	abs.Abs(&a.units)
	return Amount{units: abs, currency: a.currency}
}

func (a Amount) sameCurrency(b Amount) error {
	if a.currency != b.currency {
		return fmt.Errorf("%w: %s and %s", ErrCurrencyMismatch, a.currency, b.currency)
	}
	return nil
}

// divRound divides and applies the rounding mode to the remainder.
func divRound(numerator, denominator *big.Int, mode Rounding) *big.Int {
	quotient := new(big.Int)
	remainder := new(big.Int)
	quotient.QuoRem(numerator, denominator, remainder)
	if remainder.Sign() == 0 {
		return quotient
	}

	negative := (numerator.Sign() < 0) != (denominator.Sign() < 0)
	if mode == Down {
		return quotient // QuoRem already truncates toward zero
	}

	// Compare |remainder|*2 against |denominator| to classify the tie.
	twice := new(big.Int).Abs(remainder)
	twice.Lsh(twice, 1)
	comparison := twice.Cmp(new(big.Int).Abs(denominator))

	roundAway := false
	switch {
	case comparison > 0:
		roundAway = true
	case comparison == 0:
		if mode == HalfUp {
			roundAway = true
		} else {
			// HalfEven: round to the neighbour with an even last digit.
			roundAway = quotient.Bit(0) == 1
		}
	}

	if roundAway {
		if negative {
			quotient.Sub(quotient, big.NewInt(1))
		} else {
			quotient.Add(quotient, big.NewInt(1))
		}
	}
	return quotient
}
