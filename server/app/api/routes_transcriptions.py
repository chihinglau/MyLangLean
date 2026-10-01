"""Transcription jobs.

MVP runs ASR in an in-process background task (asyncio + thread executor).
The job service interface stays identical when swapped for Redis/RQ on a
GPU worker (see services/task_runner.py).
"""
import asyncio
import tempfile
import uuid
from dataclasses import dataclass

from fastapi import APIRouter, BackgroundTasks, HTTPException, UploadFile, status

from ..core import db
from ..core.deps import CurrentUser, Principal
from ..models import (
    SegmentOut,
    TranscriptionIn,
    TranscriptionJobOut,
    TranscriptOut,
    WordOut,
)
from ..services import asr as asr_service
from ..services.quota import charge
from ..services.translate import translate

router = APIRouter(prefix="/api/v1/transcriptions", tags=["transcriptions"])


@dataclass
class Job:
    id: str
    status: str = "queued"
    transcript: TranscriptOut | None = None
    billed_sec: int = 0
    error: str | None = None
    # idempotency: (user_id, client_key) -> job_id
    dedupe: tuple[str, str] | None = None


_jobs: dict[str, Job] = {}
_dedupe: dict[tuple[str, str], str] = {}


def _to_transcript(result: asr_service.AsrResult,
                   target_lang: str | None) -> TranscriptOut:
    translations: dict[int, str] = {}
    if target_lang:
        texts = [s.text for s in result.segments]
        for seg_id, text in zip(
            [s.id for s in result.segments],
            translate(texts, result.language, target_lang),
        ):
            translations[seg_id] = text

    return TranscriptOut(
        language=result.language,
        duration=result.duration,
        segments=[
            SegmentOut(
                id=s.id,
                start=s.start,
                end=s.end,
                text=s.text,
                translation=translations.get(s.id),
                words=[WordOut(w=w.w, s=w.s, e=w.e, p=w.p) for w in s.words],
            )
            for s in result.segments
        ],
    )


async def _run(job: Job, user_id: str, source: str, language: str,
               target_lang: str | None) -> None:
    job.status = "processing"
    try:
        loop = asyncio.get_running_loop()
        result = await loop.run_in_executor(
            None, asr_service.transcribe, source, language)
        duration_sec = max(1, round(result.duration))
        if db.get_user(user_id) is not None:
            charge(user_id, duration_sec)
        job.transcript = _to_transcript(result, target_lang)
        job.billed_sec = duration_sec
        job.status = "done"
    except HTTPException as exc:
        job.status = "error"
        job.error = str(exc.detail)
    except Exception as exc:  # noqa: BLE001 - surfaced to client polling
        job.status = "error"
        job.error = repr(exc)


def _create_job(principal: Principal, source: str, language: str,
                target_lang: str | None, client_key: str | None) -> Job:
    if client_key:
        existing = _dedupe.get((principal.user_id, client_key))
        if existing:
            return _jobs[existing]

    job = Job(id=uuid.uuid4().hex)
    job.dedupe = (principal.user_id, client_key) if client_key else None
    _jobs[job.id] = job
    if client_key:
        _dedupe[(principal.user_id, client_key)] = job.id

    asyncio.create_task(
        _run(job, principal.user_id, source, language, target_lang))
    return job


@router.post("", response_model=TranscriptionJobOut, status_code=202)
async def create_from_url(
    body: TranscriptionIn,
    principal: Principal = CurrentUser,
) -> TranscriptionJobOut:
    if not body.audio_url:
        raise HTTPException(status.HTTP_400_BAD_REQUEST,
                            "audio_url required (or use /upload)")
    job = _create_job(principal, body.audio_url, body.language,
                      body.target_lang, body.client_key)
    return TranscriptionJobOut(id=job.id, status=job.status)


@router.post("/upload", response_model=TranscriptionJobOut, status_code=202)
async def create_from_upload(
    background: BackgroundTasks,
    file: UploadFile,
    language: str = "en",
    target_lang: str | None = None,
    client_key: str | None = None,
    principal: Principal = CurrentUser,
) -> TranscriptionJobOut:
    suffix = ".m4a"
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    tmp.write(await file.read())
    tmp.close()
    job = _create_job(principal, tmp.name, language, target_lang, client_key)
    return TranscriptionJobOut(id=job.id, status=job.status)


@router.get("/{job_id}", response_model=TranscriptionJobOut)
def get_job(job_id: str, principal: Principal = CurrentUser) -> TranscriptionJobOut:
    job = _jobs.get(job_id)
    if job is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "任务不存在")
    return TranscriptionJobOut(
        id=job.id,
        status=job.status,
        transcript=job.transcript,
        billed_sec=job.billed_sec,
        error=job.error,
    )
