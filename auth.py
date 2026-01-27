import csv
import hashlib
from pathlib import Path
from utils.logger import setup_logger

logger = setup_logger("auth")

USERS_FILE = Path("data/users.csv")
USERS_FILE.parent.mkdir(exist_ok=True)

FIELDNAMES = ["username", "password_hash"]


def hash_password(password: str) -> str:
    return hashlib.sha256(password.encode()).hexdigest()


def ensure_users_file():
    if not USERS_FILE.exists():
        with open(USERS_FILE, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=FIELDNAMES)
            writer.writeheader()


def read_users():
    ensure_users_file()
    with open(USERS_FILE, "r", newline="") as f:
        reader = csv.DictReader(f)
        if reader.fieldnames != FIELDNAMES:
            raise RuntimeError(
                f"Invalid users.csv format. Expected headers: {FIELDNAMES}"
            )
        return list(reader)


def signup(username: str, password: str) -> bool:
    users = read_users()
    for user in users:
        if user["username"] == username:
            return False

    with open(USERS_FILE, "a", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=FIELDNAMES)
        writer.writerow(
            {"username": username, "password_hash": hash_password(password)}
        )

    logger.info(f"User signed up: {username}")
    return True


def login(username: str, password: str) -> bool:
    users = read_users()
    for user in users:
        if user["username"] == username and user["password_hash"] == hash_password(
            password
        ):
            logger.info(f"User logged in: {username}")
            return True
    return False
