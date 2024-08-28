import gleam/list

pub fn split_on_newline(ba) {
  split_on_newline_(ba, <<>>)
}

fn split_on_newline_(ba, acc) {
  case ba, acc {
    <<>>, acc -> Error(acc)
    <<"\r\n", rest:bits>>, acc -> Ok(#(acc, rest))
    <<char, rest:bits>>, acc -> split_on_newline_(rest, <<acc:bits, char>>)
    _, _ -> panic as "tadas"
  }
}

pub fn take_lines(data, num: Int) {
  case take_lines_(data, num, []) {
    Error(_) -> Error(data)
    Ok(#(lines, rest)) -> Ok(#(lines, rest))
  }
}

pub fn take_lines_(data, num: Int, acc: List(BitArray)) {
  case num {
    0 -> Ok(#(list.reverse(acc), data))
    n if n > 0 -> {
      case split_on_newline(data) {
        Ok(#(line, rest)) -> take_lines_(rest, n - 1, [line, ..acc])
        Error(_) -> Error(Nil)
      }
    }
    _ -> panic as "num cannot be negative"
  }
}

pub fn get_bytes(bytes, number_of_bytes) {
  get_bytes_(bytes, number_of_bytes, <<>>)
}

fn get_bytes_(bytes, number_of_bytes, acc) {
  case number_of_bytes {
    0 -> Ok(#(acc, bytes))
    n -> {
      case bytes {
        <<>> -> Error(Nil)
        <<a, rest:bits>> -> get_bytes_(rest, n - 1, <<acc:bits, a>>)
        _ -> panic
      }
    }
  }
}

pub fn consume_whitespace(data) {
  case data {
    <<" ", rest:bits>> -> consume_whitespace(rest)
    <<"\t", rest:bits>> -> consume_whitespace(rest)
    data -> data
  }
}
