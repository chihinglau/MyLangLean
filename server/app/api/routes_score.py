from fastapi import APIRouter

from ..models import ScoreIn, ScoreOut
from ..services.scoring import score

router = APIRouter(prefix="/api/v1/score", tags=["score"])


@router.post("", response_model=ScoreOut)
def post_score(body: ScoreIn) -> ScoreOut:
    s = score(body.reference_duration_ms, body.attempt_duration_ms,
              body.pause_count)
    return ScoreOut(
        overall=s.overall,
        rhythm=s.rhythm,
        fluency=s.fluency,
        intonation=s.intonation,
        suggestions=s.suggestions,
    )
