import httpx
from starlette.applications import Starlette
from starlette.requests import Request
from starlette.responses import PlainTextResponse, StreamingResponse
from starlette.routing import Route

OLLAMA_URL = "http://127.0.0.1:11434/api/generate"

async def llmprompt(request: Request):
    body = await request.json()

    model = body.get("model")
    prompt = body.get("prompt")
    stream = body.get("stream", True)

    if not isinstance(model, str) or not isinstance(prompt, str) or not isinstance(stream, bool):
        return PlainTextResponse("Bad Request", status_code=400)

    async def ndjson_stream():
        async with httpx.AsyncClient(timeout=None) as client:
            async with client.stream(
                "POST",
                OLLAMA_URL,
                json={"model": model, "prompt": prompt, "stream": stream},
                headers={"Content-Type": "application/json"},
            ) as r:
                r.raise_for_status()
                async for line in r.aiter_lines():
                    if line:
                        yield (line + "\n").encode("utf-8")

    return StreamingResponse(ndjson_stream(), media_type="application/x-ndjson")

app = Starlette(routes=[
    Route("/llmprompt", llmprompt, methods=["POST"]),
])

