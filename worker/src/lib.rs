mod data;
mod db;
mod utils;
mod v1;

pub(crate) use data::*;
pub(crate) use utils::*;

use worker::*;

#[event(fetch)]
async fn fetch(mut request: Request, env: Env, _ctx: Context) -> Result<Response> {
    let path = request.path();
    let method = request.method();
    let response = v1::route(&method, &path, &mut request, &env).await?;
    secure_headers(response)
}
