///|
fn optional_string(value : String?) -> Json {
  match value {
    Some(text) => Json(text)
    None => Json(null)
  }
}

///|
fn command_error(kind : String, message : String) -> Json {
  Json::object({ "kind": Json(kind), "message": Json(message) })
}
