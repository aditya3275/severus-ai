from pathlib import Path
from pypdf import PdfReader
import pandas as pd


def extract_text_from_file(file_path: str) -> str:
    path = Path(file_path)
    suffix = path.suffix.lower()

    if suffix == ".pdf":
        return extract_pdf(path)

    elif suffix in [".csv"]:
        return extract_csv(path)

    elif suffix in [".xlsx", ".xls"]:
        return extract_excel(path)

    elif suffix in [".txt", ".py", ".js", ".md"]:
        return extract_text_file(path)

    else:
        return "Unsupported file type"


def extract_pdf(path: Path) -> str:
    reader = PdfReader(path)
    text = []
    for page in reader.pages:
        text.append(page.extract_text() or "")
    return "\n".join(text)


def extract_csv(path: Path) -> str:
    df = pd.read_csv(path)
    return df.to_string(index=False)


def extract_excel(path: Path) -> str:
    df = pd.read_excel(path)
    return df.to_string(index=False)


def extract_text_file(path: Path) -> str:
    return path.read_text(errors="ignore")
