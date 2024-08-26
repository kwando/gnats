import gleam/option
import gleeunit
import gleeunit/should
import gnats/internal.{Info, Msg, OK, Ping, parse}
import utils

pub fn main() {
  gleeunit.main()
}

// gleeunit test functions end in `_test`
pub fn hello_world_test() {
  utils.split_on_newline(<<"hello\r\nworld\r\n">>, <<>>)
  |> should.be_ok
  |> should.equal(#(<<"hello">>, <<"world\r\n">>))

  utils.split_on_newline(<<"hello">>, <<>>)
  |> should.be_error
  |> should.equal(<<"hello">>)
}

fn parse_sequence(bits) {
  case parse(bits) {
    Ok(#(msg, rest)) -> {
      let #(msgs, rest) = parse_sequence(rest)
      #([msg, ..msgs], rest)
    }
    Error(rest) -> #([], rest)
  }
}

pub fn parse_test() {
  parse_sequence(<<"INFO {}\r\nPING\r\n+OK\r\nPING">>)
  |> should.equal(#([Info("{}"), Ping, OK], <<"PING">>))

  parse_sequence(<<"MSG sub.topic 3289 0\r\n\r\n">>)
  |> should.equal(
    #(
      [
        Msg(
          topic: "sub.topic",
          subscription: "3289",
          reply_to: option.None,
          payload: <<>>,
        ),
      ],
      <<>>,
    ),
  )
}

pub fn take_lines_test() {
  utils.take_lines(<<"AAA\r\nBBB\r\nCCC\r\n">>, 2)
  |> should.be_ok
  |> should.equal(#([<<"AAA">>, <<"BBB">>], <<"CCC\r\n">>))
}
