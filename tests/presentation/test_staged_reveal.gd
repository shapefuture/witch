extends TestCase

# A plaque's inspection reveal in layers (ROOM_OF_US item 3): evocative line, surprise, memory, connection, one per tap,
# in that order whatever order the data was written in.

func test_layers_come_in_the_fixed_order_whatever_order_they_were_written() -> void:
	var reveal := StagedReveal.new({"connection": "c", "evocative": "e", "surprise": "s"})
	eq(reveal.layer_count(), 3, "three layers")
	eq(reveal.current(), "e", "the evocative line first")
	ok(reveal.advance(), "a tap reveals the next layer")
	eq(reveal.current(), "s", "then the surprise")
	ok(reveal.advance(), "another tap")
	eq(reveal.current(), "c", "then the connection")
	ok(reveal.at_last(), "that is the last layer")
	ok(not reveal.advance(), "nothing comes after the last layer")
	eq(reveal.current(), "c", "and the last layer stays on the plaque")

func test_an_object_with_one_layer_or_none() -> void:
	var one := StagedReveal.new({"evocative": "e"})
	ok(one.at_last(), "one layer is already the last")
	ok(not one.advance(), "no more to reveal")
	var none := StagedReveal.new({})
	eq(none.current(), "", "no layers, no text")
	ok(none.at_last(), "and nothing to reveal")

func test_a_layer_the_order_does_not_name_is_ignored() -> void:
	var reveal := StagedReveal.new({"rumour": "r", "memory": "m"})
	eq(reveal.layer_count(), 1, "a layer the order does not name is not shown")
	eq(reveal.current(), "m", "the known layer is")
