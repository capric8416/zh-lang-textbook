mod accounts;
mod auth;
mod bootstrap;
mod classes;
mod health;
mod me;
mod practice;

use worker::{Env, Method, Request, Response, Result};

pub async fn route(
    method: &Method,
    path: &str,
    request: &mut Request,
    env: &Env,
) -> Result<Response> {
    match (method, path) {
        (Method::Options, _) => Response::empty(),
        (Method::Get, "/api/v1/health") => health::get(),
        (Method::Post, "/api/v1/bootstrap") => bootstrap::create(request, env).await,
        (Method::Post, "/api/v1/auth/register") => auth::register(request, env).await,
        (Method::Post, "/api/v1/auth/parameters") => auth::parameters(request, env).await,
        (Method::Post, "/api/v1/auth/login") => auth::login(request, env).await,
        (Method::Post, "/api/v1/auth/logout") => auth::logout(request, env).await,
        (Method::Get, "/api/v1/me") => me::get(request, env).await,
        (Method::Patch, "/api/v1/me") => me::update_profile(request, env).await,
        (Method::Post, "/api/v1/me/password") => me::change_password(request, env).await,
        (Method::Delete, "/api/v1/me/class") => me::leave_class(request, env).await,
        (Method::Post, "/api/v1/practice/records") => practice::record(request, env).await,
        (Method::Get, "/api/v1/practice/records") => practice::student_records(request, env).await,
        (Method::Get, path)
            if path.starts_with("/api/v1/classes/")
                && path.ends_with("/records")
                && !path.contains("/students/") =>
        {
            let class_id = &path[16..path.len() - "/records".len()];
            practice::class_records(request, env, class_id).await
        }
        (Method::Get, "/api/v1/accounts/tree") => accounts::tree(request, env).await,
        (Method::Post, "/api/v1/accounts") => accounts::create(request, env).await,
        (Method::Patch, path) if path.starts_with("/api/v1/accounts/") => {
            accounts::patch(request, env, &path[17..]).await
        }
        (Method::Post, "/api/v1/classes") => classes::create(request, env).await,
        (Method::Get, "/api/v1/classes") => classes::list(request, env).await,
        (Method::Patch, path) if path.starts_with("/api/v1/classes/") => {
            let class_id = &path[16..];
            if class_id.is_empty() || class_id.contains('/') {
                Response::error("not found", 404)
            } else {
                classes::rename(request, env, class_id).await
            }
        }
        (Method::Post, "/api/v1/classes/join-code") => {
            classes::create_join_code(request, env).await
        }
        (Method::Post, "/api/v1/classes/join") => classes::join(request, env).await,
        (Method::Delete, path) if path.starts_with("/api/v1/classes/members/") => {
            classes::remove_member(request, env, &path["/api/v1/classes/members/".len()..]).await
        }
        (Method::Get, path)
            if path.starts_with("/api/v1/classes/") && path.ends_with("/blacklist") =>
        {
            let class_id = &path[16..path.len() - "/blacklist".len()];
            classes::list_blacklist(request, env, class_id).await
        }
        (Method::Delete, path) if path.starts_with("/api/v1/classes/") => {
            if let Some((class_id, student_id)) = path[16..].split_once("/blacklist/") {
                classes::unblacklist(request, env, class_id, student_id).await
            } else {
                Response::error("not found", 404)
            }
        }
        _ => Response::error("not found", 404),
    }
}
