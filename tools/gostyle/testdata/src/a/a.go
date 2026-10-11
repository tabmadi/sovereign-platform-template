package a

func f(args ...int) {}

func calls(xs []int) {
	f(1, 2, 3)
	f(
		1,
		2,
	)
	f(1, // want "call arguments are partially broken across lines"
		2)
	f( // want "call arguments are partially broken across lines"
		1, 2,
	)
	f( // want "call arguments are partially broken across lines"
		xs...)
}
