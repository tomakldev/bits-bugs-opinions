import contextlib

from fastapi import FastAPI

from license_check import verify_license_or_exit


@contextlib.asynccontextmanager
async def lifespan(app: FastAPI):
    # License check runs once at startup before the app accepts traffic.
    # If it fails, the process exits — nothing is served.
    verify_license_or_exit()
    yield


app = FastAPI(lifespan=lifespan)


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/api/hello")
async def hello():
    return {"message": "Hello from the backend"}
