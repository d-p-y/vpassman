module model

[heap]
struct Maybe[T] {
pub:
	has_value bool
	value     T
}

pub fn new_maybe_some[T](some_value T) Maybe[T] {
	return Maybe[T]{
		has_value: true
		value: some_value
	}
}

pub fn new_maybe_none[T]() Maybe[T] {
	return Maybe[T]{
		has_value: false
	}
}
