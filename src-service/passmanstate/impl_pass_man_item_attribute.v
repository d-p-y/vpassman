module passmanstate

pub fn (t PassManItemAttribute) get_field_value_as_string(field CustomAttrField) !string {
	match field {
		.name {
			match t.identifier {
				AttributeIdentifierStandard {
					return error('not allowed to get serialized name of standard attribute')
				}
				AttributeIdentifierCustom {
					return t.identifier.attribute_name
				}
			}
		}
		.value {
			return t.value
		}
	}
}

pub fn (mut t PassManItemAttribute) set_field_value_from_string(field CustomAttrField, str_value string) ! {
	match field {
		.name {
			match t.identifier {
				AttributeIdentifierStandard {
					return error('not allowed to set name for standard attribute')
				}
				AttributeIdentifierCustom {
					// cannot mutate directly due to bug https://github.com/vlang/v/issues/16506

					t.identifier = AttributeIdentifierCustom{
						attribute_name: str_value
					}
					return
				}
			}
		}
		.value {
			t.value = str_value
			return
		}
	}
}
