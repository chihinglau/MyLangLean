"""当前账号资料与订阅同步。"""
from fastapi import APIRouter, HTTPException, Response, status

from ..core import db
from ..core.deps import CurrentUser, Principal
from ..models import AccountOut

router = APIRouter(prefix="/api/v1/me", tags=["me"])


@router.get("", response_model=AccountOut)
def get_me(principal: Principal = CurrentUser) -> AccountOut:
    user = db.get_user(principal.user_id)
    if user is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "登录已失效，请重新登录")
    return AccountOut(**db.account_out(user))


@router.get("/subscriptions")
def list_my_subscriptions(principal: Principal = CurrentUser) -> dict:
    items = [db.podcast_out(r)
             for r in db.list_subscription_podcasts(principal.user_id)]
    return {"items": items, "content_version": db.content_version()}


@router.put("/subscriptions/{podcast_id}", status_code=204)
def put_subscription(podcast_id: str,
                     principal: Principal = CurrentUser) -> Response:
    # 幂等订阅；目标不存在或已下架返回 404。
    result = db.add_subscription(principal.user_id, podcast_id)
    if result is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "播客不存在或已下架")
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.delete("/subscriptions/{podcast_id}", status_code=204)
def delete_subscription(podcast_id: str,
                        principal: Principal = CurrentUser) -> Response:
    # 幂等退订：无论此前是否订阅均 204。
    db.remove_subscription(principal.user_id, podcast_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
