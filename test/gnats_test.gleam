import gleam/option
import gleeunit
import gleeunit/should
import gnats/internal.{Info, Msg, OK, Ping, client_msg_to_string, parse}
import utils

pub fn main() {
  gleeunit.main()
}

// gleeunit test functions end in `_test`
pub fn hello_world_test() {
  utils.split_on_newline(<<"hello\r\nworld\r\n">>)
  |> should.be_ok
  |> should.equal(#(<<"hello">>, <<"world\r\n">>))

  utils.split_on_newline(<<"hello">>)
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
  parse_sequence(<<
    "INFO {}\r\nPING\r\n+OK\r\n-ERR this is an error message\r\nPING",
  >>)
  |> should.equal(#(
    [Info("{}"), Ping, OK, internal.ERR("this is an error message")],
    internal.NeedsMoreData(<<"PING">>),
  ))

  parse_sequence(<<"MSG sub.topic 3289 0\r\n\r\n">>)
  |> should.equal(#(
    [
      Msg(
        topic: "sub.topic",
        subscription: "3289",
        reply_to: option.None,
        payload: <<>>,
        headers: [],
      ),
    ],
    internal.NeedsMoreData(<<>>),
  ))

  parse_sequence(<<"MSG sub.topic 3289 473.3472-reply 11\r\nhello world\r\n">>)
  |> should.equal(#(
    [
      Msg(
        topic: "sub.topic",
        subscription: "3289",
        reply_to: option.Some("473.3472-reply"),
        payload: <<"hello world">>,
        headers: [],
      ),
    ],
    internal.NeedsMoreData(<<>>),
  ))

  // should ignore \r\n inside the payload
  parse_sequence(<<
    "MSG sub.topic 3289 473.3472-reply 12\r\nhello\r\nworld\r\n",
  >>)
  |> should.equal(#(
    [
      Msg(
        topic: "sub.topic",
        subscription: "3289",
        headers: [],
        reply_to: option.Some("473.3472-reply"),
        payload: <<"hello\r\nworld">>,
      ),
    ],
    internal.NeedsMoreData(<<>>),
  ))

  // invalid bytes length
  parse_sequence(<<"MSG sub.topic 3289 473.3472-reply 10\r\nhello world\r\n">>)
  |> should.equal(#(
    [],
    internal.ProtocolError("payload should be terminated with \\r\\n", <<
      "MSG sub.topic 3289 473.3472-reply 10\r\nhello world\r\n",
    >>),
  ))
}

pub fn parse_hmsg_test() {
  parse_sequence(<<
    "HMSG FOO.BAR sub32 34 45\r\nNATS/1.0\r\nFoodGroup: vegetable\r\n\r\nHello World\r\n",
  >>)
  |> should.equal(#(
    [
      Msg(
        topic: "FOO.BAR",
        subscription: "sub32",
        reply_to: option.None,
        headers: [#("FoodGroup", "vegetable")],
        payload: <<"Hello World">>,
      ),
    ],
    internal.NeedsMoreData(<<>>),
  ))
}

pub fn client_msg_to_string_test() {
  client_msg_to_string(internal.Unsubscribe("324", option.Some(5)))
  |> should.equal(<<"UNSUB 324 5\r\n">>)

  client_msg_to_string(internal.Unsubscribe("324", option.None))
  |> should.equal(<<"UNSUB 324\r\n">>)

  client_msg_to_string(internal.Publish(
    subject: "FOO",
    headers: [#("Bar", "Baz")],
    payload: <<"Hello NATS!">>,
    reply_to: option.None,
  ))
  |> should.equal(<<
    "HPUB FOO 22 33\r\nNATS/1.0\r\nBar: Baz\r\n\r\nHello NATS!\r\n",
  >>)
}
