from fastapi import APIRouter

from ..models import TranslateIn, TranslateOut
from ..services.translate import translate

router = APIRouter(prefix="/api/v1/translate", tags=["translate"])


@router.post("", response_model=TranslateOut)
def post_translate(body: TranslateIn) -> TranslateOut:
    result = translate(body.texts, body.language, body.target_lang)
    return TranslateOut(translations=result)
