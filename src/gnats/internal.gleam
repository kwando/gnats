import gleam/bit_array
import gleam/option
import gleam/result
import gleam/string
import utils

pub type ServerMessage {
  Info(String)
  Ping
  OK
  Msg(
    topic: String,
    subscription: String,
    reply_to: option.Option(String),
    payload: BitArray,
  )
}

pub type ClientMessage {
  Connect(String)
  Subscribe(subject: String, sid: String, queue_group: option.Option(String))
  Publish(
    subject: String,
    sid: String,
    queue_group: option.Option(String),
    payload: BitArray,
  )
  Pong
}

pub fn client_msg_to_string(msg: ClientMessage) -> String {
  case msg {
    Pong -> "PONG\r\n"
    Connect(..) -> "CONNECT {}\r\n"
    Subscribe(subject:, sid:, queue_group: option.None) -> {
      "SUB " <> subject <> " " <> sid <> "\r\n"
    }
    Subscribe(subject:, sid:, queue_group: option.Some(group)) -> {
      "SUB " <> subject <> " " <> group <> " " <> sid <> "\r\n"
    }
    _ -> todo
  }
}

pub fn parse(bits) {
  case bits {
    <<"INFO", _:bits>> -> {
      case utils.split_on_newline(bits, <<>>) {
        Ok(#(line, rest)) -> {
          let assert Ok(msg) = bit_array.to_string(line)
          let assert Ok(#("INFO", json)) = string.split_once(msg, " ")
          Ok(#(Info(json), rest))
        }
        Error(rest) -> Error(rest)
      }
    }
    <<"PING", _:bits>> -> {
      case utils.split_on_newline(bits, <<>>) {
        Ok(#(_, rest)) -> Ok(#(Ping, rest))
        Error(rest) -> Error(rest)
      }
    }
    <<"+OK", _:bits>> -> {
      case utils.split_on_newline(bits, <<>>) {
        Ok(#(_, rest)) -> Ok(#(OK, rest))
        Error(rest) -> Error(rest)
      }
    }
    <<"MSG", _:bits>> -> {
      use #(lines, rest) <- result.try(utils.take_lines(bits, 2))

      let assert [first, payload] = lines
      let assert Ok(first) = bit_array.to_string(first)

      case string.split(first, " ") {
        [_sub, topic, subscription, _bytes] ->
          Ok(#(Msg(topic, subscription, option.None, payload), rest))
        [_sub, topic, subscription, reply_to, _bytes] ->
          Ok(#(Msg(topic, subscription, option.Some(reply_to), payload), rest))
        _ -> panic as "protocol error"
      }
    }
    msg -> {
      Error(msg)
    }
  }
}
