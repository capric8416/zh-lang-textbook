use serde::{Deserialize, Serialize};
use worker::{D1Database, Result};

#[derive(Deserialize, Serialize)]
#[serde(rename_all(serialize = "camelCase", deserialize = "snake_case"))]
pub(crate) struct PracticeRecord {
    pub(crate) id: String,
    pub(crate) student_id: String,
    pub(crate) class_id: String,
    pub(crate) textbook_key: String,
    pub(crate) question_id: String,
    pub(crate) chapter_id: String,
    pub(crate) question_kind: String,
    pub(crate) category: String,
    pub(crate) source: String,
    pub(crate) direction: String,
    pub(crate) prompt: String,
    pub(crate) student_answer: String,
    pub(crate) expected_answer: String,
    pub(crate) is_correct: i64,
    pub(crate) occurred_at: String,
    pub(crate) created_at: String,
}

#[derive(Deserialize, Serialize)]
#[serde(rename_all(serialize = "camelCase", deserialize = "snake_case"))]
pub(crate) struct ClassPracticeRecord {
    pub(crate) id: String,
    pub(crate) student_id: String,
    pub(crate) class_id: String,
    pub(crate) textbook_key: String,
    pub(crate) question_id: String,
    pub(crate) chapter_id: String,
    pub(crate) question_kind: String,
    pub(crate) category: String,
    pub(crate) source: String,
    pub(crate) direction: String,
    pub(crate) prompt: String,
    pub(crate) student_answer: String,
    pub(crate) expected_answer: String,
    pub(crate) is_correct: i64,
    pub(crate) occurred_at: String,
    pub(crate) created_at: String,
    pub(crate) username: String,
    pub(crate) display_name: String,
}

pub(crate) async fn insert(
    db: &D1Database,
    record: &PracticeRecord,
    student_id: &str,
    class_id: &str,
) -> Result<()> {
    db.prepare("INSERT INTO practice_records(id,student_id,class_id,textbook_key,question_id,chapter_id,question_kind,category,source,direction,prompt,student_answer,expected_answer,is_correct,occurred_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO NOTHING")
        .bind(&[
            record.id.clone().into(), student_id.into(), class_id.into(),
            record.textbook_key.clone().into(), record.question_id.clone().into(),
            record.chapter_id.clone().into(), record.question_kind.clone().into(),
            record.category.clone().into(), record.source.clone().into(),
            record.direction.clone().into(), record.prompt.clone().into(),
            record.student_answer.clone().into(),
            record.expected_answer.clone().into(), (record.is_correct as f64).into(),
            record.occurred_at.clone().into(),
        ])?
        .run()
        .await?;
    Ok(())
}

pub(crate) async fn list_for_class_page(
    db: &D1Database,
    class_id: &str,
    limit: u32,
    offset: u32,
) -> Result<Vec<ClassPracticeRecord>> {
    db.prepare("SELECT p.id,p.student_id,p.class_id,p.textbook_key,p.question_id,p.chapter_id,p.question_kind,p.category,p.source,p.direction,p.prompt,p.student_answer,p.expected_answer,p.is_correct,p.occurred_at,p.created_at,a.username,a.display_name FROM practice_records p JOIN accounts a ON a.id=p.student_id WHERE p.class_id=? ORDER BY p.occurred_at DESC,p.id LIMIT ? OFFSET ?")
        .bind(&[class_id.into(), (limit as f64).into(), (offset as f64).into()])?
        .all()
        .await?
        .results::<ClassPracticeRecord>()
}

#[cfg(test)]
mod tests {
    use super::PracticeRecord;

    #[test]
    fn maps_practice_record_columns_to_api_json() {
        let record: PracticeRecord = serde_json::from_str(
            r#"{"id":"attempt-1","student_id":"student-1","class_id":"class-1","textbook_key":"grade2b","question_id":"q1","chapter_id":"c1","question_kind":"字词","category":"字","source":"第一课","direction":"writeHanzi","prompt":"xue2","student_answer":"雪","expected_answer":"学","is_correct":1,"occurred_at":"2026-10-13T01:23:45.000Z","created_at":"2026-10-13 01:23:45"}"#,
        )
        .unwrap();
        let response = serde_json::to_value(record).unwrap();

        assert_eq!(response["textbookKey"], "grade2b");
        assert_eq!(response["questionId"], "q1");
        assert_eq!(response["isCorrect"], 1);
        assert_eq!(response["studentAnswer"], "雪");
        assert_eq!(response["occurredAt"], "2026-10-13T01:23:45.000Z");
        assert_eq!(response["studentId"], "student-1");
        assert_eq!(response["classId"], "class-1");
        assert_eq!(response["createdAt"], "2026-10-13 01:23:45");
    }
}
