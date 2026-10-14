use super::auth::current_account;
use crate::*;
use serde::Deserialize;
use worker::{Env, Request, Response, Result};

#[derive(Deserialize)]
struct ClassInput {
    name: String,
}

#[derive(Deserialize)]
struct ClassNameUpdate {
    name: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct JoinInput {
    code: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct JoinCodeInput {
    class_id: String,
}

pub(super) async fn create(request: &mut Request, env: &Env) -> Result<Response> {
    let Some(user) = current_account(request, env).await? else {
        return error("unauthorized", 401);
    };
    if user.role != "class_admin" {
        return error("forbidden", 403);
    }
    let input: ClassInput = match read_json(request).await {
        Ok(v) => v,
        Err(_) => return error("invalid request", 400),
    };
    let name = input.name.trim();
    if name.chars().count() < 2 || name.chars().count() > 60 {
        return error("class name must be 2-60 characters", 400);
    }
    let id = uuid();
    let db = env.d1("DB")?;
    let school_admin_id = crate::db::accounts::parent_id(&db, &user.id).await?;
    crate::db::classes::create(&db, &id, name, &user.id, &school_admin_id).await?;
    Response::from_json(&serde_json::json!({"id":id,"name":name})).map(|r| r.with_status(201))
}

pub(super) async fn list(request: &Request, env: &Env) -> Result<Response> {
    let Some(user) = current_account(request, env).await? else {
        return error("unauthorized", 401);
    };
    let db = env.d1("DB")?;
    let rows = if user.role == "student" {
        crate::db::class_memberships::find_for_student(&db, &user.id)
            .await?
            .into_iter()
            .collect::<Vec<_>>()
    } else if user.role == "class_admin" {
        crate::db::classes::list_for_admin(&db, &user.id).await?
    } else {
        return error("forbidden", 403);
    };
    Response::from_json(&serde_json::json!({"classes":rows}))
}

pub(super) async fn rename(request: &mut Request, env: &Env, class_id: &str) -> Result<Response> {
    let Some(user) = current_account(request, env).await? else {
        return error("unauthorized", 401);
    };
    if user.role != "class_admin" {
        return error("forbidden", 403);
    }
    let input: ClassNameUpdate = match read_json(request).await {
        Ok(value) => value,
        Err(_) => return error("invalid request", 400),
    };
    let name = input.name.trim();
    if name.chars().count() < 2 || name.chars().count() > 60 {
        return error("class name must be 2-60 characters", 400);
    }
    let db = env.d1("DB")?;
    if !crate::db::classes::exists_for_admin(&db, class_id, &user.id).await? {
        return error("class not found", 404);
    }
    crate::db::classes::set_name(&db, class_id, &user.id, name).await?;
    Response::from_json(&serde_json::json!({"id":class_id,"name":name}))
}

pub(super) async fn create_join_code(request: &mut Request, env: &Env) -> Result<Response> {
    let Some(user) = current_account(request, env).await? else {
        return error("unauthorized", 401);
    };
    if user.role != "class_admin" {
        return error("forbidden", 403);
    }
    let input: JoinCodeInput = match read_json(request).await {
        Ok(v) => v,
        Err(_) => return error("invalid request", 400),
    };
    let db = env.d1("DB")?;
    if !crate::db::classes::exists_for_admin(&db, &input.class_id, &user.id).await? {
        return error("class not found", 404);
    }
    let code = random_hex(12);
    let expiry = now() + 7 * 86400;
    crate::db::class_join_codes::create(&db, &code, &input.class_id, &user.id, expiry).await?;
    Response::from_json(&serde_json::json!({"code":code,"expiresAt":expiry}))
        .map(|r| r.with_status(201))
}

pub(super) async fn join(request: &mut Request, env: &Env) -> Result<Response> {
    let Some(user) = current_account(request, env).await? else {
        return error("unauthorized", 401);
    };
    if user.role != "student" {
        return error("only student accounts can join a class", 403);
    }
    let input: JoinInput = match read_json(request).await {
        Ok(v) => v,
        Err(_) => return error("invalid request", 400),
    };
    let raw = input.code.trim();
    let code = raw.strip_prefix("join:").unwrap_or(raw);
    let db = env.d1("DB")?;
    let class = crate::db::class_join_codes::find_valid_class(&db, code, now()).await?;
    let Some(class) = class else {
        return error("invalid or expired class QR", 404);
    };
    if crate::db::class_blacklist::contains(&db, &class.id, &user.id).await? {
        return error("你已被此班级移出并加入黑名单，暂时无法重新加入", 403);
    }
    crate::db::class_memberships::assign(&db, &user.id, &class.id).await?;
    Response::from_json(&serde_json::json!({"class":class}))
}

pub(super) async fn remove_member(
    request: &Request,
    env: &Env,
    student_id: &str,
) -> Result<Response> {
    let Some(user) = current_account(request, env).await? else {
        return error("unauthorized", 401);
    };
    if user.role != "class_admin" {
        return error("forbidden", 403);
    }
    let db = env.d1("DB")?;
    let Some(student) = crate::db::accounts::find_by_id(&db, student_id).await? else {
        return error("student not found", 404);
    };
    if student.role != "student" {
        return error("student not found", 404);
    }
    let Some(class_id) =
        crate::db::class_memberships::find_class_for_student(&db, student_id).await?
    else {
        return error("student is not in a class", 404);
    };
    if !crate::db::classes::exists_for_admin(&db, &class_id, &user.id).await? {
        return error("student is not in your class", 403);
    }
    crate::db::class_blacklist::add(&db, &class_id, student_id, &user.id).await?;
    crate::db::class_memberships::leave(&db, student_id).await?;
    Response::from_json(&serde_json::json!({"ok":true,"blacklisted":true}))
}

pub(super) async fn list_blacklist(
    request: &Request,
    env: &Env,
    class_id: &str,
) -> Result<Response> {
    let Some(user) = current_account(request, env).await? else {
        return error("unauthorized", 401);
    };
    if user.role != "class_admin" {
        return error("forbidden", 403);
    }
    let db = env.d1("DB")?;
    if !crate::db::classes::exists_for_admin(&db, class_id, &user.id).await? {
        return error("class not found", 404);
    }
    let students = crate::db::class_blacklist::list_for_class(&db, class_id).await?;
    Response::from_json(&serde_json::json!({"students":students}))
}

pub(super) async fn unblacklist(
    request: &Request,
    env: &Env,
    class_id: &str,
    student_id: &str,
) -> Result<Response> {
    let Some(user) = current_account(request, env).await? else {
        return error("unauthorized", 401);
    };
    if user.role != "class_admin" {
        return error("forbidden", 403);
    }
    let db = env.d1("DB")?;
    if !crate::db::classes::exists_for_admin(&db, class_id, &user.id).await? {
        return error("class not found", 404);
    }
    crate::db::class_blacklist::remove(&db, class_id, student_id).await?;
    Response::from_json(&serde_json::json!({"ok":true}))
}
