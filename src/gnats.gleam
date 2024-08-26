import gleam/bit_array
import gleam/erlang/process
import gleam/io
import gleam/option
import gnats/internal
import mug

pub fn main() {
  process.start(fn() { start_client("100.125.121.45", 4222) }, True)

  process.sleep_forever()
}

type State {
  State(buffer: BitArray, socket: mug.Socket, wait_ok: Bool)
}

fn start_client(host, port) {
  let assert Ok(socket) =
    mug.new(host, port)
    |> mug.connect()

  loop(State(<<>>, socket, wait_ok: False))
}

fn send(state: State, msg: internal.ClientMessage) {
  let msg_str = internal.client_msg_to_string(msg)
  io.debug("<< " <> msg_str)
  case mug.send(state.socket, bit_array.from_string(msg_str)) {
    Ok(_) -> state
    Error(_) -> state
  }
}

fn handle_message(state: State, msg: internal.ServerMessage) -> State {
  case state, msg {
    State(wait_ok: True, ..), internal.OK -> {
      send(state, internal.Subscribe("naboo.nmea", "3829", option.None))
      State(..state, wait_ok: False)
    }
    _, internal.Info(..) -> {
      send(state, internal.Connect(""))
      State(..state, wait_ok: True)
    }
    _, internal.Ping -> {
      send(state, internal.Pong)
      state
    }
    _, internal.Msg(payload:, ..) -> {
      io.debug(payload)
      state
    }
    _, msg -> {
      io.debug(#("unhandled msg", msg))
      state
    }
  }
}

fn loop(state: State) {
  case mug.receive(state.socket, 1000) {
    Ok(chunk) -> {
      case internal.parse(bit_array.append(state.buffer, chunk)) {
        Ok(#(msg, rest)) -> {
          handle_message(State(..state, buffer: rest), msg)
        }
        Error(rest) -> State(..state, buffer: rest)
      }
    }
    _ -> state
  }
  |> loop()
}
