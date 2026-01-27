from pathlib import Path


from file_text_extractor import extract_text_from_file

UPLOAD_BASE = Path("data/uploads")

MAX_FILE_SIZE_MB = 5  # option 2


def save_uploaded_file(chat_id: int, uploaded_file):
    chat_dir = UPLOAD_BASE / str(chat_id)
    chat_dir.mkdir(parents=True, exist_ok=True)

    file_path = chat_dir / uploaded_file.name

    # 🚀 FAST upload (NO chunking, NO blocking)
    with open(file_path, "wb") as f:
        f.write(uploaded_file.getbuffer())

    return file_path


def ensure_extracted_text(chat_id: int):
    """
    Extract document text ONLY ON DEMAND.
    Runs once per chat.
    """

    chat_dir = UPLOAD_BASE / str(chat_id)
    extracted_file = chat_dir / "extracted_text.txt"

    # ✅ Already extracted → DO NOTHING
    if extracted_file.exists() and extracted_file.stat().st_size > 0:
        return extracted_file

    extracted_file.parent.mkdir(parents=True, exist_ok=True)

    with open(extracted_file, "w", encoding="utf-8") as out:
        for f in chat_dir.iterdir():
            if f.name == "extracted_text.txt":
                continue
            if not f.is_file():
                continue

            # 🚫 Skip images
            if f.suffix.lower() in [".png", ".jpg", ".jpeg"]:
                continue

            # 🚫 Large file guard (Option 2)
            size_mb = f.stat().st_size / (1024 * 1024)
            if size_mb > MAX_FILE_SIZE_MB:
                out.write(
                    f"\n\n⚠️ FILE SKIPPED (too large: {size_mb:.2f} MB): {f.name}\n"
                )
                continue

            raw_text = extract_text_from_file(str(f))
            if not raw_text:
                continue

            cleaned = raw_text.encode("utf-8", errors="ignore").decode("utf-8")

            out.write("\n\n========== FILE START ==========\n")
            out.write(cleaned)
            out.write("\n=========== FILE END ===========\n")

    return extracted_file
