use super::auth::current_account;
use crate::*;
use serde::Deserialize;
use worker::{Env, Request, Response, Result};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct PracticeRecordInput {
    id: String,
    textbook_key: String,
    question_id: String,
    chapter_id: String,
    question_kind: String,
    category: String,
    source: String,
    direction: String,
    prompt: String,
    student_answer: String,
    expected_answer: String,
    is_correct: bool,
    occurred_at: String,
}

pub(super) async fn record(request: &mut Request, env: &Env) -> Result<Response> {
    let Some(student) = current_account(request, env).await? else {
        return error("unauthorized", 401);
    };
    if student.role != "student" {
        return error("only student accounts can upload practice records", 403);
    }
    let input: PracticeRecordInput = match read_json(request).await {
        Ok(value) => value,
        Err(_) => return error("invalid practice record", 400),
    };
    if !valid_input(&input) {
        return error("做题记录字段无效", 400);
    }
    let db = env.d1("DB")?;
    let class_id = crate::db::class_memberships::find_for_student(&db, &student.id)
        .await?
        .map(|class| class.id);
    let record = crate::db::practice_records::PracticeRecord {
        id: input.id,
        student_id: student.id.clone(),
        class_id: class_id.clone(),
        textbook_key: input.textbook_key,
        question_id: input.question_id,
        chapter_id: input.chapter_id,
        question_kind: input.question_kind,
        category: input.category,
        source: input.source,
        direction: input.direction,
        prompt: input.prompt,
        student_answer: input.student_answer,
        expected_answer: input.expected_answer,
        is_correct: if input.is_correct { 1 } else { 0 },
        occurred_at: input.occurred_at,
        created_at: String::new(),
    };
    crate::db::practice_records::insert(&db, &record, &student.id, class_id.as_deref()).await?;
    Response::from_json(&serde_json::json!({"ok":true,"classId":class_id}))
}

#[derive(Deserialize)]
struct RecordPage {
    offset: Option<u32>,
    limit: Option<u32>,
}

pub(super) async fn class_records(
    request: &Request,
    env: &Env,
    class_id: &str,
) -> Result<Response> {
    let Some(admin) = current_account(request, env).await? else {
        return error("unauthorized", 401);
    };
    if admin.role != "class_admin" {
        return error("forbidden", 403);
    }
    let db = env.d1("DB")?;
    if !crate::db::classes::exists_for_admin(&db, class_id, &admin.id).await? {
        return error("class not found", 404);
    }
    let page = request.query::<RecordPage>().unwrap_or(RecordPage {
        offset: None,
        limit: None,
    });
    let offset = page.offset.unwrap_or(0);
    let limit = page.limit.unwrap_or(500).clamp(1, 500);
    let records =
        crate::db::practice_records::list_for_class_page(&db, class_id, limit, offset).await?;
    Response::from_json(&serde_json::json!({"records":records,"offset":offset,"limit":limit}))
}

fn valid_input(input: &PracticeRecordInput) -> bool {
    let id_is_hex = input.id.len() == 32 && input.id.bytes().all(|byte| byte.is_ascii_hexdigit());
    let valid_text =
        |value: &str, max: usize| !value.trim().is_empty() && value.chars().count() <= max;
    id_is_hex
        && valid_text(&input.textbook_key, 128)
        && valid_text(&input.question_id, 256)
        && valid_text(&input.chapter_id, 128)
        && valid_text(&input.question_kind, 64)
        && valid_text(&input.category, 64)
        && valid_text(&input.source, 256)
        && valid_text(&input.prompt, 2000)
        && valid_text(&input.student_answer, 2000)
        && valid_text(&input.expected_answer, 2000)
        && valid_text(&input.occurred_at, 40)
        && matches!(
            input.direction.as_str(),
            "writeHanzi" | "writePinyin" | "listenWriteHanzi" | "readAloud"
        )
}

#[cfg(test)]
mod tests {
    use super::{valid_input, PracticeRecordInput};

    fn input() -> PracticeRecordInput {
        PracticeRecordInput {
            id: "0123456789abcdef0123456789abcdef".into(),
            textbook_key: "grade2b.json".into(),
            question_id: "poem:test".into(),
            chapter_id: "chapter-1".into(),
            question_kind: "诗词".into(),
            category: "诗词".into(),
            source: "静夜思".into(),
            direction: "writeHanzi".into(),
            prompt: "chuáng qián míng yuè guāng".into(),
            student_answer: "床前明月光".into(),
            expected_answer: "床前明月光".into(),
            is_correct: true,
            occurred_at: "2026-10-13T01:23:45.000Z".into(),
        }
    }

    #[test]
    fn accepts_valid_practice_attempt() {
        assert!(valid_input(&input()));
    }

    #[test]
    fn rejects_bad_id_or_direction() {
        let mut record = input();
        record.id = "not-an-id".into();
        assert!(!valid_input(&record));

        let mut record = input();
        record.direction = "admin".into();
        assert!(!valid_input(&record));
    }
}
