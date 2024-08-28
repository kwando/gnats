import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import utils

pub type Headers =
  List(#(String, String))

pub type ServerMessage {
  Info(String)
  Ping
  OK
  ERR(String)
  Msg(
    topic: String,
    subscription: String,
    headers: Headers,
    reply_to: option.Option(String),
    payload: BitArray,
  )
}

pub type ClientMessage {
  Connect(String)
  Subscribe(subject: String, sid: String, queue_group: option.Option(String))
  Publish(
    subject: String,
    headers: Headers,
    reply_to: option.Option(String),
    payload: BitArray,
  )
  Pong
  Unsubscribe(sid: String, max_messages: option.Option(Int))
}

pub fn client_msg_to_string(msg: ClientMessage) -> BitArray {
  case msg {
    Pong -> <<"PONG\r\n">>
    Connect(..) -> <<"CONNECT {}\r\n">>
    Subscribe(subject:, sid:, queue_group: option.None) -> {
      bit_array.from_string("SUB " <> subject <> " " <> sid <> "\r\n")
    }
    Subscribe(subject:, sid:, queue_group: option.Some(group)) -> {
      bit_array.from_string(
        "SUB " <> subject <> " " <> group <> " " <> sid <> "\r\n",
      )
    }
    Publish(subject:, headers: [], reply_to:, payload:) -> {
      let payload_bytes = bit_array.byte_size(payload)
      bit_array.from_string(
        { "PUB " <> subject }
        |> maybe_append(reply_to)
        <> " "
        <> int.to_string(payload_bytes)
        <> "\r\n",
      )
      |> bit_array.append(payload)
      |> bit_array.append(<<"\r\n">>)
    }
    Publish(subject:, headers:, reply_to:, payload:) -> {
      let payload_bytes = bit_array.byte_size(payload)
      let header_str = headers_to_string(headers)
      let header_bytes = string.byte_size(header_str)

      bit_array.from_string(
        { "HPUB " <> subject }
        |> maybe_append(reply_to)
        <> " "
        <> int.to_string(header_bytes + 2)
        <> " "
        <> int.to_string(payload_bytes + header_bytes + 2)
        <> "\r\n"
        <> header_str
        <> "\r\n",
      )
      |> bit_array.append(payload)
      |> bit_array.append(<<"\r\n">>)
    }
    Unsubscribe(sid:, max_messages:) -> {
      maybe_append("UNSUB " <> sid, max_messages |> option.map(int.to_string))
      |> bit_array.from_string
      |> bit_array.append(<<"\r\n">>)
    }
  }
}

fn maybe_append(line: String, optional: option.Option(String)) {
  case optional {
    option.None -> line
    option.Some(value) -> line <> " " <> value
  }
}

pub type ParseError {
  NeedsMoreData(BitArray)
  ProtocolError(String, BitArray)
}

pub fn parse(bits) -> Result(#(ServerMessage, BitArray), ParseError) {
  case bits {
    <<"INFO", _:bits>> -> {
      use line, rest <- take_line(bits)
      let assert Ok(msg) = bit_array.to_string(line)
      let assert Ok(#("INFO", json)) = string.split_once(msg, " ")
      Ok(#(Info(json), rest))
    }

    <<"PING\r\n", rest:bits>> -> {
      Ok(#(Ping, rest))
    }

    <<"+OK\r\n", rest:bits>> -> {
      Ok(#(OK, rest))
    }
    <<"-ERR ", _:bits>> -> {
      use line, rest <- take_line(bits)
      let assert Ok(line) = bit_array.to_string(line)
      let assert Ok(#(_, error_message)) = string.split_once(line, " ")
      Ok(#(ERR(error_message), rest))
    }

    <<"MSG", _:bits>> -> {
      use line, rest <- take_line(bits)

      let assert Ok(line) = bit_array.to_string(line)
      case string.split(line, " ") {
        [_sub, topic, subscription, bytes_to_read] -> {
          parse_message(
            topic,
            subscription,
            option.None,
            <<>>,
            bytes_to_read,
            rest,
            bits,
          )
        }

        [_sub, topic, subscription, reply_to, bytes_to_read] -> {
          parse_message(
            topic,
            subscription,
            option.Some(reply_to),
            <<>>,
            bytes_to_read,
            rest,
            bits,
          )
        }

        _ -> Error(ProtocolError("expected 4 or 5 fields", bits))
      }
    }

    <<"HMSG ", _:bits>> -> {
      use line, rest <- take_line(bits)

      let assert Ok(line) = bit_array.to_string(line)
      case string.split(line, " ") {
        [_hmsg, topic, subscription, header_bytes_str, total_bytes_str] -> {
          use header_bytes <- result.try(
            int.parse(header_bytes_str)
            |> result.replace_error(ProtocolError(
              "integer expected for paload size",
              bits,
            )),
          )
          use total_bytes <- result.try(
            int.parse(total_bytes_str)
            |> result.replace_error(ProtocolError(
              "integer expected for paload size",
              bits,
            )),
          )

          use #(header_str, rest) <- result.try(take_bytes(
            rest,
            header_bytes - 2,
            bits,
          ))

          parse_message(
            topic,
            subscription,
            option.None,
            header_str,
            int.to_string(total_bytes - header_bytes),
            rest,
            bits,
          )
        }

        segs ->
          Error(ProtocolError(
            "expected 4 or 5 fields but got "
              <> int.to_string(list.length(segs)),
            bits,
          ))
      }
    }

    msg -> {
      Error(NeedsMoreData(msg))
    }
  }
}

fn take_line(bits, callback) {
  case utils.split_on_newline(bits) {
    Ok(#(line, rest)) -> callback(line, rest)
    _ -> Error(NeedsMoreData(bits))
  }
}

fn headers_to_string(headers: Headers) {
  "NATS/1.0\r\n"
  <> list.fold(headers, "", fn(acc, pair) {
    let #(k, v) = pair
    acc <> k <> ": " <> v <> "\r\n"
  })
}

fn parse_message(
  topic,
  subscription,
  reply_to: option.Option(String),
  header_str: BitArray,
  bytes_str,
  rest,
  bits,
) {
  use bytes_to_read <- result.try(
    int.parse(bytes_str)
    |> result.replace_error(ProtocolError(
      "integer expected for paload size",
      bits,
    )),
  )
  use #(payload, rest) <- result.try(take_bytes(rest, bytes_to_read, bits))
  use headers <- result.try(
    parse_headers(header_str)
    |> result.replace_error(ProtocolError("could not parse headers", bits)),
  )

  Ok(#(Msg(topic, subscription, headers, reply_to, payload), rest))
}

fn parse_headers(header_str) -> Result(List(#(String, String)), Nil) {
  case header_str {
    <<>> -> Ok([])
    <<"NATS/1.0\r\n", rest:bits>> -> {
      let assert Ok(headers) = bit_array.to_string(rest)

      headers
      |> string.trim()
      |> string.split("\r\n")
      |> list.map(fn(line) {
        let assert Ok(#(k, v)) = string.split_once(line, ":")

        #(k, string.trim(v))
      })
      |> Ok
    }
    _ -> Error(Nil)
  }
}

fn take_bytes(rest, count: Int, bits) {
  use #(bytes, rest) <- result.try(
    utils.get_bytes(rest, count) |> result.replace_error(NeedsMoreData(bits)),
  )
  use rest <- result.try(consume_end_of_line(rest, bits))
  Ok(#(bytes, rest))
}

fn consume_end_of_line(rest, bits) {
  case rest {
    <<>> -> Error(NeedsMoreData(bits))
    <<_>> -> Error(NeedsMoreData(bits))
    <<"\r\n", rest:bits>> -> Ok(rest)
    _ -> Error(ProtocolError("payload should be terminated with \\r\\n", bits))
  }
}
