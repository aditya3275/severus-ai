from storage import get_connection
from utils.logger import setup_logger

logger = setup_logger("chat")


# =========================
# CHAT CRUD
# =========================


def create_chat(username: str, title="New Chat"):
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO chats (username, title) VALUES (?, ?)",
        (username, title),
    )
    chat_id = cur.lastrowid
    conn.commit()
    conn.close()
    logger.info(f"Chat created: {chat_id} for {username}")
    return chat_id


def get_user_chats(username: str):
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(
        "SELECT id, title FROM chats WHERE username = ? ORDER BY created_at DESC",
        (username,),
    )
    rows = cur.fetchall()
    conn.close()
    return rows


def get_messages(chat_id: int):
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(
        "SELECT role, content FROM messages WHERE chat_id = ? ORDER BY timestamp",
        (chat_id,),
    )
    rows = cur.fetchall()
    conn.close()
    return rows


def save_message(chat_id: int, role: str, content: str):
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO messages (chat_id, role, content) VALUES (?, ?, ?)",
        (chat_id, role, content),
    )
    conn.commit()
    conn.close()


def rename_chat(chat_id: int, new_title: str):
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(
        "UPDATE chats SET title = ? WHERE id = ?",
        (new_title, chat_id),
    )
    conn.commit()
    conn.close()
    logger.info(f"Chat renamed: {chat_id} -> {new_title}")


def delete_chat(chat_id: int):
    conn = get_connection()
    cur = conn.cursor()

    # delete messages
    cur.execute("DELETE FROM messages WHERE chat_id = ?", (chat_id,))

    # delete files
    cur.execute("DELETE FROM chat_files WHERE chat_id = ?", (chat_id,))

    # delete chat
    cur.execute("DELETE FROM chats WHERE id = ?", (chat_id,))

    conn.commit()
    conn.close()
    logger.info(f"Chat deleted: {chat_id}")


# =========================
# FILES
# =========================


def add_file_record(chat_id: int, filename: str, filepath: str):
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO chat_files (chat_id, filename, filepath) VALUES (?, ?, ?)",
        (chat_id, filename, filepath),
    )
    conn.commit()
    conn.close()


def get_files_for_chat(chat_id: int):
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(
        "SELECT filename, filepath FROM chat_files WHERE chat_id = ?",
        (chat_id,),
    )
    rows = cur.fetchall()
    conn.close()
    return rows
