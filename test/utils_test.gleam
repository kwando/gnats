import gleeunit/should
import utils

pub fn get_byte_test() {
  utils.get_bytes(<<1, 2, 3, 4, 5>>, 3)
  |> should.be_ok
  |> should.equal(#(<<1, 2, 3>>, <<4, 5>>))
}

pub fn take_lines_test() {
  utils.take_lines(<<"AAA\r\nBBB\r\nCCC\r\n">>, 2)
  |> should.be_ok
  |> should.equal(#([<<"AAA">>, <<"BBB">>], <<"CCC\r\n">>))
}
