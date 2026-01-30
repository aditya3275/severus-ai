import streamlit as st
from pathlib import Path

from utils.logger import setup_logger

# ✅ ADDED

from storage import init_db
from auth import signup, login
from chat import (
    create_chat,
    get_user_chats,
    get_messages,
    save_message,
    delete_chat,
    add_file_record,
)
from file_utils import save_uploaded_file, ensure_extracted_text
from utils.ollama_client import chat_with_model

# ======================================================
# LOGGER
# ======================================================
logger = setup_logger("app")  # ✅ ADDED
logger.info("Application starting")  # ✅ ADDED

# ======================================================
# APP CONFIG
# ======================================================
st.set_page_config(
    page_title="Severus AI",
    page_icon="🧠",
    layout="wide",
)

init_db()
logger.info("Database initialized")  # ✅ ADDED

# ======================================================
# SESSION STATE (MINIMAL & SAFE)
# ======================================================
st.session_state.setdefault("authenticated", False)
st.session_state.setdefault("username", None)
st.session_state.setdefault("chat_id", None)

st.session_state.setdefault("has_document", {})  # chat_id -> bool
st.session_state.setdefault("upload_notice", {})  # chat_id -> str | None
st.session_state.setdefault("files_to_process", None)  # TEMP buffer

# ======================================================
# HEADER
# ======================================================
st.markdown(
    """
    <div style="text-align:center; padding:10px 0 25px 0;">
        <h1>🧠 Severus AI</h1>
        <p style="color:gray;">Your personal local AI assistant</p>
    </div>
    """,
    unsafe_allow_html=True,
)

# ======================================================
# AUTH
# ======================================================
if not st.session_state.authenticated:
    col1, col2, col3 = st.columns([1, 2, 1])
    with col2:
        tab1, tab2 = st.tabs(["🔐 Login", "🆕 Sign Up"])

        with tab1:
            u = st.text_input("Username")
            p = st.text_input("Password", type="password")
            if st.button("Login", use_container_width=True):
                if login(u, p):
                    logger.info(f"User logged in: {u}")  # ✅ ADDED
                    st.session_state.authenticated = True
                    st.session_state.username = u
                    st.rerun()
                else:
                    logger.warning(f"Failed login attempt: {u}")  # ✅ ADDED
                    st.error("Invalid credentials")

        with tab2:
            u = st.text_input("New Username")
            p = st.text_input("New Password", type="password")
            if st.button("Create Account", use_container_width=True):
                if signup(u, p):
                    logger.info(f"User signed up: {u}")  # ✅ ADDED
                    st.success("Account created. Login now.")
                else:
                    logger.warning(f"Signup failed (username exists): {u}")  # ✅ ADDED
                    st.error("Username already exists")

# ======================================================
# MAIN APP
# ======================================================
else:
    # ---------------- SIDEBAR ----------------
    st.sidebar.markdown(f"👤 **{st.session_state.username}**")

    if st.sidebar.button("🚪 Logout", use_container_width=True):
        logger.info(f"User logged out: {st.session_state.username}")  # ✅ ADDED
        st.session_state.clear()
        st.rerun()

    st.sidebar.divider()
    st.sidebar.markdown("### 💬 Chats")

    chats = get_user_chats(st.session_state.username)

    if st.sidebar.button("➕ New Chat", use_container_width=True):
        cid = create_chat(st.session_state.username)
        logger.info(f"New chat created: chat_id={cid}")  # ✅ ADDED
        st.session_state.chat_id = cid
        st.session_state.has_document[cid] = False
        st.session_state.upload_notice[cid] = None
        st.rerun()

    for cid, title in chats:
        c1, c2 = st.sidebar.columns([5, 1])
        if c1.button(title, key=f"open_{cid}", use_container_width=True):
            logger.info(f"Chat opened: chat_id={cid}")  # ✅ ADDED
            st.session_state.chat_id = cid
            st.rerun()
        if c2.button("🗑️", key=f"del_{cid}"):
            logger.info(f"Chat deleted: chat_id={cid}")  # ✅ ADDED
            delete_chat(cid)
            st.session_state.has_document.pop(cid, None)
            st.session_state.upload_notice.pop(cid, None)
            if st.session_state.chat_id == cid:
                st.session_state.chat_id = None
            st.rerun()

    if not st.session_state.chat_id:
        st.info("👈 Create or select a chat to begin.")
        st.stop()

    chat_id = st.session_state.chat_id
    st.session_state.has_document.setdefault(chat_id, False)
    st.session_state.upload_notice.setdefault(chat_id, None)

    # ======================================================
    # FILE UPLOAD (ZERO PROCESSING HERE)
    # ======================================================
    st.sidebar.divider()
    st.sidebar.markdown("### 📂 Upload Files")

    file_type = st.sidebar.selectbox(
        "File type",
        ["PDF", "CSV", "Excel", "Image", "Other"],
    )

    allowed = {
        "PDF": ["pdf"],
        "CSV": ["csv"],
        "Excel": ["xlsx", "xls"],
        "Image": ["png", "jpg", "jpeg"],
        "Other": ["txt", "py", "js", "md"],
    }[file_type]

    uploaded_files = st.sidebar.file_uploader(
        "Choose files",
        type=allowed,
        accept_multiple_files=True,
        key="uploader",
    )

    if st.sidebar.button("⬆️ Confirm Upload"):
        if uploaded_files:
            logger.info(
                f"Files confirmed for upload: {[f.name for f in uploaded_files]} (chat_id={chat_id})"
            )  # ✅ ADDED
            st.session_state.files_to_process = uploaded_files

    # ======================================================
    # PROCESS FILES (RUNS ONCE, SAFE)
    # ======================================================
    files = st.session_state.pop("files_to_process", None)

    if files:
        for f in files:
            save_uploaded_file(chat_id, f)
            add_file_record(chat_id, f.name, f"data/uploads/{chat_id}/{f.name}")
            logger.info(f"File uploaded: {f.name} (chat_id={chat_id})")  # ✅ ADDED

            if f.name.lower().endswith(("png", "jpg", "jpeg")):
                st.session_state.upload_notice[chat_id] = "image"
            else:
                st.session_state.has_document[chat_id] = True
                st.session_state.upload_notice[chat_id] = "document"

        st.rerun()

    # ======================================================
    # UPLOAD NOTICE (ONCE)
    # ======================================================
    notice = st.session_state.upload_notice.get(chat_id)
    if notice:
        msg = (
            "🖼️ **Image uploaded successfully.**\n\nAsk anything about it."
            if notice == "image"
            else "📄 **Document uploaded successfully.**\n\nClick **Summarize Uploaded Document**."
        )
        save_message(chat_id, "assistant", msg)
        st.session_state.upload_notice[chat_id] = None
        st.rerun()

    # ======================================================
    # CHAT WINDOW
    # ======================================================
    messages = get_messages(chat_id)

    if st.session_state.has_document.get(chat_id):
        if st.button("📄 Summarize Uploaded Document", use_container_width=True):
            logger.info(
                f"Document summarization requested (chat_id={chat_id})"
            )  # ✅ ADDED
            with st.spinner("Reading and summarizing document..."):
                ensure_extracted_text(chat_id)

                prompt = "Summarize the uploaded document clearly and concisely."
                save_message(chat_id, "user", prompt)

                reply = chat_with_model(
                    "gemma3:1b",
                    get_messages(chat_id) + [("user", prompt)],
                    chat_id=chat_id,
                )

                save_message(chat_id, "assistant", reply)

            st.rerun()

    for role, content in messages:
        with st.chat_message(role):
            st.markdown(content)

    user_input = st.chat_input("Ask something...")

    if user_input:
        logger.info(f"User message sent (chat_id={chat_id})")  # ✅ ADDED
        save_message(chat_id, "user", user_input)

        reply = chat_with_model(
            "gemma3:1b",
            get_messages(chat_id) + [("user", user_input)],
            chat_id=chat_id,
        )

        save_message(chat_id, "assistant", reply)
        st.rerun()
