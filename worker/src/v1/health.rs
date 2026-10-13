use worker::{Response, Result};

pub(super) fn get() -> Result<Response> {
    Response::from_json(&serde_json::json!({ "status": "ok" }))
}
